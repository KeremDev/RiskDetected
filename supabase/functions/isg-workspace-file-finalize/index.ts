/**
 * Finalizes one OSGB workspace upload after inspecting the exact bytes written
 * to the server-selected private path. The caller can provide only the opaque
 * upload token; bucket, path, tenant scope and asset identity stay server-owned.
 */
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  inspect,
  LIMITS,
  readZipDirectory,
  SCANNER_NAME,
  SCANNER_VERSION,
} from "../_shared/isg/file-format-inspector.ts";

const MAX_BYTES = 52_428_800;
type Body = { upload_token?: unknown };

const json = (status: number, payload: Record<string, unknown>) =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const token = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9a-f]{64}$/.test(value);

const uuid = (value: unknown): value is string =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

async function sha256(input: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", input);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function inflateAll(input: Uint8Array, limit: number): Promise<Uint8Array> {
  const stream = new Blob([input]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  const chunks: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of stream as unknown as AsyncIterable<Uint8Array>) {
    total += chunk.length;
    if (total > limit) throw new Error("INFLATE_LIMIT");
    chunks.push(chunk);
  }
  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}

async function inflateCache(bytes: Uint8Array): Promise<(input: Uint8Array, limit: number) => Uint8Array> {
  const cache = new Map<string, Uint8Array>();
  const key = (value: Uint8Array) => `${value.length}:${value[0] ?? 0}:${value[value.length - 1] ?? 0}`;
  for (const entry of readZipDirectory(bytes) ?? []) {
    if (entry.method === 0 || entry.uncompressedSize > LIMITS.zipInspectEntry) continue;
    const at = entry.localHeaderOffset;
    if (at + 30 > bytes.length) continue;
    const view = new DataView(bytes.buffer, bytes.byteOffset);
    const start = at + 30 + view.getUint16(at + 26, true) + view.getUint16(at + 28, true);
    const body = bytes.subarray(start, start + entry.compressedSize);
    try {
      cache.set(key(body), await inflateAll(body, LIMITS.zipInspectEntry));
    } catch {
      // The shared inspector treats a missing decompression result as malformed.
    }
  }
  return (input: Uint8Array) => {
    const output = cache.get(key(input));
    if (!output) throw new Error("INFLATE_MISS");
    return output;
  };
}

serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !serviceKey) return json(500, { error: "FUNCTION_NOT_CONFIGURED" });

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) return json(401, { error: "AUTH_REQUIRED" });
  const caller = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: authError } = await caller.auth.getUser();
  if (authError) return json(401, { error: "AUTH_REQUIRED" });

  let body: Body;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "VALIDATION_ERROR" });
  }
  if (!token(body.upload_token)) return json(400, { error: "VALIDATION_ERROR" });

  const worker = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: claim, error: claimError } = await worker.rpc("isg_workspace_upload_claim_worker_v1", {
    p_token: body.upload_token,
    p_now: new Date().toISOString(),
  });
  if (claimError) return json(403, { error: String(claimError.message).slice(0, 120) });
  if (claim?.status === "finalized" && uuid(claim.asset_id)) {
    return json(200, claim as Record<string, unknown>);
  }
  if (claim?.status !== "open" || typeof claim.bucket !== "string" ||
      typeof claim.object_path !== "string" || typeof claim.extension !== "string" ||
      typeof claim.declared_sha256 !== "string" || !/^[0-9a-f]{64}$/.test(claim.declared_sha256)) {
    return json(409, { error: "UPLOAD_NOT_OPEN" });
  }

  const downloaded = await worker.storage.from(claim.bucket).download(claim.object_path);
  if (downloaded.error || !downloaded.data) return json(409, { error: "UPLOAD_NOT_FOUND" });
  const input = new Uint8Array(await downloaded.data.arrayBuffer());
  if (input.length < 1 || input.length > MAX_BYTES || input.length !== Number(claim.expected_bytes)) {
    await worker.storage.from(claim.bucket).remove([claim.object_path]);
    return json(413, { error: "SIZE_LIMIT" });
  }

  try {
    const hash = await sha256(input);
    const inflateRaw = await inflateCache(input);
    const result = inspect({
      bytes: input,
      declaredExtension: claim.extension,
      declaredBytes: Number(claim.expected_bytes),
      declaredSha256: claim.declared_sha256,
      actualSha256: hash,
      inflateRaw,
    });
    if (result.verdict !== "clean") {
      await worker.storage.from(claim.bucket).remove([claim.object_path]);
      return json(422, {
        error: "FILE_REJECTED",
        finding_code: result.findingCode ?? "unsupported",
        scanner: SCANNER_NAME,
        scanner_version: SCANNER_VERSION,
      });
    }
    const { data: finalized, error: finalizeError } = await worker.rpc(
      "isg_workspace_upload_finalize_worker_v1",
      {
        p_token: body.upload_token,
        p_object_version: hash,
        p_actual_bytes: input.length,
        p_sha: `\\x${hash}`,
        p_now: new Date().toISOString(),
      },
    );
    if (finalizeError) return json(409, { error: String(finalizeError.message).slice(0, 120) });
    return json(200, finalized as Record<string, unknown>);
  } catch {
    return json(422, { error: "FILE_INSPECTION_FAILED" });
  }
});
