#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { isAbsolute, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

const repositoryRoot = resolve(import.meta.dirname, "..");
const evidenceRelativePath =
  "docs/localization/phase-5/PHASE_5_EXTERNAL_GATE_EVIDENCE_2026-07-31.json";
const expectedProjectRef = "ppcrzemgiztzcgddbins";
const requiredLegalKinds = new Set(["terms", "privacy", "consent"]);
const requiredPublicURLKeys = new Set([
  "terms",
  "privacy",
  "ai_data_processing_notice",
]);
const requiredSmokeTests = new Set([
  "tr_signup",
  "en_signup",
  "tr_recovery",
  "en_recovery",
  "secure_email_change",
]);
const legalPageMarkers = {
  terms: "Terms of Use",
  privacy: "Privacy Policy",
  ai_data_processing_notice: "AI and Data Processing Notice",
};

export const sha256 = (value) =>
  createHash("sha256").update(value).digest("hex");

const readUTF8 = (absolutePath) => readFileSync(absolutePath, "utf8");
const parseJSON = (absolutePath) => JSON.parse(readUTF8(absolutePath));
const isSHA256 = (value) => /^[a-f0-9]{64}$/u.test(value ?? "");
const isNonEmpty = (value) =>
  typeof value === "string" && value.trim().length > 0;
const isTimestamp = (value) =>
  isNonEmpty(value) && Number.isFinite(Date.parse(value));
const sameStringSet = (actual, expected) =>
  Array.isArray(actual) &&
  new Set(actual).size === expected.size &&
  [...expected].every((value) => actual.includes(value));

function resolveRepositoryPath(path, integrityErrors, label) {
  if (!isNonEmpty(path) || isAbsolute(path)) {
    integrityErrors.push(`${label}: repository-relative path required`);
    return null;
  }
  const absolute = resolve(repositoryRoot, path);
  const rel = relative(repositoryRoot, absolute);
  if (rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) {
    integrityErrors.push(`${label}: path escapes repository root`);
    return null;
  }
  return absolute;
}

function requireExactKeys(actual, expected, issues, label) {
  const actualKeys = new Set(Object.keys(actual ?? {}));
  if (
    actualKeys.size !== expected.size ||
    [...expected].some((key) => !actualKeys.has(key))
  ) {
    issues.push(`${label}: exact keys must be ${[...expected].join(", ")}`);
  }
}

function validateDocumentIntegrity(manifest, integrityErrors) {
  if (manifest.schema_version !== 1) {
    integrityErrors.push("LEGAL-EN: schema_version must be 1");
  }
  if (manifest.document_set_id !== "en-global-v1") {
    integrityErrors.push("LEGAL-EN: document_set_id must be en-global-v1");
  }
  if (manifest.locale !== "en") {
    integrityErrors.push("LEGAL-EN: locale must be en");
  }
  if (!Array.isArray(manifest.documents)) {
    integrityErrors.push("LEGAL-EN: documents must be an array");
    return;
  }

  const kinds = new Set(manifest.documents.map((document) => document.kind));
  if (
    kinds.size !== requiredLegalKinds.size ||
    [...requiredLegalKinds].some((kind) => !kinds.has(kind))
  ) {
    integrityErrors.push(
      "LEGAL-EN: exact document kinds must be terms, privacy, consent",
    );
  }

  for (const document of manifest.documents) {
    const path = resolveRepositoryPath(
      `App/LegalDocuments/${document.path ?? ""}`,
      integrityErrors,
      `LEGAL-EN:${document.kind ?? "unknown"}`,
    );
    if (!path) continue;
    if (!document.path?.startsWith("en/")) {
      integrityErrors.push(
        `LEGAL-EN:${document.kind ?? "unknown"}: path must start with en/`,
      );
      continue;
    }
    try {
      const actualHash = sha256(readFileSync(path));
      if (actualHash !== document.hash) {
        integrityErrors.push(
          `LEGAL-EN:${document.kind}: document hash mismatch`,
        );
      }
    } catch {
      integrityErrors.push(`LEGAL-EN:${document.kind}: document file missing`);
    }
  }
}

function validateLegalApprovalIntegrity({
  manifest,
  evidence,
  approvalRecord,
  approvalRecordHash,
  integrityErrors,
}) {
  const review = evidence?.counsel_review_evidence ?? {};

  if (
    approvalRecord.schema_version !== 1 ||
    approvalRecord.document_set_id !== manifest.document_set_id ||
    approvalRecord.locale !== manifest.locale ||
    approvalRecord.reviewed_preapproval_manifest_path !==
      evidence?.manifest_path ||
    !isSHA256(approvalRecord.reviewed_preapproval_manifest_sha256) ||
    approvalRecord.reviewed_preapproval_manifest_sha256 !==
      review.reviewed_preapproval_manifest_sha256
  ) {
    integrityErrors.push("LEGAL-EN: counsel approval record contract is invalid");
  }
  if (
    manifest.counsel_approval_record_path !== review.approval_record_path ||
    manifest.counsel_approval_record_sha256 !== approvalRecordHash ||
    review.approval_record_sha256 !== approvalRecordHash
  ) {
    integrityErrors.push(
      "LEGAL-EN: counsel approval record path or hash integrity mismatch",
    );
  }
  if (
    approvalRecord.decision !== review.decision ||
    approvalRecord.reviewer_name !== review.reviewer_name ||
    approvalRecord.reviewer_name !== manifest.reviewed_by ||
    approvalRecord.reviewer_qualification !== review.reviewer_qualification ||
    approvalRecord.reviewer_qualification !== manifest.reviewer_qualification ||
    approvalRecord.reviewed_at !== review.reviewed_at ||
    approvalRecord.reviewed_at !== manifest.reviewed_at
  ) {
    integrityErrors.push(
      "LEGAL-EN: counsel approval record, manifest and external evidence disagree",
    );
  }

  if (
    !Array.isArray(approvalRecord.reviewed_documents) ||
    !Array.isArray(manifest.documents)
  ) {
    integrityErrors.push(
      "LEGAL-EN: counsel approval must contain the reviewed document set",
    );
    return;
  }
  const approvedKinds = new Set(
    approvalRecord.reviewed_documents.map((document) => document.kind),
  );
  if (
    approvedKinds.size !== requiredLegalKinds.size ||
    [...requiredLegalKinds].some((kind) => !approvedKinds.has(kind))
  ) {
    integrityErrors.push(
      "LEGAL-EN: counsel approval must cover terms, privacy and consent",
    );
  }
  for (const document of manifest.documents) {
    const approvedDocument = approvalRecord.reviewed_documents.find(
      (candidate) => candidate.kind === document.kind,
    );
    if (
      approvedDocument?.path !== document.path ||
      approvedDocument?.sha256 !== document.hash
    ) {
      integrityErrors.push(
        `LEGAL-EN:${document.kind}: current document is outside counsel approval`,
      );
    }
  }
}

export function validateLegalHTTPResponse({
  key,
  requestedURL,
  finalURL,
  status,
  contentType,
  body,
}) {
  const issues = [];
  let parsedRequested;
  let parsedFinal;
  try {
    parsedRequested = new URL(requestedURL);
    parsedFinal = new URL(finalURL);
  } catch {
    return ["LEGAL-EN: invalid requested or final public URL"];
  }

  if (
    parsedRequested.protocol !== "https:" ||
    parsedRequested.hostname.toLowerCase() !== "riskdetected.com" ||
    parsedRequested.pathname === "/"
  ) {
    issues.push(`LEGAL-EN:${key}: URL must be a non-root riskdetected.com HTTPS URL`);
  }
  if (
    parsedFinal.protocol !== "https:" ||
    parsedFinal.hostname.toLowerCase() !== "riskdetected.com"
  ) {
    issues.push(`LEGAL-EN:${key}: redirect left riskdetected.com HTTPS`);
  }
  if (status !== 200) {
    issues.push(`LEGAL-EN:${key}: HTTP status must be 200`);
  }
  if (!/text\/html|text\/markdown|text\/plain/iu.test(contentType ?? "")) {
    issues.push(`LEGAL-EN:${key}: unsupported content type`);
  }
  if (Buffer.byteLength(body ?? "", "utf8") < 500) {
    issues.push(`LEGAL-EN:${key}: response body is too small`);
  }
  if (/<html[^>]*\blang=["']?tr(?:[-_"'\s>])/iu.test(body ?? "")) {
    issues.push(`LEGAL-EN:${key}: Turkish HTML locale fallback detected`);
  }
  if (
    /Kullanım Koşulları|Gizlilik Politikası|Açık Rıza|KVKK Aydınlatma/iu.test(
      body ?? "",
    )
  ) {
    issues.push(`LEGAL-EN:${key}: Turkish legal content detected`);
  }
  const expectedMarker = legalPageMarkers[key];
  if (!expectedMarker || !(body ?? "").includes(expectedMarker)) {
    issues.push(`LEGAL-EN:${key}: expected English document marker missing`);
  }
  return issues;
}

async function verifyLiveLegalURL(key, requestedURL, fetchImplementation) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetchImplementation(requestedURL, {
      redirect: "follow",
      headers: {
        accept: "text/html,text/markdown,text/plain",
        "user-agent": "RiskDetected-Phase5-Release-Gate/1.0",
      },
      signal: controller.signal,
    });
    const body = await response.text();
    return validateLegalHTTPResponse({
      key,
      requestedURL,
      finalURL: response.url || requestedURL,
      status: response.status,
      contentType: response.headers.get("content-type"),
      body,
    });
  } catch (error) {
    return [`LEGAL-EN:${key}: live request failed (${error.name ?? "Error"})`];
  } finally {
    clearTimeout(timeout);
  }
}

function validateLegalEvidence({
  manifest,
  evidence,
  approvalRecord,
  approvalRecordHash,
  live,
}) {
  const blockers = [];
  const review = evidence?.counsel_review_evidence ?? {};
  const publicEvidence = evidence?.public_url_evidence ?? {};

  if (manifest.release_status !== "approved") {
    blockers.push("LEGAL-EN: release_status is not approved");
  }
  if (manifest.counsel_review_status !== "approved") {
    blockers.push("LEGAL-EN: counsel_review_status is not approved");
  }
  if (!isNonEmpty(manifest.reviewed_by)) {
    blockers.push("LEGAL-EN: manifest reviewed_by is missing");
  }
  if (!isTimestamp(manifest.reviewed_at)) {
    blockers.push("LEGAL-EN: manifest reviewed_at is missing or invalid");
  }
  if (!isNonEmpty(manifest.reviewer_qualification)) {
    blockers.push("LEGAL-EN: manifest reviewer_qualification is missing");
  }
  if (review.decision !== "approved") {
    blockers.push("LEGAL-EN: counsel evidence decision is not approved");
  }
  if (!isNonEmpty(review.reviewer_name)) {
    blockers.push("LEGAL-EN: counsel reviewer name is missing");
  }
  if (!isNonEmpty(review.reviewer_qualification)) {
    blockers.push("LEGAL-EN: counsel reviewer qualification is missing");
  }
  if (!isTimestamp(review.reviewed_at)) {
    blockers.push("LEGAL-EN: counsel reviewed_at is missing or invalid");
  }
  if (
    approvalRecord?.decision !== "approved" ||
    review.approval_record_sha256 !== approvalRecordHash
  ) {
    blockers.push("LEGAL-EN: counsel approval record is not valid");
  }

  requireExactKeys(
    manifest.public_urls,
    requiredPublicURLKeys,
    blockers,
    "LEGAL-EN:public_urls",
  );
  if (!isTimestamp(manifest.public_urls_verified_at)) {
    blockers.push("LEGAL-EN: public_urls_verified_at is missing or invalid");
  }
  if (publicEvidence.status !== "verified") {
    blockers.push("LEGAL-EN: public URL evidence is not verified");
  }
  if (!isTimestamp(publicEvidence.verified_at)) {
    blockers.push("LEGAL-EN: public URL evidence timestamp is missing or invalid");
  }
  if (!isSHA256(publicEvidence.verification_sha256)) {
    blockers.push("LEGAL-EN: public URL verification digest is missing");
  }
  if (!live) {
    blockers.push("LEGAL-EN: live URL verification was not executed");
  }

  return blockers;
}

function validateLegalProductionIntegrity({
  evidence,
  manifest,
  manifestHash,
  approvalRecordHash,
  integrityErrors,
}) {
  const publicEvidence = evidence?.legal?.public_url_evidence ?? {};
  const verificationPath = resolveRepositoryPath(
    publicEvidence.verification_path,
    integrityErrors,
    "LEGAL-EN:production_verification_path",
  );
  if (!verificationPath) return;

  const verification = parseJSON(verificationPath);
  const verificationHash = sha256(readFileSync(verificationPath));
  if (publicEvidence.verification_sha256 !== verificationHash) {
    integrityErrors.push("LEGAL-EN: production evidence integrity mismatch");
  }

  const safety = verification.publication_safety ?? {};
  const deployment = verification.deployment ?? {};
  const approval = verification.approval ?? {};
  const verifiedManifest = verification.manifest ?? {};
  if (
    verification.schema_version !== 1 ||
    publicEvidence.status !== "verified" ||
    publicEvidence.verified_at !== verification.verified_at ||
    publicEvidence.deployment_id !== deployment.id ||
    deployment.target !== "production" ||
    deployment.ready !== true ||
    deployment.blue_green_candidate_verified_before_promotion !== true ||
    deployment.promoted_after_verification !== true ||
    safety.source_git_commit_matched_previous_production !== true ||
    safety.isolated_clean_export_used !== true ||
    safety.unrelated_dirty_worktree_changes_deployed !== false ||
    safety.root_html_regression !== false ||
    safety.ios_runtime_activation !== false ||
    safety.supabase_localization_rollout_activation !== false ||
    safety.notification_delivery_activation !== false ||
    safety.app_store_release !== false ||
    approval.record_sha256 !== approvalRecordHash ||
    verifiedManifest.path !== evidence.legal?.manifest_path ||
    verifiedManifest.sha256 !== manifestHash ||
    verifiedManifest.release_status !== "approved" ||
    verifiedManifest.public_urls_verified_at !== manifest.public_urls_verified_at
  ) {
    integrityErrors.push("LEGAL-EN: production publication contract is invalid");
  }

  const expectedHashes = Object.fromEntries(
    (manifest.documents ?? []).map((document) => [
      document.kind,
      document.hash,
    ]),
  );
  const expectedURLs = manifest.public_urls ?? {};
  const documents = verification.documents ?? {};
  const documentContracts = [
    ["terms", "terms", "terms"],
    ["privacy", "privacy", "privacy"],
    ["ai_data_processing_notice", "consent", "ai_data_processing_notice"],
  ];
  requireExactKeys(
    documents,
    new Set(documentContracts.map(([verificationKey]) => verificationKey)),
    integrityErrors,
    "LEGAL-EN:production_documents",
  );
  for (const [verificationKey, manifestKind, urlKey] of documentContracts) {
    const document = documents[verificationKey] ?? {};
    if (
      document.status !== 200 ||
      !document.content_type?.startsWith("text/markdown") ||
      document.redirects !== 0 ||
      document.url !== expectedURLs[urlKey] ||
      document.sha256 !== expectedHashes[manifestKind] ||
      document.exact_approved_source_hash_match !== true ||
      document.english_content_marker_verified !== true ||
      document.draft_or_release_blocker_marker_present !== false
    ) {
      integrityErrors.push(
        `LEGAL-EN:${verificationKey}: production document contract is invalid`,
      );
    }
  }
}

function validateNotificationEvidence(
  evidence,
  packHash,
  approvalRecord,
  approvalRecordHash,
) {
  const blockers = [];
  if (evidence.decision !== "approved") {
    blockers.push("NOTIFICATION-COPY: decision is not approved");
  }
  if (!isNonEmpty(evidence.reviewer_name)) {
    blockers.push("NOTIFICATION-COPY: reviewer name is missing");
  }
  if (!isNonEmpty(evidence.reviewer_qualification)) {
    blockers.push("NOTIFICATION-COPY: reviewer qualification is missing");
  }
  if (!isTimestamp(evidence.reviewed_at)) {
    blockers.push("NOTIFICATION-COPY: reviewed_at is missing or invalid");
  }
  if (evidence.review_pack_sha256 !== packHash) {
    blockers.push("NOTIFICATION-COPY: approval is not bound to this review pack");
  }
  if (
    evidence.approval_record_sha256 !== approvalRecordHash ||
    approvalRecord?.review_pack_sha256 !== packHash
  ) {
    blockers.push(
      "NOTIFICATION-COPY: approval record is not bound to this review pack",
    );
  }
  if (
    approvalRecord?.decision !== evidence.decision ||
    approvalRecord?.reviewer_name !== evidence.reviewer_name ||
    approvalRecord?.reviewer_qualification !==
      evidence.reviewer_qualification ||
    approvalRecord?.reviewed_at !== evidence.reviewed_at
  ) {
    blockers.push(
      "NOTIFICATION-COPY: approval record and external evidence disagree",
    );
  }
  if (
    !sameStringSet(
      approvalRecord?.approved_locales,
      new Set(["en-001", "en-GB", "en-US", "en-AU", "en-CA"]),
    ) ||
    !sameStringSet(
      approvalRecord?.approved_automation_template_keys,
      new Set([
        "first_analysis_reminder_v1",
        "inactivity_reminder_v1",
      ]),
    ) ||
    approvalRecord?.approved_exact_locale_rows !== 10 ||
    evidence.approved_repository_seed_rows !== 10
  ) {
    blockers.push(
      "NOTIFICATION-COPY: repository approval must cover 10 exact-locale rows",
    );
  }
  if (evidence.production_approved_exact_locale_rows !== 10) {
    blockers.push(
      "NOTIFICATION-COPY: 10 production exact-locale rows are not verified",
    );
  }
  if (!isTimestamp(evidence.production_rows_verified_at)) {
    blockers.push(
      "NOTIFICATION-COPY: production verification timestamp is missing or invalid",
    );
  }
  if (!isSHA256(evidence.production_verification_sha256)) {
    blockers.push("NOTIFICATION-COPY: production verification digest is missing");
  }
  return blockers;
}

function validateNotificationProductionVerification({
  evidence,
  verification,
  verificationHash,
  integrityErrors,
}) {
  if (
    evidence.production_verification_sha256 !== verificationHash ||
    !isSHA256(verificationHash)
  ) {
    integrityErrors.push(
      "NOTIFICATION-COPY: production verification integrity mismatch",
    );
  }
  if (
    verification.schema_version !== 1 ||
    verification.project_ref !== expectedProjectRef ||
    !isTimestamp(verification.verified_at) ||
    verification.verified_at !== evidence.production_rows_verified_at
  ) {
    integrityErrors.push(
      "NOTIFICATION-COPY: production verification contract is invalid",
    );
  }

  const approvedCopy = verification.approved_copy ?? {};
  const rows = approvedCopy.rows;
  const expectedLocales = new Set([
    "en-001",
    "en-AU",
    "en-CA",
    "en-GB",
    "en-US",
  ]);
  const expectedTemplates = new Set([
    "first_analysis_reminder_v1",
    "inactivity_reminder_v1",
  ]);
  const rowKeys = Array.isArray(rows)
    ? rows.map((row) => `${row.template_key}|${row.locale}`)
    : [];
  if (
    verification.migration_ledger?.row_count !== 114 ||
    !Array.isArray(verification.migration_ledger?.required_tail) ||
    !sameStringSet(
      verification.migration_ledger.required_tail.map((entry) => entry.version),
      new Set([
        "20260728201500",
        "20260728202000",
        "20260728203000",
        "20260730213000",
      ]),
    ) ||
    verification.migration_ledger.required_tail.some(
      (entry) => !isSHA256(entry.source_sha256),
    )
  ) {
    integrityErrors.push(
      "NOTIFICATION-COPY: production migration ledger evidence is invalid",
    );
  }
  if (
    approvedCopy.row_count !== 10 ||
    approvedCopy.template_count !== 2 ||
    !sameStringSet(approvedCopy.locales, expectedLocales) ||
    approvedCopy.reviewer_name !== evidence.reviewer_name ||
    approvedCopy.reviewer_qualification !== evidence.reviewer_qualification ||
    approvedCopy.reviewed_at !== evidence.reviewed_at ||
    approvedCopy.review_pack_sha256 !== evidence.review_pack_sha256 ||
    approvedCopy.approval_record_sha256 !== evidence.approval_record_sha256 ||
    !isSHA256(approvedCopy.production_content_sha256) ||
    !Array.isArray(rows) ||
    rows.length !== 10 ||
    new Set(rowKeys).size !== 10 ||
    rows.some(
      (row) =>
        !expectedTemplates.has(row.template_key) ||
        !expectedLocales.has(row.locale) ||
        !isSHA256(row.checksum),
    )
  ) {
    integrityErrors.push(
      "NOTIFICATION-COPY: approved production row evidence is invalid",
    );
  }

  const access = verification.access_control ?? {};
  if (
    [
      "notification_localizations_rls_enabled",
      "anon_select_revoked",
      "authenticated_select_revoked",
      "service_role_select_granted",
      "checksum_trigger_present",
      "job_localization_trigger_present",
      "service_role_delivery_rpc_granted",
      "authenticated_delivery_rpc_revoked",
    ].some((key) => access[key] !== true)
  ) {
    integrityErrors.push(
      "NOTIFICATION-COPY: production access-control evidence is invalid",
    );
  }

  const automation = verification.automation_safety ?? {};
  if (
    automation.feature_flag_key !== "engagement_notification_automation" ||
    !isTimestamp(automation.feature_flag_updated_at) ||
    automation.rules?.shadow !== 2 ||
    automation.jobs?.shadow !== 3 ||
    automation.active_rule_count !== 0 ||
    automation.pending_delivery_job_count !== 0 ||
    automation.delivery_activated_by_localization_migration !== false
  ) {
    integrityErrors.push(
      "NOTIFICATION-COPY: automation shadow-safety evidence is invalid",
    );
  }

  if (
    verification.post_migration_advisors
      ?.new_localization_tables_warn_or_error_count !== 0 ||
    verification.post_migration_advisors
      ?.new_localization_tables_info_only !== true ||
    verification.privacy?.user_identifiers_captured !== false ||
    verification.privacy?.recipient_addresses_captured !== false ||
    verification.privacy?.secret_values_or_digests_captured !== false
  ) {
    integrityErrors.push(
      "NOTIFICATION-COPY: advisor or privacy evidence is invalid",
    );
  }
}

function validateAuthHookEvidence(evidence, runbookHash) {
  const blockers = [];
  if (evidence.activation_runbook_sha256 !== runbookHash) {
    blockers.push("AUTH-EMAIL-HOOK: activation evidence uses a stale runbook");
  }
  if (evidence.function_name !== "auth-send-email-hook") {
    blockers.push("AUTH-EMAIL-HOOK: unexpected function name");
  }
  if (evidence.function_deployed !== true || !isTimestamp(evidence.deployed_at)) {
    blockers.push("AUTH-EMAIL-HOOK: production deployment is not verified");
  }
  if (!isNonEmpty(evidence.deployment_version)) {
    blockers.push("AUTH-EMAIL-HOOK: deployment version is missing");
  }
  if (
    evidence.hook_activated !== true ||
    !isTimestamp(evidence.hook_activated_at)
  ) {
    blockers.push("AUTH-EMAIL-HOOK: dashboard hook activation is not verified");
  }
  if (evidence.secret_name_present !== true) {
    blockers.push("AUTH-EMAIL-HOOK: SEND_EMAIL_HOOK_SECRET name is not verified");
  }
  if (evidence.secret_value_recorded !== false) {
    blockers.push("AUTH-EMAIL-HOOK: secret value must never be recorded");
  }
  requireExactKeys(
    evidence.smoke_tests,
    requiredSmokeTests,
    blockers,
    "AUTH-EMAIL-HOOK:smoke_tests",
  );
  for (const smoke of requiredSmokeTests) {
    if (evidence.smoke_tests?.[smoke] !== "passed") {
      blockers.push(`AUTH-EMAIL-HOOK:${smoke}: smoke test has not passed`);
    }
  }
  if (!isTimestamp(evidence.smoke_completed_at)) {
    blockers.push("AUTH-EMAIL-HOOK: smoke completion timestamp is missing");
  }
  if (!isSHA256(evidence.production_verification_sha256)) {
    blockers.push("AUTH-EMAIL-HOOK: production verification digest is missing");
  }
  return blockers;
}

function validateAuthHookProductionVerification({
  evidence,
  verification,
  verificationHash,
  integrityErrors,
}) {
  if (
    evidence.production_verification_sha256 !== verificationHash ||
    !isSHA256(verificationHash)
  ) {
    integrityErrors.push(
      "AUTH-EMAIL-HOOK: production verification integrity mismatch",
    );
  }
  if (
    verification.schema_version !== 1 ||
    verification.project_ref !== expectedProjectRef ||
    !isTimestamp(verification.verified_at)
  ) {
    integrityErrors.push(
      "AUTH-EMAIL-HOOK: production verification contract is invalid",
    );
  }
  if (
    verification.function?.name !== evidence.function_name ||
    verification.function?.status !== "ACTIVE" ||
    String(verification.function?.version ?? "") !==
      evidence.deployment_version ||
    verification.function?.verify_jwt !== false ||
    verification.function?.deployed_at !== evidence.deployed_at
  ) {
    integrityErrors.push(
      "AUTH-EMAIL-HOOK: function deployment evidence disagrees",
    );
  }
  if (
    verification.hook?.type !== "send_email" ||
    verification.hook?.transport !== "https" ||
    verification.hook?.enabled !== true ||
    verification.hook?.activated_at !== evidence.hook_activated_at ||
    verification.hook?.endpoint_matches_deployed_function !== true
  ) {
    integrityErrors.push("AUTH-EMAIL-HOOK: hook activation evidence disagrees");
  }
  if (
    verification.secrets?.secret_values_or_digests_captured !== false ||
    verification.secret_value_recorded !== false ||
    !sameStringSet(
      verification.secrets?.required_names_present,
      new Set([
        "SEND_EMAIL_HOOK_SECRET",
        "RESEND_API_KEY",
        "RESEND_FROM_EMAIL",
      ]),
    )
  ) {
    integrityErrors.push("AUTH-EMAIL-HOOK: secret evidence contract is invalid");
  }
  const smokeTests = verification.smoke_tests;
  if (
    !Array.isArray(smokeTests) ||
    !sameStringSet(
      smokeTests.map((smoke) => smoke.id),
      requiredSmokeTests,
    ) ||
    smokeTests.some(
      (smoke) => smoke.result !== "passed" || smoke.status_code !== 200,
    ) ||
    verification.smoke_completed_at !== evidence.smoke_completed_at
  ) {
    integrityErrors.push("AUTH-EMAIL-HOOK: smoke evidence contract is invalid");
  }
  const invalidSignature = verification.security_tests?.find(
    (test) => test.id === "invalid_signature_fail_closed",
  );
  if (
    invalidSignature?.result !== "passed" ||
    invalidSignature?.status_code !== 401 ||
    invalidSignature?.error_code !== "invalid_webhook_signature"
  ) {
    integrityErrors.push(
      "AUTH-EMAIL-HOOK: invalid-signature fail-closed evidence is missing",
    );
  }
  if (
    verification.production_user_records_created !== false ||
    verification.recipient_addresses_recorded !== false
  ) {
    integrityErrors.push(
      "AUTH-EMAIL-HOOK: production smoke privacy contract is invalid",
    );
  }
}

export async function evaluatePhase5ExternalGates({
  live = false,
  fetchImplementation = globalThis.fetch,
} = {}) {
  const integrityErrors = [];
  const evidencePath = resolve(repositoryRoot, evidenceRelativePath);
  const evidence = parseJSON(evidencePath);

  if (evidence.schema_version !== 1) {
    integrityErrors.push("evidence schema_version must be 1");
  }
  if (evidence.project_ref !== expectedProjectRef) {
    integrityErrors.push("evidence project_ref does not match production");
  }
  if (!isTimestamp(evidence.updated_at)) {
    integrityErrors.push("evidence updated_at is missing or invalid");
  }
  if ("secret_value" in (evidence.auth_email_hook ?? {})) {
    integrityErrors.push("AUTH-EMAIL-HOOK: secret values are forbidden in evidence");
  }

  const productionSnapshotPath = resolveRepositoryPath(
    evidence.production_read_only_snapshot_path,
    integrityErrors,
    "production_read_only_snapshot_path",
  );
  if (productionSnapshotPath) {
    const productionSnapshot = parseJSON(productionSnapshotPath);
    const productionSnapshotHash = sha256(readFileSync(productionSnapshotPath));
    if (
      evidence.production_read_only_snapshot_sha256 !== productionSnapshotHash
    ) {
      integrityErrors.push("production read-only snapshot integrity mismatch");
    }
    if (
      productionSnapshot.schema_version !== 1 ||
      productionSnapshot.project_ref !== expectedProjectRef ||
      productionSnapshot.mutation_performed !== false ||
      productionSnapshot.auth_email_hook?.secret_values_or_digests_captured !==
        false
    ) {
      integrityErrors.push("production read-only snapshot contract is invalid");
    }
  }

  const manifestPath = resolveRepositoryPath(
    evidence.legal?.manifest_path,
    integrityErrors,
    "LEGAL-EN:manifest_path",
  );
  const manifest = manifestPath ? parseJSON(manifestPath) : {};
  const manifestHash = manifestPath
    ? sha256(readFileSync(manifestPath))
    : null;
  validateDocumentIntegrity(manifest, integrityErrors);

  const legalApprovalRecordPath = resolveRepositoryPath(
    evidence.legal?.counsel_review_evidence?.approval_record_path,
    integrityErrors,
    "LEGAL-EN:approval_record_path",
  );
  const legalApprovalRecord = legalApprovalRecordPath
    ? parseJSON(legalApprovalRecordPath)
    : {};
  const legalApprovalRecordHash = legalApprovalRecordPath
    ? sha256(readFileSync(legalApprovalRecordPath))
    : null;
  validateLegalApprovalIntegrity({
    manifest,
    evidence: evidence.legal,
    approvalRecord: legalApprovalRecord,
    approvalRecordHash: legalApprovalRecordHash,
    integrityErrors,
  });
  validateLegalProductionIntegrity({
    evidence,
    manifest,
    manifestHash,
    approvalRecordHash: legalApprovalRecordHash,
    integrityErrors,
  });

  const reviewPackPath = resolveRepositoryPath(
    evidence.notification_copy?.review_pack_path,
    integrityErrors,
    "NOTIFICATION-COPY:review_pack_path",
  );
  const reviewPackHash = reviewPackPath
    ? sha256(readFileSync(reviewPackPath))
    : null;
  if (
    reviewPackHash &&
    evidence.notification_copy?.review_pack_sha256 !== reviewPackHash
  ) {
    integrityErrors.push("NOTIFICATION-COPY: review pack integrity mismatch");
  }

  const approvalRecordPath = resolveRepositoryPath(
    evidence.notification_copy?.approval_record_path,
    integrityErrors,
    "NOTIFICATION-COPY:approval_record_path",
  );
  const approvalRecord = approvalRecordPath
    ? parseJSON(approvalRecordPath)
    : {};
  const approvalRecordHash = approvalRecordPath
    ? sha256(readFileSync(approvalRecordPath))
    : null;
  if (
    approvalRecordHash &&
    evidence.notification_copy?.approval_record_sha256 !== approvalRecordHash
  ) {
    integrityErrors.push("NOTIFICATION-COPY: approval record integrity mismatch");
  }
  if (
    approvalRecord.schema_version !== 1 ||
    approvalRecord.review_pack_path !==
      evidence.notification_copy?.review_pack_path
  ) {
    integrityErrors.push("NOTIFICATION-COPY: approval record contract is invalid");
  }
  const notificationVerificationPath = resolveRepositoryPath(
    evidence.notification_copy?.production_verification_path,
    integrityErrors,
    "NOTIFICATION-COPY:production_verification_path",
  );
  const notificationVerification = notificationVerificationPath
    ? parseJSON(notificationVerificationPath)
    : {};
  const notificationVerificationHash = notificationVerificationPath
    ? sha256(readFileSync(notificationVerificationPath))
    : null;
  validateNotificationProductionVerification({
    evidence: evidence.notification_copy ?? {},
    verification: notificationVerification,
    verificationHash: notificationVerificationHash,
    integrityErrors,
  });

  const runbookPath = resolveRepositoryPath(
    evidence.auth_email_hook?.activation_runbook_path,
    integrityErrors,
    "AUTH-EMAIL-HOOK:activation_runbook_path",
  );
  const runbookHash = runbookPath ? sha256(readFileSync(runbookPath)) : null;
  if (
    runbookHash &&
    evidence.auth_email_hook?.activation_runbook_sha256 !== runbookHash
  ) {
    integrityErrors.push("AUTH-EMAIL-HOOK: activation runbook integrity mismatch");
  }
  const authHookVerificationPath = resolveRepositoryPath(
    evidence.auth_email_hook?.production_verification_path,
    integrityErrors,
    "AUTH-EMAIL-HOOK:production_verification_path",
  );
  const authHookVerification = authHookVerificationPath
    ? parseJSON(authHookVerificationPath)
    : {};
  const authHookVerificationHash = authHookVerificationPath
    ? sha256(readFileSync(authHookVerificationPath))
    : null;
  validateAuthHookProductionVerification({
    evidence: evidence.auth_email_hook ?? {},
    verification: authHookVerification,
    verificationHash: authHookVerificationHash,
    integrityErrors,
  });

  const legalBlockers = validateLegalEvidence({
    manifest,
    evidence: evidence.legal,
    approvalRecord: legalApprovalRecord,
    approvalRecordHash: legalApprovalRecordHash,
    live,
  });
  if (live && manifest.public_urls) {
    for (const key of requiredPublicURLKeys) {
      const url = manifest.public_urls[key];
      if (isNonEmpty(url)) {
        legalBlockers.push(
          ...(await verifyLiveLegalURL(key, url, fetchImplementation)),
        );
      }
    }
  }

  const gates = [
    {
      id: "LEGAL-EN",
      status: legalBlockers.length === 0 ? "passed" : "blocked",
      blockers: legalBlockers,
    },
    {
      id: "NOTIFICATION-COPY",
      status: "blocked",
      blockers: validateNotificationEvidence(
        evidence.notification_copy ?? {},
        reviewPackHash,
        approvalRecord,
        approvalRecordHash,
      ),
    },
    {
      id: "AUTH-EMAIL-HOOK",
      status: "blocked",
      blockers: validateAuthHookEvidence(
        evidence.auth_email_hook ?? {},
        runbookHash,
      ),
    },
  ];
  for (const gate of gates) {
    gate.status = gate.blockers.length === 0 ? "passed" : "blocked";
  }

  return {
    schema_version: 1,
    phase: 5,
    project_ref: expectedProjectRef,
    checked_at: new Date().toISOString(),
    live_url_check: live,
    status:
      integrityErrors.length === 0 &&
      gates.every((gate) => gate.status === "passed")
        ? "passed"
        : "blocked",
    integrity_errors: integrityErrors,
    gates,
  };
}

export function parseCLI(argv) {
  const modeArgument = argv.find((argument) => argument.startsWith("--mode="));
  const mode = modeArgument?.split("=", 2)[1] ?? "current";
  if (!["current", "release"].includes(mode)) {
    throw new Error("--mode must be current or release");
  }
  return {
    mode,
    live: argv.includes("--live") || mode === "release",
    json: argv.includes("--json"),
  };
}

async function main() {
  const options = parseCLI(process.argv.slice(2));
  const report = await evaluatePhase5ExternalGates({ live: options.live });

  if (options.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log(`Phase 5 external gates: ${report.status}`);
    for (const gate of report.gates) {
      console.log(`${gate.id}: ${gate.status} (${gate.blockers.length} blocker)`);
    }
    for (const error of report.integrity_errors) {
      console.error(`integrity error: ${error}`);
    }
  }

  if (report.integrity_errors.length > 0) {
    process.exitCode = 1;
  } else if (options.mode === "release" && report.status !== "passed") {
    process.exitCode = 1;
  }
}

const invokedPath = process.argv[1]
  ? pathToFileURL(resolve(process.argv[1])).href
  : null;
if (invokedPath === import.meta.url) {
  await main();
}
