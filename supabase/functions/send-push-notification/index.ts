/**
 * send-push-notification — APNs push sender for RiskDetected.
 *
 * Required secrets before real delivery:
 * - APNS_KEY_ID
 * - APNS_TEAM_ID
 * - APNS_BUNDLE_ID (usually com.riskdetected.app)
 * - APNS_PRIVATE_KEY (contents of the .p8 key, with escaped or real newlines)
 * - APNS_ENV (sandbox | production)
 *
 * Call this only from trusted backend/admin contexts with service-role auth.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type PushRequest = {
  user_id?: string;
  kind?: string;
  title?: string;
  body?: string;
  data?: Record<string, unknown>;
};

type PushToken = {
  id: string;
  token: string;
};

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
  const keyID = requiredEnv("APNS_KEY_ID");
  const teamID = requiredEnv("APNS_TEAM_ID");
  const privateKey = requiredEnv("APNS_PRIVATE_KEY");

  const header = { alg: "ES256", kid: keyID };
  const claims = { iss: teamID, iat: Math.floor(Date.now() / 1000) };
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

  return `${signingInput}.${base64URL(signature)}`;
}

function apnsHost(): string {
  return Deno.env.get("APNS_ENV") === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
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

  const authHeader = req.headers.get("Authorization") ?? "";
  if (authHeader !== `Bearer ${serviceRoleKey}`) {
    return json(401, { error: "Unauthorized" });
  }

  let body: PushRequest;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body" });
  }

  if (!body.user_id || !body.title || !body.body) {
    return json(400, { error: "user_id, title and body are required" });
  }

  const kind = body.kind ?? "account_updates";
  const payloadData = body.data ?? {};
  const now = new Date().toISOString();
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: preference } = await supabase
    .from("notification_preferences")
    .select(
      "enabled, analysis_complete, report_ready, account_updates, marketing",
    )
    .eq("user_id", body.user_id)
    .maybeSingle();

  const preferenceKey = kind.replaceAll("-", "_");
  const allowedByKind = preference
    ? preference[preferenceKey as keyof typeof preference] !== false
    : true;
  if (preference?.enabled === false || !allowedByKind) {
    const { data: event } = await supabase
      .from("notification_events")
      .insert({
        user_id: body.user_id,
        kind,
        title: body.title,
        body: body.body,
        data: payloadData,
        status: "skipped",
        last_error: "user_preference_disabled",
      })
      .select("id")
      .single();
    return json(200, { status: "skipped", event_id: event?.id ?? null });
  }

  const environment = Deno.env.get("APNS_ENV") === "production"
    ? "production"
    : "sandbox";
  const { data: tokens, error: tokenError } = await supabase
    .from("push_device_tokens")
    .select("id, token")
    .eq("user_id", body.user_id)
    .eq("environment", environment)
    .eq("notifications_enabled", true);

  if (tokenError) {
    return json(500, { error: "Failed to load device tokens" });
  }

  const deviceTokens = (tokens ?? []) as PushToken[];
  const { data: event, error: eventError } = await supabase
    .from("notification_events")
    .insert({
      user_id: body.user_id,
      kind,
      title: body.title,
      body: body.body,
      data: payloadData,
      status: deviceTokens.length > 0 ? "queued" : "skipped",
      last_error: deviceTokens.length > 0 ? null : "no_active_device_tokens",
    })
    .select("id")
    .single();

  if (eventError) {
    return json(500, { error: "Failed to create notification event" });
  }

  if (deviceTokens.length === 0) {
    return json(200, {
      status: "skipped",
      reason: "no_active_device_tokens",
      event_id: event.id,
    });
  }

  let providerToken: string;
  try {
    providerToken = await makeProviderToken();
  } catch (error) {
    await supabase
      .from("notification_events")
      .update({
        status: "failed",
        failure_count: deviceTokens.length,
        last_error: safeErrorText(error),
      })
      .eq("id", event.id);
    return json(500, {
      error: "APNs credentials are not configured",
      event_id: event.id,
    });
  }

  const topic = Deno.env.get("APNS_BUNDLE_ID") ?? "com.riskdetected.app";
  const apnsPayload = {
    aps: {
      alert: {
        title: body.title,
        body: body.body,
      },
      sound: "default",
    },
    data: payloadData,
    kind,
    event_id: event.id,
  };

  let sent = 0;
  let failed = 0;
  let lastError: string | null = null;

  for (const token of deviceTokens) {
    const response = await fetch(`${apnsHost()}/3/device/${token.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${providerToken}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "content-type": "application/json",
      },
      body: JSON.stringify(apnsPayload),
    });

    if (response.ok) {
      sent += 1;
      await supabase
        .from("push_device_tokens")
        .update({ last_success_at: now, last_failure_reason: null })
        .eq("id", token.id);
    } else {
      failed += 1;
      const errorText = await response.text();
      lastError = `${response.status}: ${safeErrorText(errorText)}`;
      await supabase
        .from("push_device_tokens")
        .update({ last_failure_at: now, last_failure_reason: lastError })
        .eq("id", token.id);
    }
  }

  await supabase
    .from("notification_events")
    .update({
      status: sent > 0 ? "sent" : "failed",
      sent_count: sent,
      failure_count: failed,
      last_error: lastError,
      sent_at: sent > 0 ? now : null,
    })
    .eq("id", event.id);

  return json(200, {
    status: sent > 0 ? "sent" : "failed",
    event_id: event.id,
    sent,
    failed,
  });
});
