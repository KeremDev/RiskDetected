import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { buildWelcomeEmailContent } from "./template.ts";

Deno.test("welcome email template renders supported placeholders", () => {
  const email = buildWelcomeEmailContent({
    displayName: "Kerem Kayalar",
    supportEmail: "info@riskdetected.com",
    currentYear: "2026",
  });

  assertEquals(email.subject, "RiskDetected’a hoş geldiniz");
  assert(email.html.includes("Hoş geldiniz, Kerem Kayalar"));
  assert(email.html.includes("mailto:info@riskdetected.com"));
  assert(email.html.includes("&copy; 2026 RiskDetected"));
  assert(email.text.includes("Merhaba Kerem Kayalar,"));
  assert(!email.html.includes("{{"));
  assert(!email.text.includes("{{"));
});

Deno.test("welcome email template escapes dynamic display name", () => {
  const email = buildWelcomeEmailContent({
    displayName: "<script>alert('x')</script>",
    supportEmail: "info@riskdetected.com",
    currentYear: "2026",
  });

  assert(
    email.html.includes("&lt;script&gt;alert(&#039;x&#039;)&lt;/script&gt;"),
  );
  assert(!email.html.includes("<script>"));
});

Deno.test("welcome email template uses fallback display name", () => {
  const email = buildWelcomeEmailContent({
    displayName: "",
    supportEmail: "info@riskdetected.com",
    currentYear: "2026",
  });

  assert(email.html.includes("Hoş geldiniz, RiskDetected kullanıcısı"));
  assert(email.text.includes("Merhaba RiskDetected kullanıcısı,"));
});

Deno.test("English welcome email renders the exact requested locale", () => {
  const email = buildWelcomeEmailContent({
    displayName: "Kerem",
    supportEmail: "info@riskdetected.com",
    currentYear: "2026",
    locale: "en-GB",
  });

  assertEquals(email.subject, "Welcome to RiskDetected");
  assert(email.html.includes('<html lang="en">'));
  assert(email.html.includes("Welcome, Kerem"));
  assert(email.text.includes("Hello Kerem,"));
  assert(!email.html.includes("İSG"));
  assert(!email.text.includes("Mevzuat"));
});

Deno.test("welcome email never falls back from an unsupported locale", () => {
  assertThrows(
    () =>
      buildWelcomeEmailContent({
        displayName: "Kerem",
        supportEmail: "info@riskdetected.com",
        currentYear: "2026",
        locale: "en-NZ" as "en-GB",
      }),
    Error,
    "WELCOME_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING",
  );
});
