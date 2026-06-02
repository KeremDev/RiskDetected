import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SupportAttachment = {
  filename?: string;
  mime_type?: string;
  data?: string;
  size_bytes?: number;
};

type SupportRequestBody = {
  subject?: string;
  message?: string;
  attachments?: SupportAttachment[];
};

type NormalizedAttachment = {
  filename: string;
  mime_type: string;
  data: string;
  size_bytes: number;
};

type SupportRateLimitResult = {
  ok?: boolean;
  code?: string;
  retry_after_seconds?: number;
};

const MAX_ATTACHMENT_COUNT = 3;
const MAX_ATTACHMENT_BYTES = 5_000_000;
const MAX_ATTACHMENT_TOTAL_BYTES = 15_000_000;

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

function decodedBase64ByteLength(base64: string): number {
  const normalized = base64.replace(/\s/g, "");
  const padding = normalized.endsWith("==")
    ? 2
    : normalized.endsWith("=")
    ? 1
    : 0;
  return Math.max(0, Math.floor((normalized.length * 3) / 4) - padding);
}

function isValidStandardBase64(value: string): boolean {
  const normalized = value.replace(/\s/g, "");
  return normalized.length > 0 &&
    normalized.length % 4 !== 1 &&
    /^[A-Za-z0-9+/]*={0,2}$/.test(normalized);
}

function normalizeAttachments(value: unknown): {
  attachments: NormalizedAttachment[];
  error?: { code: string; message: string };
} {
  if (value === undefined || value === null) return { attachments: [] };
  if (!Array.isArray(value)) {
    return {
      attachments: [],
      error: {
        code: "invalid_attachments",
        message: "Ek dosya verisi geçersiz.",
      },
    };
  }
  if (value.length > MAX_ATTACHMENT_COUNT) {
    return {
      attachments: [],
      error: {
        code: "too_many_attachments",
        message: `En fazla ${MAX_ATTACHMENT_COUNT} ek dosya gönderebilirsin.`,
      },
    };
  }

  let totalBytes = 0;
  const attachments: NormalizedAttachment[] = [];
  for (const item of value) {
    const source = item as SupportAttachment;
    const data = typeof source?.data === "string"
      ? source.data.replace(/\s/g, "")
      : "";
    if (!isValidStandardBase64(data)) {
      return {
        attachments: [],
        error: {
          code: "invalid_attachment_data",
          message: "Ek dosya verisi geçersiz.",
        },
      };
    }

    const decodedBytes = decodedBase64ByteLength(data);
    if (decodedBytes > MAX_ATTACHMENT_BYTES) {
      return {
        attachments: [],
        error: {
          code: "attachment_too_large",
          message: "Ek dosya 5 MB'dan küçük olmalı.",
        },
      };
    }

    totalBytes += decodedBytes;
    if (totalBytes > MAX_ATTACHMENT_TOTAL_BYTES) {
      return {
        attachments: [],
        error: {
          code: "attachments_too_large",
          message: "Ek dosyaların toplam boyutu çok büyük.",
        },
      };
    }

    attachments.push({
      filename: cleanText(source.filename, 120) || "ek-dosya",
      mime_type: cleanText(source.mime_type, 80) ||
        "application/octet-stream",
      data,
      size_bytes: decodedBytes,
    });
  }

  return { attachments };
}

function attachmentMetadata(attachments: NormalizedAttachment[]) {
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
    attachments: NormalizedAttachment[];
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
  const attachmentResult = normalizeAttachments(body.attachments);
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
    .select("full_name,email,phone,tier,company_name,title")
    .eq("id", user.id)
    .maybeSingle();

  const senderName = cleanText(profile?.full_name, 160) || "Kayıtlı değil";
  const senderEmail = cleanText(profile?.email, 240) || user.email ||
    "Kayıtlı değil";
  const senderPhone = cleanText(profile?.phone, 80) || "Kayıtlı değil";
  const senderTier = cleanText(profile?.tier, 40) || "free";
  const companyName = cleanText(profile?.company_name, 160) || "Kayıtlı değil";
  const senderTitle = cleanText(profile?.title, 120) || "Kayıtlı değil";

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
      reply_to: senderEmail.includes("@") ? senderEmail : undefined,
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
    attachments,
    deliveryStatus: "sent",
  });

  return json(200, {
    ok: true,
    support_id: supportID,
    delivery_status: "sent",
  });
});
