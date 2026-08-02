import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import {
  AUTH_EMAIL_LOCALES,
  buildAuthEmail,
} from "../_shared/auth-email-localization.ts";

type HookPayload = {
  user?: {
    id?: string;
    email?: string;
    new_email?: string;
    user_metadata?: Record<string, unknown>;
  };
  email_data?: {
    token?: string;
    token_new?: string;
    email_action_type?: string;
  };
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function webhookHeaders(req: Request): Record<string, string> {
  return {
    "webhook-id": req.headers.get("webhook-id") ?? "",
    "webhook-timestamp": req.headers.get("webhook-timestamp") ?? "",
    "webhook-signature": req.headers.get("webhook-signature") ?? "",
  };
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

type DeliveryClaim = {
  status?: unknown;
  claimed?: unknown;
  lease_token?: unknown;
};

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const hookSecret = Deno.env.get("SEND_EMAIL_HOOK_SECRET");
  const resendAPIKey = Deno.env.get("RESEND_API_KEY");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (
    !hookSecret || !resendAPIKey || !supabaseURL || !serviceRoleKey
  ) {
    return json(500, { error: "auth_email_hook_not_configured" });
  }

  const rawBody = await req.text();
  let payload: HookPayload;
  try {
    const secret = hookSecret
      .replace(/^v1,whsec_/, "")
      .replace(/^whsec_/, "")
      .replace(/^v1,/, "");
    payload = new Webhook(secret).verify(
      rawBody,
      webhookHeaders(req),
    ) as HookPayload;
  } catch {
    return json(401, { error: "invalid_webhook_signature" });
  }
  const webhookID = req.headers.get("webhook-id")?.trim();
  if (!webhookID) {
    return json(422, { error: "auth_email_webhook_id_missing" });
  }
  const webhookIDHash = await sha256Hex(webhookID);
  const requestBodyHash = await sha256Hex(rawBody);

  const userID = payload.user?.id;
  const currentEmail = payload.user?.email;
  if (!userID || !currentEmail) {
    return json(422, { error: "auth_email_recipient_missing" });
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: profile } = await supabase
    .from("profiles")
    .select("app_language,preferred_content_locale")
    .eq("id", userID)
    .maybeSingle();
  const metadata = payload.user?.user_metadata ?? {};
  const resolvedLocale = profile?.preferred_content_locale ??
    metadata.content_locale ??
    metadata.preferred_content_locale;
  const resolvedAppLanguage = profile?.app_language ?? metadata.app_language;
  const isLegacyTurkishRequest = resolvedLocale == null &&
    resolvedAppLanguage == null;
  const locale = isLegacyTurkishRequest ? "tr-TR" : resolvedLocale;
  const appLanguage = isLegacyTurkishRequest ? "tr" : resolvedAppLanguage;
  if (
    typeof locale !== "string" ||
    !(AUTH_EMAIL_LOCALES as readonly string[]).includes(locale) ||
    (appLanguage !== "tr" && appLanguage !== "en") ||
    (locale === "tr-TR" ? "tr" : "en") !== appLanguage
  ) {
    return json(422, {
      error: "AUTH_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING",
    });
  }

  const action = payload.email_data?.email_action_type;
  const token = payload.email_data?.token;
  const tokenNew = payload.email_data?.token_new;
  const newEmail = payload.user?.new_email;
  const deliveries: Array<{ recipient: string; token: unknown }> =
    action === "email_change" && newEmail
      ? tokenNew
        ? [
          { recipient: currentEmail, token },
          { recipient: newEmail, token: tokenNew },
        ]
        : [{ recipient: newEmail, token }]
      : [{ recipient: currentEmail, token }];

  const renderedDeliveries = deliveries.map((delivery) => ({
    recipient: delivery.recipient,
    email: buildAuthEmail({
      locale,
      action,
      token: delivery.token,
    }),
  }));
  const renderFailure = renderedDeliveries.find((delivery) =>
    !delivery.email.ok
  );
  if (renderFailure && !renderFailure.email.ok) {
    return json(422, { error: renderFailure.email.code });
  }

  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ??
    "RiskDetected <info@riskdetected.com>";
  const replyToEmail = Deno.env.get("RESEND_REPLY_TO_EMAIL") ??
    "info@riskdetected.com";

  for (
    const [deliveryIndex, { recipient, email }] of renderedDeliveries.entries()
  ) {
    if (!email.ok) {
      return json(422, { error: email.code });
    }
    const { data: claimData, error: claimError } = await supabase.rpc(
      "claim_auth_email_delivery_v1",
      {
        p_webhook_id_sha256: webhookIDHash,
        p_delivery_index: deliveryIndex,
        p_request_body_sha256: requestBodyHash,
      },
    );
    if (claimError) {
      return json(503, { error: "auth_email_delivery_claim_failed" });
    }
    const claim = (claimData ?? {}) as DeliveryClaim;
    if (claim.status === "sent") continue;
    if (
      claim.status !== "claimed" ||
      claim.claimed !== true ||
      typeof claim.lease_token !== "string"
    ) {
      return json(503, { error: "auth_email_delivery_in_progress" });
    }

    const providerResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendAPIKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key":
          `riskdetected-auth/${webhookIDHash}/${deliveryIndex}`,
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [recipient],
        reply_to: replyToEmail,
        subject: email.subject,
        html: email.html,
        text: email.text,
      }),
    });
    if (!providerResponse.ok) {
      await supabase.rpc("release_auth_email_delivery_v1", {
        p_webhook_id_sha256: webhookIDHash,
        p_delivery_index: deliveryIndex,
        p_request_body_sha256: requestBodyHash,
        p_lease_token: claim.lease_token,
      });
      return json(502, { error: "auth_email_provider_failed" });
    }

    const providerPayload = await providerResponse.json().catch(() => ({})) as {
      id?: unknown;
    };
    const providerMessageID = typeof providerPayload.id === "string"
      ? providerPayload.id
      : "";
    const { data: completed, error: completionError } = await supabase.rpc(
      "complete_auth_email_delivery_v1",
      {
        p_webhook_id_sha256: webhookIDHash,
        p_delivery_index: deliveryIndex,
        p_request_body_sha256: requestBodyHash,
        p_lease_token: claim.lease_token,
        p_provider_message_id: providerMessageID,
      },
    );
    if (completionError || completed !== true) {
      return json(503, { error: "auth_email_delivery_completion_failed" });
    }
  }

  return json(200, {});
});
