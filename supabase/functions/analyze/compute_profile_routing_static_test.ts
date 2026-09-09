import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const analyzeSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const workerSource = await Deno.readTextFile(
  new URL("../process-analysis-jobs/index.ts", import.meta.url),
);
const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824134647_analysis_engine_vnext_compute_profiles_v24.sql",
    import.meta.url,
  ),
);

Deno.test("trusted compute route overwrites any client-supplied queue field", () => {
  const bodySpread = analyzeSource.indexOf("...queueSourceBody");
  const trustedField = analyzeSource.indexOf(
    "analysis_compute_routing: params.analysisComputeRouting",
  );
  assert(bodySpread >= 0 && trustedField > bodySpread);
  assertStringIncludes(analyzeSource, "buildTrustedAnalysisComputeRouting");
  assertStringIncludes(analyzeSource, "analysisComputeRouting,");
});

Deno.test("worker pins compute route through v5 with deploy-order fallback", () => {
  const v5 = workerSource.indexOf('"resolve_analysis_engine_route_v5"');
  const v4 = workerSource.indexOf('"resolve_analysis_engine_route_v4"', v5);
  assert(v5 >= 0 && v4 > v5);
  assertStringIncludes(workerSource, "p_client_routing");
  assertStringIncludes(workerSource, "p_compute_routing");
});

Deno.test("database route validates product plan and stores cost telemetry", () => {
  assertStringIncludes(migrationSource, "compute_route_plan_mismatch");
  assertStringIncludes(
    migrationSource,
    "trusted_compute_route_snapshot_missing",
  );
  assertStringIncludes(migrationSource, "standard_equivalent_cost_usd");
  assertStringIncludes(migrationSource, "requested_service_tier");
  assertStringIncludes(migrationSource, "paid_flex_enabled");
});
