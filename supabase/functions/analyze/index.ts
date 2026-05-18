/**
 * analyze — RiskDetected Edge Function (Gemini-first, schema-aligned)
 *
 * POST body:
 *   analysis_id  : string (UUID)
 *   canvas       : string (primary canvas id, single-value enum)
 *   canvases     : string[] (all selected; Free supports one, paid plans support multiple)
 *   text_input   : string | null
 *   user_prompt  : string | null (optional, max 100 chars; user focus note)
 *   request_id   : string | null (client trace id)
 *   support_id   : string | null (user-facing support code)
 *   photo_paths  : string[] (Storage paths in "photos" bucket)
 *   photo_base64_parts: { mime_type: string; data: string; width?: number; height?: number }[] (inline photos)
 *
 * Schema notes (v4):
 *   - profiles.tier        enum/text: free | plus | pro
 *   - analyses.analysis_mode enum/text: standard | detailed | emergency | procedure
 *   - analyses.status      enum: pending | analyzing | completed | failed
 *   - analyses.canvas      text canvas id; known ids are listed in CANVAS_FOCUS
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

const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";

const MODEL_FREE_LITE = "gemini-2.5-flash-lite";
const MODEL_FREE = "gemini-2.5-flash";
// Gemini Pro model free quota bu API key'de 0 dönebiliyor.
// Ücretli Google AI planı açılana kadar PRO kullanıcıyı da Flash üzerinde çalıştırıyoruz.
const MODEL_PRO = "gemini-2.5-flash";

type PlanTier = "free" | "plus" | "pro";
type AnalysisMode = "standard" | "detailed" | "emergency" | "procedure";

const PLAN_LIMITS: Record<PlanTier, {
  dailyStandardLimit?: number;
  dailyDetailedLimit?: number;
  maxHazards: number;
}> = {
  free: { dailyStandardLimit: 1, maxHazards: 4 },
  plus: { dailyStandardLimit: 10, dailyDetailedLimit: 2, maxHazards: 8 },
  pro: { dailyStandardLimit: 40, dailyDetailedLimit: 10, maxHazards: 10 },
};

const COMMON_ANALYSIS_PROMPT =
  `Fotoğrafı iş güvenliği uzmanı saha gözlemi gibi analiz et. Sadece görüntüde görülen bulgulara dayan. Görünmeyen veya emin olmadığın noktaları "kontrol edilmeli" diye belirt.`;

const PRO_REFERENCES_PROMPT =
  `Fotoğrafı Türkiye İSG mevzuatı perspektifiyle değerlendir. Her bulgu için Türkiye İSG mevzuatıyla ilişkili uygun kanun/yönetmelik başlığını references alanında kısa yaz. References alanı kısaltılmış kanun/yönetmelik adı ve biliyorsan kısa madde bilgisini içersin; emin değilsen madde uydurma, "mevzuat karşılığı kontrol edilmeli" yaz. Standart numarası, ölçüm değeri veya uzun açıklama uydurma.`;

const CANVAS_FOCUS: Record<string, string> = {
  general:
    "Görüntüdeki tüm görünür İSG uygunsuzluklarını tara; düşme, çarpma, sıkışma, elektrik, yangın, kimyasal, düzen-temizlik, KKD, işaretleme, acil çıkış ve çalışma alanı risklerini önceliklendir.",
  ppe:
    "Baret, gözlük/yüz koruma, eldiven, iş ayakkabısı, reflektif yelek, solunum koruması, kulak koruması, emniyet kemeri ve kullanım/uygunluk eksiklerini değerlendir.",
  machine:
    "Koruyucular, döner/hareketli parçalar, sıkışma-ezilme-kesilme riskleri, acil durdurma, bakım-kilit/etiketleme, periyodik kontrol ve yetkisiz erişim uygunsuzluklarını analiz et.",
  warning_signs:
    "Uyarı, yasak, zorunluluk, acil çıkış, yangın ekipmanı, yönlendirme, zemin/alan işaretlemesi, görünürlük, konum ve eksik işaret risklerini belirt.",
  electrical:
    "Pano, kablo, priz, topraklama, kaçak akım, açık iletken, izolasyon, dağınık kablolama, nem/sıvı teması, yetkisiz erişim ve elektrik çarpması/yangın risklerini değerlendir.",
  sector:
    "Sektör bağlamını tahmin et; inşaat, üretim, depo/lojistik, ofis veya saha çalışmasına özgü tipik İSG risklerini görünür bulgularla ilişkilendir. Tahmin belirsizse açıkça belirt.",
  fire:
    "Yanıcı/parlayıcı malzeme, sıcak çalışma, elektrik kaynaklı yangın, söndürücü erişimi, yangın dolabı, acil çıkış, tahliye yolu, depolama düzeni ve yangın yükünü analiz et.",
  ergonomics:
    "Fotoğraftaki ekipmanı tanımla ve İSG açısından değerlendir. Emin değilsen olasılıkları belirt, varsayım yapma. Kısa başlıklarla şunları ver: ekipman adı, tehlikeler, riskler, önlemler, gerekli KKD, kullanım öncesi kontroller ve durdurma kriterleri. Kritik risk varsa en başta uyar. Eksik bilgi varsa ek fotoğraf veya marka/model iste.",
  environment_measurement:
    'Gürültü, toz, gaz/buhar, aydınlatma, sıcaklık, havalandırma, titreşim ve kimyasal maruziyet gibi ölçüm gerektiren başlıkları "ölçümle doğrulanmalı" olarak yaz.',
  explosion:
    "Patlayıcı atmosfer, gaz/buhar/toz birikimi, yanıcı depolama, basınçlı kap, statik elektrik, kıvılcım/ateşleme kaynağı, havalandırma, Ex ekipman ve patlamadan korunma dokümanı ihtiyacını değerlendir.",
  environment:
    "Atık yönetimi, sızıntı/dökülme, kimyasal depolama, drenaj, toprak/su kirliliği, emisyon/toz yayılımı, saha düzeni ve çevresel acil durum risklerini analiz et.",
  legislation:
    "Görüntüdeki bulguları Türkiye İSG mevzuatı açısından eşleştir. 6331, Risk Değerlendirmesi, KKD, İş Ekipmanları, Sağlık ve Güvenlik İşaretleri, Acil Durumlar, Yapı İşleri, İş Hijyeni, Patlayıcı Ortamlar vb. başlıklarla ilişkilendir. Emin olmadığın maddeyi uydurma.",
  working_at_height:
    "Düşme tehlikesi, korkuluk, iskele, merdiven, platform, yaşam hattı, ankraj, emniyet kemeri, boşluk/kenar koruması, düşen cisim ve erişim güvenliğini analiz et.",
  mobile_equipment:
    "Forklift, transpalet, vinç, kamyon, araç-yaya ayrımı, kör nokta, hız, manevra alanı, yük güvenliği, geri görüş, uyarı sistemi ve çarpma/ezilme risklerini belirt.",
  general_premium:
    "Tüm görünür İSG risklerini denetim odaklı ve ayrıntılı analiz et. Bulguları kritik seviyeden düşüğe sırala; her biri için kök neden, olası kaza senaryosu, acil aksiyon ve mevzuat karşılığını ver.",
  construction_machinery:
    "Ekskavatör, yükleyici, vinç, kazıcı, kaldırıcı ve saha araçlarında devrilme, ezilme, kör nokta, operatör görüşü, yük kaldırma, zemin stabilitesi, bakım/periyodik kontrol ve yetkisiz yaklaşma risklerini analiz et.",
};

const PRO_CANVASES = new Set([
  "legislation",
  "general_premium",
  "ergonomics",
]);
const PLUS_CANVASES = new Set([
  "machine",
  "sector",
  "environment_measurement",
]);
const PAID_CANVASES = new Set([...PLUS_CANVASES, ...PRO_CANVASES]);
const DETAILED_CANVASES = new Set([
  ...PLUS_CANVASES,
  ...PRO_CANVASES,
  "general_premium",
]);

// DB constraint ile birebir uyumlu Fine-Kinney ölçekleri
const FK_PROBABILITY_VALUES = [0.2, 0.5, 1, 3, 6, 10];
const FK_FREQUENCY_VALUES = [0.5, 1, 2, 3, 6, 10];
const FK_SEVERITY_VALUES = [1, 3, 7, 15, 40, 100];

function clampFK(value: number, allowed: number[]): number {
  return allowed.reduce((prev, curr) =>
    Math.abs(curr - value) < Math.abs(prev - value) ? curr : prev
  );
}

// Fine-Kinney skor → risk_level enum
function fkBand(score: number): "low" | "medium" | "high" | "critical" {
  if (score < 70) return "low";
  if (score < 200) return "medium";
  if (score < 400) return "high";
  return "critical";
}

// 5×5 skor → risk_level enum
function m5Band(score: number): "low" | "medium" | "high" | "critical" {
  if (score <= 4) return "low";
  if (score <= 9) return "medium";
  if (score <= 16) return "high";
  return "critical";
}

function responseSchema(isPro: boolean) {
  const hazardProperties: Record<string, unknown> = {
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
  };
  if (isPro) {
    hazardProperties.references = { type: "STRING" };
  }

  return {
    type: "OBJECT",
    properties: {
      hazards: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: hazardProperties,
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

class GeminiAPIError extends Error {
  status: number;
  body: string;

  constructor(status: number, body: string) {
    super(`Gemini HTTP ${status}: ${body}`);
    this.status = status;
    this.body = body;
  }
}

type GeminiKeyConfig = {
  alias: "gemini_primary" | "gemini_secondary" | "gemini_tertiary";
  key: string;
};

type AISimulationMode = "429" | "500" | "502" | "503" | "504" | "invalid_json";

type AISimulationConfig = {
  enabled: boolean;
  mode: AISimulationMode | null;
  once: boolean;
  remainingFailures: number;
};

function aiSimulationConfig(): AISimulationConfig {
  const enabled =
    Deno.env.get("RISKDETECTED_ENABLE_TEST_SIMULATION") === "true";
  const rawMode = Deno.env.get("SIMULATE_AI_ERROR_CODE")?.trim().toLowerCase();
  const validModes = new Set<AISimulationMode>([
    "429",
    "500",
    "502",
    "503",
    "504",
    "invalid_json",
  ]);
  const mode = validModes.has(rawMode as AISimulationMode)
    ? rawMode as AISimulationMode
    : null;
  const once = Deno.env.get("SIMULATE_AI_ERROR_ONCE") !== "false";

  return {
    enabled: enabled && mode !== null,
    mode,
    once,
    remainingFailures: once ? 1 : Number.POSITIVE_INFINITY,
  };
}

function maybeSimulateAIError(simulation?: AISimulationConfig) {
  if (
    !simulation?.enabled || !simulation.mode ||
    simulation.remainingFailures <= 0
  ) {
    return;
  }

  simulation.remainingFailures -= 1;
  console.warn(
    "RiskDetected AI simulation triggered",
    JSON.stringify({
      mode: simulation.mode,
      once: simulation.once,
    }),
  );

  if (simulation.mode === "invalid_json") {
    throw new SyntaxError("Simulated invalid AI JSON response.");
  }

  const status = Number(simulation.mode);
  throw new GeminiAPIError(
    status,
    JSON.stringify({
      error: {
        code: status,
        message: `Simulated Gemini HTTP ${status}`,
        status: status === 429 ? "RESOURCE_EXHAUSTED" : "UNAVAILABLE",
      },
    }),
  );
}

function tierRank(tier: PlanTier): number {
  switch (tier) {
    case "pro":
      return 2;
    case "plus":
      return 1;
    case "free":
    default:
      return 0;
  }
}

function normalizeTier(raw: unknown): PlanTier {
  return raw === "pro" || raw === "plus" ? raw : "free";
}

function hasActiveSubscription(
  row:
    | { status?: string | null; current_period_ends_at?: string | null }
    | null,
): boolean {
  if (!row) return false;
  if (
    !["active", "trialing", "grace_period"].includes(String(row.status ?? ""))
  ) return false;
  if (!row.current_period_ends_at) return true;
  const expiresAt = Date.parse(row.current_period_ends_at);
  return Number.isFinite(expiresAt) && expiresAt > Date.now();
}

function resolvePlanTier(
  profileTier: unknown,
  subscription: {
    tier?: string | null;
    status?: string | null;
    current_period_ends_at?: string | null;
  } | null,
): PlanTier {
  void profileTier;
  return hasActiveSubscription(subscription)
    ? normalizeTier(subscription?.tier)
    : "free";
}

function canUseCanvas(tier: PlanTier, canvasID: string): boolean {
  if (PRO_CANVASES.has(canvasID)) return tier === "pro";
  if (PLUS_CANVASES.has(canvasID)) return tier === "plus" || tier === "pro";
  return !PAID_CANVASES.has(canvasID);
}

function normalizeAnalysisMode(
  rawMode: unknown,
  canvasIDs: string[],
): AnalysisMode {
  if (
    rawMode === "detailed" || rawMode === "emergency" || rawMode === "procedure"
  ) {
    return rawMode;
  }
  if (canvasIDs.some((id) => DETAILED_CANVASES.has(id))) return "detailed";
  return "standard";
}

function istanbulDayStartISO(): string {
  const day = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Istanbul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  return `${day}T00:00:00+03:00`;
}

function buildSystemPrompt(canvases: string[], tier: PlanTier): string {
  const isPro = tier === "pro";
  const maxHazards = PLAN_LIMITS[tier].maxHazards;
  const focusLines =
    canvases.map((c) => CANVAS_FOCUS[c]).filter(Boolean).join(" ") ||
    CANVAS_FOCUS["general"];
  return `Sen deneyimli bir iş güvenliği (HSE/İSG) uzmanısın. Görevin: verilen görsel ve/veya metin girdisinden İSG tehlikelerini ve risklerini tespit etmek.

ORTAK YAKLAŞIM:
${COMMON_ANALYSIS_PROMPT}
${isPro ? `\nPRO MEVZUAT REFERANSI:\n${PRO_REFERENCES_PROMPT}` : ""}

ODAK: ${focusLines}

KURALLAR:
- Yalnızca fotoğrafta/metinde GÖZLEMLENEN kanıtlara dayan. Tahmin etme.
- Emin olmadığın noktalar için confidence değerini düşür (0.3–0.6).
- En fazla ${maxHazards} tehlike döndür; önem sırasına göre sırala.
- Her tehlike için description alanını kısa tut; yalnızca görünen kanıt ve riskin özünü 1-2 kısa cümleyle anlat.
- Her tehlike için recommended_action alanını kısa, uygulanabilir ve en fazla 180 karakter olacak şekilde yaz.
${
    isPro
      ? `- Her tehlike için references alanını kısa tut; kısaltılmış kanun/yönetmelik adı + varsa kısa madde bilgisini yaz veya "mevzuat karşılığı kontrol edilmeli" yaz.`
      : ""
  }
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
  userPrompt: string | null,
  imageBase64Parts: { mimeType: string; data: string }[],
  isPro: boolean,
  simulation?: AISimulationConfig,
) {
  maybeSimulateAIError(simulation);

  const parts: unknown[] = [];
  for (const img of imageBase64Parts) {
    parts.push({ inlineData: { mimeType: img.mimeType, data: img.data } });
  }
  if (userPrompt) {
    parts.push({
      text:
        `Kullanıcının özel analiz talebi: ${userPrompt}\nBu talebi yalnızca görsel/metin kanıtları destekliyorsa önceliklendir; kanıt yoksa uydurma.`,
    });
  }
  if (userText) {
    parts.push({ text: `Kullanıcı saha/metin girdisi: ${userText}` });
  } else if (imageBase64Parts.length === 0) {
    throw new Error("En az bir fotoğraf veya metin girdisi gerekli.");
  }

  const body = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: "user", parts }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: responseSchema(isPro),
      temperature: 0.2,
      maxOutputTokens: 12000,
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
    inputTokens: json.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: json.usageMetadata?.candidatesTokenCount ?? 0,
  };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function geminiKeyPool(): GeminiKeyConfig[] {
  const primary = Deno.env.get("GEMINI_API_KEY_PRIMARY") ??
    Deno.env.get("GEMINI_API_KEY");
  const secondary = Deno.env.get("GEMINI_API_KEY_SECONDARY");
  const tertiary = Deno.env.get("GEMINI_API_KEY_TERTIARY");

  const keys = [
    primary ? { alias: "gemini_primary" as const, key: primary } : null,
    secondary ? { alias: "gemini_secondary" as const, key: secondary } : null,
    tertiary ? { alias: "gemini_tertiary" as const, key: tertiary } : null,
  ].filter((item): item is GeminiKeyConfig => item !== null);

  const preferredAlias = Deno.env.get("GEMINI_PREFERRED_KEY_ALIAS")?.trim();
  if (!preferredAlias) return keys;

  const preferredIndex = keys.findIndex((item) =>
    item.alias === preferredAlias
  );
  if (preferredIndex < 0) return keys;

  const preferred = keys[preferredIndex];
  return [
    preferred,
    ...keys.filter((_, index) => index !== preferredIndex),
  ];
}

function userFacingAIError(
  err: unknown,
): { status: number; code: string; message: string } {
  if (err instanceof GeminiAPIError) {
    if (err.status === 429) {
      return {
        status: 429,
        code: "ai_rate_limited",
        message:
          "Gemini kotası doldu. Google AI kullanım limitini veya faturalandırma planını kontrol etmek gerekiyor.",
      };
    }
    if (err.status === 503) {
      return {
        status: 503,
        code: "ai_unavailable",
        message: "Gemini modeli şu anda yoğun. Biraz sonra tekrar dene.",
      };
    }
    return {
      status: 502,
      code: "ai_provider_error",
      message: `Gemini servis hatası (${err.status}).`,
    };
  }

  if (err instanceof SyntaxError) {
    return {
      status: 502,
      code: "ai_invalid_response",
      message: "AI yanıtı işlenemedi. Lütfen aynı analizi tekrar dene.",
    };
  }

  return {
    status: 502,
    code: "ai_failed",
    message: "AI analizi tamamlanamadı. Lütfen tekrar dene.",
  };
}

async function callGeminiWithFallback(
  keyPool: GeminiKeyConfig[],
  preferredModel: string,
  systemPrompt: string,
  userText: string | null,
  userPrompt: string | null,
  imageBase64Parts: { mimeType: string; data: string }[],
  isPro: boolean,
  simulation?: AISimulationConfig,
) {
  const models = preferredModel === MODEL_FREE_LITE
    ? [MODEL_FREE_LITE, MODEL_FREE]
    : [preferredModel, MODEL_FREE_LITE];

  let lastError: unknown = null;
  let attempt = 0;
  for (const keyConfig of keyPool) {
    for (const model of [...new Set(models)]) {
      attempt += 1;
      try {
        const out = await callGemini(
          keyConfig.key,
          model,
          systemPrompt,
          userText,
          userPrompt,
          imageBase64Parts,
          isPro,
          simulation,
        );
        return {
          ...out,
          modelUsed: model,
          apiKeyAlias: keyConfig.alias,
          attempt,
        };
      } catch (err) {
        lastError = err;
        const retryable = err instanceof SyntaxError ||
          (err instanceof GeminiAPIError &&
            [429, 500, 502, 503, 504].includes(err.status));
        console.error(
          "Gemini attempt failed",
          JSON.stringify({
            apiKeyAlias: keyConfig.alias,
            model,
            attempt,
            retryable,
            error: safeLogError(err),
          }),
        );
        if (!retryable) throw err;
        await delay(500);
      }
    }
  }

  throw lastError ?? new Error("Gemini analizi başarısız.");
}

function newSupportID(): string {
  return `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function safeLogError(error: unknown): Record<string, unknown> {
  if (error instanceof GeminiAPIError) {
    return { name: "GeminiAPIError", status: error.status };
  }
  if (error instanceof SyntaxError) {
    return { name: "SyntaxError" };
  }
  if (error instanceof Error) {
    return {
      name: error.name || "Error",
      message: error.message.replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
        .slice(0, 160),
    };
  }
  return { name: typeof error };
}

function safeLogText(value: unknown, maxLength = 220): string {
  if (typeof value !== "string") return "";
  return value.replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]").slice(
    0,
    maxLength,
  );
}

function storageObjectURL(
  supabaseUrl: string,
  bucket: string,
  path: string,
): string {
  const cleanUrl = supabaseUrl.replace(/\/$/, "");
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  return `${cleanUrl}/storage/v1/object/${encodeURIComponent(bucket)}/${encodedPath}`;
}

async function uploadStorageObject(params: {
  supabaseUrl: string;
  serviceRoleKey: string;
  bucket: string;
  path: string;
  body: Uint8Array;
  mimeType: string;
}): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const res = await fetch(
    storageObjectURL(params.supabaseUrl, params.bucket, params.path),
    {
      method: "POST",
      headers: {
        apikey: params.serviceRoleKey,
        Authorization: `Bearer ${params.serviceRoleKey}`,
        "Content-Type": params.mimeType,
        "cache-control": "3600",
        "x-upsert": "true",
      },
      body: params.body,
    },
  );

  if (res.ok) return { ok: true };
  return {
    ok: false,
    status: res.status,
    error: safeLogText(await res.text().catch(() => ""), 500),
  };
}

async function hashedID(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest.slice(0, 6)))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function normalizedTraceValue(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().replace(/[^a-zA-Z0-9._:-]/g, "").slice(0, 80);
  return clean.length > 0 ? clean : fallback;
}

function errorResponse(status: number, message: string, meta?: {
  code?: string;
  requestID?: string;
  supportID?: string;
  tier?: string;
  limit?: number;
  used?: number;
  feature?: string;
}): Response {
  const supportID = meta?.supportID ?? newSupportID();
  return new Response(
    JSON.stringify({
      error: message,
      message,
      code: meta?.code ?? "unknown",
      request_id: meta?.requestID ?? null,
      support_id: supportID,
      tier: meta?.tier ?? null,
      limit: meta?.limit ?? null,
      used: meta?.used ?? null,
      feature: meta?.feature ?? null,
    }),
    {
      status,
      headers: { "Content-Type": "application/json" },
    },
  );
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function stripJPEGMetadata(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return bytes;

  const chunks: Uint8Array[] = [bytes.subarray(0, 2)];
  let offset = 2;

  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) return bytes;

    let markerOffset = offset;
    while (markerOffset < bytes.length && bytes[markerOffset] === 0xff) {
      markerOffset++;
    }
    if (markerOffset >= bytes.length) return bytes;

    const marker = bytes[markerOffset];
    offset = markerOffset + 1;

    // Start of Scan: compressed image data follows; copy the rest as-is.
    if (marker === 0xda) {
      chunks.push(bytes.subarray(markerOffset - 1));
      return concatBytes(chunks);
    }

    // Standalone markers without payload length.
    if (
      marker === 0xd9 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0x01
    ) {
      chunks.push(bytes.subarray(markerOffset - 1, offset));
      continue;
    }

    if (offset + 2 > bytes.length) return bytes;
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return bytes;

    const segmentStart = markerOffset - 1;
    const segmentEnd = offset + length;
    const isAppSegment = marker >= 0xe0 && marker <= 0xef;
    const isComment = marker === 0xfe;

    // APPn segments commonly carry EXIF/GPS/XMP/JFIF metadata; COM carries comments.
    if (!isAppSegment && !isComment) {
      chunks.push(bytes.subarray(segmentStart, segmentEnd));
    }

    offset = segmentEnd;
  }

  return concatBytes(chunks);
}

function stripPNGMetadata(bytes: Uint8Array): Uint8Array {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (
    bytes.length < signature.length ||
    !signature.every((b, i) => bytes[i] === b)
  ) return bytes;

  const chunks: Uint8Array[] = [bytes.subarray(0, 8)];
  let offset = 8;
  const metadataChunkTypes = new Set(["eXIf", "tEXt", "zTXt", "iTXt", "tIME"]);

  while (offset + 12 <= bytes.length) {
    const length = (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
    if (length < 0) return bytes;

    const chunkEnd = offset + 12 + length;
    if (chunkEnd > bytes.length) return bytes;

    const type = String.fromCharCode(
      bytes[offset + 4],
      bytes[offset + 5],
      bytes[offset + 6],
      bytes[offset + 7],
    );

    if (!metadataChunkTypes.has(type)) {
      chunks.push(bytes.subarray(offset, chunkEnd));
    }

    offset = chunkEnd;
    if (type === "IEND") break;
  }

  return concatBytes(chunks);
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

function normalizedImageMimeType(value: unknown): "image/jpeg" | "image/png" {
  const raw = typeof value === "string" ? value.toLowerCase() : "";
  return raw.includes("png") ? "image/png" : "image/jpeg";
}

function stripImageMetadata(bytes: Uint8Array, mimeType: string): Uint8Array {
  if (mimeType === "image/png") return stripPNGMetadata(bytes);
  return stripJPEGMetadata(bytes);
}

function sanitizedDimension(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.round(value)
    : 0;
}

function sanitizedUserPrompt(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 100);
  return cleaned.length > 0 ? cleaned : null;
}

// deno-lint-ignore no-explicit-any
async function logUsage(supabase: any, data: any) {
  try {
    await supabase.from("ai_usage_logs").insert(data);
  } catch (e) {
    console.error("Usage log insert failed", JSON.stringify(safeLogError(e)));
  }
}

// deno-lint-ignore no-explicit-any
async function releaseAnalysisQuota(
  supabase: any,
  analysisID: string,
  userID: string,
) {
  try {
    await supabase
      .from("usage_events")
      .delete()
      .eq("user_id", userID)
      .eq("source_id", analysisID)
      .in("feature", ["analysis_standard", "analysis_detailed"])
      .eq("event_type", "reserved");
  } catch (e) {
    console.error(
      "Quota reservation release failed",
      JSON.stringify(safeLogError(e)),
    );
  }
}

// deno-lint-ignore no-explicit-any
async function completeAnalysisQuota(
  supabase: any,
  analysisID: string,
  userID: string,
) {
  try {
    await supabase
      .from("usage_events")
      .update({
        event_type: "completed",
      })
      .eq("user_id", userID)
      .eq("source_id", analysisID)
      .in("feature", ["analysis_standard", "analysis_detailed"])
      .eq("event_type", "reserved");
  } catch (e) {
    console.error(
      "Quota reservation completion failed",
      JSON.stringify(safeLogError(e)),
    );
  }
}

const BAND_RANK: Record<string, number> = {
  low: 0,
  medium: 1,
  high: 2,
  critical: 3,
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  const startMs = Date.now();
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const supabase = createClient(
    supabaseUrl,
    serviceRoleKey,
  );

  const fallbackRequestID = crypto.randomUUID();
  let requestID = normalizedTraceValue(
    req.headers.get("x-request-id"),
    fallbackRequestID,
  );
  let supportID = normalizedTraceValue(
    req.headers.get("x-support-id"),
    newSupportID(),
  );

  const geminiKeys = geminiKeyPool();
  if (geminiKeys.length === 0) {
    return errorResponse(500, "Gemini API key secret eksik.", {
      code: "missing_secret",
      requestID,
      supportID,
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse(401, "Authorization header eksik.", {
      code: "auth_required",
      requestID,
      supportID,
    });
  }

  const { data: { user }, error: authErr } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (authErr || !user) {
    return errorResponse(401, "Geçersiz token.", {
      code: "auth_invalid",
      requestID,
      supportID,
    });
  }

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "Geçersiz JSON body.", {
      code: "invalid_json",
      requestID,
      supportID,
    });
  }

  const {
    analysis_id,
    canvas,
    canvases,
    analysis_mode,
    text_input,
    photo_paths = [],
    photo_base64_parts = [],
  } = body;
  requestID = normalizedTraceValue(body.request_id, requestID);
  supportID = normalizedTraceValue(body.support_id, supportID);
  const userPrompt = sanitizedUserPrompt(body.user_prompt);
  if (!analysis_id) {
    return errorResponse(400, "analysis_id zorunlu.", {
      code: "validation_failed",
      requestID,
      supportID,
    });
  }
  const analysisID = String(analysis_id);
  const requestedPhotoPaths = Array.isArray(photo_paths)
    ? photo_paths
      .map((path) => typeof path === "string" ? path.trim() : "")
      .filter((path) => path.length > 0)
    : [];

  console.log(
    "Analyze request started",
    JSON.stringify({
      request_id: requestID,
      support_id: supportID,
      analysis_id: analysisID,
      user_hash: await hashedID(user.id),
    }),
  );

  const { data: ownedAnalysis, error: analysisOwnerErr } = await supabase
    .from("analyses")
    .select("id,user_id")
    .eq("id", analysisID)
    .eq("user_id", user.id)
    .maybeSingle();

  if (analysisOwnerErr || !ownedAnalysis) {
    console.warn(
      "Analyze ownership denied",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        analysis_id: analysisID,
        user_hash: await hashedID(user.id),
        error: analysisOwnerErr ? safeLogError(analysisOwnerErr) : null,
      }),
    );
    return errorResponse(
      404,
      "Analiz bulunamadı veya bu işlem için yetki yok.",
      {
        code: "analysis_not_found",
        requestID,
        supportID,
      },
    );
  }

  // deno-lint-ignore no-explicit-any
  const updateOwnedAnalysis = (patch: Record<string, any>) =>
    supabase.from("analyses")
      .update(patch)
      .eq("id", analysisID)
      .eq("user_id", user.id);

  const requestedCanvases = [
    ...new Set(
      (Array.isArray(canvases) && canvases.length > 0 ? canvases : [canvas])
        .map((item) => String(item ?? "").trim())
        .filter((item) => item.length > 0),
    ),
  ];
  const analysisMode = normalizeAnalysisMode(analysis_mode, requestedCanvases);

  // Profil + backend-synced subscription tier
  const { data: profile } = await supabase
    .from("profiles")
    .select("tier")
    .eq("id", user.id)
    .single();
  const { data: subscription } = await supabase
    .from("user_subscriptions")
    .select("tier,status,current_period_ends_at")
    .eq("user_id", user.id)
    .maybeSingle();
  const planTier = resolvePlanTier(profile?.tier, subscription);
  const isPro = planTier === "pro";

  if (planTier === "free" && requestedCanvases.length > 1) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Free planda tek analiz odağı seçebilirsin. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Free planda tek analiz odağı seçebilirsin.",
      {
        code: "single_canvas_required",
        requestID,
        supportID,
        tier: planTier,
      },
    );
  }

  if (requestedCanvases.some((id) => !canUseCanvas(planTier, String(id)))) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Bu analiz odağı daha yüksek üyelik gerektirir. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Bu analiz odağı daha yüksek üyelik gerektirir.",
      {
        code: "plan_required",
        requestID,
        supportID,
      },
    );
  }

  if (analysisMode === "detailed" && planTier === "free") {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Detaylı analiz Plus veya Pro üyelik gerektirir. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Detaylı analiz Plus veya Pro üyelik gerektirir.",
      {
        code: "plan_required",
        requestID,
        supportID,
      },
    );
  }

  if (analysisMode === "emergency" && planTier === "free") {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Acil risk modülü Plus veya Pro üyelik gerektirir. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Acil risk modülü Plus veya Pro üyelik gerektirir.",
      {
        code: "plan_required",
        requestID,
        supportID,
      },
    );
  }

  if (analysisMode === "procedure" && planTier !== "pro") {
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Prosedür uygunluk kontrolü Pro üyelik gerektirir. Destek kodu: ${supportID}`,
    });
    return errorResponse(
      403,
      "Prosedür uygunluk kontrolü Pro üyelik gerektirir.",
      {
        code: "plan_required",
        requestID,
        supportID,
      },
    );
  }

  const { data: quotaReservation, error: quotaReservationErr } = await supabase
    .rpc("reserve_analysis_quota", {
      p_user_id: user.id,
      p_analysis_id: analysisID,
      p_analysis_mode: analysisMode,
    });

  if (quotaReservationErr) {
    console.error(
      "Quota reservation failed",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        analysis_id: analysisID,
        error: safeLogError(quotaReservationErr),
      }),
    );
    await updateOwnedAnalysis({
      status: "failed",
      status_message:
        `Analiz kotası kontrol edilemedi. Destek kodu: ${supportID}`,
    });
    return errorResponse(500, "Analiz kotası kontrol edilemedi.", {
      code: "quota_check_failed",
      requestID,
      supportID,
    });
  }

  if (quotaReservation?.ok !== true) {
    await updateOwnedAnalysis({
      status: "failed",
      status_message: `${
        quotaReservation?.message ?? "Analiz kotası doldu."
      } Destek kodu: ${supportID}`,
    });
    return errorResponse(
      quotaReservation?.code === "plan_required" ? 403 : 429,
      quotaReservation?.message ?? "Analiz kotası doldu.",
      {
        code: quotaReservation?.code ?? "quota_exceeded",
        requestID,
        supportID,
        tier: quotaReservation?.tier,
        limit: quotaReservation?.limit,
        used: quotaReservation?.used,
        feature: quotaReservation?.feature,
      },
    );
  }

  // Status → analyzing
  await updateOwnedAnalysis({
    status: "analyzing",
    analysis_mode: analysisMode,
    started_at: new Date().toISOString(),
  });

  const model = planTier === "free" ? MODEL_FREE_LITE : MODEL_PRO;

  // Storage → base64
  const imageBase64Parts: { mimeType: string; data: string }[] = [];
  const inlinePhotoParts = Array.isArray(photo_base64_parts)
    ? photo_base64_parts
    : [];
  const sanitizedInlinePhotos: {
    mimeType: "image/jpeg" | "image/png";
    bytes: Uint8Array;
    data: string;
    width: number;
    height: number;
  }[] = [];
  const inlinePhotoCount = inlinePhotoParts.length;
  const storagePhotoCount = requestedPhotoPaths.length;

  for (const part of inlinePhotoParts) {
    if (!part?.data) continue;
    const mimeType = normalizedImageMimeType(part.mime_type ?? part.mimeType);
    const rawBytes = base64ToBytes(part.data);
    const bytes = stripImageMetadata(rawBytes, mimeType);
    const data = bytesToBase64(bytes);
    sanitizedInlinePhotos.push({
      mimeType,
      bytes,
      data,
      width: sanitizedDimension(part.width),
      height: sanitizedDimension(part.height),
    });
    imageBase64Parts.push({
      mimeType,
      data,
    });
  }

  // Inline gelen fotoğrafları kalıcı olarak Storage + photos tablosuna yaz.
  // Client tarafında Storage RLS'e takılmamak için bu işi service role ile Edge Function yapıyor.
  const persistedPhotoPaths: string[] = [];
  const photoPersistErrors: Record<string, unknown>[] = [];
  if (sanitizedInlinePhotos.length > 0) {
    const { error: deletePhotoErr } = await supabase.from("photos")
      .delete()
      .eq("analysis_id", analysisID)
      .eq("user_id", user.id);

    if (deletePhotoErr) {
      photoPersistErrors.push({
        stage: "delete_existing_metadata",
        error: safeLogError(deletePhotoErr),
      });
      console.error(
        "Persist inline photo cleanup error",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogError(deletePhotoErr),
        }),
      );
    }

    for (let i = 0; i < sanitizedInlinePhotos.length; i++) {
      const part = sanitizedInlinePhotos[i];
      const mimeType = part.mimeType;
      const ext = mimeType.includes("png") ? "png" : "jpg";
      const storagePath = `${user.id}/${analysisID}/p${i + 1}.${ext}`;
      const uploadBody = part.bytes.byteOffset === 0 &&
          part.bytes.byteLength === part.bytes.buffer.byteLength
        ? part.bytes
        : part.bytes.slice();

      const uploadResult = await uploadStorageObject({
        supabaseUrl,
        serviceRoleKey,
        bucket: "photos",
        path: storagePath,
        body: uploadBody,
        mimeType,
      });

      if (!uploadResult.ok) {
        photoPersistErrors.push({
          stage: "storage_upload",
          photo_index: i + 1,
          status: uploadResult.status,
          error: safeLogText(uploadResult.error),
        });
        console.error(
          "Persist inline photo upload error",
          JSON.stringify({
            request_id: requestID,
            support_id: supportID,
            analysis_id: analysisID,
            photo_index: i + 1,
            status: uploadResult.status,
            error: safeLogText(uploadResult.error),
          }),
        );
        continue;
      }

      const { error: photoErr } = await supabase.from("photos").insert({
        analysis_id: analysisID,
        user_id: user.id,
        storage_path: storagePath,
        width: part.width,
        height: part.height,
        size_bytes: part.bytes.byteLength,
        mime_type: mimeType,
      });

      if (photoErr) {
        photoPersistErrors.push({
          stage: "metadata_insert",
          photo_index: i + 1,
          error: safeLogError(photoErr),
        });
        console.error(
          "Persist inline photo metadata error",
          JSON.stringify({
            request_id: requestID,
            support_id: supportID,
            analysis_id: analysisID,
            photo_index: i + 1,
            error: safeLogError(photoErr),
          }),
        );
        continue;
      }

      persistedPhotoPaths.push(storagePath);
    }
  }

  const uniqueRequestedPhotoPaths = [...new Set(requestedPhotoPaths)];
  if (uniqueRequestedPhotoPaths.length > 0) {
    const expectedPrefix = `${user.id}/${analysisID}/`;
    const { data: ownedPhotoRows, error: ownedPhotoErr } = await supabase
      .from("photos")
      .select("storage_path")
      .eq("analysis_id", analysisID)
      .eq("user_id", user.id)
      .in("storage_path", uniqueRequestedPhotoPaths);

    const ownedPaths = new Set(
      (ownedPhotoRows ?? []).map((row) => String(row.storage_path)),
    );
    const invalidPaths = uniqueRequestedPhotoPaths.filter((path) =>
      !path.startsWith(expectedPrefix) || !ownedPaths.has(path)
    );

    if (ownedPhotoErr || invalidPaths.length > 0) {
      console.warn(
        "Analyze photo ownership denied",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          user_hash: await hashedID(user.id),
          invalid_path_count: invalidPaths.length,
          error: ownedPhotoErr ? safeLogError(ownedPhotoErr) : null,
        }),
      );
      await updateOwnedAnalysis({
        status: "failed",
        status_message:
          `Fotoğraf bu analiz için doğrulanamadı. Destek kodu: ${supportID}`,
      });
      await releaseAnalysisQuota(supabase, analysisID, user.id);
      return errorResponse(403, "Fotoğraf bu analiz için doğrulanamadı.", {
        code: "photo_not_authorized",
        requestID,
        supportID,
      });
    }
  }

  for (const path of uniqueRequestedPhotoPaths) {
    const { data: fileData, error: storageErr } = await supabase.storage.from(
      "photos",
    ).download(path);
    if (storageErr || !fileData) {
      console.error(
        "Storage download error",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: storageErr
            ? safeLogError(storageErr)
            : { name: "empty_file_data" },
        }),
      );
      continue;
    }
    const buffer = await fileData.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    const base64 = btoa(binary);
    const mimeType = path.endsWith(".png") ? "image/png" : "image/jpeg";
    imageBase64Parts.push({ mimeType, data: base64 });
  }

  const validRequestedCanvases = requestedCanvases.filter((id) =>
    Boolean(CANVAS_FOCUS[id])
  );
  const resolvedCanvases = validRequestedCanvases.length > 0
    ? validRequestedCanvases
    : ["general"];
  const resolvedCanvasPrompts = resolvedCanvases
    .map((id) => ({ id, prompt: CANVAS_FOCUS[id] }))
    .filter((item) => Boolean(item.prompt));
  const systemPrompt = buildSystemPrompt(resolvedCanvases, planTier);
  const aiSimulation = aiSimulationConfig();
  const inputAudit: Record<string, unknown> = {
    input_mode: imageBase64Parts.length > 0 ? "photo" : "text",
    inline_photo_count: inlinePhotoCount,
    storage_photo_count: storagePhotoCount,
    persisted_photo_count: persistedPhotoPaths.length,
    persisted_photo_paths: persistedPhotoPaths,
    photo_persist_error_count: photoPersistErrors.length,
    photo_persist_errors: photoPersistErrors,
    gemini_image_part_count: imageBase64Parts.length,
    text_input_present: Boolean(text_input),
    user_prompt_present: Boolean(userPrompt),
    user_prompt: userPrompt,
    analysis_mode: analysisMode,
    user_plan: planTier,
    request_id: requestID,
    support_id: supportID,
    selected_canvas_ids: resolvedCanvases,
    resolved_canvas_prompts: resolvedCanvasPrompts,
    common_analysis_prompt: COMMON_ANALYSIS_PROMPT,
    pro_references_prompt: isPro ? PRO_REFERENCES_PROMPT : null,
    references_requested: isPro,
    response_schema_includes_references: isPro,
    system_prompt_sent: systemPrompt,
    model,
    gemini_key_aliases_available: geminiKeys.map((item) => item.alias),
    test_simulation_enabled: aiSimulation.enabled,
    test_simulation_mode: aiSimulation.enabled ? aiSimulation.mode : null,
  };

  // deno-lint-ignore no-explicit-any
  let geminiResult: any;
  let inputTokens = 0, outputTokens = 0;
  let aiError: string | null = null;
  let modelUsed = model;
  let apiKeyAlias: string | null = null;
  let attemptCount = 0;

  try {
    const out = await callGeminiWithFallback(
      geminiKeys,
      model,
      systemPrompt,
      text_input ?? null,
      userPrompt,
      imageBase64Parts,
      isPro,
      aiSimulation,
    );
    geminiResult = out.result;
    inputTokens = out.inputTokens;
    outputTokens = out.outputTokens;
    modelUsed = out.modelUsed;
    inputAudit.model = out.modelUsed;
    apiKeyAlias = out.apiKeyAlias;
    attemptCount = out.attempt;
    inputAudit.api_key_alias = apiKeyAlias;
    inputAudit.gemini_attempt_count = attemptCount;
  } catch (err) {
    aiError = String(err);
    const cleanError = userFacingAIError(err);
    await releaseAnalysisQuota(supabase, analysisID, user.id);
    await updateOwnedAnalysis({
      status: "failed",
      status_message: `${cleanError.message} Destek kodu: ${supportID}`,
      raw_ai_response: {
        _input_audit: inputAudit,
        _error: {
          message: aiError,
          code: cleanError.code,
          support_id: supportID,
          request_id: requestID,
        },
      },
    });
    await logUsage(supabase, {
      analysis_id: analysisID,
      user_id: user.id,
      provider: "gemini",
      model,
      tokens_in: 0,
      tokens_out: 0,
      duration_ms: Date.now() - startMs,
      error: aiError,
      user_plan: planTier,
      request_id: requestID,
      support_id: supportID,
      error_code: cleanError.code,
      http_status: cleanError.status,
      fallback_source: modelUsed === model ? null : modelUsed,
      api_key_alias: apiKeyAlias,
      attempt_count: attemptCount || null,
    });
    return errorResponse(cleanError.status, cleanError.message, {
      code: cleanError.code,
      requestID,
      supportID,
    });
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
    const fkF = clampFK(h.fk_frequency, FK_FREQUENCY_VALUES);
    const fkS = clampFK(h.fk_severity, FK_SEVERITY_VALUES);
    const fkSc = fkP * fkF * fkS;
    const fkB = fkBand(fkSc);
    const m5P = Math.max(1, Math.min(5, Math.round(h.m5_probability)));
    const m5S = Math.max(1, Math.min(5, Math.round(h.m5_severity)));
    const m5Sc = m5P * m5S;
    const m5B = m5Band(m5Sc);
    totalScoreFK += fkSc;
    totalScoreM5 += m5Sc;
    if (BAND_RANK[fkB] > BAND_RANK[highestBandFK]) highestBandFK = fkB;
    if (BAND_RANK[m5B] > BAND_RANK[highestBandM5]) highestBandM5 = m5B;
    return {
      analysis_id: analysisID,
      user_id: user.id,
      ordinal: i + 1,
      title: h.title,
      category: h.category ?? "",
      description: `${h.observed_evidence}\n\n${h.description}`.trim(),
      recommended_action: h.recommended_action,
      references_text: isPro ? h.references ?? "" : "",
      confidence: Math.max(0, Math.min(1, h.confidence)),
      fk_probability: fkP,
      fk_frequency: fkF,
      fk_severity: fkS,
      fk_band: fkB,
      m5_probability: m5P,
      m5_severity: m5S,
      m5_band: m5B,
    };
  });

  if (findingRows.length > 0) {
    const { error: findingsErr } = await supabase.from("findings").insert(
      findingRows,
    );
    if (findingsErr) {
      console.error(
        "Findings insert error",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogError(findingsErr),
        }),
      );
      await releaseAnalysisQuota(supabase, analysisID, user.id);
      await updateOwnedAnalysis({
        status: "failed",
        status_message: `Findings DB hatası. Destek kodu: ${supportID}`,
      });
      return errorResponse(500, "Bulgular kaydedilemedi.", {
        code: "findings_insert_failed",
        requestID,
        supportID,
      });
    }
  }

  await updateOwnedAnalysis({
    status: "completed",
    status_message: `Gemini ${modelUsed} · ${imageBase64Parts.length} foto · ${
      text_input ? "metin var" : "metin yok"
    } · ${supportID}`,
    completed_at: new Date().toISOString(),
    ai_summary: geminiResult.ai_summary,
    total_score_fk: totalScoreFK,
    total_score_m5: totalScoreM5,
    highest_band_fk: highestBandFK,
    highest_band_m5: highestBandM5,
    finding_count: findingRows.length,
    raw_ai_response: { ...geminiResult, _input_audit: inputAudit },
    ai_models_used: [modelUsed],
  });

  await completeAnalysisQuota(supabase, analysisID, user.id);

  await logUsage(supabase, {
    analysis_id: analysisID,
    user_id: user.id,
    provider: "gemini",
    model: modelUsed,
    tokens_in: inputTokens,
    tokens_out: outputTokens,
    duration_ms: Date.now() - startMs,
    error: null,
    user_plan: planTier,
    request_id: requestID,
    support_id: supportID,
    error_code: null,
    http_status: 200,
    fallback_source: [
      modelUsed !== model ? modelUsed : null,
      apiKeyAlias && apiKeyAlias !== "gemini_primary" ? apiKeyAlias : null,
    ].filter(Boolean).join(" -> ") || null,
    api_key_alias: apiKeyAlias,
    attempt_count: attemptCount || null,
  });

  return new Response(
    JSON.stringify({
      ok: true,
      finding_count: findingRows.length,
      request_id: requestID,
      support_id: supportID,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
