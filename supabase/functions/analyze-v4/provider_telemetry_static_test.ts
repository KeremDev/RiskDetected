import { assertStringIncludes } from "https://deno.land/std@0.208.0/testing/asserts.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260825113038_v4_provider_attempt_telemetry_v5.sql",
    import.meta.url,
  ),
);

Deno.test("v4 provider attempts fail closed and persist authoritative budgets", () => {
  assertStringIncludes(source, '"record_analysis_provider_attempt_v5"');
  assertStringIncludes(source, "data?.ok === true");
  assertStringIncludes(source, "v4_provider_telemetry_failed");
  assertStringIncludes(source, "p_prompt_sha256");
  assertStringIncludes(source, "p_prompt_bundle_sha256");
  assertStringIncludes(source, "p_max_output_tokens");
});

Deno.test("provider attempt v5 RPC is service-only and idempotent", () => {
  assertStringIncludes(
    migration,
    "create or replace function public.record_analysis_provider_attempt_v5",
  );
  assertStringIncludes(migration, "on conflict (id) do update");
  assertStringIncludes(
    migration,
    ") from public,anon,authenticated;",
  );
  assertStringIncludes(migration, ") to service_role;");
  assertStringIncludes(migration, "'reason_code','sqlstate_' || sqlstate");
});

Deno.test("targeted reinspection validates only its selected module", () => {
  assertStringIncludes(
    source,
    "group.candidates.map((candidate) => candidate.module_id)",
  );
  assertStringIncludes(source, "requiredModules: [");
  assertStringIncludes(source, "...new Set(");
});

Deno.test("coverage-only primary defects recover without a paid technical retry", () => {
  assertStringIncludes(
    source,
    "error.schemaIssues.length > 0 && error.recoverableOutput && error.usage",
  );
  if (
    source.includes(
      'spec.kind === "technical_retry" &&\n        error.schemaIssues.length > 0',
    )
  ) {
    throw new Error("coverage recovery is still restricted to technical retry");
  }
});
