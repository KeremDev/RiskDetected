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

type RevenueCatSubscriberResponse = {
  subscriber?: {
    entitlements?: Record<string, RevenueCatEntitlement>;
  };
};

const PUBLIC_REVENUECAT_API_KEY = "appl_mckFFxUrvtNqzjShezjMIrFmItA";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function isActiveEntitlement(entitlement: RevenueCatEntitlement | undefined): boolean {
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

  const payload = await revenueCatResponse.json() as RevenueCatSubscriberResponse;
  const entitlements = payload.subscriber?.entitlements ?? {};
  const resolved = entitlementTier(entitlements);
  const entitlementIDs = Object.entries(entitlements)
    .filter(([, value]) => isActiveEntitlement(value))
    .map(([key]) => key);
  const status = resolved.tier === "free" ? "inactive" : "active";

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
