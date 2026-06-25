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

Deno.test("mutate-analysis-finding checks analysis update and rollup errors", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    "const { error: analysisUpdateError } = await supabase",
  );
  assertStringIncludes(
    source,
    "analysis_update:${analysisUpdateError.message}",
  );
  assertStringIncludes(
    source,
    "const { error: rollupError } = await supabase.rpc(",
  );
  assertStringIncludes(source, "rollup:${rollupError.message}");
});

Deno.test("mutate-analysis-finding lets generated score columns recalculate", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    "const fkScore = resolvedFkP * resolvedFkF * resolvedFkS;",
  );
  assertStringIncludes(source, "update.fk_band = fkBand(fkScore);");
  assertStringIncludes(
    source,
    "const m5Score = resolvedM5P * resolvedM5S;",
  );
  assertStringIncludes(source, "update.m5_band = m5Band(m5Score);");
  assertStringIncludes(source, "function withDerivedRiskSnapshot");
  assertStringIncludes(source, "snapshot.fk_score = score;");
  assertStringIncludes(source, "snapshot.m5_score = score;");
});

Deno.test("mutate-analysis-finding hard delete removes row after audit", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, 'event_type: "hard_delete"');
  assertStringIncludes(source, 'changed_fields: ["__deleted__"]');
  assertStringIncludes(source, '.from("findings")');
  assertStringIncludes(source, ".delete()");
  assertStringIncludes(source, '.eq("id", findingID)');
  assertStringIncludes(source, '.eq("analysis_id", analysisID)');
  assertStringIncludes(source, '.eq("user_id", user.id)');
});

Deno.test("finding edit audit table grants service_role access explicitly", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260622195418_multi_photo_editable_findings.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(
    normalizedSQL,
    "grant select, insert on table public.finding_edit_events to service_role",
  );
});

Deno.test("finding edits require build gated API contract", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "type ClientReleaseContext");
  assertStringIncludes(source, "function clientReleaseContext");
  assertStringIncludes(source, "function editableReleaseGateOpen");
  assertStringIncludes(source, "client.apiContractVersion < 2");
  assertStringIncludes(
    source,
    "client.capabilities.editable_findings !== true",
  );
  assertStringIncludes(
    source,
    "editableFindingsEnabled(supabase, clientRelease)",
  );
});
