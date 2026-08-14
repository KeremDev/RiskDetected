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

Deno.test("pipeline v2 submit and claim happen before worker AI execution", async () => {
  const analyze = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  const worker = await readTextIfAllowed(
    new URL("../process-analysis-jobs/index.ts", import.meta.url),
  );
  if (analyze == null || worker == null) return;

  assertStringIncludes(analyze, '"submit_analysis_job_v2"');
  assertStringIncludes(analyze, '"validate_analysis_job_claim_v2"');
  assertStringIncludes(analyze, '"finalize_analysis_result_v2"');
  assertStringIncludes(worker, '"claim_analysis_job_v2"');

  const claim = worker.indexOf('"claim_analysis_job_v2"');
  const invoke = worker.indexOf("/functions/v1/analyze", claim);
  assert(claim > 0 && invoke > claim);
  assertStringIncludes(worker, 'claimState === "busy"');
  assertStringIncludes(worker, '"superseded"');
  assertStringIncludes(worker, '"defer_analysis_job_message_v2"');
  assertStringIncludes(analyze, '.eq("status", "pending")');
  assertStringIncludes(
    analyze,
    "Analyze enqueue error ignored after concurrent submit won",
  );
});

Deno.test("pipeline v2 terminal writes and repair transitions are claim guarded", async () => {
  const analyze = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (analyze == null) return;

  assertStringIncludes(analyze, '"record_analysis_job_failure_v2"');
  assertStringIncludes(analyze, '"transition_analysis_to_repair_v2"');
  assertStringIncludes(analyze, "__worker_claim_token");
  assertStringIncludes(analyze, "__queue_msg_id");
  assertStringIncludes(analyze, "__job_generation");

  const v2Finalization = analyze.indexOf('"finalize_analysis_result_v2"');
  const legacyFindingInsert = analyze.indexOf(
    "!isPipelineV2Worker && findingRows.length > 0",
  );
  assert(v2Finalization > 0 && legacyFindingInsert > 0);
});

Deno.test("AI success telemetry is pending before persistence and later resolved", async () => {
  const analyze = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (analyze == null) return;

  const pending = analyze.indexOf('persistence_outcome: "pending"');
  const finalization = analyze.indexOf(
    '"finalize_analysis_result_v2"',
    pending,
  );
  assert(pending > 0 && finalization > pending);
  assertStringIncludes(analyze, '"persisted"');
  assertStringIncludes(analyze, '"discarded"');
  assertStringIncludes(analyze, '"analysis_finalization_failed"');
  assertEquals(
    analyze.slice(finalization).includes('persistence_outcome: "pending"'),
    false,
  );
});

Deno.test("pipeline v2 migration is additive, private, and service-role only", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260720100545_analysis_pipeline_v2_hardening.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const sql = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(
    sql,
    "create table if not exists private.analysis_job_state",
  );
  assertStringIncludes(
    sql,
    "create or replace function public.submit_analysis_job_v2",
  );
  assertStringIncludes(
    sql,
    "create or replace function public.claim_analysis_job_v2",
  );
  assertStringIncludes(
    sql,
    "create or replace function public.finalize_analysis_result_v2",
  );
  assertStringIncludes(sql, "set search_path = ''");
  assertStringIncludes(sql, "from public, anon, authenticated");
  assertStringIncludes(sql, "to service_role");
  assertStringIncludes(sql, "completed_analysis_status_is_terminal");
  assertStringIncludes(sql, "persistence_outcome");
  assertStringIncludes(sql, "'rollout_mode', 'off'");
  assertStringIncludes(sql, "on conflict (key) do nothing");
});

Deno.test("pipeline v2 keeps cancelled trial provider isolation untouched", async () => {
  const analyze = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (analyze == null) return;
  const freeRoute = analyze.indexOf(
    "if (usesFreeGeminiProviderPool(aiExecutionRoute))",
  );
  const paidTrialRoute = analyze.indexOf(
    'if (aiExecutionRoute === "free_paid_trial")',
    freeRoute,
  );
  const branch = analyze.slice(freeRoute, paidTrialRoute);
  assertStringIncludes(branch, "callAIWithFreeProviderPool(");
  assertEquals(branch.includes("callPaidAIWithFallback("), false);
});
