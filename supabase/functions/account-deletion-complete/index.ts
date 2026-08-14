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
  target_user_hash: string | null;
  attempt_count: number;
  processing_started_at: string | null;
};

type CompletionBody = {
  request_id?: string;
  user_id?: string;
  dry_run?: boolean;
  processed_by?: string;
};

type SupabaseAdmin = ReturnType<typeof createClient<any, "public">>;

const BUCKETS = ["photos", "reports", "logos", "avatars"] as const;
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

function safeErrorCode(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  const category = raw.split(":", 1)[0].toLowerCase();
  const sanitized = category.replace(/[^a-z0-9_]/g, "_").slice(0, 80);
  return sanitized || "unknown_failure";
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

async function sendCompletionEmail(
  email: string | null,
  supportID: string,
): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("RESEND_FROM_EMAIL") ??
    "RiskDetected <info@riskdetected.com>";
  if (!apiKey || !email) return;

  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [email],
      subject: "RiskDetected hesabın ve verilerin silindi",
      text:
        "Hesabın ve RiskDetected verilerin silindi. Aktif Google Play veya App Store aboneliğin varsa mağaza abonelik ayarlarından ayrıca yönetmelisin.\n\n" +
        `Destek kodu: ${supportID}`,
    }),
  }).catch(() => undefined);
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
        "id,user_id,email,status,requested_scope,target_user_id,target_email,target_user_hash,attempt_count,processing_started_at",
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
      "id,user_id,email,status,requested_scope,target_user_id,target_email,target_user_hash,attempt_count,processing_started_at",
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
      failure_code: safeErrorCode(error),
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

  const now = new Date().toISOString();
  if (request.status === "processing") {
    const staleBefore = new Date(Date.now() - 15 * 60 * 1000).toISOString();
    const startedAt = request.processing_started_at;
    if (!startedAt || startedAt > staleBefore) {
      return json(409, {
        error: "request_already_processing",
        status: request.status,
        request_id: request.id,
        support_id: supportID,
      });
    }
    const recoveredAttemptCount = Math.min(request.attempt_count + 1, 10);
    const { data: recovered, error: recoveryError } = await supabase
      .from("account_deletion_requests")
      .update({
        status: "pending",
        attempt_count: recoveredAttemptCount,
        completion_error: "stale_claim_recovered",
        last_error_code: "stale_claim_recovered",
        next_attempt_at: null,
        updated_at: now,
      })
      .eq("id", request.id)
      .eq("status", "processing")
      .lte("processing_started_at", staleBefore)
      .select("id")
      .maybeSingle();
    if (recoveryError || !recovered) {
      return json(409, {
        error: "request_recovery_conflict",
        request_id: request.id,
        support_id: supportID,
      });
    }
    request = {
      ...request,
      status: "pending",
      attempt_count: recoveredAttemptCount,
    };
  }

  if (request.status !== "pending") {
    return json(409, {
      error: "request_not_processable",
      status: request.status,
      request_id: request.id,
      support_id: supportID,
    });
  }

  if (
    (!request.user_id && !request.target_user_hash) ||
    (request.user_id && request.target_user_id &&
      request.target_user_id !== request.user_id)
  ) {
    return json(409, {
      error: "target_user_mismatch",
      message: "Deletion request target does not match the requesting user.",
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

  const processedBy = cleanText(
    body.processed_by,
    "edge:function:account-deletion-complete",
  );
  const targetEmail = request.target_email ?? request.email ?? null;
  const targetHash = await sha256Hex(targetUserID);

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

  const processingPatch: Record<string, unknown> = {
    status: "processing",
    processed_by: processedBy,
    completion_support_id: supportID,
    completion_error: null,
    target_user_id: targetUserID,
    target_email: targetEmail,
    target_user_hash: targetHash,
    processing_started_at: now,
    last_attempt_at: now,
    last_error_code: null,
    next_attempt_at: null,
    updated_at: now,
  };

  const { data: claimedRequest, error: processingError } = await supabase
    .from("account_deletion_requests")
    .update(processingPatch)
    .eq("id", request.id)
    .eq("status", "pending")
    .select("id")
    .maybeSingle();

  if (processingError) {
    return json(500, {
      error: "request_lock_failed",
      request_id: request.id,
      support_id: supportID,
    });
  }
  if (!claimedRequest) {
    return json(409, {
      error: "request_claim_conflict",
      request_id: request.id,
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

    const { data: authLookup, error: authLookupError } = await supabase.auth
      .admin
      .getUserById(targetUserID);
    const lookupStatus = Number(
      (authLookupError as { status?: number } | null)?.status ?? 0,
    );
    if (authLookupError && lookupStatus !== 404) {
      throw new Error(`auth_lookup_failed:${authLookupError.message}`);
    }
    if (authLookup?.user) {
      const { error: authDeleteError } = await supabase.auth.admin.deleteUser(
        targetUserID,
      );
      if (authDeleteError) {
        throw new Error(`auth_delete_failed:${authDeleteError.message}`);
      }
    }

    const completedAt = new Date().toISOString();
    const { data: completedRequest, error: completeError } = await supabase
      .from("account_deletion_requests")
      .update({
        status: "completed",
        completed_at: completedAt,
        completion_support_id: supportID,
        completion_error: null,
        last_error_code: null,
        next_attempt_at: null,
        deleted_photo_objects: removed.photos ?? 0,
        deleted_report_objects: removed.reports ?? 0,
        deleted_logo_objects: removed.logos ?? 0,
        deleted_avatar_objects: removed.avatars ?? 0,
        auth_user_deleted: true,
        user_id: null,
        email: null,
        target_user_id: null,
        target_email: null,
        updated_at: completedAt,
      })
      .eq("id", request.id)
      .eq("status", "processing")
      .eq("completion_support_id", supportID)
      .select("id")
      .maybeSingle();

    if (completeError || !completedRequest) {
      throw new Error(
        `request_complete_update_failed:${
          completeError?.message ?? "claim_lost"
        }`,
      );
    }

    await sendCompletionEmail(targetEmail, supportID);

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
    const failureCode = safeErrorCode(error);
    const attemptCount = Math.min((request.attempt_count ?? 0) + 1, 10);
    const retryDelayMinutes = Math.min(15 * 2 ** (attemptCount - 1), 360);
    const nextAttemptAt = new Date(
      Date.now() + retryDelayMinutes * 60 * 1000,
    ).toISOString();
    await supabase
      .from("account_deletion_requests")
      .update({
        status: "pending",
        completion_error: failureCode,
        completion_support_id: supportID,
        attempt_count: attemptCount,
        last_attempt_at: failedAt,
        last_error_code: failureCode,
        next_attempt_at: nextAttemptAt,
        updated_at: failedAt,
      })
      .eq("id", request.id)
      .eq("status", "processing")
      .eq("completion_support_id", supportID);

    return json(500, {
      error: "account_deletion_failed",
      failure_code: failureCode,
      request_id: request.id,
      support_id: supportID,
    });
  }
});
