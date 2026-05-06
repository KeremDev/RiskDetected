/**
 * analyze — RiskDetected Edge Function (Gemini-first, schema-aligned)
 *
 * POST body:
 *   analysis_id  : string (UUID)
 *   canvas       : string (primary canvas id, single-value enum)
 *   canvases     : string[] (all selected — for future multi-canvas backend)
 *   text_input   : string | null
 *   photo_paths  : string[] (Storage paths in "photos" bucket)
 *   photo_base64_parts: { mime_type: string; data: string; width?: number; height?: number }[] (inline photos)
 *
 * Schema notes (v4):
 *   - profiles.tier        enum: free | pro
 *   - analyses.status      enum: pending | analyzing | completed | failed
 *   - analyses.canvas      enum: general | ppe | mark | sector | urgent | procedure
 *   - findings.fk_score    GENERATED — DO NOT INSERT
 *   - findings.m5_score    GENERATED — DO NOT INSERT
 *   - findings.user_id     REQUIRED
 *   - fk_band / m5_band    enum: critical | high | medium | low | unknown
 *   - fk_probability check: [0.2, 0.5, 1, 3, 6, 10]
 *   - fk_frequency   check: [0.5, 1, 2, 3, 6, 10]
 *   - fk_severity    check: [1, 3, 7, 15, 40, 100]
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

const MODEL_FREE_LITE = "gemini-2.5-flash-lite";
const MODEL_FREE      = "gemini-2.5-flash";
// Gemini Pro model free quota bu API key'de 0 dönebiliyor.
// Ücretli Google AI planı açılana kadar PRO kullanıcıyı da Flash üzerinde çalıştırıyoruz.
const MODEL_PRO       = "gemini-2.5-flash";
const FREE_DAILY_LIMIT = 2;

const CANVAS_FOCUS: Record<string, string> = {
  general:   "Tüm iş güvenliği uygunsuzluklarını geniş kapsamlı tara.",
  ppe:       "Baret, gözlük, eldiven, emniyet kemeri ve yelek (KKD) kontrolüne odaklan.",
  mark:      "Yalnızca fotoğraf üzerinde işaretlenmiş alanları analiz et.",
  sector:    "İnşaat, üretim, depo veya ofis bağlamına göre sektöre özgü risklere odaklan.",
  urgent:    "Yalnızca kritik ve yüksek seviye anlık riskleri öne çıkar.",
  procedure: "Standart İSG prosedürlerine uyumsuzlukları tespit et.",
};

// DB constraint ile birebir uyumlu Fine-Kinney ölçekleri
const FK_PROBABILITY_VALUES = [0.2, 0.5, 1, 3, 6, 10];
const FK_FREQUENCY_VALUES   = [0.5, 1, 2, 3, 6, 10];
const FK_SEVERITY_VALUES    = [1, 3, 7, 15, 40, 100];

function clampFK(value: number, allowed: number[]): number {
  return allowed.reduce((prev, curr) =>
    Math.abs(curr - value) < Math.abs(prev - value) ? curr : prev
  );
}

// Fine-Kinney skor → risk_level enum
function fkBand(score: number): "low" | "medium" | "high" | "critical" {
  if (score < 70)  return "low";
  if (score < 200) return "medium";
  if (score < 400) return "high";
  return "critical";
}

// 5×5 skor → risk_level enum
function m5Band(score: number): "low" | "medium" | "high" | "critical" {
  if (score <= 4)  return "low";
  if (score <= 9)  return "medium";
  if (score <= 16) return "high";
  return "critical";
}

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    hazards: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          title:              { type: "STRING" },
          category:           { type: "STRING" },
          observed_evidence:  { type: "STRING" },
          description:        { type: "STRING" },
          recommended_action: { type: "STRING" },
          references:         { type: "STRING" },
          confidence:         { type: "NUMBER" },
          fk_probability:     { type: "NUMBER" },
          fk_frequency:       { type: "NUMBER" },
          fk_severity:        { type: "NUMBER" },
          m5_probability:     { type: "NUMBER" },
          m5_severity:        { type: "NUMBER" },
        },
        required: [
          "title", "category", "observed_evidence", "description",
          "recommended_action", "confidence",
          "fk_probability", "fk_frequency", "fk_severity",
          "m5_probability", "m5_severity",
        ],
      },
    },
    ai_summary:  { type: "STRING" },
    limitations: { type: "STRING" },
  },
  required: ["hazards", "ai_summary"],
};

class GeminiAPIError extends Error {
  status: number;
  body: string;

  constructor(status: number, body: string) {
    super(`Gemini HTTP ${status}: ${body}`);
    this.status = status;
    this.body = body;
  }
}

function buildSystemPrompt(canvases: string[], isPro: boolean): string {
  const maxHazards = isPro ? 14 : 4;
  const focusLines = canvases.map((c) => CANVAS_FOCUS[c]).filter(Boolean).join(" ") || CANVAS_FOCUS["general"];
  return `Sen deneyimli bir iş güvenliği (HSE/İSG) uzmanısın. Görevin: verilen görsel ve/veya metin girdisinden İSG tehlikelerini ve risklerini tespit etmek.

ODAK: ${focusLines}

KURALLAR:
- Yalnızca fotoğrafta/metinde GÖZLEMLENEN kanıtlara dayan. Tahmin etme.
- Emin olmadığın noktalar için confidence değerini düşür (0.3–0.6).
- En fazla ${maxHazards} tehlike döndür; önem sırasına göre sırala.
- Her tehlike için Fine-Kinney girdilerini (fk_probability, fk_frequency, fk_severity) ve 5×5 girdilerini (m5_probability 1-5, m5_severity 1-5) öner.
- Fine-Kinney ihtimal değerleri (sadece bunlar): 0.2 / 0.5 / 1 / 3 / 6 / 10
- Fine-Kinney frekans değerleri (sadece bunlar): 0.5 / 1 / 2 / 3 / 6 / 10
- Fine-Kinney şiddet değerleri (sadece bunlar): 1 / 3 / 7 / 15 / 40 / 100
- Skorları hesaplama — yalnızca ham girdileri ver; sistem hesaplar.
- Türkçe yanıt ver.
- Yalnızca JSON döndür.`;
}

async function callGemini(
  apiKey: string,
  model: string,
  systemPrompt: string,
  userText: string | null,
  imageBase64Parts: { mimeType: string; data: string }[],
) {
  const parts: unknown[] = [];
  for (const img of imageBase64Parts) {
    parts.push({ inlineData: { mimeType: img.mimeType, data: img.data } });
  }
  if (userText) {
    parts.push({ text: `Kullanıcı notu: ${userText}` });
  } else if (imageBase64Parts.length === 0) {
    throw new Error("En az bir fotoğraf veya metin girdisi gerekli.");
  }

  const body = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: "user", parts }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
      temperature: 0.2,
      maxOutputTokens: 8192,
    },
  };

  const url = `${GEMINI_API_BASE}/${model}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new GeminiAPIError(res.status, errText);
  }

  const json = await res.json();
  const candidate = json.candidates?.[0];
  if (!candidate) throw new Error("Gemini yanıt boş.");
  const text = candidate.content?.parts?.[0]?.text;
  if (!text) throw new Error("Gemini yanıtında metin yok.");

  return {
    result: JSON.parse(text),
    inputTokens:  json.usageMetadata?.promptTokenCount     ?? 0,
    outputTokens: json.usageMetadata?.candidatesTokenCount ?? 0,
  };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function userFacingAIError(err: unknown): { status: number; message: string } {
  if (err instanceof GeminiAPIError) {
    if (err.status === 429) {
      return {
        status: 429,
        message: "Gemini kotası doldu. Google AI kullanım limitini veya faturalandırma planını kontrol etmek gerekiyor.",
      };
    }
    if (err.status === 503) {
      return {
        status: 503,
        message: "Gemini modeli şu anda yoğun. Biraz sonra tekrar dene.",
      };
    }
    return {
      status: 502,
      message: `Gemini servis hatası (${err.status}).`,
    };
  }

  return {
    status: 502,
    message: "AI analizi tamamlanamadı. Lütfen tekrar dene.",
  };
}

async function callGeminiWithFallback(
  apiKey: string,
  preferredModel: string,
  systemPrompt: string,
  userText: string | null,
  imageBase64Parts: { mimeType: string; data: string }[],
) {
  const models = preferredModel === MODEL_FREE_LITE
    ? [MODEL_FREE_LITE, MODEL_FREE]
    : [preferredModel, MODEL_FREE_LITE];

  let lastError: unknown = null;
  for (const model of [...new Set(models)]) {
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const out = await callGemini(apiKey, model, systemPrompt, userText, imageBase64Parts);
        return { ...out, modelUsed: model };
      } catch (err) {
        lastError = err;
        const retryable = err instanceof GeminiAPIError && [429, 500, 502, 503, 504].includes(err.status);
        console.error("Gemini attempt failed", JSON.stringify({
          model,
          attempt,
          retryable,
          error: String(err),
        }));
        if (!retryable) throw err;
        if (attempt < 2) await delay(900);
      }
    }
  }

  throw lastError ?? new Error("Gemini analizi başarısız.");
}

function errorResponse(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// deno-lint-ignore no-explicit-any
async function logUsage(supabase: any, data: any) {
  try { await supabase.from("ai_usage_logs").insert(data); }
  catch (e) { console.error("Usage log insert failed:", e); }
}

const BAND_RANK: Record<string, number> = { low: 0, medium: 1, high: 2, critical: 3 };

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin":  "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  const startMs = Date.now();

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiKey) return errorResponse(500, "GEMINI_API_KEY secret eksik.");

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return errorResponse(401, "Authorization header eksik.");

  // deno-lint-ignore no-explicit-any
  const { data: { user }, error: authErr } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (authErr || !user) return errorResponse(401, "Geçersiz token.");

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); }
  catch { return errorResponse(400, "Geçersiz JSON body."); }

  const { analysis_id, canvas, canvases, text_input, photo_paths = [], photo_base64_parts = [] } = body;
  if (!analysis_id) return errorResponse(400, "analysis_id zorunlu.");

  // Profil + tier
  const { data: profile } = await supabase
    .from("profiles")
    .select("tier")
    .eq("id", user.id)
    .single();
  const isPro = profile?.tier === "pro";

  // Quota (free)
  if (!isPro) {
    const today = new Date().toISOString().slice(0, 10);
    const { count } = await supabase
      .from("analyses")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("status", "completed")
      .gte("created_at", `${today}T00:00:00Z`);

    if ((count ?? 0) >= FREE_DAILY_LIMIT) {
      await supabase.from("analyses")
        .update({ status: "failed", status_message: `Günlük kota doldu (${FREE_DAILY_LIMIT}/gün).` })
        .eq("id", analysis_id);
      return errorResponse(429, `Günlük kota doldu (${FREE_DAILY_LIMIT} analiz/gün).`);
    }
  }

  // Status → analyzing
  await supabase.from("analyses")
    .update({ status: "analyzing", started_at: new Date().toISOString() })
    .eq("id", analysis_id);

  const model = isPro
    ? MODEL_PRO
    : (canvas === "urgent" || canvas === "procedure" ? MODEL_FREE : MODEL_FREE_LITE);

  // Storage → base64
  const imageBase64Parts: { mimeType: string; data: string }[] = [];
  const inlinePhotoCount = Array.isArray(photo_base64_parts) ? photo_base64_parts.length : 0;
  const storagePhotoCount = Array.isArray(photo_paths) ? photo_paths.length : 0;

  for (const part of photo_base64_parts) {
    if (!part?.data) continue;
    imageBase64Parts.push({
      mimeType: part.mime_type ?? part.mimeType ?? "image/jpeg",
      data: part.data,
    });
  }

  // Inline gelen fotoğrafları kalıcı olarak Storage + photos tablosuna yaz.
  // Client tarafında Storage RLS'e takılmamak için bu işi service role ile Edge Function yapıyor.
  const persistedPhotoPaths: string[] = [];
  if (Array.isArray(photo_base64_parts) && photo_base64_parts.length > 0) {
    await supabase.from("photos").delete().eq("analysis_id", analysis_id);

    for (let i = 0; i < photo_base64_parts.length; i++) {
      const part = photo_base64_parts[i];
      if (!part?.data) continue;

      const mimeType = part.mime_type ?? part.mimeType ?? "image/jpeg";
      const ext = mimeType.includes("png") ? "png" : "jpg";
      const storagePath = `${user.id}/${analysis_id}/p${i + 1}.${ext}`;
      const bytes = base64ToBytes(part.data);

      const { error: uploadErr } = await supabase.storage
        .from("photos")
        .upload(storagePath, new Blob([bytes], { type: mimeType }), {
          contentType: mimeType,
          upsert: true,
        });

      if (uploadErr) {
        console.error("Persist inline photo upload error:", uploadErr);
        continue;
      }

      const { error: photoErr } = await supabase.from("photos").insert({
        analysis_id,
        user_id: user.id,
        storage_path: storagePath,
        width: Number.isFinite(part.width) ? Math.round(part.width) : 0,
        height: Number.isFinite(part.height) ? Math.round(part.height) : 0,
        mime_type: mimeType,
      });

      if (photoErr) {
        console.error("Persist inline photo metadata error:", photoErr);
        continue;
      }

      persistedPhotoPaths.push(storagePath);
    }
  }

  for (const path of photo_paths) {
    const { data: fileData, error: storageErr } = await supabase.storage.from("photos").download(path);
    if (storageErr || !fileData) { console.error("Storage download error:", storageErr); continue; }
    const buffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    const base64 = btoa(binary);
    const mimeType = path.endsWith(".png") ? "image/png" : "image/jpeg";
    imageBase64Parts.push({ mimeType, data: base64 });
  }

  const systemPrompt = buildSystemPrompt(canvases ?? [canvas], isPro);
  const inputAudit = {
    input_mode: imageBase64Parts.length > 0 ? "photo" : "text",
    inline_photo_count: inlinePhotoCount,
    storage_photo_count: storagePhotoCount,
    persisted_photo_count: persistedPhotoPaths.length,
    gemini_image_part_count: imageBase64Parts.length,
    text_input_present: Boolean(text_input),
    model,
  };

  // deno-lint-ignore no-explicit-any
  let geminiResult: any;
  let inputTokens = 0, outputTokens = 0;
  let aiError: string | null = null;
  let modelUsed = model;

  try {
    const out = await callGeminiWithFallback(geminiKey, model, systemPrompt, text_input ?? null, imageBase64Parts);
    geminiResult = out.result;
    inputTokens = out.inputTokens;
    outputTokens = out.outputTokens;
    modelUsed = out.modelUsed;
    inputAudit.model = out.modelUsed;
  } catch (err) {
    aiError = String(err);
    const cleanError = userFacingAIError(err);
    await supabase.from("analyses")
      .update({ status: "failed", status_message: cleanError.message })
      .eq("id", analysis_id);
    await logUsage(supabase, {
      analysis_id, user_id: user.id, provider: "gemini", model,
      tokens_in: 0, tokens_out: 0,
      duration_ms: Date.now() - startMs, error: aiError, user_plan: isPro ? "pro" : "free",
    });
    return errorResponse(cleanError.status, cleanError.message);
  }

  const hazards = geminiResult.hazards ?? [];
  let totalScoreFK = 0, totalScoreM5 = 0;
  let highestBandFK: "low" | "medium" | "high" | "critical" = "low";
  let highestBandM5: "low" | "medium" | "high" | "critical" = "low";

  // findings rows — fk_score / m5_score GENERATED, INSERT ETME.
  // user_id REQUIRED, set et.
  // deno-lint-ignore no-explicit-any
  const findingRows = hazards.map((h: any, i: number) => {
    const fkP = clampFK(h.fk_probability, FK_PROBABILITY_VALUES);
    const fkF = clampFK(h.fk_frequency,   FK_FREQUENCY_VALUES);
    const fkS = clampFK(h.fk_severity,    FK_SEVERITY_VALUES);
    const fkSc = fkP * fkF * fkS;
    const fkB  = fkBand(fkSc);
    const m5P  = Math.max(1, Math.min(5, Math.round(h.m5_probability)));
    const m5S  = Math.max(1, Math.min(5, Math.round(h.m5_severity)));
    const m5Sc = m5P * m5S;
    const m5B  = m5Band(m5Sc);
    totalScoreFK += fkSc;
    totalScoreM5 += m5Sc;
    if (BAND_RANK[fkB] > BAND_RANK[highestBandFK]) highestBandFK = fkB;
    if (BAND_RANK[m5B] > BAND_RANK[highestBandM5]) highestBandM5 = m5B;
    return {
      analysis_id,
      user_id:           user.id,
      ordinal:           i + 1,
      title:             h.title,
      category:          h.category ?? "",
      description:       `${h.observed_evidence}\n\n${h.description}`.trim(),
      recommended_action: h.recommended_action,
      references_text:   h.references ?? "",
      confidence:        Math.max(0, Math.min(1, h.confidence)),
      fk_probability:    fkP,
      fk_frequency:      fkF,
      fk_severity:       fkS,
      fk_band:           fkB,
      m5_probability:    m5P,
      m5_severity:       m5S,
      m5_band:           m5B,
    };
  });

  if (findingRows.length > 0) {
    const { error: findingsErr } = await supabase.from("findings").insert(findingRows);
    if (findingsErr) {
      console.error("Findings insert error:", findingsErr);
      await supabase.from("analyses")
        .update({ status: "failed", status_message: `Findings DB hatası: ${findingsErr.message}` })
        .eq("id", analysis_id);
      return errorResponse(500, `DB hatası: ${findingsErr.message}`);
    }
  }

  await supabase.from("analyses").update({
    status:           "completed",
    status_message:   `Gemini ${modelUsed} · ${imageBase64Parts.length} foto · ${text_input ? "metin var" : "metin yok"}`,
    completed_at:     new Date().toISOString(),
    ai_summary:       geminiResult.ai_summary,
    total_score_fk:   totalScoreFK,
    total_score_m5:   totalScoreM5,
    highest_band_fk:  highestBandFK,
    highest_band_m5:  highestBandM5,
    finding_count:    findingRows.length,
    raw_ai_response:  { ...geminiResult, _input_audit: inputAudit },
    ai_models_used:   [modelUsed],
  }).eq("id", analysis_id);

  await logUsage(supabase, {
    analysis_id, user_id: user.id, provider: "gemini", model: modelUsed,
    tokens_in: inputTokens, tokens_out: outputTokens,
    duration_ms: Date.now() - startMs, error: null, user_plan: isPro ? "pro" : "free",
  });

  return new Response(
    JSON.stringify({ ok: true, finding_count: findingRows.length }),
    { headers: { "Content-Type": "application/json" } },
  );
});
