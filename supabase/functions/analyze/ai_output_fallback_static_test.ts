import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const analyzeSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const flagsMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260821100156_ai_output_contract_rollout_flags.sql",
    import.meta.url,
  ),
);
const quotaMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260821100205_deterministic_fallback_quota_settlement.sql",
    import.meta.url,
  ),
);

Deno.test("AI output policy flags provide shadow, allowlist and kill-switch control", () => {
  assertStringIncludes(analyzeSource, '"ai_output_certainty_policy_v2"');
  assertStringIncludes(
    analyzeSource,
    '"ai_output_deterministic_fallback_v1"',
  );
  assertStringIncludes(analyzeSource, "type AIOutputPolicyRolloutMode");
  for (const mode of ['"off"', '"shadow"', '"allowlist"', '"on"']) {
    assertStringIncludes(analyzeSource, mode);
  }
  assertStringIncludes(
    analyzeSource,
    '!killSwitch && rolloutMode === "shadow"',
  );
  assertStringIncludes(analyzeSource, "enabledHashes.includes(userHash)");
  assertStringIncludes(flagsMigration, "'kill_switch', false");
  assertEquals(
    (flagsMigration.match(/'rollout_mode', 'on'/g) ?? []).length,
    2,
  );
});

Deno.test("analyze records policy, repair and deterministic fallback telemetry", () => {
  for (
    const field of [
      "certainty_policy_mode",
      "certainty_policy_shadow_candidate_violations",
      "repair_transport_failed",
      "repair_transport_error_class",
      "repair_integrity_check_passed",
      "deterministic_fallback_used",
      "deterministic_fallback_code",
      "deterministic_fallback_paths",
      "deterministic_fallback_removed_findings_count",
      "deterministic_fallback_zero_findings",
      "analysis_quota_consumed",
    ]
  ) {
    assertStringIncludes(analyzeSource, field);
  }
  assertStringIncludes(analyzeSource, 'certaintyPolicy: "v2"');
  assertStringIncludes(analyzeSource, "validateAIOutputContract(");
  assertStringIncludes(analyzeSource, "enforceRepairIntegrity:");
  assertStringIncludes(
    analyzeSource,
    "!deterministicFallbackUsed",
  );
});

Deno.test("zero-finding fallback quota settlement is strict and atomic", () => {
  const strictReleaseIndex = analyzeSource.indexOf(
    "await releaseAnalysisQuotaStrict(supabase, analysisID, user.id)",
  );
  const completionUpdateIndex = analyzeSource.indexOf(
    "const { error: completionUpdateError } = await updateOwnedAnalysis",
  );
  assert(strictReleaseIndex > 0);
  assert(completionUpdateIndex > strictReleaseIndex);
  assertStringIncludes(analyzeSource, "consume_analysis_quota:");
  assertStringIncludes(
    quotaMigration,
    "v_inserted = 0",
  );
  assertStringIncludes(
    quotaMigration,
    "deterministic_fallback_used",
  );
  assertStringIncludes(
    quotaMigration,
    "deterministic_fallback_zero_findings",
  );
  assertStringIncludes(quotaMigration, "delete from public.usage_events");
  assertStringIncludes(quotaMigration, "set event_type = 'completed'");
  assertStringIncludes(quotaMigration, "'quota_consumed'");
});
