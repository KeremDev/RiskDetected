import {
  type APNsClassification,
  classifyAPNsResponse,
  classifyAPNsTransportError,
  MAX_APNS_ATTEMPTS,
} from "../_shared/notification-contract.ts";

export type APNsAttempt = APNsClassification & {
  attemptNumber: number;
  httpStatus: number | null;
  apnsID: string | null;
  durationMs: number;
};

export type APNsDeliveryResult = {
  final: APNsAttempt;
  attempts: APNsAttempt[];
};

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

type WaitLike = (milliseconds: number) => Promise<void>;

const defaultWait: WaitLike = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

export async function deliverToAPNs(params: {
  url: string;
  headers: Record<string, string>;
  payload: unknown;
  fetchImpl?: FetchLike;
  waitImpl?: WaitLike;
  maxAttempts?: number;
  timeoutMilliseconds?: number;
  onAttempt?: (attempt: APNsAttempt) => Promise<void>;
}): Promise<APNsDeliveryResult> {
  const fetchImpl = params.fetchImpl ?? fetch;
  const waitImpl = params.waitImpl ?? defaultWait;
  const maxAttempts = Math.max(
    1,
    Math.min(params.maxAttempts ?? MAX_APNS_ATTEMPTS, MAX_APNS_ATTEMPTS),
  );
  const attempts: APNsAttempt[] = [];
  const timeoutMilliseconds = Math.max(
    1_000,
    Math.min(params.timeoutMilliseconds ?? 15_000, 30_000),
  );

  for (let attemptNumber = 1; attemptNumber <= maxAttempts; attemptNumber++) {
    const startedAt = Date.now();
    let attempt: APNsAttempt;
    try {
      const response = await fetchImpl(params.url, {
        method: "POST",
        signal: AbortSignal.timeout(timeoutMilliseconds),
        headers: params.headers,
        body: JSON.stringify(params.payload),
      });
      const rawBody = response.ok ? "" : await response.text();
      const classification = classifyAPNsResponse(response.status, rawBody);
      attempt = {
        ...classification,
        attemptNumber,
        httpStatus: response.status,
        apnsID: response.headers.get("apns-id"),
        durationMs: Math.max(0, Date.now() - startedAt),
      };
    } catch {
      attempt = {
        ...classifyAPNsTransportError(),
        attemptNumber,
        httpStatus: null,
        apnsID: null,
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

export async function mapWithConcurrency<T, R>(
  values: readonly T[],
  concurrency: number,
  operation: (value: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(values.length);
  const workerCount = Math.max(1, Math.min(concurrency, values.length || 1));
  let nextIndex = 0;

  await Promise.all(
    Array.from({ length: workerCount }, async () => {
      while (true) {
        const index = nextIndex++;
        if (index >= values.length) return;
        results[index] = await operation(values[index]);
      }
    }),
  );

  return results;
}
