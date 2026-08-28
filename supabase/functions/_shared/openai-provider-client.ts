import { fetchWithDeadline, type ProviderFetch } from "./provider-fetch.ts";

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";

export type OpenAIResponsesRequest = {
  apiKey: string;
  body: unknown;
  timeoutMs: number;
  idempotencyKey?: string;
  fetchImpl?: ProviderFetch;
};

export async function sendOpenAIResponse(
  request: OpenAIResponsesRequest,
): Promise<Response> {
  if (!request.apiKey.trim()) throw new Error("OPENAI_API_KEY_MISSING");
  if (
    !Number.isInteger(request.timeoutMs) || request.timeoutMs <= 0 ||
    request.timeoutMs > 300_000
  ) {
    throw new Error("OPENAI_TIMEOUT_INVALID");
  }
  return await fetchWithDeadline(
    request.fetchImpl ?? fetch,
    OPENAI_RESPONSES_URL,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${request.apiKey}`,
        "Content-Type": "application/json",
        ...(request.idempotencyKey
          ? { "Idempotency-Key": request.idempotencyKey }
          : {}),
      },
      body: JSON.stringify(request.body),
    },
    request.timeoutMs,
  );
}

export type OpenAIResponseRetrieveRequest = {
  apiKey: string;
  responseID: string;
  timeoutMs: number;
  fetchImpl?: ProviderFetch;
};

export async function retrieveOpenAIResponse(
  request: OpenAIResponseRetrieveRequest,
): Promise<Response> {
  if (!request.apiKey.trim()) throw new Error("OPENAI_API_KEY_MISSING");
  if (!/^resp_[A-Za-z0-9_-]+$/.test(request.responseID)) {
    throw new Error("OPENAI_RESPONSE_ID_INVALID");
  }
  if (
    !Number.isInteger(request.timeoutMs) || request.timeoutMs <= 0 ||
    request.timeoutMs > 300_000
  ) {
    throw new Error("OPENAI_TIMEOUT_INVALID");
  }
  return await fetchWithDeadline(
    request.fetchImpl ?? fetch,
    `${OPENAI_RESPONSES_URL}/${encodeURIComponent(request.responseID)}`,
    {
      method: "GET",
      headers: {
        "Authorization": `Bearer ${request.apiKey}`,
        "Content-Type": "application/json",
      },
    },
    request.timeoutMs,
  );
}
