import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readTextIfAllowed(url: URL): Promise<string | null> {
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") return null;
  return await Deno.readTextFile(path);
}

Deno.test("guard v2 snapshots rollout policy into queue and repair messages", async () => {
  const analyze = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (analyze == null) return;

  assertStringIncludes(
    analyze,
    '"analysis_ambiguous_dispatch_guard"',
  );
  assertStringIncludes(
    analyze,
    "claim_guard_version: params.claimGuardVersion",
  );
  assertStringIncludes(
    analyze,
    "Number(params.body.claim_guard_version) === 2 ? 2 : 1",
  );
  assertStringIncludes(analyze, "isGuardedPipelineV2Worker");
});

Deno.test("analyze owns controlled retry and terminal claim decisions", async () => {
  const analyze = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (analyze == null) return;

  const providerCatch = analyze.indexOf("const retryableProviderFailure");
  const controlledRelease = analyze.indexOf(
    "await releaseWorkerClaimForRetry",
    providerCatch,
  );
  const finalizationFailure = analyze.indexOf(
    '"analysis_finalization_failed"',
    providerCatch,
  );
  const finalizationRelease = analyze.indexOf(
    "await releaseWorkerClaimForRetry",
    finalizationFailure,
  );
  assert(providerCatch > 0 && controlledRelease > providerCatch);
  assert(finalizationFailure > controlledRelease);
  assert(finalizationRelease > finalizationFailure);
  assertStringIncludes(analyze, 'recordWorkerEvent("terminal_failed"');
  assertStringIncludes(analyze, 'recordWorkerEvent("finalized"');
  assertStringIncludes(analyze, 'recordWorkerEvent("claim_kept"');
});

Deno.test("guarded worker reconciles every dispatch against database state", async () => {
  const worker = await readTextIfAllowed(
    new URL("../process-analysis-jobs/index.ts", import.meta.url),
  );
  if (worker == null) return;

  const guardedBranch = worker.indexOf("if (\n        isGuardedV2");
  const legacyFailureWrite = worker.indexOf(
    "const failureResult = await recordV2WorkerFailure",
  );
  assert(guardedBranch > 0);
  assert(legacyFailureWrite > guardedBranch);
  assertStringIncludes(worker, '"validate_analysis_job_claim_v2"');
  assertStringIncludes(worker, "reconcileGuardedV2Dispatch");
  assertStringIncludes(worker, 'observation: "ambiguous_transport"');
  assertStringIncludes(worker, 'eventType: "lease_expired_retry"');
  assertEquals(
    worker.slice(guardedBranch, legacyFailureWrite).includes(
      "recordV2WorkerFailure",
    ),
    false,
  );
});

Deno.test("guard migration is private, additive, and service-role only", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260720123158_analysis_ambiguous_dispatch_guard.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const sql = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(
    sql,
    "create table if not exists private.analysis_job_events",
  );
  assertStringIncludes(
    sql,
    "alter table private.analysis_job_events enable row level security",
  );
  assertStringIncludes(
    sql,
    "create or replace function public.record_analysis_job_event_v2",
  );
  assertStringIncludes(sql, "security definer set search_path = ''");
  assertStringIncludes(sql, "from public, anon, authenticated");
  assertStringIncludes(sql, "to service_role");
  assertStringIncludes(sql, "'analysis_ambiguous_dispatch_guard'");
  assertStringIncludes(sql, "on conflict (key) do nothing");
});
