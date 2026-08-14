import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

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

Deno.test("sync-revenuecat-subscription preserves active test overrides before RevenueCat lookup", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  const overrideLookupIndex = source.indexOf(
    "activeSubscriptionTestOverride(supabase, user.id)",
  );
  const revenueCatLookupIndex = source.indexOf("https://api.revenuecat.com");

  assert(overrideLookupIndex > 0);
  assert(revenueCatLookupIndex > 0);
  assert(overrideLookupIndex < revenueCatLookupIndex);
  assertStringIncludes(source, '.from("subscription_test_overrides")');
  assertStringIncludes(source, '.is("revoked_at", null)');
  assertStringIncludes(source, '.gt("expires_at", now)');
  assertStringIncludes(source, 'source: "test_override"');
  assertStringIncludes(source, "test_override: true");
  assertStringIncludes(source, "test_override_expired");
});

Deno.test("subscription test override migration is service-role only and time bounded", async () => {
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
    "create table if not exists public.subscription_test_overrides",
  );
  assertStringIncludes(
    normalizedSQL,
    "references auth.users(id) on delete cascade",
  );
  assertStringIncludes(normalizedSQL, "check (tier in ('plus', 'pro'))");
  assertStringIncludes(normalizedSQL, "check (expires_at > starts_at)");
  assertStringIncludes(
    normalizedSQL,
    "alter table public.subscription_test_overrides enable row level security",
  );
  assertStringIncludes(
    normalizedSQL,
    "revoke all on table public.subscription_test_overrides from anon, authenticated",
  );
  assertStringIncludes(
    normalizedSQL,
    "grant select, insert, update, delete on table public.subscription_test_overrides to service_role",
  );
});

Deno.test("free RevenueCat sync clears stale test and trial metadata", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  const freeWriterStart = source.indexOf(
    "async function writeFreeSubscriptionState",
  );
  const overrideLookupStart = source.indexOf(
    "async function activeSubscriptionTestOverride",
    freeWriterStart,
  );
  assert(freeWriterStart > 0 && overrideLookupStart > freeWriterStart);
  const freeWriter = source.slice(freeWriterStart, overrideLookupStart);
  assertStringIncludes(freeWriter, "environment: null");
  assertStringIncludes(freeWriter, "...clearTrialReminderMetadataPatch()");
});

Deno.test("passive RevenueCat sync updates only matching active Plus trial metadata", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "canPassivelySyncPlusTrialMetadata(");
  assertStringIncludes(source, "verifiedTrialMetadataPatch({");
  assertStringIncludes(source, "renewal_intent_synced: true");
  assertStringIncludes(
    source,
    "previous.entitlement_id !== resolved.entitlementID",
  );
  assertStringIncludes(
    source,
    "!timestampsMatch(previous.current_period_ends_at, resolved.expiration)",
  );

  const passiveStart = source.indexOf("if (!expectedTier) {");
  const mismatchStart = source.indexOf(
    "if (expectedTier && expectedTier !== resolved.tier)",
    passiveStart,
  );
  assert(passiveStart > 0 && mismatchStart > passiveStart);
  const passiveBlock = source.slice(passiveStart, mismatchStart);
  assertStringIncludes(passiveBlock, '.from("user_subscriptions")');
  assert(!passiveBlock.includes('.from("profiles")'));
  assert(!passiveBlock.includes('source: "revenuecat_sync"'));
});
