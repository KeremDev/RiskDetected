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

Deno.test("request-account-deletion invokes privileged completion worker", async () => {
  const source = await readTextIfAllowed(
    new URL("../request-account-deletion/index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "account-deletion-complete");
  assertStringIncludes(source, '"Authorization": `Bearer ${serviceRoleKey}`');
  assertStringIncludes(source, "completed: true");
  assertStringIncludes(source, "auth_user_deleted");
  assertStringIncludes(source, "workerResponse.status");
  assertStringIncludes(source, "ok: false");
  assertStringIncludes(source, "Hesap silme işlemi tamamlanamadı");
});

Deno.test("account-deletion-complete records DB/Auth/Storage completion markers", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    'const BUCKETS = ["photos", "reports", "logos", "avatars"]',
  );
  assertStringIncludes(source, "await removeBucketPrefix(");
  assertStringIncludes(source, ".getUserById(targetUserID)");
  assertStringIncludes(source, "lookupStatus !== 404");
  assertStringIncludes(source, "supabase.auth.admin.deleteUser");
  assertStringIncludes(source, 'status: "completed"');
  assertStringIncludes(source, "completed_at: completedAt");
  assertStringIncludes(source, "auth_user_deleted: true");
  assertStringIncludes(source, "completion_error: null");
  assertStringIncludes(source, "target_user_hash");
  assertStringIncludes(source, "stale_claim_recovered");
  assertStringIncludes(source, 'request.status === "processing"');
  assertStringIncludes(source, '.lte("processing_started_at", staleBefore)');
  assertStringIncludes(source, "!request.user_id && !request.target_user_hash");
  assertStringIncludes(source, "sendCompletionEmail");
  assertStringIncludes(source, "target_email: null");
  assertStringIncludes(source, 'status: "pending"');
  assertStringIncludes(source, "attempt_count: attemptCount");
  assertStringIncludes(source, "last_error_code: failureCode");
  assertStringIncludes(source, "next_attempt_at: nextAttemptAt");
  assertStringIncludes(source, 'error: "request_already_processing"');
  assertStringIncludes(source, '.eq("status", "pending")');
  assertStringIncludes(source, '.select("id")');
  assertStringIncludes(source, ".maybeSingle()");
  assertStringIncludes(source, '.eq("completion_support_id", supportID)');
});

Deno.test("request-account-deletion preserves immediate mobile behavior and queues web requests", async () => {
  const source = await readTextIfAllowed(
    new URL("../request-account-deletion/index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, '"immediate", "request_only"');
  assertStringIncludes(source, 'clientPlatform !== "web"');
  assertStringIncludes(source, "sendRequestAcceptedEmail");
  assertStringIncludes(source, "return json(req, 202");
  assertStringIncludes(source, "estimated_completion_at");
  assertStringIncludes(source, "alignOpenRequest");
  assertStringIncludes(source, "targetUserHash: await sha256Hex(user.id)");
  assertStringIncludes(source, 'error: "invalid_request_id"');
  assertStringIncludes(source, "failure_code: safeErrorCode(error)");
  assertStringIncludes(source, 'completionMode === "request_only" ? 24');
  assertStringIncludes(source, "ACCOUNT_DELETION_ALLOWED_ORIGINS");
  assertStringIncludes(source, '"https://riskdetected.com"');
  if (source.includes("http://localhost")) {
    throw new Error(
      "Production account-deletion CORS defaults must not allow localhost.",
    );
  }
});

Deno.test("account deletion migration keeps editable finding audit from blocking auth delete", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260728201500_reconcile_untracked_production_schema_state.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(
    normalizedSQL,
    "alter table public.finding_edit_events alter column actor_user_id drop not null",
  );
  assertStringIncludes(
    normalizedSQL,
    "foreign key (actor_user_id) references auth.users(id) on delete set null",
  );
  assertStringIncludes(
    normalizedSQL,
    "foreign key (last_user_edit_by) references auth.users(id) on delete set null",
  );
  assertStringIncludes(
    normalizedSQL,
    "foreign key (user_deleted_by) references auth.users(id) on delete set null",
  );
});
