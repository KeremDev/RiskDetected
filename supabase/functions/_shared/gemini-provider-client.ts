import { fetchWithDeadline, type ProviderFetch } from "./provider-fetch.ts";

const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";

export type GeminiGenerateContentRequest = {
  apiKey: string;
  model: string;
  body: unknown;
  timeoutMs: number;
  fetchImpl?: ProviderFetch;
};

export function geminiGenerateContentURL(model: string): string {
  const normalizedModel = model.trim();
  if (!/^[a-zA-Z0-9._-]+$/.test(normalizedModel)) {
    throw new Error("GEMINI_MODEL_INVALID");
  }
  return `${GEMINI_API_BASE}/${normalizedModel}:generateContent`;
}

export function geminiRetryAfterMilliseconds(
  headers: Headers,
  nowMs = Date.now(),
): number {
  const raw = headers.get("retry-after");
  if (!raw) return 0;
  const seconds = Number(raw);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return Math.min(60_000, Math.round(seconds * 1000));
  }
  const timestamp = Date.parse(raw);
  return Number.isFinite(timestamp)
    ? Math.min(60_000, Math.max(0, timestamp - nowMs))
    : 0;
}

export async function sendGeminiGenerateContent(
  request: GeminiGenerateContentRequest,
): Promise<Response> {
  if (!request.apiKey.trim()) {
    throw new Error("GEMINI_API_KEY_MISSING");
  }
  if (
    !Number.isInteger(request.timeoutMs) ||
    request.timeoutMs <= 0 ||
    request.timeoutMs > 300_000
  ) {
    throw new Error("GEMINI_TIMEOUT_INVALID");
  }
  return await fetchWithDeadline(
    request.fetchImpl ?? fetch,
    geminiGenerateContentURL(request.model),
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": request.apiKey,
      },
      body: JSON.stringify(request.body),
    },
    request.timeoutMs,
  );
}
