import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("support request persists language context without translating user text", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );

  for (
    const field of [
      "app_language",
      "content_locale",
      "user_message_language",
      "preferred_response_language",
    ]
  ) {
    assertStringIncludes(source, field);
  }
  assertStringIncludes(source, "message: values.message");
  assertStringIncludes(source, "Tercih edilen yanıt dili");
  assertStringIncludes(source, "supportAcknowledgement(");
  assertEquals(source.includes("translate("), false);
  assertEquals(source.includes("translation.googleapis.com"), false);
  assertEquals(source.includes("generativelanguage.googleapis.com"), false);
});

Deno.test("support acknowledgement has exact Turkish and English branches", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assert(source.includes("Your support request was sent."));
  assert(source.includes("Destek talebin gönderildi."));
  assert(
    source.includes("profile?.preferred_content_locale !== contentLocale"),
  );
});
