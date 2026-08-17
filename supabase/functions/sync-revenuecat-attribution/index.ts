/**
 * Private hourly worker for Apple Ads signup attribution.
 *
 * This function is deliberately outside every user-facing path. It reads
 * profiles/subscription events, calls RevenueCat API v2 and writes only to
 * user_ad_attribution. It never creates RevenueCat customers and never sends
 * X-Platform, so customer last_seen is not changed by the sync.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  fetchRevenueCatAttributes,
  type RevenueCatFetchResult,
} from "../_shared/revenuecat-attribution-api.ts";
import {
  type AttributionValues,
  emptyAttributionValues,
  isAppleAdsAttribution,
  mergeFirstTouch,
  nextAttributionAttempt,
  parseWebhookSubscriberAttributes,
  type StoredAttributionValues,
} from "../_shared/revenuecat-attribution.ts";

type SupabaseAdminClient = ReturnType<typeof createClient<any>>;

type RequestBody = {
  limit?: unknown;
  source?: unknown;
  skip_webhook_backfill?: unknown;
};

type ProfileRow = {
  id: string;
  created_at: string;
};

type AttributionRow = {
  user_id: string;
  platform: "ios";
  provider: string | null;
  media_source: string | null;
  campaign_name: string | null;
  campaign_id: string | null;
  ad_group_name: string | null;
  ad_group_id: string | null;
  keyword_name: string | null;
  keyword_id: string | null;
  ad_id: string | null;
  org_id: string | null;
  claim_type: string | null;
  conversion_type: string | null;
  country_or_region: string | null;
  supply_placement: string | null;
  source_updated_at: string | null;
  first_fetched_at: string | null;
  attempt_count: number;
};

const PRE_COLLECTION_CUTOFF = "2026-06-22T00:00:00.000Z";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function constantTimeEquals(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  let mismatch = leftBytes.length ^ rightBytes.length;
  const maxLength = Math.max(leftBytes.length, rightBytes.length);
  for (let index = 0; index < maxLength; index += 1) {
    mismatch |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return mismatch === 0;
}

function safeLimit(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed)
    ? Math.max(1, Math.min(25, Math.trunc(parsed)))
    : 25;
}

function cleanErrorCode(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const cleaned = value.toLowerCase().replace(/[^a-z0-9_.-]/g, "_").slice(
    0,
    120,
  );
  return cleaned || fallback;
}

function storedValues(row: AttributionRow): StoredAttributionValues {
  return {
    mediaSource: row.media_source,
    campaignName: row.campaign_name,
    campaignId: row.campaign_id,
    adGroupName: row.ad_group_name,
    adGroupId: row.ad_group_id,
    keywordName: row.keyword_name,
    keywordId: row.keyword_id,
    adId: row.ad_id,
    orgId: row.org_id,
    claimType: row.claim_type,
    conversionType: row.conversion_type,
    countryOrRegion: row.country_or_region,
    supplyPlacement: row.supply_placement,
  };
}

function databaseFields(values: StoredAttributionValues) {
  return {
    media_source: values.mediaSource,
    campaign_name: values.campaignName,
    campaign_id: values.campaignId,
    ad_group_name: values.adGroupName,
    ad_group_id: values.adGroupId,
    keyword_name: values.keywordName,
    keyword_id: values.keywordId,
    ad_id: values.adId,
    org_id: values.orgId,
    claim_type: values.claimType,
    conversion_type: values.conversionType,
    country_or_region: values.countryOrRegion,
    supply_placement: values.supplyPlacement,
  };
}

async function sendAuthorizationAlert(params: {
  supportID: string;
  status: number;
}) {
  console.error(JSON.stringify({
    alarm: "revenuecat_attribution_authorization_failed",
    support_id: params.supportID,
    http_status: params.status,
  }));
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const to = Deno.env.get("ATTRIBUTION_ALERT_EMAIL") ??
    Deno.env.get("ACCOUNT_DELETION_ALERT_EMAIL") ?? "info@riskdetected.com";
  if (!apiKey || !to) return;
  const from = Deno.env.get("RESEND_FROM_EMAIL") ??
    "RiskDetected <info@riskdetected.com>";
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: "REVENUECAT_ATTRIBUTION_SYNC_ALERT",
      text:
        `support_id=${params.supportID}\nhttp_status=${params.status}\nfailure_code=revenuecat_authorization_failed`,
    }),
  }).catch(() => undefined);
}

async function seedIOSCandidates(
  supabase: SupabaseAdminClient,
  now: Date,
): Promise<number> {
  let offset = 0;
  let insertedCandidates = 0;
  const pageSize = 500;

  while (true) {
    const { data, error } = await supabase
      .from("profiles")
      .select("id,created_at")
      .eq("signup_platform", "ios")
      .order("created_at", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (error) throw new Error("candidate_profile_lookup_failed");
    const rows = (data ?? []) as ProfileRow[];
    if (rows.length === 0) break;

    const candidates = rows.map((profile) => {
      const oneHourAfterSignup = new Date(profile.created_at).getTime() +
        60 * 60 * 1000;
      const dueAt = new Date(
        Math.max(
          Number.isFinite(oneHourAfterSignup) ? oneHourAfterSignup : 0,
          now.getTime(),
        ),
      ).toISOString();
      return {
        user_id: profile.id,
        platform: "ios",
        sync_status: "pending",
        source: "revenuecat_customer_attributes_v2",
        next_attempt_at: dueAt,
      };
    });
    const { data: inserted, error: insertError } = await supabase
      .from("user_ad_attribution")
      .upsert(candidates, {
        onConflict: "user_id,platform",
        ignoreDuplicates: true,
      })
      .select("id");
    if (insertError) throw new Error("candidate_seed_failed");
    insertedCandidates += inserted?.length ?? 0;
    if (rows.length < pageSize) break;
    offset += pageSize;
  }
  return insertedCandidates;
}

async function backfillWebhookAttribution(
  supabase: SupabaseAdminClient,
  now: Date,
): Promise<number> {
  const { data, error } = await supabase
    .from("subscription_events")
    .select("user_id,raw_event,received_at")
    .eq("environment", "PRODUCTION")
    .not("user_id", "is", null)
    .order("received_at", { ascending: true })
    .limit(5000);
  if (error) throw new Error("webhook_backfill_lookup_failed");

  const byUser = new Map<string, AttributionValues>();
  for (const row of data ?? []) {
    if (typeof row.user_id !== "string") continue;
    const incoming = parseWebhookSubscriberAttributes(row.raw_event);
    if (!isAppleAdsAttribution(incoming)) continue;
    const existing = byUser.get(row.user_id) ?? emptyAttributionValues();
    const merged = mergeFirstTouch(existing, incoming);
    byUser.set(row.user_id, {
      ...merged.values,
      sourceUpdatedAt: incoming.sourceUpdatedAt ?? existing.sourceUpdatedAt,
    });
  }

  let backfilled = 0;
  for (const [userID, values] of byUser) {
    const { data: existing, error: existingError } = await supabase
      .from("user_ad_attribution")
      .select("*")
      .eq("user_id", userID)
      .eq("platform", "ios")
      .maybeSingle();
    if (existingError) throw new Error("webhook_backfill_existing_failed");
    const current = existing as AttributionRow | null;
    if (current?.provider === "apple_ads") continue;
    const merged = mergeFirstTouch(
      current ? storedValues(current) : emptyAttributionValues(),
      values,
    );
    const payload = {
      user_id: userID,
      platform: "ios",
      provider: "apple_ads",
      ...databaseFields(merged.values),
      sync_status: "attributed",
      source: "revenuecat_customer_attributes_v2",
      source_updated_at: current?.source_updated_at ?? values.sourceUpdatedAt,
      first_fetched_at: current?.first_fetched_at ?? now.toISOString(),
      last_fetched_at: now.toISOString(),
      next_attempt_at: null,
      last_http_status: 200,
      last_error_code: merged.conflict ? "attribute_conflict" : null,
    };
    const { error: upsertError } = await supabase
      .from("user_ad_attribution")
      .upsert(payload, { onConflict: "user_id,platform" });
    if (upsertError) throw new Error("webhook_backfill_write_failed");
    backfilled += 1;
  }
  return backfilled;
}

async function updateAfterAttempt(params: {
  supabase: SupabaseAdminClient;
  row: AttributionRow;
  profile: ProfileRow;
  result: RevenueCatFetchResult;
  now: Date;
}): Promise<"attributed" | "pending" | "unavailable" | "error" | "not_found"> {
  const attempts = params.row.attempt_count + 1;
  const retry = nextAttributionAttempt({
    signupCreatedAt: params.profile.created_at,
    completedAttempts: attempts,
    now: params.now,
  });
  const base = {
    attempt_count: attempts,
    first_fetched_at: params.row.attempt_count === 0
      ? params.now.toISOString()
      : undefined,
    last_fetched_at: params.now.toISOString(),
    last_http_status: params.result.status,
  };

  if (
    params.result.kind === "ok" && isAppleAdsAttribution(params.result.values)
  ) {
    const merged = mergeFirstTouch(
      storedValues(params.row),
      params.result.values,
    );
    const { error } = await params.supabase.from("user_ad_attribution").update({
      ...base,
      provider: "apple_ads",
      ...databaseFields(merged.values),
      sync_status: "attributed",
      source_updated_at: params.row.source_updated_at ??
        params.result.values.sourceUpdatedAt,
      next_attempt_at: null,
      last_error_code: merged.conflict ? "attribute_conflict" : null,
    }).eq("user_id", params.row.user_id).eq("platform", "ios");
    if (error) throw new Error("attribution_write_failed");
    return "attributed";
  }

  const isPreCollection = Date.parse(params.profile.created_at) <
    Date.parse(PRE_COLLECTION_CUTOFF);
  if (params.result.kind === "ok") {
    const terminal = retry.terminal || isPreCollection;
    const { error } = await params.supabase.from("user_ad_attribution").update({
      ...base,
      sync_status: terminal ? "unavailable" : "pending",
      next_attempt_at: terminal ? null : retry.nextAttemptAt,
      last_error_code: isPreCollection
        ? "pre_collection"
        : terminal
        ? "retry_window_exhausted"
        : "attributes_pending",
    }).eq("user_id", params.row.user_id).eq("platform", "ios");
    if (error) throw new Error("pending_write_failed");
    return terminal ? "unavailable" : "pending";
  }

  if (params.result.kind === "rate_limited") {
    const { error } = await params.supabase.from("user_ad_attribution").update({
      ...base,
      sync_status: "error",
      next_attempt_at: params.result.retryAt,
      last_error_code: "rate_limited",
    }).eq("user_id", params.row.user_id).eq("platform", "ios");
    if (error) throw new Error("rate_limit_write_failed");
    return "error";
  }

  if (params.result.kind === "not_found") {
    const terminal = retry.terminal || isPreCollection;
    const { error } = await params.supabase.from("user_ad_attribution").update({
      ...base,
      sync_status: terminal ? "unavailable" : "not_found",
      next_attempt_at: terminal ? null : retry.nextAttemptAt,
      last_error_code: isPreCollection
        ? "pre_collection"
        : terminal
        ? "retry_window_exhausted"
        : "customer_not_found",
    }).eq("user_id", params.row.user_id).eq("platform", "ios");
    if (error) throw new Error("not_found_write_failed");
    return terminal ? "unavailable" : "not_found";
  }

  if (params.result.kind === "retryable") {
    const serverBackoffHours = Math.min(24, 2 ** Math.min(attempts, 4));
    const serverBackoff = new Date(
      params.now.getTime() + serverBackoffHours * 60 * 60 * 1000,
    ).toISOString();
    const terminal = retry.terminal;
    const { error } = await params.supabase.from("user_ad_attribution").update({
      ...base,
      sync_status: terminal ? "unavailable" : "error",
      next_attempt_at: terminal ? null : serverBackoff,
      last_error_code: terminal
        ? "retry_window_exhausted"
        : cleanErrorCode(params.result.code, "revenuecat_error"),
    }).eq("user_id", params.row.user_id).eq("platform", "ios");
    if (error) throw new Error("error_state_write_failed");
    return terminal ? "unavailable" : "error";
  }

  throw new Error("authorization_result_must_abort_batch");
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("REVENUECAT_V2_READ_ONLY_API_KEY");
  const projectID = Deno.env.get("REVENUECAT_PROJECT_ID");
  const expectedSecret = Deno.env.get("ATTRIBUTION_SYNC_SECRET");
  const providedSecret = req.headers.get("x-attribution-sync-secret") ?? "";

  if (
    !supabaseURL || !serviceRoleKey || !apiKey || !projectID || !expectedSecret
  ) {
    return json(500, { error: "not_configured" });
  }
  if (!constantTimeEquals(providedSecret, expectedSecret)) {
    return json(401, { error: "unauthorized" });
  }

  let body: RequestBody = {};
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }
  const limit = safeLimit(body.limit);
  const now = new Date();
  const supportID = `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let seeded = 0;
  let webhookBackfilled = 0;
  try {
    if (body.skip_webhook_backfill !== true) {
      webhookBackfilled = await backfillWebhookAttribution(supabase, now);
    }
    seeded = await seedIOSCandidates(supabase, now);
  } catch (error) {
    console.error(JSON.stringify({
      support_id: supportID,
      failure_code: cleanErrorCode(
        error instanceof Error ? error.message : error,
        "preparation_failed",
      ),
    }));
    return json(500, { error: "preparation_failed", support_id: supportID });
  }

  const { data: dueData, error: dueError } = await supabase
    .from("user_ad_attribution")
    .select("*")
    .eq("platform", "ios")
    .in("sync_status", ["pending", "not_found", "error"])
    .lte("next_attempt_at", now.toISOString())
    .order("next_attempt_at", { ascending: true })
    .limit(limit);
  if (dueError) {
    return json(500, { error: "queue_lookup_failed", support_id: supportID });
  }
  const due = (dueData ?? []) as AttributionRow[];
  const profileIDs = due.map((row) => row.user_id);
  const profiles = new Map<string, ProfileRow>();
  if (profileIDs.length > 0) {
    const { data, error } = await supabase.from("profiles")
      .select("id,created_at").in("id", profileIDs);
    if (error) {
      return json(500, {
        error: "profile_lookup_failed",
        support_id: supportID,
      });
    }
    for (const profile of (data ?? []) as ProfileRow[]) {
      profiles.set(profile.id, profile);
    }
  }

  const counts = {
    selected: due.length,
    attributed: 0,
    pending: 0,
    unavailable: 0,
    not_found: 0,
    error: 0,
    missing_profile: 0,
  };
  let authorizationFailure: 401 | 403 | null = null;

  for (let offset = 0; offset < due.length; offset += 5) {
    if (authorizationFailure) break;
    const chunk = due.slice(offset, offset + 5);
    const results = await Promise.all(chunk.map(async (row) => {
      const profile = profiles.get(row.user_id);
      if (!profile) return { row, outcome: "missing_profile" as const };
      const result = await fetchRevenueCatAttributes({
        apiKey,
        projectID,
        customerID: row.user_id,
        now,
      });
      if (result.kind === "unauthorized") {
        return { row, outcome: "unauthorized" as const, result };
      }
      try {
        const outcome = await updateAfterAttempt({
          supabase,
          row,
          profile,
          result,
          now,
        });
        return { row, outcome };
      } catch (error) {
        console.error(JSON.stringify({
          support_id: supportID,
          failure_code: cleanErrorCode(
            error instanceof Error ? error.message : error,
            "attribution_update_failed",
          ),
        }));
        return { row, outcome: "error" as const };
      }
    }));

    for (const result of results) {
      if (result.outcome === "unauthorized") {
        authorizationFailure = result.result.status;
      } else if (result.outcome === "missing_profile") {
        counts.missing_profile += 1;
      } else {
        counts[result.outcome] += 1;
      }
    }
  }

  if (authorizationFailure) {
    await sendAuthorizationAlert({ supportID, status: authorizationFailure });
    return json(502, {
      ok: false,
      error: "revenuecat_authorization_failed",
      support_id: supportID,
      seeded,
      webhook_backfilled: webhookBackfilled,
      counts,
    });
  }

  return json(200, {
    ok: true,
    support_id: supportID,
    seeded,
    webhook_backfilled: webhookBackfilled,
    counts,
  });
});
