import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { AnalysisServiceTier } from "../_shared/analysis-compute-profile.ts";
import { resolveVNextConfig } from "../analyze-vnext/compute-profile.ts";
import type { GeminiThinkingLevel } from "../analyze-vnext/compute-profile.ts";
import {
  getSectorProfile,
  resolveVNextSectorSelection,
} from "../analyze-vnext/sector-profile.ts";
import {
  assertCriticalCandidateFates,
  criticalDemotions,
  routeCandidates,
} from "./claim-router.ts";
import {
  type NormalizedCandidate,
  type ProviderPhotoOutput,
  type RoutedItem,
  V4_ASSURANCE_VERSION,
  V4_COVERAGE_VERSION,
  V4_DOMAIN_SCHEMA_VERSION,
  V4_ENGINE_VERSION,
  V4_PROMPT_VERSION,
  V4_PROVIDER_CONTRACT_VERSION,
  V4_QUALITY_TRACE_VERSION,
  V4_REPORT_PROJECTION_VERSION,
  V4_ROUTER_VERSION,
  V4_STANDARDS_VERSION,
} from "./contracts.ts";
import {
  activatedModulesFromScene,
  initialActiveModules,
  missingCoreCoverage,
  recoverCoverageDeterministically,
} from "./dynamic-modules.ts";
import { normalizeCandidates } from "./evidence-normalizer.ts";
import {
  assertV4PromptIntegrity,
  assertV5PromptIntegrity,
  sha256Text,
} from "./prompt-integrity.ts";
import { sendStructuredGemini, thinkingTelemetry } from "./provider.ts";
import { buildV5Prompt, buildV5SplitPrompt } from "./v5-prompt.ts";
import {
  runV5PhotoAttempt,
  v5AttemptLimit,
  v5ProviderKey,
  V5RetryPending,
} from "./v5-execution.ts";
import {
  V5_ENGINE_MODE,
  V5_PROMPT_VERSION,
  V5_RESPONSE_SCHEMA,
} from "./v5-contracts.ts";
import {
  applySplitFindings,
  looksLikePlaceholder,
  packedFindings,
  parseV5Output,
  recordsFindingsAbsorbingHazards,
  routeV5Findings,
  unfulfilledHazardLayers,
} from "./v5-engine.ts";
import { buildV4PhotoPrompt, V4_PROMPT_COMMON } from "./prompt.ts";
import {
  reconcileVerificationPass,
  summarizePrimaryPass,
  summarizeSecondPass,
  V4_VERIFICATION_PROMPT_COMMON,
} from "./verification-pass.ts";
import { languageContractCorrection } from "./language-contract.ts";
import {
  buildCoverageRepairPrompt,
  callV4Gemini,
  V4ProviderError,
  type V4ProviderResult,
} from "./provider.ts";
import {
  buildTargetedQueue,
  mergeTargetedOutput,
  type TargetedGroup,
  targetedPrompt,
} from "./targeted-queue.ts";
import { refreshTrainingCardSnapshot } from "../_shared/training-recommendations/snapshot.ts";
import { refreshApprovedNotebookAdvisories } from "../_shared/approved-notebook-advisory-snapshot.ts";

type JobBody = Record<string, unknown> & {
  __worker?: boolean;
  pipeline_version?: number;
  job_mode?: string;
  user_id?: string;
  analysis_id?: string;
  __queue_msg_id?: number;
  __job_generation?: number;
  __worker_claim_token?: string;
  request_id?: string;
  support_id?: string;
  photo_paths?: unknown[];
};

type PhotoInput = {
  photoID: string | null;
  photoIndex: number;
  storagePath: string;
  mimeType: string;
  base64: string;
};

type PhotoResult = {
  photo: PhotoInput;
  output: ProviderPhotoOutput;
  usage: V4ProviderResult["usage"] | null;
  attemptCount: number;
  reused: boolean;
  coverageRecovery?: {
    issues: string[];
    recoveredModules: string[];
  };
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function strings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.flatMap((item) =>
      typeof item === "string" && item.trim() ? [item.trim()] : []
    )
    : [];
}

function safe(value: unknown, max = 180): string {
  return String(value).replace(/Bearer\s+\S+/gi, "Bearer [redacted]").slice(
    0,
    max,
  );
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
  }
  return btoa(binary);
}

function sectorPrompt(sectorID: string | null): string {
  const profile = getSectorProfile(sectorID);
  if (!profile) return "";
  const equipment = profile.criticalEquipment.map((item) =>
    `${item.labels.tr}: ${item.components.join(", ")} [${
      item.checkCodes.join(", ")
    }]`
  ).join("; ");
  return [
    `Sektör=${profile.sectorId}`,
    `Zorunlu tarama=${profile.mandatoryModules.join(", ")}`,
    `Öncelikli tarama=${profile.priorityModules.join(", ")}`,
    `Görünürse kritik ekipman=${equipment}`,
    `Ölümcül mekanizma çapaları=${profile.fatalMechanismAnchors.join("; ")}`,
    `Negatif varsayım kodları=${profile.negativeRuleCodes.join(", ")}`,
    "Bu bilgi yalnız tarama önceliğidir; görünür kanıt, tehlike veya şiddet değildir.",
  ].join("\n");
}

function providerKey(): string | null {
  return Deno.env.get("GEMINI_API_KEY_PAID") ??
    Deno.env.get("GEMINI_PAID_API_KEY") ?? null;
}

// deno-lint-ignore no-explicit-any
async function recordAttempt(supabase: any, params: {
  attemptID: string;
  userID: string;
  engineRunID: string;
  photoRunID: string | null;
  kind:
    | "primary"
    | "technical_retry"
    | "provider_fallback"
    | "targeted_reinspection"
    | "verification_pass";
  number: number;
  model: string;
  state: "received" | "persisted" | "failed";
  /**
   * Only usage, ids and timings are read here, so the free engine's
   * schema-agnostic response satisfies this without carrying a v4 output.
   */
  result?: Omit<V4ProviderResult, "output"> & { output?: unknown };
  error?: V4ProviderError;
  computeProfile: string;
  providerPool: string;
  requestedTier: AnalysisServiceTier;
  fallbackReason?: string | null;
  promptSHA256: string;
  promptBundleSHA256: string;
  maxOutputTokens: number;
}) {
  const usage = params.result?.usage ?? params.error?.usage;
  const payload = {
    p_attempt_id: params.attemptID,
    p_user_id: params.userID,
    p_engine_run_id: params.engineRunID,
    p_photo_run_id: params.photoRunID,
    p_attempt_kind: params.kind,
    p_attempt_number: params.number,
    p_provider: "gemini",
    p_model: params.model,
    p_state: params.state,
    p_provider_request_id: params.result?.providerRequestID ??
      params.error?.providerRequestID ?? null,
    p_input_tokens: usage?.inputTokens ?? 0,
    p_output_tokens: usage?.outputTokens ?? 0,
    p_reasoning_tokens: usage?.reasoningTokens ?? 0,
    p_cached_input_tokens: usage?.cachedInputTokens ?? 0,
    p_cost_usd: usage?.costUSD ?? 0,
    p_duration_ms: params.result?.durationMs ?? params.error?.durationMs ??
      null,
    p_http_status: params.result?.httpStatus ?? params.error?.httpStatus ??
      null,
    p_error_code: params.error?.code ?? null,
    p_compute_profile: params.computeProfile,
    p_provider_pool: params.providerPool,
    p_requested_service_tier: params.requestedTier,
    p_effective_service_tier: params.result?.effectiveServiceTier ??
      params.error?.effectiveServiceTier ?? null,
    p_standard_equivalent_cost_usd: usage?.standardEquivalentCostUSD ?? 0,
    p_service_tier_fallback_reason: params.fallbackReason ?? null,
    p_prompt_sha256: params.promptSHA256,
    p_prompt_bundle_sha256: params.promptBundleSHA256,
    p_max_output_tokens: params.maxOutputTokens,
  };
  let failure = "attempt_record_failed";
  for (let retry = 0; retry < 2; retry += 1) {
    const { data, error } = await supabase.rpc(
      "record_analysis_provider_attempt_v5",
      payload,
    );
    if (!error && data?.ok === true) return;
    failure = safe(error?.message ?? data?.reason_code ?? data?.state);
  }
  throw new Error(`v4_provider_telemetry_failed:${failure}`);
}

// deno-lint-ignore no-explicit-any
async function checkpointPhoto(supabase: any, params: {
  userID: string;
  engineRunID: string;
  photo: PhotoInput;
  model: string;
  status: "running" | "completed" | "failed";
  attemptCount: number;
  output?: unknown;
  result?: Omit<V4ProviderResult, "output">;
  errorCode?: string;
}): Promise<string | null> {
  const serialized = params.output ? JSON.stringify(params.output) : "";
  const { data, error } = await supabase.rpc(
    "checkpoint_analysis_photo_run_v3",
    {
      p_user_id: params.userID,
      p_engine_run_id: params.engineRunID,
      p_photo_id: params.photo.photoID,
      p_photo_index: params.photo.photoIndex,
      p_storage_path: params.photo.storagePath,
      p_provider: "gemini",
      p_model: params.model,
      p_status: params.status,
      p_attempt_count: params.attemptCount,
      p_normalized_output: params.output ?? null,
      p_output_sha256: serialized ? await sha256Text(serialized) : null,
      p_input_tokens: params.result?.usage.inputTokens ?? 0,
      p_output_tokens: params.result?.usage.outputTokens ?? 0,
      p_reasoning_tokens: params.result?.usage.reasoningTokens ?? 0,
      p_cost_usd: params.result?.usage.costUSD ?? 0,
      p_duration_ms: params.result?.durationMs ?? null,
      p_error_code: params.errorCode ?? null,
    },
  );
  if (error || data?.ok !== true) {
    throw new Error(
      `photo_checkpoint_failed:${safe(error?.message ?? data?.state)}`,
    );
  }
  return typeof data.photo_run_id === "string" ? data.photo_run_id : null;
}

async function analyzePhoto(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userID: string;
  engineRunID: string;
  photo: PhotoInput;
  prompt: string;
  model: string;
  key: string;
  computeProfile: "premium" | "economy";
  providerPool: string;
  serviceTier: AnalysisServiceTier;
  thinking: number;
  thinkingLevel: GeminiThinkingLevel;
  retryThinking: number;
  maxOutput: number;
  requiredModules: ReturnType<typeof initialActiveModules>;
  promptSHA256: string;
  promptBundleSHA256: string;
  outputLanguage: string;
}): Promise<PhotoResult> {
  const attempts: Array<{
    kind: "primary" | "technical_retry" | "provider_fallback";
    tier: AnalysisServiceTier;
    thinking: number;
    fallbackReason?: string;
    prompt: string;
  }> = [{
    kind: "primary",
    tier: params.serviceTier,
    thinking: params.thinking,
    prompt: params.prompt,
  }];
  let attempt = 0;
  let lastError: V4ProviderError | null = null;
  let schemaRetryAdded = false;
  let languageRetryAdded = false;
  let flexFallbackAdded = false;
  while (attempt < attempts.length) {
    const spec = attempts[attempt];
    attempt += 1;
    const attemptID = crypto.randomUUID();
    try {
      const result = await callV4Gemini({
        apiKey: params.key,
        model: params.model,
        prompt: spec.prompt,
        imageData: params.photo.base64,
        mimeType: params.photo.mimeType,
        timeoutMs: 110_000,
        thinkingBudget: spec.thinking,
        thinkingLevel: params.thinkingLevel,
        maxOutputTokens: params.maxOutput,
        serviceTier: spec.tier,
        requiredModules: params.requiredModules,
        expectedLanguage: params.outputLanguage,
      });
      const photoRunID = await checkpointPhoto(params.supabase, {
        userID: params.userID,
        engineRunID: params.engineRunID,
        photo: params.photo,
        model: params.model,
        status: "completed",
        attemptCount: attempt,
        output: result.output,
        result,
      });
      await recordAttempt(params.supabase, {
        attemptID,
        userID: params.userID,
        engineRunID: params.engineRunID,
        photoRunID,
        kind: spec.kind,
        number: attempt,
        model: params.model,
        state: "persisted",
        result,
        computeProfile: params.computeProfile,
        providerPool: spec.tier === "flex" ? "paid_flex" : "paid_standard",
        requestedTier: spec.tier,
        fallbackReason: spec.fallbackReason,
        promptSHA256: params.promptSHA256,
        promptBundleSHA256: params.promptBundleSHA256,
        maxOutputTokens: params.maxOutput,
      });
      return {
        photo: params.photo,
        output: result.output,
        usage: result.usage,
        attemptCount: attempt,
        reused: false,
      };
    } catch (unknownError) {
      const error = unknownError instanceof V4ProviderError
        ? unknownError
        : new V4ProviderError(
          safe(unknownError),
          "provider_unknown_error",
          null,
          0,
          false,
        );
      lastError = error;
      // Which clause of the contract the provider broke, not just that it broke
      // one. `provider_schema_invalid` reached the attempts table with no
      // detail anywhere, so a gemini-3.7-flash trial that failed two of three
      // calls could not be told apart from a model that saw nothing -- and the
      // two call for opposite decisions.
      console.error(
        "v4 provider attempt failed",
        JSON.stringify({
          engine_run_id: params.engineRunID,
          model: params.model,
          kind: spec.kind,
          attempt,
          code: error.code,
          detail: safe(error.message, 400),
          schema_issues: error.schemaIssues.slice(0, 6),
        }),
      );
      // Coverage-only defects do not justify paying for a second vision pass.
      // The candidate payload already passed the semantic schema; close only
      // the missing coverage rows deterministically and preserve its facts.
      if (
        error.schemaIssues.length > 0 && error.recoverableOutput && error.usage
      ) {
        const recovery = recoverCoverageDeterministically(
          error.recoverableOutput,
          params.requiredModules,
        );
        const recoveredResult: V4ProviderResult = {
          output: recovery.output,
          providerRequestID: error.providerRequestID ?? null,
          durationMs: error.durationMs,
          httpStatus: error.httpStatus ?? 200,
          requestedServiceTier: spec.tier,
          effectiveServiceTier: error.effectiveServiceTier ?? spec.tier,
          usage: error.usage,
        };
        const photoRunID = await checkpointPhoto(params.supabase, {
          userID: params.userID,
          engineRunID: params.engineRunID,
          photo: params.photo,
          model: params.model,
          status: "completed",
          attemptCount: attempt,
          output: recovery.output,
          result: recoveredResult,
        });
        await recordAttempt(params.supabase, {
          attemptID,
          userID: params.userID,
          engineRunID: params.engineRunID,
          photoRunID,
          kind: spec.kind,
          number: attempt,
          model: params.model,
          state: "persisted",
          result: recoveredResult,
          computeProfile: params.computeProfile,
          providerPool: spec.tier === "flex" ? "paid_flex" : "paid_standard",
          requestedTier: spec.tier,
          fallbackReason: "deterministic_coverage_recovery",
          promptSHA256: params.promptSHA256,
          promptBundleSHA256: params.promptBundleSHA256,
          maxOutputTokens: params.maxOutput,
        });
        return {
          photo: params.photo,
          output: recovery.output,
          usage: recovery.issues.length > 0 ? recoveredResult.usage : null,
          attemptCount: attempt,
          reused: false,
          coverageRecovery: {
            issues: recovery.issues,
            recoveredModules: recovery.recoveredModules,
          },
        };
      }
      await recordAttempt(params.supabase, {
        attemptID,
        userID: params.userID,
        engineRunID: params.engineRunID,
        photoRunID: null,
        kind: spec.kind,
        number: attempt,
        model: params.model,
        state: "failed",
        error,
        computeProfile: params.computeProfile,
        providerPool: spec.tier === "flex" ? "paid_flex" : "paid_standard",
        requestedTier: spec.tier,
        fallbackReason: spec.fallbackReason,
        promptSHA256: params.promptSHA256,
        promptBundleSHA256: params.promptBundleSHA256,
        maxOutputTokens: params.maxOutput,
      });
      if (
        !languageRetryAdded && error.code === "provider_output_language_invalid"
      ) {
        // One retry, with the failure named. Publishing an English report to a
        // Turkish reader is worse than the cost of asking again.
        languageRetryAdded = true;
        attempts.push({
          kind: "technical_retry",
          tier: spec.tier,
          thinking: params.retryThinking,
          prompt: languageContractCorrection(params.prompt),
        });
      } else if (
        !schemaRetryAdded && error.code === "provider_schema_invalid"
      ) {
        schemaRetryAdded = true;
        attempts.push({
          kind: "technical_retry",
          tier: spec.tier,
          thinking: params.retryThinking,
          prompt: error.schemaIssues.length > 0
            ? buildCoverageRepairPrompt(
              params.prompt,
              error.schemaIssues,
              params.requiredModules,
            )
            : `${params.prompt}\n\nTEKNİK SÖZLEŞME DÜZELTMESİ\n- Önceki JSON şema doğrulamasından geçmedi (${
              safe(error.message)
            }). Aynı görsel kanıta bağlı kalarak eksiksiz tek JSON üret.`,
        });
      } else if (
        !flexFallbackAdded && params.computeProfile === "economy" &&
        spec.tier === "flex" &&
        [
          "provider_rate_limited",
          "provider_unavailable",
          "provider_transport_error",
        ].includes(error.code)
      ) {
        flexFallbackAdded = true;
        attempts.push({
          kind: "provider_fallback",
          tier: "standard",
          thinking: params.thinking,
          fallbackReason: error.code,
          prompt: spec.prompt,
        });
      }
    }
  }
  await checkpointPhoto(params.supabase, {
    userID: params.userID,
    engineRunID: params.engineRunID,
    photo: params.photo,
    model: params.model,
    status: "failed",
    attemptCount: attempt,
    errorCode: lastError?.code ?? "photo_analysis_failed",
  });
  throw lastError ?? new Error("photo_analysis_failed");
}

/**
 * Scored findings and unscored assurance/verification items used to compete for
 * the same eight slots, and whatever lost was decided by display_order, whose
 * final tie-break is the Turkish alphabet. On a three-photo run that produced
 * four findings, one verification request and four assurance items, the storage
 * tank's "Proses bütünlüğü" assurance was cut purely because P sorts after K and
 * M -- and nothing anywhere recorded that it had been cut.
 *
 * Findings keep their own budget, unscored items get a separate one, and within
 * each group the survivors are chosen by consequence, never by name.
 */
function boundedVisibleItems(
  items: RoutedItem[],
  maxFindings = 8,
  // Six was too tight once verification requests joined the same budget: a run
  // with three of them cut the crane's periodic-inspection assurance and the
  // machine-guard assurance, both of which are legally required checks, to make
  // room for barrier claims the photograph did not support.
  maxUnscored = 8,
): { kept: RoutedItem[]; excluded: Array<{ title: string; reason: string }> } {
  const internal = items.filter((item) =>
    !["observed_finding", "assurance_requirement", "verification_request"]
      .includes(item.item_class)
  );
  const findings = items.filter((item) =>
    item.item_class === "observed_finding"
  );
  const unscored = items.filter((item) =>
    ["assurance_requirement", "verification_request"].includes(item.item_class)
  );

  const fkScore = (item: RoutedItem) => {
    const raw = item.score_payload?.fk_score ??
      (item.fk_probability ?? 0) * (item.fk_frequency ?? 0) *
        (item.fk_severity ?? 0);
    return typeof raw === "number" ? raw : 0;
  };
  const criticality = (item: RoutedItem) =>
    item.criticality === "fatal"
      ? 0
      : item.criticality === "permanent"
      ? 1
      : item.criticality === "serious"
      ? 2
      : 3;

  const keptFindings = [...findings].sort((a, b) =>
    criticality(a) - criticality(b) ||
    fkScore(b) - fkScore(a) ||
    a.display_order - b.display_order
  );
  const consequence = (item: RoutedItem) =>
    typeof item.internal_priority?.consequence_rank === "number"
      ? item.internal_priority.consequence_rank as number
      : 99;
  const keptUnscored = [...unscored].sort((a, b) =>
    criticality(a) - criticality(b) ||
    consequence(a) - consequence(b) ||
    a.display_order - b.display_order
  );

  const droppedFindings = keptFindings.slice(maxFindings);
  const droppedUnscored = keptUnscored.slice(maxUnscored);
  const excluded = [
    ...droppedFindings.map((item) => ({
      title: item.title,
      reason: "finding_budget",
    })),
    ...droppedUnscored.map((item) => ({
      title: item.title,
      reason: "unscored_budget",
    })),
  ];

  const kept = [
    ...keptFindings.slice(0, maxFindings),
    ...keptUnscored.slice(0, maxUnscored),
    ...internal,
  ].sort((a, b) => a.display_order - b.display_order);
  kept.forEach((item, index) => {
    item.ordinal = index + 1;
    item.display_order = index + 1;
  });
  return { kept, excluded };
}

// deno-lint-ignore no-explicit-any
async function checkpointTargeted(supabase: any, params: {
  userID: string;
  engineRunID: string;
  group: TargetedGroup;
  status: "queued" | "running" | "completed" | "failed" | "budget_excluded";
  attemptID?: string | null;
  result?: unknown;
}) {
  const { error } = await supabase.rpc("checkpoint_analysis_targeted_run_v4", {
    p_user_id: params.userID,
    p_engine_run_id: params.engineRunID,
    p_region_key: params.group.regionKey,
    p_candidate_ids: params.group.candidateIDs,
    p_photo_index: params.group.photoIndex,
    p_status: params.status,
    p_provider_attempt_id: params.attemptID ?? null,
    p_result: params.result ?? null,
  });
  if (error) {
    console.warn("v4 targeted checkpoint skipped", safe(error.message));
  }
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { code: "method_not_allowed" });
  const started = Date.now();
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
    body.job_mode === "repair" ||
    !userID || !analysisID || !claimToken || !Number.isInteger(msgID) ||
    msgID <= 0 ||
    !Number.isInteger(generation) || generation <= 0
  ) {
    return json(400, { code: "v4_worker_contract_invalid" });
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
      "begin_analysis_engine_run_v4",
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
      typeof begin.engine_run_id !== "string"
    ) {
      return json(409, {
        code: String(begin?.state ?? "v4_engine_run_rejected"),
      });
    }
    engineRunID = begin.engine_run_id;
    if (begin.state === "completed") {
      return json(200, {
        ok: true,
        status: "already_completed",
        code: "completed",
      });
    }
    const snapshot = record(begin.config_snapshot);
    const engineConfig = record(snapshot.engine_config);
    const promptSHA = await assertV4PromptIntegrity(engineConfig.prompt_sha256);
    if (
      begin.engine_version !== V4_ENGINE_VERSION ||
      begin.schema_version !== V4_DOMAIN_SCHEMA_VERSION ||
      begin.prompt_version !== V4_PROMPT_VERSION ||
      begin.policy_version !== V4_ROUTER_VERSION
    ) {
      throw new Error("v4_runtime_snapshot_mismatch");
    }

    const { data: analysis, error: analysisError } = await supabase.from(
      "analyses",
    )
      .select(
        "id,user_id,status,analysis_sector,output_language,plan_at_creation,canvas,localization_snapshot,regulatory_reference_policy",
      )
      .eq("id", analysisID).eq("user_id", userID).maybeSingle();
    if (analysisError || !analysis) throw new Error("analysis_not_found");
    const requestedPaths = [...new Set(strings(body.photo_paths))].slice(0, 3);
    if (requestedPaths.length === 0) throw new Error("photo_required");
    const { data: rows, error: photoError } = await supabase.from("photos")
      .select("id,storage_path,mime_type,sequence_index")
      .eq("analysis_id", analysisID).eq("user_id", userID).in(
        "storage_path",
        requestedPaths,
      );
    if (photoError) {
      throw new Error(`photo_metadata_failed:${safe(photoError.message)}`);
    }
    const byPath = new Map(
      (rows ?? []).map((
        row: Record<string, unknown>,
      ) => [String(row.storage_path), row]),
    );
    const ordered = requestedPaths.sort((a, b) =>
      Number(byPath.get(a)?.sequence_index ?? 99) -
      Number(byPath.get(b)?.sequence_index ?? 99)
    );
    const photos: PhotoInput[] = await Promise.all(
      ordered.map(async (path, fallbackIndex) => {
        const row = byPath.get(path);
        if (!row) throw new Error("photo_ownership_mismatch");
        const { data: blob, error } = await supabase.storage.from("photos")
          .download(path);
        if (error || !blob) {
          throw new Error(`photo_download_failed:${safe(error?.message)}`);
        }
        const bytes = new Uint8Array(await blob.arrayBuffer());
        if (bytes.byteLength === 0 || bytes.byteLength > 15 * 1024 * 1024) {
          throw new Error("photo_size_invalid");
        }
        return {
          photoID: typeof row.id === "string" ? row.id : null,
          photoIndex: Number.isInteger(Number(row.sequence_index))
            ? Number(row.sequence_index)
            : fallbackIndex + 1,
          storagePath: path,
          mimeType: typeof row.mime_type === "string"
            ? row.mime_type
            : "image/jpeg",
          base64: bytesToBase64(bytes),
        };
      }),
    );
    if (
      photos.map((photo) => photo.photoIndex).sort().some((value, index) =>
        value !== index + 1
      )
    ) throw new Error("photo_sequence_invalid");
    const config = resolveVNextConfig(snapshot, photos.length);
    if (config.primaryProvider !== "gemini") {
      throw new Error("v4_gemini_only_contract");
    }
    if (
      config.providerPool === "free_standard" &&
      analysis.plan_at_creation !==
        record(snapshot.compute_routing).product_plan
    ) {
      throw new Error("free_pool_plan_mismatch");
    }
    const key = config.providerPool === "free_standard"
      ? v5ProviderKey(config.providerPool, (name) => Deno.env.get(name))
      : providerKey();
    if (!key) throw new Error("missing_ai_secret");
    const sectorSelection = resolveVNextSectorSelection(
      analysis.analysis_sector,
      body.analysis_sector,
    );
    const sectorID = sectorSelection.sectorID;
    const language = typeof analysis.output_language === "string"
      ? analysis.output_language
      : "tr";
    // The free engine. One call per photograph, the model's own assessment,
    // and the same finalize RPC -- so the app, the report and the score totals
    // are untouched and the way back is one config key. See v5-contracts.ts
    // for why it exists.
    if (String(engineConfig.engine_mode ?? "contract") === V5_ENGINE_MODE) {
      const v5PromptSHA = await assertV5PromptIntegrity(
        engineConfig.v5_prompt_sha256,
      );
      // Thinking is billed against this cap too, so an eighteen-layer sweep at
      // HIGH needs far more headroom than the contract engine's 12288.
      const freeMaxOutputTokens = Number(
        engineConfig.v5_max_output_tokens ?? config.maxProviderOutputTokens,
      );
      const freeThinkingLevel =
        typeof engineConfig.v5_gemini_thinking_level === "string"
          ? engineConfig
            .v5_gemini_thinking_level as typeof config.geminiThinkingLevel
          : config.geminiThinkingLevel;
      const priorPhotos: Record<string, unknown>[] =
        (Array.isArray(begin.photo_runs) ? begin.photo_runs : [])
          .map(record);
      const settled = await Promise.allSettled(photos.map(async (photo) => {
        const prompt = buildV5Prompt({
          photoIndex: photo.photoIndex,
          photoCount: photos.length,
          outputLanguage: language,
          sectorID,
          analysisContext: String(analysis.canvas ?? "general"),
        });
        const request = {
          apiKey: key,
          model: config.primaryModel,
          prompt,
          imageData: photo.base64,
          mimeType: photo.mimeType,
          timeoutMs: 110_000,
          thinkingBudget: config.geminiThinkingBudget,
          thinkingLevel: freeThinkingLevel,
          maxOutputTokens: freeMaxOutputTokens,
          serviceTier: config.requestedServiceTier,
          billingTier: config.providerPool === "free_standard"
            ? "free" as const
            : "paid" as const,
        };
        // No key or raw photo enters a persisted identity or telemetry field.
        const identity = await sha256Text(JSON.stringify({
          prompt,
          model: request.model,
          pool: config.providerPool,
          serviceTier: request.serviceTier,
          thinking: freeThinkingLevel,
          thinkingBudget: request.thinkingBudget,
          maxOutputTokens: freeMaxOutputTokens,
          mimeType: photo.mimeType,
          imageHash: await sha256Text(photo.base64),
        }));
        const prior = priorPhotos.find((row) =>
          Number(row.photo_index) === photo.photoIndex &&
          row.storage_path === photo.storagePath
        );
        let photoRunID: string | null = null;
        const result = await runV5PhotoAttempt({
          model: config.primaryModel,
          identity,
          previous: prior?.normalized_output,
          maxAttempts: v5AttemptLimit(snapshot, config),
          maxOutputTokens: freeMaxOutputTokens,
          call: () => sendStructuredGemini(request, V5_RESPONSE_SCHEMA),
          checkpoint: async (state) => {
            photoRunID = await checkpointPhoto(supabase, {
              userID,
              engineRunID: engineRunID!,
              photo,
              model: config.primaryModel,
              status: state.status,
              attemptCount: state.attemptCount,
              output: state,
              errorCode: state.errorCode,
              result: {
                providerRequestID: null,
                durationMs: 0,
                httpStatus: 200,
                requestedServiceTier: config.requestedServiceTier,
                effectiveServiceTier: config.requestedServiceTier,
                usage: state.usage,
              },
            });
          },
          recordAttempt: (event) =>
            recordAttempt(supabase, {
              attemptID: event.id,
              userID,
              engineRunID: engineRunID!,
              photoRunID,
              kind: event.kind,
              number: event.number,
              model: config.primaryModel,
              state: event.state,
              computeProfile: config.computeProfile,
              providerPool: config.providerPool,
              requestedTier: config.requestedServiceTier,
              fallbackReason: event.reason,
              promptSHA256: v5PromptSHA,
              promptBundleSHA256: v5PromptSHA,
              maxOutputTokens: freeMaxOutputTokens,
              error: event.error,
              result: event.response
                ? {
                  ...event.response,
                  requestedServiceTier: config.requestedServiceTier,
                }
                : undefined,
            }),
        });
        return { photoIndex: photo.photoIndex, ...result };
      }));
      // Wait for every photo to checkpoint before releasing the claim. One
      // photo failing must not leave other paid calls running unobserved.
      const failures = settled.filter((entry) => entry.status === "rejected");
      const terminal = failures.find((entry) =>
        !(entry.reason instanceof V5RetryPending)
      );
      if (terminal) throw terminal.reason;
      if (failures.length) {
        return json(202, {
          ok: true,
          code: "v5_retry_pending",
          retry_after_seconds: Math.max(
            ...failures.map((entry) =>
              (entry.reason as V5RetryPending).retryAfterSeconds
            ),
          ),
        });
      }
      const outputs = settled.flatMap((entry) =>
        entry.status === "fulfilled" ? [entry.value] : []
      );

      // The follow-up call, only where the primary answer packed hazards into
      // one record. Seven rounds of prompt rules did not move the model off
      // ~3200 tokens and four findings; c6cbe445 proved nothing truncates it
      // and 2e350e22 ruled out thinking competing for the budget. A length
      // prior no instruction reaches needs a second call, not an eighth rule.
      const splitOutcomes: Array<Record<string, unknown>> = [];
      // Config-gated so the second call can be turned off without a deploy.
      // It doubles the cost of a packed run -- $0.051 against $0.031 -- and in
      // analysis 078cd96f the primary pass alone produced seven findings, so
      // how far one request gets on its own is worth measuring before paying
      // for two.
      const splitPassEnabled = engineConfig.v5_split_pass_enabled !== false &&
        config.providerPool !== "free_standard";
      for (
        let index = 0;
        splitPassEnabled && index < outputs.length;
        index += 1
      ) {
        const entry = outputs[index];
        const packed = packedFindings(entry.output);
        if (packed.length === 0) continue;
        const photo = photos.find((item) =>
          item.photoIndex === entry.photoIndex
        );
        if (!photo) continue;
        const hazardNotes = entry.output.layer_scan.filter((row) =>
          row.result === "tehlike_var" &&
          packed.some((finding) => finding.layers.includes(row.layer))
        ).map((row) => ({ layer: row.layer, note: row.note }));
        const attemptID = crypto.randomUUID();
        const telemetry = {
          attemptID,
          userID,
          engineRunID: engineRunID!,
          photoRunID: null,
          kind: "targeted_reinspection" as const,
          number: 1,
          model: config.primaryModel,
          computeProfile: config.computeProfile,
          providerPool: config.providerPool,
          requestedTier: config.requestedServiceTier,
          promptSHA256: v5PromptSHA,
          promptBundleSHA256: v5PromptSHA,
          maxOutputTokens: freeMaxOutputTokens,
        };
        try {
          const second = await sendStructuredGemini({
            apiKey: key,
            model: config.primaryModel,
            prompt: buildV5SplitPrompt({
              photoIndex: entry.photoIndex,
              photoCount: photos.length,
              outputLanguage: language,
              sectorID,
              packed: packed.map((finding) => ({
                title: finding.title,
                layers: finding.layers,
                description: finding.description,
              })),
              scanNotes: hazardNotes,
            }),
            imageData: photo.base64,
            mimeType: photo.mimeType,
            timeoutMs: 110_000,
            thinkingBudget: config.geminiThinkingBudget,
            thinkingLevel: freeThinkingLevel,
            maxOutputTokens: freeMaxOutputTokens,
            serviceTier: config.requestedServiceTier,
          }, V5_RESPONSE_SCHEMA);
          await recordAttempt(supabase, {
            ...telemetry,
            state: "persisted",
            result: {
              ...second,
              requestedServiceTier: config.requestedServiceTier,
            },
          });
          const applied = applySplitFindings(
            entry.output,
            parseV5Output(second.text).findings,
          );
          outputs[index] = { ...entry, output: applied.output };
          splitOutcomes.push({
            photo_index: entry.photoIndex,
            packed_titles: packed.map((finding) => finding.title),
            applied: applied.applied,
            reason: applied.reason,
            finish_reason: second.finishReason,
          });
        } catch (error) {
          // A failed split leaves the primary answer standing. It is a
          // second opinion, not a dependency.
          splitOutcomes.push({
            photo_index: entry.photoIndex,
            applied: false,
            reason: "split_call_failed",
            detail: safe(error instanceof Error ? error.message : error, 200),
          });
        }
      }

      const routedFree = routeV5Findings(
        outputs.map((entry) => ({
          photoIndex: entry.photoIndex,
          output: entry.output,
        })),
      );
      // Scored site findings. Assurance items are published too -- the hub
      // routes them to Uzman Görüşü -- but they are not what "no visible items"
      // is asking about, and they carry no score.
      const visibleFree = routedFree.items.filter((item) =>
        item.item_class === "observed_finding"
      );
      const assuranceFree = routedFree.items.filter((item) =>
        item.item_class === "assurance_requirement"
      );
      // A summary that came out of the prompt rather than the photograph must
      // not reach the reader; the generic fallback is more honest.
      const echoedSummary = outputs.some((entry) =>
        looksLikePlaceholder(entry.output.scene_summary)
      );
      const sum = (pick: (usage: V4ProviderResult["usage"]) => number) =>
        outputs.reduce((total, entry) => total + pick(entry.usage), 0);
      const freeBundle = {
        candidates: routedFree.candidates,
        items: routedFree.items,
        routing_ledger: routedFree.droppedFindings.map((entry) => ({
          from_state: "v5_finding",
          to_state: "hard_reject",
          reason_code: `v5_${entry.reason}`,
          details: { finding_key: entry.finding_key },
        })),
        hard_rejections: [],
        quality_trace: {
          prompt_sha256: v5PromptSHA,
          version_snapshot: {
            engine: V4_ENGINE_VERSION,
            engine_mode: V5_ENGINE_MODE,
            prompt: V5_PROMPT_VERSION,
            router: "v5-free-router-v1",
          },
          photo_coverage_matrix: outputs.map((entry) => ({
            photo_index: entry.photoIndex,
            scene_summary: entry.output.scene_summary,
            finding_count: entry.output.findings.length,
            positive_control_count: entry.output.positive_controls.length,
            // Internal only. The traversal is auditable here and reaches no
            // reader, which is the whole difference from v4's coverage matrix.
            layer_scan: entry.output.layer_scan,
            layers_with_hazard: entry.output.layer_scan.filter((row) =>
              row.result === "tehlike_var"
            ).map((row) => row.layer),
            layers_without_finding: unfulfilledHazardLayers(entry.output),
            records_findings_absorbing_hazards: recordsFindingsAbsorbingHazards(
              entry.output,
            ),
            findings_per_hazard_layer: entry.output.layer_scan.filter((row) =>
                row.result === "tehlike_var"
              ).length > 0
              ? Number(
                (entry.output.findings.length /
                  entry.output.layer_scan.filter((row) =>
                    row.result === "tehlike_var"
                  ).length).toFixed(2),
              )
              : null,
          })),
          candidate_counts: {
            raw: routedFree.candidates.length,
            critical: routedFree.candidates.filter((candidate) =>
              ["fatal", "permanent"].includes(String(candidate.criticality))
            ).length,
          },
          routing_counts: {
            observed_finding: visibleFree.length,
            positive_control: routedFree.items.length - visibleFree.length -
              assuranceFree.length,
            assurance_requirement: assuranceFree.length,
            verification_request: 0,
            not_assessable: 0,
          },
          critical_silent_drop_count: 0,
          provider_usage: {
            compute_profile: config.computeProfile,
            provider_pool: config.providerPool,
            requested_service_tier: config.requestedServiceTier,
            attempt_counts: outputs.map((entry) =>
              entry.attemptCount
            ),
            photo_count: photos.length,
            // Read from the same branch the request took, so the trace reports
            // the lever that was actually sent rather than a config value the
            // provider never saw.
            ...thinkingTelemetry(config.primaryModel, {
              thinkingBudget: config.geminiThinkingBudget,
              thinkingLevel: freeThinkingLevel,
            }),
            max_output_tokens: freeMaxOutputTokens,
            // Why the answer ended. STOP means the model chose to stop and any
            // length ceiling is its own; MAX_TOKENS means we capped it. Six
            // runs sat within 4% of 3200 visible tokens against a 32768 budget
            // and the cause was being deduced rather than read.
            finish_reasons: outputs.map((entry) => entry.finishReason),
            stopped_naturally: outputs.every((entry) =>
              entry.finishReason === "STOP"
            ),
            input_tokens: sum((usage) => usage.inputTokens),
            visible_output_tokens: sum((usage) => usage.outputTokens),
            thinking_tokens: sum((usage) => usage.reasoningTokens),
            cost_usd: sum((usage) => usage.costUSD),
          },
          v5_free: {
            // What the model said it saw, what the registry could speak about,
            // and what it could not. The last list is the registry's work
            // queue: a family that keeps appearing there is the next entry to
            // write.
            observed_assets: [
              ...new Set(
                outputs.flatMap((entry) => entry.output.observed_assets ?? []),
              ),
            ].sort(),
            expert_cards: routedFree.expertCardCount,
            expert_families_without_entry:
              routedFree.expertFamiliesWithoutEntry,
            records_findings_superseded: routedFree.recordsFindingsSuperseded,
            split_pass_enabled: splitPassEnabled,
            split_pass: splitOutcomes,
            // Recorded whether or not the split ran, so a single-request run
            // still shows how much packing it left behind.
            packed_findings: outputs.flatMap((entry) =>
              packedFindings(entry.output).map((finding) => ({
                photo_index: entry.photoIndex,
                title: finding.title,
                layers: finding.layers,
              }))
            ),
            sanitized_removals: routedFree.sanitizedCount,
            scale_snaps: routedFree.snappedCount,
            dropped_findings: routedFree.droppedFindings,
          },
          quality_flags: [
            "engine_mode_free",
            ...(echoedSummary ? ["v5_prompt_example_echoed"] : []),
            ...(outputs.some((entry) =>
                unfulfilledHazardLayers(entry.output).length > 0
              )
              ? ["v5_layer_hazard_without_finding"]
              : []),
            ...(outputs.some((entry) =>
                recordsFindingsAbsorbingHazards(entry.output).length > 0
              )
              ? ["v5_records_finding_absorbed_hazard"]
              : []),
            ...(splitOutcomes.some((entry) => entry.applied === true)
              ? ["v5_split_pass_applied"]
              : []),
            ...(splitOutcomes.some((entry) => entry.applied === false)
              ? ["v5_split_pass_rejected"]
              : []),
            ...(visibleFree.length === 0 ? ["no_visible_items"] : []),
            ...(routedFree.sanitizedCount > 0 ? ["v5_text_sanitized"] : []),
            ...(routedFree.snappedCount > 0 ? ["v5_scale_snapped"] : []),
          ],
        },
        analysis_result: {
          status_message: `Analiz tamamlandı. Destek kodu: ${supportID}`,
          ai_summary: (echoedSummary ? "" : outputs[0]?.output.scene_summary) ||
            (visibleFree.length > 0
              ? `${visibleFree.length} bulgu raporlandı.`
              : "Görüntüde kullanıcıya gösterilecek yeterli kanıt bulunamadı."),
          duration_ms: Date.now() - started,
        },
      };
      const { data: freeFinal, error: freeError } = await supabase.rpc(
        "finalize_analysis_result_v4",
        {
          p_user_id: userID,
          p_analysis_id: analysisID,
          p_msg_id: msgID,
          p_generation: generation,
          p_claim_token: claimToken,
          p_engine_run_id: engineRunID,
          p_bundle: freeBundle,
        },
      );
      if (freeError || freeFinal?.ok !== true) {
        throw new Error(
          `v5_finalize_failed:${safe(freeError?.message ?? freeFinal?.state)}`,
        );
      }
      return json(200, {
        ok: true,
        status: "completed",
        code: "completed",
        engine: V4_ENGINE_VERSION,
        engine_mode: V5_ENGINE_MODE,
        finding_count: freeFinal.finding_count,
        request_id: requestID,
        support_id: supportID,
      });
    }

    const savedRuns: Record<string, unknown>[] = Array.isArray(begin.photo_runs)
      ? begin.photo_runs.map(record)
      : [];
    const saved = new Map<number, ProviderPhotoOutput>(
      savedRuns.filter((item: Record<string, unknown>) =>
        item.status === "completed" && item.normalized_output
      ).map((item: Record<string, unknown>) => [
        Number(item.photo_index),
        item.normalized_output as ProviderPhotoOutput,
      ]),
    );
    const results = await Promise.all(
      photos.map(async (photo): Promise<PhotoResult> => {
        const checkpoint = saved.get(photo.photoIndex);
        if (checkpoint) {
          return {
            photo,
            output: checkpoint,
            usage: null,
            attemptCount: 0,
            reused: true,
          };
        }
        const prompt = buildV4PhotoPrompt({
          photoIndex: photo.photoIndex,
          photoCount: photos.length,
          outputLanguage: language,
          sectorBlock: sectorPrompt(sectorID),
          analysisContext: String(analysis.canvas ?? "general"),
          activeModules: initialActiveModules(sectorID),
        });
        return await analyzePhoto({
          supabase,
          userID,
          engineRunID: engineRunID!,
          photo,
          prompt,
          model: config.primaryModel,
          key,
          computeProfile: config.computeProfile,
          providerPool: config.providerPool,
          serviceTier: config.requestedServiceTier,
          thinking: config.geminiThinkingBudget,
          thinkingLevel: config.geminiThinkingLevel,
          retryThinking: config.geminiRetryThinkingBudget,
          maxOutput: config.maxProviderOutputTokens,
          requiredModules: initialActiveModules(sectorID),
          promptSHA256: promptSHA,
          promptBundleSHA256: promptSHA,
          outputLanguage: language,
        });
      }),
    );

    let candidates = results.flatMap((result) =>
      normalizeCandidates(result.output, result.photo.photoIndex)
    );

    // A second, independent look at the same photograph. Single photo only: a
    // multi-photo analysis already spends one call per photo and doubling that
    // is a cost decision that has not been taken. See verification-pass.ts for
    // why agreement is required in one direction and not the other.
    let verification: {
      ran: boolean;
      added: number;
      disputed: Array<{ candidate_id: string; label: string; reason: string }>;
      duplicates: number;
      error?: string;
      errorDetail?: string;
      secondPass?: Record<string, unknown>;
    } = { ran: false, added: 0, disputed: [], duplicates: 0 };
    if (photos.length === 1 && results.length === 1) {
      const primary = results[0];
      const photo = primary.photo;
      const attemptID = crypto.randomUUID();
      try {
        const second = await callV4Gemini({
          apiKey: key,
          model: config.primaryModel,
          prompt: `${V4_PROMPT_COMMON}\n\n${V4_VERIFICATION_PROMPT_COMMON}\n\n${
            summarizePrimaryPass(primary.output)
          }\n\nDEĞİŞKEN BAĞLAM\n- Fotoğraf: 1/1\n- Çıktı dili: ${language}\n- Etkin modüller: ${
            initialActiveModules(sectorID).join(", ")
          }\n\nJSON sözleşmesine tam uy. Başka metin ekleme.`,
          imageData: photo.base64,
          mimeType: photo.mimeType,
          timeoutMs: 110_000,
          thinkingBudget: config.geminiThinkingBudget,
          thinkingLevel: config.geminiThinkingLevel,
          maxOutputTokens: config.maxProviderOutputTokens,
          serviceTier: config.requestedServiceTier,
          // Coverage is established by the primary pass and this output's
          // matrix is never read, so holding the second look to the coverage
          // contract only discards valid gap-finding answers.
          requiredModules: [],
          skipCoverageContract: true,
          expectedLanguage: language,
        });
        await recordAttempt(supabase, {
          attemptID,
          userID,
          engineRunID: engineRunID!,
          photoRunID: null,
          kind: "verification_pass",
          number: 1,
          model: config.primaryModel,
          state: "persisted",
          result: second,
          computeProfile: config.computeProfile,
          providerPool: config.providerPool,
          requestedTier: config.requestedServiceTier,
          promptSHA256: promptSHA,
          promptBundleSHA256: promptSHA,
          maxOutputTokens: config.maxProviderOutputTokens,
        });
        const secondCandidates = normalizeCandidates(
          second.output,
          photo.photoIndex,
        );
        const reconciled = reconcileVerificationPass({
          primaryCandidates: candidates,
          second: second.output,
          secondCandidates,
        });
        candidates = [...candidates, ...reconciled.added];
        verification = {
          ran: true,
          added: reconciled.added.length,
          disputed: reconciled.disputed,
          duplicates: reconciled.duplicateCount,
          secondPass: summarizeSecondPass(second.output, secondCandidates),
        };
      } catch (unknownError) {
        // The second look is an improvement, not a dependency. A failure here
        // must never cost the reader the analysis the first pass already
        // produced -- it is recorded and the run continues on one pass.
        const error = unknownError instanceof V4ProviderError
          ? unknownError
          : new V4ProviderError(
            safe(unknownError),
            "verification_pass_failed",
            null,
            0,
            false,
          );
        await recordAttempt(supabase, {
          attemptID,
          userID,
          engineRunID: engineRunID!,
          photoRunID: null,
          kind: "verification_pass",
          number: 1,
          model: config.primaryModel,
          state: "failed",
          error,
          computeProfile: config.computeProfile,
          providerPool: config.providerPool,
          requestedTier: config.requestedServiceTier,
          promptSHA256: promptSHA,
          promptBundleSHA256: promptSHA,
          maxOutputTokens: config.maxProviderOutputTokens,
        });
        // The bare code said only "provider_schema_invalid" and the message was
        // nowhere, so diagnosing the first failure meant reading the parser.
        verification = {
          ...verification,
          error: error.code,
          errorDetail: safe(error.message).slice(0, 300),
        };
      }
    }

    const targetedQueue = buildTargetedQueue(candidates, config.computeProfile);
    await Promise.all(
      targetedQueue.budgetExcluded.map((group) =>
        checkpointTargeted(supabase, {
          userID,
          engineRunID: engineRunID!,
          group,
          status: "budget_excluded",
          result: {
            preserved_as: "verification_request",
            reason: "targeted_budget_excluded",
          },
        })
      ),
    );
    const targetedOutcomes = await Promise.all(
      targetedQueue.selected.map(async (group) => {
        await checkpointTargeted(supabase, {
          userID,
          engineRunID: engineRunID!,
          group,
          status: "running",
        });
        const photo = photos.find((item) =>
          item.photoIndex === group.photoIndex
        )!;
        const attemptID = crypto.randomUUID();
        try {
          const result = await callV4Gemini({
            apiKey: key,
            model: config.primaryModel,
            prompt: `${V4_PROMPT_COMMON}\n${targetedPrompt(group)}`,
            imageData: photo.base64,
            mimeType: photo.mimeType,
            timeoutMs: 80_000,
            thinkingBudget: config.geminiTargetedThinkingBudget,
            thinkingLevel: config.geminiThinkingLevel,
            maxOutputTokens: config.targetedMaxProviderOutputTokens,
            serviceTier: config.requestedServiceTier,
            // A regional reinspection must close only the module represented
            // by that target. Requiring Core-7 here turns an otherwise valid
            // focused answer into a schema failure and wastes the call.
            requiredModules: [
              ...new Set(
                group.candidates.map((candidate) => candidate.module_id),
              ),
            ],
          });
          await recordAttempt(supabase, {
            attemptID,
            userID,
            engineRunID: engineRunID!,
            photoRunID: null,
            kind: "targeted_reinspection",
            number: 1,
            model: config.primaryModel,
            state: "persisted",
            result,
            computeProfile: config.computeProfile,
            providerPool: config.providerPool,
            requestedTier: config.requestedServiceTier,
            promptSHA256: promptSHA,
            promptBundleSHA256: promptSHA,
            maxOutputTokens: config.targetedMaxProviderOutputTokens,
          });
          await checkpointTargeted(supabase, {
            userID,
            engineRunID: engineRunID!,
            group,
            status: "completed",
            attemptID,
            result: result.output,
          });
          return {
            group,
            candidates: normalizeCandidates(result.output, group.photoIndex),
            output: result.output,
            usage: result.usage,
          };
        } catch (unknownError) {
          const error = unknownError instanceof V4ProviderError
            ? unknownError
            : new V4ProviderError(
              safe(unknownError),
              "targeted_failed",
              null,
              0,
              false,
            );
          await recordAttempt(supabase, {
            attemptID,
            userID,
            engineRunID: engineRunID!,
            photoRunID: null,
            kind: "targeted_reinspection",
            number: 1,
            model: config.primaryModel,
            state: "failed",
            error,
            computeProfile: config.computeProfile,
            providerPool: config.providerPool,
            requestedTier: config.requestedServiceTier,
            promptSHA256: promptSHA,
            promptBundleSHA256: promptSHA,
            maxOutputTokens: config.targetedMaxProviderOutputTokens,
          });
          await checkpointTargeted(supabase, {
            userID,
            engineRunID: engineRunID!,
            group,
            status: "failed",
            attemptID,
            result: { error_code: error.code },
          });
          return {
            group,
            candidates: [] as NormalizedCandidate[],
            output: null,
            usage: null,
          };
        }
      }),
    );
    for (const targeted of targetedOutcomes) {
      candidates = mergeTargetedOutput(
        candidates,
        targeted.group,
        targeted.candidates,
        targeted.output,
      );
    }
    const routed = routeCandidates({
      candidates,
      photoOutputs: results.map((result) => ({
        photoIndex: result.photo.photoIndex,
        output: result.output,
      })),
      sectorID,
      referencePolicy: typeof analysis.regulatory_reference_policy === "string"
        ? analysis.regulatory_reference_policy
        : null,
    });
    assertCriticalCandidateFates(
      candidates,
      routed.items,
      routed.hardRejections,
      routed.ledger,
    );
    const bounded = boundedVisibleItems(routed.items);
    const items = bounded.kept;
    const coverageMatrix = results.map((result) => ({
      photo_index: result.photo.photoIndex,
      core_missing: missingCoreCoverage(result.output),
      active_modules: activatedModulesFromScene(result.output, sectorID),
      // module_id and outcome alone are not enough to explain a published
      // "değerlendirilemedi" line. In analysis 92788b58 excavation survived the
      // v36 activation gate on a photograph with no excavation in it, and the
      // matrix could not say whether it carried an entity reference, a sector
      // signal or neither -- the third time this run of work has been slowed by
      // a trace that recorded the verdict and dropped the reason.
      outcomes: result.output.module_coverage.map((entry) => ({
        module_id: entry.module_id,
        outcome: entry.outcome,
        activated_by: entry.activated_by ?? [],
        entity_refs: entry.entity_refs ?? [],
        candidate_keys: entry.candidate_keys ?? [],
        note: (entry.note ?? "").slice(0, 200),
      })),
      coverage_recovery: result.coverageRecovery ?? null,
    }));
    const visible = items.filter((item) =>
      ["observed_finding", "assurance_requirement", "verification_request"]
        .includes(item.item_class)
    );
    const bundle = {
      candidates,
      items,
      routing_ledger: routed.ledger,
      hard_rejections: routed.hardRejections,
      quality_trace: {
        prompt_sha256: promptSHA,
        version_snapshot: {
          engine: V4_ENGINE_VERSION,
          provider_contract: V4_PROVIDER_CONTRACT_VERSION,
          domain_schema: V4_DOMAIN_SCHEMA_VERSION,
          prompt: V4_PROMPT_VERSION,
          router: V4_ROUTER_VERSION,
          coverage: V4_COVERAGE_VERSION,
          assurance: V4_ASSURANCE_VERSION,
          standards: V4_STANDARDS_VERSION,
          quality_trace: V4_QUALITY_TRACE_VERSION,
          report_projection: V4_REPORT_PROJECTION_VERSION,
        },
        photo_coverage_matrix: coverageMatrix,
        candidate_counts: {
          raw: candidates.length,
          critical: candidates.filter((item) =>
            ["fatal", "permanent"].includes(item.criticality)
          ).length,
        },
        routing_counts: Object.fromEntries(
          [
            "observed_finding",
            "assurance_requirement",
            "verification_request",
            "positive_control",
            "not_assessable",
          ].map((klass) => [
            klass,
            items.filter((item) =>
              item.item_class === klass
            ).length,
          ]),
        ),
        critical_silent_drop_count: 0,
        // A critical candidate that had a visible, reachable event path and
        // still did not become a finding. Zero silent drops used to be
        // reported while exactly this was happening.
        critical_demotions: [...criticalDemotions],
        verification_pass: verification,
        // The report budget used to cut items with no record at all, so a
        // dropped tank assurance was indistinguishable from one the engine
        // never produced.
        report_budget_excluded: bounded.excluded,
        targeted_queue: {
          selected: targetedQueue.selected.map((item) => item.regionKey),
          budget_excluded: targetedQueue.budgetExcluded.map((item) =>
            item.regionKey
          ),
          limit: config.computeProfile === "premium" ? 2 : 1,
        },
        standards_trace: {
          registry_version: V4_STANDARDS_VERSION,
          free_text_references_allowed: false,
        },
        provider_usage: {
          compute_profile: config.computeProfile,
          photo_count: photos.length,
          ...thinkingTelemetry(config.primaryModel, {
            thinkingBudget: config.geminiThinkingBudget,
            thinkingLevel: config.geminiThinkingLevel,
          }),
          input_tokens: results.reduce(
            (sum, item) => sum + (item.usage?.inputTokens ?? 0),
            0,
          ) + targetedOutcomes.reduce(
            (sum, item) => sum + (item.usage?.inputTokens ?? 0),
            0,
          ),
          visible_output_tokens: results.reduce(
            (sum, item) => sum + (item.usage?.outputTokens ?? 0),
            0,
          ) + targetedOutcomes.reduce(
            (sum, item) => sum + (item.usage?.outputTokens ?? 0),
            0,
          ),
          thinking_tokens: results.reduce(
            (sum, item) => sum + (item.usage?.reasoningTokens ?? 0),
            0,
          ) + targetedOutcomes.reduce(
            (sum, item) => sum + (item.usage?.reasoningTokens ?? 0),
            0,
          ),
          cost_usd: results.reduce(
            (sum, item) => sum + (item.usage?.costUSD ?? 0),
            0,
          ) + targetedOutcomes.reduce(
            (sum, item) => sum + (item.usage?.costUSD ?? 0),
            0,
          ),
        },
        quality_flags: [
          ...(sectorSelection.requestMismatch
            ? ["sector_request_database_mismatch"]
            : []),
          ...(visible.length === 0 ? ["no_visible_items"] : []),
          ...(results.some((result) => result.coverageRecovery)
            ? ["deterministic_coverage_recovery_used"]
            : []),
        ],
      },
      analysis_result: {
        status_message: `Analiz tamamlandı. Destek kodu: ${supportID}`,
        ai_summary: visible.length > 0
          ? `${visible.length} kayıt değerlendirildi; yalnız doğrudan gözlenen bulgular skorlandı.`
          : "Görüntüde kullanıcıya gösterilecek yeterli kanıt bulunamadı.",
        duration_ms: Date.now() - started,
      },
    };
    const { data: finalized, error: finalizeError } = await supabase.rpc(
      "finalize_analysis_result_v4",
      {
        p_user_id: userID,
        p_analysis_id: analysisID,
        p_msg_id: msgID,
        p_generation: generation,
        p_claim_token: claimToken,
        p_engine_run_id: engineRunID,
        p_bundle: bundle,
      },
    );
    if (finalizeError || finalized?.ok !== true) {
      throw new Error(
        `v4_finalize_failed:${
          safe(finalizeError?.message ?? finalized?.state)
        }`,
      );
    }
    try {
      await refreshTrainingCardSnapshot(supabase, {
        userID,
        analysisID,
      });
    } catch (snapshotError) {
      // The committed analysis remains authoritative. Result-hub reads retry
      // the same deterministic projection if this best-effort write fails.
      console.warn(
        "v4 training snapshot skipped",
        safe(
          snapshotError instanceof Error
            ? snapshotError.message
            : snapshotError,
          240,
        ),
      );
    }
    try {
      await refreshApprovedNotebookAdvisories(supabase, {
        userID,
        analysisID,
      });
    } catch (snapshotError) {
      // The operational Risk Analizi result is already committed. Notebook
      // prose is an isolated, best-effort projection and must never fail it.
      console.warn(
        "v4 notebook advisory snapshot skipped",
        safe(
          snapshotError instanceof Error
            ? snapshotError.message
            : snapshotError,
          240,
        ),
      );
    }
    return json(200, {
      ok: true,
      status: "completed",
      code: "completed",
      engine: V4_ENGINE_VERSION,
      finding_count: finalized.finding_count,
      request_id: requestID,
      support_id: supportID,
    });
  } catch (error) {
    const code =
      safe(error instanceof Error ? error.message.split(":")[0] : error, 120) ||
      "v4_analysis_failed";
    // `code` is everything before the first colon, which is what the DB column
    // wants and what a dashboard groups by. It also threw away the only useful
    // part of a provider rejection: a Gemini 400 logged as "Gemini HTTP 400"
    // and nothing else, so the switch to gemini-3.5-flash-lite failed with no
    // way to tell which field it had objected to. The provider's own sentence
    // now travels beside the code.
    console.error(
      "v4 analysis failed",
      JSON.stringify({
        analysis_id: analysisID,
        request_id: requestID,
        code,
        detail: safe(error instanceof Error ? error.message : error, 600),
      }),
    );
    if (engineRunID) {
      await supabase.rpc("fail_analysis_engine_run_v3", {
        p_user_id: userID,
        p_engine_run_id: engineRunID,
        p_error_code: code,
      });
    }
    await supabase.rpc("record_analysis_job_failure_v2", {
      p_user_id: userID,
      p_analysis_id: analysisID,
      p_msg_id: msgID,
      p_generation: generation,
      p_claim_token: claimToken,
      p_error: code,
      p_failure_code: code,
      p_status_message: `Analiz tamamlanamadı. Destek kodu: ${supportID}`,
      p_terminal: true,
      p_raw_ai_response: { _engine: V4_ENGINE_VERSION, _support_id: supportID },
    });
    return json(500, {
      ok: false,
      code: "v4_analysis_failed",
      support_id: supportID,
    });
  }
});
