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
  assertStringIncludes(source, "latest_build: 76");
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
