/**
 * analyze-vnext — clean-room, photo-fanout risk analysis worker.
 *
 * This endpoint is service-role worker-only. The existing mobile request and
 * public findings response remain backward-compatible through the legacy
 * enqueue endpoint and finalize_analysis_result_v3.
 */
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  buildEngineProduct,
  constrainTargetedFactsWithTrace,
  inspectionSignalIDsEquivalent,
  parsePhotoAnalysisV3,
  parsePhotoAnalysisV3WithSalvage,
  type PhotoResult,
  selectTargetedDecision,
  selectTargetedSignal,
  targetedSourceFacts,
  targetedSourceSignals,
} from "./engine.ts";
import { buildPrimaryPhotoPrompt, buildTargetedPrompt } from "./prompt.ts";
import {
  POLICY_VERSION,
  PROMPT_BUNDLE_POLICY_VERSION,
  PROMPT_BUNDLE_SHA256,
  PROMPT_VERSION,
} from "./contracts.ts";
import { sha256Text, verifyPromptBundleIntegrity } from "./prompt-integrity.ts";
import {
  callPhotoProvider,
  pollOpenAIBackgroundPhotoProvider,
  ProviderCallError,
  type ProviderCallResult,
  type ProviderName,
  startOpenAIBackgroundPhotoProvider,
} from "./provider.ts";
import {
  shouldRetrySameProvider,
  shouldUseEconomyStandardFallback,
  shouldUseFallbackProvider,
} from "./recovery-policy.ts";
import {
  resolveVNextSectorSelection,
  SECTOR_PROFILE_VERSION,
} from "./sector-profile.ts";
import {
  type ResolvedVNextConfig,
  resolveVNextConfig,
} from "./compute-profile.ts";
import type { AnalysisServiceTier } from "../_shared/analysis-compute-profile.ts";
import {
  fallbackProviderTimeoutMs,
  OPENAI_BACKGROUND_POLL_TIMEOUT_MS,
  OPENAI_BACKGROUND_SUBMIT_TIMEOUT_MS,
  primaryProviderAttemptLimit,
  primaryProviderTimeoutMs,
  retryProviderTimeoutMs,
  shouldUseOpenAILunaBackground,
  targetedProviderTimeoutMs,
} from "../_shared/provider-execution-policy.ts";
import { refreshTrainingCardSnapshot } from "../_shared/training-recommendations/snapshot.ts";
import { refreshApprovedNotebookAdvisories } from "../_shared/approved-notebook-advisory-snapshot.ts";

type JobBody = Record<string, unknown> & {
  analysis_id?: string;
  user_id?: string;
  photo_paths?: unknown[];
  __queue_msg_id?: number;
  __job_generation?: number;
  __worker_claim_token?: string;
  checkpoint_only_refinalize?: boolean;
};

type PhotoInput = {
  photoID: string | null;
  photoIndex: number;
  storagePath: string;
  mimeType: string;
  base64: string;
};

type TargetedCheckpoint = {
  signalID: string;
  photoIndex: number;
  status: "confirmed" | "rejected" | "failed";
  output: unknown | null;
};

type Config = ResolvedVNextConfig;

type ProviderAttemptKind =
  | "primary"
  | "technical_retry"
  | "schema_repair"
  | "provider_fallback"
  | "targeted_reinspection";

type ProviderAttemptBudgetTrace = {
  attempt_id: string;
  photo_index: number;
  attempt_kind: ProviderAttemptKind;
  attempt_number: number;
  state: "received" | "failed";
  provider: ProviderName;
  model: string;
  input_tokens: number;
  output_tokens: number;
  reasoning_tokens: number;
  generated_tokens: number;
  max_output_tokens: number;
  visible_output_budget_used_pct: number;
  generated_output_budget_used_pct: number;
  output_budget_used_pct: number;
  budget_remaining_tokens: number;
  reason_code: string | null;
  error_code: string | null;
  prompt_sha256: string;
  prompt_bundle_sha256: string;
};

type OpenAIBackgroundCheckpoint = {
  backgroundID: string;
  attemptID: string;
  attemptNumber: number;
  providerRequestID: string | null;
  providerStatus: string;
  submittedAt: string | null;
  expiresAt: string | null;
  created: boolean;
  errorCode: string | null;
};

class ProviderBackgroundPendingError extends Error {
  readonly code = "provider_background_pending";

  constructor(
    readonly retryAfterSeconds: number,
    readonly providerStatus: string,
    readonly providerRequestID: string | null,
  ) {
    super("OpenAI Luna background response is still processing");
  }
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function safeText(value: unknown, max = 200): string {
  return String(value ?? "").replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .slice(0, max);
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function strings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map((item) => typeof item === "string" ? item.trim() : "").filter(
      Boolean,
    )
    : [];
}

const TARGETED_COMPONENT_CONTEXT =
  /(?:pim|pin|segman|retainer|mandal|latch|kanca|hook|mafsal|joint|hortum|hose|boru|pipe|flanş|flans|flange|kaynak|weld|cıvata|civata|bolt|koruyucu|guard|korkuluk|rail|midrail|ara korkuluk|orta korkuluk|toe board|toeboard|kick plate|etek sacı|etek tahtası|etek elemanı|topuk levhası|süpürgelik|şev|sev|slope|zemin|ground|palet|track)/iu;

const TARGETED_COMPONENT_SEMANTIC_FAMILIES = [
  /(?:kanca|hook|mandal|latch)/iu,
  /(?:pim|pin|segman|retainer)/iu,
  /(?:palet|track|şasi|sasi|chassis|undercarriage)/iu,
  /(?:koruyucu|guard|korkuluk|rail|midrail|ara korkuluk|orta korkuluk|toe board|toeboard|kick plate|etek sacı|etek tahtası|etek elemanı|topuk levhası|süpürgelik)/iu,
  /(?:hortum|hose|boru|pipe|flanş|flans|flange)/iu,
  /(?:şev|sev|slope|zemin|ground|stabil)/iu,
];

function targetedComponentSemanticallyMatches(
  signalText: string,
  componentText: string,
): boolean {
  return TARGETED_COMPONENT_SEMANTIC_FAMILIES.some((family) =>
    family.test(signalText) && family.test(componentText)
  );
}

function targetedSignalContext(
  photoResults: PhotoResult[],
  signal: ReturnType<typeof selectTargetedSignal>,
): Record<string, unknown> {
  if (!signal) return {};
  const source = photoResults.find((result) =>
    result.photoIndex === signal.photo_index
  );
  const selectedFacts = targetedSourceFacts(photoResults, signal);
  const selectedSignals = targetedSourceSignals(photoResults, signal);
  const selectedFact = selectedFacts[0] ?? null;
  const relatedComponents = (source?.output.scene_inventory ?? [])
    .filter((item) =>
      selectedFacts.length > 0
        ? selectedFacts.some((target) =>
          item.entity_ref === target.entity.entity_ref ||
          (item.equipment_family === target.entity.equipment_family &&
            item.component === target.entity.component)
        )
        : TARGETED_COMPONENT_CONTEXT.test(
          `${item.equipment_family} ${item.component} ${item.visible_condition_summary}`,
        ) && signal.affirmative_cues.some((cue) =>
          cue.toLocaleLowerCase("tr-TR").includes(
            item.component.toLocaleLowerCase("tr-TR"),
          ) || targetedComponentSemanticallyMatches(
            cue,
            `${item.equipment_family} ${item.component} ${item.visible_condition_summary}`,
          )
        )
    )
    .slice(0, 8)
    .map((item) => ({
      entity_ref: item.entity_ref,
      equipment_family: item.equipment_family,
      component: item.component,
      visible_condition_summary: item.visible_condition_summary,
    }));
  return {
    ...signal as unknown as Record<string, unknown>,
    selected_targets: selectedFacts.map((target) => ({
      fact_id: target.fact_id,
      entity_ref: target.entity.entity_ref,
      equipment_family: target.entity.equipment_family,
      component: target.entity.component,
      condition_code: target.observed_condition.condition_code,
      mechanism_code: target.mechanism_code,
      evidence_region: target.evidence.normalized_region,
    })),
    selected_target: selectedFact
      ? {
        fact_id: selectedFact.fact_id,
        entity_ref: selectedFact.entity.entity_ref,
        equipment_family: selectedFact.entity.equipment_family,
        component: selectedFact.entity.component,
        condition_code: selectedFact.observed_condition.condition_code,
        mechanism_code: selectedFact.mechanism_code,
      }
      : null,
    selected_signal_targets: selectedSignals.map((target) => ({
      signal_id: target.signal_id,
      evidence_region: target.evidence_region,
      affirmative_cues: target.affirmative_cues,
      reason_code: target.reason_code,
    })),
    related_components: relatedComponents,
  };
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

async function sha256(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function budgetPercent(tokens: number, maximum: number): number {
  return maximum > 0 ? Math.round(1000 * tokens / maximum) / 10 : 0;
}

function providerAttemptBudgetTrace(params: {
  attemptID: string;
  photoIndex: number;
  kind: ProviderAttemptKind;
  attemptNumber: number;
  provider: ProviderName;
  model: string;
  config: Config;
  promptHash: string;
  result?: ProviderCallResult;
  error?: ProviderCallError;
}): ProviderAttemptBudgetTrace {
  const usage = params.result?.usage ?? params.error?.usage;
  const input = Math.max(0, usage?.inputTokens ?? 0);
  const output = Math.max(0, usage?.outputTokens ?? 0);
  const reasoning = Math.max(0, usage?.reasoningTokens ?? 0);
  const generated = output + reasoning;
  const maximum = Math.max(0, params.config.maxProviderOutputTokens);
  const generatedPct = budgetPercent(generated, maximum);
  const exhausted = Boolean(
    params.error?.schemaError && maximum > 0 &&
      (generated >= maximum - 32 || generatedPct >= 99.5),
  );
  return {
    attempt_id: params.attemptID,
    photo_index: params.photoIndex,
    attempt_kind: params.kind,
    attempt_number: params.attemptNumber,
    state: params.error ? "failed" : "received",
    provider: params.provider,
    model: params.model,
    input_tokens: input,
    output_tokens: output,
    reasoning_tokens: reasoning,
    generated_tokens: generated,
    max_output_tokens: maximum,
    visible_output_budget_used_pct: budgetPercent(output, maximum),
    generated_output_budget_used_pct: generatedPct,
    // Backward-compatible field name now reflects Gemini's real combined
    // generation budget instead of visible output alone.
    output_budget_used_pct: generatedPct,
    budget_remaining_tokens: Math.max(0, maximum - generated),
    reason_code: exhausted
      ? "output_cap_exhausted"
      : generatedPct >= 95
      ? "output_budget_near_limit"
      : null,
    error_code: params.error?.code ?? null,
    prompt_sha256: params.promptHash,
    prompt_bundle_sha256: PROMPT_BUNDLE_SHA256,
  };
}

function providerKey(provider: ProviderName): string | null {
  if (provider === "openai") return Deno.env.get("OPENAI_API_KEY") ?? null;
  // Both vNext profiles use paid Gemini service. Product entitlement no longer
  // decides which API pool is used.
  return Deno.env.get("GEMINI_API_KEY_PAID") ??
    Deno.env.get("GEMINI_PAID_API_KEY") ?? null;
}

async function recordAttempt(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  params: {
    attemptID: string;
    userID: string;
    engineRunID: string;
    photoRunID: string | null;
    kind: string;
    number: number;
    provider: ProviderName;
    model: string;
    state: string;
    result?: ProviderCallResult;
    error?: ProviderCallError;
    config?: Config;
    requestedServiceTier?: AnalysisServiceTier;
    serviceTierFallbackReason?: string | null;
    promptHash?: string | null;
    promptBundleHash?: string | null;
    maxOutputTokens?: number | null;
  },
) {
  try {
    const result = params.result;
    const error = params.error;
    const commonPayload = {
      p_attempt_id: params.attemptID,
      p_user_id: params.userID,
      p_engine_run_id: params.engineRunID,
      p_photo_run_id: params.photoRunID,
      p_attempt_kind: params.kind,
      p_attempt_number: params.number,
      p_provider: params.provider,
      p_model: params.model,
      p_state: params.state,
      p_provider_request_id: result?.providerRequestID ??
        error?.providerRequestID ?? null,
      p_input_tokens: result?.usage.inputTokens ??
        error?.usage?.inputTokens ?? 0,
      p_output_tokens: result?.usage.outputTokens ??
        error?.usage?.outputTokens ?? 0,
      p_reasoning_tokens: result?.usage.reasoningTokens ??
        error?.usage?.reasoningTokens ?? 0,
      p_cached_input_tokens: result?.usage.cachedInputTokens ??
        error?.usage?.cachedInputTokens ?? 0,
      p_cost_usd: result?.usage.costUSD ?? error?.usage?.costUSD ?? 0,
      p_duration_ms: result?.durationMs ?? error?.durationMs ?? null,
      p_http_status: result?.httpStatus ?? error?.httpStatus ?? null,
      p_error_code: error?.code ??
        (result?.output._schema_diagnostics_v1?.salvaged
          ? "provider_schema_salvaged"
          : null),
    };
    const v5 = await supabase.rpc(
      "record_analysis_provider_attempt_v5",
      {
        ...commonPayload,
        p_compute_profile: params.config?.computeProfile ?? null,
        p_provider_pool: params.config?.providerPool ?? null,
        p_requested_service_tier: result?.requestedServiceTier ??
          params.requestedServiceTier ?? null,
        p_effective_service_tier: result?.effectiveServiceTier ?? null,
        p_standard_equivalent_cost_usd:
          result?.usage.standardEquivalentCostUSD ??
            error?.usage?.standardEquivalentCostUSD ?? 0,
        p_service_tier_fallback_reason: params.serviceTierFallbackReason ??
          null,
        p_prompt_sha256: params.promptHash ?? null,
        p_prompt_bundle_sha256: params.promptBundleHash ??
          PROMPT_BUNDLE_SHA256,
        p_max_output_tokens: params.maxOutputTokens ??
          params.config?.maxProviderOutputTokens ?? null,
      },
    );
    if (!v5.error && v5.data?.ok !== true) {
      console.warn(
        "vNext attempt telemetry v5 rejected",
        safeText(v5.data?.state ?? "unknown_state"),
      );
    }
    let rpcError = null;
    if (v5.error) {
      const v4 = await supabase.rpc(
        "record_analysis_provider_attempt_v4",
        {
          ...commonPayload,
          p_compute_profile: params.config?.computeProfile ?? null,
          p_provider_pool: params.config?.providerPool ?? null,
          p_requested_service_tier: result?.requestedServiceTier ??
            params.requestedServiceTier ?? null,
          p_effective_service_tier: result?.effectiveServiceTier ?? null,
          p_standard_equivalent_cost_usd:
            result?.usage.standardEquivalentCostUSD ??
              error?.usage?.standardEquivalentCostUSD ?? 0,
          p_service_tier_fallback_reason: params.serviceTierFallbackReason ??
            null,
        },
      );
      rpcError = v4.error
        ? (await supabase.rpc(
          "record_analysis_provider_attempt_v3",
          commonPayload,
        )).error
        : null;
    }
    if (rpcError) {
      console.warn(
        "vNext attempt telemetry skipped",
        safeText(rpcError.message),
      );
    }
  } catch (error) {
    console.warn("vNext attempt telemetry failed", safeText(error));
  }
}

async function checkpointPhoto(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  params: {
    userID: string;
    engineRunID: string;
    photo: PhotoInput;
    provider: ProviderName;
    model: string;
    status: "running" | "completed" | "failed";
    attemptCount: number;
    output?: unknown;
    result?: ProviderCallResult;
    errorCode?: string | null;
  },
): Promise<string> {
  const { data, error } = await supabase.rpc(
    "checkpoint_analysis_photo_run_v3",
    {
      p_user_id: params.userID,
      p_engine_run_id: params.engineRunID,
      p_photo_id: params.photo.photoID,
      p_photo_index: params.photo.photoIndex,
      p_storage_path: params.photo.storagePath,
      p_provider: params.provider,
      p_model: params.model,
      p_status: params.status,
      p_attempt_count: params.attemptCount,
      p_normalized_output: params.output ?? null,
      p_output_sha256: params.output ? await sha256(params.output) : null,
      p_input_tokens: params.result?.usage.inputTokens ?? 0,
      p_output_tokens: params.result?.usage.outputTokens ?? 0,
      p_reasoning_tokens: params.result?.usage.reasoningTokens ?? 0,
      p_cost_usd: params.result?.usage.costUSD ?? 0,
      p_duration_ms: params.result?.durationMs ?? null,
      p_error_code: params.errorCode ?? null,
    },
  );
  if (error || data?.ok !== true || typeof data?.photo_run_id !== "string") {
    throw new Error(
      `photo_checkpoint_failed:${safeText(error?.message ?? data?.state)}`,
    );
  }
  return data.photo_run_id;
}

async function loadTargetedCheckpoint(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userID: string,
  engineRunID: string,
): Promise<TargetedCheckpoint | null> {
  const { data, error } = await supabase.rpc(
    "get_analysis_targeted_run_v1",
    {
      p_user_id: userID,
      p_engine_run_id: engineRunID,
    },
  );
  if (error) {
    console.warn(
      "vNext targeted checkpoint read skipped",
      safeText(error.message),
    );
    return null;
  }
  if (data?.ok !== true || data?.state !== "found") return null;
  const status = String(data.status);
  if (!["confirmed", "rejected", "failed"].includes(status)) return null;
  return {
    signalID: String(data.signal_id ?? ""),
    photoIndex: Number(data.photo_index),
    status: status as TargetedCheckpoint["status"],
    output: data.normalized_output ?? null,
  };
}

async function checkpointTargetedResult(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  params: {
    userID: string;
    engineRunID: string;
    photoRunID: string;
    signalID: string;
    photoIndex: number;
    provider: ProviderName;
    model: string;
    status: TargetedCheckpoint["status"];
    output: unknown | null;
    errorCode?: string | null;
  },
): Promise<void> {
  const { data, error } = await supabase.rpc(
    "checkpoint_analysis_targeted_run_v1",
    {
      p_user_id: params.userID,
      p_engine_run_id: params.engineRunID,
      p_photo_run_id: params.photoRunID,
      p_signal_id: params.signalID,
      p_photo_index: params.photoIndex,
      p_provider: params.provider,
      p_model: params.model,
      p_status: params.status,
      p_normalized_output: params.output,
      p_output_sha256: params.output ? await sha256(params.output) : null,
      p_error_code: params.errorCode ?? null,
    },
  );
  if (error || data?.ok !== true) {
    throw new Error(
      `targeted_checkpoint_failed:${safeText(error?.message ?? data?.state)}`,
    );
  }
}

async function beginOpenAIBackgroundAttempt(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  params: {
    userID: string;
    engineRunID: string;
    photoRunID: string;
    phase: "primary" | "targeted";
    logicalKey: string;
    kind: ProviderAttemptKind;
    attemptNumber: number;
    model: string;
    promptHash: string;
  },
): Promise<OpenAIBackgroundCheckpoint> {
  const { data, error } = await supabase.rpc(
    "begin_analysis_openai_background_v1",
    {
      p_user_id: params.userID,
      p_engine_run_id: params.engineRunID,
      p_photo_run_id: params.photoRunID,
      p_phase: params.phase,
      p_logical_key: params.logicalKey,
      p_attempt_kind: params.kind,
      p_attempt_number: params.attemptNumber,
      p_model: params.model,
      p_prompt_sha256: params.promptHash,
    },
  );
  if (
    error || data?.ok !== true ||
    typeof data?.background_id !== "string" ||
    typeof data?.attempt_id !== "string"
  ) {
    throw new Error(
      `openai_background_begin_failed:${
        safeText(error?.message ?? data?.state)
      }`,
    );
  }
  return {
    backgroundID: data.background_id,
    attemptID: data.attempt_id,
    attemptNumber: Math.max(1, Number(data.attempt_number ?? 1)),
    providerRequestID: typeof data.provider_request_id === "string"
      ? data.provider_request_id
      : null,
    providerStatus: String(data.provider_status ?? "creating"),
    submittedAt: typeof data.submitted_at === "string"
      ? data.submitted_at
      : null,
    expiresAt: typeof data.expires_at === "string" ? data.expires_at : null,
    created: data.state === "created",
    errorCode: typeof data.error_code === "string" ? data.error_code : null,
  };
}

async function checkpointOpenAIBackgroundAttempt(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  params: {
    userID: string;
    backgroundID: string;
    providerRequestID: string | null;
    providerStatus: string;
    httpStatus?: number | null;
    durationMs?: number | null;
    errorCode?: string | null;
    polled: boolean;
  },
): Promise<OpenAIBackgroundCheckpoint> {
  const { data, error } = await supabase.rpc(
    "checkpoint_analysis_openai_background_v1",
    {
      p_user_id: params.userID,
      p_background_id: params.backgroundID,
      p_provider_request_id: params.providerRequestID,
      p_provider_status: params.providerStatus,
      p_http_status: params.httpStatus ?? null,
      p_duration_ms: params.durationMs ?? null,
      p_error_code: params.errorCode ?? null,
      p_polled: params.polled,
    },
  );
  if (
    error || data?.ok !== true ||
    typeof data?.background_id !== "string" ||
    typeof data?.attempt_id !== "string"
  ) {
    throw new Error(
      `openai_background_checkpoint_failed:${
        safeText(error?.message ?? data?.state)
      }`,
    );
  }
  return {
    backgroundID: data.background_id,
    attemptID: data.attempt_id,
    attemptNumber: 1,
    providerRequestID: typeof data.provider_request_id === "string"
      ? data.provider_request_id
      : null,
    providerStatus: String(data.provider_status ?? params.providerStatus),
    submittedAt: typeof data.submitted_at === "string"
      ? data.submitted_at
      : null,
    expiresAt: typeof data.expires_at === "string" ? data.expires_at : null,
    created: false,
    errorCode: params.errorCode ?? null,
  };
}

function backgroundTransportCanRetry(error: ProviderCallError): boolean {
  return error.code === "provider_timeout" ||
    error.code === "provider_transport_error" ||
    error.code === "provider_rate_limited" ||
    (error.httpStatus !== null && error.httpStatus >= 500);
}

async function executeOpenAIBackgroundAttempt(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userID: string;
  engineRunID: string;
  photoRunID: string;
  photo: PhotoInput;
  model: string;
  prompt: string;
  key: string;
  kind: ProviderAttemptKind;
  attemptNumber: number;
  config: Config;
  backgroundLogicalKey?: string;
  renderedPromptHash: string;
  attemptBudgetTraces?: Map<string, ProviderAttemptBudgetTrace>;
}): Promise<ProviderCallResult & { attemptID: string }> {
  const phase = params.kind === "targeted_reinspection"
    ? "targeted"
    : "primary";
  const logicalKey = params.backgroundLogicalKey ??
    `${params.kind}:photo:${params.photo.photoIndex}`;
  const backgroundPromptHash = await sha256({
    phase,
    logicalKey,
    model: params.model,
    prompt: params.prompt,
    photoIndex: params.photo.photoIndex,
    mimeType: params.photo.mimeType,
    reasoningEffort: params.config.openAIReasoningEffort,
    maxOutputTokens: params.config.maxProviderOutputTokens,
    compactProviderContract: params.config.compactProviderContractEnabled,
  });
  let background = await beginOpenAIBackgroundAttempt(params.supabase, {
    userID: params.userID,
    engineRunID: params.engineRunID,
    photoRunID: params.photoRunID,
    phase,
    logicalKey,
    kind: params.kind,
    attemptNumber: params.attemptNumber,
    model: params.model,
    promptHash: backgroundPromptHash,
  });
  if (background.created) {
    await recordAttempt(params.supabase, {
      attemptID: background.attemptID,
      userID: params.userID,
      engineRunID: params.engineRunID,
      photoRunID: params.photoRunID,
      kind: params.kind,
      number: params.attemptNumber,
      provider: "openai",
      model: params.model,
      state: "started",
      config: params.config,
      requestedServiceTier: "standard",
      promptHash: params.renderedPromptHash,
      promptBundleHash: PROMPT_BUNDLE_SHA256,
      maxOutputTokens: params.config.maxProviderOutputTokens,
    });
  }

  if (
    ["failed", "cancelled", "incomplete", "expired"].includes(
      background.providerStatus,
    )
  ) {
    const error = new ProviderCallError(
      "OpenAI Luna background response is terminal",
      background.errorCode ??
        `provider_background_${background.providerStatus}`,
      "openai",
      params.model,
      null,
      0,
      false,
      undefined,
      background.providerRequestID,
    );
    params.attemptBudgetTraces?.set(
      background.attemptID,
      providerAttemptBudgetTrace({
        attemptID: background.attemptID,
        photoIndex: params.photo.photoIndex,
        kind: params.kind,
        attemptNumber: params.attemptNumber,
        provider: "openai",
        model: params.model,
        config: params.config,
        promptHash: params.renderedPromptHash,
        error,
      }),
    );
    throw error;
  }

  let observation;
  const polled = Boolean(background.providerRequestID);
  try {
    observation = background.providerRequestID
      ? await pollOpenAIBackgroundPhotoProvider({
        apiKey: params.key,
        responseID: background.providerRequestID,
        model: params.model,
        photoIndex: params.photo.photoIndex,
        timeoutMs: OPENAI_BACKGROUND_POLL_TIMEOUT_MS,
      })
      : await startOpenAIBackgroundPhotoProvider({
        apiKey: params.key,
        model: params.model,
        prompt: params.prompt,
        imageData: params.photo.base64,
        mimeType: params.photo.mimeType,
        photoIndex: params.photo.photoIndex,
        timeoutMs: OPENAI_BACKGROUND_SUBMIT_TIMEOUT_MS,
        reasoningEffort: params.config.openAIReasoningEffort,
        maxOutputTokens: params.config.maxProviderOutputTokens,
        compactProviderContract: params.config.compactProviderContractEnabled,
        idempotencyKey: `riskdetected-bg-${background.backgroundID}`,
      });
  } catch (rawError) {
    const error = rawError instanceof ProviderCallError
      ? rawError
      : new ProviderCallError(
        safeText(rawError),
        "provider_unknown_error",
        "openai",
        params.model,
        null,
        0,
      );
    if (backgroundTransportCanRetry(error)) {
      await checkpointOpenAIBackgroundAttempt(params.supabase, {
        userID: params.userID,
        backgroundID: background.backgroundID,
        providerRequestID: background.providerRequestID,
        providerStatus: background.providerStatus,
        httpStatus: error.httpStatus,
        durationMs: error.durationMs,
        errorCode: error.code,
        polled,
      });
      throw new ProviderBackgroundPendingError(
        params.config.openAILunaBackgroundPollSeconds,
        background.providerStatus,
        background.providerRequestID,
      );
    }
    await checkpointOpenAIBackgroundAttempt(params.supabase, {
      userID: params.userID,
      backgroundID: background.backgroundID,
      providerRequestID: error.providerRequestID ??
        background.providerRequestID,
      providerStatus: "failed",
      httpStatus: error.httpStatus,
      durationMs: error.durationMs,
      errorCode: error.code,
      polled,
    });
    await recordAttempt(params.supabase, {
      attemptID: background.attemptID,
      userID: params.userID,
      engineRunID: params.engineRunID,
      photoRunID: params.photoRunID,
      kind: params.kind,
      number: params.attemptNumber,
      provider: "openai",
      model: params.model,
      state: "failed",
      error,
      config: params.config,
      requestedServiceTier: "standard",
      promptHash: params.renderedPromptHash,
      promptBundleHash: PROMPT_BUNDLE_SHA256,
      maxOutputTokens: params.config.maxProviderOutputTokens,
    });
    params.attemptBudgetTraces?.set(
      background.attemptID,
      providerAttemptBudgetTrace({
        attemptID: background.attemptID,
        photoIndex: params.photo.photoIndex,
        kind: params.kind,
        attemptNumber: params.attemptNumber,
        provider: "openai",
        model: params.model,
        config: params.config,
        promptHash: params.renderedPromptHash,
        error,
      }),
    );
    throw error;
  }

  background = await checkpointOpenAIBackgroundAttempt(params.supabase, {
    userID: params.userID,
    backgroundID: background.backgroundID,
    providerRequestID: observation.providerRequestID,
    providerStatus: observation.providerStatus,
    httpStatus: observation.state === "completed"
      ? observation.result.httpStatus
      : observation.httpStatus,
    durationMs: observation.state === "completed"
      ? observation.result.durationMs
      : observation.durationMs,
    errorCode: null,
    polled,
  });
  if (observation.state === "pending") {
    throw new ProviderBackgroundPendingError(
      params.config.openAILunaBackgroundPollSeconds,
      observation.providerStatus,
      observation.providerRequestID,
    );
  }

  const submittedAtMs = background.submittedAt
    ? Date.parse(background.submittedAt)
    : Number.NaN;
  const result = Number.isFinite(submittedAtMs)
    ? {
      ...observation.result,
      durationMs: Math.max(0, Date.now() - submittedAtMs),
    }
    : observation.result;
  await recordAttempt(params.supabase, {
    attemptID: background.attemptID,
    userID: params.userID,
    engineRunID: params.engineRunID,
    photoRunID: params.photoRunID,
    kind: params.kind,
    number: params.attemptNumber,
    provider: "openai",
    model: params.model,
    state: "received",
    result,
    config: params.config,
    requestedServiceTier: "standard",
    promptHash: params.renderedPromptHash,
    promptBundleHash: PROMPT_BUNDLE_SHA256,
    maxOutputTokens: params.config.maxProviderOutputTokens,
  });
  params.attemptBudgetTraces?.set(
    background.attemptID,
    providerAttemptBudgetTrace({
      attemptID: background.attemptID,
      photoIndex: params.photo.photoIndex,
      kind: params.kind,
      attemptNumber: params.attemptNumber,
      provider: "openai",
      model: params.model,
      config: params.config,
      promptHash: params.renderedPromptHash,
      result,
    }),
  );
  return { ...result, attemptID: background.attemptID };
}

async function executeProviderAttempt(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userID: string;
  engineRunID: string;
  photoRunID: string | null;
  photo: PhotoInput;
  provider: ProviderName;
  model: string;
  prompt: string;
  key: string;
  kind: ProviderAttemptKind;
  attemptNumber: number;
  timeoutMs: number;
  config: Config;
  serviceTier?: AnalysisServiceTier;
  serviceTierFallbackReason?: string | null;
  backgroundLogicalKey?: string;
  attemptBudgetTraces?: Map<string, ProviderAttemptBudgetTrace>;
}): Promise<ProviderCallResult & { attemptID: string }> {
  const renderedPromptHash = await sha256Text(params.prompt);
  if (
    params.photoRunID && shouldUseOpenAILunaBackground({
      provider: params.provider,
      model: params.model,
      enabled: params.config.openAILunaBackgroundEnabled,
    })
  ) {
    return await executeOpenAIBackgroundAttempt({
      supabase: params.supabase,
      userID: params.userID,
      engineRunID: params.engineRunID,
      photoRunID: params.photoRunID,
      photo: params.photo,
      model: params.model,
      prompt: params.prompt,
      key: params.key,
      kind: params.kind,
      attemptNumber: params.attemptNumber,
      config: params.config,
      backgroundLogicalKey: params.backgroundLogicalKey,
      renderedPromptHash,
      attemptBudgetTraces: params.attemptBudgetTraces,
    });
  }
  const attemptID = crypto.randomUUID();
  const requestedServiceTier = params.provider === "gemini"
    ? params.serviceTier ?? params.config.requestedServiceTier
    : "standard";
  await recordAttempt(params.supabase, {
    attemptID,
    userID: params.userID,
    engineRunID: params.engineRunID,
    photoRunID: params.photoRunID,
    kind: params.kind,
    number: params.attemptNumber,
    provider: params.provider,
    model: params.model,
    state: "started",
    config: params.config,
    requestedServiceTier,
    serviceTierFallbackReason: params.serviceTierFallbackReason,
    promptHash: renderedPromptHash,
    promptBundleHash: PROMPT_BUNDLE_SHA256,
    maxOutputTokens: params.config.maxProviderOutputTokens,
  });
  try {
    const result = await callPhotoProvider({
      provider: params.provider,
      apiKey: params.key,
      model: params.model,
      prompt: params.prompt,
      imageData: params.photo.base64,
      mimeType: params.photo.mimeType,
      photoIndex: params.photo.photoIndex,
      timeoutMs: params.timeoutMs,
      geminiThinkingBudget: params.config.geminiThinkingBudget,
      maxOutputTokens: params.config.maxProviderOutputTokens,
      openAIReasoningEffort: params.config.openAIReasoningEffort,
      serviceTier: requestedServiceTier,
      compactProviderContract: params.config.compactProviderContractEnabled,
    });
    await recordAttempt(params.supabase, {
      attemptID,
      userID: params.userID,
      engineRunID: params.engineRunID,
      photoRunID: params.photoRunID,
      kind: params.kind,
      number: params.attemptNumber,
      provider: params.provider,
      model: params.model,
      state: "received",
      result,
      config: params.config,
      requestedServiceTier,
      serviceTierFallbackReason: params.serviceTierFallbackReason,
      promptHash: renderedPromptHash,
      promptBundleHash: PROMPT_BUNDLE_SHA256,
      maxOutputTokens: params.config.maxProviderOutputTokens,
    });
    params.attemptBudgetTraces?.set(
      attemptID,
      providerAttemptBudgetTrace({
        attemptID,
        photoIndex: params.photo.photoIndex,
        kind: params.kind,
        attemptNumber: params.attemptNumber,
        provider: params.provider,
        model: params.model,
        config: params.config,
        promptHash: renderedPromptHash,
        result,
      }),
    );
    return { ...result, attemptID };
  } catch (rawError) {
    const error = rawError instanceof ProviderCallError
      ? rawError
      : new ProviderCallError(
        safeText(rawError),
        "provider_unknown_error",
        params.provider,
        params.model,
        null,
        0,
      );
    await recordAttempt(params.supabase, {
      attemptID,
      userID: params.userID,
      engineRunID: params.engineRunID,
      photoRunID: params.photoRunID,
      kind: params.kind,
      number: params.attemptNumber,
      provider: params.provider,
      model: params.model,
      state: "failed",
      error,
      config: params.config,
      requestedServiceTier,
      serviceTierFallbackReason: params.serviceTierFallbackReason,
      promptHash: renderedPromptHash,
      promptBundleHash: PROMPT_BUNDLE_SHA256,
      maxOutputTokens: params.config.maxProviderOutputTokens,
    });
    params.attemptBudgetTraces?.set(
      attemptID,
      providerAttemptBudgetTrace({
        attemptID,
        photoIndex: params.photo.photoIndex,
        kind: params.kind,
        attemptNumber: params.attemptNumber,
        provider: params.provider,
        model: params.model,
        config: params.config,
        promptHash: renderedPromptHash,
        error,
      }),
    );
    throw error;
  }
}

async function analyzePhoto(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userID: string;
  engineRunID: string;
  photo: PhotoInput;
  config: Config;
  sector: string;
  focuses: string[];
  language: string;
  priorAttemptCount?: number;
  priorErrorCode?: string | null;
  attemptBudgetTraces?: Map<string, ProviderAttemptBudgetTrace>;
}): Promise<
  { result: PhotoResult; schemaRepairUsed: boolean; photoRunID: string }
> {
  const prompt = buildPrimaryPhotoPrompt({
    photoIndex: params.photo.photoIndex,
    sector: params.sector,
    focuses: params.focuses,
    language: params.language,
    sectorProfileEnabled: params.config.sectorProfileEnabled,
    sectorFrequencyPriorEnabled: params.config.sectorFrequencyPriorEnabled,
    sectorControlPreferencesEnabled:
      params.config.sectorControlPreferencesEnabled,
    sectorNegativeRulesEnabled: params.config.sectorNegativeRulesEnabled,
    compactProviderContractEnabled:
      params.config.compactProviderContractEnabled,
  });
  let photoRunID = await checkpointPhoto(params.supabase, {
    userID: params.userID,
    engineRunID: params.engineRunID,
    photo: params.photo,
    provider: params.config.primaryProvider,
    model: params.config.primaryModel,
    status: "running",
    attemptCount: Math.max(0, params.priorAttemptCount ?? 0),
  });
  const primaryKey = providerKey(params.config.primaryProvider);
  if (!primaryKey) {
    throw new Error(`${params.config.primaryProvider}_api_key_missing`);
  }
  const priorAttemptCount = Math.max(0, params.priorAttemptCount ?? 0);
  let lastError: ProviderCallError | null = priorAttemptCount > 0
    ? new ProviderCallError(
      "Previous worker attempt did not complete this photo",
      params.priorErrorCode || "provider_retry_checkpoint_resumed",
      params.config.primaryProvider,
      params.config.primaryModel,
      null,
      0,
      String(params.priorErrorCode ?? "").startsWith(
        "provider_schema_invalid",
      ),
    )
    : null;
  let schemaRepairUsed = false;
  let primaryAttempts = priorAttemptCount;
  let attemptsMade = priorAttemptCount;
  const primaryAttemptLimit = primaryProviderAttemptLimit(
    params.config.primaryProvider,
    params.config.computeProfile,
  );
  for (
    let attempt = priorAttemptCount + 1;
    attempt <= primaryAttemptLimit;
    attempt += 1
  ) {
    const kind = attempt === 1 ? "primary" : "technical_retry";
    primaryAttempts = attempt;
    attemptsMade = attempt;
    try {
      const result = await executeProviderAttempt({
        supabase: params.supabase,
        userID: params.userID,
        engineRunID: params.engineRunID,
        photoRunID,
        photo: params.photo,
        provider: params.config.primaryProvider,
        model: params.config.primaryModel,
        prompt,
        key: primaryKey,
        kind,
        attemptNumber: attempt,
        timeoutMs: attempt === 1
          ? primaryProviderTimeoutMs(params.config.primaryProvider)
          : retryProviderTimeoutMs(params.config.primaryProvider),
        config: attempt === 1 ? params.config : {
          ...params.config,
          geminiThinkingBudget: Math.min(
            params.config.geminiThinkingBudget,
            params.config.geminiRetryThinkingBudget,
          ),
        },
        attemptBudgetTraces: params.attemptBudgetTraces,
      });
      photoRunID = await checkpointPhoto(params.supabase, {
        userID: params.userID,
        engineRunID: params.engineRunID,
        photo: params.photo,
        provider: result.provider,
        model: result.model,
        status: "completed",
        attemptCount: attempt,
        output: result.output,
        result,
      });
      // A persisted attempt is never overwritten by later phases.
      await recordAttempt(params.supabase, {
        attemptID: result.attemptID,
        userID: params.userID,
        engineRunID: params.engineRunID,
        photoRunID,
        kind,
        number: attempt,
        provider: result.provider,
        model: result.model,
        state: "persisted",
        result,
        config: params.config,
      });
      // Deterministic record-level salvage does not consume another semantic
      // provider call, so it must not suppress the one allowed targeted pass.
      // `schemaRepairUsed` remains reserved for an actual retry/fallback call.
      schemaRepairUsed = attempt > 1 && lastError?.schemaError === true;
      return {
        result: {
          photoID: params.photo.photoID,
          photoIndex: params.photo.photoIndex,
          storagePath: params.photo.storagePath,
          provider: result.provider,
          model: result.model,
          output: result.output,
          usage: {
            inputTokens: result.usage.inputTokens,
            outputTokens: result.usage.outputTokens,
            reasoningTokens: result.usage.reasoningTokens,
            maxOutputTokens: params.config.maxProviderOutputTokens,
          },
        },
        schemaRepairUsed,
        photoRunID,
      };
    } catch (error) {
      if (error instanceof ProviderBackgroundPendingError) throw error;
      lastError = error instanceof ProviderCallError
        ? error
        : new ProviderCallError(
          safeText(error),
          "photo_analysis_failed",
          params.config.primaryProvider,
          params.config.primaryModel,
          null,
          0,
        );
      // Local syntax repair and record-level salvage have already run. A
      // remaining schema/transport failure may use one lower-budget technical
      // retry; the persisted attempt number survives a queue redelivery.
      if (!shouldRetrySameProvider(lastError)) {
        schemaRepairUsed = true;
        break;
      }
    }
  }
  const economyStandardFallback = Boolean(
    lastError && params.config.computeProfile === "economy" &&
      params.config.requestedServiceTier === "flex" &&
      params.config.economyStandardFallbackEnabled &&
      shouldUseEconomyStandardFallback(lastError),
  );
  const configuredProviderFallback = Boolean(
    lastError && params.config.computeProfile === "premium" &&
      shouldUseFallbackProvider(lastError),
  );
  const fallbackKey = providerKey(params.config.fallbackProvider);
  if (
    lastError && (economyStandardFallback || configuredProviderFallback) &&
    attemptsMade < primaryAttemptLimit + 1 &&
    fallbackKey &&
    (economyStandardFallback ||
      params.config.fallbackProvider !== params.config.primaryProvider ||
      params.config.fallbackModel !== params.config.primaryModel)
  ) {
    const fallbackAttempt = primaryAttempts + 1;
    attemptsMade = fallbackAttempt;
    try {
      const result = await executeProviderAttempt({
        supabase: params.supabase,
        userID: params.userID,
        engineRunID: params.engineRunID,
        photoRunID,
        photo: params.photo,
        provider: params.config.fallbackProvider,
        model: params.config.fallbackModel,
        prompt,
        key: fallbackKey,
        kind: "provider_fallback",
        attemptNumber: fallbackAttempt,
        timeoutMs: fallbackProviderTimeoutMs(params.config.fallbackProvider),
        config: params.config,
        serviceTier: params.config.fallbackServiceTier,
        serviceTierFallbackReason: economyStandardFallback
          ? lastError.code
          : null,
        attemptBudgetTraces: params.attemptBudgetTraces,
      });
      photoRunID = await checkpointPhoto(params.supabase, {
        userID: params.userID,
        engineRunID: params.engineRunID,
        photo: params.photo,
        provider: result.provider,
        model: result.model,
        status: "completed",
        attemptCount: fallbackAttempt,
        output: result.output,
        result,
      });
      await recordAttempt(params.supabase, {
        attemptID: result.attemptID,
        userID: params.userID,
        engineRunID: params.engineRunID,
        photoRunID,
        kind: "provider_fallback",
        number: fallbackAttempt,
        provider: result.provider,
        model: result.model,
        state: "persisted",
        result,
        config: params.config,
        serviceTierFallbackReason: economyStandardFallback
          ? lastError.code
          : null,
      });
      return {
        result: {
          photoID: params.photo.photoID,
          photoIndex: params.photo.photoIndex,
          storagePath: params.photo.storagePath,
          provider: result.provider,
          model: result.model,
          output: result.output,
          usage: {
            inputTokens: result.usage.inputTokens,
            outputTokens: result.usage.outputTokens,
            reasoningTokens: result.usage.reasoningTokens,
            maxOutputTokens: params.config.maxProviderOutputTokens,
          },
        },
        schemaRepairUsed,
        photoRunID,
      };
    } catch (error) {
      if (error instanceof ProviderBackgroundPendingError) throw error;
      lastError = error instanceof ProviderCallError ? error : lastError;
    }
  }
  await checkpointPhoto(params.supabase, {
    userID: params.userID,
    engineRunID: params.engineRunID,
    photo: params.photo,
    provider: lastError?.provider ?? params.config.primaryProvider,
    model: lastError?.model ?? params.config.primaryModel,
    status: "failed",
    attemptCount: attemptsMade,
    errorCode: lastError?.code ?? "photo_analysis_failed",
  });
  throw lastError ?? new Error("photo_analysis_failed");
}

async function sendCompletionPush(params: {
  supabaseUrl: string;
  serviceRoleKey: string;
  userID: string;
  analysisID: string;
  requestID: string;
  supportID: string;
}) {
  try {
    await fetch(`${params.supabaseUrl}/functions/v1/send-push-notification`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${params.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: params.userID,
        kind: "analysis_complete",
        event_key: "analysis_complete",
        data: {
          analysis_id: params.analysisID,
          destination: "history",
          request_id: params.requestID,
          support_id: params.supportID,
        },
      }),
    });
  } catch (error) {
    console.warn("vNext completion push skipped", safeText(error));
  }
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { code: "method_not_allowed" });
  const startedAt = Date.now();
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { code: "supabase_credentials_missing" });
  }
  if (req.headers.get("Authorization") !== `Bearer ${serviceRoleKey}`) {
    return json(401, { code: "worker_auth_required" });
  }
  let body: JobBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { code: "invalid_json" });
  }
  const userID = typeof body.user_id === "string" ? body.user_id : "";
  const analysisID = typeof body.analysis_id === "string"
    ? body.analysis_id
    : "";
  const msgID = Number(body.__queue_msg_id);
  const generation = Number(body.__job_generation);
  const claimToken = typeof body.__worker_claim_token === "string"
    ? body.__worker_claim_token
    : "";
  const requestID = typeof body.request_id === "string"
    ? body.request_id.slice(0, 120)
    : crypto.randomUUID();
  const supportID = typeof body.support_id === "string"
    ? body.support_id.slice(0, 120)
    : crypto.randomUUID().slice(0, 12);
  if (
    body.__worker !== true || Number(body.pipeline_version) !== 2 ||
    body.job_mode === "repair" || !userID || !analysisID || !claimToken ||
    !Number.isInteger(msgID) || msgID <= 0 || !Number.isInteger(generation) ||
    generation <= 0
  ) {
    return json(400, { code: "vnext_worker_contract_invalid" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let engineRunID: string | null = null;
  try {
    const { data: claim, error: claimError } = await supabase.rpc(
      "validate_analysis_job_claim_v2",
      {
        p_user_id: userID,
        p_analysis_id: analysisID,
        p_msg_id: msgID,
        p_generation: generation,
        p_claim_token: claimToken,
      },
    );
    if (claimError || claim?.ok !== true) {
      return json(409, { code: String(claim?.state ?? "lost_claim") });
    }
    const { data: begin, error: beginError } = await supabase.rpc(
      "begin_analysis_engine_run_v3",
      {
        p_user_id: userID,
        p_analysis_id: analysisID,
        p_msg_id: msgID,
        p_generation: generation,
        p_claim_token: claimToken,
        p_job_mode: "analysis",
      },
    );
    if (
      beginError || begin?.ok !== true ||
      typeof begin?.engine_run_id !== "string"
    ) {
      return json(409, { code: String(begin?.state ?? "engine_run_rejected") });
    }
    engineRunID = begin.engine_run_id;
    if (begin.state === "completed") {
      return json(200, {
        ok: true,
        status: "already_completed",
        code: "completed",
      });
    }
    const { data: analysis, error: analysisError } = await supabase.from(
      "analyses",
    )
      .select(
        "id,user_id,status,analysis_sector,analysis_sector_source,analysis_sector_prompt_version,output_language,plan_at_creation,canvas,safety_profile_id,regulatory_reference_policy,localization_snapshot",
      )
      .eq("id", analysisID).eq("user_id", userID).maybeSingle();
    if (analysisError || !analysis) throw new Error("analysis_not_found");
    const requestedPaths = [...new Set(strings(body.photo_paths))].slice(0, 3);
    if (requestedPaths.length < 1) throw new Error("photo_required");
    const { data: rows, error: photoError } = await supabase.from("photos")
      .select("id,storage_path,mime_type,sequence_index")
      .eq("analysis_id", analysisID).eq("user_id", userID)
      .in("storage_path", requestedPaths);
    if (photoError) {
      throw new Error(`photo_metadata_failed:${photoError.message}`);
    }
    const rowByPath = new Map(
      (Array.isArray(rows) ? rows : []).map((
        row,
      ) => [String(row.storage_path), row]),
    );
    const orderedPaths = [...requestedPaths].sort((left, right) => {
      const leftIndex = Number(rowByPath.get(left)?.sequence_index);
      const rightIndex = Number(rowByPath.get(right)?.sequence_index);
      return (Number.isInteger(leftIndex)
        ? leftIndex
        : requestedPaths.indexOf(left)) -
        (Number.isInteger(rightIndex)
          ? rightIndex
          : requestedPaths.indexOf(right));
    });
    const photos: PhotoInput[] = await Promise.all(
      orderedPaths.map(async (path, i) => {
        const row = rowByPath.get(path);
        if (!row) throw new Error("photo_ownership_mismatch");
        const { data: blob, error } = await supabase.storage.from("photos")
          .download(path);
        if (error || !blob) {
          throw new Error(`photo_download_failed:${safeText(error?.message)}`);
        }
        const bytes = new Uint8Array(await blob.arrayBuffer());
        if (bytes.byteLength === 0 || bytes.byteLength > 15 * 1024 * 1024) {
          throw new Error("photo_size_invalid");
        }
        return {
          photoID: typeof row.id === "string" ? row.id : null,
          photoIndex: Number.isInteger(Number(row.sequence_index))
            ? Number(row.sequence_index)
            : i + 1,
          storagePath: path,
          mimeType: typeof row.mime_type === "string"
            ? row.mime_type
            : "image/jpeg",
          base64: bytesToBase64(bytes),
        };
      }),
    );
    const photoIndices = photos.map((photo) => photo.photoIndex).sort((a, b) =>
      a - b
    );
    if (
      photoIndices.some((value, index) => value !== index + 1) ||
      new Set(photoIndices).size !== photos.length
    ) throw new Error("photo_sequence_invalid");
    // Resolve the paid thinking policy only after every requested photo has
    // passed ownership, metadata and payload validation. The pinned engine
    // config plus this verified count makes worker retries deterministic while
    // preventing a client-supplied count from selecting a compute budget.
    const config = resolveVNextConfig(
      object((begin as Record<string, unknown>).config_snapshot),
      photos.length,
    );
    const engineConfigSnapshot = object(
      object((begin as Record<string, unknown>).config_snapshot).engine_config,
    );
    if (config.promptBundleIntegrityEnabled) {
      await verifyPromptBundleIntegrity();
      if (
        String(begin.prompt_version ?? "") !== PROMPT_VERSION ||
        String(begin.policy_version ?? "") !== POLICY_VERSION ||
        String(engineConfigSnapshot.prompt_bundle_policy_version ?? "") !==
          PROMPT_BUNDLE_POLICY_VERSION ||
        String(engineConfigSnapshot.prompt_bundle_sha256 ?? "") !==
          PROMPT_BUNDLE_SHA256
      ) {
        throw new Error("prompt_bundle_contract_mismatch");
      }
    }
    const language = typeof analysis.output_language === "string"
      ? analysis.output_language
      : object(analysis.localization_snapshot).output_language === "en"
      ? "en"
      : "tr";
    const sectorSelection = resolveVNextSectorSelection(
      analysis.analysis_sector,
      body.analysis_sector,
    );
    const sector = sectorSelection.sectorID;
    const sectorSource = sectorSelection.source;
    const sectorRequestMismatch = sectorSelection.requestMismatch;
    if (sector) {
      const sectorUpdate: Record<string, unknown> = {
        analysis_sector_prompt_version: SECTOR_PROFILE_VERSION,
      };
      if (sectorSelection.shouldBackfillDatabase) {
        sectorUpdate.analysis_sector = sector;
        sectorUpdate.analysis_sector_source =
          "analysis_request_legacy_fallback";
      }
      const { error: sectorUpdateError } = await supabase.from("analyses")
        .update(sectorUpdate).eq("id", analysisID).eq("user_id", userID);
      if (sectorUpdateError) {
        console.warn(
          "vNext sector metadata update skipped",
          safeText(sectorUpdateError.message),
        );
      }
    }
    const focuses = strings(body.canvases).length > 0
      ? strings(body.canvases)
      : [String(body.canvas ?? analysis.canvas ?? "general")];
    const plan = String(analysis.plan_at_creation ?? "free");
    const effectiveAnalysisPlan = config.aiExecutionRoute === "free_paid_trial"
      ? "plus"
      : plan;
    const localizationSnapshot = object(analysis.localization_snapshot);
    const checkpointOnlyRefinalize = body.checkpoint_only_refinalize === true;
    const savedRuns = Array.isArray(begin.photo_runs) ? begin.photo_runs : [];
    const savedByIndex = new Map<number, Record<string, unknown>>(
      savedRuns.filter((item: unknown) => object(item).status === "completed")
        .map((
          item: unknown,
        ) => [Number(object(item).photo_index), object(item)]),
    );
    const failedByIndex = new Map<number, Record<string, unknown>>(
      savedRuns.filter((item: unknown) =>
        ["failed", "running"].includes(String(object(item).status))
      ).map((item: unknown) => [
        Number(object(item).photo_index),
        object(item),
      ]),
    );
    let schemaRepairUsed = false;
    const photoRunIDs = new Map<number, string>();
    const attemptBudgetTraces = new Map<string, ProviderAttemptBudgetTrace>();
    const settledPhotoResults = await Promise.allSettled(
      photos.map(async (photo) => {
        const saved = savedByIndex.get(photo.photoIndex);
        if (saved && saved.normalized_output) {
          const parsed = parsePhotoAnalysisV3WithSalvage(
            saved.normalized_output,
            photo.photoIndex,
          );
          photoRunIDs.set(photo.photoIndex, String(saved.id));
          return {
            photoID: photo.photoID,
            photoIndex: photo.photoIndex,
            storagePath: photo.storagePath,
            provider: String(saved.provider ?? config.primaryProvider),
            model: String(saved.model ?? config.primaryModel),
            output: parsed,
          } satisfies PhotoResult;
        }
        if (checkpointOnlyRefinalize) {
          throw new Error("checkpoint_only_photo_output_missing");
        }
        const completed = await analyzePhoto({
          supabase,
          userID,
          engineRunID: engineRunID!,
          photo,
          config,
          sector: sector ?? "",
          focuses,
          language,
          priorAttemptCount: Number(
            failedByIndex.get(photo.photoIndex)?.attempt_count ?? 0,
          ),
          priorErrorCode: failedByIndex.get(photo.photoIndex)?.error_code
            ? String(failedByIndex.get(photo.photoIndex)?.error_code)
            : null,
          attemptBudgetTraces,
        });
        if (completed.schemaRepairUsed) schemaRepairUsed = true;
        photoRunIDs.set(photo.photoIndex, completed.photoRunID);
        return completed.result;
      }),
    );
    const failedPhoto = settledPhotoResults.find((item) =>
      item.status === "rejected" &&
      !(item.reason instanceof ProviderBackgroundPendingError)
    );
    if (failedPhoto?.status === "rejected") throw failedPhoto.reason;
    const pendingPhoto = settledPhotoResults.find((item) =>
      item.status === "rejected" &&
      item.reason instanceof ProviderBackgroundPendingError
    );
    if (pendingPhoto?.status === "rejected") throw pendingPhoto.reason;
    const photoResults = settledPhotoResults.map((item) => {
      if (item.status !== "fulfilled") {
        throw new Error("photo_analysis_failed");
      }
      return item.value;
    });

    let targetedFacts = [] as ReturnType<
      typeof parsePhotoAnalysisV3
    >["hazard_facts"];
    let targetedRejections: Array<{
      fact_id: string;
      photo_index: number;
      reason_code: string;
    }> = [];
    const savedTargeted = await loadTargetedCheckpoint(
      supabase,
      userID,
      engineRunID!,
    );
    // Screening is pure computation over facts that were already paid for. It
    // used to be skipped entirely alongside the targeted provider call, which
    // meant a rejected critical component left `screened_facts` empty and the
    // run reported `candidate_count: 0` -- the diagnostic disappeared together
    // with the remedy. Screening now always runs; only the provider call is
    // subject to budget suppression.
    const targetedDecision = selectTargetedDecision(
      photoResults,
      config.sectorProfileEnabled ? sector : null,
      config.multiPhotoHighHazardCoverageEnabled,
      {
        contextualFallBarrierAliasEnabled:
          config.contextualFallBarrierAliasEnabled,
      },
    );
    /**
     * A technical retry has already consumed one provider call, so the targeted
     * pass is normally suppressed to hold the budget. That trade is wrong on
     * two paths, and both have to be checked: screening may have rejected a
     * fact whose consequence class reaches permanent disability or worse, or
     * the sector critical-coverage net may have raised a component the sector
     * profile treats as critical. Checking only the first left a selected
     * scaffold-guardrail candidate suppressed with `signal: null` beside a
     * `candidate_count: 1`.
     *
     * The targeted pass runs at 768 thinking tokens. A missed fatal hazard
     * costs more than that.
     */
    const targetedRescuesHighConsequence = targetedDecision.screened_facts
      .some((fact) => fact.targeted_eligible === true) ||
      targetedDecision.candidates
        .some((candidate) => candidate.sector_critical_component === true);
    const suppressTargetedForBudget = schemaRepairUsed &&
      !targetedRescuesHighConsequence;
    const targetedSignal = suppressTargetedForBudget
      ? null
      : targetedDecision.signal;
    let targetedStatus:
      | "not_needed"
      | "confirmed"
      | "rejected"
      | "skipped_schema_repair" = suppressTargetedForBudget
        ? "skipped_schema_repair"
        : "not_needed";
    let effectiveTargetedSignalID = targetedSignal?.signal_id ?? null;
    if (savedTargeted) {
      // A targeted provider response is a paid semantic result. Reuse its
      // checkpoint after worker/finalization retries instead of calling the
      // model again. Primary photo outputs remain independently checkpointed.
      const savedSignalMatchesCurrent = Boolean(
        targetedSignal &&
          targetedSignal.photo_index === savedTargeted.photoIndex &&
          inspectionSignalIDsEquivalent(
            targetedSignal.signal_id,
            savedTargeted.signalID,
          ),
      );
      effectiveTargetedSignalID = savedSignalMatchesCurrent && targetedSignal
        ? targetedSignal.signal_id
        : savedTargeted.signalID;
      if (savedTargeted.output) {
        try {
          targetedFacts = parsePhotoAnalysisV3WithSalvage(
            savedTargeted.output,
            savedTargeted.photoIndex,
          ).hazard_facts;
          if (targetedSignal && savedSignalMatchesCurrent) {
            const constrained = constrainTargetedFactsWithTrace(
              photoResults,
              targetedSignal,
              targetedFacts,
            );
            targetedFacts = constrained.facts;
            targetedRejections = constrained.rejections;
          } else {
            targetedRejections = targetedFacts.map((fact) => ({
              fact_id: fact.fact_id,
              photo_index: fact.photo_index,
              reason_code: "targeted_checkpoint_signal_mismatch",
            }));
            targetedFacts = [];
          }
        } catch (error) {
          console.warn(
            "vNext targeted checkpoint parse skipped",
            safeText(error),
          );
          targetedFacts = [];
        }
      }
      targetedStatus = savedTargeted.status === "confirmed" &&
          targetedFacts.length > 0
        ? "confirmed"
        : "rejected";
    } else if (targetedSignal && checkpointOnlyRefinalize) {
      targetedStatus = "rejected";
      targetedRejections = [{
        fact_id: targetedSignal.signal_id,
        photo_index: targetedSignal.photo_index,
        reason_code: "checkpoint_only_targeted_output_missing",
      }];
    } else if (targetedSignal) {
      const photo = photos.find((item) =>
        item.photoIndex === targetedSignal.photo_index
      );
      const source = photoResults.find((item) =>
        item.photoIndex === targetedSignal.photo_index
      );
      const key = source ? providerKey(source.provider as ProviderName) : null;
      if (photo && source && key) {
        const targetedConfig: Config = {
          ...config,
          // A focused verification pass does not need the full primary
          // reasoning budget; keeping it bounded protects latency/cost.
          geminiThinkingBudget: Math.min(
            config.geminiThinkingBudget,
            config.geminiTargetedThinkingBudget,
          ),
          maxProviderOutputTokens: config.targetedMaxProviderOutputTokens,
          openAIReasoningEffort: config.openAIReasoningEffort,
        };
        try {
          const prompt = buildTargetedPrompt({
            photoIndex: photo.photoIndex,
            language,
            sector: sector ?? undefined,
            sectorProfileEnabled: config.sectorProfileEnabled,
            compactProviderContractEnabled:
              config.compactProviderContractEnabled,
            signal: targetedSignalContext(photoResults, targetedSignal),
          });
          let targetedFallbackReason: string | null = null;
          let result: ProviderCallResult & { attemptID: string };
          try {
            result = await executeProviderAttempt({
              supabase,
              userID,
              engineRunID: engineRunID!,
              photoRunID: photoRunIDs.get(photo.photoIndex) ?? null,
              photo,
              provider: source.provider as ProviderName,
              model: source.model,
              prompt,
              key,
              kind: "targeted_reinspection",
              attemptNumber: 1,
              timeoutMs: targetedProviderTimeoutMs(
                source.provider as ProviderName,
              ),
              config: targetedConfig,
              backgroundLogicalKey:
                `targeted:${photo.photoIndex}:${targetedSignal.signal_id}`,
              attemptBudgetTraces,
            });
          } catch (rawTargetedError) {
            const targetedError = rawTargetedError instanceof ProviderCallError
              ? rawTargetedError
              : null;
            if (
              !targetedError || config.computeProfile !== "economy" ||
              config.requestedServiceTier !== "flex" ||
              !config.economyStandardFallbackEnabled ||
              !shouldUseEconomyStandardFallback(targetedError)
            ) throw rawTargetedError;
            targetedFallbackReason = targetedError.code;
            result = await executeProviderAttempt({
              supabase,
              userID,
              engineRunID: engineRunID!,
              photoRunID: photoRunIDs.get(photo.photoIndex) ?? null,
              photo,
              provider: source.provider as ProviderName,
              model: source.model,
              prompt,
              key,
              kind: "provider_fallback",
              attemptNumber: 2,
              timeoutMs: targetedProviderTimeoutMs(
                source.provider as ProviderName,
              ),
              config: targetedConfig,
              serviceTier: "standard",
              serviceTierFallbackReason: targetedFallbackReason,
              attemptBudgetTraces,
            });
          }
          const constrained = constrainTargetedFactsWithTrace(
            photoResults,
            targetedSignal,
            result.output.hazard_facts,
          );
          targetedFacts = constrained.facts;
          targetedRejections = constrained.rejections;
          targetedStatus = targetedFacts.length > 0 ? "confirmed" : "rejected";
          await checkpointTargetedResult(supabase, {
            userID,
            engineRunID: engineRunID!,
            photoRunID: photoRunIDs.get(photo.photoIndex)!,
            signalID: targetedSignal.signal_id,
            photoIndex: photo.photoIndex,
            provider: result.provider,
            model: result.model,
            status: targetedStatus,
            output: result.output,
          });
          await recordAttempt(supabase, {
            attemptID: result.attemptID,
            userID,
            engineRunID: engineRunID!,
            photoRunID: photoRunIDs.get(photo.photoIndex) ?? null,
            kind: targetedFallbackReason
              ? "provider_fallback"
              : "targeted_reinspection",
            number: targetedFallbackReason ? 2 : 1,
            provider: result.provider,
            model: result.model,
            state: "persisted",
            result,
            config: targetedConfig,
            serviceTierFallbackReason: targetedFallbackReason,
          });
        } catch (error) {
          if (error instanceof ProviderBackgroundPendingError) throw error;
          targetedStatus = "rejected";
          try {
            await checkpointTargetedResult(supabase, {
              userID,
              engineRunID: engineRunID!,
              photoRunID: photoRunIDs.get(photo.photoIndex)!,
              signalID: targetedSignal.signal_id,
              photoIndex: photo.photoIndex,
              provider: source.provider as ProviderName,
              model: source.model,
              status: "failed",
              output: null,
              errorCode: error instanceof ProviderCallError
                ? error.code
                : "targeted_reinspection_failed",
            });
          } catch (checkpointError) {
            console.warn(
              "vNext targeted failure checkpoint skipped",
              safeText(checkpointError),
            );
          }
        }
      }
    }
    const product = buildEngineProduct(
      photoResults,
      language,
      effectiveAnalysisPlan,
      targetedFacts,
      {
        safetyProfileID: String(
          localizationSnapshot.safety_profile_id ??
            analysis.safety_profile_id ?? "",
        ),
        regulatoryReferencePolicy: String(
          localizationSnapshot.regulatory_reference_policy ??
            analysis.regulatory_reference_policy ?? "",
        ),
        structuredRegulatoryReferencesEnabled:
          localizationSnapshot.structured_regulatory_references_enabled ===
            true,
      },
      {
        sectorID: sector,
        source: sectorSource,
        requestMismatch: sectorRequestMismatch,
        profileEnabled: config.sectorProfileEnabled,
        frequencyPriorEnabled: config.sectorFrequencyPriorEnabled,
        controlPreferencesEnabled: config.sectorControlPreferencesEnabled,
        negativeRulesEnabled: config.sectorNegativeRulesEnabled,
        regulationAnchorsEnabled: config.sectorRegulationAnchorsEnabled,
        contextualFallBarrierAliasEnabled:
          config.contextualFallBarrierAliasEnabled,
        personBarrierEquivalentMergeEnabled:
          config.personBarrierEquivalentMergeEnabled,
      },
    );
    const evidenceAlert = object(
      object(product.analysisResult.raw_ai_response)._quality_trace_v3,
    ).evidence_rejection_alert;
    if (object(evidenceAlert).triggered === true) {
      console.warn(
        "vNext evidence rejection ratio alert",
        JSON.stringify({
          analysis_id: analysisID,
          engine_run_id: engineRunID,
          ...object(evidenceAlert),
        }),
      );
    }
    if (effectiveTargetedSignalID) {
      product.inspectionSignals = product.inspectionSignals.map((signal) =>
        signal.signal_id === effectiveTargetedSignalID
          ? {
            ...signal,
            status: targetedStatus === "confirmed" ? "confirmed" : "rejected",
          }
          : signal
      );
    }
    const targetedDecisionAudit = {
      ...targetedDecision,
      signal: targetedSignal
        ? targetedSignalContext(photoResults, targetedSignal)
        : null,
      execution_status: targetedStatus,
      accepted_targeted_fact_ids: targetedFacts.map((fact) => fact.fact_id),
      rejection_ledger: targetedRejections,
    };
    product.qualityTrace.targeted_reinspection = targetedDecisionAudit;
    /**
     * Answers one question the trace could not: is the model filling its output
     * budget or stopping on its own? Raw fact production has been pinned at
     * three per photo through prompt versions, budget changes and a schema
     * reordering, and nothing recorded which of the two was happening.
     */
    product.qualityTrace.provider_output_budget = photoResults.map((result) => {
      const usage = result.usage;
      const generatedTokens = usage
        ? usage.outputTokens + usage.reasoningTokens
        : null;
      return {
        photo_index: result.photoIndex,
        output_tokens: usage?.outputTokens ?? null,
        reasoning_tokens: usage?.reasoningTokens ?? null,
        generated_tokens: generatedTokens,
        input_tokens: usage?.inputTokens ?? null,
        max_output_tokens: usage?.maxOutputTokens ?? null,
        visible_output_budget_used_pct: usage && usage.maxOutputTokens > 0
          ? budgetPercent(usage.outputTokens, usage.maxOutputTokens)
          : null,
        generated_output_budget_used_pct: usage &&
            usage.maxOutputTokens > 0
          ? budgetPercent(generatedTokens!, usage.maxOutputTokens)
          : null,
        output_budget_used_pct: usage && usage.maxOutputTokens > 0
          ? budgetPercent(generatedTokens!, usage.maxOutputTokens)
          : null,
        raw_fact_count: result.output.hazard_facts.length,
        scene_inventory_count: result.output.scene_inventory.length,
      };
    });
    const orderedAttemptBudgetTraces = [...attemptBudgetTraces.values()].sort(
      (left, right) =>
        left.photo_index - right.photo_index ||
        left.attempt_number - right.attempt_number ||
        left.attempt_kind.localeCompare(right.attempt_kind),
    );
    product.qualityTrace.provider_attempt_output_budget =
      config.providerAttemptBudgetTraceEnabled
        ? orderedAttemptBudgetTraces
        : [];
    product.qualityTrace.provider_attempt_output_budget_summary = {
      enabled: config.providerAttemptBudgetTraceEnabled,
      attempt_count: orderedAttemptBudgetTraces.length,
      primary_attempt_count: orderedAttemptBudgetTraces.filter((attempt) =>
        attempt.attempt_kind === "primary"
      ).length,
      technical_retry_attempt_count: orderedAttemptBudgetTraces.filter(
        (attempt) =>
          attempt.attempt_kind === "technical_retry",
      ).length,
      output_cap_exhausted_attempt_count: orderedAttemptBudgetTraces.filter(
        (attempt) => attempt.reason_code === "output_cap_exhausted",
      ).length,
    };
    product.qualityTrace.prompt_integrity = {
      enabled: config.promptBundleIntegrityEnabled,
      prompt_version: PROMPT_VERSION,
      policy_version: POLICY_VERSION,
      bundle_policy_version: PROMPT_BUNDLE_POLICY_VERSION,
      prompt_bundle_sha256: PROMPT_BUNDLE_SHA256,
      rendered_prompt_sha256: orderedAttemptBudgetTraces.map((attempt) => ({
        attempt_id: attempt.attempt_id,
        photo_index: attempt.photo_index,
        attempt_kind: attempt.attempt_kind,
        sha256: attempt.prompt_sha256,
      })),
    };
    product.qualityTrace.thinking_policy = {
      policy_version: config.geminiThinkingPolicyVersion,
      photo_count_policy_enabled: config.geminiThinkingByPhotoEnabled,
      verified_photo_count: config.verifiedPhotoCount,
      compute_profile: config.computeProfile,
      primary_gemini_thinking_budget: config.geminiThinkingBudget,
      technical_retry_gemini_thinking_budget: config.geminiRetryThinkingBudget,
      targeted_gemini_thinking_budget: config.geminiTargetedThinkingBudget,
    };
    product.qualityTrace.critical_coverage_policy = {
      multi_photo_high_hazard_coverage_enabled:
        config.multiPhotoHighHazardCoverageEnabled,
      verified_photo_count: config.verifiedPhotoCount,
      active_sector: sector,
      selected_reason_code: targetedDecision.signal?.reason_code ?? null,
    };
    product.analysisResult.duration_ms = Date.now() - startedAt;
    const rawAI = object(product.analysisResult.raw_ai_response);
    product.analysisResult.raw_ai_response = {
      ...rawAI,
      _quality_trace_v3: product.qualityTrace,
      _engine_contract: {
        engine_version: begin.engine_version,
        schema_version: begin.schema_version,
        prompt_version: begin.prompt_version,
        policy_version: begin.policy_version,
        control_catalog_version: begin.control_catalog_version,
        sector_profile_version: sector ? SECTOR_PROFILE_VERSION : null,
        active_sector: sector,
        sector_source: sectorSource,
        sector_request_database_mismatch: sectorRequestMismatch,
        visual_input_mode: begin.visual_input_mode,
        provider: config.primaryProvider,
        model: config.primaryModel,
        ai_execution_route: config.aiExecutionRoute,
        product_plan: plan,
        analysis_quality_plan: effectiveAnalysisPlan,
        compute_profile: config.computeProfile,
        compute_profile_version: config.computeProfileVersion,
        provider_pool: config.providerPool,
        requested_service_tier: config.requestedServiceTier,
        compact_provider_contract_enabled:
          config.compactProviderContractEnabled,
        contextual_fall_barrier_alias_enabled:
          config.contextualFallBarrierAliasEnabled,
        person_barrier_equivalent_merge_enabled:
          config.personBarrierEquivalentMergeEnabled,
        provider_attempt_budget_trace_enabled:
          config.providerAttemptBudgetTraceEnabled,
        prompt_bundle_integrity_enabled: config.promptBundleIntegrityEnabled,
        prompt_bundle_policy_version: PROMPT_BUNDLE_POLICY_VERSION,
        prompt_bundle_sha256: PROMPT_BUNDLE_SHA256,
        multi_photo_high_hazard_critical_coverage_enabled:
          config.multiPhotoHighHazardCoverageEnabled,
        openai_luna_background_enabled: config.openAILunaBackgroundEnabled,
        openai_luna_background_version: config.openAILunaBackgroundVersion,
        openai_luna_background_effective: shouldUseOpenAILunaBackground({
          provider: config.primaryProvider,
          model: config.primaryModel,
          enabled: config.openAILunaBackgroundEnabled,
        }),
        openai_luna_background_poll_seconds:
          config.openAILunaBackgroundPollSeconds,
        provider_experiment_id: config.providerExperimentID,
        provider_experiment_label: config.providerExperimentLabel,
        provider_experiment_one_shot: config.providerExperimentOneShot,
        economy_standard_fallback_enabled:
          config.economyStandardFallbackEnabled,
        gemini_thinking_by_photo_enabled: config.geminiThinkingByPhotoEnabled,
        gemini_thinking_policy_version: config.geminiThinkingPolicyVersion,
        verified_photo_count: config.verifiedPhotoCount,
        gemini_thinking_budget: config.geminiThinkingBudget,
        technical_retry_gemini_thinking_budget:
          config.geminiRetryThinkingBudget,
        targeted_gemini_thinking_budget: config.geminiTargetedThinkingBudget,
        max_provider_output_tokens: config.maxProviderOutputTokens,
        targeted_max_provider_output_tokens:
          config.targetedMaxProviderOutputTokens,
        openai_reasoning_effort: config.openAIReasoningEffort,
        primary_provider_timeout_ms: primaryProviderTimeoutMs(
          config.primaryProvider,
        ),
        primary_provider_attempt_limit: primaryProviderAttemptLimit(
          config.primaryProvider,
          config.computeProfile,
        ),
        fallback_provider_timeout_ms: fallbackProviderTimeoutMs(
          config.fallbackProvider,
        ),
        targeted_provider_timeout_ms: targetedProviderTimeoutMs(
          config.primaryProvider,
        ),
        photo_primary_runs: photoResults.length,
        targeted_reinspection: targetedStatus,
        targeted_decision: targetedDecisionAudit,
      },
    };
    const { data: finalized, error: finalizeError } = await supabase.rpc(
      "finalize_analysis_result_v3",
      {
        p_user_id: userID,
        p_analysis_id: analysisID,
        p_msg_id: msgID,
        p_generation: generation,
        p_claim_token: claimToken,
        p_engine_run_id: engineRunID,
        p_findings: product.findings,
        p_analysis_result: product.analysisResult,
        p_photo_summaries: product.photoSummaries,
        p_fact_lineage: product.factLineage,
        p_module_audits: product.moduleAudits,
        p_inspection_signals: product.inspectionSignals,
      },
    );
    if (finalizeError || finalized?.ok !== true) {
      throw new Error(
        `finalize_v3_failed:${
          safeText(finalizeError?.message ?? finalized?.state)
        }`,
      );
    }
    try {
      await refreshTrainingCardSnapshot(supabase, {
        userID,
        analysisID,
      });
    } catch (snapshotError) {
      // Finalization is already committed. Keep the analysis successful and
      // let the result-hub load path self-heal this idempotent projection.
      console.warn(
        "vNext training snapshot skipped",
        safeText(snapshotError, 240),
      );
    }
    try {
      await refreshApprovedNotebookAdvisories(supabase, {
        userID,
        analysisID,
      });
    } catch (snapshotError) {
      // Legacy/vNext routing may still complete older jobs. It gets the same
      // isolated notebook projection without changing its analysis payload.
      console.warn(
        "vNext notebook advisory snapshot skipped",
        safeText(snapshotError, 240),
      );
    }
    if (!checkpointOnlyRefinalize) {
      await sendCompletionPush({
        supabaseUrl,
        serviceRoleKey,
        userID,
        analysisID,
        requestID,
        supportID,
      });
    }
    return json(200, {
      ok: true,
      status: "completed",
      code: "completed",
      analysis_id: analysisID,
      engine: "vnext",
      finding_count: product.findings.length,
      photo_run_count: photoResults.length,
      targeted_reinspection: targetedStatus,
      duration_ms: Date.now() - startedAt,
      request_id: requestID,
      support_id: supportID,
    });
  } catch (error) {
    if (error instanceof ProviderBackgroundPendingError) {
      return json(202, {
        ok: true,
        status: "processing",
        code: error.code,
        provider: "openai",
        model: "gpt-5.6-luna",
        provider_status: error.providerStatus,
        provider_request_id: error.providerRequestID,
        retry_after_seconds: error.retryAfterSeconds,
        analysis_id: analysisID,
        request_id: requestID,
        support_id: supportID,
      });
    }
    console.error(
      "analyze-vnext failed",
      JSON.stringify({
        analysis_id: analysisID,
        request_id: requestID,
        support_id: supportID,
        error: safeText(error, 500),
      }),
    );
    if (engineRunID) {
      await supabase.rpc("fail_analysis_engine_run_v3", {
        p_user_id: userID,
        p_engine_run_id: engineRunID,
        p_error_code: error instanceof ProviderCallError
          ? error.code
          : safeText(error, 120),
      });
    }
    return json(500, {
      ok: false,
      code: error instanceof ProviderCallError
        ? error.code
        : "vnext_analysis_failed",
      request_id: requestID,
      support_id: supportID,
    });
  }
});
