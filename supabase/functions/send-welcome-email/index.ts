import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildWelcomeEmailContent } from "./template.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPPORT_EMAIL = "info@riskdetected.com";

type ProfileRow = {
  id: string;
  email: string | null;
  full_name: string | null;
  welcome_email_sent_at: string | null;
  welcome_email_status: string | null;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function cleanText(value: unknown, maxLength: number): string {
  return String(value ?? "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim()
    .slice(0, maxLength);
}

function safeLogText(value: unknown, maxLength = 220): string {
  return cleanText(value, maxLength)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[email]");
}

function displayName(profile: ProfileRow, fallbackEmail?: string | null) {
  const fullName = cleanText(profile.full_name, 120);
  if (fullName) return fullName;
  const email = cleanText(profile.email, 240) || cleanText(fallbackEmail, 240);
  return email.includes("@") ? email.split("@")[0] : "";
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendAPIKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ??
    "RiskDetected <info@riskdetected.com>";
  const replyToEmail = Deno.env.get("RESEND_REPLY_TO_EMAIL") ??
    "info@riskdetected.com";

  if (!supabaseURL || !serviceRoleKey) {
    return json(500, { error: "welcome_mail_not_configured" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json(401, { error: "unauthorized" });
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: userResult, error: userError } = await supabase.auth.getUser(
    jwt,
  );
  const user = userResult?.user;
  if (userError || !user) {
    return json(401, { error: "unauthorized" });
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("id,email,full_name,welcome_email_sent_at,welcome_email_status")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError) {
    console.error(
      "welcome email profile read failed",
      JSON.stringify({
        user_id: user.id,
        error: safeLogText(profileError.message),
      }),
    );
    return json(500, { error: "profile_read_failed" });
  }

  if (!profile) {
    return json(404, { error: "profile_not_found" });
  }

  const profileRow = profile as ProfileRow;

  if (profileRow.welcome_email_sent_at) {
    return json(200, { ok: true, delivery_status: "already_sent" });
  }

  if (profileRow.welcome_email_status === "sending") {
    return json(200, { ok: true, delivery_status: "already_sending" });
  }

  const { data: lockedProfile, error: lockError } = await supabase
    .from("profiles")
    .update({
      welcome_email_status: "sending",
      welcome_email_error: null,
    })
    .eq("id", user.id)
    .is("welcome_email_sent_at", null)
    .or("welcome_email_status.is.null,welcome_email_status.neq.sending")
    .select("id,email,full_name,welcome_email_sent_at,welcome_email_status")
    .maybeSingle();

  if (lockError || !lockedProfile) {
    return json(200, { ok: true, delivery_status: "already_sending" });
  }

  const lockedProfileRow = lockedProfile as ProfileRow;
  const toEmail = cleanText(lockedProfileRow.email, 240) ||
    cleanText(user.email, 240);
  if (!toEmail.includes("@")) {
    await supabase
      .from("profiles")
      .update({
        welcome_email_status: "email_failed",
        welcome_email_error: "missing recipient email",
      })
      .eq("id", user.id);
    return json(200, { ok: true, delivery_status: "email_failed" });
  }

  const email = buildWelcomeEmailContent({
    displayName: displayName(lockedProfileRow, user.email),
    supportEmail: SUPPORT_EMAIL,
    currentYear: new Date().getUTCFullYear().toString(),
  });

  if (!resendAPIKey) {
    await supabase
      .from("profiles")
      .update({
        welcome_email_status: "email_failed",
        welcome_email_error: "RESEND_API_KEY missing",
      })
      .eq("id", user.id);
    return json(200, { ok: true, delivery_status: "email_failed" });
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendAPIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [toEmail],
      reply_to: replyToEmail,
      subject: email.subject,
      html: email.html,
      text: email.text,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    await supabase
      .from("profiles")
      .update({
        welcome_email_status: "email_failed",
        welcome_email_error: safeLogText(detail, 500),
      })
      .eq("id", user.id);

    console.error(
      "welcome email failed",
      JSON.stringify({
        user_id: user.id,
        http_status: response.status,
        detail: safeLogText(detail),
      }),
    );

    return json(200, { ok: true, delivery_status: "email_failed" });
  }

  await supabase
    .from("profiles")
    .update({
      welcome_email_sent_at: new Date().toISOString(),
      welcome_email_status: "sent",
      welcome_email_error: null,
    })
    .eq("id", user.id);

  return json(200, { ok: true, delivery_status: "sent" });
});
