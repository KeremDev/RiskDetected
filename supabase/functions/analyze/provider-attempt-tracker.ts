export type ProviderAttemptReason =
  | "initial"
  | "coverage_schema_fallback"
  | "layer_schema_fallback"
  | "max_tokens_retry"
  | "invalid_json_fallback"
  | "key_fallback"
  | "model_fallback"
  | "provider_fallback";

export type ProviderAttemptRecord = {
  sequence: number;
  provider: "gemini" | "groq";
  model: string;
  api_key_alias: string | null;
  reason: ProviderAttemptReason;
  http_status: number | null;
  outcome: string;
  duration_ms: number;
  input_tokens: number;
  output_tokens: number;
  thoughts_tokens: number;
  total_tokens: number;
};

export type ProviderAttemptInput =
  & Omit<
    ProviderAttemptRecord,
    | "sequence"
    | "duration_ms"
    | "input_tokens"
    | "output_tokens"
    | "thoughts_tokens"
    | "total_tokens"
  >
  & {
    duration_ms?: unknown;
    input_tokens?: unknown;
    output_tokens?: unknown;
    thoughts_tokens?: unknown;
    total_tokens?: unknown;
  };

const MAX_PROVIDER_ATTEMPTS = 32;

function safeCount(value: unknown): number {
  const numeric = Math.round(Number(value));
  return Number.isFinite(numeric) && numeric > 0 ? numeric : 0;
}

function safeDuration(value: unknown): number {
  const numeric = Math.round(Number(value));
  return Number.isFinite(numeric) && numeric >= 0 ? numeric : 0;
}

export class ProviderAttemptTracker {
  #attempts: ProviderAttemptRecord[] = [];
  #totalTokens = 0;
  #requestCount = 0;

  record(input: ProviderAttemptInput): void {
    this.#requestCount += 1;
    const inputTokens = safeCount(input.input_tokens);
    const outputTokens = safeCount(input.output_tokens);
    const thoughtsTokens = safeCount(input.thoughts_tokens);
    const explicitTotal = safeCount(input.total_tokens);
    const totalTokens = explicitTotal > 0
      ? explicitTotal
      : inputTokens + outputTokens + thoughtsTokens;
    this.#totalTokens += totalTokens;

    if (this.#attempts.length >= MAX_PROVIDER_ATTEMPTS) return;
    this.#attempts.push({
      sequence: this.#requestCount,
      provider: input.provider,
      model: String(input.model).slice(0, 120),
      api_key_alias: input.api_key_alias
        ? String(input.api_key_alias).slice(0, 120)
        : null,
      reason: input.reason,
      http_status: typeof input.http_status === "number" &&
          Number.isFinite(input.http_status)
        ? Math.round(input.http_status)
        : null,
      outcome: String(input.outcome).slice(0, 80),
      duration_ms: safeDuration(input.duration_ms),
      input_tokens: inputTokens,
      output_tokens: outputTokens,
      thoughts_tokens: thoughtsTokens,
      total_tokens: totalTokens,
    });
  }

  get requestCount(): number {
    return this.#requestCount;
  }

  get totalTokens(): number {
    return this.#totalTokens;
  }

  snapshot(): ProviderAttemptRecord[] {
    return this.#attempts.map((item) => ({ ...item }));
  }
}
