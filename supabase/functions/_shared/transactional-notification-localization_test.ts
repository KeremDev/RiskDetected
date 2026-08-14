import {
  assertEquals,
  assertMatch,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  NOTIFICATION_LOCALES,
  resolveTransactionalNotificationTemplate,
  TRANSACTIONAL_NOTIFICATION_EVENT_KEYS,
} from "./transactional-notification-localization.ts";

Deno.test("every transactional event has an exact template for every locale", async () => {
  for (const locale of NOTIFICATION_LOCALES) {
    for (const eventKey of TRANSACTIONAL_NOTIFICATION_EVENT_KEYS) {
      const result = await resolveTransactionalNotificationTemplate({
        locale,
        eventKey,
      });
      assertEquals(result.ok, true, `${locale}/${eventKey}`);
      if (!result.ok) continue;
      assertEquals(result.locale, locale);
      assertMatch(result.checksum, /^[0-9a-f]{64}$/);
      assertEquals(result.title.length > 0, true);
      assertEquals(result.body.length > 0, true);
    }
  }
});

Deno.test("transactional template resolver never falls back across locales", async () => {
  const result = await resolveTransactionalNotificationTemplate({
    locale: "en-NZ",
    eventKey: "report_ready",
  });
  assertEquals(result, {
    ok: false,
    code: "NOTIFICATION_LOCALE_UNSUPPORTED",
  });
});

Deno.test("unknown transactional event keys fail closed", async () => {
  const result = await resolveTransactionalNotificationTemplate({
    locale: "en-GB",
    eventKey: "arbitrary_free_text",
  });
  assertEquals(result, {
    ok: false,
    code: "NOTIFICATION_EVENT_KEY_UNKNOWN",
  });
});
