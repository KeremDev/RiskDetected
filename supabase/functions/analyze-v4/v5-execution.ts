import type { ResolvedVNextConfig } from "../analyze-vnext/compute-profile.ts";
import {
  type StructuredGeminiResponse,
  V4ProviderError,
  type V4ProviderUsage,
} from "./provider.ts";
import { parseV5Output } from "./v5-engine.ts";

export function v5ProviderKey(
  pool: string,
  getSecret: (name: string) => string | undefined,
): string | null {
  const names = pool === "free_standard"
    ? ["GEMINI_API_KEY_PRIMARY", "GEMINI_API_KEY"]
    : ["GEMINI_API_KEY_PAID", "GEMINI_PAID_API_KEY"];
  // Never rotate projects to bypass a quota, or silently charge a free route.
  for (const name of names) {
    const value = getSecret(name)?.trim();
    if (value) return value;
  }
  return null;
}

export function v5AttemptLimit(
  snapshot: Record<string, unknown>,
  config: ResolvedVNextConfig,
): 1 | 2 {
  const engine = record(snapshot.engine_config);
  const routing = record(snapshot.compute_routing);
  return engine.v5_same_model_retry_enabled === true &&
      routing.source === "trusted_analyze_enqueue" &&
      routing.ai_execution_route === "paid_plan" &&
      ["plus", "pro"].includes(String(routing.product_plan)) &&
      config.providerPool !== "free_standard"
    ? 2
    : 1;
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

const ZERO_USAGE: V4ProviderUsage = {
  inputTokens: 0,
  outputTokens: 0,
  reasoningTokens: 0,
  cachedInputTokens: 0,
  costUSD: 0,
  standardEquivalentCostUSD: 0,
};

function usage(value: unknown): V4ProviderUsage {
  const source = record(value);
  return Object.fromEntries(
    Object.keys(ZERO_USAGE).map((key) => [
      key,
      Math.max(0, Number(source[key]) || 0),
    ]),
  ) as V4ProviderUsage;
}

function addUsage(a: V4ProviderUsage, b?: V4ProviderUsage): V4ProviderUsage {
  return Object.fromEntries(
    Object.keys(ZERO_USAGE).map((key) => [
      key,
      a[key as keyof V4ProviderUsage] +
      (b?.[key as keyof V4ProviderUsage] ?? 0),
    ]),
  ) as V4ProviderUsage;
}

export type V5Checkpoint = {
  version: 1;
  model: string;
  identity: string;
  status: "running" | "completed" | "failed";
  attemptCount: number;
  usage: V4ProviderUsage;
  output?: ReturnType<typeof parseV5Output>;
  finishReason?: string;
  retryable?: boolean;
  retryAt?: number;
  errorCode?: string;
};

export type V5AttemptEvent = {
  id: string;
  number: number;
  kind: "primary" | "technical_retry";
  reason: string | null;
  state: "received" | "persisted" | "failed";
  response?: StructuredGeminiResponse;
  error?: V4ProviderError;
};

export class V5RetryPending extends Error {
  constructor(readonly retryAfterSeconds: number) {
    super("v5_retry_pending");
  }
}

/** One physical request per dispatch; retry resumes the same photo checkpoint.
 * The provider callback is unchanged between attempts (including its 110s
 * timeout). Database errors never re-enter the provider retry catch.
 */
export async function runV5PhotoAttempt(params: {
  model: string;
  identity: string;
  previous: unknown;
  maxAttempts: 1 | 2;
  maxOutputTokens: number;
  call: () => Promise<StructuredGeminiResponse>;
  checkpoint: (state: V5Checkpoint) => Promise<void>;
  recordAttempt: (event: V5AttemptEvent) => Promise<void>;
  now?: () => number;
}) {
  const now = params.now ?? Date.now;
  const previous = record(params.previous);
  if (
    Object.keys(previous).length && (
      previous.version !== 1 || previous.model !== params.model ||
      previous.identity !== params.identity
    )
  ) throw new Error("v5_checkpoint_identity_mismatch");
  const attemptCount = Math.max(0, Number(previous.attemptCount) || 0);
  const priorUsage = usage(previous.usage);
  if (previous.status === "completed") {
    return {
      output: parseV5Output(JSON.stringify(previous.output)),
      usage: priorUsage,
      finishReason: String(previous.finishReason ?? ""),
      attemptCount,
    };
  }
  if (
    attemptCount >= params.maxAttempts ||
    (previous.status === "failed" && previous.retryable !== true)
  ) {
    throw new Error(String(previous.errorCode ?? "v5_attempts_exhausted"));
  }
  if (Number(previous.retryAt) > now()) {
    throw new V5RetryPending(
      Math.ceil((Number(previous.retryAt) - now()) / 1000),
    );
  }
  const number = attemptCount + 1;
  const state: V5Checkpoint = {
    version: 1,
    model: params.model,
    identity: params.identity,
    status: "running",
    attemptCount: number,
    usage: priorUsage,
  };
  // Count before sending: a lost response cannot create unbounded calls.
  await params.checkpoint(state);
  const event = {
    id: crypto.randomUUID(),
    number,
    kind: number === 1 ? "primary" as const : "technical_retry" as const,
    reason: number === 1
      ? null
      : String(previous.errorCode ?? "ambiguous_provider_attempt"),
  };
  await params.recordAttempt({ ...event, state: "received" });
  let response: StructuredGeminiResponse | undefined;
  let output: ReturnType<typeof parseV5Output>;
  try {
    response = await params.call();
    try {
      output = parseV5Output(response.text);
    } catch {
      const truncated = response.finishReason === "MAX_TOKENS" ||
        response.usage.reasoningTokens + response.usage.outputTokens >=
          params.maxOutputTokens - 64;
      throw new V4ProviderError(
        truncated ? "v5_output_truncated" : "v5_schema_invalid",
        truncated ? "v5_output_truncated" : "v5_schema_invalid",
        response.httpStatus,
        response.durationMs,
        // Same cap cannot repair a deterministically truncated answer.
        !truncated,
        response.usage,
        response.providerRequestID,
        [],
        null,
        response.effectiveServiceTier,
      );
    }
  } catch (error) {
    const providerError = error instanceof V4ProviderError
      ? error
      : new V4ProviderError(
        "v5_provider_failed",
        "v5_provider_failed",
        null,
        0,
        false,
      );
    const retryable = providerError.retryable && number < params.maxAttempts;
    const retryMs = Math.max(5_000, providerError.retryAfterMs);
    const failed: V5Checkpoint = {
      ...state,
      status: "failed",
      usage: addUsage(priorUsage, providerError.usage),
      retryable,
      errorCode: providerError.code,
      retryAt: retryable ? now() + retryMs : undefined,
    };
    await params.recordAttempt({
      ...event,
      state: "failed",
      error: providerError,
    });
    await params.checkpoint(failed);
    if (retryable) throw new V5RetryPending(Math.ceil(retryMs / 1000));
    throw providerError;
  }
  await params.recordAttempt({ ...event, state: "persisted", response });
  const completed: V5Checkpoint = {
    ...state,
    status: "completed",
    usage: addUsage(priorUsage, response.usage),
    output,
    finishReason: response.finishReason,
  };
  await params.checkpoint(completed);
  return {
    output,
    usage: completed.usage,
    finishReason: response.finishReason,
    attemptCount: number,
  };
}
