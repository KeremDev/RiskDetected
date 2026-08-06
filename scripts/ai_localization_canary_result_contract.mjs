const FORBIDDEN_CONTENT_KEYS = new Set([
  "prompt",
  "system_prompt",
  "analysis_context",
  "raw_response",
  "response_content",
  "image_base64",
  "base64",
  "user_text",
  "company_name",
  "result",
  "hazards",
]);

function failure(code, details = null) {
  return { ok: false, code, details };
}

export function validateNativeReview(review) {
  if (!review || typeof review !== "object") {
    return failure("CANARY_NATIVE_REVIEW_MISSING");
  }
  if (review.decision !== "approved") {
    return failure("CANARY_NATIVE_REVIEW_PENDING");
  }
  if (
    review.reviewer_role !== "native English workplace-safety reviewer"
  ) {
    return failure("CANARY_NATIVE_REVIEW_ROLE_INVALID");
  }
  if (
    typeof review.reviewer_name !== "string" ||
    review.reviewer_name.trim().length < 2 ||
    review.reviewer_name.trim().length > 120
  ) {
    return failure("CANARY_NATIVE_REVIEW_IDENTITY_MISSING");
  }
  if (
    typeof review.reviewed_at !== "string" ||
    !Number.isFinite(Date.parse(review.reviewed_at))
  ) {
    return failure("CANARY_NATIVE_REVIEW_DATE_INVALID");
  }
  return { ok: true, code: null, details: null };
}

function findForbiddenContentKey(value, path = "$") {
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      const found = findForbiddenContentKey(value[index], `${path}[${index}]`);
      if (found) return found;
    }
    return null;
  }
  if (!value || typeof value !== "object") return null;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_CONTENT_KEYS.has(key)) return `${path}.${key}`;
    const found = findForbiddenContentKey(child, `${path}.${key}`);
    if (found) return found;
  }
  return null;
}

export function validateCanaryResultDocument({
  document,
  manifest,
  manifestSHA256,
  profiles,
  matrix,
  requireAllPassed = true,
}) {
  if (!document || typeof document !== "object" || Array.isArray(document)) {
    return failure("CANARY_RESULT_ROOT_INVALID");
  }
  if (document.mode !== "live") {
    return failure("CANARY_RESULT_MODE_INVALID");
  }
  if (document.corpus_id !== manifest?.corpus_id) {
    return failure("CANARY_RESULT_CORPUS_MISMATCH");
  }
  const nativeReview = validateNativeReview(manifest?.review);
  if (!nativeReview.ok || document.native_review_decision !== "approved") {
    return failure(nativeReview.code ?? "CANARY_RESULT_NATIVE_REVIEW_MISMATCH");
  }
  if (matrix !== "smoke" && matrix !== "full") {
    return failure("CANARY_RESULT_MATRIX_INVALID");
  }
  if (document.matrix !== matrix) {
    return failure("CANARY_RESULT_MATRIX_MISMATCH");
  }
  if (
    !/^[a-f0-9]{64}$/u.test(String(document.manifest_sha256 ?? "")) ||
    document.manifest_sha256 !== manifestSHA256
  ) {
    return failure("CANARY_RESULT_MANIFEST_HASH_INVALID");
  }
  if (
    document.content_logging !== false ||
    document.exact_source_photo_coverage_validation !== true
  ) {
    return failure("CANARY_RESULT_PRIVACY_OR_COVERAGE_GUARD_MISSING");
  }
  const forbiddenPath = findForbiddenContentKey(document);
  if (forbiddenPath) {
    return failure("CANARY_RESULT_CONTENT_FIELD_FORBIDDEN", forbiddenPath);
  }

  const profileByID = new Map(
    profiles.map((profile) => [profile.id, profile]),
  );
  const expectedProfileIDs = manifest.live_matrix.profiles;
  const expectedScenarios = manifest.scenarios.filter((scenario) =>
    matrix === "full" || scenario.matrix === "smoke"
  );
  if (
    document.asset_count !== manifest.assets.length ||
    document.profile_count !== expectedProfileIDs.length ||
    document.scenario_count !== expectedScenarios.length ||
    document.integrity !== "passed"
  ) {
    return failure("CANARY_RESULT_PREFLIGHT_SUMMARY_MISMATCH");
  }
  const expectedPairs = new Set();
  for (const profileID of expectedProfileIDs) {
    if (!profileByID.has(profileID)) {
      return failure("CANARY_RESULT_PROFILE_MANIFEST_UNKNOWN", profileID);
    }
    for (const scenario of expectedScenarios) {
      expectedPairs.add(`${profileID}::${scenario.id}`);
    }
  }
  const expectedCount = expectedPairs.size;
  if (
    document.planned_requests !== expectedCount ||
    document.planned_max_provider_requests !== expectedCount * 5 ||
    document.max_initial_transient_retries !== 3
  ) {
    return failure("CANARY_RESULT_REQUEST_PLAN_MISMATCH");
  }
  if (
    !Array.isArray(document.results) ||
    document.results.length !== expectedCount
  ) {
    return failure("CANARY_RESULT_COUNT_MISMATCH", {
      expected: expectedCount,
      actual: Array.isArray(document.results) ? document.results.length : null,
    });
  }

  const observedPairs = new Set();
  for (const row of document.results) {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      return failure("CANARY_RESULT_ROW_INVALID");
    }
    const pair = `${row.profile_id}::${row.scenario_id}`;
    if (!expectedPairs.has(pair)) {
      return failure("CANARY_RESULT_PAIR_UNEXPECTED", pair);
    }
    if (observedPairs.has(pair)) {
      return failure("CANARY_RESULT_PAIR_DUPLICATE", pair);
    }
    observedPairs.add(pair);

    const profile = profileByID.get(row.profile_id);
    if (
      row.profile_version !== profile.profile_version ||
      row.output_language !== profile.language ||
      row.output_locale !== profile.content_locale
    ) {
      return failure("CANARY_RESULT_PROFILE_SNAPSHOT_MISMATCH", pair);
    }
    if (
      typeof row.prompt_contract_version !== "string" ||
      !row.prompt_contract_version
    ) {
      return failure("CANARY_RESULT_PROMPT_CONTRACT_MISSING", pair);
    }
    if (
      row.provider !== "gemini" ||
      document.provider !== row.provider ||
      typeof row.model !== "string" ||
      !row.model ||
      document.model !== row.model
    ) {
      return failure("CANARY_RESULT_PROVIDER_METADATA_INVALID", pair);
    }
    if (
      row.provider_http_status !== null &&
      (!Number.isInteger(row.provider_http_status) ||
        row.provider_http_status < 400 ||
        row.provider_http_status > 599)
    ) {
      return failure("CANARY_RESULT_PROVIDER_STATUS_INVALID", pair);
    }
    if (
      row.validation_detail_code !== null &&
      (typeof row.validation_detail_code !== "string" ||
        row.validation_detail_code.length === 0 ||
        row.validation_detail_code.length > 120)
    ) {
      return failure("CANARY_RESULT_VALIDATION_DETAIL_INVALID", pair);
    }
    if (
      row.status === "passed" &&
      (row.provider_http_status !== null ||
        row.validation_detail_code !== null)
    ) {
      return failure("CANARY_RESULT_PASSED_ERROR_METADATA_INVALID", pair);
    }
    if (
      row.validation_code === "CANARY_PROVIDER_ERROR" &&
      row.provider_http_status === null
    ) {
      return failure("CANARY_RESULT_PROVIDER_STATUS_MISSING", pair);
    }
    if (
      row.validation_code === "OUTPUT_LANGUAGE_CONTRACT_FAILED" &&
      typeof row.validation_detail_code !== "string"
    ) {
      return failure("CANARY_RESULT_VALIDATION_DETAIL_MISSING", pair);
    }
    if (
      !Number.isInteger(row.provider_request_count) ||
      row.provider_request_count < 1 ||
      row.provider_request_count > 5 ||
      ![1, 2].includes(row.validation_attempts)
    ) {
      return failure("CANARY_RESULT_ATTEMPT_COUNT_INVALID", pair);
    }
    if (
      !Number.isInteger(row.provider_transient_retry_count) ||
      row.provider_transient_retry_count < 0 ||
      row.provider_transient_retry_count > 3 ||
      row.provider_transient_retry_count >
        row.provider_request_count - 1
    ) {
      return failure("CANARY_RESULT_TRANSIENT_RETRY_COUNT_INVALID", pair);
    }
    if (
      row.provider_request_count !==
        row.validation_attempts + row.provider_transient_retry_count
    ) {
      return failure("CANARY_RESULT_ATTEMPT_COUNT_ORDER_INVALID", pair);
    }
    if (
      !Number.isFinite(row.input_tokens) ||
      row.input_tokens < 0 ||
      !Number.isFinite(row.output_tokens) ||
      row.output_tokens < 0 ||
      !Number.isFinite(row.duration_ms) ||
      row.duration_ms < 0
    ) {
      return failure("CANARY_RESULT_TELEMETRY_INVALID", pair);
    }
    if (
      row.semantic_hazard_count !== null &&
      (!Number.isInteger(row.semantic_hazard_count) ||
        row.semantic_hazard_count < 0 ||
        !Number.isInteger(row.semantic_field_verification_hazard_count) ||
        row.semantic_field_verification_hazard_count < 0 ||
        row.semantic_field_verification_hazard_count >
          row.semantic_hazard_count)
    ) {
      return failure("CANARY_RESULT_SEMANTIC_METADATA_INVALID", pair);
    }
    if (
      row.semantic_hazard_count === null &&
      row.semantic_field_verification_hazard_count !== null
    ) {
      return failure("CANARY_RESULT_SEMANTIC_METADATA_INVALID", pair);
    }
    if (
      requireAllPassed &&
      (row.status !== "passed" ||
        !["passed", "repaired"].includes(row.validation_status) ||
        row.semantic_code !== null)
    ) {
      return failure("CANARY_RESULT_PAIR_FAILED", pair);
    }
  }
  if (observedPairs.size !== expectedPairs.size) {
    return failure("CANARY_RESULT_PAIR_COVERAGE_INCOMPLETE");
  }

  const passed = document.results.filter((row) => row.status === "passed")
    .length;
  const failed = document.results.length - passed;
  if (document.passed !== passed || document.failed !== failed) {
    return failure("CANARY_RESULT_SUMMARY_MISMATCH");
  }
  if (requireAllPassed && failed !== 0) {
    return failure("CANARY_RESULT_MATRIX_FAILED", { passed, failed });
  }
  return {
    ok: true,
    code: null,
    details: {
      matrix,
      expected_pairs: expectedCount,
      passed,
      failed,
    },
  };
}
