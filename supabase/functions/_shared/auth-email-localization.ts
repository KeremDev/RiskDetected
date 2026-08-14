export const AUTH_EMAIL_LOCALES = [
  "tr-TR",
  "en-001",
  "en-GB",
  "en-US",
  "en-AU",
  "en-CA",
] as const;

export type AuthEmailLocale = typeof AUTH_EMAIL_LOCALES[number];

export const AUTH_EMAIL_ACTIONS = [
  "signup",
  "magiclink",
  "email",
  "recovery",
  "email_change",
  "reauthentication",
  "invite",
  "password_changed_notification",
  "email_changed_notification",
  "phone_changed_notification",
  "identity_linked_notification",
  "identity_unlinked_notification",
  "mfa_factor_enrolled_notification",
  "mfa_factor_unenrolled_notification",
] as const;

export type AuthEmailAction = typeof AUTH_EMAIL_ACTIONS[number];

const AUTH_EMAIL_TOKEN_ACTIONS = new Set<AuthEmailAction>([
  "signup",
  "magiclink",
  "email",
  "recovery",
  "email_change",
  "reauthentication",
  "invite",
]);

type AuthEmailCopy = {
  subject: string;
  heading: string;
  instruction: string;
  expiry: string;
};

const TURKISH_COPY: Record<AuthEmailAction, AuthEmailCopy> = {
  signup: {
    subject: "RiskDetected e-posta doğrulama kodu",
    heading: "E-posta doğrulama kodun",
    instruction:
      "RiskDetected hesabını doğrulamak için bu kodu uygulamaya gir.",
    expiry: "Bu işlemi sen başlatmadıysan bu e-postayı yok sayabilirsin.",
  },
  magiclink: {
    subject: "RiskDetected giriş kodu",
    heading: "Giriş kodun",
    instruction:
      "RiskDetected hesabına giriş yapmak için bu kodu uygulamaya gir.",
    expiry: "Bu işlemi sen başlatmadıysan bu e-postayı yok sayabilirsin.",
  },
  email: {
    subject: "RiskDetected giriş kodu",
    heading: "Giriş kodun",
    instruction:
      "RiskDetected hesabına giriş yapmak için bu kodu uygulamaya gir.",
    expiry: "Bu işlemi sen başlatmadıysan bu e-postayı yok sayabilirsin.",
  },
  recovery: {
    subject: "RiskDetected hesap kurtarma kodu",
    heading: "Hesap kurtarma kodun",
    instruction: "Hesap kurtarma işlemini tamamlamak için bu kodu kullan.",
    expiry: "Bu işlemi sen başlatmadıysan bu e-postayı yok sayabilirsin.",
  },
  email_change: {
    subject: "RiskDetected e-posta değişikliği kodu",
    heading: "E-posta değişikliği kodun",
    instruction: "E-posta değişikliğini onaylamak için bu kodu kullan.",
    expiry: "Bu değişikliği sen istemediysen destek ekibimize ulaş.",
  },
  reauthentication: {
    subject: "RiskDetected güvenlik doğrulama kodu",
    heading: "Güvenlik doğrulama kodun",
    instruction: "Hassas işlemi tamamlamak için bu kodu kullan.",
    expiry: "Bu işlemi sen başlatmadıysan bu e-postayı yok sayabilirsin.",
  },
  invite: {
    subject: "RiskDetected davetin",
    heading: "Davet kodun",
    instruction: "RiskDetected davetini kabul etmek için bu kodu kullan.",
    expiry: "Bu daveti beklemiyorsan bu e-postayı yok sayabilirsin.",
  },
  password_changed_notification: {
    subject: "RiskDetected şifren değiştirildi",
    heading: "Şifren değiştirildi",
    instruction: "RiskDetected hesabının şifresi başarıyla değiştirildi.",
    expiry:
      "Bu değişikliği sen yapmadıysan hemen destek ekibimizle iletişime geç.",
  },
  email_changed_notification: {
    subject: "RiskDetected e-posta adresin değiştirildi",
    heading: "E-posta adresin değiştirildi",
    instruction:
      "RiskDetected hesabına bağlı e-posta adresi başarıyla değiştirildi.",
    expiry:
      "Bu değişikliği sen yapmadıysan hemen destek ekibimizle iletişime geç.",
  },
  phone_changed_notification: {
    subject: "RiskDetected telefon numaran değiştirildi",
    heading: "Telefon numaran değiştirildi",
    instruction:
      "RiskDetected hesabına bağlı telefon numarası başarıyla değiştirildi.",
    expiry:
      "Bu değişikliği sen yapmadıysan hemen destek ekibimizle iletişime geç.",
  },
  identity_linked_notification: {
    subject: "RiskDetected hesabına yeni giriş yöntemi bağlandı",
    heading: "Yeni giriş yöntemi bağlandı",
    instruction:
      "RiskDetected hesabına yeni bir kimlik sağlayıcısı başarıyla bağlandı.",
    expiry: "Bu işlemi sen yapmadıysan hemen destek ekibimizle iletişime geç.",
  },
  identity_unlinked_notification: {
    subject: "RiskDetected hesabından bir giriş yöntemi kaldırıldı",
    heading: "Giriş yöntemi kaldırıldı",
    instruction:
      "RiskDetected hesabına bağlı bir kimlik sağlayıcısı kaldırıldı.",
    expiry: "Bu işlemi sen yapmadıysan hemen destek ekibimizle iletişime geç.",
  },
  mfa_factor_enrolled_notification: {
    subject: "RiskDetected hesabında çok faktörlü doğrulama etkinleştirildi",
    heading: "Çok faktörlü doğrulama etkinleştirildi",
    instruction:
      "RiskDetected hesabına yeni bir çok faktörlü doğrulama yöntemi eklendi.",
    expiry: "Bu işlemi sen yapmadıysan hemen destek ekibimizle iletişime geç.",
  },
  mfa_factor_unenrolled_notification: {
    subject: "RiskDetected hesabından çok faktörlü doğrulama kaldırıldı",
    heading: "Çok faktörlü doğrulama kaldırıldı",
    instruction:
      "RiskDetected hesabına bağlı bir çok faktörlü doğrulama yöntemi kaldırıldı.",
    expiry: "Bu işlemi sen yapmadıysan hemen destek ekibimizle iletişime geç.",
  },
};

const ENGLISH_COPY: Record<AuthEmailAction, AuthEmailCopy> = {
  signup: {
    subject: "RiskDetected email verification code",
    heading: "Your email verification code",
    instruction:
      "Enter this code in the app to verify your RiskDetected account.",
    expiry: "If you did not request this, you can ignore this email.",
  },
  magiclink: {
    subject: "RiskDetected sign-in code",
    heading: "Your sign-in code",
    instruction: "Enter this code in the app to sign in to RiskDetected.",
    expiry: "If you did not request this, you can ignore this email.",
  },
  email: {
    subject: "RiskDetected sign-in code",
    heading: "Your sign-in code",
    instruction: "Enter this code in the app to sign in to RiskDetected.",
    expiry: "If you did not request this, you can ignore this email.",
  },
  recovery: {
    subject: "RiskDetected account recovery code",
    heading: "Your account recovery code",
    instruction: "Use this code to complete account recovery.",
    expiry: "If you did not request this, you can ignore this email.",
  },
  email_change: {
    subject: "RiskDetected email change code",
    heading: "Your email change code",
    instruction: "Use this code to confirm the email change.",
    expiry: "If you did not request this change, contact support.",
  },
  reauthentication: {
    subject: "RiskDetected security verification code",
    heading: "Your security verification code",
    instruction: "Use this code to complete the sensitive action.",
    expiry: "If you did not request this, you can ignore this email.",
  },
  invite: {
    subject: "Your RiskDetected invitation",
    heading: "Your invitation code",
    instruction: "Use this code to accept your RiskDetected invitation.",
    expiry: "If you were not expecting this invitation, ignore this email.",
  },
  password_changed_notification: {
    subject: "Your RiskDetected password was changed",
    heading: "Your password was changed",
    instruction:
      "The password for your RiskDetected account was changed successfully.",
    expiry:
      "If you did not make this change, contact our support team immediately.",
  },
  email_changed_notification: {
    subject: "Your RiskDetected email address was changed",
    heading: "Your email address was changed",
    instruction:
      "The email address linked to your RiskDetected account was changed successfully.",
    expiry:
      "If you did not make this change, contact our support team immediately.",
  },
  phone_changed_notification: {
    subject: "Your RiskDetected phone number was changed",
    heading: "Your phone number was changed",
    instruction:
      "The phone number linked to your RiskDetected account was changed successfully.",
    expiry:
      "If you did not make this change, contact our support team immediately.",
  },
  identity_linked_notification: {
    subject: "A new sign-in method was linked to RiskDetected",
    heading: "A new sign-in method was linked",
    instruction:
      "A new identity provider was linked to your RiskDetected account.",
    expiry:
      "If you did not make this change, contact our support team immediately.",
  },
  identity_unlinked_notification: {
    subject: "A sign-in method was removed from RiskDetected",
    heading: "A sign-in method was removed",
    instruction:
      "An identity provider was removed from your RiskDetected account.",
    expiry:
      "If you did not make this change, contact our support team immediately.",
  },
  mfa_factor_enrolled_notification: {
    subject: "Multi-factor authentication was enabled on RiskDetected",
    heading: "Multi-factor authentication was enabled",
    instruction:
      "A new multi-factor authentication method was added to your RiskDetected account.",
    expiry:
      "If you did not make this change, contact our support team immediately.",
  },
  mfa_factor_unenrolled_notification: {
    subject: "Multi-factor authentication was removed from RiskDetected",
    heading: "Multi-factor authentication was removed",
    instruction:
      "A multi-factor authentication method was removed from your RiskDetected account.",
    expiry:
      "If you did not make this change, contact our support team immediately.",
  },
};

const CATALOG: Record<
  AuthEmailLocale,
  Record<AuthEmailAction, AuthEmailCopy>
> = {
  "tr-TR": TURKISH_COPY,
  "en-001": ENGLISH_COPY,
  "en-GB": ENGLISH_COPY,
  "en-US": ENGLISH_COPY,
  "en-AU": ENGLISH_COPY,
  "en-CA": ENGLISH_COPY,
};

function escapeHTML(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function isLocale(value: unknown): value is AuthEmailLocale {
  return typeof value === "string" &&
    (AUTH_EMAIL_LOCALES as readonly string[]).includes(value);
}

function isAction(value: unknown): value is AuthEmailAction {
  return typeof value === "string" &&
    (AUTH_EMAIL_ACTIONS as readonly string[]).includes(value);
}

export function buildAuthEmail(params: {
  locale: unknown;
  action: unknown;
  token: unknown;
}):
  | { ok: true; subject: string; html: string; text: string }
  | {
    ok: false;
    code:
      | "AUTH_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING"
      | "AUTH_EMAIL_ACTION_UNSUPPORTED"
      | "AUTH_EMAIL_TOKEN_MISSING";
  } {
  if (!isLocale(params.locale)) {
    return {
      ok: false,
      code: "AUTH_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING",
    };
  }
  if (!isAction(params.action)) {
    return { ok: false, code: "AUTH_EMAIL_ACTION_UNSUPPORTED" };
  }
  const tokenRequired = AUTH_EMAIL_TOKEN_ACTIONS.has(params.action);
  if (
    tokenRequired &&
    (typeof params.token !== "string" || !params.token.trim())
  ) {
    return { ok: false, code: "AUTH_EMAIL_TOKEN_MISSING" };
  }

  const token = tokenRequired
    ? (params.token as string).trim().slice(0, 32)
    : null;
  const copy = CATALOG[params.locale][params.action];
  const language = params.locale === "tr-TR" ? "tr" : "en";
  const codeHTML = token
    ? `<div style="font-size:36px;letter-spacing:10px;font-weight:800;color:#00b82e;background:#eaf8ee;border-radius:14px;padding:18px 20px;text-align:center;">${
      escapeHTML(token)
    }</div>`
    : "";
  const html = `<!doctype html>
<html lang="${language}">
<body style="margin:0;background:#f6f7f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#0b0d0e;">
  <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="padding:28px 16px;">
    <tr><td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:520px;background:#ffffff;border-radius:18px;padding:28px;border:1px solid #dde3e0;">
        <tr><td>
          <h1 style="margin:0 0 24px;font-size:26px;">RiskDetected</h1>
          <h2 style="margin:0 0 12px;font-size:20px;">${
    escapeHTML(copy.heading)
  }</h2>
          <p style="font-size:15px;line-height:1.5;">${
    escapeHTML(copy.instruction)
  }</p>
          ${codeHTML}
          <p style="margin:22px 0 0;font-size:13px;color:#6b7280;">${
    escapeHTML(copy.expiry)
  }</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
  return {
    ok: true,
    subject: copy.subject,
    html,
    text: [copy.heading, copy.instruction, token, copy.expiry]
      .filter((part): part is string => Boolean(part))
      .join("\n\n"),
  };
}
