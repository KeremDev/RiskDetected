/**
 * account-deletion-complete — privileged account deletion worker.
 *
 * Intended use:
 * - Called manually by an operator or from a secured backend job after a user
 *   creates `public.account_deletion_requests`.
 * - Requires the service-role key in Authorization or
 *   `ACCOUNT_DELETION_ADMIN_SECRET` via `x-account-deletion-secret`.
 *
 * The mobile app must never call this function directly.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type AccountDeletionRequest = {
  id: string;
  user_id: string | null;
  email: string | null;
  status: string;
  requested_scope: string;
  target_user_id: string | null;
  target_email: string | null;
};

type CompletionBody = {
  request_id?: string;
  user_id?: string;
  dry_run?: boolean;
  processed_by?: string;
};

type SupabaseAdmin = ReturnType<typeof createClient<any, "public">>;

const BUCKETS = ["photos", "reports", "logos"] as const;
const BATCH_SIZE = 100;

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function newSupportID(): string {
  return `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function cleanText(value: unknown, fallback: string, maxLength = 120): string {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().replace(/[^\p{L}\p{N} ._:@-]/gu, "").slice(
    0,
    maxLength,
  );
  return clean.length > 0 ? clean : fallback;
}

function safeErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message.replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
      .slice(0, 240);
  }
  return String(error).replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]").slice(
    0,
    240,
  );
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function listBucketPaths(
  supabase: SupabaseAdmin,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const paths: string[] = [];

  async function walk(path: string) {
    const { data, error } = await supabase.storage
      .from(bucket)
      .list(path, { limit: 1000, sortBy: { column: "name", order: "asc" } });

    if (error) {
      throw new Error(`storage_list_failed:${bucket}:${error.message}`);
    }

    for (const item of data ?? []) {
      const childPath = path ? `${path}/${item.name}` : item.name;
      if (item.id || item.metadata) {
        paths.push(childPath);
      } else {
        await walk(childPath);
      }
    }
  }

  await walk(prefix);
  return paths;
}

async function removeBucketPrefix(
  supabase: SupabaseAdmin,
  bucket: string,
  userID: string,
): Promise<number> {
  const paths = await listBucketPaths(supabase, bucket, userID);
  let removed = 0;

  for (let index = 0; index < paths.length; index += BATCH_SIZE) {
    const chunk = paths.slice(index, index + BATCH_SIZE);
    if (chunk.length === 0) continue;

    const { data, error } = await supabase.storage
      .from(bucket)
      .remove(chunk);

    if (error) {
      throw new Error(`storage_remove_failed:${bucket}:${error.message}`);
    }
    removed += data?.length ?? chunk.length;
  }

  return removed;
}

async function findRequest(
  supabase: SupabaseAdmin,
  body: CompletionBody,
): Promise<AccountDeletionRequest | null> {
  if (body.request_id) {
    if (!isUUID(body.request_id)) throw new Error("invalid_request_id");
    const { data, error } = await supabase
      .from("account_deletion_requests")
      .select(
        "id,user_id,email,status,requested_scope,target_user_id,target_email",
      )
      .eq("id", body.request_id)
      .maybeSingle();

    if (error) throw new Error(`request_lookup_failed:${error.message}`);
    return data as AccountDeletionRequest | null;
  }

  if (!isUUID(body.user_id)) throw new Error("missing_request_id_or_user_id");
  const { data, error } = await supabase
    .from("account_deletion_requests")
    .select(
      "id,user_id,email,status,requested_scope,target_user_id,target_email",
    )
    .eq("user_id", body.user_id)
    .in("status", ["pending", "processing"])
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (error) throw new Error(`request_lookup_failed:${error.message}`);
  return data as AccountDeletionRequest | null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const supportID = newSupportID();
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return json(500, {
      error: "not_configured",
      message: "Account deletion worker is not configured.",
      support_id: supportID,
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const expectedHeader = `Bearer ${serviceRoleKey}`;
  const adminSecret = Deno.env.get("ACCOUNT_DELETION_ADMIN_SECRET");
  const providedSecret = req.headers.get("x-account-deletion-secret");

  if (
    authHeader !== expectedHeader &&
    (!adminSecret || providedSecret !== adminSecret)
  ) {
    return json(401, { error: "unauthorized", support_id: supportID });
  }

  let body: CompletionBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json", support_id: supportID });
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let request: AccountDeletionRequest | null = null;
  try {
    request = await findRequest(supabase, body);
  } catch (error) {
    return json(400, {
      error: "request_lookup_failed",
      message: safeErrorMessage(error),
      support_id: supportID,
    });
  }

  if (!request) {
    return json(404, { error: "request_not_found", support_id: supportID });
  }

  if (request.status === "completed") {
    return json(200, {
      ok: true,
      already_completed: true,
      request_id: request.id,
      support_id: supportID,
    });
  }

  if (!["pending", "processing"].includes(request.status)) {
    return json(409, {
      error: "request_not_processable",
      status: request.status,
      request_id: request.id,
      support_id: supportID,
    });
  }

  const targetUserID = request.target_user_id ?? request.user_id;
  if (!isUUID(targetUserID)) {
    return json(409, {
      error: "target_user_missing",
      request_id: request.id,
      support_id: supportID,
    });
  }

  const now = new Date().toISOString();
  const processedBy = cleanText(
    body.processed_by,
    "edge:function:account-deletion-complete",
  );
  const targetEmail = request.target_email ?? request.email ?? null;
  const targetHash = await sha256Hex(targetUserID);

  const processingPatch: Record<string, unknown> = {
    status: "processing",
    processed_by: processedBy,
    completion_support_id: supportID,
    completion_error: null,
    target_user_id: targetUserID,
    target_email: targetEmail,
    target_user_hash: targetHash,
    updated_at: now,
  };

  if (request.status !== "processing") {
    processingPatch.processing_started_at = now;
  }

  const { error: processingError } = await supabase
    .from("account_deletion_requests")
    .update(processingPatch)
    .eq("id", request.id)
    .in("status", ["pending", "processing"]);

  if (processingError) {
    return json(500, {
      error: "request_lock_failed",
      message: processingError.message,
      request_id: request.id,
      support_id: supportID,
    });
  }

  if (body.dry_run === true) {
    return json(200, {
      ok: true,
      dry_run: true,
      request_id: request.id,
      target_user_id: targetUserID,
      buckets: BUCKETS,
      support_id: supportID,
    });
  }

  const removed: Record<string, number> = {};

  try {
    for (const bucket of BUCKETS) {
      removed[bucket] = await removeBucketPrefix(
        supabase,
        bucket,
        targetUserID,
      );
    }

    const { error: authDeleteError } = await supabase.auth.admin.deleteUser(
      targetUserID,
    );
    if (authDeleteError) {
      throw new Error(`auth_delete_failed:${authDeleteError.message}`);
    }

    const completedAt = new Date().toISOString();
    const { error: completeError } = await supabase
      .from("account_deletion_requests")
      .update({
        status: "completed",
        completed_at: completedAt,
        completion_support_id: supportID,
        completion_error: null,
        deleted_photo_objects: removed.photos ?? 0,
        deleted_report_objects: removed.reports ?? 0,
        deleted_logo_objects: removed.logos ?? 0,
        auth_user_deleted: true,
        updated_at: completedAt,
      })
      .eq("id", request.id);

    if (completeError) {
      throw new Error(
        `request_complete_update_failed:${completeError.message}`,
      );
    }

    return json(200, {
      ok: true,
      request_id: request.id,
      target_user_hash: targetHash,
      deleted_storage_objects: removed,
      auth_user_deleted: true,
      support_id: supportID,
    });
  } catch (error) {
    const failedAt = new Date().toISOString();
    const message = safeErrorMessage(error);
    await supabase
      .from("account_deletion_requests")
      .update({
        status: "pending",
        completion_error: message.slice(0, 1000),
        completion_support_id: supportID,
        updated_at: failedAt,
      })
      .eq("id", request.id);

    return json(500, {
      error: "account_deletion_failed",
      message,
      request_id: request.id,
      support_id: supportID,
    });
  }
});
