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

Deno.test("register-report snapshots are rebuilt from server-side rows", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "async function loadServerReportSnapshot");
  assertStringIncludes(source, '.from("findings")');
  assertStringIncludes(source, "needs_field_verification");
  assertStringIncludes(source, '.from("photos")');
  assertStringIncludes(source, '.eq("analysis_id", params.analysisID)');
  assertStringIncludes(source, '.eq("user_id", params.userID)');
  assertStringIncludes(source, '.eq("is_user_deleted", false)');
  assertStringIncludes(source, '.eq("report_visibility", "visible")');
  assertStringIncludes(
    source,
    '.order("display_order", { ascending: true, nullsFirst: false })',
  );
  assertStringIncludes(
    source,
    '.order("sequence_index", { ascending: true, nullsFirst: false })',
  );
});

Deno.test("register-report insert ignores client supplied snapshot fields", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "findings_snapshot_json: snapshot.findings");
  assertStringIncludes(source, "photos_snapshot_json: snapshot.photos");
  assertStringIncludes(
    source,
    "analysis_edit_version: snapshot.analysisEditVersion",
  );
  assertStringIncludes(
    source,
    "generated_from_user_edited_findings: snapshot.hasUserEdits",
  );
  assertStringIncludes(source, "source_photo_count: snapshot.sourcePhotoCount");
  assertStringIncludes(
    source,
    "visible_findings_count: snapshot.visibleFindingsCount",
  );

  assert(
    !source.includes("findings_snapshot_json: body.findings_snapshot_json"),
  );
  assert(!source.includes("photos_snapshot_json: body.photos_snapshot_json"));
  assert(!source.includes("analysis_edit_version: Math.max("));
  assert(
    !source.includes(
      "generated_from_user_edited_findings === true",
    ),
  );
  assert(!source.includes("Number(body.source_photo_count)"));
  assert(!source.includes("Number(body.visible_findings_count)"));
});

Deno.test("register-report snapshot storage is build gated", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "async function reportSnapshotV2Enabled");
  assertStringIncludes(source, "function snapshotGateOpen");
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

Deno.test("register-report enforces the additive Android PDF runtime gate", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, 'clientPlatform === "android"');
  assertStringIncludes(source, "runtimeGates?.pdf_reports");
  assertStringIncludes(source, "android_pdf_reports_disabled");
});
