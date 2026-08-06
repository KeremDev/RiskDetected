#!/usr/bin/env node

import {
  APP_CONFIG,
  APP_ID,
  LOCALES,
  PROTECTED_LOCALES,
  ROOT,
  VERSION,
  assertLocalePolicy,
  assertMutableLocale,
  attributes,
  ensureScreenshotFiles,
  localeConfigs,
  metadataValidation,
  rows,
  runAsc,
  versionRow,
  writeJSON,
} from "./_shared.mjs";
import { relative, resolve } from "node:path";

assertLocalePolicy();
const configs = localeConfigs();
for (const config of configs) {
  assertMutableLocale(config.locale, "ASC plan");
}
const metadata = metadataValidation(configs);
const versionsResponse = runAsc([
  "versions",
  "list",
  "--app",
  APP_ID,
  "--platform",
  "IOS",
  "--paginate",
]);
const candidate = versionRow(versionsResponse);
const live = versionRow(
  versionsResponse,
  APP_CONFIG.production_policy.current_live_version,
);
const currentCandidateLocalizations = candidate
  ? rows(
      runAsc([
        "localizations",
        "list",
        "--version",
        candidate.id,
        "--paginate",
      ]),
    )
  : [];
const currentAppInfoLocalizations = rows(
  runAsc([
    "localizations",
    "list",
    "--app",
    APP_ID,
    "--type",
    "app-info",
    "--paginate",
  ]),
);

const currentCandidateByLocale = new Map(
  currentCandidateLocalizations.map((row) => [attributes(row).locale, row]),
);
const currentAppInfoByLocale = new Map(
  currentAppInfoLocalizations.map((row) => [attributes(row).locale, row]),
);
const screenshotFiles = LOCALES.map(ensureScreenshotFiles);
const operations = [];

if (!candidate) {
  operations.push({
    kind: "create_version",
    version: VERSION,
    release_type: APP_CONFIG.release.release_type,
  });
}

for (const config of configs) {
  const versionLocalization = currentCandidateByLocale.get(config.locale);
  const appInfoLocalization = currentAppInfoByLocale.get(config.locale);
  operations.push({
    kind: versionLocalization
      ? "upsert_version_localization"
      : "create_version_localization",
    locale: config.locale,
    current_id: versionLocalization?.id ?? null,
  });
  operations.push({
    kind: appInfoLocalization
      ? "update_app_info_localization"
      : "create_app_info_localization_after_version_locale",
    locale: config.locale,
    current_id: appInfoLocalization?.id ?? null,
  });
}

operations.push({
  kind: "upsert_subscription_localizations",
  locale_count: LOCALES.length,
});
operations.push({
  kind: "attach_existing_build",
  build_id: APP_CONFIG.release.build_id,
});
operations.push({
  kind: "upsert_review_details_without_submission",
});
operations.push({
  kind: "upload_screenshots_when_complete",
  complete_locale_count: screenshotFiles.filter((item) => item.complete).length,
  expected_locale_count: LOCALES.length,
  device_type: "IPHONE_69",
});

const plan = {
  schema_version: 1,
  generated_at: new Date().toISOString(),
  mutation_performed: false,
  app_id: APP_ID,
  target_version: VERSION,
  live_version: live
    ? {
        id: live.id,
        version: attributes(live).versionString,
        state: attributes(live).appStoreState,
      }
    : null,
  candidate_version: candidate
    ? {
        id: candidate.id,
        state: attributes(candidate).appStoreState,
        release_type: attributes(candidate).releaseType,
      }
    : null,
  metadata_validation: metadata,
  screenshot_files: screenshotFiles,
  operations,
  safety: {
    release_type: "MANUAL",
    review_submission_planned: false,
    final_release_implemented: false,
    production_rollout_change_planned: false,
    protected_locales: PROTECTED_LOCALES,
    protected_locale_mutations_planned: false,
  },
};

const outputIndex = process.argv.indexOf("--output");
if (outputIndex >= 0) {
  const outputPath = resolve(process.argv[outputIndex + 1]);
  writeJSON(outputPath, plan);
  console.log(`Wrote ${relative(ROOT, outputPath)}.`);
} else {
  console.log(JSON.stringify(plan, null, 2));
}

if (!metadata.valid) process.exitCode = 1;
