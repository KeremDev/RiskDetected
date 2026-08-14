import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  validateCanaryResultDocument,
  validateNativeReview,
} from "../../../scripts/ai_localization_canary_result_contract.mjs";
import {
  safetyProfiles,
} from "../_shared/generated/safety-profiles.generated.ts";

const manifest = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../../../docs/localization/phase-4/canary/CANARY_CORPUS_MANIFEST_2026-07-28.json",
      import.meta.url,
    ),
  ),
);
const manifestSHA256 = "a".repeat(64);
const approvedManifest = {
  ...manifest,
  review: {
    ...manifest.review,
    reviewer_name: "Reviewer",
    reviewed_at: "2026-07-29T10:00:00Z",
    decision: "approved",
  },
};
const pendingReview = {
  ...manifest.review,
  reviewer_name: null,
  reviewed_at: null,
  decision: "pending",
};

function resultDocument(matrix: "smoke" | "full" = "smoke") {
  const scenarios = manifest.scenarios.filter(
    (scenario: { matrix: string }) =>
      matrix === "full" || scenario.matrix === "smoke",
  );
  const results = safetyProfiles.flatMap((profile) =>
    scenarios.map((scenario: { id: string }) => ({
      profile_id: profile.id,
      profile_version: profile.profile_version,
      output_language: profile.language,
      output_locale: profile.content_locale,
      prompt_contract_version: "ai-localization-contract-v1",
      scenario_id: scenario.id,
      provider: "gemini",
      model: "gemini-test",
      status: "passed",
      validation_status: "passed",
      validation_attempts: 1,
      validation_code: null,
      validation_detail_code: null,
      semantic_code: null,
      semantic_hazard_count: 1,
      semantic_field_verification_hazard_count: 0,
      provider_http_status: null,
      provider_request_count: 1,
      provider_transient_retry_count: 0,
      input_tokens: 10,
      output_tokens: 20,
      duration_ms: 30,
    }))
  );
  return {
    mode: "live",
    corpus_id: manifest.corpus_id,
    manifest_sha256: manifestSHA256,
    asset_count: manifest.assets.length,
    scenario_count: scenarios.length,
    profile_count: safetyProfiles.length,
    planned_requests: results.length,
    planned_max_provider_requests: results.length * 5,
    max_initial_transient_retries: 3,
    matrix,
    native_review_decision: "approved",
    content_logging: false,
    exact_source_photo_coverage_validation: true,
    integrity: "passed",
    provider: "gemini",
    model: "gemini-test",
    passed: results.length,
    failed: 0,
    results,
  };
}

Deno.test("native review gate requires approved role, identity and date", () => {
  assertEquals(
    validateNativeReview(pendingReview).code,
    "CANARY_NATIVE_REVIEW_PENDING",
  );
  assertEquals(
    validateNativeReview({
      ...pendingReview,
      decision: "approved",
    }).code,
    "CANARY_NATIVE_REVIEW_IDENTITY_MISSING",
  );
  assertEquals(
    validateNativeReview({
      ...pendingReview,
      decision: "approved",
      reviewer_name: "Reviewer",
      reviewed_at: "not-a-date",
    }).code,
    "CANARY_NATIVE_REVIEW_DATE_INVALID",
  );
  assertEquals(
    validateNativeReview({
      ...pendingReview,
      decision: "approved",
      reviewer_name: "Reviewer",
      reviewed_at: "2026-07-29T10:00:00Z",
    }).ok,
    true,
  );
});

Deno.test("complete metadata-only smoke result satisfies the closure contract", () => {
  const validation = validateCanaryResultDocument({
    document: resultDocument(),
    manifest: approvedManifest,
    manifestSHA256,
    profiles: safetyProfiles,
    matrix: "smoke",
  });
  assertEquals(validation.ok, true);
  assertEquals(validation.details?.expected_pairs, 12);
});

Deno.test("complete metadata-only full result proves all 84 pairs", () => {
  const validation = validateCanaryResultDocument({
    document: resultDocument("full"),
    manifest: approvedManifest,
    manifestSHA256,
    profiles: safetyProfiles,
    matrix: "full",
  });
  assertEquals(validation.ok, true);
  assertEquals(validation.details?.expected_pairs, 84);
});

Deno.test("initial transient retry is separate from validation repair", () => {
  const retried = resultDocument();
  retried.results[0].provider_request_count = 2;
  retried.results[0].provider_transient_retry_count = 1;
  retried.results[0].validation_attempts = 1;
  const validation = validateCanaryResultDocument({
    document: retried,
    manifest: approvedManifest,
    manifestSHA256,
    profiles: safetyProfiles,
    matrix: "smoke",
  });
  assertEquals(validation.ok, true);
});

Deno.test("two initial transient retries still preserve one repair request", () => {
  const retriedAndRepaired = resultDocument();
  retriedAndRepaired.results[0].provider_request_count = 4;
  retriedAndRepaired.results[0].provider_transient_retry_count = 2;
  retriedAndRepaired.results[0].validation_attempts = 2;
  retriedAndRepaired.results[0].validation_status = "repaired";
  retriedAndRepaired.results[0].validation_code =
    "SAFETY_PROFILE_REQUIRED_TERMINOLOGY_MISSING";
  const validation = validateCanaryResultDocument({
    document: retriedAndRepaired,
    manifest: approvedManifest,
    manifestSHA256,
    profiles: safetyProfiles,
    matrix: "smoke",
  });
  assertEquals(validation.ok, true);
});

Deno.test("three initial transient retries still preserve one repair request", () => {
  const retriedAndRepaired = resultDocument();
  retriedAndRepaired.results[0].provider_request_count = 5;
  retriedAndRepaired.results[0].provider_transient_retry_count = 3;
  retriedAndRepaired.results[0].validation_attempts = 2;
  retriedAndRepaired.results[0].validation_status = "repaired";
  retriedAndRepaired.results[0].validation_code =
    "SAFETY_PROFILE_REQUIRED_TERMINOLOGY_MISSING";
  const validation = validateCanaryResultDocument({
    document: retriedAndRepaired,
    manifest: approvedManifest,
    manifestSHA256,
    profiles: safetyProfiles,
    matrix: "smoke",
  });
  assertEquals(validation.ok, true);
});

Deno.test("missing or duplicated profile-scenario pairs fail closed", () => {
  const missing = resultDocument();
  missing.results.pop();
  assertEquals(
    validateCanaryResultDocument({
      document: missing,
      manifest: approvedManifest,
      manifestSHA256,
      profiles: safetyProfiles,
      matrix: "smoke",
    }).code,
    "CANARY_RESULT_COUNT_MISMATCH",
  );

  const duplicate = resultDocument();
  duplicate.results[1] = structuredClone(duplicate.results[0]);
  assertEquals(
    validateCanaryResultDocument({
      document: duplicate,
      manifest: approvedManifest,
      manifestSHA256,
      profiles: safetyProfiles,
      matrix: "smoke",
    }).code,
    "CANARY_RESULT_PAIR_DUPLICATE",
  );
});

Deno.test("failed pair and forbidden content fields cannot prove closure", () => {
  const failed = resultDocument();
  failed.results[0].status = "failed";
  failed.passed -= 1;
  failed.failed = 1;
  assertEquals(
    validateCanaryResultDocument({
      document: failed,
      manifest: approvedManifest,
      manifestSHA256,
      profiles: safetyProfiles,
      matrix: "smoke",
    }).code,
    "CANARY_RESULT_PAIR_FAILED",
  );

  const contentLeak = resultDocument();
  contentLeak.results[0].raw_response = "must never be stored";
  assertEquals(
    validateCanaryResultDocument({
      document: contentLeak,
      manifest: approvedManifest,
      manifestSHA256,
      profiles: safetyProfiles,
      matrix: "smoke",
    }).code,
    "CANARY_RESULT_CONTENT_FIELD_FORBIDDEN",
  );
});

Deno.test("semantic metadata is bounded and internally consistent", () => {
  const invalid = resultDocument();
  invalid.results[0].semantic_hazard_count = 0;
  invalid.results[0].semantic_field_verification_hazard_count = 1;
  assertEquals(
    validateCanaryResultDocument({
      document: invalid,
      manifest: approvedManifest,
      manifestSHA256,
      profiles: safetyProfiles,
      matrix: "smoke",
    }).code,
    "CANARY_RESULT_SEMANTIC_METADATA_INVALID",
  );
});
