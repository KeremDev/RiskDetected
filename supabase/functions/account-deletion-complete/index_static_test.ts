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
  assertStringIncludes(source, "supabase.auth.admin.deleteUser");
  assertStringIncludes(source, 'status: "completed"');
  assertStringIncludes(source, "completed_at: completedAt");
  assertStringIncludes(source, "auth_user_deleted: true");
  assertStringIncludes(source, "completion_error: null");
  assertStringIncludes(source, "target_user_hash");
  assertStringIncludes(source, 'status: "pending"');
  assertStringIncludes(source, "completion_error: message.slice(0, 1000)");
});

Deno.test("account deletion migration keeps editable finding audit from blocking auth delete", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260624194120_account_deletion_nullable_audit_user_refs.sql",
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
