export type WelcomeEmailContent = {
  subject: string;
  html: string;
  text: string;
};

type TemplateInput = {
  displayName: string;
  supportEmail: string;
  currentYear: string;
  locale?: WelcomeEmailLocale;
};

export const WELCOME_EMAIL_LOCALES = [
  "tr-TR",
  "en-001",
  "en-GB",
  "en-US",
  "en-AU",
  "en-CA",
] as const;

export type WelcomeEmailLocale = typeof WELCOME_EMAIL_LOCALES[number];

const TURKISH_SUBJECT = "RiskDetected’a hoş geldiniz";

const HTML_TEMPLATE = `<!DOCTYPE html>
<html lang="tr" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <meta name="x-apple-disable-message-reformatting">
  <meta name="color-scheme" content="light dark">
  <meta name="supported-color-schemes" content="light dark">
  <title>RiskDetected'a hoş geldiniz</title>
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
  <style>
    body, table, td, a { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
    table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
    img { -ms-interpolation-mode: bicubic; border: 0; height: auto; line-height: 100%; outline: none; text-decoration: none; }
    body { margin: 0 !important; padding: 0 !important; width: 100% !important; }

    @media screen and (max-width: 600px) {
      .container { width: 100% !important; }
      .px { padding-left: 24px !important; padding-right: 24px !important; }
      .cta-btn { display: block !important; width: 100% !important; box-sizing: border-box; }
      .h1 { font-size: 24px !important; line-height: 32px !important; }
    }
  </style>
</head>
<body style="margin:0; padding:0; background-color:#0B1220; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none; font-size:1px; color:#0B1220; line-height:1px; max-height:0; max-width:0; opacity:0; overflow:hidden;">
    Hesabınız hazır. İlk İSG risk analizinizi saniyeler içinde başlatın.
    &nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;
  </div>

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#0B1220;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" class="container" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px; max-width:600px; background-color:#111A2E; border-radius:16px; overflow:hidden; border:1px solid #1E2A45;">
          <tr>
            <td style="height:4px; background-color:#22C55E; font-size:0; line-height:0;">&nbsp;</td>
          </tr>

          <tr>
            <td class="px" style="padding:36px 48px 8px 48px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="font-size:20px; font-weight:700; color:#FFFFFF; letter-spacing:-0.3px;">
                    Risk<span style="color:#22C55E;">Detected</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td class="px" style="padding:20px 48px 0 48px;">
              <h1 class="h1" style="margin:0; font-size:28px; line-height:36px; font-weight:700; color:#FFFFFF; letter-spacing:-0.5px;">
                Hoş geldiniz, {{display_name}}
              </h1>
            </td>
          </tr>

          <tr>
            <td class="px" style="padding:16px 48px 0 48px;">
              <p style="margin:0; font-size:16px; line-height:26px; color:#AEB9D0;">
                RiskDetected hesabınız hazır. Artık saha fotoğraflarını veya kısa açıklamaları analiz ederek İSG risklerini saniyeler içinde tespit edebilir, tehlikeleri risk analiz raporuna dönüştürebilir ve denetim arşivinizi tek yerden yönetebilirsiniz.
              </p>
            </td>
          </tr>

          <tr>
            <td class="px" style="padding:32px 48px 8px 48px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td align="left">
                    <!--[if mso]>
                    <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="https://riskdetected.com/app" style="height:52px;v-text-anchor:middle;width:280px;" arcsize="25%" stroke="f" fillcolor="#16A34A">
                      <w:anchorlock/>
                      <center style="color:#ffffff;font-family:sans-serif;font-size:16px;font-weight:bold;">İlk analizi başlat</center>
                    </v:roundrect>
                    <![endif]-->
                    <!--[if !mso]><!-- -->
                    <a class="cta-btn" href="https://riskdetected.com/app"
                       style="background-color:#16A34A; color:#FFFFFF; display:inline-block; font-size:16px; font-weight:700; line-height:52px; text-align:center; text-decoration:none; width:280px; border-radius:12px; -webkit-text-size-adjust:none;">
                      İlk analizi başlat
                    </a>
                    <!--<![endif]-->
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td class="px" style="padding:8px 48px 0 48px;">
              <p style="margin:0; font-size:14px; line-height:22px; color:#7C89A6;">
                Fotoğrafınız yoksa kısa bir açıklama yazarak da değerlendirme başlatabilirsiniz.
              </p>
            </td>
          </tr>

          <tr>
            <td class="px" style="padding:32px 48px 0 48px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr><td style="height:1px; background-color:#1E2A45; font-size:0; line-height:0;">&nbsp;</td></tr>
              </table>
            </td>
          </tr>

          <tr>
            <td class="px" style="padding:24px 48px 8px 48px;">
              <p style="margin:0; font-size:14px; line-height:22px; color:#AEB9D0;">
                Sorularınız için:
                <a href="{{support_mailto}}" style="color:#22C55E; text-decoration:none; font-weight:600;">{{support_email}}</a>
              </p>
            </td>
          </tr>

          <tr>
            <td class="px" style="padding:8px 48px 36px 48px;">
              <p style="margin:0; font-size:15px; line-height:24px; color:#FFFFFF;">
                Güvenli çalışmalar,<br>
                <strong style="color:#FFFFFF;">RiskDetected Ekibi</strong>
              </p>
            </td>
          </tr>
        </table>

        <table role="presentation" class="container" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px; max-width:600px;">
          <tr>
            <td class="px" style="padding:24px 48px;">
              <p style="margin:0; font-size:12px; line-height:18px; color:#5A6680; text-align:center;">
                Bu e-posta RiskDetected hesabınız oluşturulduğu için gönderildi.<br>
                RiskDetected · Ankara, Türkiye<br>
                &copy; {{current_year}} RiskDetected
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

const TEXT_TEMPLATE = `Merhaba {{display_name}},

RiskDetected hesabınız hazır.

Artık saha fotoğraflarını veya kısa açıklamaları analiz ederek İSG risklerini saniyeler içinde tespit edebilir, tehlikeleri risk analiz raporuna dönüştürebilir ve denetim arşivinizi tek yerden yönetebilirsiniz.

İlk analizi başlatmak için uygulamayı açabilirsiniz:
https://riskdetected.com/app

Fotoğrafınız yoksa kısa bir açıklama yazarak da değerlendirme başlatabilirsiniz.

Sorularınız için: {{support_email}}

Güvenli çalışmalar,
RiskDetected Ekibi

Bu e-posta RiskDetected hesabınız oluşturulduğu için gönderildi.
RiskDetected · Ankara, Türkiye
(c) {{current_year}} RiskDetected`;

const ENGLISH_HTML_TEMPLATE = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to RiskDetected</title>
</head>
<body style="margin:0;padding:0;background:#0B1220;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#FFFFFF;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
    <tr><td align="center" style="padding:32px 16px;">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;background:#111A2E;border:1px solid #1E2A45;border-radius:16px;">
        <tr><td style="height:4px;background:#22C55E;"></td></tr>
        <tr><td style="padding:36px 48px 8px;font-size:20px;font-weight:700;">Risk<span style="color:#22C55E;">Detected</span></td></tr>
        <tr><td style="padding:20px 48px 0;"><h1 style="margin:0;font-size:28px;line-height:36px;">Welcome, {{display_name}}</h1></td></tr>
        <tr><td style="padding:16px 48px 0;color:#AEB9D0;font-size:16px;line-height:26px;">
          Your RiskDetected account is ready. You can review site photos or short descriptions, identify visible safety findings and organise reports in one place.
        </td></tr>
        <tr><td style="padding:28px 48px 0;">
          <a href="https://riskdetected.com/app" style="display:inline-block;background:#16A34A;color:#FFFFFF;text-decoration:none;font-weight:700;padding:16px 24px;border-radius:12px;">Start your first analysis</a>
        </td></tr>
        <tr><td style="padding:24px 48px 8px;color:#AEB9D0;font-size:14px;line-height:22px;">
          Questions? <a href="{{support_mailto}}" style="color:#22C55E;">{{support_email}}</a>
        </td></tr>
        <tr><td style="padding:8px 48px 36px;font-size:15px;line-height:24px;">Work safely,<br><strong>The RiskDetected team</strong></td></tr>
      </table>
      <p style="font-size:12px;line-height:18px;color:#5A6680;text-align:center;">
        This email was sent because your RiskDetected account was created.<br>
        &copy; {{current_year}} RiskDetected
      </p>
    </td></tr>
  </table>
</body>
</html>`;

const ENGLISH_TEXT_TEMPLATE = `Hello {{display_name}},

Your RiskDetected account is ready.

You can review site photos or short descriptions, identify visible safety findings and organise reports in one place.

Start your first analysis:
https://riskdetected.com/app

Questions? {{support_email}}

Work safely,
The RiskDetected team

This email was sent because your RiskDetected account was created.
(c) {{current_year}} RiskDetected`;

function escapeHTML(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function escapePlain(value: string): string {
  return value.replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim();
}

function replaceTemplate(
  template: string,
  replacements: Record<string, string>,
): string {
  let output = template;
  for (const [key, value] of Object.entries(replacements)) {
    output = output.replaceAll(`{{${key}}}`, value);
  }
  const unresolved = output.match(/{{[^}]+}}/g);
  if (unresolved) {
    throw new Error(`welcome_template_unresolved:${unresolved.join(",")}`);
  }
  return output;
}

export function buildWelcomeEmailContent(
  input: TemplateInput,
): WelcomeEmailContent {
  const locale = input.locale ?? "tr-TR";
  if (!(WELCOME_EMAIL_LOCALES as readonly string[]).includes(locale)) {
    throw new Error("WELCOME_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING");
  }
  const isEnglish = locale !== "tr-TR";
  const displayName = escapePlain(input.displayName) ||
    (isEnglish ? "RiskDetected user" : "RiskDetected kullanıcısı");
  const supportEmail = escapePlain(input.supportEmail) ||
    "info@riskdetected.com";
  const currentYear = escapePlain(input.currentYear) ||
    new Date().getUTCFullYear().toString();
  const supportMailto = `mailto:${supportEmail}`;
  const htmlTemplate = isEnglish ? ENGLISH_HTML_TEMPLATE : HTML_TEMPLATE;
  const textTemplate = isEnglish ? ENGLISH_TEXT_TEMPLATE : TEXT_TEMPLATE;

  return {
    subject: isEnglish ? "Welcome to RiskDetected" : TURKISH_SUBJECT,
    html: replaceTemplate(htmlTemplate, {
      display_name: escapeHTML(displayName),
      support_email: escapeHTML(supportEmail),
      support_mailto: escapeHTML(supportMailto),
      current_year: escapeHTML(currentYear),
    }),
    text: replaceTemplate(textTemplate, {
      display_name: displayName,
      support_email: supportEmail,
      support_mailto: supportMailto,
      current_year: currentYear,
    }),
  };
}
