import {
  classifyFcmResponse,
  classifyFcmTransportError,
  MAX_APNS_ATTEMPTS,
  type PushClassification,
} from "../_shared/notification-contract.ts";

export type FcmAttempt = PushClassification & {
  attemptNumber: number;
  httpStatus: number | null;
  messageID: string | null;
  durationMs: number;
};

export type FcmDeliveryResult = {
  final: FcmAttempt;
  attempts: FcmAttempt[];
};

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

type WaitLike = (milliseconds: number) => Promise<void>;

const defaultWait: WaitLike = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

/** Same retry/backoff/attempt-recording shape as `deliverToAPNs` in ./apns-delivery.ts, against
 * FCM's HTTP v1 endpoint (`https://fcm.googleapis.com/v1/projects/{project}/messages:send`)
 * instead of APNs. Kept as a separate function rather than a generic "deliverToPush" — the
 * response body shape (message `name` on success vs APNs's `apns-id` header) differs enough
 * that sharing one function would need its own branching anyway. */
export async function deliverToFcm(params: {
  url: string;
  headers: Record<string, string>;
  payload: unknown;
  fetchImpl?: FetchLike;
  waitImpl?: WaitLike;
  maxAttempts?: number;
  timeoutMilliseconds?: number;
  onAttempt?: (attempt: FcmAttempt) => Promise<void>;
}): Promise<FcmDeliveryResult> {
  const fetchImpl = params.fetchImpl ?? fetch;
  const waitImpl = params.waitImpl ?? defaultWait;
  const maxAttempts = Math.max(
    1,
    Math.min(params.maxAttempts ?? MAX_APNS_ATTEMPTS, MAX_APNS_ATTEMPTS),
  );
  const attempts: FcmAttempt[] = [];
  const timeoutMilliseconds = Math.max(
    1_000,
    Math.min(params.timeoutMilliseconds ?? 15_000, 30_000),
  );

  for (let attemptNumber = 1; attemptNumber <= maxAttempts; attemptNumber++) {
    const startedAt = Date.now();
    let attempt: FcmAttempt;
    try {
      const response = await fetchImpl(params.url, {
        method: "POST",
        signal: AbortSignal.timeout(timeoutMilliseconds),
        headers: params.headers,
        body: JSON.stringify(params.payload),
      });
      const rawBody = await response.text();
      const classification = classifyFcmResponse(response.status, rawBody);
      let messageID: string | null = null;
      if (classification.outcome === "accepted") {
        try {
          messageID = (JSON.parse(rawBody) as { name?: string }).name ?? null;
        } catch {
          messageID = null;
        }
      }
      attempt = {
        ...classification,
        attemptNumber,
        httpStatus: response.status,
        messageID,
        durationMs: Math.max(0, Date.now() - startedAt),
      };
    } catch {
      attempt = {
        ...classifyFcmTransportError(),
        attemptNumber,
        httpStatus: null,
        messageID: null,
        durationMs: Math.max(0, Date.now() - startedAt),
      };
    }

    attempts.push(attempt);
    await params.onAttempt?.(attempt);

    if (!attempt.retryable || attemptNumber >= maxAttempts) {
      return { final: attempt, attempts };
    }

    await waitImpl(250 * 2 ** (attemptNumber - 1));
  }

  return { final: attempts.at(-1)!, attempts };
}
