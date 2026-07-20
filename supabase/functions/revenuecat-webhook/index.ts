/**
 * revenuecat-webhook — sync RevenueCat subscription truth to Supabase.
 *
 * Configure RevenueCat webhook Authorization header to match
 * REVENUECAT_WEBHOOK_AUTHORIZATION. App User IDs are Supabase user UUIDs
 * because the iOS SDK logs in with auth.user.id.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  type PlanTier,
  tierFromProductIdentifier,
} from "../_shared/subscription-tier.ts";
import {
  resolveRevenueCatEventUserID,
  revenueCatTransferIDs,
} from "../_shared/revenuecat-event.ts";
import {
  clearTrialReminderMetadataPatch,
  mergeTrialMetadataPatches,
  revenueCatSubscriptionRenewalIntent,
  type TrialMetadataPatch,
  trialMetadataPatchForRevenueCatEvent,
  verifiedTrialMetadataPatch,
} from "../_shared/trial-reminder.ts";

type SupabaseAdminClient = ReturnType<typeof createClient<any>>;

const ACTIVE_STATUSES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "REFUND_REVERSED",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
  "NON_RENEWING_PURCHASE",
]);

const PASSIVE_STATUSES = new Set([
  "BILLING_ISSUE",
  "SUBSCRIPTION_PAUSED",
]);

const PUBLIC_REVENUECAT_API_KEY = "appl_mckFFxUrvtNqzjShezjMIrFmItA";

type RevenueCatEntitlement = {
  expires_date?: string | null;
  product_identifier?: string | null;
  purchase_date?: string | null;
};

type RevenueCatSubscription = {
  expires_date?: string | null;
  original_purchase_date?: string | null;
  period_type?: string | null;
  product_identifier?: string | null;
  purchase_date?: string | null;
  unsubscribe_detected_at?: string | null;
};

type RevenueCatSubscriberResponse = {
  subscriber?: {
    entitlements?: Record<string, RevenueCatEntitlement>;
    subscriptions?: Record<string, RevenueCatSubscription>;
  };
};

type ResolvedSubscriberState = {
  tier: PlanTier;
  status: "active" | "inactive";
  entitlementID: string | null;
  entitlementIDs: string[];
  productID: string | null;
  expiration: string | null;
  purchaseDate: string | null;
  originalPurchaseDate: string | null;
  periodType: string | null;
  renewalIntent: boolean | null;
};

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

function isFutureExpiration(value: string | null): boolean {
  if (!value) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && parsed > Date.now();
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
  periodType: string | null;
  renewalIntent: boolean | null;
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
      periodType: null,
      renewalIntent: null,
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
      periodType: null,
      renewalIntent: null,
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
      periodType: null,
      renewalIntent: null,
    };
  }

  return {
    tier: "free",
    entitlementID: null,
    productID: null,
    expiration: null,
    purchaseDate: null,
    originalPurchaseDate: null,
    periodType: null,
    renewalIntent: null,
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
  periodType: string | null;
  renewalIntent: boolean | null;
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
      periodType: value.period_type ?? null,
      renewalIntent: revenueCatSubscriptionRenewalIntent(
        value as unknown as Record<string, unknown>,
      ),
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
    periodType: current.periodType,
    renewalIntent: current.renewalIntent,
  };
}

function resolvedStateFromSubscriber(
  payload: RevenueCatSubscriberResponse,
): ResolvedSubscriberState {
  const entitlements = payload.subscriber?.entitlements ?? {};
  const subscriptions = payload.subscriber?.subscriptions ?? {};
  const resolved = subscriptionTier(subscriptions) ??
    entitlementTier(entitlements);
  const entitlementIDs = Object.entries(entitlements)
    .filter(([, value]) => isActiveEntitlement(value))
    .map(([key]) => key);

  return {
    tier: resolved.tier,
    status: resolved.tier === "free" ? "inactive" : "active",
    entitlementID: resolved.entitlementID,
    entitlementIDs,
    productID: resolved.productID,
    expiration: resolved.expiration,
    purchaseDate: resolved.purchaseDate,
    originalPurchaseDate: resolved.originalPurchaseDate,
    periodType: resolved.periodType,
    renewalIntent: resolved.renewalIntent,
  };
}

function freeSubscriberState(): ResolvedSubscriberState {
  return {
    tier: "free",
    status: "inactive",
    entitlementID: null,
    entitlementIDs: [],
    productID: null,
    expiration: null,
    purchaseDate: null,
    originalPurchaseDate: null,
    periodType: null,
    renewalIntent: null,
  };
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

async function fetchRevenueCatSubscriberState(
  appUserID: string,
  apiKey: string,
): Promise<ResolvedSubscriberState> {
  const response = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${
      encodeURIComponent(appUserID)
    }`,
    {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "application/json",
      },
    },
  );
  if (!response.ok) {
    throw new Error(`revenuecat_lookup_failed:${response.status}`);
  }

  return resolvedStateFromSubscriber(
    await response.json() as RevenueCatSubscriberResponse,
  );
}

function safeLogText(value: unknown, maxLength = 180): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .slice(0, maxLength);
}

function accountPushCopy(eventType: string, tier: PlanTier | null): {
  title: string;
  body: string;
} | null {
  if (eventType === "INITIAL_PURCHASE" || eventType === "PRODUCT_CHANGE") {
    return null;
  }
  if (eventType === "RENEWAL" || eventType === "UNCANCELLATION") return null;
  if (eventType === "CANCELLATION") {
    return {
      title: "Üyelik iptali alındı",
      body: "Planın dönem sonuna kadar aktif kalmaya devam edecek.",
    };
  }
  if (eventType === "EXPIRATION") {
    return {
      title: "Üyelik süren doldu",
      body: "RiskDetected hesabın ücretsiz plana geçirildi.",
    };
  }
  if (eventType === "BILLING_ISSUE") {
    return {
      title: "Ödeme kontrolü gerekiyor",
      body:
        "Üyeliğinin devam etmesi için App Store ödeme bilgilerini kontrol et.",
    };
  }
  if (eventType === "SUBSCRIPTION_PAUSED") {
    return {
      title: "Üyelik duraklatıldı",
      body: "RiskDetected hesabın geçici olarak ücretsiz plana alındı.",
    };
  }
  return null;
}

async function sendAccountUpdatePush(params: {
  supabaseUrl: string;
  serviceRoleKey: string;
  userID: string;
  eventID: string;
  eventType: string;
  tier: PlanTier | null;
}) {
  const copy = accountPushCopy(params.eventType, params.tier);
  if (!copy) return;

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
        title: copy.title,
        body: copy.body,
        data: {
          destination: "profile",
          event_id: params.eventID,
          event_type: params.eventType,
          tier: params.tier,
        },
      }),
    },
  );

  if (!response.ok) {
    console.warn(
      "Account update push failed",
      JSON.stringify({
        event_id: params.eventID,
        event_type: params.eventType,
        status: response.status,
        body: safeLogText(await response.text()),
      }),
    );
  }
}

async function existingProfileID(
  supabase: SupabaseAdminClient,
  candidates: string[],
): Promise<string | null> {
  for (const candidate of candidates) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("id")
      .eq("id", candidate)
      .maybeSingle();
    if (profile?.id) return candidate;
  }
  return null;
}

async function existingSubscriptionRow(
  supabase: SupabaseAdminClient,
  userID: string,
) {
  const { data } = await supabase
    .from("user_subscriptions")
    .select(
      "trial_started_at,trial_ends_at,trial_product_id,will_renew,trial_reminder_sent_at,trial_reminder_last_attempt_at,trial_reminder_status,trial_reminder_notification_event_id",
    )
    .eq("user_id", userID)
    .maybeSingle();
  return data;
}

async function writeSubscriptionState(params: {
  supabase: SupabaseAdminClient;
  userID: string;
  revenueCatAppUserID: string | null;
  source: string;
  eventID: string;
  environment: string | null;
  state: ResolvedSubscriberState;
  trialPatch?: TrialMetadataPatch | null;
}) {
  const payload: Record<string, unknown> = {
    user_id: params.userID,
    tier: params.state.tier,
    source: params.source,
    status: params.state.status,
    revenuecat_app_user_id: params.revenueCatAppUserID,
    product_id: params.state.productID,
    entitlement_id: params.state.entitlementID,
    entitlement_ids: params.state.entitlementIDs,
    environment: params.environment,
    current_period_ends_at: params.state.expiration,
    last_event_id: params.eventID,
    updated_at: new Date().toISOString(),
  };
  if (params.trialPatch) Object.assign(payload, params.trialPatch);

  await params.supabase.from("user_subscriptions").upsert(payload, {
    onConflict: "user_id",
  });

  await params.supabase
    .from("profiles")
    .update({ tier: params.state.tier })
    .eq("id", params.userID);
}

async function deactivateTransferredFromUser(params: {
  supabase: SupabaseAdminClient;
  userID: string;
  eventID: string;
  environment: string | null;
}) {
  const { data: profile } = await params.supabase
    .from("profiles")
    .select("id")
    .eq("id", params.userID)
    .maybeSingle();
  if (!profile) return false;

  await params.supabase.from("user_subscriptions").upsert({
    user_id: params.userID,
    tier: "free",
    source: "revenuecat_transfer",
    status: "inactive",
    revenuecat_app_user_id: params.userID,
    product_id: null,
    entitlement_id: null,
    entitlement_ids: [],
    environment: params.environment,
    current_period_ends_at: null,
    last_event_id: params.eventID,
    ...clearTrialReminderMetadataPatch(),
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });

  await params.supabase
    .from("profiles")
    .update({ tier: "free" })
    .eq("id", params.userID);

  return true;
}

async function activeTransferredFromOwner(
  supabase: SupabaseAdminClient,
  candidates: string[],
): Promise<string | null> {
  if (candidates.length === 0) return null;
  const { data } = await supabase
    .from("user_subscriptions")
    .select("user_id,tier,status,current_period_ends_at")
    .in("user_id", candidates)
    .in("tier", ["plus", "pro"])
    .in("status", ["active", "trialing", "grace_period"])
    .limit(1);
  const row = (data ?? []).find((item) =>
    isFutureExpiration(item.current_period_ends_at)
  );
  return row?.user_id ? String(row.user_id) : null;
}

async function profileCreatedAt(
  supabase: SupabaseAdminClient,
  userID: string,
): Promise<string | null> {
  const { data } = await supabase
    .from("profiles")
    .select("created_at")
    .eq("id", userID)
    .maybeSingle();
  return typeof data?.created_at === "string" ? data.created_at : null;
}

function originalTransactionID(event: Record<string, unknown>): string | null {
  const value = event.original_transaction_id ??
    event.original_transaction_identifier ??
    event.original_transactionId;
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

async function priorIdentifiedOwnerForOriginalTransaction(params: {
  supabase: SupabaseAdminClient;
  eventID: string;
  userID: string;
  event: Record<string, unknown>;
}): Promise<string | null> {
  const originalID = originalTransactionID(params.event);
  if (!originalID) return null;

  const { data } = await params.supabase
    .from("subscription_events")
    .select("event_id,user_id,received_at")
    .neq("event_id", params.eventID)
    .neq("user_id", params.userID)
    .eq("raw_event->>original_transaction_id", originalID)
    .not("user_id", "is", null)
    .order("received_at", { ascending: true })
    .limit(1);

  const ownerID = data?.[0]?.user_id;
  return typeof ownerID === "string" && ownerID ? ownerID : null;
}

async function processTransferEvent(params: {
  supabase: SupabaseAdminClient;
  event: Record<string, unknown>;
  eventID: string;
  environment: string | null;
  revenueCatAPIKey: string;
}): Promise<Record<string, unknown>> {
  const { transferredFrom, transferredTo } = revenueCatTransferIDs(
    params.event,
  );
  const targetUserID = await existingProfileID(params.supabase, transferredTo);

  if (!targetUserID) {
    await params.supabase
      .from("subscription_events")
      .update({ processed_at: new Date().toISOString() })
      .eq("event_id", params.eventID);
    return {
      ok: true,
      ignored: true,
      reason: "transfer_target_profile_not_found",
      transferred_from: transferredFrom,
      transferred_to: transferredTo,
    };
  }

  const targetState = await fetchRevenueCatSubscriberState(
    targetUserID,
    params.revenueCatAPIKey,
  );

  const lockedOwnerID = targetState.tier === "free"
    ? null
    : await activeTransferredFromOwner(params.supabase, transferredFrom);
  const targetCreatedAt = await profileCreatedAt(params.supabase, targetUserID);
  if (
    targetState.tier !== "free" &&
    (lockedOwnerID ||
      purchasePredatesAccount(
        targetState.originalPurchaseDate ?? targetState.purchaseDate,
        targetCreatedAt,
      ))
  ) {
    await writeSubscriptionState({
      supabase: params.supabase,
      userID: targetUserID,
      revenueCatAppUserID: targetUserID,
      source: "revenuecat_transfer_conflict",
      eventID: params.eventID,
      environment: params.environment,
      state: freeSubscriberState(),
      trialPatch: clearTrialReminderMetadataPatch(),
    });

    await params.supabase
      .from("subscription_events")
      .update({
        user_id: targetUserID,
        processed_at: new Date().toISOString(),
      })
      .eq("event_id", params.eventID);

    return {
      ok: true,
      transfer_conflict: true,
      user_id: targetUserID,
      locked_owner_user_id: lockedOwnerID,
      purchase_date: targetState.purchaseDate,
      original_purchase_date: targetState.originalPurchaseDate,
      account_created_at: targetCreatedAt,
      transferred_from: transferredFrom,
      transferred_to: transferredTo,
    };
  }

  await writeSubscriptionState({
    supabase: params.supabase,
    userID: targetUserID,
    revenueCatAppUserID: targetUserID,
    source: "revenuecat_transfer",
    eventID: params.eventID,
    environment: params.environment,
    state: targetState,
  });

  const deactivatedFrom: string[] = [];
  for (const sourceUserID of transferredFrom) {
    if (sourceUserID === targetUserID) continue;
    const didDeactivate = await deactivateTransferredFromUser({
      supabase: params.supabase,
      userID: sourceUserID,
      eventID: params.eventID,
      environment: params.environment,
    });
    if (didDeactivate) deactivatedFrom.push(sourceUserID);
  }

  await params.supabase
    .from("subscription_events")
    .update({
      user_id: targetUserID,
      processed_at: new Date().toISOString(),
    })
    .eq("event_id", params.eventID);

  return {
    ok: true,
    transfer: true,
    user_id: targetUserID,
    tier: targetState.tier,
    status: targetState.status,
    product_id: targetState.productID,
    deactivated_from: deactivatedFrom,
  };
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const revenueCatAPIKey = Deno.env.get("REVENUECAT_REST_API_KEY") ??
    Deno.env.get("REVENUECAT_PUBLIC_API_KEY") ??
    PUBLIC_REVENUECAT_API_KEY;
  const expectedAuthorization = Deno.env.get(
    "REVENUECAT_WEBHOOK_AUTHORIZATION",
  );

  if (
    !supabaseUrl || !serviceRoleKey || !expectedAuthorization ||
    !revenueCatAPIKey
  ) {
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
  const productID = typeof event.product_id === "string"
    ? event.product_id
    : null;
  const entitlementIDs = normalizeEntitlements(event.entitlement_ids);
  const appUserID = typeof event.app_user_id === "string"
    ? event.app_user_id
    : null;
  const userID = resolveRevenueCatEventUserID(event);
  const environment = typeof event.environment === "string"
    ? event.environment
    : null;

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let eventUserID = userID;
  if (eventUserID) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("id")
      .eq("id", eventUserID)
      .maybeSingle();
    if (!profile) eventUserID = null;
  }

  const { data: existing } = await supabase
    .from("subscription_events")
    .select("event_id,processed_at")
    .eq("event_id", eventID)
    .maybeSingle();

  if (existing?.processed_at) {
    return json(200, { ok: true, duplicate: true });
  }

  if (!existing) {
    const { error: insertError } = await supabase.from("subscription_events")
      .insert({
        event_id: eventID,
        user_id: eventUserID,
        app_user_id: appUserID,
        event_type: eventType,
        product_id: productID,
        entitlement_ids: entitlementIDs,
        environment,
        raw_event: event,
      });
    if (insertError) {
      return json(500, { error: "Failed to record subscription event" });
    }
  }

  if (eventType === "TRANSFER") {
    try {
      return json(
        200,
        await processTransferEvent({
          supabase,
          event,
          eventID,
          environment,
          revenueCatAPIKey,
        }),
      );
    } catch (error) {
      return json(502, {
        error: "transfer_processing_failed",
        event_id: eventID,
        detail: safeLogText(error instanceof Error ? error.message : error),
      });
    }
  }

  if (!eventUserID || eventType === "TEST") {
    await supabase
      .from("subscription_events")
      .update({ processed_at: new Date().toISOString() })
      .eq("event_id", eventID);

    return json(200, { ok: true, ignored: true });
  }

  const shouldRefreshSubscriberState = eventType === "EXPIRATION" ||
    eventType === "CANCELLATION" ||
    ACTIVE_STATUSES.has(eventType) ||
    PASSIVE_STATUSES.has(eventType);

  if (!shouldRefreshSubscriberState) {
    await supabase
      .from("subscription_events")
      .update({ processed_at: new Date().toISOString() })
      .eq("event_id", eventID);

    return json(200, {
      ok: true,
      ignored: true,
      reason: "non_subscription_state_event",
      event_type: eventType,
    });
  }

  let verifiedState: ResolvedSubscriberState;
  try {
    verifiedState = await fetchRevenueCatSubscriberState(
      eventUserID,
      revenueCatAPIKey,
    );
  } catch (error) {
    return json(502, {
      error: "revenuecat_state_verification_failed",
      event_id: eventID,
      detail: safeLogText(error instanceof Error ? error.message : error),
    });
  }

  if (verifiedState.tier !== "free") {
    const accountCreatedAt = await profileCreatedAt(supabase, eventUserID);
    if (
      purchasePredatesAccount(
        verifiedState.originalPurchaseDate ?? verifiedState.purchaseDate,
        accountCreatedAt,
      )
    ) {
      await writeSubscriptionState({
        supabase,
        userID: eventUserID,
        revenueCatAppUserID: appUserID,
        source: "revenuecat_event_conflict",
        eventID,
        environment,
        state: freeSubscriberState(),
        trialPatch: clearTrialReminderMetadataPatch(),
      });

      await supabase
        .from("subscription_events")
        .update({
          processed_at: new Date().toISOString(),
        })
        .eq("event_id", eventID);

      return json(200, {
        ok: true,
        event_conflict: true,
        reason: "purchase_predates_account",
        user_id: eventUserID,
        purchase_date: verifiedState.purchaseDate,
        original_purchase_date: verifiedState.originalPurchaseDate,
        account_created_at: accountCreatedAt,
        event_type: eventType,
      });
    }

    const priorOwnerID = await priorIdentifiedOwnerForOriginalTransaction({
      supabase,
      eventID,
      userID: eventUserID,
      event,
    });
    if (priorOwnerID) {
      await writeSubscriptionState({
        supabase,
        userID: eventUserID,
        revenueCatAppUserID: appUserID,
        source: "revenuecat_event_conflict",
        eventID,
        environment,
        state: freeSubscriberState(),
        trialPatch: clearTrialReminderMetadataPatch(),
      });

      await supabase
        .from("subscription_events")
        .update({
          processed_at: new Date().toISOString(),
        })
        .eq("event_id", eventID);

      return json(200, {
        ok: true,
        event_conflict: true,
        reason: "original_transaction_seen_on_another_user",
        user_id: eventUserID,
        owner_user_id: priorOwnerID,
        event_type: eventType,
      });
    }
  }

  const existingSubscription = await existingSubscriptionRow(
    supabase,
    eventUserID,
  );
  const eventTrialPatch = trialMetadataPatchForRevenueCatEvent(
    eventType,
    event,
    verifiedState.productID,
    verifiedState.expiration,
    verifiedState.purchaseDate,
    existingSubscription,
  );
  const verifiedTrialPatch = verifiedTrialMetadataPatch({
    productID: verifiedState.productID,
    periodType: verifiedState.periodType,
    purchaseDate: verifiedState.purchaseDate,
    expiration: verifiedState.expiration,
    renewalIntent: verifiedState.renewalIntent,
  }, existingSubscription);

  await writeSubscriptionState({
    supabase,
    userID: eventUserID,
    revenueCatAppUserID: appUserID,
    source: "revenuecat_verified_event",
    eventID,
    environment,
    state: verifiedState,
    // The verified subscriber snapshot wins over a duplicated or delayed
    // cancellation event when it exposes current renewal intent.
    trialPatch: mergeTrialMetadataPatches(
      eventTrialPatch,
      verifiedTrialPatch,
    ),
  });

  await sendAccountUpdatePush({
    supabaseUrl,
    serviceRoleKey,
    userID: eventUserID,
    eventID,
    eventType,
    tier: verifiedState.tier === "free" ? null : verifiedState.tier,
  });

  await supabase
    .from("subscription_events")
    .update({ processed_at: new Date().toISOString() })
    .eq("event_id", eventID);

  return json(200, { ok: true });
});
