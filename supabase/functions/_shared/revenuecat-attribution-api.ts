import {
  type AttributionValues,
  parseRevenueCatAttributeItems,
  type RevenueCatAttributeItem,
} from "./revenuecat-attribution.ts";

export type RevenueCatFetchResult =
  | { kind: "ok"; status: 200; values: AttributionValues }
  | { kind: "not_found"; status: 404 }
  | { kind: "rate_limited"; status: 429; retryAt: string }
  | { kind: "unauthorized"; status: 401 | 403 }
  | { kind: "retryable"; status: number; code: string };

const MAX_API_PAGES = 5;

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function retryAfterDate(header: string | null, now: Date): string {
  const seconds = Number(header);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return new Date(now.getTime() + Math.max(60, seconds) * 1000)
      .toISOString();
  }
  if (header) {
    const parsed = new Date(header);
    if (!Number.isNaN(parsed.getTime()) && parsed > now) {
      return parsed.toISOString();
    }
  }
  return new Date(now.getTime() + 60 * 60 * 1000).toISOString();
}

function safeNextPage(
  value: unknown,
  params: { projectID: string; customerID: string },
): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const url = new URL(value, "https://api.revenuecat.com");
    const expectedPath = `/v2/projects/${
      encodeURIComponent(params.projectID)
    }/customers/${encodeURIComponent(params.customerID)}/attributes`;
    if (url.origin !== "https://api.revenuecat.com") return null;
    if (url.pathname !== expectedPath) return null;
    return url.toString();
  } catch {
    return null;
  }
}

/** Read-only RevenueCat API v2 fetch with bounded, origin-checked pagination. */
export async function fetchRevenueCatAttributes(params: {
  apiKey: string;
  projectID: string;
  customerID: string;
  now: Date;
  fetchImpl?: typeof fetch;
}): Promise<RevenueCatFetchResult> {
  const fetchImpl = params.fetchImpl ?? fetch;
  let url = `https://api.revenuecat.com/v2/projects/${
    encodeURIComponent(params.projectID)
  }/customers/${encodeURIComponent(params.customerID)}/attributes?limit=100`;
  const items: RevenueCatAttributeItem[] = [];

  for (let page = 0; page < MAX_API_PAGES; page += 1) {
    let response: Response;
    try {
      response = await fetchImpl(url, {
        method: "GET",
        headers: {
          "Authorization": `Bearer ${params.apiKey}`,
          "Accept": "application/json",
        },
      });
    } catch {
      return { kind: "retryable", status: 503, code: "network_error" };
    }

    if (response.status === 401 || response.status === 403) {
      return { kind: "unauthorized", status: response.status };
    }
    if (response.status === 404) return { kind: "not_found", status: 404 };
    if (response.status === 429) {
      return {
        kind: "rate_limited",
        status: 429,
        retryAt: retryAfterDate(
          response.headers.get("Retry-After"),
          params.now,
        ),
      };
    }
    if (response.status >= 500 || response.status === 423) {
      return {
        kind: "retryable",
        status: response.status,
        code: response.status === 423
          ? "customer_locked"
          : "revenuecat_server_error",
      };
    }
    if (!response.ok) {
      return {
        kind: "retryable",
        status: response.status,
        code: "revenuecat_unexpected_status",
      };
    }

    const payload = await response.json().catch(() => null);
    const record = asRecord(payload);
    if (!record || !Array.isArray(record.items)) {
      return { kind: "retryable", status: 502, code: "invalid_response" };
    }
    items.push(...(record.items as RevenueCatAttributeItem[]));
    const next = safeNextPage(record.next_page, params);
    if (!next) break;
    url = next;
  }

  return {
    kind: "ok",
    status: 200,
    values: parseRevenueCatAttributeItems(items),
  };
}
