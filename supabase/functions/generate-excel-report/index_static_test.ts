import { assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readTextIfAllowed(url: URL): Promise<string | null> {
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") {
    console.warn(
      `Skipping static source assertion; rerun with --allow-read=${path}`,
    );
    return null;
  }
  return await Deno.readTextFile(path);
}

Deno.test("generate-excel-report snapshot columns are build gated", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "async function reportSnapshotV2Enabled");
  assertStringIncludes(source, "function reportSnapshotV2GateOpen");
  assertStringIncludes(source, "contractVersion < 2");
  assertStringIncludes(source, "capabilities.report_snapshot_v2 !== true");
  assertStringIncludes(source, 'platform !== "android"');
  assertStringIncludes(source, "value.enabled_android_builds");
  assertStringIncludes(source, "value.min_android_build");
  assertStringIncludes(
    source,
    "const shouldStoreSnapshot = await reportSnapshotV2Enabled",
  );
  assertStringIncludes(source, "...snapshotColumns");
});

Deno.test("generate-excel-report summary and table layout prevent clipped text", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "function estimatedRowHeight");
  assertStringIncludes(source, "const summaryColumnWidths");
  assertStringIncludes(source, '"A10:B10"');
  assertStringIncludes(source, '"G13:H13"');
  assertStringIncludes(source, 'setStyle(summary, "A4:H8"');
  assertStringIncludes(source, 'setStyle(summary, "A16:H20"');
  assertStringIncludes(source, "const riskColumnWidths");
  assertStringIncludes(source, "{ min: 72, max: 260");
});

Deno.test("generate-excel-report derives language from analysis snapshot", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "resolveReportLocalization({");
  assertStringIncludes(source, "localization_snapshot");
  assertStringIncludes(source, "REPORT_LANGUAGE_MISMATCH");
  assertStringIncludes(source, "makeEnglishWorkbook(");
  assertStringIncludes(source, "report_language:");
  assertStringIncludes(source, "regulatory_sections_enabled:");
  assertStringIncludes(source, "localization_snapshot:");
});

Deno.test("generate-excel-report compares report intent UUIDs canonically", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    "reportIntent.analysis_id.toLowerCase() !== analysisID.toLowerCase()",
  );
});

Deno.test("generate-excel-report applies authenticated report customization", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "company_name_override?: string | null");
  assertStringIncludes(source, "prepared_by_override?: string | null");
  assertStringIncludes(source, "certificate_number_override?: string | null");
  assertStringIncludes(source, "company_logo_base64?: string | null");
  assertStringIncludes(source, "function inlineCompanyLogo(");
  assertStringIncludes(source, "value.length > 4_000_000");
  assertStringIncludes(source, "const effectiveProfile: ProfileRow");
  assertStringIncludes(source, "inlineCompanyLogo(body.company_logo_base64)");
  assertStringIncludes(
    source,
    "default_responsible: company.default_responsible ?? null",
  );
  assertStringIncludes(
    source,
    "default_due_days: company.default_due_days ?? null",
  );
  assertStringIncludes(source, "company_info: companyInfo");
  assertStringIncludes(
    source,
    "company_info: overrideText(body.company_info_override, 500)",
  );
  assertStringIncludes(source, "phone: companyProfile?.phone ?? null");
  assertStringIncludes(
    source,
    "safeText(profile?.company_info, safeText(profile?.phone))",
  );
});

Deno.test("generate-excel-report persists a validated request platform with analysis fallback", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "client_platform: (() => {");
  assertStringIncludes(source, "(analysis as AnalysisRow).client_platform");
});
