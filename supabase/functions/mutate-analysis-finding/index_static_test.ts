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
