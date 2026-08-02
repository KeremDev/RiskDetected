import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("auth send-email hook verifies the exact Supabase secret format", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertStringIncludes(source, 'Deno.env.get("SEND_EMAIL_HOOK_SECRET")');
  assertStringIncludes(source, '.replace(/^v1,whsec_/, "")');
  assertStringIncludes(source, "new Webhook(secret).verify");
  assertEquals(source.includes("console.log"), false);
  assertEquals(source.includes("console.error"), false);
});

Deno.test("secure email change routes both exact OTPs without fallback", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertStringIncludes(source, 'action === "email_change" && newEmail');
  assertStringIncludes(source, "{ recipient: currentEmail, token }");
  assertStringIncludes(source, "{ recipient: newEmail, token: tokenNew }");
  assertStringIncludes(
    source,
    'error: "AUTH_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING"',
  );
  assertStringIncludes(source, "for (\n    const [deliveryIndex");
});

Deno.test("hook delegates every current Supabase action to the exact-locale catalog", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const catalog = await Deno.readTextFile(
    new URL("../_shared/auth-email-localization.ts", import.meta.url),
  );
  assertStringIncludes(source, "buildAuthEmail({");
  for (
    const action of [
      "email",
      "password_changed_notification",
      "email_changed_notification",
      "phone_changed_notification",
      "identity_linked_notification",
      "identity_unlinked_notification",
      "mfa_factor_enrolled_notification",
      "mfa_factor_unenrolled_notification",
    ]
  ) {
    assertStringIncludes(catalog, `"${action}"`);
  }
});

Deno.test("signed webhook replay is blocked before Resend and provider retries stay idempotent", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertStringIncludes(source, 'req.headers.get("webhook-id")');
  assertStringIncludes(source, "claim_auth_email_delivery_v1");
  assertStringIncludes(source, "complete_auth_email_delivery_v1");
  assertStringIncludes(source, "release_auth_email_delivery_v1");
  assertStringIncludes(source, '"Idempotency-Key"');
  assertStringIncludes(
    source,
    "`riskdetected-auth/${webhookIDHash}/${deliveryIndex}`",
  );
  const claimIndex = source.indexOf("claim_auth_email_delivery_v1");
  const resendIndex = source.indexOf(
    'fetch("https://api.resend.com/emails"',
  );
  assertEquals(claimIndex >= 0 && claimIndex < resendIndex, true);
});

Deno.test("successful hook responses preserve the JSON content type required by Supabase Auth", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertStringIncludes(
    source,
    'headers: { "Content-Type": "application/json" }',
  );
  assertStringIncludes(source, "return json(200, {});");
  assertEquals(
    source.includes("return new Response(null, { status: 200 });"),
    false,
  );
});

Deno.test("metadata-free Build 77 requests use only the bounded Turkish legacy context", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertStringIncludes(
    source,
    "const isLegacyTurkishRequest = resolvedLocale == null &&",
  );
  assertStringIncludes(source, "resolvedAppLanguage == null;");
  assertStringIncludes(
    source,
    'const locale = isLegacyTurkishRequest ? "tr-TR" : resolvedLocale;',
  );
  assertStringIncludes(
    source,
    'const appLanguage = isLegacyTurkishRequest ? "tr" : resolvedAppLanguage;',
  );
  assertStringIncludes(
    source,
    'error: "AUTH_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING"',
  );
});
