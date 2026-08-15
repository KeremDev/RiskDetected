/**
 * send-push-notification — fail-closed APNs + FCM sender for RiskDetected.
 *
 * Required secrets:
 * - APNS_KEY_ID
 * - APNS_TEAM_ID
 * - APNS_BUNDLE_ID
 * - APNS_PRIVATE_KEY
 * - APNS_ENV (sandbox | production)
 * localization-inventory: machine-prompt-begin
 * - FCM_SERVICE_ACCOUNT_JSON (the raw contents of a Firebase service account key JSON with
 *   the "Firebase Cloud Messaging API" scope — Android tokens fail closed with
 *   fcm_credentials_not_configured until this is set, same fail-closed shape APNs already had)
 * localization-inventory: machine-prompt-end
 *
 * This function keeps verify_jwt=false for backwards compatibility and performs
 * an exact service-role Authorization check in the function body.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  ANDROID_RUNTIME_GATE_KEYS,
  type AndroidRuntimeGateName,
  evaluateAndroidRuntimeGates,
} from "../_shared/android-runtime-gates.ts";
import {
  notificationContentError,
  type NotificationDestination,
  notificationDestinationError,
  notificationKindContract,
  notificationPayloadError,
  type NotificationPreferenceKey,
  type NotificationSource,
  type PushOutcome,
} from "../_shared/notification-contract.ts";
import {
  type APNsAttempt,
  deliverToAPNs,
  mapWithConcurrency,
} from "./apns-delivery.ts";
import { deliverToFcm, type FcmAttempt } from "./fcm-delivery.ts";
import {
  resolveTransactionalNotificationTemplate,
} from "../_shared/transactional-notification-localization.ts";

type PushRequest = {
  user_id?: string;
  kind?: string;
  event_key?: string;
  title?: string;
  body?: string;
  data?: Record<string, unknown>;
  source?: NotificationSource;
  job_id?: string | null;
  campaign_id?: string | null;
  template_id?: string | null;
  dedupe_key?: string | null;
  localization?: {
    language: "tr" | "en";
    locale: string;
    snapshot: Record<string, unknown>;
    templateLocale: string | null;
    templateLocalizationID: string | null;
  };
};

type PushToken = {
  id: string;
  token: string;
  environment: "sandbox" | "production";
  provider: "apns" | "fcm";
  clientBuild: number | null;
};

/** Normalized shape both the APNs and FCM delivery loops reduce their results into, so the
 * final sent/failed/ambiguous/lastError/event-status logic (previously APNs-only) doesn't need
 * to know which provider produced a given outcome. */
type DeliveryOutcome = {
  token: PushToken;
  outcome: PushOutcome;
  reason: string;
};

type PreferenceRow = {
  enabled: boolean;
  analysis_complete: boolean;
  report_ready: boolean;
  account_updates: boolean;
  trial_reminder: boolean;
  progress_weekly_summary: boolean;
  progress_monthly_summary: boolean;
  progress_milestones: boolean;
  app_reminders: boolean;
};

async function filterAndroidRuntimeEnabledTokens(
  supabase: SupabaseAdminClient,
  tokens: PushToken[],
): Promise<PushToken[]> {
  if (!tokens.some((token) => token.provider === "fcm")) return tokens;

  const names = Object.keys(
    ANDROID_RUNTIME_GATE_KEYS,
  ) as AndroidRuntimeGateName[];
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("key,value")
    .in("key", Object.values(ANDROID_RUNTIME_GATE_KEYS));
  if (error || !Array.isArray(data)) {
    return tokens.filter((token) => token.provider !== "fcm");
  }
  const rows = new Map<string, unknown>(
    data.map((row: Record<string, unknown>) => [String(row.key), row.value]),
  );
  const values = Object.fromEntries(
    names.map((name) => [name, rows.get(ANDROID_RUNTIME_GATE_KEYS[name])]),
  ) as Partial<Record<AndroidRuntimeGateName, unknown>>;

  return tokens.filter((token) =>
    token.provider !== "fcm" ||
    evaluateAndroidRuntimeGates(values, token.clientBuild).notifications.enabled
  );
}

type SupabaseAdminClient = ReturnType<typeof createClient<any>>;

let cachedProviderToken:
  | { value: string; createdAtMilliseconds: number }
  | null = null;

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function safeErrorText(value: unknown, maxLength = 180): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .replace(/[A-Fa-f0-9]{64,}/g, "[hex]")
    .slice(0, maxLength);
}

function base64URL(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

function base64URLText(value: string): string {
  return base64URL(new TextEncoder().encode(value).buffer);
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const normalized = pem
    .replaceAll("\\n", "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

async function makeProviderToken(): Promise<string> {
  const now = Date.now();
  if (
    cachedProviderToken &&
    now - cachedProviderToken.createdAtMilliseconds < 45 * 60 * 1000
  ) {
    return cachedProviderToken.value;
  }

  const keyID = requiredEnv("APNS_KEY_ID");
  const teamID = requiredEnv("APNS_TEAM_ID");
  const privateKey = requiredEnv("APNS_PRIVATE_KEY");
  const header = { alg: "ES256", kid: keyID };
  const claims = { iss: teamID, iat: Math.floor(now / 1000) };
  const signingInput = `${base64URLText(JSON.stringify(header))}.${
    base64URLText(JSON.stringify(claims))
  }`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const value = `${signingInput}.${base64URL(signature)}`;
  cachedProviderToken = { value, createdAtMilliseconds: now };
  return value;
}

function fallbackEnvironment(): "sandbox" | "production" {
  return Deno.env.get("APNS_ENV") === "production" ? "production" : "sandbox";
}

function apnsHost(environment: "sandbox" | "production"): string {
  return environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
}

type FcmServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

function parseFcmServiceAccount(): FcmServiceAccount {
  const raw = requiredEnv("FCM_SERVICE_ACCOUNT_JSON");
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("fcm_service_account_json_invalid");
  }
  const value = parsed as Partial<FcmServiceAccount>;
  if (!value.client_email || !value.private_key || !value.project_id) {
    throw new Error("fcm_service_account_fields_missing");
  }
  return value as FcmServiceAccount;
}

let cachedFcmToken:
  | {
    value: string;
    projectId: string;
    createdAtMilliseconds: number;
    validForMilliseconds: number;
  }
  | null = null;

// localization-inventory: machine-prompt-begin
/** Google OAuth2 service-account JWT-bearer flow (RFC 7523) — the FCM HTTP v1 API's auth
 * scheme, structurally the same shape as APNs's `makeProviderToken` above (build a signed JWT,
 * cache the result) but RS256 against a Google service account instead of ES256 against an
 * Apple auth key, and with an extra token-exchange round trip Apple's scheme doesn't need
 * (APNs accepts the signed JWT directly as the bearer token; Google exchanges it for a
 * short-lived OAuth2 access token first). */
// localization-inventory: machine-prompt-end
async function makeFcmProviderToken(): Promise<
  { accessToken: string; projectId: string }
> {
  const now = Date.now();
  if (
    cachedFcmToken &&
    now - cachedFcmToken.createdAtMilliseconds <
      cachedFcmToken.validForMilliseconds
  ) {
    return {
      accessToken: cachedFcmToken.value,
      projectId: cachedFcmToken.projectId,
    };
  }

  const account = parseFcmServiceAccount();
  const iat = Math.floor(now / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat,
    exp: iat + 3600,
  };
  const signingInput = `${base64URLText(JSON.stringify(header))}.${
    base64URLText(JSON.stringify(claims))
  }`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  const assertion = `${signingInput}.${base64URL(signature)}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }).toString(),
  });
  if (!response.ok) {
    throw new Error(`fcm_oauth_token_exchange_failed:${response.status}`);
  }
  const body = await response.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!body.access_token) {
    throw new Error("fcm_oauth_token_exchange_missing_access_token");
  }
  cachedFcmToken = {
    value: body.access_token,
    projectId: account.project_id,
    createdAtMilliseconds: now,
    // A 5-minute safety margin before the token's real expiry (typically 3600s) — same margin
    // philosophy as APNs's 45-minute cache against a JWT technically valid ~60 minutes.
    validForMilliseconds: Math.max(
      60_000,
      ((body.expires_in ?? 3600) - 300) * 1000,
    ),
  };
  return { accessToken: body.access_token, projectId: account.project_id };
}

async function createEvent(params: {
  supabase: SupabaseAdminClient;
  request: PushRequest;
  kind: string;
  source: NotificationSource;
  destination: NotificationDestination | null;
  status: "queued" | "skipped";
  lastError: string | null;
}) {
  const { data, error } = await params.supabase
    .from("notification_events")
    .insert({
      user_id: params.request.user_id,
      kind: params.kind,
      title: params.request.title,
      body: params.request.body,
      data: params.request.data ?? {},
      source: params.source,
      job_id: params.request.job_id ?? null,
      campaign_id: params.request.campaign_id ?? null,
      template_id: params.request.template_id ?? null,
      destination: params.destination,
      dedupe_key: params.request.dedupe_key ?? null,
      status: params.status,
      last_error: params.lastError,
      language: params.request.localization?.language ?? null,
      locale: params.request.localization?.locale ?? null,
      localization_snapshot: params.request.localization?.snapshot ?? null,
      template_locale: params.request.localization?.templateLocale ?? null,
      template_localization_id:
        params.request.localization?.templateLocalizationID ?? null,
    })
    .select("id")
    .single();
  if (!error) {
    return {
      id: data.id as string,
      status: params.status,
      existing: false,
      sentCount: 0,
      failureCount: 0,
    };
  }

  if (error.code === "23505" && params.request.dedupe_key) {
    const { data: existing, error: existingError } = await params.supabase
      .from("notification_events")
      .select("id,status,sent_count,failure_count")
      .eq("dedupe_key", params.request.dedupe_key)
      .maybeSingle();
    if (!existingError && existing?.id) {
      return {
        id: existing.id as string,
        status: existing.status as "queued" | "sent" | "failed" | "skipped",
        existing: true,
        sentCount: Number(existing.sent_count ?? 0),
        failureCount: Number(existing.failure_count ?? 0),
      };
    }
  }

  throw new Error(`notification_event_insert_failed:${error.code}`);
}

// F4: calls record_notification_delivery_attempt_v2 directly (provider-agnostic) instead of
// v1. Row shape/behavior for provider="apns" is proven identical to the old v1 call by the
// pgTAP suite (android_notification_delivery_attempt_v2_test.sql) — v1 itself now just
// delegates to v2 with these same arguments, so this is a same-behavior, different-entrypoint
// change. `provider` is now a real parameter, not hardcoded "apns" — this is the seam the F4
// comment anticipated a Faz 7 FCM sender calling into with provider="fcm", now wired for real.
// The full providers/apns.ts + providers/fcm.ts + dispatch() *file* split from the review doc's
// F4 write-up still isn't done (this function still holds both providers inline) — that reorg
// is a separate, purely-organizational follow-up, not required to make FCM sending itself work.
async function recordDeliveryAttempt(params: {
  supabase: SupabaseAdminClient;
  eventID: string;
  jobID: string | null;
  tokenID: string;
  environment: "sandbox" | "production";
  provider: "apns" | "fcm";
  attemptNumber: number;
  outcome: PushOutcome;
  httpStatus: number | null;
  providerMessageID: string | null;
  reason: string;
  durationMs: number;
}) {
  const { error } = await params.supabase.rpc(
    "record_notification_delivery_attempt_v2",
    {
      p_notification_event_id: params.eventID,
      p_job_id: params.jobID,
      p_push_device_token_id: params.tokenID,
      p_environment: params.environment,
      p_attempt_number: params.attemptNumber,
      p_outcome: params.outcome,
      p_provider: params.provider,
      p_http_status: params.httpStatus,
      p_provider_message_id: params.providerMessageID,
      p_reason: params.reason,
      p_duration_ms: params.durationMs,
    },
  );
  if (error) {
    console.warn(
      "Notification delivery telemetry failed",
      safeErrorText(error.code ?? error.message),
    );
  }
}

async function skipForPreference(params: {
  supabase: SupabaseAdminClient;
  request: PushRequest;
  kind: string;
  source: NotificationSource;
  destination: NotificationDestination | null;
  reason: string;
}) {
  const event = await createEvent({
    supabase: params.supabase,
    request: params.request,
    kind: params.kind,
    source: params.source,
    destination: params.destination,
    status: "skipped",
    lastError: params.reason,
  }).catch(() => null);
  return json(200, {
    status: "skipped",
    reason: params.reason,
    event_id: event?.id ?? null,
  });
}

function eventKeyMatchesKind(kind: string, eventKey: string): boolean {
  if (kind === "account_updates") {
    return eventKey.startsWith("account_update.");
  }
  return kind === eventKey;
}

async function resolveManagedContent(params: {
  supabase: SupabaseAdminClient;
  request: PushRequest;
  source: NotificationSource;
}): Promise<
  | { ok: true; request: PushRequest }
  | { ok: false; code: string; locale: string | null }
> {
  const userID = params.request.user_id!;
  const kind = params.request.kind!;

  if (params.source === "automation" || params.source === "manual") {
    if (!params.request.job_id) {
      return {
        ok: false,
        code: "NOTIFICATION_JOB_ID_REQUIRED",
        locale: null,
      };
    }
    const { data, error } = await params.supabase.rpc(
      "notification_job_delivery_content_v1",
      { p_job_id: params.request.job_id },
    );
    if (
      error || data?.allowed !== true || data?.user_id !== userID ||
      data?.kind !== kind || typeof data?.title !== "string" ||
      typeof data?.body !== "string" || typeof data?.locale !== "string" ||
      (data?.language !== "tr" && data?.language !== "en")
    ) {
      return {
        ok: false,
        code: "NOTIFICATION_JOB_CONTENT_UNAVAILABLE",
        locale: typeof data?.locale === "string" ? data.locale : null,
      };
    }
    return {
      ok: true,
      request: {
        ...params.request,
        title: data.title,
        body: data.body,
        template_id: data.template_id ?? params.request.template_id ?? null,
        localization: {
          language: data.language,
          locale: data.locale,
          snapshot: data.localization_snapshot ?? {
            schema_version: 1,
            content_mode: "managed_job",
          },
          templateLocale: data.template_locale ?? null,
          templateLocalizationID: data.template_localization_id ?? null,
        },
      },
    };
  }

  const { data: profile, error: profileError } = await params.supabase
    .from("profiles")
    .select("app_language,preferred_content_locale")
    .eq("id", userID)
    .maybeSingle();
  const locale = typeof profile?.preferred_content_locale === "string"
    ? profile.preferred_content_locale
    : null;
  if (
    profileError || !profile || locale === null ||
    (profile.app_language !== "tr" && profile.app_language !== "en")
  ) {
    return {
      ok: false,
      code: "NOTIFICATION_RECIPIENT_LOCALE_MISSING",
      locale,
    };
  }
  if (
    typeof params.request.event_key !== "string" ||
    !eventKeyMatchesKind(kind, params.request.event_key)
  ) {
    return {
      ok: false,
      code: "NOTIFICATION_EVENT_KEY_KIND_MISMATCH",
      locale,
    };
  }

  const resolution = await resolveTransactionalNotificationTemplate({
    eventKey: params.request.event_key,
    locale,
  });
  if (!resolution.ok) {
    return { ok: false, code: resolution.code, locale };
  }
  if (resolution.language !== profile.app_language) {
    return {
      ok: false,
      code: "NOTIFICATION_PROFILE_LANGUAGE_LOCALE_MISMATCH",
      locale,
    };
  }

  return {
    ok: true,
    request: {
      ...params.request,
      title: resolution.title,
      body: resolution.body,
      localization: {
        language: resolution.language,
        locale: resolution.locale,
        snapshot: {
          schema_version: 1,
          content_mode: "transactional_event_catalog",
          event_key: resolution.eventKey,
          locale: resolution.locale,
          language: resolution.language,
          template_checksum: resolution.checksum,
          resolved_at: new Date().toISOString(),
        },
        templateLocale: resolution.locale,
        templateLocalizationID: null,
      },
    },
  };
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, {
      error: "Supabase service credentials are not configured",
    });
  }
  if (req.headers.get("Authorization") !== `Bearer ${serviceRoleKey}`) {
    return json(401, { error: "Unauthorized" });
  }

  let rawRequest: PushRequest;
  try {
    rawRequest = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body" });
  }

  if (!rawRequest.user_id || !rawRequest.kind) {
    return json(400, { error: "user_id and kind are required" });
  }
  const notificationKind = rawRequest.kind;
  const contract = notificationKindContract(notificationKind);
  if (!contract) {
    return json(400, { error: "unknown_notification_kind" });
  }

  const payloadData = rawRequest.data ?? {};
  const payloadError = notificationPayloadError(payloadData);
  if (payloadError) return json(400, { error: payloadError });
  const destination = payloadData.destination ?? null;
  const destinationError = notificationDestinationError({
    contract,
    destination,
  });
  if (destinationError) return json(400, { error: destinationError });

  const source = rawRequest.source ?? contract.defaultSource;
  if (
    !["transactional", "trial", "progress", "automation", "manual"].includes(
      source,
    )
  ) {
    return json(400, { error: "invalid_notification_source" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const managedContent = await resolveManagedContent({
    supabase,
    request: rawRequest,
    source,
  });
  if (!managedContent.ok) {
    const failureLanguage = managedContent.locale === "tr-TR"
      ? "tr"
      : managedContent.locale?.startsWith("en-")
      ? "en"
      : null;
    const blockedRequest: PushRequest = {
      ...rawRequest,
      title: "LOCALIZATION_BLOCKED",
      body: "Notification delivery was blocked by exact-locale resolution.",
      localization: failureLanguage && managedContent.locale
        ? {
          language: failureLanguage,
          locale: managedContent.locale,
          snapshot: {
            schema_version: 1,
            content_mode: "blocked",
            error_code: managedContent.code,
            requested_locale: managedContent.locale,
            resolved_at: new Date().toISOString(),
          },
          templateLocale: null,
          templateLocalizationID: null,
        }
        : undefined,
    };
    const event = await createEvent({
      supabase,
      request: blockedRequest,
      kind: rawRequest.kind,
      source,
      destination: destination as NotificationDestination | null,
      status: "skipped",
      lastError: managedContent.code,
    }).catch(() => null);
    return json(422, {
      error: managedContent.code,
      status: "skipped",
      event_id: event?.id ?? null,
    });
  }
  const request = managedContent.request;
  const contentError = notificationContentError({
    title: request.title,
    body: request.body,
  });
  if (contentError) return json(500, { error: contentError });

  const { data: preference, error: preferenceError } = await supabase
    .from("notification_preferences")
    .select(
      "enabled,analysis_complete,report_ready,account_updates,trial_reminder,progress_weekly_summary,progress_monthly_summary,progress_milestones,app_reminders",
    )
    .eq("user_id", request.user_id)
    .maybeSingle();

  if (preferenceError) {
    return skipForPreference({
      supabase,
      request,
      kind: notificationKind,
      source,
      destination: destination as NotificationDestination | null,
      reason: "preference_query_failed",
    });
  }

  const preferenceRow = preference as PreferenceRow | null;
  const allowedByKind = preferenceRow
    ? preferenceRow[contract.preferenceKey as NotificationPreferenceKey]
    : !contract.requiresPreferenceRow;
  if (
    (contract.requiresPreferenceRow && !preferenceRow) ||
    preferenceRow?.enabled === false ||
    allowedByKind !== true
  ) {
    return skipForPreference({
      supabase,
      request,
      kind: notificationKind,
      source,
      destination: destination as NotificationDestination | null,
      reason: !preferenceRow
        ? "preference_row_required"
        : "user_preference_disabled",
    });
  }

  const { data: tokens, error: tokenError } = await supabase
    .from("push_device_tokens")
    .select("id,token,environment,provider,client_build")
    .eq("user_id", request.user_id)
    .eq("notifications_enabled", true);
  if (tokenError) {
    return json(503, { error: "device_token_query_failed" });
  }

  const deviceTokens = ((tokens ?? []) as Array<{
    id: string;
    token: string;
    environment?: string | null;
    provider?: string | null;
    client_build?: string | null;
  }>).map((token) => ({
    id: token.id,
    token: token.token,
    environment: token.environment === "production" ||
        token.environment === "sandbox"
      ? token.environment
      : fallbackEnvironment(),
    // Legacy rows predate the `provider` column (F2) and are all iOS — default to "apns" rather
    // than reject them, same additive-migration spirit as `fallbackEnvironment` above.
    provider: token.provider === "fcm" ? "fcm" : "apns",
    clientBuild: (() => {
      const parsed = Math.round(Number(token.client_build));
      return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
    })(),
  })) as PushToken[];
  const runtimeEnabledTokens = await filterAndroidRuntimeEnabledTokens(
    supabase,
    deviceTokens,
  );
  const apnsTokens = runtimeEnabledTokens.filter((token) =>
    token.provider === "apns"
  );
  const fcmTokens = runtimeEnabledTokens.filter((token) =>
    token.provider === "fcm"
  );
  const environments = [
    ...new Set(runtimeEnabledTokens.map((token) => token.environment)),
  ]
    .sort();

  let event: Awaited<ReturnType<typeof createEvent>>;
  try {
    event = await createEvent({
      supabase,
      request,
      kind: notificationKind,
      source,
      destination: destination as NotificationDestination | null,
      status: runtimeEnabledTokens.length > 0 ? "queued" : "skipped",
      lastError: runtimeEnabledTokens.length > 0
        ? null
        : "no_active_device_tokens",
    });
  } catch (error) {
    return json(500, {
      error: "notification_event_insert_failed",
      detail: safeErrorText(error),
    });
  }
  const eventID = event.id;

  if (event.existing) {
    if (event.status === "sent") {
      return json(200, {
        status: "sent",
        event_id: eventID,
        sent: event.sentCount,
        failed: event.failureCount,
        deduplicated: true,
      });
    }
    if (event.status === "skipped") {
      return json(200, {
        status: "skipped",
        event_id: eventID,
        reason: "deduplicated_existing_skip",
        deduplicated: true,
      });
    }
    return json(200, {
      status: "failed",
      event_id: eventID,
      ambiguous: event.status === "queued" ? 1 : 0,
      retryable: false,
      error: event.status === "queued"
        ? "ambiguous_transport"
        : "deduplicated_existing_failure",
      deduplicated: true,
    });
  }

  if (runtimeEnabledTokens.length === 0) {
    return json(200, {
      status: "skipped",
      reason: "no_active_device_tokens",
      event_id: eventID,
      environments,
    });
  }

  // Fail-closed per provider: only acquire (and require) credentials for a provider that
  // actually has pending tokens this call. A staging project with zero FCM tokens registered
  // yet must not fail on a missing FCM_SERVICE_ACCOUNT_JSON, mirroring how APNs already worked
  // before FCM existed. If a provider *with* pending tokens can't get credentials, the whole
  // request still fails closed (matches this function's existing all-or-nothing philosophy —
  // half-sent states would complicate the event status/dedupe logic for little benefit).
  let apnsProviderToken: string | null = null;
  if (apnsTokens.length > 0) {
    try {
      apnsProviderToken = await makeProviderToken();
    } catch (error) {
      await supabase.from("notification_events").update({
        status: "failed",
        failure_count: runtimeEnabledTokens.length,
        last_error: safeErrorText(error),
      }).eq("id", eventID);
      return json(500, {
        error: "apns_credentials_not_configured",
        event_id: eventID,
      });
    }
  }
  let fcmAuth: { accessToken: string; projectId: string } | null = null;
  if (fcmTokens.length > 0) {
    try {
      fcmAuth = await makeFcmProviderToken();
    } catch (error) {
      await supabase.from("notification_events").update({
        status: "failed",
        failure_count: runtimeEnabledTokens.length,
        last_error: safeErrorText(error),
      }).eq("id", eventID);
      return json(500, {
        error: "fcm_credentials_not_configured",
        event_id: eventID,
      });
    }
  }

  const now = new Date().toISOString();

  async function finalizeTokenDelivery(
    token: PushToken,
    final: { outcome: PushOutcome; reason: string; disableToken: boolean },
  ) {
    if (final.outcome === "accepted") {
      await supabase.from("push_device_tokens").update({
        last_success_at: now,
        last_failure_reason: null,
      }).eq("id", token.id);
    } else {
      await supabase.from("push_device_tokens").update({
        notifications_enabled: final.disableToken ? false : true,
        last_failure_at: now,
        last_failure_reason: `${final.outcome}:${final.reason}`,
      }).eq("id", token.id);
    }
  }

  const topic = Deno.env.get("APNS_BUNDLE_ID") ?? "com.riskdetected.app";
  const apnsPayload = {
    aps: {
      alert: { title: request.title, body: request.body },
      sound: "default",
    },
    data: payloadData,
    kind: notificationKind,
    event_id: eventID,
  };

  // Android receives a typed, minimal deep-link contract only. Display title/body stay in the
  // FCM notification envelope; arbitrary request data, PII and raw message content never enter
  // the FCM data map. APNs remains byte-for-byte compatible with the existing iOS payload.
  const fcmDataPayload: Record<string, string> = {
    type: notificationKind,
    event_id: eventID,
  };
  for (const key of ["analysis_id", "report_id"] as const) {
    const value = payloadData[key];
    if (
      typeof value === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(value)
    ) {
      fcmDataPayload[key] = value;
    }
  }

  const apnsResults = apnsTokens.length === 0 ? [] : await mapWithConcurrency(
    apnsTokens,
    4,
    async (token): Promise<DeliveryOutcome> => {
      const result = await deliverToAPNs({
        url: `${apnsHost(token.environment)}/3/device/${token.token}`,
        headers: {
          authorization: `bearer ${apnsProviderToken!}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "content-type": "application/json",
        },
        payload: apnsPayload,
        onAttempt: (attempt: APNsAttempt) =>
          recordDeliveryAttempt({
            supabase,
            eventID,
            jobID: request.job_id ?? null,
            tokenID: token.id,
            environment: token.environment,
            provider: "apns",
            attemptNumber: attempt.attemptNumber,
            outcome: attempt.outcome,
            httpStatus: attempt.httpStatus,
            providerMessageID: attempt.apnsID,
            reason: attempt.reason,
            durationMs: attempt.durationMs,
          }),
      });
      await finalizeTokenDelivery(token, result.final);
      return {
        token,
        outcome: result.final.outcome,
        reason: result.final.reason,
      };
    },
  );

  const fcmResults = fcmTokens.length === 0 ? [] : await mapWithConcurrency(
    fcmTokens,
    4,
    async (token): Promise<DeliveryOutcome> => {
      const result = await deliverToFcm({
        url: `https://fcm.googleapis.com/v1/projects/${
          fcmAuth!.projectId
        }/messages:send`,
        headers: {
          authorization: `Bearer ${fcmAuth!.accessToken}`,
          "content-type": "application/json",
        },
        payload: {
          message: {
            token: token.token,
            notification: { title: request.title, body: request.body },
            data: fcmDataPayload,
            android: { priority: "high" },
          },
        },
        onAttempt: (attempt: FcmAttempt) =>
          recordDeliveryAttempt({
            supabase,
            eventID,
            jobID: request.job_id ?? null,
            tokenID: token.id,
            environment: token.environment,
            provider: "fcm",
            attemptNumber: attempt.attemptNumber,
            outcome: attempt.outcome,
            httpStatus: attempt.httpStatus,
            providerMessageID: attempt.messageID,
            reason: attempt.reason,
            durationMs: attempt.durationMs,
          }),
      });
      await finalizeTokenDelivery(token, result.final);
      return {
        token,
        outcome: result.final.outcome,
        reason: result.final.reason,
      };
    },
  );

  const results = [...apnsResults, ...fcmResults];

  const sent = results.filter(({ outcome }) => outcome === "accepted").length;
  const failed = results.length - sent;
  const ambiguous = results.filter(({ outcome }) =>
    outcome === "ambiguous"
  ).length;
  const transientExhausted = results.some(({ outcome }) =>
    outcome === "transient"
  );
  const lastError = results
    .map(({ token, outcome, reason }) =>
      outcome === "accepted"
        ? null
        : `${token.environment}:${outcome}:${reason}`
    )
    .filter(Boolean)
    .at(-1) ?? null;

  await supabase.from("notification_events").update({
    status: sent > 0 ? "sent" : "failed",
    sent_count: sent,
    failure_count: failed,
    last_error: lastError,
    sent_at: sent > 0 ? now : null,
  }).eq("id", eventID);

  return json(200, {
    status: sent > 0 ? "sent" : "failed",
    event_id: eventID,
    sent,
    failed,
    ambiguous,
    retryable: false,
    transient_exhausted: transientExhausted,
    environments,
    sent_environments: [
      ...new Set(
        results
          .filter(({ outcome }) => outcome === "accepted")
          .map(({ token }) => token.environment),
      ),
    ].sort(),
    failed_environments: [
      ...new Set(
        results
          .filter(({ outcome }) => outcome !== "accepted")
          .map(({ token }) => token.environment),
      ),
    ].sort(),
  });
});
