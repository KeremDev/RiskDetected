import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const CONTRACT_ID = "rd-global-localization-testflight-rollout-v1";
export const SUPABASE_PROJECT_REF = "ppcrzemgiztzcgddbins";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function readAppStoreCandidate() {
  try {
    const app = JSON.parse(
      readFileSync(resolve(ROOT, "appstore/app.json"), "utf8"),
    );
    return app?.release ?? {};
  } catch {
    return {};
  }
}

const APP_STORE_CANDIDATE = readAppStoreCandidate();

export const CANDIDATE_BUILD =
  process.env.RD_RELEASE_BUILD ??
  APP_STORE_CANDIDATE.build_number ??
  "80";
export const ASC_BUILD_ID =
  process.env.RD_ASC_BUILD_ID ??
  APP_STORE_CANDIDATE.build_id ??
  "71cc9591-32b9-4fee-b6c4-8c4d30713b23";

export const LOCALIZATION_FLAG_KEYS = [
  "localization_v2",
  "english_product_enabled",
  "global_localization_wave1",
  "safety_profile_en_intl_enabled",
  "safety_profile_en_gb_enabled",
  "safety_profile_en_us_enabled",
  "safety_profile_en_au_enabled",
  "safety_profile_en_ca_enabled",
  "localization_queue_payload_v1",
  "ai_language_guard_enabled",
  "ai_country_term_guard_enabled",
  "english_report_enabled",
  "english_notifications_enabled",
];

const FORBIDDEN_EVIDENCE_KEYS = new Set([
  "access_token",
  "authorization",
  "body",
  "contact",
  "email",
  "jwt",
  "message",
  "phone",
  "photo",
  "prompt",
  "raw_ai_response",
  "refresh_token",
  "title",
  "token",
  "user_id",
]);

const TERMINAL_QUEUE_EVENTS = [
  "dispatch_success_response",
  "dispatch_application_error",
  "claim_released_for_retry",
  "terminal_failed",
  "repair_superseded",
  "finalized",
  "message_deleted_after_response_loss",
  "max_attempts",
];

function nonNegativeInteger(value, label) {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${label} must be a non-negative integer`);
  }
  return value;
}

export function sha256JSON(value) {
  return createHash("sha256")
    .update(`${stableJSONStringify(value)}\n`)
    .digest("hex");
}

export function stableJSONStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableJSONStringify(item)).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJSONStringify(value[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function canonicalISO(value, label) {
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new Error(`${label} must be a valid ISO-8601 timestamp`);
  }
  return parsed.toISOString();
}

export function validateBuild(value) {
  if (typeof value !== "string" || !/^[1-9][0-9]{0,8}$/u.test(value)) {
    throw new Error("candidate build must be a positive build string");
  }
  return value;
}

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sqlTextList(values) {
  return values.map(sqlText).join(", ");
}

export function buildRuntimeConfigSQL() {
  return `
select json_build_object(
  'project_ref', ${sqlText(SUPABASE_PROJECT_REF)},
  'localization_flags',
  coalesce(
    (
      select json_agg(
        json_build_object(
          'key', f.key,
          'rollout_mode', coalesce(f.value ->> 'rollout_mode', 'missing'),
          'enabled_user_hash_count',
            case
              when jsonb_typeof(f.value -> 'enabled_user_hashes') = 'array'
                then jsonb_array_length(f.value -> 'enabled_user_hashes')
              else 0
            end,
          'enabled_ios_builds',
            case
              when jsonb_typeof(f.value -> 'enabled_ios_builds') = 'array'
                then f.value -> 'enabled_ios_builds'
              else '[]'::jsonb
            end,
          'min_ios_build', f.value ->> 'min_ios_build',
          'kill_switch', coalesce((f.value ->> 'kill_switch')::boolean, false)
        )
        order by f.key
      )
      from public.app_feature_flags f
      where f.key in (${sqlTextList(LOCALIZATION_FLAG_KEYS)})
    ),
    '[]'::json
  )
) as snapshot;
`.trim();
}

export function buildWindowMetricsSQL({
  candidateBuild,
  windowStart,
  windowEnd,
}) {
  const build = validateBuild(candidateBuild);
  const start = canonicalISO(windowStart, "window start");
  const end = canonicalISO(windowEnd, "window end");
  if (Date.parse(start) >= Date.parse(end)) {
    throw new Error("window start must be before window end");
  }

  return `
with
params as (
  select
    ${sqlText(build)}::text as candidate_build,
    ${sqlText(start)}::timestamptz as window_start,
    ${sqlText(end)}::timestamptz as window_end
),
build_analyses as (
  select a.*
  from public.analyses a
  cross join params p
  where a.client_build = p.candidate_build
    and a.created_at >= p.window_start
    and a.created_at < p.window_end
),
build_reports as (
  select r.*
  from public.reports r
  join build_analyses a on a.id = r.analysis_id
  cross join params p
  where r.created_at >= p.window_start
    and r.created_at < p.window_end
),
build_notification_events as (
  select distinct e.*
  from public.notification_events e
  cross join params p
  where e.created_at >= p.window_start
    and e.created_at < p.window_end
    and (
      exists (
        select 1
        from build_analyses a
        where a.id::text = e.data ->> 'analysis_id'
      )
      or exists (
        select 1
        from build_reports r
        where r.id::text = e.data ->> 'report_id'
      )
    )
),
unresolved_ambiguous_dispatches as (
  select e.id
  from private.analysis_job_events e
  join build_analyses a on a.id = e.analysis_id
  cross join params p
  where e.event_type = 'dispatch_ambiguous_transport'
    and e.created_at >= p.window_start
    and e.created_at < p.window_end
    and not exists (
      select 1
      from private.analysis_job_events terminal
      where terminal.analysis_id = e.analysis_id
        and terminal.job_generation = e.job_generation
        and terminal.worker_attempt = e.worker_attempt
        and terminal.created_at >= e.created_at
        and terminal.event_type in (${sqlTextList(TERMINAL_QUEUE_EVENTS)})
    )
),
flag_state as (
  select coalesce(
    json_agg(
      json_build_object(
        'key', f.key,
        'rollout_mode', coalesce(f.value ->> 'rollout_mode', 'missing'),
        'enabled_user_hash_count',
          case
            when jsonb_typeof(f.value -> 'enabled_user_hashes') = 'array'
              then jsonb_array_length(f.value -> 'enabled_user_hashes')
            else 0
          end,
        'enabled_ios_builds',
          case
            when jsonb_typeof(f.value -> 'enabled_ios_builds') = 'array'
              then f.value -> 'enabled_ios_builds'
            else '[]'::jsonb
          end,
        'min_ios_build', f.value ->> 'min_ios_build',
        'kill_switch', coalesce((f.value ->> 'kill_switch')::boolean, false)
      )
      order by f.key
    ),
    '[]'::json
  ) as flags
  from public.app_feature_flags f
  where f.key in (${sqlTextList(LOCALIZATION_FLAG_KEYS)})
)
select json_build_object(
  'project_ref', ${sqlText(SUPABASE_PROJECT_REF)},
  'metrics', json_build_object(
    'analyses', json_build_object(
      'total', (select count(*) from build_analyses),
      'completed', (
        select count(*) from build_analyses where status::text = 'completed'
      ),
      'failed', (
        select count(*) from build_analyses where status::text = 'failed'
      ),
      'pending', (
        select count(*) from build_analyses
        where status::text not in ('completed', 'failed')
      ),
      'wrong_language', (
        select count(*) from build_analyses
        where language_validation_status = 'failed'
      ),
      'repaired', (
        select count(*) from build_analyses
        where language_validation_status = 'repaired'
          or language_contract_repair_used is true
      ),
      'telemetry_missing', (
        select count(*) from build_analyses
        where language_validation_status is null
          or language_validation_status = 'not_evaluated'
      ),
      'telemetry_null', (
        select count(*) from build_analyses
        where language_validation_status is null
      ),
      'not_evaluated', (
        select count(*) from build_analyses
        where language_validation_status = 'not_evaluated'
      )
    ),
    'reports', json_build_object(
      'observed_successful', (select count(*) from build_reports)
    ),
    'notifications', json_build_object(
      'attempts', (select count(*) from build_notification_events),
      'template_misses', (
        select count(*)
        from build_notification_events
        where status = 'skipped'
          and (
            last_error = 'TEMPLATE_EXACT_LOCALE_MISSING'
            or localization_snapshot ->> 'error_code'
              = 'TEMPLATE_EXACT_LOCALE_MISSING'
          )
      ),
      'telemetry_missing', (
        select count(*)
        from build_notification_events
        where language is null or locale is null
      )
    ),
    'queue', json_build_object(
      'jobs', (
        select count(*)
        from private.analysis_job_state s
        join build_analyses a on a.id = s.analysis_id
      ),
      'retried_jobs', (
        select count(*)
        from private.analysis_job_state s
        join build_analyses a on a.id = s.analysis_id
        where greatest(
          coalesce(s.worker_attempt_count, 0),
          coalesce(a.worker_attempt_count, 0)
        ) > 1
      ),
      'ambiguous_dispatches', (
        select count(*) from unresolved_ambiguous_dispatches
      )
    )
  ),
  'runtime_config', json_build_object(
    'localization_flags', (select flags from flag_state)
  )
) as snapshot;
`.trim();
}

export function parseSupabaseQueryOutput(stdout) {
  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw new Error("Supabase CLI did not return valid JSON");
  }
  if (
    !Array.isArray(parsed?.rows) ||
    parsed.rows.length !== 1 ||
    !parsed.rows[0]?.snapshot ||
    typeof parsed.rows[0].snapshot !== "object"
  ) {
    throw new Error("Supabase CLI JSON is missing rows[0].snapshot");
  }
  return parsed.rows[0].snapshot;
}

export function parseASCUsageOutput(stdout) {
  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw new Error("App Store Connect CLI did not return valid JSON");
  }
  const points = parsed?.data?.flatMap((item) =>
    Array.isArray(item?.dataPoints) ? item.dataPoints : []
  );
  if (!Array.isArray(points) || points.length === 0) {
    throw new Error("App Store Connect beta usage response has no data points");
  }
  const totals = {
    install_count: 0,
    crash_count: 0,
    session_count: 0,
    invite_count: 0,
    feedback_count: 0,
  };
  const mapping = {
    installCount: "install_count",
    crashCount: "crash_count",
    sessionCount: "session_count",
    inviteCount: "invite_count",
    feedbackCount: "feedback_count",
  };
  for (const point of points) {
    for (const [source, target] of Object.entries(mapping)) {
      totals[target] += nonNegativeInteger(
        point?.values?.[source],
        `ASC ${source}`,
      );
    }
  }
  return totals;
}

export function normalizeRuntimeConfig(runtimeConfig) {
  const flags = runtimeConfig?.localization_flags;
  if (!Array.isArray(flags)) {
    throw new Error("runtime configuration is missing localization_flags");
  }
  const normalized = flags.map((flag) => ({
    key: String(flag?.key ?? ""),
    rollout_mode: String(flag?.rollout_mode ?? "missing"),
    enabled_user_hash_count: nonNegativeInteger(
      flag?.enabled_user_hash_count,
      `${flag?.key ?? "flag"} enabled_user_hash_count`,
    ),
    enabled_ios_builds: Array.isArray(flag?.enabled_ios_builds)
      ? flag.enabled_ios_builds.map((value) => String(value)).sort()
      : [],
    min_ios_build: flag?.min_ios_build === null ||
        flag?.min_ios_build === undefined
      ? null
      : String(flag.min_ios_build),
    kill_switch: flag?.kill_switch === true,
  })).sort((left, right) => left.key.localeCompare(right.key));

  const keys = normalized.map((flag) => flag.key);
  const expected = [...LOCALIZATION_FLAG_KEYS].sort();
  if (stableJSONStringify(keys) !== stableJSONStringify(expected)) {
    throw new Error(
      `runtime configuration must contain exactly ${expected.length} localization flags`,
    );
  }
  return {
    flag_count: normalized.length,
    enabled_user_hash_count: normalized.reduce(
      (sum, flag) => sum + flag.enabled_user_hash_count,
      0,
    ),
    non_off_flag_count: normalized.filter((flag) =>
      flag.rollout_mode !== "off"
    ).length,
    kill_switch_count: normalized.filter((flag) => flag.kill_switch).length,
    flags: normalized,
    sha256: sha256JSON(normalized),
  };
}

export function createBeginEvidence({
  thresholds,
  stage,
  candidateBuild,
  windowStart,
  ascUsage,
  runtimeConfig,
}) {
  const stageContract = thresholds?.stages?.find((item) =>
    item.stage === stage
  );
  if (!stageContract) throw new Error(`stage ${stage} is not defined`);
  const build = validateBuild(candidateBuild);
  const normalizedRuntime = normalizeRuntimeConfig(runtimeConfig);
  return {
    schema_version: 1,
    kind: "testflight_rollout_stage_begin",
    contract_id: thresholds.contract_id,
    stage,
    stage_key: stageContract.key,
    candidate_build: build,
    asc_build_id: ASC_BUILD_ID,
    window_start: canonicalISO(windowStart, "window start"),
    baseline: {
      stability: parseASCUsageOutput(JSON.stringify(ascUsage)),
      runtime_config: normalizedRuntime,
    },
    privacy: {
      aggregate_only: true,
      disallowed_data_present: false,
    },
  };
}

function usageDelta(baseline, current, key, issues) {
  const before = nonNegativeInteger(baseline?.[key], `baseline ${key}`);
  const after = nonNegativeInteger(current?.[key], `current ${key}`);
  if (after < before) {
    issues.push(`ASC ${key} decreased from ${before} to ${after}`);
    return 0;
  }
  return after - before;
}

export function normalizeAcceleratedValidationEvidence({
  thresholds,
  stage,
  candidateBuild,
  evidence,
}) {
  const policy = thresholds?.accelerated_validation_policy;
  const stageContract = thresholds?.stages?.find((item) =>
    item.stage === stage
  );
  const requirement = stageContract?.validation;
  if (
    policy?.owner_authorized !== true ||
    policy?.app_store_connect_usage_is_gate_input !== false ||
    policy?.app_store_connect_usage_collection_required !== false ||
    policy?.strict_stage_order_remains_required !== true ||
    policy?.zero_tolerance_thresholds_remain_enforced !== true ||
    !Array.isArray(policy?.applies_to_stages) ||
    !policy.applies_to_stages.includes(stage)
  ) {
    throw new Error(`stage ${stage} accelerated validation policy is invalid`);
  }
  if (!requirement) {
    throw new Error(`stage ${stage} validation requirement is missing`);
  }
  if (
    evidence?.schema_version !== 1 ||
    evidence?.kind !== "device_simulator_rollout_validation" ||
    evidence?.policy_id !== policy.policy_id ||
    evidence?.contract_id !== thresholds.contract_id ||
    evidence?.candidate_build !== candidateBuild ||
    evidence?.stage !== stage ||
    evidence?.status !== "passed" ||
    evidence?.mode !== requirement.mode
  ) {
    throw new Error(`stage ${stage} validation evidence contract is invalid`);
  }
  const launches = nonNegativeInteger(
    evidence?.launches,
    `stage ${stage} validation launches`,
  );
  const crashes = nonNegativeInteger(
    evidence?.crashes,
    `stage ${stage} validation crashes`,
  );
  if (launches < requirement.minimum_launches) {
    throw new Error(
      `stage ${stage} validation launches are below the required minimum`,
    );
  }
  if (crashes > thresholds.count_thresholds.crash_count_max) {
    throw new Error(`stage ${stage} validation observed a crash`);
  }
  const profiles = Array.isArray(evidence?.profiles)
    ? [...new Set(evidence.profiles.map(String))].sort()
    : [];
  const checks = Array.isArray(evidence?.checks)
    ? [...new Set(evidence.checks.map(String))].sort()
    : [];
  for (const profile of requirement.required_profiles) {
    if (!profiles.includes(profile)) {
      throw new Error(
        `stage ${stage} validation is missing required profile ${profile}`,
      );
    }
  }
  for (const check of requirement.required_checks) {
    if (!checks.includes(check)) {
      throw new Error(
        `stage ${stage} validation is missing required check ${check}`,
      );
    }
  }
  if (
    evidence?.privacy?.aggregate_only !== true ||
    evidence?.privacy?.device_identifiers_included !== false ||
    evidence?.privacy?.user_or_account_data_included !== false ||
    evidence?.privacy?.user_content_included !== false
  ) {
    throw new Error(`stage ${stage} validation evidence is not aggregate-only`);
  }
  const proofDigests = Array.isArray(evidence?.proof_digests)
    ? [...new Set(evidence.proof_digests.map(String))].sort()
    : [];
  if (
    proofDigests.length === 0 ||
    proofDigests.some((digest) => !/^[a-f0-9]{64}$/u.test(digest))
  ) {
    throw new Error(`stage ${stage} validation proof digests are invalid`);
  }
  return {
    policy_id: policy.policy_id,
    mode: requirement.mode,
    status: "passed",
    launches,
    crashes,
    profiles,
    checks,
    proof_digests: proofDigests,
    source_sha256: sha256JSON(evidence),
    privacy: {
      aggregate_only: true,
      device_identifiers_included: false,
      user_or_account_data_included: false,
      user_content_included: false,
    },
  };
}

export function createFinishEvidence({
  thresholds,
  beginEvidence,
  windowEnd,
  supabaseObservation,
  ascUsage,
  reportRequests,
  reportFailures,
  reportCountersAttested,
  stage1SessionDelayWaiver = null,
  acceleratedValidationEvidence = null,
}) {
  if (beginEvidence?.kind !== "testflight_rollout_stage_begin") {
    throw new Error("begin evidence has an unsupported kind");
  }
  if (beginEvidence.contract_id !== thresholds?.contract_id) {
    throw new Error("begin evidence does not match the threshold contract");
  }
  const end = canonicalISO(windowEnd, "window end");
  if (Date.parse(beginEvidence.window_start) >= Date.parse(end)) {
    throw new Error("window end must be after the begin timestamp");
  }
  const requests = nonNegativeInteger(reportRequests, "report requests");
  const failures = nonNegativeInteger(reportFailures, "report failures");
  const blockingIssues = [];
  const holdIssues = [];
  if (reportCountersAttested !== true) {
    blockingIssues.push("report aggregate counters were not attested");
  }
  if (failures > requests) {
    blockingIssues.push("report failures cannot exceed report requests");
  }

  const metrics = supabaseObservation?.metrics;
  const observedReportSuccesses = nonNegativeInteger(
    metrics?.reports?.observed_successful,
    "observed successful reports",
  );
  const expectedSuccesses = Math.max(0, requests - failures);
  if (observedReportSuccesses < expectedSuccesses) {
    holdIssues.push(
      `database has ${observedReportSuccesses} successful reports; ` +
        `${expectedSuccesses} are required by the attested counters`,
    );
  }
  if (observedReportSuccesses > requests) {
    blockingIssues.push(
      `database has ${observedReportSuccesses} successful reports but only ` +
        `${requests} report requests were attested`,
    );
  }

  const analysisTotal = nonNegativeInteger(
    metrics?.analyses?.total,
    "analysis total",
  );
  const analysisCompleted = nonNegativeInteger(
    metrics?.analyses?.completed,
    "completed analyses",
  );
  const analysisFailed = nonNegativeInteger(
    metrics?.analyses?.failed,
    "failed analyses",
  );
  const analysisPending = nonNegativeInteger(
    metrics?.analyses?.pending,
    "pending analyses",
  );
  const hasSplitAnalysisTelemetry =
    metrics?.analyses?.telemetry_null !== undefined &&
    metrics?.analyses?.not_evaluated !== undefined;
  const analysisTelemetryNull = nonNegativeInteger(
    hasSplitAnalysisTelemetry
      ? metrics.analyses.telemetry_null
      : metrics?.analyses?.telemetry_missing,
    "analyses with null telemetry",
  );
  const analysisNotEvaluated = nonNegativeInteger(
    hasSplitAnalysisTelemetry
      ? metrics.analyses.not_evaluated
      : 0,
    "analyses not evaluated for language",
  );
  const analysisTelemetryMissing =
    analysisTelemetryNull + analysisNotEvaluated;
  if (analysisCompleted + analysisFailed + analysisPending !== analysisTotal) {
    blockingIssues.push(
      "analysis terminal-state counts do not equal analysis total",
    );
  }
  if (analysisPending > 0) {
    holdIssues.push(`${analysisPending} analyses are not in a terminal state`);
  }
  if (analysisTelemetryNull > 0) {
    blockingIssues.push(
      `${analysisTelemetryNull} analyses have null language telemetry`,
    );
  }
  if (beginEvidence.stage !== 1 && analysisNotEvaluated > 0) {
    blockingIssues.push(
      `${analysisNotEvaluated} analyses were not evaluated for language`,
    );
  }

  const notificationTelemetryMissing = nonNegativeInteger(
    metrics?.notifications?.telemetry_missing,
    "notifications with missing telemetry",
  );
  if (notificationTelemetryMissing > 0) {
    blockingIssues.push(
      `${notificationTelemetryMissing} notifications are missing locale telemetry`,
    );
  }

  const startRuntime = beginEvidence?.baseline?.runtime_config;
  const endRuntime = normalizeRuntimeConfig(
    supabaseObservation?.runtime_config,
  );
  if (startRuntime?.sha256 !== endRuntime.sha256) {
    blockingIssues.push(
      "localization runtime configuration changed during the stage",
    );
  }

  const acceleratedValidation = beginEvidence.stage >= 2
    ? normalizeAcceleratedValidationEvidence({
      thresholds,
      stage: beginEvidence.stage,
      candidateBuild: beginEvidence.candidate_build,
      evidence: acceleratedValidationEvidence,
    })
    : null;
  const baselineUsage = beginEvidence?.baseline?.stability;
  const currentUsage = acceleratedValidation === null
    ? parseASCUsageOutput(JSON.stringify(ascUsage))
    : { ...baselineUsage };
  const ascSessionDelta = usageDelta(
      baselineUsage,
      currentUsage,
      "session_count",
      blockingIssues,
    );
  const ascCrashDelta = usageDelta(
      baselineUsage,
      currentUsage,
      "crash_count",
      blockingIssues,
    );
  const stability = {
    sessions: acceleratedValidation?.launches ?? ascSessionDelta,
    crashes: acceleratedValidation?.crashes ?? ascCrashDelta,
  };
  const usageDeltas = {
    installs: usageDelta(
      baselineUsage,
      currentUsage,
      "install_count",
      blockingIssues,
    ),
    invites: usageDelta(
      baselineUsage,
      currentUsage,
      "invite_count",
      blockingIssues,
    ),
    feedback: usageDelta(
      baselineUsage,
      currentUsage,
      "feedback_count",
      blockingIssues,
    ),
  };
  const waivers = stage1SessionDelayWaiver === null
    ? []
    : [{
      waiver_id: String(stage1SessionDelayWaiver.waiver_id ?? ""),
      kind: String(stage1SessionDelayWaiver.kind ?? ""),
      stage: nonNegativeInteger(
        stage1SessionDelayWaiver.stage,
        "waiver stage",
      ),
      metric: String(stage1SessionDelayWaiver.metric ?? ""),
      owner_authorized: stage1SessionDelayWaiver.owner_authorized === true,
      actual_session_delta: nonNegativeInteger(
        stage1SessionDelayWaiver.actual_session_delta,
        "waiver actual session delta",
      ),
      required_session_delta: nonNegativeInteger(
        stage1SessionDelayWaiver.required_session_delta,
        "waiver required session delta",
      ),
      installed_tester_count: nonNegativeInteger(
        stage1SessionDelayWaiver.installed_tester_count,
        "waiver installed tester count",
      ),
      physical_candidate_installed:
        stage1SessionDelayWaiver.physical_candidate_installed === true,
      physical_launch_succeeded:
        stage1SessionDelayWaiver.physical_launch_succeeded === true,
      apple_documented_latency_hours_max: nonNegativeInteger(
        stage1SessionDelayWaiver.apple_documented_latency_hours_max,
        "waiver documented latency",
      ),
      evidence_verified:
        stage1SessionDelayWaiver.evidence_verified === true,
      waiver_record_sha256: String(
        stage1SessionDelayWaiver.waiver_record_sha256 ?? "",
      ),
    }];

  const snapshot = {
    schema_version: 1,
    contract_id: beginEvidence.contract_id,
    stage: beginEvidence.stage,
    stage_key: beginEvidence.stage_key,
    candidate_build: beginEvidence.candidate_build,
    window_start: beginEvidence.window_start,
    window_end: end,
    metrics: {
      analyses: {
        total: analysisTotal,
        failed: analysisFailed,
        wrong_language: nonNegativeInteger(
          metrics?.analyses?.wrong_language,
          "wrong-language analyses",
        ),
        repaired: nonNegativeInteger(
          metrics?.analyses?.repaired,
          "repaired analyses",
        ),
      },
      reports: {
        requests,
        failed: failures,
      },
      notifications: {
        attempts: nonNegativeInteger(
          metrics?.notifications?.attempts,
          "notification attempts",
        ),
        template_misses: nonNegativeInteger(
          metrics?.notifications?.template_misses,
          "notification template misses",
        ),
      },
      stability,
      queue: {
        jobs: nonNegativeInteger(metrics?.queue?.jobs, "queue jobs"),
        retried_jobs: nonNegativeInteger(
          metrics?.queue?.retried_jobs,
          "retried queue jobs",
        ),
        ambiguous_dispatches: nonNegativeInteger(
          metrics?.queue?.ambiguous_dispatches,
          "ambiguous queue dispatches",
        ),
      },
    },
    observation: {
      supabase_project_ref: SUPABASE_PROJECT_REF,
      asc_build_id: beginEvidence.asc_build_id,
      report_counters: {
        source: "operator_aggregate_attestation",
        attested: reportCountersAttested === true,
        observed_successful: observedReportSuccesses,
      },
      analyses: {
        completed: analysisCompleted,
        pending: analysisPending,
        telemetry_missing: analysisTelemetryMissing,
        telemetry_null: analysisTelemetryNull,
        not_evaluated: analysisNotEvaluated,
      },
      notifications: {
        telemetry_missing: notificationTelemetryMissing,
      },
      stability_baseline: baselineUsage,
      stability_end: currentUsage,
      stability_source: acceleratedValidation === null
        ? "app_store_connect_beta_usage"
        : "device_simulator_validation",
      app_store_connect_usage_gate_input: acceleratedValidation === null,
      usage_deltas: usageDeltas,
      runtime_config: {
        start_sha256: startRuntime?.sha256 ?? null,
        end_sha256: endRuntime.sha256,
        unchanged: startRuntime?.sha256 === endRuntime.sha256,
        flag_count: endRuntime.flag_count,
        enabled_user_hash_count: endRuntime.enabled_user_hash_count,
        non_off_flag_count: endRuntime.non_off_flag_count,
        kill_switch_count: endRuntime.kill_switch_count,
        flags: endRuntime.flags,
      },
    },
    validation: acceleratedValidation,
    waivers,
    integrity: {
      status: blockingIssues.length > 0
        ? "blocked"
        : holdIssues.length > 0
        ? "hold"
        : "passed",
      issues: [...blockingIssues, ...holdIssues],
      blocking_issues: blockingIssues,
      hold_issues: holdIssues,
    },
    privacy: {
      aggregate_only: true,
      disallowed_data_present: false,
    },
  };
  const privacyIssues = findForbiddenEvidenceKeys(snapshot);
  if (privacyIssues.length > 0) {
    snapshot.integrity.status = "blocked";
    const issue = `forbidden evidence keys: ${privacyIssues.join(", ")}`;
    snapshot.integrity.issues.push(issue);
    snapshot.integrity.blocking_issues.push(issue);
    snapshot.privacy.disallowed_data_present = true;
  }
  return snapshot;
}

export function findForbiddenEvidenceKeys(value, path = "$", issues = []) {
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      findForbiddenEvidenceKeys(item, `${path}[${index}]`, issues)
    );
    return issues;
  }
  if (!value || typeof value !== "object") return issues;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_EVIDENCE_KEYS.has(key.toLowerCase())) {
      issues.push(`${path}.${key}`);
    }
    findForbiddenEvidenceKeys(child, `${path}.${key}`, issues);
  }
  return issues;
}

export function verifyRolloutSequence({
  thresholds,
  stageRecords,
  candidateBuild = CANDIDATE_BUILD,
}) {
  const issues = [];
  const stages = Array.isArray(thresholds?.stages) ? thresholds.stages : [];
  if (
    thresholds?.schema_version !== 1 ||
    thresholds?.contract_id !== CONTRACT_ID ||
    stages.length !== 9
  ) {
    issues.push("unsupported or incomplete rollout threshold contract");
  }
  const records = [...stageRecords].sort((left, right) =>
    (left?.snapshot?.stage ?? 0) - (right?.snapshot?.stage ?? 0)
  );
  let priorEnd = null;
  let completed = 0;
  for (let index = 0; index < records.length; index += 1) {
    const record = records[index];
    const expectedStage = index + 1;
    const snapshot = record?.snapshot;
    const result = record?.result;
    if (snapshot?.stage !== expectedStage) {
      issues.push(
        `stage sequence gap: expected ${expectedStage}, found ${snapshot?.stage ?? "missing"}`,
      );
    }
    const contractStage = stages.find((item) => item.stage === expectedStage);
    if (snapshot?.stage_key !== contractStage?.key) {
      issues.push(`stage ${expectedStage} key does not match the contract`);
    }
    if (snapshot?.candidate_build !== candidateBuild) {
      issues.push(`stage ${expectedStage} targets a different build`);
    }
    if (snapshot?.contract_id !== thresholds.contract_id) {
      issues.push(`stage ${expectedStage} contract does not match`);
    }
    if (snapshot?.integrity?.status !== "passed") {
      issues.push(`stage ${expectedStage} integrity did not pass`);
    }
    if (result?.status !== "passed") {
      issues.push(`stage ${expectedStage} rollout gate did not pass`);
    }
    if (
      result?.snapshot_sha256 &&
      result.snapshot_sha256 !== sha256JSON(snapshot)
    ) {
      issues.push(`stage ${expectedStage} snapshot digest does not match`);
    }
    const start = Date.parse(snapshot?.window_start);
    const end = Date.parse(snapshot?.window_end);
    if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end) {
      issues.push(`stage ${expectedStage} has an invalid observation window`);
    } else if (priorEnd !== null && start < priorEnd) {
      issues.push(`stage ${expectedStage} overlaps the previous stage`);
    }
    priorEnd = Number.isFinite(end) ? end : priorEnd;
    const privacyIssues = findForbiddenEvidenceKeys(snapshot);
    if (
      snapshot?.privacy?.aggregate_only !== true ||
      snapshot?.privacy?.disallowed_data_present !== false ||
      privacyIssues.length > 0
    ) {
      issues.push(`stage ${expectedStage} violates the aggregate-only contract`);
    }
    if (
      snapshot?.integrity?.status === "passed" &&
      result?.status === "passed"
    ) {
      completed += 1;
    }
    const snapshotWaivers = Array.isArray(snapshot?.waivers)
      ? snapshot.waivers
      : [];
    const appliedWaivers = Array.isArray(result?.applied_waivers)
      ? result.applied_waivers
      : [];
    if (snapshotWaivers.length > 0) {
      const waiver = snapshotWaivers[0];
      const applied = appliedWaivers[0];
      if (
        expectedStage !== 1 ||
        snapshotWaivers.length !== 1 ||
        waiver?.kind !== "stage1_asc_session_propagation" ||
        waiver?.metric !== "sessions" ||
        waiver?.owner_authorized !== true ||
        waiver?.evidence_verified !== true ||
        !/^[a-f0-9]{64}$/u.test(waiver?.waiver_record_sha256 ?? "") ||
        appliedWaivers.length !== 1 ||
        applied?.waiver_id !== waiver?.waiver_id ||
        applied?.metric !== "sessions"
      ) {
        issues.push(`stage ${expectedStage} has an invalid applied waiver`);
      }
    } else if (appliedWaivers.length > 0) {
      issues.push(
        `stage ${expectedStage} result applies an undeclared waiver`,
      );
    }
  }
  if (records.length > stages.length) {
    issues.push("more stage records exist than the contract permits");
  }
  const nextStage = Math.min(records.length + 1, stages.length);
  return {
    schema_version: 1,
    contract_id: thresholds?.contract_id ?? null,
    candidate_build: candidateBuild,
    status: issues.length > 0
      ? "blocked"
      : records.length === stages.length
      ? "passed"
      : "hold",
    completed_stages: completed,
    required_stages: stages.length,
    next_stage: records.length === stages.length ? null : nextStage,
    next_stage_key: records.length === stages.length
      ? null
      : stages.find((item) => item.stage === nextStage)?.key ?? null,
    issues,
  };
}
