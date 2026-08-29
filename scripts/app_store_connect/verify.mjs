#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  APP_CONFIG,
  APP_ID,
  BUILD_ID,
  LOCALES,
  ROOT,
  SUBSCRIPTION_MANIFEST,
  SUBSCRIPTION_SOURCE,
  VERSION,
  assertLocalePolicy,
  assertMutableLocale,
  attributes,
  ensureScreenshotFiles,
  localeConfigs,
  metadataValidation,
  readJSON,
  rows,
  runAsc,
  versionRow,
  writeJSON,
} from "./_shared.mjs";
import {
  captureProtectedState,
  compareProtectedState,
} from "./protected-state.mjs";

const protectedBaselinePath = resolve(
  ROOT,
  ".asc/evidence/protected-locales-before.json",
);
const evidencePath = resolve(
  ROOT,
  `.asc/evidence/verify-${VERSION}-result.json`,
);
const errors = [];
const checks = [];

function check(name, valid, detail = null) {
  checks.push({ name, valid, detail });
  if (!valid) errors.push(detail ? `${name}: ${detail}` : name);
}

function rowByLocale(responseRows, locale) {
  return responseRows.find((row) => attributes(row).locale === locale) ?? null;
}

function compareFields(actual, expected, fields, prefix) {
  for (const [expectedField, actualField] of fields) {
    check(
      `${prefix}.${expectedField}`,
      actual?.[actualField] === expected?.[expectedField],
      actual?.[actualField] === expected?.[expectedField]
        ? null
        : "App Store value does not match the approved local source.",
    );
  }
}

function md5(path) {
  return createHash("md5").update(readFileSync(path)).digest("hex");
}

function screenshotChecksums(response) {
  return screenshotRows(response)
    .map((row) => {
      const value = attributes(row).sourceFileChecksum;
      return typeof value === "string" ? value.toLowerCase() : null;
    })
    .filter(Boolean)
    .sort();
}

function screenshotRows(response) {
  if (Array.isArray(response?.sets)) {
    return response.sets.flatMap((set) =>
      Array.isArray(set?.screenshots) ? set.screenshots : [],
    );
  }
  return rows(response);
}

assertLocalePolicy();
const configs = localeConfigs();
for (const config of configs) {
  assertMutableLocale(config.locale, "ASC verification");
}
const metadata = metadataValidation(configs);
check("local_metadata_validation", metadata.valid, metadata.errors.join("; "));

const versionsResponse = runAsc([
  "versions",
  "list",
  "--app",
  APP_ID,
  "--platform",
  APP_CONFIG.platform,
  "--paginate",
]);
const candidate = versionRow(versionsResponse);
check("candidate_exists", Boolean(candidate));
if (!candidate) {
  throw new Error(`ASC candidate ${VERSION} is absent.`);
}
const candidateAttributes = attributes(candidate);
check(
  "candidate_release_type_matches_plan",
  candidateAttributes.releaseType === APP_CONFIG.release.release_type,
  `actual=${candidateAttributes.releaseType ?? "missing"}`,
);
check(
  "candidate_not_released",
  !["READY_FOR_SALE", "READY_FOR_DISTRIBUTION"].includes(
    candidateAttributes.appStoreState,
  ),
  `actual=${candidateAttributes.appStoreState ?? "missing"}`,
);

const versionView = runAsc([
  "versions",
  "view",
  "--version-id",
  candidate.id,
  "--include-build",
  "--include-submission",
]);
const relationshipBuildID =
  versionView?.buildId ??
  versionView?.data?.relationships?.build?.data?.id ??
  null;
const includedBuild = (versionView?.included ?? []).find(
  (row) => row.type === "builds" && row.id === BUILD_ID,
);
check(
  `build_${APP_CONFIG.release.build_number}_attached`,
  relationshipBuildID === BUILD_ID || Boolean(includedBuild),
  `expected=${BUILD_ID}, actual=${relationshipBuildID ?? "missing"}`,
);
const submissionRelationship =
  versionView?.data?.relationships?.appStoreVersionSubmission?.data ?? null;
const reviewStatus = runAsc([
  "review",
  "status",
  "--app",
  APP_ID,
]);
const reviewSubmissionExpected =
  APP_CONFIG.production_policy.review_submission_performed_by_automation === true;
const submittedReviewStates = new Set([
  "WAITING_FOR_REVIEW",
  "IN_REVIEW",
  "PENDING_DEVELOPER_RELEASE",
  "PENDING_APPLE_RELEASE",
  "PROCESSING_FOR_DISTRIBUTION",
  "READY_FOR_SALE",
  "READY_FOR_DISTRIBUTION",
]);
check(
  "review_submission_matches_plan",
  reviewSubmissionExpected
    ? submittedReviewStates.has(reviewStatus.reviewState)
    : reviewStatus.reviewState === "NOT_SUBMITTED",
  `expected_submitted=${reviewSubmissionExpected}, actual=${reviewStatus.reviewState ?? "missing"}`,
);

const versionLocalizations = rows(
  runAsc([
    "localizations",
    "list",
    "--version",
    candidate.id,
    "--paginate",
  ]),
);
const appInfos = rows(
  runAsc([
    "apps",
    "info",
    "list",
    "--app",
    APP_ID,
  ]),
);
const candidateAppInfo = appInfos.find((row) => {
  const state = attributes(row).state ?? attributes(row).appStoreState;
  return state === candidateAttributes.appStoreState;
}) ?? appInfos[0] ?? null;
check("candidate_app_info_exists", Boolean(candidateAppInfo));
const appInfoLocalizationArgs = [
  "localizations",
  "list",
  "--app",
  APP_ID,
  "--type",
  "app-info",
];
if (candidateAppInfo?.id) {
  appInfoLocalizationArgs.push("--app-info", candidateAppInfo.id);
}
appInfoLocalizationArgs.push("--paginate");
const appInfoLocalizations = rows(
  runAsc([
    ...appInfoLocalizationArgs,
  ]),
);

const screenshotEvidence = [];
for (const config of configs) {
  const locale = config.locale;
  const versionLocalization = rowByLocale(versionLocalizations, locale);
  const appInfoLocalization = rowByLocale(appInfoLocalizations, locale);
  check(`${locale}.version_localization_exists`, Boolean(versionLocalization));
  check(`${locale}.app_info_localization_exists`, Boolean(appInfoLocalization));

  compareFields(
    attributes(versionLocalization) ?? {},
    config.version_info,
    [
      ["description", "description"],
      ["keywords", "keywords"],
      ["marketing_url", "marketingUrl"],
      ["promotional_text", "promotionalText"],
      ["support_url", "supportUrl"],
      ["whats_new", "whatsNew"],
    ],
    `${locale}.version`,
  );
  compareFields(
    attributes(appInfoLocalization) ?? {},
    config.app_info,
    [
      ["name", "name"],
      ["subtitle", "subtitle"],
      ["privacy_policy_url", "privacyPolicyUrl"],
    ],
    `${locale}.app_info`,
  );

  const screenshotFiles = ensureScreenshotFiles(locale);
  const expectedChecksums = screenshotFiles.files.map(md5).sort();
  const response = versionLocalization
    ? runAsc([
        "screenshots",
        "list",
        "--version-localization",
        versionLocalization.id,
      ])
    : { data: [] };
  const actualChecksums = screenshotChecksums(response);
  const count = screenshotRows(response).length;
  check(
    `${locale}.screenshot_count`,
    count === APP_CONFIG.screenshots.slides_per_locale,
    `expected=${APP_CONFIG.screenshots.slides_per_locale}, actual=${count}`,
  );
  const checksumsComparable =
    actualChecksums.length === expectedChecksums.length;
  const screenshotChecksumsMatch =
    checksumsComparable &&
    JSON.stringify(actualChecksums) === JSON.stringify(expectedChecksums);
  check(
    `${locale}.screenshot_checksums`,
    screenshotChecksumsMatch,
    screenshotChecksumsMatch
      ? null
      : checksumsComparable
        ? "Uploaded screenshot checksums do not match local approved files."
        : "ASC did not return one checksum per screenshot.",
  );
  screenshotEvidence.push({
    locale,
    localization_id: versionLocalization?.id ?? null,
    count,
    expected_md5: expectedChecksums,
    actual_md5: actualChecksums,
  });
}

const groupRows = rows(
  runAsc([
    "subscriptions",
    "groups",
    "localizations",
    "list",
    "--group-id",
    SUBSCRIPTION_MANIFEST.subscription_group_id,
    "--paginate",
  ]),
);
for (const localization of SUBSCRIPTION_SOURCE.subscription_group
  .localizations) {
  const actual = rowByLocale(groupRows, localization.locale);
  check(
    `${localization.locale}.subscription_group_localization`,
    (attributes(actual) ?? {}).name === localization.name,
  );
}

for (const product of SUBSCRIPTION_SOURCE.products) {
  const productRows = rows(
    runAsc([
      "subscriptions",
      "localizations",
      "list",
      "--subscription-id",
      product.subscription_id,
      "--paginate",
    ]),
  );
  for (const localization of product.localizations) {
    const actual =
      attributes(rowByLocale(productRows, localization.locale)) ?? {};
    check(
      `${product.product_id}.${localization.locale}.subscription_name`,
      actual.name === localization.name,
    );
    check(
      `${product.product_id}.${localization.locale}.subscription_description`,
      actual.description === localization.description,
    );
  }
}

const reviewRows = rows(
  runAsc([
    "review",
    "details-for-version",
    "--version-id",
    candidate.id,
  ]),
);
const review = attributes(reviewRows[0]) ?? {};
for (const field of [
  "contactFirstName",
  "contactLastName",
  "contactPhone",
  "contactEmail",
  "notes",
]) {
  check(
    `review_details.${field}`,
    typeof review[field] === "string" && review[field].trim().length > 0,
  );
}
if (review.demoAccountRequired === true) {
  check(
    "review_details.demoAccountName",
    typeof review.demoAccountName === "string" &&
      review.demoAccountName.length > 0,
  );
  check(
    "review_details.demoAccountPassword",
    typeof review.demoAccountPassword === "string" &&
      review.demoAccountPassword.length > 0,
  );
}

const protectedBaseline = readJSON(protectedBaselinePath);
const protectedAfter = captureProtectedState();
const protectedComparison = compareProtectedState(
  protectedBaseline,
  protectedAfter,
  { requireCandidate: true },
);
check(
  "protected_turkish_content_unchanged",
  protectedComparison.valid,
  protectedComparison.errors.join("; "),
);

writeJSON(evidencePath, {
  schema_version: 1,
  verified_at: new Date().toISOString(),
  mutation_performed: false,
  app_id: APP_ID,
  version: VERSION,
  version_id: candidate.id,
  app_store_state: candidateAttributes.appStoreState,
  release_type: candidateAttributes.releaseType,
  build_id: relationshipBuildID ?? includedBuild?.id ?? null,
  review_submission_present:
    Boolean(submissionRelationship) || reviewSubmissionExpected,
  review_state: reviewStatus.reviewState ?? null,
  protected_locales: APP_CONFIG.protected_locales,
  protected_locale_mutations_detected: !protectedComparison.valid,
  protected_content_sha256: protectedAfter.protected_content_sha256,
  mutable_locales: LOCALES,
  screenshots: screenshotEvidence,
  checks,
  valid: errors.length === 0,
  errors,
});

if (errors.length > 0) {
  console.error(`ASC verification failed:\n- ${errors.join("\n- ")}`);
  process.exitCode = 1;
} else {
  console.log(
    `ASC ${VERSION} verification passed; ${checks.length} checks are green; ` +
      `review_state=${reviewStatus.reviewState}; release is not live.`,
  );
}
