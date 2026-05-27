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

type PlanTier = "free" | "plus" | "pro";

type RevenueCatEntitlement = {
  expires_date?: string | null;
  product_identifier?: string | null;
};

type RevenueCatSubscription = {
  expires_date?: string | null;
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
} {
  const pro = entitlements.pro;
  if (isActiveEntitlement(pro)) {
    return {
      tier: "pro",
      entitlementID: "pro",
      productID: pro?.product_identifier ?? null,
      expiration: pro?.expires_date ?? null,
    };
  }

  const plus = entitlements.plus;
  if (isActiveEntitlement(plus)) {
    return {
      tier: "plus",
      entitlementID: "plus",
      productID: plus?.product_identifier ?? null,
      expiration: plus?.expires_date ?? null,
    };
  }

  return {
    tier: "free",
    entitlementID: null,
    productID: null,
    expiration: null,
  };
}

function tierFromProductIdentifier(productID: string): PlanTier | null {
  const product = productID.toLowerCase();
  if (product.includes("plus")) return "plus";
  if (product.includes("pro")) return "pro";
  return null;
}

function subscriptionTier(
  subscriptions: Record<string, RevenueCatSubscription>,
): {
  tier: PlanTier;
  entitlementID: string | null;
  productID: string | null;
  expiration: string | null;
} | null {
  const active = Object.entries(subscriptions)
    .map(([productID, value]) => ({
      productID,
      tier: tierFromProductIdentifier(productID),
      expiration: value.expires_date ?? null,
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
  };
}

function normalizeTier(value: unknown): PlanTier | null {
  return value === "free" || value === "plus" || value === "pro" ? value : null;
}

function safeLogText(value: unknown, maxLength = 180): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .slice(0, maxLength);
}

async function sendAccountSyncPush(params: {
  supabaseUrl: string;
  serviceRoleKey: string;
  userID: string;
  tier: PlanTier;
  status: string;
}) {
  if (params.tier === "free") return;
  const planName = params.tier === "pro" ? "Pro" : "Plus";
  const response = await fetch(
    `${params.supabaseUrl}/functions/v1/send-push-notification`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${params.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: params.userID,
        kind: "account_updates",
        title: `${planName} plan aktif`,
        body: `RiskDetected ${planName} üyeliğin hesabına tanımlandı.`,
        data: {
          destination: "profile",
          source: "revenuecat_sync",
          tier: params.tier,
          status: params.status,
        },
      }),
    },
  );

  if (!response.ok) {
    console.warn(
      "Account sync push failed",
      JSON.stringify({
        user_id: params.userID,
        tier: params.tier,
        status: response.status,
        body: safeLogText(await response.text()),
      }),
    );
  }
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
  const originalAppUserID =
    typeof payload.subscriber?.original_app_user_id === "string"
      ? payload.subscriber.original_app_user_id.trim().toLowerCase()
      : null;
  if (
    originalAppUserID &&
    originalAppUserID !== user.id.toLowerCase() &&
    !originalAppUserID.startsWith("$rcanonymousid:")
  ) {
    return json(409, {
      error: "revenuecat_owner_mismatch",
      tier: expectedTier ?? "free",
      original_app_user_id: originalAppUserID,
    });
  }

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

  if (resolved.tier === "free") {
    // Webhooks are the source of truth for cancellations/downgrades. This
    // authenticated fallback exists to repair missing paid access when the SDK
    // sees an active entitlement; it must not downgrade an existing backend
    // subscription just because RevenueCat briefly returns no active entitlement.
    return json(200, {
      ok: true,
      tier: previousTier ?? "free",
      status: previousStatus ?? "inactive",
      entitlement_id: previousSubscription?.entitlement_id ?? null,
      product_id: previousSubscription?.product_id ?? null,
      current_period_ends_at:
        previousSubscription?.current_period_ends_at ?? null,
      revenuecat_tier: resolved.tier,
      skipped_downgrade: true,
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

  if (previousTier !== resolved.tier || previousStatus !== status) {
    await sendAccountSyncPush({
      supabaseUrl,
      serviceRoleKey,
      userID: user.id,
      tier: resolved.tier,
      status,
    });
  }

  return json(200, {
    ok: true,
    tier: resolved.tier,
    status,
    entitlement_id: resolved.entitlementID,
    product_id: resolved.productID,
    current_period_ends_at: resolved.expiration,
  });
});
