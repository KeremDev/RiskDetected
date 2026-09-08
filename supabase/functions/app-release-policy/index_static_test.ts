import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

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

Deno.test("app-release-policy returns sanitized public release policy", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  // F9 (2026-08-06): the flag key is now resolved per-platform instead of hardcoded inline,
  // so the ios_release_policy literal moved into policyKeyAndFallback() — assert both halves.
  assertStringIncludes(source, '.eq("key", key)');
  assertStringIncludes(source, 'key: "ios_release_policy"');
  assertStringIncludes(source, 'key: "android_release_policy"');
  assertStringIncludes(source, "sanitizePolicy(data.value, fallback)");
  assertStringIncludes(source, "decisionFor(policy, build)");
  assertStringIncludes(
    source,
    "readAndroidRuntimeGates(supabase, platform, build)",
  );
  assertStringIncludes(source, "android_runtime_gates");
  assertStringIncludes(source, "android_legal_policy");
  assertStringIncludes(source, 'if (platform !== "android") return null');
  assertStringIncludes(source, 'action: "update_app"');
  assertStringIncludes(source, 'requiresAcknowledgement ? "accept" : "none"');
  assertStringIncludes(
    source,
    "sanitizeAndroidLegalPolicy(data.value, fallback)",
  );
  assertStringIncludes(source, '"android_legal_policy_en"');
  assertStringIncludes(source, "DEFAULT_ANDROID_LEGAL_POLICY_EN");
  assertStringIncludes(source, "hard_update_required");
  assertStringIncludes(source, "soft_update_available");
  assertStringIncludes(source, "cleanURL(");
  assertStringIncludes(source, "latest_build: 88");
  assert(!source.includes("service_role_key:"));
});

Deno.test("app-release-policy resolves android and unrecognized platforms without touching iOS's flag row", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  // F9 regression guard: an android or unrecognized-platform request must never fall through
  // to ios_release_policy — that was the actual bug (any platform silently got iOS's build
  // numbers). Each platform branch now has its own key and its own closed-by-default fallback.
  assertStringIncludes(source, 'if (platform === "ios")');
  assertStringIncludes(source, 'if (platform === "android")');
  assertStringIncludes(source, "DEFAULT_ANDROID_POLICY");
  assertStringIncludes(source, "DEFAULT_UNKNOWN_PLATFORM_POLICY");
  assertStringIncludes(source, "readPolicy(platform, supabase)");
});

Deno.test("attested iOS release policy stays safe for build 62 and App Review", async () => {
  const initialMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260622195418_multi_photo_editable_findings.sql",
      import.meta.url,
    ),
  );
  const currentMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260726152710_publish_ios_build_77_release_policy.sql",
      import.meta.url,
    ),
  );
  if (initialMigration == null || currentMigration == null) return;
  const normalizedSQL = `${initialMigration}\n${currentMigration}`
    .toLowerCase()
    .replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "'ios_release_policy'");
  assertStringIncludes(normalizedSQL, "'minimum_supported_build', 62");
  assertStringIncludes(normalizedSQL, "'latest_build', 77");
  assertStringIncludes(normalizedSQL, "'hard_update_enabled', false");
  assertStringIncludes(normalizedSQL, "'soft_update_enabled', true");
  assertStringIncludes(normalizedSQL, "apps.apple.com/tr/app/riskdetected");
});

Deno.test("live iOS build 88 is not offered the unreleased build 89", async () => {
  const reconciliationMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260906181130_reconcile_ios_build_88_release_policy.sql",
      import.meta.url,
    ),
  );
  if (reconciliationMigration == null) return;

  const normalizedSQL = reconciliationMigration
    .toLowerCase()
    .replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "'minimum_supported_build', 88");
  assertStringIncludes(normalizedSQL, "'latest_build', 88");
  assertStringIncludes(normalizedSQL, "'hard_update_enabled', true");
  assertStringIncludes(normalizedSQL, "'soft_update_enabled', true");
  assertStringIncludes(
    normalizedSQL,
    "'policy_version', 'build-88-appstore-general-release-reconciled'",
  );
});

Deno.test("published iOS build 89 keeps build 88 supported and validates analysis gates", async () => {
  const releaseMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260907020258_publish_ios_build_89_release_policy.sql",
      import.meta.url,
    ),
  );
  if (releaseMigration == null) return;

  const normalizedSQL = releaseMigration
    .toLowerCase()
    .replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "'minimum_supported_build', 88");
  assertStringIncludes(normalizedSQL, "'latest_build', 89");
  assertStringIncludes(normalizedSQL, "'hard_update_enabled', true");
  assertStringIncludes(normalizedSQL, "'soft_update_enabled', true");
  assertStringIncludes(
    normalizedSQL,
    "'policy_version', 'build-89-appstore-general-release'",
  );
  assertStringIncludes(normalizedSQL, "analysis_engine_v4");
  assertStringIncludes(normalizedSQL, "analysis_result_hub_v1");
  assertStringIncludes(normalizedSQL, "enabled_ios_builds");
  assertStringIncludes(normalizedSQL, "jsonb_array_elements_text");
  assertStringIncludes(normalizedSQL, "'[\"89\"]'::jsonb");
  assertStringIncludes(normalizedSQL, "? '89'");
});

Deno.test("published iOS build 90 keeps build 88 supported and opens both analysis gates", async () => {
  const releaseMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260908040102_publish_ios_build_90_release_policy.sql",
      import.meta.url,
    ),
  );
  if (releaseMigration == null) return;

  const normalizedSQL = releaseMigration
    .toLowerCase()
    .replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "'minimum_supported_build', 88");
  assertStringIncludes(normalizedSQL, "'latest_build', 90");
  assertStringIncludes(normalizedSQL, "'hard_update_enabled', true");
  assertStringIncludes(normalizedSQL, "'soft_update_enabled', true");
  assertStringIncludes(
    normalizedSQL,
    "'policy_version', 'build-90-appstore-general-release'",
  );
  assertStringIncludes(normalizedSQL, "analysis_engine_v4");
  assertStringIncludes(normalizedSQL, "analysis_result_hub_v1");
  assertStringIncludes(normalizedSQL, "enabled_ios_builds");
  assertStringIncludes(normalizedSQL, "jsonb_array_elements_text");
  assertStringIncludes(normalizedSQL, "'[\"90\"]'::jsonb");
  assertStringIncludes(normalizedSQL, "? '90'");
});

Deno.test("published iOS build 91 keeps build 88 supported and opens both analysis gates", async () => {
  const releaseMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260908235200_publish_ios_build_91_release_policy.sql",
      import.meta.url,
    ),
  );
  if (releaseMigration == null) return;

  const normalizedSQL = releaseMigration
    .toLowerCase()
    .replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "'minimum_supported_build', 88");
  assertStringIncludes(normalizedSQL, "'latest_build', 91");
  assertStringIncludes(normalizedSQL, "'hard_update_enabled', true");
  assertStringIncludes(normalizedSQL, "'soft_update_enabled', true");
  assertStringIncludes(
    normalizedSQL,
    "'policy_version', 'build-91-appstore-general-release'",
  );
  assertStringIncludes(normalizedSQL, "analysis_engine_v4");
  assertStringIncludes(normalizedSQL, "analysis_result_hub_v1");
  assertStringIncludes(normalizedSQL, "enabled_ios_builds");
  assertStringIncludes(normalizedSQL, "jsonb_array_elements_text");
  assertStringIncludes(normalizedSQL, "'[\"91\"]'::jsonb");
  assertStringIncludes(normalizedSQL, "? '91'");
});

Deno.test("live Android build 13 is reconciled without enabling update prompts", async () => {
  const releaseMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260909000000_publish_android_build_13_release_policy.sql",
      import.meta.url,
    ),
  );
  if (releaseMigration == null) return;

  const normalizedSQL = releaseMigration
    .toLowerCase()
    .replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "'latest_build', 13");
  assertStringIncludes(normalizedSQL, "'soft_update_enabled', false");
  assertStringIncludes(normalizedSQL, "'hard_update_enabled', false");
  assertStringIncludes(
    normalizedSQL,
    "'policy_version', 'production-2.0.1-vc13'",
  );
});

Deno.test("Android build 14 opens analysis gates without being advertised early", async () => {
  const gateMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260909000500_android_build_14_v4_result_hub_gate.sql",
      import.meta.url,
    ),
  );
  if (gateMigration == null) return;

  const normalizedSQL = gateMigration
    .toLowerCase()
    .replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "analysis_engine_v4");
  assertStringIncludes(normalizedSQL, "analysis_result_hub_v1");
  assertStringIncludes(normalizedSQL, "'[\"14\"]'::jsonb");
  assertStringIncludes(
    normalizedSQL,
    "?& array['7','8','9','10','11','12','13','14']",
  );
  assertStringIncludes(normalizedSQL, "<> 13");
  assertStringIncludes(normalizedSQL, "'production-2.0.1-vc13'");
});
