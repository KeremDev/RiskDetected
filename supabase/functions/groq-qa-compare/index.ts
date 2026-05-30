// deno-lint-ignore-file no-explicit-any no-import-prefix
/**
 * groq-qa-compare — admin-only QA runner for comparing Groq against existing
 * Gemini analysis prompts/photos without touching production quota or findings.
 *
 * POST body:
 *   free_analysis_id: string
 *   pro_analysis_id : string
 *
 * Security:
 *   Requires header `x-qa-secret` to match `GROQ_QA_SECRET`.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions";
const DEFAULT_GROQ_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct";
const PHOTOS_BUCKET = "photos";
const MAX_ANALYSIS_PHOTOS = 5;
const MAX_PHOTO_BYTES = 4 * 1024 * 1024;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-qa-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const FK_PROBABILITY_VALUES = [0.2, 0.5, 1, 3, 6, 10];
const FK_FREQUENCY_VALUES = [0.5, 1, 2, 3, 6, 10];
const FK_SEVERITY_VALUES = [1, 3, 7, 15, 40, 100];

type CompareRequest = {
  free_analysis_id?: string;
  pro_analysis_id?: string;
};

type PlanTier = "free" | "pro";

type GroqRunInput = {
  label: PlanTier;
  analysisID: string;
  apiKey: string;
  model: string;
};

type ImagePart = {
  mimeType: string;
  data: string;
  byteSize: number;
  storagePath: string;
};

type AnalysisAudit = {
  system_prompt_sent?: string;
  selected_canvas_ids?: string[];
  resolved_canvas_prompts?: Array<{ id?: string; prompt?: string }>;
  analysis_mode?: string;
  input_mode?: string;
  user_plan?: string;
  references_requested?: boolean;
};

type ExistingAnalysis = {
  id: string;
  user_id: string;
  title: string | null;
  created_at: string | null;
  raw_ai_response: Record<string, unknown> | null;
};

type ExistingPhoto = {
  storage_path: string;
  mime_type: string | null;
  width: number | null;
  height: number | null;
};

class GroqAPIError extends Error {
  status: number;
  body: string;

  constructor(status: number, body: string) {
    super(`Groq HTTP ${status}`);
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
  if (error instanceof GroqAPIError) {
    return { name: "GroqAPIError", status: error.status };
  }
  if (error instanceof SyntaxError) return { name: "SyntaxError" };
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message
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

function groqResponseSchemaInstruction(isPro: boolean): string {
  const referencesField = isPro
    ? `,\n      "references": "kısa mevzuat referansı veya mevzuat karşılığı kontrol edilmeli"`
    : "";
  return `Aşağıdaki JSON yapısına birebir uy. Markdown, açıklama veya kod bloğu ekleme:
{
  "hazards": [
    {
      "title": "kısa tehlike başlığı",
      "category": "risk kategorisi",
      "observed_evidence": "görüntü/metinde görülen kanıt",
      "description": "riskin kısa açıklaması",
      "recommended_action": "kısa uygulanabilir önlem",
      "confidence": 0.0,
      "fk_probability": 1,
      "fk_frequency": 1,
      "fk_severity": 1,
      "m5_probability": 1,
      "m5_severity": 1${referencesField}
    }
  ],
  "ai_summary": "kısa özet",
  "limitations": "varsa belirsizlikler"
}`;
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
      references: typeof h.references === "string" ? h.references : "",
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

function auditFromAnalysis(analysis: ExistingAnalysis): AnalysisAudit {
  const raw = analysis.raw_ai_response ?? {};
  const audit = raw._input_audit;
  return audit && typeof audit === "object" ? audit as AnalysisAudit : {};
}

async function loadImages(
  supabase: any,
  analysisID: string,
): Promise<ImagePart[]> {
  const { data: photoRows, error } = await supabase
    .from("photos")
    .select("storage_path,mime_type,width,height")
    .eq("analysis_id", analysisID)
    .order("created_at", { ascending: true })
    .limit(MAX_ANALYSIS_PHOTOS);

  if (error) throw new Error(`photos query failed: ${error.message}`);
  const photos = (photoRows ?? []) as ExistingPhoto[];
  const images: ImagePart[] = [];

  for (const photo of photos) {
    const { data, error: downloadError } = await supabase.storage
      .from(PHOTOS_BUCKET)
      .download(photo.storage_path);
    if (downloadError || !data) {
      throw new Error(
        `photo download failed: ${photo.storage_path}`,
      );
    }

    const bytes = new Uint8Array(await data.arrayBuffer());
    if (bytes.byteLength > MAX_PHOTO_BYTES) {
      throw new Error(
        `photo too large for Groq QA: ${photo.storage_path}`,
      );
    }

    images.push({
      mimeType: normalizeMimeType(photo.mime_type),
      data: base64FromBytes(bytes),
      byteSize: bytes.byteLength,
      storagePath: photo.storage_path,
    });
  }

  return images;
}

async function callGroq(params: {
  apiKey: string;
  model: string;
  systemPrompt: string;
  images: ImagePart[];
  isPro: boolean;
}) {
  const content: unknown[] = [
    {
      type: "text",
      text: [
        groqResponseSchemaInstruction(params.isPro),
      ].filter(Boolean).join("\n\n"),
    },
  ];

  for (const image of params.images) {
    content.push({
      type: "image_url",
      image_url: {
        url: `data:${image.mimeType};base64,${image.data}`,
      },
    });
  }

  const startedAt = Date.now();
  const res = await fetch(GROQ_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${params.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: params.model,
      messages: [
        { role: "system", content: params.systemPrompt },
        { role: "user", content },
      ],
      response_format: { type: "json_object" },
      temperature: 0.2,
      max_completion_tokens: 6000,
    }),
  });

  const durationMs = Date.now() - startedAt;
  if (!res.ok) {
    throw new GroqAPIError(res.status, await res.text().catch(() => ""));
  }

  const json = await res.json();
  const text = json.choices?.[0]?.message?.content;
  if (!text) throw new Error("Groq response content is empty.");
  const parsed = JSON.parse(text);

  return {
    result: parsed,
    usage: {
      input_tokens: json.usage?.prompt_tokens ?? 0,
      output_tokens: json.usage?.completion_tokens ?? 0,
      total_tokens: json.usage?.total_tokens ?? 0,
      duration_ms: durationMs,
    },
  };
}

async function runComparison(
  supabase: any,
  input: GroqRunInput,
) {
  const { data: analysis, error } = await supabase
    .from("analyses")
    .select("id,user_id,title,created_at,raw_ai_response")
    .eq("id", input.analysisID)
    .maybeSingle();

  if (error) throw new Error(`analysis query failed: ${error.message}`);
  if (!analysis) throw new Error(`analysis not found: ${input.analysisID}`);

  const existing = analysis as ExistingAnalysis;
  const audit = auditFromAnalysis(existing);
  const systemPrompt = audit.system_prompt_sent;
  if (!systemPrompt) {
    throw new Error(`system prompt missing for analysis: ${input.analysisID}`);
  }

  const images = await loadImages(supabase, input.analysisID);
  if (images.length === 0) {
    throw new Error(`analysis has no persisted photos: ${input.analysisID}`);
  }

  const groq = await callGroq({
    apiKey: input.apiKey,
    model: input.model,
    systemPrompt,
    images,
    isPro: input.label === "pro",
  });
  const normalized = normalizedFindings(groq.result?.hazards);

  return {
    label: input.label,
    source_analysis: {
      id: existing.id,
      user_id: existing.user_id,
      title: existing.title,
      created_at: existing.created_at,
      selected_canvas_ids: audit.selected_canvas_ids ?? [],
      resolved_canvas_prompts: audit.resolved_canvas_prompts ?? [],
      analysis_mode: audit.analysis_mode ?? null,
      input_mode: audit.input_mode ?? null,
      original_user_plan: audit.user_plan ?? null,
      references_requested: audit.references_requested ?? false,
    },
    groq_run: {
      provider: "groq",
      model: input.model,
      key_alias: input.label === "free"
        ? "groq_free_primary"
        : "groq_plus_pro_primary",
      photo_count: images.length,
      photo_metadata: images.map((image) => ({
        storage_path: image.storagePath,
        mime_type: image.mimeType,
        byte_size: image.byteSize,
      })),
      usage: groq.usage,
      ai_summary: groq.result?.ai_summary ?? "",
      limitations: groq.result?.limitations ?? "",
      ...normalized,
      raw_result: groq.result,
    },
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const qaSecret = Deno.env.get("GROQ_QA_SECRET")?.trim();
  if (!qaSecret) {
    return json(503, {
      error: "qa_secret_not_configured",
      message: "GROQ_QA_SECRET tanımlı değil.",
    });
  }

  if (req.headers.get("x-qa-secret") !== qaSecret) {
    return json(403, { error: "forbidden" });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const freeGroqKey = Deno.env.get("GROQ_API_KEY_FREE") ??
    Deno.env.get("GROQ_API_KEY");
  const plusProGroqKey = Deno.env.get("GROQ_API_KEY_PLUS_PRO") ??
    Deno.env.get("GROQ_API_KEY_PAID");
  const freeModel = Deno.env.get("GROQ_FREE_MODEL")?.trim() ||
    DEFAULT_GROQ_MODEL;
  const plusProModel = Deno.env.get("GROQ_PLUS_PRO_MODEL")?.trim() ||
    Deno.env.get("GROQ_PAID_MODEL")?.trim() ||
    DEFAULT_GROQ_MODEL;

  if (!supabaseURL || !serviceRoleKey || !freeGroqKey || !plusProGroqKey) {
    return json(503, {
      error: "qa_runner_not_configured",
      message:
        "SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GROQ_API_KEY_FREE ve GROQ_API_KEY_PLUS_PRO gerekli.",
    });
  }

  let body: CompareRequest;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const freeAnalysisID = cleanID(body.free_analysis_id);
  const proAnalysisID = cleanID(body.pro_analysis_id);
  if (!freeAnalysisID || !proAnalysisID) {
    return json(400, {
      error: "missing_analysis_ids",
      message: "free_analysis_id ve pro_analysis_id gerekli.",
    });
  }

  const startedAt = Date.now();
  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  try {
    const [freeResult, proResult] = await Promise.all([
      runComparison(supabase, {
        label: "free",
        analysisID: freeAnalysisID,
        apiKey: freeGroqKey,
        model: freeModel,
      }),
      runComparison(supabase, {
        label: "pro",
        analysisID: proAnalysisID,
        apiKey: plusProGroqKey,
        model: plusProModel,
      }),
    ]);

    return json(200, {
      ok: true,
      runner: "groq-qa-compare",
      duration_ms: Date.now() - startedAt,
      results: {
        free: freeResult,
        pro: proResult,
      },
    });
  } catch (error) {
    console.error("groq qa compare failed", JSON.stringify(safeLogError(error)));
    return json(500, {
      error: "groq_qa_compare_failed",
      details: safeLogError(error),
    });
  }
});
