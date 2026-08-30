import type { AnalysisServiceTier } from "../_shared/analysis-compute-profile.ts";
import type { GeminiThinkingLevel } from "../analyze-vnext/compute-profile.ts";
import { sendGeminiGenerateContent } from "../_shared/gemini-provider-client.ts";
import { outputLanguageFailure } from "./language-contract.ts";
import {
  CORE_MODULE_IDS,
  DYNAMIC_MODULE_IDS,
  MODULE_OUTCOMES,
  type ProviderPhotoOutput,
  V4_PROVIDER_CONTRACT_VERSION,
  V4_PROVIDER_RESPONSE_SCHEMA,
  type V4ModuleID,
} from "./contracts.ts";
import { coverageValidationIssues } from "./dynamic-modules.ts";
import {
  V4_COVERAGE_REPAIR_COMMON,
  V4_GEMINI3_THRESHOLD_ADDENDUM,
} from "./prompt.ts";

export type V4ProviderUsage = {
  inputTokens: number;
  outputTokens: number;
  reasoningTokens: number;
  cachedInputTokens: number;
  costUSD: number;
  standardEquivalentCostUSD: number;
};

export type V4ProviderResult = {
  output: ProviderPhotoOutput;
  providerRequestID: string | null;
  durationMs: number;
  httpStatus: number;
  requestedServiceTier: AnalysisServiceTier;
  effectiveServiceTier: AnalysisServiceTier;
  usage: V4ProviderUsage;
};

export class V4ProviderError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly httpStatus: number | null,
    readonly durationMs: number,
    readonly retryable: boolean,
    readonly usage?: V4ProviderUsage,
    readonly providerRequestID?: string | null,
    readonly schemaIssues: readonly string[] = [],
    readonly recoverableOutput: ProviderPhotoOutput | null = null,
    readonly effectiveServiceTier: AnalysisServiceTier | null = null,
  ) {
    super(message);
  }
}

class V4CoverageContractError extends Error {
  constructor(
    readonly output: ProviderPhotoOutput,
    readonly issues: readonly string[],
  ) {
    super(`provider_critical_coverage_incomplete:${issues.join(",")}`);
  }
}

export function buildCoverageRepairPrompt(
  basePrompt: string,
  issues: readonly string[],
  requiredModules: readonly V4ModuleID[],
): string {
  const boundedIssues = [...new Set(issues)].slice(0, 32);
  return `${basePrompt}

${V4_COVERAGE_REPAIR_COMMON.trim()}
- Zorunlu modüller: ${requiredModules.join(", ")}
- Düzeltilmesi gereken kapsam kodları: ${boundedIssues.join(", ")}`;
}

function count(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.round(parsed) : 0;
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function structuredText(envelope: Record<string, unknown>): string {
  const candidate = Array.isArray(envelope.candidates)
    ? object(envelope.candidates[0])
    : {};
  const content = object(candidate.content);
  const parts = Array.isArray(content.parts) ? content.parts : [];
  return parts.flatMap((part) => {
    const text = object(part).text;
    return typeof text === "string" ? [text] : [];
  }).join("");
}

function toGeminiResponseSchema(value: unknown): unknown {
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

function geminiCost(
  model: string,
  serviceTier: AnalysisServiceTier,
  usage: Omit<V4ProviderUsage, "costUSD" | "standardEquivalentCostUSD">,
): number {
  // Named per family rather than by a single "lite" substring: "Lite" stopped
  // meaning cheap at Gemini 3. gemini-3.5-flash-lite lists at the same $0.30 /
  // $2.50 as 2.5 Flash, so a switch to it is a quality and latency decision,
  // not a cost saving -- and gemini-3.5-flash is five times the input price.
  // Matching on "2.5-flash-lite" alone would have priced all three the same.
  const name = model.trim().toLowerCase();
  // gemini-3.7-flash launched on introductory rates that double on 2027-01-01.
  // A hardcoded 0.75 would keep reporting half the real cost from that morning
  // onward, silently and on every run, so the date decides.
  const introOver = Date.now() >= Date.parse("2027-01-01T00:00:00Z");
  const rates = name.includes("2.5-flash-lite")
    ? { input: 0.10, cachedInput: 0.01, output: 0.40 }
    : name.includes("3.5-flash-lite")
    ? { input: 0.30, cachedInput: 0.03, output: 2.50 }
    : name.includes("3.7-flash")
    ? (introOver
      ? { input: 1.50, cachedInput: 0.15, output: 7.50 }
      : { input: 0.75, cachedInput: 0.075, output: 3.75 })
    : name.includes("3.5-flash")
    ? { input: 1.50, cachedInput: 0.15, output: 9.00 }
    : { input: 0.30, cachedInput: 0.03, output: 2.50 };
  const uncachedInput = Math.max(
    0,
    usage.inputTokens - usage.cachedInputTokens,
  );
  const standardCost = (uncachedInput * rates.input +
    usage.cachedInputTokens * rates.cachedInput +
    (usage.outputTokens + usage.reasoningTokens) * rates.output) / 1_000_000;
  return Number(
    (serviceTier === "flex" ? standardCost * 0.5 : standardCost).toFixed(8),
  );
}

function parseOutput(
  text: string,
  requiredModules: readonly V4ModuleID[],
  skipCoverageContract = false,
): ProviderPhotoOutput {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    const repaired = text.replace(/,\s*([}\]])/g, "$1");
    raw = JSON.parse(repaired);
  }
  const record = object(raw);
  if (record.contract_version !== V4_PROVIDER_CONTRACT_VERSION) {
    throw new Error("provider_contract_version_invalid");
  }
  for (
    const key of [
      "scene_entities",
      "people",
      "accessible_regions",
      "energy_sources",
      "candidates",
      "positive_controls",
      "module_coverage",
      "untrusted_embedded_text",
    ]
  ) {
    if (!Array.isArray(record[key])) {
      throw new Error(`provider_array_missing:${key}`);
    }
  }
  const output = record as unknown as ProviderPhotoOutput;
  const moduleIDs = new Set([...CORE_MODULE_IDS, ...DYNAMIC_MODULE_IDS]);
  const finiteUnit = (value: unknown) =>
    Number.isFinite(Number(value)) && Number(value) >= 0 && Number(value) <= 1;
  const validRegion = (value: unknown) => {
    if (value === undefined || value === null) return true;
    const region = object(value);
    return finiteUnit(region.x) && finiteUnit(region.y) &&
      finiteUnit(region.width) && finiteUnit(region.height) &&
      Number(region.width) > 0 && Number(region.height) > 0;
  };
  if (
    output.candidates.some((candidate) =>
      !candidate.candidate_key?.trim() || !moduleIDs.has(candidate.module_id) ||
      !Array.isArray(candidate.affirmative_cues) ||
      !Array.isArray(candidate.counter_cues) ||
      !["none", "partial", "substantial", "unknown"].includes(
        candidate.occlusion,
      ) ||
      !["ordinary", "serious", "permanent", "fatal"].includes(
        candidate.potential_consequence,
      ) ||
      typeof candidate.visually_resolvable !== "boolean" ||
      typeof candidate.requires_document_or_measurement !== "boolean" ||
      !candidate.event_path?.source?.trim() ||
      !candidate.event_path?.contact_or_failure?.trim() ||
      !candidate.event_path?.consequence?.trim() ||
      !finiteUnit(candidate.confidence?.visibility) ||
      !finiteUnit(candidate.confidence?.localization) ||
      !finiteUnit(candidate.confidence?.mechanism) ||
      !validRegion(candidate.evidence_region)
    )
  ) throw new Error("provider_candidate_invalid");
  if (
    new Set(output.candidates.map((candidate) => candidate.candidate_key))
      .size !==
      output.candidates.length
  ) throw new Error("provider_candidate_key_duplicate");
  if (
    output.positive_controls.some((control) =>
      !control.control_key?.trim() || !moduleIDs.has(control.module_id) ||
      !control.description?.trim() ||
      !Array.isArray(control.affirmative_cues) ||
      control.affirmative_cues.length === 0 ||
      !validRegion(control.evidence_region)
    )
  ) throw new Error("provider_positive_control_invalid");
  if (
    output.module_coverage.some((coverage) =>
      !moduleIDs.has(coverage.module_id) ||
      !MODULE_OUTCOMES.includes(coverage.outcome)
    )
  ) throw new Error("provider_coverage_enum_invalid");
  // expectedCoverageModules always unions Core-7, so an empty requiredModules
  // does not relax anything. The verification pass is a gap-finding second look
  // whose coverage matrix is never read -- the report is projected from the
  // primary pass -- so holding it to the coverage contract only throws away
  // otherwise valid answers. It cost one wasted call before this existed.
  if (!skipCoverageContract) {
    const coverageIssues = coverageValidationIssues(output, requiredModules);
    if (coverageIssues.length > 0) {
      throw new V4CoverageContractError(output, coverageIssues);
    }
  }
  return output;
}

/**
 * The prompt the model actually receives.
 *
 * Gemini 3 gets the threshold addendum appended; 2.5 gets exactly the bytes it
 * has always had, which is what keeps its measured baseline comparable. Applied
 * here rather than at the call sites so the primary pass, the coverage repair,
 * the targeted reinspection and the verification pass all agree -- a threshold
 * that held for one call and not the next would produce candidates the second
 * look then dropped.
 */
function promptFor(model: string, prompt: string): string {
  return isGemini3(model)
    ? `${prompt}\n${V4_GEMINI3_THRESHOLD_ADDENDUM}`
    : prompt;
}

/** Gemini 3 and later: the thinking enum, no temperature, ultra-high media. */
function isGemini3(model: string): boolean {
  return /gemini-3(?:\.|-)/u.test(model.trim().toLowerCase());
}

/**
 * Temperature is dropped on Gemini 3.
 *
 * Google's migration guidance is explicit that values below the default of 1.0
 * cause looping and degraded output on these models. We had 0.1 for
 * reproducibility, which was the right call on 2.5 and is the documented wrong
 * one here. Run-to-run variance is already a known property of this engine and
 * the routing gates are what contain it -- see the resolution floor.
 */
function geminiSamplingConfig(model: string): Record<string, unknown> {
  return isGemini3(model) ? {} : { temperature: 0.1 };
}

function geminiThinkingConfig(
  model: string,
  params: { thinkingBudget: number; thinkingLevel: GeminiThinkingLevel },
): Record<string, unknown> {
  // Sending both is a 400, so this is an either/or and never a merge.
  return {
    thinkingConfig: isGemini3(model)
      ? { thinkingLevel: params.thinkingLevel }
      : { thinkingBudget: params.thinkingBudget },
  };
}

/**
 * Media resolution, which on this workload matters more than thinking does.
 *
 * For images Gemini 3's default is 1120 tokens -- the same allocation as
 * `high`, so asking for high changes nothing. `ultra_high` is 2240 and is the
 * only setting that actually gives the model more of the picture. That is the
 * lever for the failure this engine keeps producing: a crane hook twelve pixels
 * across, whose latch no amount of reasoning can resolve because it was never
 * in the tensor. About three hundredths of a cent per analysis.
 *
 * ULTRA_HIGH is accepted **per part only**. Sending it in generationConfig is
 * rejected outright -- the first gemini-3.5-flash-lite run came back 400 in
 * forty-six milliseconds, before any inference. So Gemini 3 carries no global
 * setting at all and states the level next to the image instead, where the
 * enum is an object with a lowercase level. 2.5, which has no per-part form,
 * keeps the global field it always had.
 */
function globalMediaResolution(model: string): Record<string, unknown> {
  return isGemini3(model) ? {} : { mediaResolution: "MEDIA_RESOLUTION_HIGH" };
}

function imagePart(
  model: string,
  mimeType: string,
  data: string,
): Record<string, unknown> {
  return {
    inlineData: { mimeType, data },
    ...(isGemini3(model)
      ? { mediaResolution: { level: "media_resolution_ultra_high" } }
      : {}),
  };
}

export async function callV4Gemini(params: {
  apiKey: string;
  model: string;
  prompt: string;
  imageData: string;
  mimeType: string;
  timeoutMs: number;
  thinkingBudget: number;
  /** Used instead of the budget on Gemini 3; the two cannot both be sent. */
  thinkingLevel: GeminiThinkingLevel;
  maxOutputTokens: number;
  serviceTier: AnalysisServiceTier;
  requiredModules?: readonly V4ModuleID[];
  /** Set for calls whose module_coverage is never consumed. */
  skipCoverageContract?: boolean;
  /** Analysis output language. A mismatch is retryable, like a schema failure. */
  expectedLanguage?: string;
}): Promise<V4ProviderResult> {
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
            { text: promptFor(params.model, params.prompt) },
            imagePart(params.model, params.mimeType, params.imageData),
          ],
        }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: toGeminiResponseSchema(V4_PROVIDER_RESPONSE_SCHEMA),
          maxOutputTokens: params.maxOutputTokens,
          ...geminiSamplingConfig(params.model),
          ...geminiThinkingConfig(params.model, params),
          ...globalMediaResolution(params.model),
        },
      },
    });
  } catch (error) {
    throw new V4ProviderError(
      error instanceof Error ? error.message : "Gemini transport failed",
      "provider_transport_error",
      null,
      Date.now() - started,
      true,
    );
  }
  const durationMs = Date.now() - started;
  const body = await response.text();
  const requestID = response.headers.get("x-request-id") ??
    response.headers.get("x-goog-request-id");
  if (!response.ok) {
    throw new V4ProviderError(
      `Gemini HTTP ${response.status}: ${body.slice(0, 300)}`,
      response.status === 429
        ? "provider_rate_limited"
        : response.status === 503
        ? "provider_unavailable"
        : "provider_http_error",
      response.status,
      durationMs,
      response.status === 429 || response.status >= 500,
      undefined,
      requestID,
    );
  }
  const envelope = object(JSON.parse(body));
  const metadata = object(envelope.usageMetadata);
  // Google reports the prompt split by modality, and it is the only way to tell
  // whether a media_resolution setting actually applied: an image is 1120
  // tokens at Gemini 3's default and 2240 at ultra_high. Without this the two
  // are indistinguishable from the total, because a model change moves the text
  // tokens at the same time -- which is exactly how the first flash-lite run
  // left us unable to say whether the per-part field had been honoured or
  // silently dropped.
  const imageTokens = (Array.isArray(metadata.promptTokensDetails)
    ? metadata.promptTokensDetails
    : [])
    .map(object)
    .filter((entry) => String(entry.modality ?? "").toUpperCase() === "IMAGE")
    .reduce((total, entry) => total + count(entry.tokenCount), 0);
  // finishReason separates a model that broke the contract from one that was
  // cut off mid-JSON. Both surface as provider_schema_invalid, and the
  // gemini-3.7-flash trial hit that twice with no way to tell which -- the
  // arithmetic said there was budget left, but thinking tokens can count
  // against maxOutputTokens and arithmetic is not evidence.
  const finishReason = String(
    object(
      Array.isArray(envelope.candidates) ? envelope.candidates[0] : {},
    ).finishReason ?? "",
  );
  console.log(
    "v4 gemini usage",
    JSON.stringify({
      model: params.model,
      prompt_tokens: count(metadata.promptTokenCount),
      image_tokens: imageTokens,
      output_tokens: count(metadata.candidatesTokenCount),
      thoughts_tokens: count(metadata.thoughtsTokenCount),
      max_output_tokens: params.maxOutputTokens,
      finish_reason: finishReason,
    }),
  );
  const baseUsage = {
    inputTokens: count(metadata.promptTokenCount),
    outputTokens: count(metadata.candidatesTokenCount),
    reasoningTokens: count(metadata.thoughtsTokenCount),
    cachedInputTokens: count(metadata.cachedContentTokenCount),
  };
  const header = response.headers.get("x-gemini-service-tier")?.toLowerCase();
  const effectiveServiceTier: AnalysisServiceTier = header === "flex"
    ? "flex"
    : header === "standard"
    ? "standard"
    : params.serviceTier;
  const usage: V4ProviderUsage = {
    ...baseUsage,
    costUSD: geminiCost(params.model, effectiveServiceTier, baseUsage),
    standardEquivalentCostUSD: geminiCost(params.model, "standard", baseUsage),
  };
  const text = structuredText(envelope);
  if (!text) {
    throw new V4ProviderError(
      "Provider output missing",
      "provider_output_missing",
      200,
      durationMs,
      true,
      usage,
      requestID,
    );
  }
  try {
    const parsed = parseOutput(
      text,
      params.requiredModules ?? CORE_MODULE_IDS,
      params.skipCoverageContract === true,
    );
    // The output contract covers the language too. Treated like a schema
    // failure so the existing retry path re-asks rather than publishing an
    // English report to a Turkish reader.
    const languageFailure = outputLanguageFailure(
      parsed,
      params.expectedLanguage ?? "",
    );
    if (languageFailure) {
      throw new V4ProviderError(
        languageFailure,
        "provider_output_language_invalid",
        response.status,
        durationMs,
        true,
        usage,
        requestID,
        [],
        null,
        effectiveServiceTier,
      );
    }
    return {
      output: parsed,
      providerRequestID: requestID,
      durationMs,
      httpStatus: response.status,
      requestedServiceTier: params.serviceTier,
      effectiveServiceTier,
      usage,
    };
  } catch (error) {
    // Already shaped and classified; re-wrapping it as a schema failure would
    // lose the language code the retry path keys on.
    if (error instanceof V4ProviderError) throw error;
    const coverageError = error instanceof V4CoverageContractError
      ? error
      : null;
    throw new V4ProviderError(
      error instanceof Error ? error.message : "provider_schema_invalid",
      "provider_schema_invalid",
      response.status,
      durationMs,
      true,
      usage,
      requestID,
      coverageError?.issues ?? [],
      coverageError?.output ?? null,
      effectiveServiceTier,
    );
  }
}
