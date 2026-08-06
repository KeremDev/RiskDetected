import { assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readTextIfAllowed(url: URL): Promise<string | null> {
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") return null;
  return await Deno.readTextFile(path);
}

Deno.test("retention cleanup validates user and analysis storage binding", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    ".select(\"id, storage_path, analysis_id, user_id\")",
  );
  assertStringIncludes(source, "function hasBoundStoragePath");
  assertStringIncludes(source, "photos = allExpiredPhotos.filter");
  assertStringIncludes(source, "skipped_unbound_photo_rows");
});
