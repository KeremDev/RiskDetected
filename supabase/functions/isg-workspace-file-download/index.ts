/** Delivers one short-lived workspace download after a fresh scope check. */
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Body = { download_token?: unknown };
const json = (status: number, payload: Record<string, unknown>) =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
const validToken = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
async function sha256(input: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", input);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
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
  if (!validToken(body.download_token)) return json(400, { error: "VALIDATION_ERROR" });

  const worker = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: claim, error: claimError } = await worker.rpc("isg_workspace_download_claim_worker_v1", {
    p_token: body.download_token,
    p_now: new Date().toISOString(),
  });
  if (claimError || typeof claim?.bucket !== "string" || typeof claim?.object_path !== "string") {
    return json(403, { error: "ACCESS_DENIED" });
  }
  const downloaded = await worker.storage.from(claim.bucket).download(claim.object_path);
  if (downloaded.error || !downloaded.data) return json(404, { error: "FILE_NOT_FOUND" });
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
  if (bytes.length !== Number(claim.byte_size) || await sha256(bytes) !== claim.sha256) {
    return json(409, { error: "DELIVERY_EVIDENCE_CONFLICT" });
  }
  const { error: deliveredError } = await worker.rpc("isg_workspace_download_delivered_worker_v1", {
    p_download: claim.download_id,
    p_object_version: claim.object_version,
    p_bytes: bytes.length,
    p_now: new Date().toISOString(),
  });
  if (deliveredError) return json(409, { error: "DELIVERY_EVIDENCE_CONFLICT" });
  return new Response(bytes, {
    status: 200,
    headers: {
      "content-type": "application/octet-stream",
      "content-length": String(bytes.length),
      "cache-control": "private, no-store",
    },
  });
});
