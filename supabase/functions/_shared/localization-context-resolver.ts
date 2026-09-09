import {
  contentLocales,
  jurisdictionCountries,
  legalDocumentSetIDs,
  type RiskMethod,
  riskMethods,
} from "./approved-safety-profiles.generated.ts";
import {
  hasLocalizationRequestFields,
  LOCALIZATION_ERROR_CODES,
  LOCALIZATION_PROMPT_PROFILE_VERSION,
  LOCALIZATION_SNAPSHOT_SCHEMA_VERSION,
  LocalizationContractError,
  type LocalizationRequest,
  type LocalizationSnapshot,
} from "./localization-contract.ts";
import {
  defaultSafetyProfileID,
  requireSafetyProfile,
  safetyProfileManifestVersion,
  safetyProfileSourceSHA256,
} from "./safety-profile-manifest.ts";

export type LocalizationRolloutPolicy = {
  enabledProfileIDs: ReadonlySet<string>;
  queueSnapshotAuthorityEnabled: boolean;
  approvedSafetyProfileSourceSHA256: string | null;
};

export type ResolveLocalizationContextInput = {
  request: LocalizationRequest;
  persistedSnapshot?: unknown;
  persistedMethod: unknown;
  workerInvocation: boolean;
  allowLegacyWorkerBackfill?: boolean;
  rolloutPolicy: LocalizationRolloutPolicy;
};

const asTrimmedString = (value: unknown): string | null =>
  typeof value === "string" && value.trim().length > 0 ? value.trim() : null;

const asOptionalRegion = (value: unknown): string | null => {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.invalidContext,
      400,
    );
  }
  const region = value.trim();
  if (region.length === 0) return null;
  if (region.length > 80 || !/^[A-Za-z0-9][A-Za-z0-9 ._/-]*$/.test(region)) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.invalidContext,
      400,
    );
  }
  return region;
};

const hasOwn = (value: object, key: string): boolean =>
  Object.prototype.hasOwnProperty.call(value, key);

function requireRiskMethod(value: unknown): RiskMethod {
  const method = asTrimmedString(value);
  if (!method || !riskMethods.includes(method as RiskMethod)) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.methodNotAllowed,
      400,
    );
  }
  return method as RiskMethod;
}

function requireInteger(value: unknown): number {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string" && value.trim().length > 0
    ? Number(value)
    : Number.NaN;
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.snapshotInvalid,
      409,
    );
  }
  return parsed;
}

function assertRequestFieldMatch(
  request: LocalizationRequest,
  field: keyof LocalizationRequest,
  expected: string | number | null,
): void {
  if (!hasOwn(request, field) || request[field] === undefined) return;
  const actual = field === "work_jurisdiction_region"
    ? asOptionalRegion(request[field])
    : field === "safety_profile_version"
    ? Number(request[field])
    : asTrimmedString(request[field]);
  if (actual !== expected) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.snapshotMismatch,
      409,
    );
  }
}

export function parsePersistedLocalizationSnapshot(
  value: unknown,
): LocalizationSnapshot {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.snapshotInvalid,
      409,
    );
  }
  const record = value as Record<string, unknown>;
  const profile = requireSafetyProfile(record.safety_profile_id);
  const method = requireRiskMethod(record.method);
  const region = asOptionalRegion(record.work_jurisdiction_region);
  const version = requireInteger(record.safety_profile_version);

  const valid =
    record.schema_version === LOCALIZATION_SNAPSHOT_SCHEMA_VERSION &&
    record.output_language === profile.language &&
    record.output_locale === profile.content_locale &&
    record.work_jurisdiction_country === profile.jurisdiction_country &&
    version === profile.profile_version &&
    record.regulatory_reference_policy ===
      profile.regulatory_reference_policy &&
    record.prompt_profile_version === LOCALIZATION_PROMPT_PROFILE_VERSION &&
    profile.allowed_risk_methods.includes(method) &&
    legalDocumentSetIDs.includes(record.legal_document_set as never) &&
    record.legislation_canvas_enabled ===
      profile.legislation_canvas_enabled &&
    record.structured_regulatory_references_enabled ===
      profile.structured_regulatory_references_enabled &&
    record.manifest_version === safetyProfileManifestVersion &&
    record.manifest_source_sha256 === safetyProfileSourceSHA256 &&
    ["legacy_tr_default", "explicit_request", "legacy_tr_backfill"].includes(
      String(record.source),
    );

  if (!valid) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.snapshotInvalid,
      409,
    );
  }

  return {
    ...record,
    work_jurisdiction_region: region,
    method,
  } as LocalizationSnapshot;
}

function assertRequestMatchesSnapshot(
  request: LocalizationRequest,
  snapshot: LocalizationSnapshot,
): void {
  assertRequestFieldMatch(
    request,
    "output_language",
    snapshot.output_language,
  );
  assertRequestFieldMatch(request, "output_locale", snapshot.output_locale);
  assertRequestFieldMatch(
    request,
    "work_jurisdiction_country",
    snapshot.work_jurisdiction_country,
  );
  assertRequestFieldMatch(
    request,
    "work_jurisdiction_region",
    snapshot.work_jurisdiction_region,
  );
  assertRequestFieldMatch(
    request,
    "safety_profile_id",
    snapshot.safety_profile_id,
  );
  assertRequestFieldMatch(
    request,
    "safety_profile_version",
    snapshot.safety_profile_version,
  );
  assertRequestFieldMatch(request, "method", snapshot.method);
}

export function localizationSnapshotsEqual(
  left: unknown,
  right: unknown,
): boolean {
  try {
    const a = parsePersistedLocalizationSnapshot(left);
    const b = parsePersistedLocalizationSnapshot(right);
    return JSON.stringify(a) === JSON.stringify(b);
  } catch {
    return false;
  }
}

export function resolveLocalizationContext(
  input: ResolveLocalizationContextInput,
): LocalizationSnapshot {
  if (
    input.persistedSnapshot !== null && input.persistedSnapshot !== undefined
  ) {
    const snapshot = parsePersistedLocalizationSnapshot(
      input.persistedSnapshot,
    );
    if (
      snapshot.source === "explicit_request" &&
      input.rolloutPolicy.approvedSafetyProfileSourceSHA256 !==
        safetyProfileSourceSHA256
    ) {
      throw new LocalizationContractError(
        LOCALIZATION_ERROR_CODES.profileNotApproved,
        403,
      );
    }
    assertRequestMatchesSnapshot(input.request, snapshot);
    const persistedMethod = requireRiskMethod(input.persistedMethod);
    if (snapshot.method !== persistedMethod) {
      throw new LocalizationContractError(
        LOCALIZATION_ERROR_CODES.methodMismatch,
        409,
      );
    }
    return snapshot;
  }

  if (input.workerInvocation && input.allowLegacyWorkerBackfill !== true) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.snapshotRequired,
      409,
    );
  }

  const explicit = hasLocalizationRequestFields(input.request);
  if (explicit && !asTrimmedString(input.request.safety_profile_id)) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.profileRequired,
      400,
    );
  }

  const profile = requireSafetyProfile(
    explicit ? input.request.safety_profile_id : defaultSafetyProfileID,
  );
  if (
    explicit &&
    input.rolloutPolicy.approvedSafetyProfileSourceSHA256 !==
      safetyProfileSourceSHA256
  ) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.profileNotApproved,
      403,
    );
  }
  if (
    profile.id !== defaultSafetyProfileID &&
    !input.rolloutPolicy.enabledProfileIDs.has(profile.id)
  ) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.profileNotEnabled,
      403,
    );
  }

  const version = hasOwn(input.request, "safety_profile_version")
    ? Number(input.request.safety_profile_version)
    : profile.profile_version;
  if (version !== profile.profile_version) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.profileVersionMismatch,
      409,
    );
  }

  const expectedFields = [
    ["output_language", profile.language],
    ["output_locale", profile.content_locale],
    ["work_jurisdiction_country", profile.jurisdiction_country],
  ] as const;
  for (const [field, expected] of expectedFields) {
    if (
      hasOwn(input.request, field) &&
      asTrimmedString(input.request[field]) !== expected
    ) {
      throw new LocalizationContractError(
        LOCALIZATION_ERROR_CODES.profileContextMismatch,
        400,
      );
    }
  }

  if (
    !contentLocales.includes(profile.content_locale) ||
    !jurisdictionCountries.includes(profile.jurisdiction_country)
  ) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.invalidContext,
      500,
    );
  }

  const persistedMethod = requireRiskMethod(input.persistedMethod);
  const method = hasOwn(input.request, "method")
    ? requireRiskMethod(input.request.method)
    : persistedMethod;
  if (method !== persistedMethod) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.methodMismatch,
      409,
    );
  }
  if (!profile.allowed_risk_methods.includes(method)) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.methodNotAllowed,
      400,
    );
  }

  return {
    schema_version: LOCALIZATION_SNAPSHOT_SCHEMA_VERSION,
    output_language: profile.language,
    output_locale: profile.content_locale,
    work_jurisdiction_country: profile.jurisdiction_country,
    work_jurisdiction_region: hasOwn(
        input.request,
        "work_jurisdiction_region",
      )
      ? asOptionalRegion(input.request.work_jurisdiction_region)
      : profile.jurisdiction_region,
    safety_profile_id: profile.id,
    safety_profile_version: profile.profile_version,
    regulatory_reference_policy: profile.regulatory_reference_policy,
    prompt_profile_version: LOCALIZATION_PROMPT_PROFILE_VERSION,
    method,
    legal_document_set: profile.language === "tr"
      ? "tr-current"
      : "en-global-v1",
    legislation_canvas_enabled: profile.legislation_canvas_enabled,
    structured_regulatory_references_enabled:
      profile.structured_regulatory_references_enabled,
    manifest_version: safetyProfileManifestVersion,
    manifest_source_sha256: safetyProfileSourceSHA256,
    source: explicit ? "explicit_request" : "legacy_tr_default",
  };
}

type FlagValue = {
  rollout_mode?: unknown;
  enabled_user_hashes?: unknown;
  enabled_ios_builds?: unknown;
  min_ios_build?: unknown;
  kill_switch?: unknown;
};

export type LocalizationRolloutContext = {
  userHash: string;
  clientBuild: string | null;
  // F3 (Android review, 2026-08-06): build_allowlist/min_build flag values below are
  // *_ios_builds/min_ios_build — platform-specific by name. Without this field an Android
  // client whose versionCode collides with a historical iOS build number would silently
  // unlock these flags. Defaults to "ios" only at call sites written before this field
  // existed would be wrong — every caller must now pass the real client platform explicitly.
  platform: string;
  globalLocalizationCapability: boolean;
  approvedSafetyProfileSourceSHA256: string | null;
};

function normalizedBuild(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const build = value.trim();
  return /^[1-9][0-9]{0,8}$/.test(build) ? build : null;
}

function normalizedBuildNumber(value: unknown): number | null {
  const build = typeof value === "number"
    ? value
    : normalizedBuild(value) == null
    ? Number.NaN
    : Number(value);
  return Number.isInteger(build) && build > 0 && build <= 999_999_999
    ? build
    : null;
}

export function localizationFlagEnabled(
  value: FlagValue | null,
  context: LocalizationRolloutContext,
): boolean {
  if (value?.kill_switch === true) return false;
  const mode = typeof value?.rollout_mode === "string"
    ? value.rollout_mode
    : "off";
  if (mode === "on") return true;
  if (mode === "allowlist") {
    return Array.isArray(value?.enabled_user_hashes) &&
      value.enabled_user_hashes.includes(context.userHash);
  }
  if (mode === "build_allowlist") {
    // F3: enabled_ios_builds is ios-only by name — fail closed for every other platform,
    // including "android" and "unknown", rather than matching on build number alone.
    if (context.platform !== "ios") return false;
    const clientBuild = normalizedBuild(context.clientBuild);
    if (
      clientBuild == null ||
      !Array.isArray(value?.enabled_ios_builds)
    ) {
      return false;
    }
    return value.enabled_ios_builds
      .map(normalizedBuild)
      .some((build) => build === clientBuild);
  }
  if (mode === "min_build") {
    // F3: min_ios_build is ios-only by name — same fail-closed rule as build_allowlist above.
    if (context.platform !== "ios") return false;
    const clientBuild = normalizedBuildNumber(context.clientBuild);
    const minimumBuild = normalizedBuildNumber(value?.min_ios_build);
    return clientBuild != null &&
      minimumBuild != null &&
      clientBuild >= minimumBuild;
  }
  return false;
}

function reviewerCohortAllows(
  value: FlagValue | null,
  context: LocalizationRolloutContext,
): boolean {
  return context.userHash.length > 0 &&
    Array.isArray(value?.enabled_user_hashes) &&
    value.enabled_user_hashes.includes(context.userHash);
}

/// Yayin modlari: sahibin bilerek "herkese ac" dedigi rollout modlari.
/// `allowlist` ve `build_allowlist` bilerek disaridadir — ikisi de yayin oncesi
/// modlardir ve gozden gecirme kohortuyla sinirli kalmalidir (bkz.
/// localization-context-resolver_test.ts, kohort disi kullanici testi).
function localizationRolloutIsPublic(value: FlagValue | null): boolean {
  const mode = typeof value?.rollout_mode === "string"
    ? value.rollout_mode
    : "off";
  return mode === "on" || mode === "min_build";
}

function preReleaseLocalizationFlagEnabled(
  value: FlagValue | null,
  context: LocalizationRolloutContext,
): boolean {
  // Rollout modunun kendi kosulu her zaman gecerlidir.
  if (!localizationFlagEnabled(value, context)) return false;
  // Yayin oncesi modlarda (allowlist / build_allowlist) ek olarak gozden gecirme
  // kohortu aranir. `on` ve `min_build` ise bilincli birer yayin kararidir; aksi
  // halde bu iki mod hicbir zaman kohort disina cikamaz ve anlamsizlasirdi.
  return localizationRolloutIsPublic(value) ||
    reviewerCohortAllows(value, context);
}

export async function loadLocalizationRolloutPolicy(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  context: LocalizationRolloutContext,
): Promise<LocalizationRolloutPolicy> {
  const keysByProfileID = new Map([
    ["en-intl-generic-v1", "safety_profile_en_intl_enabled"],
    ["en-gb-generic-v1", "safety_profile_en_gb_enabled"],
    ["en-us-generic-v1", "safety_profile_en_us_enabled"],
    ["en-au-generic-v1", "safety_profile_en_au_enabled"],
    ["en-ca-generic-v1", "safety_profile_en_ca_enabled"],
  ]);
  const keys = [
    "localization_v2",
    "english_product_enabled",
    "global_localization_wave1",
    "localization_queue_payload_v1",
    ...keysByProfileID.values(),
  ];
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("key,value")
    .in("key", keys);
  if (error) {
    return {
      enabledProfileIDs: new Set(),
      queueSnapshotAuthorityEnabled: false,
      approvedSafetyProfileSourceSHA256: null,
    };
  }
  const values = new Map<string, FlagValue>(
    (Array.isArray(data) ? data : []).map((row) => [row.key, row.value]),
  );
  const approvedSourceSHA256 =
    context.approvedSafetyProfileSourceSHA256 === safetyProfileSourceSHA256
      ? safetyProfileSourceSHA256
      : null;
  const globalEnabled = approvedSourceSHA256 !== null &&
    context.globalLocalizationCapability &&
    preReleaseLocalizationFlagEnabled(
      values.get("localization_v2") ?? null,
      context,
    ) &&
    preReleaseLocalizationFlagEnabled(
      values.get("english_product_enabled") ?? null,
      context,
    ) &&
    preReleaseLocalizationFlagEnabled(
      values.get("global_localization_wave1") ?? null,
      context,
    );
  const enabledProfileIDs = new Set<string>();
  if (globalEnabled) {
    for (const [profileID, key] of keysByProfileID) {
      if (
        preReleaseLocalizationFlagEnabled(
          values.get(key) ?? null,
          context,
        )
      ) {
        enabledProfileIDs.add(profileID);
      }
    }
  }
  return {
    enabledProfileIDs,
    queueSnapshotAuthorityEnabled: globalEnabled &&
      preReleaseLocalizationFlagEnabled(
        values.get("localization_queue_payload_v1") ?? null,
        context,
      ),
    approvedSafetyProfileSourceSHA256: approvedSourceSHA256,
  };
}
