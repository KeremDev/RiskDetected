import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const manifestURL = new URL(
  "../../../docs/localization/phase-4/canary/CANARY_CORPUS_MANIFEST_2026-07-28.json",
  import.meta.url,
);
const manifest = JSON.parse(await Deno.readTextFile(manifestURL));
const runner = await Deno.readTextFile(
  new URL("../../../scripts/run_ai_localization_canary.mjs", import.meta.url),
);
const geminiProviderClient = await Deno.readTextFile(
  new URL("../_shared/gemini-provider-client.ts", import.meta.url),
);
const keychainRunner = await Deno.readTextFile(
  new URL(
    "../../../scripts/run_ai_localization_canary_from_keychain.sh",
    import.meta.url,
  ),
);

function hex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("synthetic canary corpus covers all required scene categories", () => {
  assertEquals(manifest.content_policy.synthetic_only, true);
  assertEquals(manifest.content_policy.real_user_content, false);
  assertEquals(manifest.content_policy.real_company_content, false);
  assertEquals(
    manifest.content_policy.prompt_or_response_content_may_be_logged,
    false,
  );
  assertEquals(manifest.assets.length, 13);
  assertEquals(manifest.scenarios.length, 14);
  assertEquals(manifest.live_matrix.profiles.length, 6);
  assertEquals(
    manifest.live_matrix.required_completion
      .smoke_profile_scenario_pairs,
    12,
  );
  assertEquals(
    manifest.live_matrix.required_completion.full_profile_scenario_pairs,
    84,
  );
  assertEquals(
    manifest.live_matrix.required_completion
      .max_provider_requests_per_pair,
    2,
  );
  assertEquals(
    manifest.live_matrix.required_completion
      .exact_source_photo_coverage_validation,
    true,
  );
  assertEquals(manifest.review.decision, "approved");
  assertEquals(manifest.review.reviewer_name, "Kerem");
  assertEquals(
    manifest.content_policy.review_status,
    "native_reviewer_approved",
  );

  const scenarioIDs = new Set(
    manifest.scenarios.map((scenario: { id: string }) => scenario.id),
  );
  for (
    const required of [
      "single_work_at_height",
      "single_electrical_panel",
      "single_machine_guarding",
      "single_forklift_pedestrian",
      "single_chemical_container",
      "single_ppe",
      "single_fire_access",
      "single_housekeeping",
      "single_manual_handling",
      "single_clean",
      "single_low_quality",
      "multi_same_hazard",
      "multi_independent_hazards",
      "single_visible_prompt_injection",
    ]
  ) {
    assert(scenarioIDs.has(required), required);
  }
});

Deno.test("canary runtime assets match immutable checksums and bounds", async () => {
  const manifestDirectory = new URL("./", manifestURL);
  for (
    const asset of manifest.assets as Array<{
      id: string;
      file: string;
      sha256: string;
      bytes: number;
    }>
  ) {
    const bytes = await Deno.readFile(new URL(asset.file, manifestDirectory));
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    assertEquals(bytes.byteLength, asset.bytes, asset.id);
    assertEquals(hex(digest), asset.sha256, asset.id);
    assert(bytes.byteLength < 1_500_000, asset.id);
  }
});

Deno.test("live canary runner records metadata only and requires explicit approval", () => {
  assertStringIncludes(runner, "validateNativeReview(manifest.review)");
  assertStringIncludes(runner, "validateCanaryResultDocument");
  assertStringIncludes(runner, "validateAIOutputWithSingleRepair");
  assertStringIncludes(runner, "buildLanguageContractRepairInstruction");
  assertStringIncludes(runner, "provider_request_count");
  assertStringIncludes(runner, "provider_http_status");
  assertStringIncludes(runner, "provider_transient_retry_count");
  assertStringIncludes(runner, "validation_detail_code");
  assertStringIncludes(runner, "providerValidationDetailCode");
  assertStringIncludes(runner, "RISKDETECTED_CANARY_INTER_PAIR_DELAY_MS");
  assertStringIncludes(
    runner,
    "RISKDETECTED_CANARY_TRANSIENT_RETRY_DELAY_MS",
  );
  assertStringIncludes(runner, "maxInitialTransientRetries = 3");
  assertStringIncludes(runner, "transientRetryLimit: 0");
  assertStringIncludes(runner, "productionConfidenceFinding(");
  assertStringIncludes(runner, "productionFindingNeedsFieldVerification(");
  assertStringIncludes(runner, "CANARY_PROVIDER_REQUEST_BUDGET_EXHAUSTED");
  assertStringIncludes(runner, "CANARY_SOURCE_PHOTO_INDICES_MISSING");
  assertStringIncludes(runner, "CANARY_SOURCE_PHOTO_INDEX_INVALID");
  assertStringIncludes(runner, "normalizeSourcePhotoIndices(");
  assertStringIncludes(runner, "semantic_hazard_count");
  assertStringIncludes(runner, 'Deno.args.includes("--write-result")');
  assertStringIncludes(runner, "--probe-scenario=");
  assertStringIncludes(runner, "CANARY_PROBE_RESULT_WRITE_FORBIDDEN");
  assertStringIncludes(runner, "CANARY_PROBE_SCENARIO_UNKNOWN");
  assertStringIncludes(
    runner,
    "docs/localization/phase-4/canary/results/",
  );
  assertStringIncludes(runner, "CANARY_ACTIONABLE_PHOTO_COVERAGE_MISSING");
  assertStringIncludes(runner, "planned_max_provider_requests");
  assertStringIncludes(runner, "exact_source_photo_coverage_validation");
  assertStringIncludes(runner, "manifest_sha256");
  assertStringIncludes(runner, "prompt_contract_version");
  assertStringIncludes(runner, "sendGeminiGenerateContent");
  assertStringIncludes(
    geminiProviderClient,
    '"x-goog-api-key": request.apiKey',
  );
  assertStringIncludes(geminiProviderClient, "fetchWithDeadline(");
  assertEquals(runner.includes(":generateContent?key="), false);
  assertEquals(geminiProviderClient.includes(":generateContent?key="), false);
  assertEquals(runner.includes("console.log(text)"), false);
  assertEquals(runner.includes("console.log(prompt)"), false);
  assertEquals(runner.includes("raw_response"), false);
  assertEquals(runner.includes("response_content"), false);
  assertEquals(runner.includes("--output="), false);
});

Deno.test("Keychain canary wrapper injects the provider key without logging it", () => {
  assertStringIncludes(
    keychainRunner,
    'keychain_service="riskdetected_gemini_api_key_canary"',
  );
  assertStringIncludes(
    keychainRunner,
    "security find-generic-password",
  );
  assertStringIncludes(
    keychainRunner,
    'export GEMINI_API_KEY="$gemini_canary_key"',
  );
  assertStringIncludes(
    keychainRunner,
    'exec "$(dirname "$0")/run_ai_localization_canary.mjs" "$@"',
  );
  assertEquals(keychainRunner.includes("set -x"), false);
  assertEquals(keychainRunner.includes("echo $gemini_canary_key"), false);
  assertEquals(keychainRunner.includes("print $gemini_canary_key"), false);
});
