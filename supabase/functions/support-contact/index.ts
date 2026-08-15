import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  type NormalizedSupportAttachment,
  normalizeSupportAttachments,
  type SupportAttachmentInput,
} from "../_shared/support-attachment-validation.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SupportRequestBody = {
  subject?: string;
  message?: string;
  attachments?: SupportAttachmentInput[];
  app_language?: string;
  content_locale?: string;
  user_message_language?: string;
  preferred_response_language?: string;
};

type SupportRateLimitResult = {
  ok?: boolean;
  code?: string;
  retry_after_seconds?: number;
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

function escapeHTML(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function newSupportID(): string {
  return `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function safeLogText(value: string, maxLength = 180): string {
  return value
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[email]")
    .slice(0, maxLength);
}

function verifiedTierFromSubscription(
  subscription: Record<string, unknown> | null,
): string {
  const tier = cleanText(subscription?.tier, 40);
  const status = cleanText(subscription?.status, 40);
  const periodEndsAt = cleanText(subscription?.current_period_ends_at, 80);
  const activeStatus = ["active", "trialing", "grace_period"].includes(status);
  const activePeriod = !periodEndsAt || Date.parse(periodEndsAt) > Date.now();
  if ((tier === "plus" || tier === "pro") && activeStatus && activePeriod) {
    return tier;
  }
  return "free";
}

function attachmentMetadata(attachments: NormalizedSupportAttachment[]) {
  return attachments.map((attachment) => ({
    filename: attachment.filename,
    mime_type: attachment.mime_type,
    size_bytes: attachment.size_bytes ?? 0,
  }));
}

async function saveSupportRequest(
  supabase: { from: (table: string) => any },
  values: {
    userID: string;
    supportID: string;
    subject: string;
    message: string;
    senderName: string;
    senderEmail: string;
    senderPhone: string;
    senderTier: string;
    companyName: string;
    senderTitle: string;
    appLanguage: "tr" | "en";
    contentLocale: string;
    userMessageLanguage: "tr" | "en" | "und";
    preferredResponseLanguage: "tr" | "en";
    attachments: NormalizedSupportAttachment[];
    deliveryStatus: "sent" | "stored" | "email_failed";
    deliveryError?: string;
  },
): Promise<boolean> {
  const { error } = await supabase.from("support_requests").insert({
    user_id: values.userID,
    support_id: values.supportID,
    subject: values.subject,
    message: values.message,
    sender_name: values.senderName,
    sender_email: values.senderEmail,
    sender_phone: values.senderPhone,
    tier: values.senderTier,
    company_name: values.companyName,
    title: values.senderTitle,
    app_language: values.appLanguage,
    content_locale: values.contentLocale,
    user_message_language: values.userMessageLanguage,
    preferred_response_language: values.preferredResponseLanguage,
    attachment_count: values.attachments.length,
    attachments: attachmentMetadata(values.attachments),
    delivery_status: values.deliveryStatus,
    delivery_error: values.deliveryError,
  });

  if (error) {
    console.error(
      "support request save failed",
      JSON.stringify({
        support_id: values.supportID,
        error: safeLogText(error.message),
      }),
    );
    return false;
  }

  return true;
}

const SUPPORTED_CONTENT_LOCALES = new Set([
  "tr-TR",
  "en-001",
  "en-GB",
  "en-US",
  "en-AU",
  "en-CA",
]);

function supportAcknowledgement(
  language: "tr" | "en",
  supportID: string,
  deliveryStatus: "sent" | "stored" | "email_failed",
): string {
  if (language === "en") {
    return deliveryStatus === "sent"
      ? `Your support request was sent. Support ID: ${supportID}`
      : `Your support request was saved. Support ID: ${supportID}`;
  }
  return deliveryStatus === "sent"
    ? `Destek talebin gönderildi. Destek kodu: ${supportID}`
    : `Destek talebin kaydedildi. Destek kodu: ${supportID}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const supportID = newSupportID();
  const resendAPIKey = Deno.env.get("RESEND_API_KEY");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const toEmail = Deno.env.get("SUPPORT_TO_EMAIL") ?? "info@riskdetected.com";
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ??
    "RiskDetected Destek <info@riskdetected.com>";

  if (!supabaseURL || !serviceRoleKey) {
    return json(500, {
      error: "support_mail_not_configured",
      message: "Destek mail servisi yapılandırılmamış.",
      support_id: supportID,
    });
  }

  let body: SupportRequestBody;
  try {
    body = await req.json();
  } catch {
    return json(400, {
      error: "invalid_json",
      message: "Form verisi okunamadı.",
      support_id: supportID,
    });
  }

  const subject = cleanText(body.subject, 120);
  const message = cleanText(body.message, 5000);
  const appLanguage = cleanText(body.app_language, 8);
  const contentLocale = cleanText(body.content_locale, 16);
  const userMessageLanguage = cleanText(body.user_message_language, 8);
  const preferredResponseLanguage = cleanText(
    body.preferred_response_language,
    8,
  );
  const localeLanguage = contentLocale === "tr-TR"
    ? "tr"
    : contentLocale.startsWith("en-")
    ? "en"
    : null;
  if (
    !["tr", "en"].includes(appLanguage) ||
    !SUPPORTED_CONTENT_LOCALES.has(contentLocale) ||
    localeLanguage !== appLanguage ||
    !["tr", "en", "und"].includes(userMessageLanguage) ||
    !["tr", "en"].includes(preferredResponseLanguage)
  ) {
    return json(422, {
      error: "support_language_context_invalid",
      message: appLanguage === "en"
        ? "The support language context is invalid."
        : "Destek dili bilgisi geçersiz.",
      support_id: supportID,
    });
  }
  const attachmentResult = normalizeSupportAttachments(
    body.attachments,
    appLanguage,
  );
  if (attachmentResult.error) {
    return json(400, {
      error: attachmentResult.error.code,
      message: attachmentResult.error.message,
      support_id: supportID,
    });
  }
  const attachments = attachmentResult.attachments;

  if (subject.length < 3 || message.length < 10) {
    return json(400, {
      error: "validation_failed",
      message: "Konu ve mesaj alanlarını doldur.",
      support_id: supportID,
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json(401, {
      error: "unauthorized",
      message: "Destek talebi için oturum gerekli.",
      support_id: supportID,
    });
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: userResult, error: userError } = await supabase.auth.getUser(
    jwt,
  );
  const user = userResult?.user;
  if (userError || !user) {
    return json(401, {
      error: "unauthorized",
      message: "Oturum doğrulanamadı.",
      support_id: supportID,
    });
  }

  const { data: rateLimit, error: rateLimitError } = await supabase.rpc(
    "check_support_request_rate_limit",
    {
      p_user_id: user.id,
      p_hour_limit: 5,
      p_day_limit: 20,
    },
  );
  if (rateLimitError) {
    console.error(
      "support rate limit check failed",
      JSON.stringify({
        support_id: supportID,
        error: safeLogText(rateLimitError.message),
      }),
    );
    return json(500, {
      error: "support_rate_check_failed",
      message: "Destek talebi limiti kontrol edilemedi.",
      support_id: supportID,
    });
  }

  const rateLimitResult = rateLimit as SupportRateLimitResult | null;
  if (rateLimitResult?.ok !== true) {
    const retryAfter = Math.max(
      60,
      Number(rateLimitResult?.retry_after_seconds ?? 3600),
    );
    return json(429, {
      error: "support_rate_limited",
      code: rateLimitResult?.code ?? "support_rate_limited",
      message:
        "Kısa sürede çok fazla destek talebi gönderdin. Lütfen biraz sonra tekrar dene.",
      support_id: supportID,
      retry_after_seconds: retryAfter,
    });
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select(
      "full_name,email,phone,tier,company_name,title,app_language,preferred_content_locale",
    )
    .eq("id", user.id)
    .maybeSingle();

  const { data: subscription } = await supabase
    .from("user_subscriptions")
    .select("tier,status,current_period_ends_at")
    .eq("user_id", user.id)
    .maybeSingle();

  const authEmail = cleanText(user.email, 240);
  const profileEmail = cleanText(profile?.email, 240);
  const senderName = cleanText(profile?.full_name, 160) || "Kayıtlı değil";
  const senderEmail = authEmail || profileEmail ||
    "Kayıtlı değil";
  const senderPhone = cleanText(profile?.phone, 80) || "Kayıtlı değil";
  const senderTier = verifiedTierFromSubscription(
    subscription as Record<string, unknown> | null,
  );
  const companyName = cleanText(profile?.company_name, 160) || "Kayıtlı değil";
  const senderTitle = cleanText(profile?.title, 120) || "Kayıtlı değil";
  const replyToEmail = authEmail.includes("@") ? authEmail : undefined;
  if (
    profile?.app_language !== appLanguage ||
    profile?.preferred_content_locale !== contentLocale
  ) {
    return json(422, {
      error: "support_language_context_mismatch",
      message: appLanguage === "en"
        ? "The support language does not match your profile."
        : "Destek dili profilinle eşleşmiyor.",
      support_id: supportID,
    });
  }
  const languageFields = {
    appLanguage: appLanguage as "tr" | "en",
    contentLocale,
    userMessageLanguage: userMessageLanguage as "tr" | "en" | "und",
    preferredResponseLanguage: preferredResponseLanguage as "tr" | "en",
  };

  const escapedMessage = escapeHTML(message).replace(/\n/g, "<br>");
  const html = `
    <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#101415;line-height:1.5">
      <h2 style="margin:0 0 12px">RiskDetected destek talebi</h2>
      <p style="margin:0 0 16px;color:#667085">Destek kodu: <strong>${supportID}</strong></p>
      <table style="border-collapse:collapse;margin-bottom:18px">
        <tr><td style="padding:6px 12px 6px 0;color:#667085">Ad soyad</td><td style="padding:6px 0"><strong>${
    escapeHTML(senderName)
  }</strong></td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#667085">E-posta</td><td style="padding:6px 0">${
    escapeHTML(senderEmail)
  }</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#667085">Telefon</td><td style="padding:6px 0">${
    escapeHTML(senderPhone)
  }</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#667085">Plan</td><td style="padding:6px 0">${
    escapeHTML(senderTier)
  }</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#667085">Firma</td><td style="padding:6px 0">${
    escapeHTML(companyName)
  }</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#667085">Ünvan</td><td style="padding:6px 0">${
    escapeHTML(senderTitle)
  }</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#667085">Uygulama dili / locale</td><td style="padding:6px 0">${
    escapeHTML(`${appLanguage} / ${contentLocale}`)
  }</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#667085">Kullanıcı mesaj dili</td><td style="padding:6px 0">${
    escapeHTML(userMessageLanguage)
  }</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#667085">Tercih edilen yanıt dili</td><td style="padding:6px 0"><strong>${
    escapeHTML(preferredResponseLanguage)
  }</strong></td></tr>
      </table>
      <h3 style="margin:0 0 8px">${escapeHTML(subject)}</h3>
      <div style="padding:14px;border:1px solid #E3E7E3;border-radius:12px;background:#F6F7F6">${escapedMessage}</div>
    </div>
  `;

  const text = [
    "RiskDetected destek talebi",
    `Destek kodu: ${supportID}`,
    `Ad soyad: ${senderName}`,
    `E-posta: ${senderEmail}`,
    `Telefon: ${senderPhone}`,
    `Plan: ${senderTier}`,
    `Firma: ${companyName}`,
    `Ünvan: ${senderTitle}`,
    `Uygulama dili / locale: ${appLanguage} / ${contentLocale}`,
    `Kullanıcı mesaj dili: ${userMessageLanguage}`,
    `Tercih edilen yanıt dili: ${preferredResponseLanguage}`,
    "",
    `Konu: ${subject}`,
    "",
    message,
  ].join("\n");

  if (!resendAPIKey) {
    const saved = await saveSupportRequest(supabase, {
      userID: user.id,
      supportID,
      subject,
      message,
      senderName,
      senderEmail,
      senderPhone,
      senderTier,
      companyName,
      senderTitle,
      ...languageFields,
      attachments,
      deliveryStatus: "stored",
      deliveryError: "RESEND_API_KEY missing",
    });

    if (!saved) {
      return json(500, {
        error: "support_request_save_failed",
        message: "Destek talebi kaydedilemedi.",
        support_id: supportID,
      });
    }

    return json(200, {
      ok: true,
      support_id: supportID,
      delivery_status: "stored",
      acknowledgement: supportAcknowledgement(
        languageFields.appLanguage,
        supportID,
        "stored",
      ),
    });
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
      subject: `[RiskDetected Destek] ${subject}`,
      html,
      text,
      attachments: attachments.map((attachment) => ({
        filename: attachment.filename,
        content: attachment.data,
        content_type: attachment.mime_type,
      })),
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    const saved = await saveSupportRequest(supabase, {
      userID: user.id,
      supportID,
      subject,
      message,
      senderName,
      senderEmail,
      senderPhone,
      senderTier,
      companyName,
      senderTitle,
      ...languageFields,
      attachments,
      deliveryStatus: "email_failed",
      deliveryError: safeLogText(detail),
    });

    console.error(
      "support email failed",
      JSON.stringify({
        support_id: supportID,
        http_status: response.status,
        detail: safeLogText(detail),
        saved,
      }),
    );

    if (saved) {
      return json(200, {
        ok: true,
        support_id: supportID,
        delivery_status: "email_failed",
        acknowledgement: supportAcknowledgement(
          languageFields.appLanguage,
          supportID,
          "email_failed",
        ),
      });
    }

    return json(502, {
      error: "email_failed",
      message: "Destek talebi mail olarak gönderilemedi.",
      support_id: supportID,
    });
  }

  await saveSupportRequest(supabase, {
    userID: user.id,
    supportID,
    subject,
    message,
    senderName,
    senderEmail,
    senderPhone,
    senderTier,
    companyName,
    senderTitle,
    ...languageFields,
    attachments,
    deliveryStatus: "sent",
  });

  return json(200, {
    ok: true,
    support_id: supportID,
    delivery_status: "sent",
    acknowledgement: supportAcknowledgement(
      languageFields.appLanguage,
      supportID,
      "sent",
    ),
  });
});
