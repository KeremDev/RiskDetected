import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  AUTH_EMAIL_ACTIONS,
  AUTH_EMAIL_LOCALES,
  buildAuthEmail,
} from "./auth-email-localization.ts";

Deno.test("auth email has exact-locale English templates", () => {
  for (const locale of AUTH_EMAIL_LOCALES.filter((item) => item !== "tr-TR")) {
    const email = buildAuthEmail({
      locale,
      action: "magiclink",
      token: "123456",
    });
    assertEquals(email.ok, true);
    if (!email.ok) continue;
    assertEquals(email.subject, "RiskDetected sign-in code");
    assert(email.html.includes('<html lang="en">'));
    assert(email.text.includes("123456"));
    assertEquals(email.html.includes("Giriş kodun"), false);
  }
});

Deno.test("auth email preserves Turkish exact-locale copy", () => {
  const email = buildAuthEmail({
    locale: "tr-TR",
    action: "signup",
    token: "654321",
  });
  assertEquals(email.ok, true);
  if (!email.ok) return;
  assertEquals(email.subject, "RiskDetected e-posta doğrulama kodu");
  assert(email.html.includes('<html lang="tr">'));
});

Deno.test("auth email never falls back for unsupported locale", () => {
  assertEquals(
    buildAuthEmail({
      locale: "en-NZ",
      action: "magiclink",
      token: "123456",
    }),
    {
      ok: false,
      code: "AUTH_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING",
    },
  );
});

Deno.test("all current Supabase auth email actions have exact-locale copy", () => {
  const notificationActions = new Set([
    "password_changed_notification",
    "email_changed_notification",
    "phone_changed_notification",
    "identity_linked_notification",
    "identity_unlinked_notification",
    "mfa_factor_enrolled_notification",
    "mfa_factor_unenrolled_notification",
  ]);

  for (const locale of AUTH_EMAIL_LOCALES) {
    for (const action of AUTH_EMAIL_ACTIONS) {
      const email = buildAuthEmail({
        locale,
        action,
        token: notificationActions.has(action) ? undefined : "123456",
      });
      assertEquals(email.ok, true, `${locale}:${action}`);
      if (!email.ok) continue;
      assert(email.subject.length > 0);
      assert(email.text.length > 0);
      assert(
        email.html.includes(
          locale === "tr-TR" ? '<html lang="tr">' : '<html lang="en">',
        ),
      );
    }
  }
});

Deno.test("security notifications render without an OTP block", () => {
  const email = buildAuthEmail({
    locale: "en-US",
    action: "password_changed_notification",
    token: undefined,
  });
  assertEquals(email.ok, true);
  if (!email.ok) return;
  assertEquals(email.html.includes("letter-spacing:10px"), false);
  assertEquals(email.text.includes("undefined"), false);
});

Deno.test("token actions still fail closed when the OTP is missing", () => {
  assertEquals(
    buildAuthEmail({
      locale: "en-US",
      action: "recovery",
      token: undefined,
    }),
    {
      ok: false,
      code: "AUTH_EMAIL_TOKEN_MISSING",
    },
  );
});
