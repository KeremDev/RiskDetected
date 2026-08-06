import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  LOCALIZATION_ERROR_CODES,
  LocalizationContractError,
  localizationPersistencePatch,
  localizationQueueGuard,
  stripLocalizationRequestFields,
} from "./localization-contract.ts";
import {
  loadLocalizationRolloutPolicy,
  localizationFlagEnabled,
  localizationSnapshotsEqual,
  resolveLocalizationContext,
} from "./localization-context-resolver.ts";
import { assertCanvasAvailableForSafetyProfile } from "./regulatory-reference-policy.ts";
import {
  defaultSafetyProfileID,
  requireSafetyProfile,
  safetyProfileSourceSHA256,
} from "./safety-profile-manifest.ts";

const allProfilesEnabled = new Set([
  "en-intl-generic-v1",
  "en-gb-generic-v1",
  "en-us-generic-v1",
  "en-au-generic-v1",
  "en-ca-generic-v1",
]);

function expectCode(
  code: string,
  callback: () => unknown,
): LocalizationContractError {
  const error = assertThrows(callback, LocalizationContractError);
  assertEquals(error.code, code);
  return error;
}

Deno.test("legacy request resolves to explicit immutable Turkish defaults", () => {
  const snapshot = resolveLocalizationContext({
    request: {},
    persistedMethod: "fine_kinney",
    workerInvocation: false,
    rolloutPolicy: {
      enabledProfileIDs: new Set(),
      queueSnapshotAuthorityEnabled: false,
      approvedSafetyProfileSourceSHA256: null,
    },
  });

  assertEquals(snapshot.safety_profile_id, defaultSafetyProfileID);
  assertEquals(snapshot.output_language, "tr");
  assertEquals(snapshot.output_locale, "tr-TR");
  assertEquals(snapshot.work_jurisdiction_country, "TR");
  assertEquals(snapshot.regulatory_reference_policy, "tr_current");
  assertEquals(snapshot.source, "legacy_tr_default");
  assertEquals(
    localizationPersistencePatch(snapshot).localization_snapshot,
    snapshot,
  );
});

Deno.test("all six safety profiles resolve from explicit profile requests", () => {
  const cases = [
    ["tr-tr-current-v1", "tr", "tr-TR", "TR", "fine_kinney"],
    ["en-intl-generic-v1", "en", "en-001", "INTL", "matrix_5x5"],
    ["en-gb-generic-v1", "en", "en-GB", "GB", "matrix_5x5"],
    ["en-us-generic-v1", "en", "en-US", "US", "matrix_5x5"],
    ["en-au-generic-v1", "en", "en-AU", "AU", "matrix_5x5"],
    ["en-ca-generic-v1", "en", "en-CA", "CA", "matrix_5x5"],
  ] as const;

  for (const [profileID, language, locale, country, method] of cases) {
    const snapshot = resolveLocalizationContext({
      request: {
        safety_profile_id: profileID,
        safety_profile_version: 1,
        output_language: language,
        output_locale: locale,
        work_jurisdiction_country: country,
        method,
      },
      persistedMethod: method,
      workerInvocation: false,
      rolloutPolicy: {
        enabledProfileIDs: allProfilesEnabled,
        queueSnapshotAuthorityEnabled: true,
        approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
      },
    });
    assertEquals(snapshot.safety_profile_id, profileID);
    assertEquals(snapshot.output_language, language);
    assertEquals(snapshot.output_locale, locale);
    assertEquals(snapshot.work_jurisdiction_country, country);
    assertEquals(snapshot.method, method);
    assertEquals(snapshot.source, "explicit_request");
  }
});

Deno.test("explicit machine-draft profile source fails without exact approval", () => {
  expectCode(
    LOCALIZATION_ERROR_CODES.profileNotApproved,
    () =>
      resolveLocalizationContext({
        request: { safety_profile_id: "en-intl-generic-v1" },
        persistedMethod: "matrix_5x5",
        workerInvocation: false,
        rolloutPolicy: {
          enabledProfileIDs: allProfilesEnabled,
          queueSnapshotAuthorityEnabled: true,
          approvedSafetyProfileSourceSHA256: null,
        },
      }),
  );
});

Deno.test("English context requires an explicit safety profile", () => {
  expectCode(
    LOCALIZATION_ERROR_CODES.profileRequired,
    () =>
      resolveLocalizationContext({
        request: { output_language: "en" },
        persistedMethod: "matrix_5x5",
        workerInvocation: false,
        rolloutPolicy: {
          enabledProfileIDs: allProfilesEnabled,
          queueSnapshotAuthorityEnabled: true,
          approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
        },
      }),
  );
});

Deno.test("disabled non-TR profile fails closed", () => {
  expectCode(
    LOCALIZATION_ERROR_CODES.profileNotEnabled,
    () =>
      resolveLocalizationContext({
        request: { safety_profile_id: "en-us-generic-v1" },
        persistedMethod: "matrix_5x5",
        workerInvocation: false,
        rolloutPolicy: {
          enabledProfileIDs: new Set(),
          queueSnapshotAuthorityEnabled: false,
          approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
        },
      }),
  );
});

Deno.test("profile language, locale, country and version cannot conflict", () => {
  for (
    const request of [
      {
        safety_profile_id: "en-gb-generic-v1",
        output_language: "tr",
      },
      {
        safety_profile_id: "en-gb-generic-v1",
        output_locale: "en-US",
      },
      {
        safety_profile_id: "en-gb-generic-v1",
        work_jurisdiction_country: "US",
      },
    ]
  ) {
    expectCode(
      LOCALIZATION_ERROR_CODES.profileContextMismatch,
      () =>
        resolveLocalizationContext({
          request,
          persistedMethod: "matrix_5x5",
          workerInvocation: false,
          rolloutPolicy: {
            enabledProfileIDs: allProfilesEnabled,
            queueSnapshotAuthorityEnabled: true,
            approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
          },
        }),
    );
  }

  expectCode(
    LOCALIZATION_ERROR_CODES.profileVersionMismatch,
    () =>
      resolveLocalizationContext({
        request: {
          safety_profile_id: "en-gb-generic-v1",
          safety_profile_version: 2,
        },
        persistedMethod: "matrix_5x5",
        workerInvocation: false,
        rolloutPolicy: {
          enabledProfileIDs: allProfilesEnabled,
          queueSnapshotAuthorityEnabled: true,
          approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
        },
      }),
  );
});

Deno.test("request method must match the analysis method", () => {
  expectCode(
    LOCALIZATION_ERROR_CODES.methodMismatch,
    () =>
      resolveLocalizationContext({
        request: {
          safety_profile_id: "en-us-generic-v1",
          method: "fine_kinney",
        },
        persistedMethod: "matrix_5x5",
        workerInvocation: false,
        rolloutPolicy: {
          enabledProfileIDs: allProfilesEnabled,
          queueSnapshotAuthorityEnabled: true,
          approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
        },
      }),
  );
});

Deno.test("persisted snapshot is authoritative across retry and repair", () => {
  const snapshot = resolveLocalizationContext({
    request: { safety_profile_id: "en-ca-generic-v1" },
    persistedMethod: "matrix_5x5",
    workerInvocation: false,
    rolloutPolicy: {
      enabledProfileIDs: allProfilesEnabled,
      queueSnapshotAuthorityEnabled: true,
      approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
    },
  });

  const workerSnapshot = resolveLocalizationContext({
    request: {},
    persistedSnapshot: snapshot,
    persistedMethod: "matrix_5x5",
    workerInvocation: true,
    rolloutPolicy: {
      enabledProfileIDs: new Set(),
      queueSnapshotAuthorityEnabled: false,
      approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
    },
  });
  assertEquals(localizationSnapshotsEqual(snapshot, workerSnapshot), true);

  expectCode(
    LOCALIZATION_ERROR_CODES.snapshotMismatch,
    () =>
      resolveLocalizationContext({
        request: { output_locale: "en-US" },
        persistedSnapshot: snapshot,
        persistedMethod: "matrix_5x5",
        workerInvocation: true,
        rolloutPolicy: {
          enabledProfileIDs: new Set(),
          queueSnapshotAuthorityEnabled: false,
          approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
        },
      }),
  );
});

Deno.test("worker invocation without a snapshot fails closed", () => {
  expectCode(
    LOCALIZATION_ERROR_CODES.snapshotRequired,
    () =>
      resolveLocalizationContext({
        request: {},
        persistedMethod: "fine_kinney",
        workerInvocation: true,
        rolloutPolicy: {
          enabledProfileIDs: new Set(),
          queueSnapshotAuthorityEnabled: false,
          approvedSafetyProfileSourceSHA256: null,
        },
      }),
  );
});

Deno.test("legacy in-flight worker may establish Turkish snapshot exactly once", () => {
  const snapshot = resolveLocalizationContext({
    request: {},
    persistedMethod: "fine_kinney",
    workerInvocation: true,
    allowLegacyWorkerBackfill: true,
    rolloutPolicy: {
      enabledProfileIDs: new Set(),
      queueSnapshotAuthorityEnabled: false,
      approvedSafetyProfileSourceSHA256: null,
    },
  });
  assertEquals(snapshot.safety_profile_id, "tr-tr-current-v1");
  assertEquals(snapshot.source, "legacy_tr_default");
});

Deno.test("non-TR legislation canvas is rejected by stable code", () => {
  for (
    const profileID of [
      "en-intl-generic-v1",
      "en-gb-generic-v1",
      "en-us-generic-v1",
      "en-au-generic-v1",
      "en-ca-generic-v1",
    ]
  ) {
    expectCode(
      LOCALIZATION_ERROR_CODES.canvasUnavailable,
      () =>
        assertCanvasAvailableForSafetyProfile(
          requireSafetyProfile(profileID),
          ["legislation"],
        ),
    );
  }

  assertCanvasAvailableForSafetyProfile(
    requireSafetyProfile("tr-tr-current-v1"),
    ["legislation"],
  );
});

Deno.test("queue transition strips request localization and keeps guard only", () => {
  const snapshot = resolveLocalizationContext({
    request: { safety_profile_id: "en-au-generic-v1" },
    persistedMethod: "matrix_5x5",
    workerInvocation: false,
    rolloutPolicy: {
      enabledProfileIDs: allProfilesEnabled,
      queueSnapshotAuthorityEnabled: true,
      approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
    },
  });
  const stripped = stripLocalizationRequestFields({
    analysis_id: "analysis-id",
    output_language: "en",
    output_locale: "en-AU",
    safety_profile_id: "en-au-generic-v1",
    method: "matrix_5x5",
    photo_paths: ["one.jpg"],
  });
  assertEquals(stripped, {
    analysis_id: "analysis-id",
    photo_paths: ["one.jpg"],
  });
  assertEquals(localizationQueueGuard(snapshot), {
    schema_version: 1,
    safety_profile_id: "en-au-generic-v1",
    safety_profile_version: 1,
    manifest_version: 1,
  });
});

Deno.test("localization rollout supports candidate build allowlists and fails closed", () => {
  const candidate = {
    userHash: "user-hash",
    clientBuild: "78",
    globalLocalizationCapability: true,
    approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
  };
  assertEquals(
    localizationFlagEnabled(
      {
        rollout_mode: "build_allowlist",
        enabled_ios_builds: ["78"],
      },
      candidate,
    ),
    true,
  );
  assertEquals(
    localizationFlagEnabled(
      {
        rollout_mode: "build_allowlist",
        enabled_ios_builds: ["78"],
      },
      { ...candidate, clientBuild: "77" },
    ),
    false,
  );
  assertEquals(
    localizationFlagEnabled(
      {
        rollout_mode: "build_allowlist",
        enabled_ios_builds: ["78"],
        kill_switch: true,
      },
      candidate,
    ),
    false,
  );
  assertEquals(
    localizationFlagEnabled(
      {
        rollout_mode: "min_build",
        min_ios_build: 78,
      },
      { ...candidate, clientBuild: "garbage" },
    ),
    false,
  );
});

Deno.test("localization rollout requires compiled capability and all global gates", async () => {
  const rows = [
    "localization_v2",
    "english_product_enabled",
    "global_localization_wave1",
    "localization_queue_payload_v1",
    "safety_profile_en_intl_enabled",
  ].map((key) => ({
    key,
    value: {
      rollout_mode: "build_allowlist",
      enabled_ios_builds: ["78"],
      enabled_user_hashes: ["user-hash"],
    },
  }));
  const supabase = {
    from: () => ({
      select: () => ({
        in: () => Promise.resolve({ data: rows, error: null }),
      }),
    }),
  };
  const baseContext = {
    userHash: "user-hash",
    clientBuild: "78",
    globalLocalizationCapability: true,
    approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
  };
  const enabled = await loadLocalizationRolloutPolicy(supabase, baseContext);
  assertEquals(
    [...enabled.enabledProfileIDs],
    ["en-intl-generic-v1"],
  );
  assertEquals(enabled.queueSnapshotAuthorityEnabled, true);

  const unapprovedSource = await loadLocalizationRolloutPolicy(supabase, {
    ...baseContext,
    approvedSafetyProfileSourceSHA256: null,
  });
  assertEquals([...unapprovedSource.enabledProfileIDs], []);
  assertEquals(unapprovedSource.queueSnapshotAuthorityEnabled, false);
  assertEquals(unapprovedSource.approvedSafetyProfileSourceSHA256, null);

  const outsideReviewerCohort = await loadLocalizationRolloutPolicy(
    supabase,
    {
      ...baseContext,
      userHash: "different-user-hash",
    },
  );
  assertEquals([...outsideReviewerCohort.enabledProfileIDs], []);
  assertEquals(
    outsideReviewerCohort.queueSnapshotAuthorityEnabled,
    false,
  );

  const disabled = await loadLocalizationRolloutPolicy(supabase, {
    ...baseContext,
    globalLocalizationCapability: false,
  });
  assertEquals([...disabled.enabledProfileIDs], []);
  assertEquals(disabled.queueSnapshotAuthorityEnabled, false);
});
