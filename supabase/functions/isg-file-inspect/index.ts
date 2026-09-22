/**
 * isg-file-inspect — moves one upload through the quarantine state machine.
 *
 * Authority in this function is always the signed-in expert. The caller's own
 * JWT is what proves the entry belongs to them; the service role is used only
 * to read the quarantined bytes and to write the promoted object, and the
 * inspection entry it calls takes no actor argument at all. Holding the service
 * key therefore never lets this function act as a user.
 *
 * What runs here is the format inspector in _shared/isg/file-format-inspector.ts:
 * real type, size, hash and active content. It is not antivirus, and nothing in
 * this function or the rows it writes says otherwise.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  inspect,
  LIMITS,
  readZipDirectory,
  SCANNER_NAME,
  SCANNER_VERSION,
  storedContentType,
} from "../_shared/isg/file-format-inspector.ts";

const QUARANTINE = "isg-quarantine";
const FINAL = "isg-documents";
/** Beyond this the worker refuses rather than pulling the file into memory. */
const MAX_INSPECT_BYTES = 52_428_800;

type Body = { entry_id?: unknown; workspace_id?: unknown };

const json = (status: number, payload: Record<string, unknown>) =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const isUuid = (value: unknown): value is string =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

async function digest(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes).buffer);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/** Async pre-pass: decompress the package parts the inspector wants to read. */
async function inflateAll(input: Uint8Array, limit: number): Promise<Uint8Array> {
  const stream = new Blob([Uint8Array.from(input).buffer]).stream().pipeThrough(
    new DecompressionStream("deflate-raw"),
  );
  const chunks: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of stream as unknown as AsyncIterable<Uint8Array>) {
    total += chunk.length;
    if (total > limit) throw new Error("INFLATE_LIMIT");
    chunks.push(chunk);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const chunk of chunks) {
    out.set(chunk, at);
    at += chunk.length;
  }
  return out;
}

/**
 * The inspector's inflate port has to answer synchronously, so every entry it
 * may ask for is decompressed first and served from this cache. Nothing outside
 * the cache is ever returned: an unexpected request throws and the upload is
 * treated as an inspection failure, never as clean.
 */
async function buildInflateCache(bytes: Uint8Array): Promise<(input: Uint8Array, limit: number) => Uint8Array> {
  const cache = new Map<string, Uint8Array>();
  const key = (input: Uint8Array) => `${input.length}:${input[0] ?? 0}:${input[input.length - 1] ?? 0}`;
  // Walk the central directory the same way the inspector does, and pre-inflate
  // every stored part. The inspector re-reads the directory itself; this pass
  // only fills the cache.
  const entries = readZipDirectory(bytes) ?? [];
  for (const entry of entries) {
    if (entry.uncompressedSize > LIMITS.zipInspectEntry) continue;
    const at = entry.localHeaderOffset;
    if (at + 30 > bytes.length) continue;
    const view = new DataView(bytes.buffer, bytes.byteOffset);
    const start = at + 30 + view.getUint16(at + 26, true) + view.getUint16(at + 28, true);
    const body = bytes.subarray(start, start + entry.compressedSize);
    if (entry.method === 0) continue;
    try {
      cache.set(key(body), await inflateAll(body, LIMITS.zipInspectEntry));
    } catch {
      // A part that will not decompress is left out; the inspector then treats
      // the package as malformed instead of clearing it.
    }
  }
  return (input: Uint8Array) => {
    const hit = cache.get(key(input));
    if (!hit) throw new Error("INFLATE_MISS");
    return hit;
  };
}

serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json(500, { error: "FUNCTION_NOT_CONFIGURED" });

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return json(401, { error: "AUTH_REQUIRED" });
  }

  let body: Body;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "VALIDATION_ERROR" });
  }
  if (!isUuid(body.entry_id)) return json(400, { error: "VALIDATION_ERROR" });
  const entryId = body.entry_id;
  const workspace = body.workspace_id;
  if (workspace !== undefined && !isUuid(workspace)) return json(400, { error: "VALIDATION_ERROR" });

  // The caller's own token decides whether this entry is theirs to inspect.
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const readArguments = {
    p_company: null, p_kind: "detail", p_query: null, p_category: null,
    p_state: null, p_id: entryId, p_limit: null, p_offset: null,
  };
  const { data: response, error: readError } = workspace
    ? await caller.rpc("isg_expert_rpc_v1", {
      p_workspace: workspace, p_function: "isg_expert_file_inspection_access_v1", p_arguments: { entry_id: entryId },
    })
    : await caller.rpc("isg_file_library_read_v1", readArguments);
  if (workspace && response?._expert_workspace_id !== workspace) return json(403, { error: "ACCESS_DENIED" });
  const owned = workspace ? response?.payload : response;
  if (readError || !owned?.row) return json(403, { error: "ACCESS_DENIED" });
  const entry = owned.row as Record<string, unknown>;
  const intentId = entry.intent_id;
  if (!isUuid(intentId)) return json(409, { error: "NOT_INSPECTABLE" });

  const worker = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const stage = async (name: string, payload: Record<string, unknown>) => {
    const { data, error } = await worker.rpc(workspace ? "isg_expert_file_inspection_v1" : "isg_file_inspection_v1", {
      p_intent: intentId, p_stage: name, p_payload: payload,
    });
    if (error) throw new Error(`STAGE_${name.toUpperCase()}_FAILED:${error.message}`);
    return data as Record<string, unknown>;
  };

  try {
    const claim = await stage("claim", {});
    if (claim.state === "promoted") return json(200, { row: entry, already: true });
    if (claim.state !== "pending" && claim.state !== "uploaded" && claim.state !== "scanning") {
      return json(409, { error: "NOT_INSPECTABLE", state: claim.state });
    }
    const declaredBytes = Number(claim.declared_bytes);
    if (!Number.isFinite(declaredBytes) || declaredBytes > MAX_INSPECT_BYTES) {
      return json(413, { error: "TOO_LARGE_TO_INSPECT" });
    }

    const download = await worker.storage.from(QUARANTINE).download(String(claim.quarantine_path));
    if (download.error || !download.data) {
      // Nothing landed, or it cannot be read. That is not a clean verdict.
      return json(409, { error: "UPLOAD_NOT_FOUND" });
    }
    const bytes = new Uint8Array(await download.data.arrayBuffer());
    const sha256 = await digest(bytes);

    const inflate = await buildInflateCache(bytes);
    const result = inspect({
      bytes,
      declaredExtension: String(claim.extension),
      declaredBytes,
      declaredSha256: String(claim.declared_sha256),
      actualSha256: sha256,
      inflateRaw: inflate,
    });

    // The state machine re-checks size and hash itself; this stage only reports
    // what landed, and it refuses the upload on its own if they disagree.
    const received = await stage("received", {
      bytes: bytes.length, sha256, detected_type: result.detectedType,
    });
    if (received.state !== "uploaded") {
      return json(200, { row: received.row ?? null, state: received.state });
    }

    const scanned = await stage("scanned", {
      scanner: SCANNER_NAME,
      scan_version: SCANNER_VERSION,
      verdict: result.verdict,
      finding_code: result.findingCode ?? "",
      sha256,
      evidence: result.evidence,
    });
    if (result.verdict !== "clean" || scanned.state !== "clean") {
      return json(200, { row: scanned.row ?? null, state: scanned.state });
    }

    // Only now do the bytes leave quarantine. upsert stays off: a content
    // addressed path must never be written over.
    const upload = await worker.storage.from(FINAL).upload(
      `assets/${claim.storage_scope ?? claim.owner_id}/${sha256}`,
      bytes,
      { contentType: storedContentType(String(claim.extension)), upsert: false },
    );
    const alreadyThere = Boolean(upload.error) &&
      /exists|duplicate|409/i.test(String(upload.error?.message ?? ""));
    if (upload.error && !alreadyThere) {
      return json(503, { error: "PROMOTION_FAILED" });
    }
    const promoted = await stage("promoted", { sha256, bytes: bytes.length });
    return json(200, { row: promoted.row ?? null, state: "promoted" });
  } catch (error) {
    // An inspection that could not finish leaves the upload where it was. The
    // expert sees an upload still waiting, never a file presented as cleared.
    return json(503, { error: "INSPECTION_UNAVAILABLE", detail: String(error).slice(0, 200) });
  }
});
