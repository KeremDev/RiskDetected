/**
 * send-push-notification — fail-closed APNs sender for RiskDetected.
 *
 * Required secrets:
 * - APNS_KEY_ID
 * - APNS_TEAM_ID
 * - APNS_BUNDLE_ID
 * - APNS_PRIVATE_KEY
 * - APNS_ENV (sandbox | production)
 *
 * This function keeps verify_jwt=false for backwards compatibility and performs
 * an exact service-role Authorization check in the function body.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  notificationContentError,
  type NotificationDestination,
  notificationDestinationError,
  notificationKindContract,
  notificationPayloadError,
  type NotificationPreferenceKey,
  type NotificationSource,
} from "../_shared/notification-contract.ts";
import {
  type APNsAttempt,
  deliverToAPNs,
  mapWithConcurrency,
} from "./apns-delivery.ts";
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
// change. This is the seam a Faz 7 FCM sender calls into with provider="fcm" instead — the
// full providers/apns.ts + providers/fcm.ts + dispatch() file split from the review doc's F4
// write-up is deferred to Faz 7, where a second real provider actually exists to justify it;
// doing that reorg now on a live, unstaged push path for zero near-term benefit isn't worth
// the blast radius (no separate staging Supabase project yet — DEC-12).
async function recordDeliveryAttempt(params: {
  supabase: SupabaseAdminClient;
  eventID: string;
  jobID: string | null;
  tokenID: string;
  environment: "sandbox" | "production";
  attempt: APNsAttempt;
}) {
  const { error } = await params.supabase.rpc(
    "record_notification_delivery_attempt_v2",
    {
      p_notification_event_id: params.eventID,
      p_job_id: params.jobID,
      p_push_device_token_id: params.tokenID,
      p_environment: params.environment,
      p_attempt_number: params.attempt.attemptNumber,
      p_outcome: params.attempt.outcome,
      p_provider: "apns",
      p_http_status: params.attempt.httpStatus,
      p_provider_message_id: params.attempt.apnsID,
      p_reason: params.attempt.reason,
      p_duration_ms: params.attempt.durationMs,
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
    .select("id,token,environment")
    .eq("user_id", request.user_id)
    .eq("notifications_enabled", true);
  if (tokenError) {
    return json(503, { error: "device_token_query_failed" });
  }

  const deviceTokens = ((tokens ?? []) as Array<{
    id: string;
    token: string;
    environment?: string | null;
  }>).map((token) => ({
    id: token.id,
    token: token.token,
    environment: token.environment === "production" ||
        token.environment === "sandbox"
      ? token.environment
      : fallbackEnvironment(),
  })) as PushToken[];
  const environments = [
    ...new Set(deviceTokens.map((token) => token.environment)),
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
      status: deviceTokens.length > 0 ? "queued" : "skipped",
      lastError: deviceTokens.length > 0 ? null : "no_active_device_tokens",
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

  if (deviceTokens.length === 0) {
    return json(200, {
      status: "skipped",
      reason: "no_active_device_tokens",
      event_id: eventID,
      environments,
    });
  }

  let providerToken: string;
  try {
    providerToken = await makeProviderToken();
  } catch (error) {
    await supabase.from("notification_events").update({
      status: "failed",
      failure_count: deviceTokens.length,
      last_error: safeErrorText(error),
    }).eq("id", eventID);
    return json(500, {
      error: "apns_credentials_not_configured",
      event_id: eventID,
    });
  }

  const now = new Date().toISOString();
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

  const results = await mapWithConcurrency(
    deviceTokens,
    4,
    async (token) => {
      const result = await deliverToAPNs({
        url: `${apnsHost(token.environment)}/3/device/${token.token}`,
        headers: {
          authorization: `bearer ${providerToken}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "content-type": "application/json",
        },
        payload: apnsPayload,
        onAttempt: (attempt) =>
          recordDeliveryAttempt({
            supabase,
            eventID,
            jobID: request.job_id ?? null,
            tokenID: token.id,
            environment: token.environment,
            attempt,
          }),
      });

      const final = result.final;
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
      return { token, result };
    },
  );

  const sent = results.filter(({ result }) =>
    result.final.outcome === "accepted"
  ).length;
  const failed = results.length - sent;
  const ambiguous =
    results.filter(({ result }) => result.final.outcome === "ambiguous").length;
  const transientExhausted = results.some(({ result }) =>
    result.final.outcome === "transient"
  );
  const lastError = results
    .map(({ token, result }) =>
      result.final.outcome === "accepted"
        ? null
        : `${token.environment}:${result.final.outcome}:${result.final.reason}`
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
          .filter(({ result }) => result.final.outcome === "accepted")
          .map(({ token }) => token.environment),
      ),
    ].sort(),
    failed_environments: [
      ...new Set(
        results
          .filter(({ result }) => result.final.outcome !== "accepted")
          .map(({ token }) => token.environment),
      ),
    ].sort(),
  });
});
