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

  assertStringIncludes(source, '.eq("key", "ios_release_policy")');
  assertStringIncludes(source, "sanitizePolicy(data.value)");
  assertStringIncludes(source, "decisionFor(policy, build)");
  assertStringIncludes(source, "hard_update_required");
  assertStringIncludes(source, "soft_update_available");
  assertStringIncludes(source, "cleanURL(");
  assertStringIncludes(source, "latest_build: 76");
  assert(!source.includes("service_role_key:"));
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
