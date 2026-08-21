import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { USER_FACING_COPY_KEYS, userFacingCopy } from "./user-facing-copy.ts";

Deno.test("semantic user copy resolves Turkish and English without leaking placeholders", () => {
  assertEquals(
    userFacingCopy("supportAttachmentsTooMany", "tr", { max: 3 }),
    "En fazla 3 ek dosya gönderebilirsin.",
  );
  assertEquals(
    userFacingCopy("supportAttachmentsTooMany", "en", { max: 3 }),
    "You can send up to 3 attachments.",
  );
  assertEquals(
    userFacingCopy("reportQuotaExceeded", "xx"),
    "Rapor kotan doldu.",
  );
});

Deno.test("coverage quality no-additional reasons stay paired in Turkish and English", () => {
  const keys = [
    "analysisQualityNoDistinctAdditionalHazard",
    "analysisQualityInsufficientVisualEvidence",
    "analysisQualityExistingFindingsCoverScene",
  ] as const;
  for (const key of keys) {
    const turkish = userFacingCopy(key, "tr");
    const english = userFacingCopy(key, "en");
    assertEquals(turkish.length > 20, true);
    assertEquals(english.length > 20, true);
    assertEquals(turkish === english, false, `languages leaked for ${key}`);
  }
});

Deno.test("every semantic user copy key has complete Turkish and English copy", () => {
  const variables = {
    max: 3,
    value: "Example",
    supportID: "RD-TEST",
    estimatedCompletionAt: "2026-08-16T00:00:00Z",
    store: "App Store",
    profileTerm: "workplace safety",
    count: 2,
  };
  for (const key of USER_FACING_COPY_KEYS) {
    for (const language of ["tr", "en"] as const) {
      const value = userFacingCopy(key, language, variables);
      assertEquals(
        value.trim().length > 0,
        true,
        `${key}/${language} is empty`,
      );
      assertEquals(
        value.includes("{{"),
        false,
        `${key}/${language} has unresolved placeholders`,
      );
    }
  }
});
