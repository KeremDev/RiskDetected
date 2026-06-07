/**
 * sync-revenuecat-subscription — authenticated fallback sync from RevenueCat
 * subscriber truth to Supabase subscription tables.
 *
 * Webhooks remain the primary path. This function covers TestFlight/device
 * cases where the SDK sees an active entitlement but the webhook has not yet
 * updated `user_subscriptions`.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  isExplicitPaidUpgradeSync,
  type PlanTier,
  tierFromProductIdentifier,
} from "../_shared/subscription-tier.ts";
import {
  isIdentifiedRevenueCatOwnerMismatch,
  normalizeRevenueCatAppUserID,
} from "../_shared/revenuecat-owner-guard.ts";

type RevenueCatEntitlement = {
  expires_date?: string | null;
  product_identifier?: string | null;
  purchase_date?: string | null;
};

type RevenueCatSubscription = {
  expires_date?: string | null;
  original_purchase_date?: string | null;
  product_identifier?: string | null;
  purchase_date?: string | null;
};

type RevenueCatSubscriberResponse = {
  subscriber?: {
    original_app_user_id?: string | null;
    entitlements?: Record<string, RevenueCatEntitlement>;
    subscriptions?: Record<string, RevenueCatSubscription>;
  };
};

type SyncRequestBody = {
  expected_tier?: string | null;
  expected_entitlement_id?: string | null;
};

const PUBLIC_REVENUECAT_API_KEY = "appl_mckFFxUrvtNqzjShezjMIrFmItA";
const ACTIVE_BACKEND_STATUSES = new Set(["active", "trialing", "grace_period"]);

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function isActiveEntitlement(
  entitlement: RevenueCatEntitlement | undefined,
): boolean {
  if (!entitlement) return false;
  if (!entitlement.expires_date) return true;
  const expiresAt = Date.parse(entitlement.expires_date);
  return Number.isFinite(expiresAt) && expiresAt > Date.now();
}

function entitlementTier(entitlements: Record<string, RevenueCatEntitlement>): {
  tier: PlanTier;
  entitlementID: string | null;
  productID: string | null;
  expiration: string | null;
  purchaseDate: string | null;
  originalPurchaseDate: string | null;
} {
  const activeEntitlements = Object.entries(entitlements)
    .filter(([, value]) => isActiveEntitlement(value));
  const productResolved = activeEntitlements
    .map(([entitlementID, value]) => ({
      tier: tierFromProductIdentifier(value.product_identifier ?? ""),
      entitlementID,
      productID: value.product_identifier ?? null,
      expiration: value.expires_date ?? null,
      purchaseDate: value.purchase_date ?? null,
    }))
    .find((item) => item.tier);
  if (productResolved?.tier) {
    return {
      tier: productResolved.tier,
      entitlementID: productResolved.tier,
      productID: productResolved.productID,
      expiration: productResolved.expiration,
      purchaseDate: productResolved.purchaseDate,
      originalPurchaseDate: productResolved.purchaseDate,
    };
  }

  const pro = entitlements.pro;
  if (isActiveEntitlement(pro)) {
    return {
      tier: "pro",
      entitlementID: "pro",
      productID: pro?.product_identifier ?? null,
      expiration: pro?.expires_date ?? null,
      purchaseDate: pro?.purchase_date ?? null,
      originalPurchaseDate: pro?.purchase_date ?? null,
    };
  }

  const plus = entitlements.plus;
  if (isActiveEntitlement(plus)) {
    return {
      tier: "plus",
      entitlementID: "plus",
      productID: plus?.product_identifier ?? null,
      expiration: plus?.expires_date ?? null,
      purchaseDate: plus?.purchase_date ?? null,
      originalPurchaseDate: plus?.purchase_date ?? null,
    };
  }

  return {
    tier: "free",
    entitlementID: null,
    productID: null,
    expiration: null,
    purchaseDate: null,
    originalPurchaseDate: null,
  };
}

function subscriptionTier(
  subscriptions: Record<string, RevenueCatSubscription>,
): {
  tier: PlanTier;
  entitlementID: string | null;
  productID: string | null;
  expiration: string | null;
  purchaseDate: string | null;
  originalPurchaseDate: string | null;
} | null {
  const active = Object.entries(subscriptions)
    .map(([productID, value]) => ({
      productID,
      tier: tierFromProductIdentifier(productID),
      expiration: value.expires_date ?? null,
      purchaseDate: value.purchase_date ?? null,
      originalPurchaseDate: value.original_purchase_date ??
        value.purchase_date ??
        null,
      purchaseTime: Date.parse(value.purchase_date ?? ""),
    }))
    .filter((item) =>
      item.tier && isActiveEntitlement({ expires_date: item.expiration })
    )
    .sort((a, b) => {
      const aTime = Number.isFinite(a.purchaseTime) ? a.purchaseTime : 0;
      const bTime = Number.isFinite(b.purchaseTime) ? b.purchaseTime : 0;
      if (aTime === bTime) {
        return (b.tier === "pro" ? 1 : 0) - (a.tier === "pro" ? 1 : 0);
      }
      return bTime - aTime;
    });

  const current = active[0];
  if (!current?.tier) return null;

  return {
    tier: current.tier,
    entitlementID: current.tier,
    productID: current.productID,
    expiration: current.expiration,
    purchaseDate: current.purchaseDate,
    originalPurchaseDate: current.originalPurchaseDate,
  };
}

function normalizeTier(value: unknown): PlanTier | null {
  return value === "free" || value === "plus" || value === "pro" ? value : null;
}

function isFutureExpiration(value: unknown): boolean {
  if (typeof value !== "string" || !value.trim()) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && parsed > Date.now();
}

function isActivePaidBackendSubscription(
  subscription: {
    tier?: string | null;
    status?: string | null;
    current_period_ends_at?: string | null;
  } | null,
): boolean {
  const tier = normalizeTier(subscription?.tier);
  if (tier !== "plus" && tier !== "pro") return false;
  if (!ACTIVE_BACKEND_STATUSES.has(String(subscription?.status ?? ""))) {
    return false;
  }
  return isFutureExpiration(subscription?.current_period_ends_at);
}

function purchasePredatesAccount(
  purchaseDate: string | null,
  accountCreatedAt: string | null | undefined,
): boolean {
  if (!purchaseDate || !accountCreatedAt) return false;
  const purchaseTime = Date.parse(purchaseDate);
  const accountTime = Date.parse(accountCreatedAt);
  if (!Number.isFinite(purchaseTime) || !Number.isFinite(accountTime)) {
    return false;
  }
  return purchaseTime < accountTime - 10 * 60 * 1000;
}

async function activeOwnerForResolvedSubscription(
  supabase: ReturnType<typeof createClient<any>>,
  currentUserID: string,
  resolved: {
    productID: string | null;
    expiration: string | null;
  },
): Promise<string | null> {
  if (!resolved.productID || !resolved.expiration) return null;

  const { data } = await supabase
    .from("user_subscriptions")
    .select("user_id,tier,status,current_period_ends_at")
    .eq("product_id", resolved.productID)
    .neq("user_id", currentUserID)
    .in("tier", ["plus", "pro"])
    .in("status", ["active", "trialing", "grace_period"])
    .limit(10);

  const resolvedExpiration = Date.parse(resolved.expiration);
  if (!Number.isFinite(resolvedExpiration)) return null;

  for (const row of data ?? []) {
    if (!isFutureExpiration(row.current_period_ends_at)) continue;
    const rowExpiration = Date.parse(String(row.current_period_ends_at ?? ""));
    if (
      Number.isFinite(rowExpiration) &&
      Math.abs(rowExpiration - resolvedExpiration) <= 60_000
    ) {
      return String(row.user_id);
    }
  }

  return null;
}

async function writeFreeSubscriptionState(
  supabase: ReturnType<typeof createClient<any>>,
  userID: string,
  source: string,
) {
  await supabase.from("user_subscriptions").upsert({
    user_id: userID,
    tier: "free",
    source,
    status: "inactive",
    revenuecat_app_user_id: userID,
    product_id: null,
    entitlement_id: null,
    entitlement_ids: [],
    current_period_ends_at: null,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });

  await supabase
    .from("profiles")
    .update({ tier: "free" })
    .eq("id", userID);
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const revenueCatAPIKey = Deno.env.get("REVENUECAT_REST_API_KEY") ??
    Deno.env.get("REVENUECAT_PUBLIC_API_KEY") ??
    PUBLIC_REVENUECAT_API_KEY;

  if (!supabaseUrl || !serviceRoleKey || !revenueCatAPIKey) {
    return json(500, { error: "sync_not_configured" });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json(401, { error: "auth_required" });
  }

  const body = await req.json().catch(() => ({})) as SyncRequestBody;
  const expectedTier = normalizeTier(body.expected_tier);
  const expectedEntitlementID = typeof body.expected_entitlement_id === "string"
    ? body.expected_entitlement_id.trim().toLowerCase()
    : null;

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authErr } = await supabase.auth.getUser(token);
  if (authErr || !user) {
    return json(401, { error: "auth_invalid" });
  }

  const revenueCatResponse = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(user.id)}`,
    {
      headers: {
        Authorization: `Bearer ${revenueCatAPIKey}`,
        Accept: "application/json",
      },
    },
  );

  if (!revenueCatResponse.ok) {
    return json(502, {
      error: "revenuecat_lookup_failed",
      status: revenueCatResponse.status,
    });
  }

  const payload = await revenueCatResponse
    .json() as RevenueCatSubscriberResponse;
  const originalAppUserID = normalizeRevenueCatAppUserID(
    payload.subscriber?.original_app_user_id,
  );

  const entitlements = payload.subscriber?.entitlements ?? {};
  const subscriptions = payload.subscriber?.subscriptions ?? {};
  const resolved = subscriptionTier(subscriptions) ??
    entitlementTier(entitlements);

  const { data: previousSubscription } = await supabase
    .from("user_subscriptions")
    .select("tier,status,current_period_ends_at,entitlement_id,product_id")
    .eq("user_id", user.id)
    .maybeSingle();
  const previousTier = normalizeTier(previousSubscription?.tier);
  const previousStatus = typeof previousSubscription?.status === "string"
    ? previousSubscription.status
    : null;

  if (
    resolved.tier !== "free" &&
    isIdentifiedRevenueCatOwnerMismatch(originalAppUserID, user.id)
  ) {
    await writeFreeSubscriptionState(
      supabase,
      user.id,
      "revenuecat_sync_conflict",
    );

    return json(409, {
      error: "revenuecat_owner_mismatch",
      tier: expectedTier ?? "free",
      resolved_tier: resolved.tier,
      original_app_user_id: originalAppUserID,
      product_id: resolved.productID,
      entitlement_id: resolved.entitlementID,
    });
  }

  if (
    resolved.tier !== "free" &&
    purchasePredatesAccount(
      resolved.originalPurchaseDate ?? resolved.purchaseDate,
      user.created_at,
    )
  ) {
    await writeFreeSubscriptionState(
      supabase,
      user.id,
      "revenuecat_sync_conflict",
    );

    return json(409, {
      error: "revenuecat_purchase_predates_account",
      tier: "free",
      resolved_tier: resolved.tier,
      product_id: resolved.productID,
      entitlement_id: resolved.entitlementID,
      purchase_date: resolved.purchaseDate,
      original_purchase_date: resolved.originalPurchaseDate,
      account_created_at: user.created_at,
    });
  }

  if (resolved.tier !== "free") {
    const existingOwnerID = await activeOwnerForResolvedSubscription(
      supabase,
      user.id,
      resolved,
    );
    if (existingOwnerID) {
      await writeFreeSubscriptionState(
        supabase,
        user.id,
        "revenuecat_sync_conflict",
      );

      return json(409, {
        error: "revenuecat_owner_mismatch",
        tier: "free",
        resolved_tier: resolved.tier,
        subscription_owner_user_id: existingOwnerID,
        product_id: resolved.productID,
        entitlement_id: resolved.entitlementID,
      });
    }
  }

  if (
    resolved.tier === "pro" && previousTier === "plus" &&
    isActivePaidBackendSubscription(previousSubscription) &&
    !isExplicitPaidUpgradeSync(previousTier, resolved.tier, expectedTier)
  ) {
    // Authenticated sync is a fallback repair path. Do not silently upgrade a
    // Plus backend subscription to Pro from a RevenueCat subscriber snapshot;
    // plan upgrades must arrive through the RevenueCat webhook product-change
    // event or an explicit Pro purchase flow.
    return json(200, {
      ok: true,
      tier: "plus",
      status: previousStatus ?? "active",
      entitlement_id: previousSubscription?.entitlement_id ?? "plus",
      product_id: previousSubscription?.product_id ?? null,
      current_period_ends_at: previousSubscription?.current_period_ends_at ??
        null,
      revenuecat_tier: resolved.tier,
      skipped_upgrade: true,
    });
  }

  if (resolved.tier === "free") {
    await writeFreeSubscriptionState(supabase, user.id, "revenuecat_sync");

    return json(200, {
      ok: true,
      tier: "free",
      status: "inactive",
      entitlement_id: null,
      product_id: null,
      current_period_ends_at: null,
      revenuecat_tier: resolved.tier,
      healed_stale_subscription: previousTier === "plus" ||
        previousTier === "pro",
    });
  }

  if (!expectedTier) {
    return json(409, {
      error: "client_tier_assertion_required",
      tier: "free",
      resolved_tier: resolved.tier,
    });
  }

  if (expectedTier && expectedTier !== resolved.tier) {
    return json(409, {
      error: "revenuecat_tier_mismatch",
      tier: expectedTier,
      resolved_tier: resolved.tier,
    });
  }

  if (
    expectedTier &&
    expectedEntitlementID && expectedEntitlementID !== resolved.entitlementID
  ) {
    return json(409, {
      error: "revenuecat_entitlement_mismatch",
      tier: expectedTier,
      resolved_tier: resolved.tier,
      resolved_entitlement_id: resolved.entitlementID,
    });
  }

  const entitlementIDs = Object.entries(entitlements)
    .filter(([, value]) => isActiveEntitlement(value))
    .map(([key]) => key);
  const status = "active";

  await supabase.from("user_subscriptions").upsert({
    user_id: user.id,
    tier: resolved.tier,
    source: "revenuecat_sync",
    status,
    revenuecat_app_user_id: user.id,
    product_id: resolved.productID,
    entitlement_id: resolved.entitlementID,
    entitlement_ids: entitlementIDs,
    current_period_ends_at: resolved.expiration,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });

  await supabase
    .from("profiles")
    .update({ tier: resolved.tier })
    .eq("id", user.id);

  return json(200, {
    ok: true,
    tier: resolved.tier,
    status,
    entitlement_id: resolved.entitlementID,
    product_id: resolved.productID,
    current_period_ends_at: resolved.expiration,
  });
});
