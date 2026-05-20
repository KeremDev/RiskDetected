// deno-lint-ignore-file no-explicit-any no-import-prefix
/**
 * gemini-free-qa-run — admin-only QA runner for testing the current Free
 * Gemini hierarchy/prompt against an existing analysis photo without writing
 * analyses/findings/usage rows or consuming quota.
 *
 * POST body:
 *   analysis_id: string
 *
 * Security:
 *   Requires `x-qa-secret` to match `AI_QA_SECRET` or `GROQ_QA_SECRET`.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";
const PHOTOS_BUCKET = "photos";
const MAX_ANALYSIS_PHOTOS = 5;

const MODEL_FLASH_LITE = "gemini-3.1-flash-lite";
const MODEL_FREE = "gemini-2.5-flash";
const MODEL_FREE_FALLBACK = MODEL_FLASH_LITE;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-qa-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const FK_PROBABILITY_VALUES = [0.2, 0.5, 1, 3, 6, 10];
const FK_FREQUENCY_VALUES = [0.5, 1, 2, 3, 6, 10];
const FK_SEVERITY_VALUES = [1, 3, 7, 15, 40, 100];

const FREE_ANALYSIS_PROMPT =
  `Sen Türkiye'de 20 yıllık saha deneyimi olan kıdemli bir İSG uzmanısın (A sınıfı). İnşaat, üretim, depo/lojistik, enerji,fabrika ve ofis sahalarında binlerce denetim yapmış, ölümcül kazaları önlemiş, mevzuata hâkim bir profesyonelsin.

GÖREV: Sana verilen görsel veya metin girdisinden, sahada fiziksel olarak bulunan bir denetçinin yakalayacağı tüm İSG tehlikelerini sistematik olarak tespit et ve raporla.

TARAMA PROSEDÜRÜ — Her görseli SIRAYLA şu 6 katmanda tara:
1. ZEMİN VE SAHA DÜZENİ: ıslaklık, çamur, su birikintisi, boşluk, kot farkı, dağınık malzeme, kablo, hortum, kayma/takılma zeminleri.
2. ÇALIŞAN(LAR) VE KKD: baret, gözlük, eldiven, ayakkabı, yelek, emniyet kemeri, maske; duruş ve manuel taşıma ergonomisi.
3. YÜKSEKTE ÇALIŞMA: kenar koruması, korkuluk, iskele bütünlüğü, merdiven açısı, platform, yaşam hattı, ankraj, açık kenar, boşluk, düşen cisim tehlikesi.
4. ELEKTRİK VE ENERJİ: kablo, pano, fiş, jeneratör, su+elektrik teması, topraklama, geçici tesisat.
5. MAKİNE, EKİPMAN VE KİMYASAL: hareketli parça, koruma, kaldırma ekipmanı, varil/şişe, etiketleme, depolama, yangın yükü.
6. ÇEVRE VE ACİL DURUM: işaretleme, acil çıkış, yangın söndürücü, ilk yardım görünürlüğü, trafik, üst yapı, hava koşulu.
7. EĞİTİM : Personelin ilgili mevzuat eğitimleri, yada işe özgü özel eğitimleri sorgulanmalı.Mesleki yeterlilik belgesi sorgulanmalı.

Her katmanı gözden geçir; bir katmanda risk yoksa atla, ama tarama atlama.

ÇIKTI HEDEFİ:
- 6 ile 9 arasında bulgu döndür. Daha azı eksik, daha fazlası odak dağıtır.
- ÖLÜMCÜL POTANSİYELİ olan bulgular (düşme, elektrik, ezilme, kimyasal, düşen cisim) en üstte.
- Sonra yüksek frekanslı bulgular (zemin, ergonomi, KKD,eğitim,belge).
- En altta düşük etkili ama mevzuat ihlali olan bulgular.

RİSK PUANLAMA KALİBRASYONU — Fine-Kinney ŞİDDET:
- 100 = Birden fazla ölüm veya kalıcı çevre felaketi.
- 40  = Tek ölüm veya kalıcı iş göremezlik (elektrik çarpması, korumasız 3m+ düşme).
- 15  = Ağır yaralanma, uzun süreli iş göremezlik (kırık, ciddi kesi).
- 7   = Önemli yaralanma, kısa süreli iş göremezlik (burkulma, dikiş).
- 3   = Hafif yaralanma, ilk yardım yeterli.
- 1   = Çok hafif, etkisiz.

5×5 ŞİDDET, Fine-Kinney ile uyumlu:
- FK Ş ≥ 40 → m5_severity = 5
- FK Ş = 15 → m5_severity = 4
- FK Ş = 7  → m5_severity = 3
- FK Ş = 3  → m5_severity = 2
- FK Ş = 1  → m5_severity = 1

KRİTİK KURAL: 2m+ yükseklikte koruma yoksa Ş değeri ASLA 40'ın altına düşmesin; m5_severity = 5 olmalı. Bu Türkiye'de en sık ölümlü iş kazası nedenidir.

CONFIDENCE:
- 0.90-0.98: net, tartışmasız kanıt.
- 0.70-0.89: güçlü kanıt, bazı detaylar belirsiz.
- 0.50-0.69: ipucu var, kesin değil.
- 0.30-0.49: sadece bağlamsal şüphe.
- < 0.30: bulguyu döndürme.
Confidence < 0.50 ise description sonuna "(sahada doğrulanmalı)" ekle.

KALİTE FİLTRESİ — KAÇIN:
- Genel ifade ("güvenlik önlemleri alınmalı") yerine somut teknik aksiyon yaz.
- Görselde olmayan riski uydurma.
- Aynı kök nedenli riskleri tek bulguda topla.
- Hassas ölçü uydurma; "yaklaşık 3m" veya "1 kat yüksekliğinde" yaz.
- "Eğitim verilmeli" jenerik aksiyonundan kaçın; spesifik ne yapılacağını söyle.

ÖRNEK BULGU (kopyalama, sadece kalite referansı):
{
  "title": "Açık kenar — düşmeyi önleyici korkuluk eksikliği",
  "category": "Yüksekte Çalışma",
  "description": "Üst katın doğu kenarında korkuluk yok; çalışan kenara yakın malzeme taşıyor. Yaklaşık 4m yükseklikten ölümcül düşme potansiyeli.",
  "recommended_action": "Tüm açık kenarlara TS EN 13374 uyumlu korkuluk kur; korkuluk takılana kadar bölgeye giriş kısıtlansın.",
  "confidence": 0.92,
  "fk_probability": 6,
  "fk_frequency": 6,
  "fk_severity": 100,
  "m5_probability": 5,
  "m5_severity": 5
}

ÇIKTI KURALLARI:
- Yalnızca JSON döndür; önünde/arkasında açıklama yazma.
- Tüm metin Türkçe.
- description max 200 karakter; recommended_action max 180 karakter.
- Skorları HESAPLAMA, ham girdileri ver — sistem hesaplar.
- Fine-Kinney ihtimal: 0.2 / 0.5 / 1 / 3 / 6 / 10
- Fine-Kinney frekans:  0.5 / 1 / 2 / 3 / 6 / 10
- Fine-Kinney şiddet:   1 / 3 / 7 / 15 / 40 / 100
- m5_probability: 1-5, m5_severity: 1-5`;

type ImagePart = {
  mimeType: string;
  data: string;
  byteSize: number;
  storagePath: string;
};

type GeminiKeyConfig = {
  alias: "gemini_primary" | "gemini_secondary";
  key: string;
  pool: "free";
};

class GeminiAPIError extends Error {
  status: number;
  body: string;

  constructor(status: number, body: string) {
    super(`Gemini HTTP ${status}`);
    this.status = status;
    this.body = body;
  }
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function cleanID(value: unknown): string {
  return String(value ?? "").trim();
}

function safeLogError(error: unknown): Record<string, unknown> {
  if (error instanceof GeminiAPIError) {
    return { name: "GeminiAPIError", status: error.status };
  }
  if (error instanceof SyntaxError) return { name: "SyntaxError" };
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message
        .replace(/key=[^&\s]+/gi, "key=[redacted]")
        .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
        .slice(0, 180),
    };
  }
  return { name: typeof error };
}

function base64FromBytes(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function normalizeMimeType(value: unknown): "image/jpeg" | "image/png" {
  const raw = String(value ?? "").toLowerCase();
  return raw.includes("png") ? "image/png" : "image/jpeg";
}

function responseSchema() {
  return {
    type: "OBJECT",
    properties: {
      hazards: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            title: { type: "STRING" },
            category: { type: "STRING" },
            observed_evidence: { type: "STRING" },
            description: { type: "STRING" },
            recommended_action: { type: "STRING" },
            confidence: { type: "NUMBER" },
            fk_probability: { type: "NUMBER" },
            fk_frequency: { type: "NUMBER" },
            fk_severity: { type: "NUMBER" },
            m5_probability: { type: "NUMBER" },
            m5_severity: { type: "NUMBER" },
          },
          required: [
            "title",
            "category",
            "observed_evidence",
            "description",
            "recommended_action",
            "confidence",
            "fk_probability",
            "fk_frequency",
            "fk_severity",
            "m5_probability",
            "m5_severity",
          ],
        },
      },
      ai_summary: { type: "STRING" },
      limitations: { type: "STRING" },
    },
    required: ["hazards", "ai_summary"],
  };
}

function thinkingConfig(model: string): Record<string, string> | null {
  return model === MODEL_FLASH_LITE ? { thinkingLevel: "medium" } : null;
}

function clampFK(value: unknown, allowed: number[]): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return allowed[0];
  return allowed.reduce((prev, curr) =>
    Math.abs(curr - numeric) < Math.abs(prev - numeric) ? curr : prev
  );
}

function fkBand(score: number): "low" | "medium" | "high" | "critical" {
  if (score < 70) return "low";
  if (score < 200) return "medium";
  if (score < 400) return "high";
  return "critical";
}

function m5Band(score: number): "low" | "medium" | "high" | "critical" {
  if (score <= 4) return "low";
  if (score <= 9) return "medium";
  if (score <= 16) return "high";
  return "critical";
}

function normalizedFindings(rawHazards: unknown) {
  const hazards = Array.isArray(rawHazards) ? rawHazards : [];
  let totalScoreFK = 0;
  let totalScoreM5 = 0;
  const findings = hazards.map((item, index) => {
    const h = item as Record<string, unknown>;
    const fkP = clampFK(h.fk_probability, FK_PROBABILITY_VALUES);
    const fkF = clampFK(h.fk_frequency, FK_FREQUENCY_VALUES);
    const fkS = clampFK(h.fk_severity, FK_SEVERITY_VALUES);
    const fkScore = fkP * fkF * fkS;
    const m5P = Math.max(1, Math.min(5, Math.round(Number(h.m5_probability))));
    const m5S = Math.max(1, Math.min(5, Math.round(Number(h.m5_severity))));
    const safeM5P = Number.isFinite(m5P) ? m5P : 1;
    const safeM5S = Number.isFinite(m5S) ? m5S : 1;
    const m5Score = safeM5P * safeM5S;
    totalScoreFK += fkScore;
    totalScoreM5 += m5Score;
    return {
      ordinal: index + 1,
      title: String(h.title ?? ""),
      category: String(h.category ?? ""),
      observed_evidence: String(h.observed_evidence ?? ""),
      description: String(h.description ?? ""),
      recommended_action: String(h.recommended_action ?? ""),
      confidence: Number(h.confidence ?? 0),
      fk_probability: fkP,
      fk_frequency: fkF,
      fk_severity: fkS,
      fk_score: fkScore,
      fk_band: fkBand(fkScore),
      m5_probability: safeM5P,
      m5_severity: safeM5S,
      m5_score: m5Score,
      m5_band: m5Band(m5Score),
    };
  });

  return {
    finding_count: findings.length,
    total_score_fk: totalScoreFK,
    total_score_m5: totalScoreM5,
    findings,
  };
}

function freeGeminiKeyPool(): GeminiKeyConfig[] {
  const primary = Deno.env.get("GEMINI_API_KEY_PRIMARY") ??
    Deno.env.get("GEMINI_API_KEY");
  const secondary = Deno.env.get("GEMINI_API_KEY_SECONDARY");
  return [
    primary
      ? { alias: "gemini_primary" as const, key: primary, pool: "free" as const }
      : null,
    secondary
      ? {
        alias: "gemini_secondary" as const,
        key: secondary,
        pool: "free" as const,
      }
      : null,
  ].filter((item): item is GeminiKeyConfig => item !== null);
}

function geminiAttemptSequence(keyPool: GeminiKeyConfig[]) {
  const primary = keyPool.find((item) => item.alias === "gemini_primary");
  const secondary = keyPool.find((item) => item.alias === "gemini_secondary");
  const ordered = [primary, secondary].filter(
    (item): item is GeminiKeyConfig => Boolean(item),
  );
  return [
    ...ordered.map((keyConfig) => ({ keyConfig, model: MODEL_FREE })),
    ...ordered.map((keyConfig) => ({ keyConfig, model: MODEL_FREE_FALLBACK })),
  ];
}

async function loadImages(supabase: any, analysisID: string) {
  const { data: photos, error } = await supabase
    .from("photos")
    .select("storage_path,mime_type,width,height")
    .eq("analysis_id", analysisID)
    .order("created_at", { ascending: true })
    .limit(MAX_ANALYSIS_PHOTOS);

  if (error) throw new Error(`photos query failed: ${error.message}`);

  const images: ImagePart[] = [];
  for (const photo of photos ?? []) {
    const { data, error: downloadError } = await supabase.storage
      .from(PHOTOS_BUCKET)
      .download(photo.storage_path);
    if (downloadError || !data) {
      throw new Error(`photo download failed: ${photo.storage_path}`);
    }

    const bytes = new Uint8Array(await data.arrayBuffer());
    images.push({
      mimeType: normalizeMimeType(photo.mime_type),
      data: base64FromBytes(bytes),
      byteSize: bytes.byteLength,
      storagePath: photo.storage_path,
    });
  }
  return images;
}

async function callGemini(params: {
  apiKey: string;
  model: string;
  images: ImagePart[];
}) {
  const parts = params.images.map((image) => ({
    inlineData: { mimeType: image.mimeType, data: image.data },
  }));
  const maybeThinkingConfig = thinkingConfig(params.model);
  const startedAt = Date.now();
  const res = await fetch(
    `${GEMINI_API_BASE}/${params.model}:generateContent?key=${params.apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: FREE_ANALYSIS_PROMPT }] },
        contents: [{ role: "user", parts }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: responseSchema(),
          temperature: 0.2,
          maxOutputTokens: 12000,
          ...(maybeThinkingConfig
            ? { thinkingConfig: maybeThinkingConfig }
            : {}),
        },
      }),
    },
  );
  const durationMs = Date.now() - startedAt;
  if (!res.ok) throw new GeminiAPIError(res.status, await res.text());

  const json = await res.json();
  const text = json.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("Gemini response content is empty.");
  return {
    result: JSON.parse(text),
    usage: {
      input_tokens: json.usageMetadata?.promptTokenCount ?? 0,
      output_tokens: json.usageMetadata?.candidatesTokenCount ?? 0,
      total_tokens: json.usageMetadata?.totalTokenCount ?? 0,
      thoughts_tokens: json.usageMetadata?.thoughtsTokenCount ?? null,
      duration_ms: durationMs,
      usage_metadata: json.usageMetadata ?? null,
    },
  };
}

async function runGeminiQA(supabase: any, analysisID: string) {
  const { data: analysis, error } = await supabase
    .from("analyses")
    .select("id,user_id,title,created_at")
    .eq("id", analysisID)
    .maybeSingle();
  if (error) throw new Error(`analysis query failed: ${error.message}`);
  if (!analysis) throw new Error(`analysis not found: ${analysisID}`);

  const images = await loadImages(supabase, analysisID);
  if (images.length === 0) throw new Error("analysis has no photos.");

  const keys = freeGeminiKeyPool();
  if (keys.length === 0) throw new Error("No Free Gemini key configured.");

  let lastError: unknown = null;
  let attempt = 0;
  for (const { keyConfig, model } of geminiAttemptSequence(keys)) {
    attempt += 1;
    try {
      const out = await callGemini({ apiKey: keyConfig.key, model, images });
      return {
        source_analysis: {
          id: analysis.id,
          user_id: analysis.user_id,
          title: analysis.title,
          created_at: analysis.created_at,
        },
        qa_run: {
          provider: "gemini",
          model,
          key_alias: keyConfig.alias,
          attempt,
          thinking_config: thinkingConfig(model),
          photo_count: images.length,
          photo_metadata: images.map((image) => ({
            storage_path: image.storagePath,
            mime_type: image.mimeType,
            byte_size: image.byteSize,
          })),
          usage: out.usage,
          ai_summary: out.result?.ai_summary ?? "",
          limitations: out.result?.limitations ?? "",
          ...normalizedFindings(out.result?.hazards),
          raw_result: out.result,
        },
      };
    } catch (error) {
      lastError = error;
      if (
        error instanceof GeminiAPIError &&
        ![429, 500, 502, 503, 504].includes(error.status)
      ) {
        throw error;
      }
    }
  }
  throw lastError ?? new Error("Gemini QA failed.");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const qaSecret = Deno.env.get("AI_QA_SECRET")?.trim() ||
    Deno.env.get("GROQ_QA_SECRET")?.trim();
  if (!qaSecret) return json(503, { error: "qa_secret_not_configured" });
  if (req.headers.get("x-qa-secret") !== qaSecret) {
    return json(403, { error: "forbidden" });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return json(503, { error: "supabase_not_configured" });
  }

  let body: { analysis_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const analysisID = cleanID(body.analysis_id);
  if (!analysisID) return json(400, { error: "missing_analysis_id" });

  const startedAt = Date.now();
  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  try {
    const result = await runGeminiQA(supabase, analysisID);
    return json(200, {
      ok: true,
      runner: "gemini-free-qa-run",
      duration_ms: Date.now() - startedAt,
      result,
    });
  } catch (error) {
    console.error("gemini free qa failed", JSON.stringify(safeLogError(error)));
    return json(500, {
      error: "gemini_free_qa_failed",
      details: safeLogError(error),
    });
  }
});
