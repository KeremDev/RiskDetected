import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  englishDueTerm,
  englishRiskBand,
  nonTRReportTemplateLeak,
  reportDate,
  reportNumber,
  resolveReportLocalization,
} from "./report-localization.ts";

const englishSnapshot = {
  schema_version: 1,
  output_language: "en",
  output_locale: "en-GB",
  work_jurisdiction_country: "GB",
  work_jurisdiction_region: null,
  safety_profile_id: "en-gb-generic-v1",
  safety_profile_version: 1,
  regulatory_reference_policy: "none",
  prompt_profile_version: "v1",
  method: "matrix_5x5",
  legal_document_set: "en-global-v1",
  manifest_version: 1,
  manifest_source_sha256: "fixture",
  source: "test",
};

Deno.test("report language is derived from immutable analysis snapshot", () => {
  const result = resolveReportLocalization({
    localizationSnapshot: englishSnapshot,
    requestedLanguage: "en",
  });
  assertEquals(result.ok, true);
  if (!result.ok) return;
  assertEquals(result.context.language, "en");
  assertEquals(result.context.locale, "en-GB");
  assertFalse(result.context.regulatorySectionsEnabled);
});

Deno.test("report language mismatch fails closed", () => {
  assertEquals(
    resolveReportLocalization({
      localizationSnapshot: englishSnapshot,
      requestedLanguage: "tr",
    }),
    { ok: false, code: "REPORT_LANGUAGE_MISMATCH" },
  );
});

Deno.test("report localization requires a complete snapshot", () => {
  assertEquals(
    resolveReportLocalization({
      localizationSnapshot: null,
      requestedLanguage: "en",
    }),
    { ok: false, code: "REPORT_LOCALIZATION_SNAPSHOT_MISSING" },
  );
  assertEquals(
    resolveReportLocalization({
      localizationSnapshot: { output_language: "en" },
      requestedLanguage: "en",
    }),
    { ok: false, code: "REPORT_LOCALIZATION_SNAPSHOT_INVALID" },
  );
});

Deno.test("English report formatting follows snapshot locale", () => {
  assertEquals(
    reportDate("2026-07-30T12:00:00Z", "en-GB"),
    "30 July 2026 at 12:00",
  );
  assertEquals(reportNumber(1234.5, "en-US"), "1,234.5");
  assertEquals(englishRiskBand("critical"), "Critical");
  assertEquals(englishDueTerm("high"), "7 days");
});

Deno.test("non-TR report template leak scanner blocks Turkish compliance copy", () => {
  assertEquals(nonTRReportTemplateLeak("Mevzuat Referansı"), "mevzuat");
  assertEquals(nonTRReportTemplateLeak("OSGB"), "osgb");
  assertEquals(
    nonTRReportTemplateLeak(
      "This output supports prioritisation and does not determine compliance.",
    ),
    null,
  );
});
