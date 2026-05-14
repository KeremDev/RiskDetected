/**
 * revenuecat-webhook — sync RevenueCat subscription truth to Supabase.
 *
 * Configure RevenueCat webhook Authorization header to match
 * REVENUECAT_WEBHOOK_AUTHORIZATION. App User IDs are Supabase user UUIDs
 * because the iOS SDK logs in with auth.user.id.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type PlanTier = "free" | "plus" | "pro";

const ACTIVE_STATUSES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
  "NON_RENEWING_PURCHASE",
]);

const PASSIVE_STATUSES = new Set([
  "BILLING_ISSUE",
  "SUBSCRIPTION_PAUSED",
]);

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function normalizeEntitlements(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => String(item).trim().toLowerCase())
    .filter(Boolean);
}

function tierFrom(entitlementIDs: string[], productID: string | null): PlanTier {
  const product = productID?.toLowerCase() ?? "";
  if (entitlementIDs.includes("pro") || product.includes("pro")) return "pro";
  if (entitlementIDs.includes("plus") || product.includes("plus")) return "plus";
  return "free";
}

function uuidFrom(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const clean = value.trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(clean)
    ? clean
    : null;
}

function resolveUserID(event: Record<string, unknown>): string | null {
  const candidates: unknown[] = [
    event.app_user_id,
    event.original_app_user_id,
    event.transferred_to,
  ];
  if (Array.isArray(event.aliases)) candidates.push(...event.aliases);
  for (const candidate of candidates) {
    const id = uuidFrom(candidate);
    if (id) return id;
  }
  return null;
}

function parseExpiration(value: unknown): string | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    const ms = value > 10_000_000_000 ? value : value * 1000;
    return new Date(ms).toISOString();
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) return new Date(parsed).toISOString();
  }
  return null;
}

function isFutureExpiration(value: string | null): boolean {
  if (!value) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && parsed > Date.now();
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const expectedAuthorization = Deno.env.get("REVENUECAT_WEBHOOK_AUTHORIZATION");

  if (!supabaseUrl || !serviceRoleKey || !expectedAuthorization) {
    return json(500, { error: "RevenueCat webhook is not configured" });
  }

  if (req.headers.get("Authorization") !== expectedAuthorization) {
    return json(401, { error: "Unauthorized" });
  }

  const body = await req.json().catch(() => null);
  const event = (body?.event ?? body) as Record<string, unknown> | null;
  if (!event || typeof event !== "object") {
    return json(400, { error: "Invalid RevenueCat event" });
  }

  const eventID = String(event.id ?? event.event_id ?? crypto.randomUUID());
  const eventType = String(event.type ?? "UNKNOWN");
  const productID = typeof event.product_id === "string" ? event.product_id : null;
  const entitlementIDs = normalizeEntitlements(event.entitlement_ids);
  const appUserID = typeof event.app_user_id === "string" ? event.app_user_id : null;
  const userID = resolveUserID(event);
  const environment = typeof event.environment === "string" ? event.environment : null;

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: existing } = await supabase
    .from("subscription_events")
    .select("event_id")
    .eq("event_id", eventID)
    .maybeSingle();

  if (existing) {
    return json(200, { ok: true, duplicate: true });
  }

  await supabase.from("subscription_events").insert({
    event_id: eventID,
    user_id: userID,
    app_user_id: appUserID,
    event_type: eventType,
    product_id: productID,
    entitlement_ids: entitlementIDs,
    environment,
    raw_event: event,
  });

  if (!userID || eventType === "TEST") {
    return json(200, { ok: true, ignored: true });
  }

  const entitlementTier = tierFrom(entitlementIDs, productID);
  const expiration = parseExpiration(event.expiration_at_ms ?? event.expiration_at);
  let nextTier: PlanTier | null = null;
  let nextStatus = "inactive";

  if (eventType === "EXPIRATION") {
    nextTier = "free";
    nextStatus = "expired";
  } else if (eventType === "CANCELLATION") {
    nextTier = entitlementTier !== "free" && isFutureExpiration(expiration)
      ? entitlementTier
      : null;
    nextStatus = nextTier ? "active" : "cancellation";
  } else if (ACTIVE_STATUSES.has(eventType)) {
    nextTier = entitlementTier;
    nextStatus = entitlementTier === "free" ? "inactive" : "active";
  } else if (PASSIVE_STATUSES.has(eventType)) {
    nextTier = null;
    nextStatus = eventType.toLowerCase();
  }

  if (nextTier) {
    await supabase.from("user_subscriptions").upsert({
      user_id: userID,
      tier: nextTier,
      source: "revenuecat",
      status: nextStatus,
      revenuecat_app_user_id: appUserID,
      product_id: productID,
      entitlement_id: entitlementTier === "free" ? null : entitlementTier,
      entitlement_ids: entitlementIDs,
      environment,
      current_period_ends_at: expiration,
      last_event_id: eventID,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });

    await supabase
      .from("profiles")
      .update({ tier: nextTier })
      .eq("id", userID);
  } else {
    await supabase
      .from("user_subscriptions")
      .update({
        status: nextStatus,
        current_period_ends_at: expiration,
        last_event_id: eventID,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", userID);

    if (eventType === "BILLING_ISSUE" || eventType === "SUBSCRIPTION_PAUSED") {
      await supabase
        .from("profiles")
        .update({ tier: "free" })
        .eq("id", userID);
    }
  }

  await supabase
    .from("subscription_events")
    .update({ processed_at: new Date().toISOString() })
    .eq("event_id", eventID);

  return json(200, { ok: true });
});
