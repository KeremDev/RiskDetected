import { sendGeminiGenerateContent } from "../_shared/gemini-provider-client.ts";
import {
  retrieveOpenAIResponse,
  sendOpenAIResponse,
} from "../_shared/openai-provider-client.ts";
import {
  PHOTO_ANALYSIS_JSON_SCHEMA,
  PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
  type PhotoAnalysisV3,
} from "./contracts.ts";
import { parsePhotoAnalysisV3WithSalvage } from "./engine.ts";
import type { AnalysisServiceTier } from "../_shared/analysis-compute-profile.ts";
import type { OpenAIReasoningEffort } from "./compute-profile.ts";

export type ProviderName = "gemini" | "openai";

export type ProviderUsage = {
  inputTokens: number;
  outputTokens: number;
  reasoningTokens: number;
  cachedInputTokens: number;
  costUSD: number;
  standardEquivalentCostUSD: number;
};

export type ProviderCallResult = {
  output: PhotoAnalysisV3;
  provider: ProviderName;
  model: string;
  providerRequestID: string | null;
  httpStatus: number;
  durationMs: number;
  usage: ProviderUsage;
  requestedServiceTier: AnalysisServiceTier;
  effectiveServiceTier: AnalysisServiceTier;
};

export type OpenAIBackgroundProviderObservation =
  | {
    state: "pending";
    providerStatus: "queued" | "in_progress";
    providerRequestID: string;
    httpStatus: number;
    durationMs: number;
  }
  | {
    state: "completed";
    providerStatus: "completed";
    providerRequestID: string;
    result: ProviderCallResult;
  };

export class ProviderCallError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly provider: ProviderName,
    readonly model: string,
    readonly httpStatus: number | null,
    readonly durationMs: number,
    readonly schemaError = false,
    readonly usage?: ProviderUsage,
    readonly providerRequestID: string | null = null,
  ) {
    super(message);
  }
}

/**
 * Repairs the one syntax defect observed in production: a trailing comma
 * immediately before a JSON object/array close. It deliberately performs no
 * quote balancing, field insertion or semantic guessing. The ordinary schema
 * parser remains authoritative after syntax recovery.
 */
export function parseProviderStructuredJSON(
  jsonText: string,
  photoIndex: number,
): PhotoAnalysisV3 {
  let raw: unknown;
  let trailingCommaRepaired = false;
  try {
    raw = JSON.parse(jsonText);
  } catch (originalError) {
    const repairedText = jsonText.replace(/,\s*([}\]])/g, "$1");
    if (repairedText === jsonText) throw originalError;
    raw = JSON.parse(repairedText);
    trailingCommaRepaired = true;
  }
  const output = parsePhotoAnalysisV3WithSalvage(raw, photoIndex);
  if (!trailingCommaRepaired) return output;
  const diagnostics = output._schema_diagnostics_v1;
  output._schema_diagnostics_v1 = {
    salvaged: true,
    strict_error_code: diagnostics?.strict_error_code ??
      "provider_json_trailing_comma",
    raw_fact_count: diagnostics?.raw_fact_count ?? output.hazard_facts.length,
    valid_fact_count: diagnostics?.valid_fact_count ??
      output.hazard_facts.length,
    invalid_fact_count: diagnostics?.invalid_fact_count ?? 0,
    raw_signal_count: diagnostics?.raw_signal_count ??
      output.inspection_signals.length,
    invalid_signal_count: diagnostics?.invalid_signal_count ?? 0,
    missing_module_ids: diagnostics?.missing_module_ids ?? [],
    duplicate_module_ids: diagnostics?.duplicate_module_ids ?? [],
    reason_codes: [
      ...new Set([
        ...(diagnostics?.reason_codes ?? []),
        "json_trailing_comma_repaired",
      ]),
    ],
  };
  return output;
}

/**
 * Gemini's generateContent `responseSchema` field uses the OpenAPI Schema
 * enum representation (OBJECT, STRING, ...), while OpenAI accepts ordinary
 * JSON Schema type names. Keep the canonical contract provider-neutral and
 * translate only at the Gemini boundary.
 *
 * `additionalProperties` is enforced again by parsePhotoAnalysisV3. Omitting
 * it here keeps Gemini's serving schema smaller and avoids unsupported/complex
 * schema rejection without weakening the server-side contract.
 */
export function toGeminiResponseSchema(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(toGeminiResponseSchema);
  if (!value || typeof value !== "object") return value;
  const output: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value)) {
    if (key === "additionalProperties") continue;
    output[key] = key === "type" && typeof child === "string"
      ? child.toUpperCase()
      : toGeminiResponseSchema(child);
  }
  return output;
}

function nonNegative(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.round(parsed) : 0;
}

function parseJSONText(
  raw: string,
  provider: ProviderName,
  model: string,
  durationMs: number,
) {
  try {
    return JSON.parse(raw);
  } catch {
    throw new ProviderCallError(
      "Provider returned invalid JSON",
      "provider_json_invalid",
      provider,
      model,
      200,
      durationMs,
      true,
    );
  }
}

type GeminiTokenRates = {
  input: number;
  cachedInput: number;
  output: number;
};

function geminiTokenRates(model: string): GeminiTokenRates {
  const normalized = model.trim().toLowerCase();
  if (normalized.includes("2.5-flash-lite")) {
    return { input: 0.10, cachedInput: 0.01, output: 0.40 };
  }
  // vNext currently pins Gemini 2.5 Flash. Unknown Gemini models deliberately
  // use this conservative table until their rates are explicitly added.
  return { input: 0.30, cachedInput: 0.03, output: 2.50 };
}

export function geminiCost(
  model: string,
  serviceTier: AnalysisServiceTier,
  usage: Omit<ProviderUsage, "costUSD" | "standardEquivalentCostUSD">,
): number {
  const rates = geminiTokenRates(model);
  const input = Math.max(0, usage.inputTokens - usage.cachedInputTokens);
  const standardCost = (input * rates.input +
    usage.cachedInputTokens * rates.cachedInput +
    (usage.outputTokens + usage.reasoningTokens) * rates.output) / 1_000_000;
  return Number(
    (serviceTier === "flex" ? standardCost * 0.5 : standardCost).toFixed(8),
  );
}

export function openAICost(
  usage: Omit<ProviderUsage, "costUSD" | "standardEquivalentCostUSD">,
): number {
  const input = Math.max(0, usage.inputTokens - usage.cachedInputTokens);
  // ProviderUsage stores visible output and reasoning separately so Gemini and
  // OpenAI telemetry are directly comparable. Both are billed at output rate.
  return Number((
    (input * 0.20 + usage.cachedInputTokens * 0.02 +
      (usage.outputTokens + usage.reasoningTokens) * 1.20) /
    1_000_000
  ).toFixed(8));
}

async function callGemini(params: {
  apiKey: string;
  model: string;
  prompt: string;
  imageData: string;
  mimeType: string;
  photoIndex: number;
  timeoutMs: number;
  thinkingBudget: number;
  maxOutputTokens: number;
  serviceTier: AnalysisServiceTier;
  compactProviderContract: boolean;
}): Promise<ProviderCallResult> {
  const started = Date.now();
  let response: Response;
  try {
    response = await sendGeminiGenerateContent({
      apiKey: params.apiKey,
      model: params.model,
      timeoutMs: params.timeoutMs,
      body: {
        ...(params.serviceTier === "flex" ? { service_tier: "flex" } : {}),
        contents: [{
          role: "user",
          parts: [
            { text: params.prompt },
            {
              inlineData: { mimeType: params.mimeType, data: params.imageData },
            },
          ],
        }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: toGeminiResponseSchema(
            params.compactProviderContract
              ? PHOTO_ANALYSIS_JSON_SCHEMA
              : PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
          ),
          temperature: 0.15,
          maxOutputTokens: params.maxOutputTokens,
          thinkingConfig: { thinkingBudget: params.thinkingBudget },
          mediaResolution: "MEDIA_RESOLUTION_HIGH",
        },
      },
    });
  } catch (error) {
    const duration = Date.now() - started;
    const timeout = error instanceof DOMException &&
      error.name === "AbortError";
    throw new ProviderCallError(
      timeout ? "Gemini request timed out" : "Gemini transport failed",
      timeout ? "provider_timeout" : "provider_transport_error",
      "gemini",
      params.model,
      null,
      duration,
    );
  }
  const durationMs = Date.now() - started;
  const raw = await response.text();
  if (!response.ok) {
    throw new ProviderCallError(
      `Gemini HTTP ${response.status}: ${raw.slice(0, 500)}`,
      response.status === 429
        ? "provider_rate_limited"
        : response.status === 503
        ? "provider_unavailable"
        : "provider_http_error",
      "gemini",
      params.model,
      response.status,
      durationMs,
      response.status === 400 && /schema|responseSchema/i.test(raw),
    );
  }
  const envelope = parseJSONText(
    raw,
    "gemini",
    params.model,
    durationMs,
  ) as Record<string, unknown>;
  const usageMetadata = envelope.usageMetadata &&
      typeof envelope.usageMetadata === "object"
    ? envelope.usageMetadata as Record<string, unknown>
    : {};
  const baseUsage = {
    inputTokens: nonNegative(usageMetadata.promptTokenCount),
    outputTokens: nonNegative(usageMetadata.candidatesTokenCount),
    reasoningTokens: nonNegative(usageMetadata.thoughtsTokenCount),
    cachedInputTokens: nonNegative(usageMetadata.cachedContentTokenCount),
  };
  const serviceTierHeader = response.headers.get("x-gemini-service-tier")
    ?.trim().toLowerCase();
  const effectiveServiceTier: AnalysisServiceTier = serviceTierHeader === "flex"
    ? "flex"
    : serviceTierHeader === "standard"
    ? "standard"
    : params.serviceTier;
  const usage = {
    ...baseUsage,
    costUSD: geminiCost(params.model, effectiveServiceTier, baseUsage),
    standardEquivalentCostUSD: geminiCost(params.model, "standard", baseUsage),
  };
  const providerRequestID = response.headers.get("x-request-id") ??
    response.headers.get("x-goog-request-id");
  const candidates = Array.isArray(envelope.candidates)
    ? envelope.candidates
    : [];
  const candidate = candidates[0] as Record<string, unknown> | undefined;
  const content = candidate && typeof candidate.content === "object"
    ? candidate.content as Record<string, unknown>
    : null;
  const parts = Array.isArray(content?.parts) ? content?.parts : [];
  const jsonText = parts.flatMap((part) => {
    if (!part || typeof part !== "object") return [];
    const value = (part as Record<string, unknown>).text;
    return typeof value === "string" ? [value] : [];
  }).join("");
  if (!jsonText) {
    throw new ProviderCallError(
      "Gemini response had no structured text",
      "provider_output_missing",
      "gemini",
      params.model,
      response.status,
      durationMs,
      true,
      usage,
      providerRequestID,
    );
  }
  let output: PhotoAnalysisV3;
  try {
    output = parseProviderStructuredJSON(jsonText, params.photoIndex);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new ProviderCallError(
      detail,
      `provider_schema_invalid__${detail}`.slice(0, 160),
      "gemini",
      params.model,
      response.status,
      durationMs,
      true,
      usage,
      providerRequestID,
    );
  }
  return {
    output,
    provider: "gemini",
    model: params.model,
    providerRequestID,
    httpStatus: response.status,
    durationMs,
    usage,
    requestedServiceTier: params.serviceTier,
    effectiveServiceTier,
  };
}

function openAIOutputText(envelope: Record<string, unknown>): string {
  if (typeof envelope.output_text === "string") return envelope.output_text;
  const output = Array.isArray(envelope.output) ? envelope.output : [];
  return output.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const content = Array.isArray((item as Record<string, unknown>).content)
      ? (item as Record<string, unknown>).content as unknown[]
      : [];
    return content.flatMap((part) => {
      if (!part || typeof part !== "object") return [];
      const record = part as Record<string, unknown>;
      return record.type === "output_text" && typeof record.text === "string"
        ? [record.text]
        : [];
    });
  }).join("");
}

type OpenAIPhotoParams = {
  apiKey: string;
  model: string;
  prompt: string;
  imageData: string;
  mimeType: string;
  photoIndex: number;
  timeoutMs: number;
  reasoningEffort: OpenAIReasoningEffort;
  maxOutputTokens: number;
  compactProviderContract: boolean;
  fetchImpl?: typeof fetch;
};

function openAIPhotoRequestBody(
  params: OpenAIPhotoParams,
  background: boolean,
): Record<string, unknown> {
  return {
    model: params.model,
    // OpenAI background responses remain retrievable during their polling
    // window even with store=false. Do not extend retention for this
    // temporary Luna experiment.
    store: false,
    ...(background ? { background: true } : {}),
    reasoning: { effort: params.reasoningEffort },
    max_output_tokens: params.maxOutputTokens,
    input: [{
      role: "user",
      content: [
        { type: "input_text", text: params.prompt },
        {
          type: "input_image",
          image_url: `data:${params.mimeType};base64,${params.imageData}`,
          detail: "original",
        },
      ],
    }],
    text: {
      format: {
        type: "json_schema",
        name: params.compactProviderContract
          ? "riskdetected_photo_analysis_v3_5"
          : "riskdetected_photo_analysis_v3_4",
        strict: true,
        schema: params.compactProviderContract
          ? PHOTO_ANALYSIS_JSON_SCHEMA
          : PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
      },
    },
  };
}

function openAIHTTPError(
  response: Response,
  raw: string,
  model: string,
  durationMs: number,
): ProviderCallError {
  return new ProviderCallError(
    `OpenAI HTTP ${response.status}`,
    response.status === 429
      ? "provider_rate_limited"
      : response.status === 404
      ? "provider_background_response_not_found"
      : "provider_http_error",
    "openai",
    model,
    response.status,
    durationMs,
    response.status === 400 && /schema|format/i.test(raw),
  );
}

function completedOpenAIResult(params: {
  envelope: Record<string, unknown>;
  model: string;
  photoIndex: number;
  httpStatus: number;
  durationMs: number;
}): ProviderCallResult {
  const usageRecord = params.envelope.usage &&
      typeof params.envelope.usage === "object"
    ? params.envelope.usage as Record<string, unknown>
    : {};
  const inputDetails = usageRecord.input_tokens_details &&
      typeof usageRecord.input_tokens_details === "object"
    ? usageRecord.input_tokens_details as Record<string, unknown>
    : {};
  const outputDetails = usageRecord.output_tokens_details &&
      typeof usageRecord.output_tokens_details === "object"
    ? usageRecord.output_tokens_details as Record<string, unknown>
    : {};
  const reasoningTokens = nonNegative(outputDetails.reasoning_tokens);
  const totalOutputTokens = nonNegative(usageRecord.output_tokens);
  const baseUsage = {
    inputTokens: nonNegative(usageRecord.input_tokens),
    outputTokens: Math.max(0, totalOutputTokens - reasoningTokens),
    reasoningTokens,
    cachedInputTokens: nonNegative(inputDetails.cached_tokens),
  };
  const costUSD = openAICost(baseUsage);
  const usage = { ...baseUsage, costUSD, standardEquivalentCostUSD: costUSD };
  const providerRequestID = typeof params.envelope.id === "string"
    ? params.envelope.id
    : null;
  const responseText = openAIOutputText(params.envelope);
  if (!responseText) {
    throw new ProviderCallError(
      "OpenAI response had no structured text",
      "provider_output_missing",
      "openai",
      params.model,
      params.httpStatus,
      params.durationMs,
      true,
      usage,
      providerRequestID,
    );
  }
  let output: PhotoAnalysisV3;
  try {
    output = parseProviderStructuredJSON(responseText, params.photoIndex);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new ProviderCallError(
      detail,
      `provider_schema_invalid__${detail}`.slice(0, 160),
      "openai",
      params.model,
      params.httpStatus,
      params.durationMs,
      true,
      usage,
      providerRequestID,
    );
  }
  return {
    output,
    provider: "openai",
    model: params.model,
    providerRequestID,
    httpStatus: params.httpStatus,
    durationMs: params.durationMs,
    usage,
    requestedServiceTier: "standard",
    effectiveServiceTier: "standard",
  };
}

function observeOpenAIBackgroundEnvelope(params: {
  envelope: Record<string, unknown>;
  model: string;
  photoIndex: number;
  httpStatus: number;
  durationMs: number;
}): OpenAIBackgroundProviderObservation {
  const providerRequestID = typeof params.envelope.id === "string"
    ? params.envelope.id
    : "";
  if (!/^resp_[A-Za-z0-9_-]+$/.test(providerRequestID)) {
    throw new ProviderCallError(
      "OpenAI background response id missing",
      "provider_background_response_id_missing",
      "openai",
      params.model,
      params.httpStatus,
      params.durationMs,
      true,
    );
  }
  const status = String(params.envelope.status ?? "");
  if (status === "queued" || status === "in_progress") {
    return {
      state: "pending",
      providerStatus: status,
      providerRequestID,
      httpStatus: params.httpStatus,
      durationMs: params.durationMs,
    };
  }
  if (status === "completed") {
    return {
      state: "completed",
      providerStatus: "completed",
      providerRequestID,
      result: completedOpenAIResult({
        envelope: params.envelope,
        model: params.model,
        photoIndex: params.photoIndex,
        httpStatus: params.httpStatus,
        durationMs: params.durationMs,
      }),
    };
  }
  const terminalStatus = ["failed", "cancelled", "incomplete"].includes(
      status,
    )
    ? status
    : "invalid_status";
  throw new ProviderCallError(
    `OpenAI background response ended with ${terminalStatus}`,
    `provider_background_${terminalStatus}`,
    "openai",
    params.model,
    params.httpStatus,
    params.durationMs,
    false,
    undefined,
    providerRequestID,
  );
}

async function callOpenAI(
  params: OpenAIPhotoParams,
): Promise<ProviderCallResult> {
  const started = Date.now();
  let response: Response;
  try {
    response = await sendOpenAIResponse({
      apiKey: params.apiKey,
      timeoutMs: params.timeoutMs,
      body: openAIPhotoRequestBody(params, false),
    });
  } catch (error) {
    const duration = Date.now() - started;
    const timeout = error instanceof DOMException &&
      error.name === "AbortError";
    throw new ProviderCallError(
      timeout ? "OpenAI request timed out" : "OpenAI transport failed",
      timeout ? "provider_timeout" : "provider_transport_error",
      "openai",
      params.model,
      null,
      duration,
    );
  }
  const durationMs = Date.now() - started;
  const raw = await response.text();
  if (!response.ok) {
    throw new ProviderCallError(
      `OpenAI HTTP ${response.status}`,
      response.status === 429 ? "provider_rate_limited" : "provider_http_error",
      "openai",
      params.model,
      response.status,
      durationMs,
      response.status === 400 && /schema|format/i.test(raw),
    );
  }
  const envelope = parseJSONText(
    raw,
    "openai",
    params.model,
    durationMs,
  ) as Record<string, unknown>;
  return completedOpenAIResult({
    envelope,
    model: params.model,
    photoIndex: params.photoIndex,
    httpStatus: response.status,
    durationMs,
  });
}

export async function startOpenAIBackgroundPhotoProvider(
  params: OpenAIPhotoParams & { idempotencyKey: string },
): Promise<OpenAIBackgroundProviderObservation> {
  const started = Date.now();
  let response: Response;
  try {
    response = await sendOpenAIResponse({
      apiKey: params.apiKey,
      timeoutMs: params.timeoutMs,
      idempotencyKey: params.idempotencyKey,
      body: openAIPhotoRequestBody(params, true),
      fetchImpl: params.fetchImpl,
    });
  } catch (error) {
    const durationMs = Date.now() - started;
    const timeout = error instanceof DOMException &&
      error.name === "AbortError";
    throw new ProviderCallError(
      timeout
        ? "OpenAI background submission timed out"
        : "OpenAI background submission failed",
      timeout ? "provider_timeout" : "provider_transport_error",
      "openai",
      params.model,
      null,
      durationMs,
    );
  }
  const durationMs = Date.now() - started;
  const raw = await response.text();
  if (!response.ok) {
    throw openAIHTTPError(response, raw, params.model, durationMs);
  }
  const envelope = parseJSONText(
    raw,
    "openai",
    params.model,
    durationMs,
  ) as Record<string, unknown>;
  return observeOpenAIBackgroundEnvelope({
    envelope,
    model: params.model,
    photoIndex: params.photoIndex,
    httpStatus: response.status,
    durationMs,
  });
}

export async function pollOpenAIBackgroundPhotoProvider(params: {
  apiKey: string;
  responseID: string;
  model: string;
  photoIndex: number;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
}): Promise<OpenAIBackgroundProviderObservation> {
  const started = Date.now();
  let response: Response;
  try {
    response = await retrieveOpenAIResponse({
      apiKey: params.apiKey,
      responseID: params.responseID,
      timeoutMs: params.timeoutMs,
      fetchImpl: params.fetchImpl,
    });
  } catch (error) {
    const durationMs = Date.now() - started;
    const timeout = error instanceof DOMException &&
      error.name === "AbortError";
    throw new ProviderCallError(
      timeout
        ? "OpenAI background poll timed out"
        : "OpenAI background poll failed",
      timeout ? "provider_timeout" : "provider_transport_error",
      "openai",
      params.model,
      null,
      durationMs,
      false,
      undefined,
      params.responseID,
    );
  }
  const durationMs = Date.now() - started;
  const raw = await response.text();
  if (!response.ok) {
    const error = openAIHTTPError(response, raw, params.model, durationMs);
    throw new ProviderCallError(
      error.message,
      error.code,
      error.provider,
      error.model,
      error.httpStatus,
      error.durationMs,
      error.schemaError,
      error.usage,
      params.responseID,
    );
  }
  const envelope = parseJSONText(
    raw,
    "openai",
    params.model,
    durationMs,
  ) as Record<string, unknown>;
  return observeOpenAIBackgroundEnvelope({
    envelope,
    model: params.model,
    photoIndex: params.photoIndex,
    httpStatus: response.status,
    durationMs,
  });
}

export async function callPhotoProvider(params: {
  provider: ProviderName;
  apiKey: string;
  model: string;
  prompt: string;
  imageData: string;
  mimeType: string;
  photoIndex: number;
  timeoutMs: number;
  geminiThinkingBudget: number;
  maxOutputTokens: number;
  openAIReasoningEffort: OpenAIReasoningEffort;
  serviceTier: AnalysisServiceTier;
  compactProviderContract: boolean;
}): Promise<ProviderCallResult> {
  if (params.provider === "openai") {
    return await callOpenAI({
      apiKey: params.apiKey,
      model: params.model,
      prompt: params.prompt,
      imageData: params.imageData,
      mimeType: params.mimeType,
      photoIndex: params.photoIndex,
      timeoutMs: params.timeoutMs,
      reasoningEffort: params.openAIReasoningEffort,
      maxOutputTokens: params.maxOutputTokens,
      compactProviderContract: params.compactProviderContract,
    });
  }
  return await callGemini({
    apiKey: params.apiKey,
    model: params.model,
    prompt: params.prompt,
    imageData: params.imageData,
    mimeType: params.mimeType,
    photoIndex: params.photoIndex,
    timeoutMs: params.timeoutMs,
    thinkingBudget: params.geminiThinkingBudget,
    maxOutputTokens: params.maxOutputTokens,
    serviceTier: params.serviceTier,
    compactProviderContract: params.compactProviderContract,
  });
}
