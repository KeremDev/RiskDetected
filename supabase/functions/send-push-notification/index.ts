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

type PushRequest = {
  user_id?: string;
  kind?: string;
  title?: string;
  body?: string;
  data?: Record<string, unknown>;
  source?: NotificationSource;
  job_id?: string | null;
  campaign_id?: string | null;
  template_id?: string | null;
  dedupe_key?: string | null;
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

async function recordDeliveryAttempt(params: {
  supabase: SupabaseAdminClient;
  eventID: string;
  jobID: string | null;
  tokenID: string;
  environment: "sandbox" | "production";
  attempt: APNsAttempt;
}) {
  const { error } = await params.supabase.rpc(
    "record_notification_delivery_attempt_v1",
    {
      p_notification_event_id: params.eventID,
      p_job_id: params.jobID,
      p_push_device_token_id: params.tokenID,
      p_environment: params.environment,
      p_attempt_number: params.attempt.attemptNumber,
      p_outcome: params.attempt.outcome,
      p_http_status: params.attempt.httpStatus,
      p_apns_id: params.attempt.apnsID,
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

  let request: PushRequest;
  try {
    request = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body" });
  }

  if (!request.user_id || !request.kind) {
    return json(400, { error: "user_id and kind are required" });
  }
  const contract = notificationKindContract(request.kind);
  if (!contract) {
    return json(400, { error: "unknown_notification_kind" });
  }
  const contentError = notificationContentError({
    title: request.title,
    body: request.body,
  });
  if (contentError) return json(400, { error: contentError });

  const payloadData = request.data ?? {};
  const payloadError = notificationPayloadError(payloadData);
  if (payloadError) return json(400, { error: payloadError });
  const destination = payloadData.destination ?? null;
  const destinationError = notificationDestinationError({
    contract,
    destination,
  });
  if (destinationError) return json(400, { error: destinationError });

  const source = request.source ?? contract.defaultSource;
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
      kind: request.kind,
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
      kind: request.kind,
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
      kind: request.kind,
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
    kind: request.kind,
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
