import type {
  AppLanguage,
  ContentLocale,
  JurisdictionCountry,
  LegalDocumentSetID,
  RegulatoryReferencePolicy,
  RiskMethod,
  SafetyProfileID,
} from "./approved-safety-profiles.generated.ts";

export const LOCALIZATION_SNAPSHOT_SCHEMA_VERSION = 1 as const;
export const LOCALIZATION_PROMPT_PROFILE_VERSION =
  "isg-photo-policy-v2026-07-single-multi-targets" as const;

export const LOCALIZATION_ERROR_CODES = {
  invalidContext: "INVALID_LOCALIZATION_CONTEXT",
  profileRequired: "SAFETY_PROFILE_REQUIRED",
  profileUnknown: "SAFETY_PROFILE_UNKNOWN",
  profileNotEnabled: "SAFETY_PROFILE_NOT_ENABLED",
  profileNotApproved: "SAFETY_PROFILE_NOT_APPROVED",
  profileVersionMismatch: "SAFETY_PROFILE_VERSION_MISMATCH",
  profileContextMismatch: "SAFETY_PROFILE_CONTEXT_MISMATCH",
  methodNotAllowed: "RISK_METHOD_NOT_ALLOWED_FOR_SAFETY_PROFILE",
  methodMismatch: "LOCALIZATION_METHOD_MISMATCH",
  snapshotInvalid: "LOCALIZATION_SNAPSHOT_INVALID",
  snapshotRequired: "LOCALIZATION_SNAPSHOT_REQUIRED",
  snapshotMismatch: "LOCALIZATION_SNAPSHOT_MISMATCH",
  canvasUnavailable: "CANVAS_NOT_AVAILABLE_FOR_SAFETY_PROFILE",
  snapshotPersistFailed: "LOCALIZATION_SNAPSHOT_PERSIST_FAILED",
  outputLanguageContractFailed: "OUTPUT_LANGUAGE_CONTRACT_FAILED",
} as const;

export type LocalizationErrorCode =
  (typeof LOCALIZATION_ERROR_CODES)[keyof typeof LOCALIZATION_ERROR_CODES];

export class LocalizationContractError extends Error {
  readonly code: LocalizationErrorCode;
  readonly status: number;

  constructor(code: LocalizationErrorCode, status = 400) {
    super(code);
    this.name = "LocalizationContractError";
    this.code = code;
    this.status = status;
  }
}

export type LocalizationRequest = {
  output_language?: unknown;
  output_locale?: unknown;
  work_jurisdiction_country?: unknown;
  work_jurisdiction_region?: unknown;
  safety_profile_id?: unknown;
  safety_profile_version?: unknown;
  method?: unknown;
};

export type LocalizationSnapshotSource =
  | "legacy_tr_default"
  | "explicit_request"
  | "legacy_tr_backfill";

export type LocalizationSnapshot = {
  schema_version: typeof LOCALIZATION_SNAPSHOT_SCHEMA_VERSION;
  output_language: AppLanguage;
  output_locale: ContentLocale;
  work_jurisdiction_country: JurisdictionCountry;
  work_jurisdiction_region: string | null;
  safety_profile_id: SafetyProfileID;
  safety_profile_version: number;
  regulatory_reference_policy: RegulatoryReferencePolicy;
  prompt_profile_version: typeof LOCALIZATION_PROMPT_PROFILE_VERSION;
  method: RiskMethod;
  legal_document_set: LegalDocumentSetID;
  legislation_canvas_enabled: boolean;
  structured_regulatory_references_enabled: boolean;
  manifest_version: number;
  manifest_source_sha256: string;
  source: LocalizationSnapshotSource;
};

export type LocalizationPersistencePatch = {
  output_language: AppLanguage;
  output_locale: ContentLocale;
  work_jurisdiction_country: JurisdictionCountry;
  work_jurisdiction_region: string | null;
  safety_profile_id: SafetyProfileID;
  safety_profile_version: number;
  regulatory_reference_policy: RegulatoryReferencePolicy;
  prompt_profile_version: typeof LOCALIZATION_PROMPT_PROFILE_VERSION;
  localization_snapshot: LocalizationSnapshot;
  language_validation_status: "not_evaluated";
  language_validation_attempts: 0;
  language_validation_code: null;
};

export const LOCALIZATION_REQUEST_FIELDS = [
  "output_language",
  "output_locale",
  "work_jurisdiction_country",
  "work_jurisdiction_region",
  "safety_profile_id",
  "safety_profile_version",
  "method",
] as const;

export function hasLocalizationRequestFields(
  request: LocalizationRequest,
): boolean {
  return LOCALIZATION_REQUEST_FIELDS.some((field) =>
    Object.prototype.hasOwnProperty.call(request, field) &&
    request[field] !== undefined
  );
}

export function localizationPersistencePatch(
  snapshot: LocalizationSnapshot,
): LocalizationPersistencePatch {
  return {
    output_language: snapshot.output_language,
    output_locale: snapshot.output_locale,
    work_jurisdiction_country: snapshot.work_jurisdiction_country,
    work_jurisdiction_region: snapshot.work_jurisdiction_region,
    safety_profile_id: snapshot.safety_profile_id,
    safety_profile_version: snapshot.safety_profile_version,
    regulatory_reference_policy: snapshot.regulatory_reference_policy,
    prompt_profile_version: snapshot.prompt_profile_version,
    localization_snapshot: snapshot,
    language_validation_status: "not_evaluated",
    language_validation_attempts: 0,
    language_validation_code: null,
  };
}

export function localizationQueueGuard(snapshot: LocalizationSnapshot) {
  return {
    schema_version: snapshot.schema_version,
    safety_profile_id: snapshot.safety_profile_id,
    safety_profile_version: snapshot.safety_profile_version,
    manifest_version: snapshot.manifest_version,
  };
}

export function stripLocalizationRequestFields(
  body: Record<string, unknown>,
): Record<string, unknown> {
  const result = { ...body };
  for (const field of LOCALIZATION_REQUEST_FIELDS) delete result[field];
  return result;
}
