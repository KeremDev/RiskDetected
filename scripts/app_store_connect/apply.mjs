#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  APP_CONFIG,
  APP_ID,
  BUILD_ID,
  LOCALES,
  REVIEW_NOTES_PATH,
  ROOT,
  SUBSCRIPTION_MANIFEST,
  SUBSCRIPTION_SOURCE,
  VERSION,
  assertLocalePolicy,
  assertMutableLocale,
  assertReleaseCannotRun,
  attributes,
  ensureScreenshotFiles,
  localeConfigs,
  metadataValidation,
  readJSON,
  requireFlag,
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
  ".asc/evidence/apply-1.3.0-result.json",
);

function localeRows(versionID) {
  return rows(
    runAsc([
      "localizations",
      "list",
      "--version",
      versionID,
      "--paginate",
    ]),
  );
}

function rowByLocale(responseRows, locale) {
  return responseRows.find((row) => attributes(row).locale === locale) ?? null;
}

function requireProtectedComparison(label, comparison) {
  if (!comparison.valid) {
    throw new Error(
      `${label} failed:\n- ${comparison.errors.join("\n- ")}`,
    );
  }
}

function append(args, flag, value) {
  if (value !== null && value !== undefined && String(value).length > 0) {
    args.push(flag, String(value));
  }
}

function upsertVersionLocalization(versionID, config, operations) {
  assertMutableLocale(config.locale, "version localization mutation");
  const current = rowByLocale(localeRows(versionID), config.locale);
  const command = current ? "update" : "create";
  const args = [
    "localizations",
    command,
    "--version",
    versionID,
    "--locale",
    config.locale,
    "--description",
    config.version_info.description,
    "--keywords",
    config.version_info.keywords,
    "--marketing-url",
    config.version_info.marketing_url,
    "--promotional-text",
    config.version_info.promotional_text,
    "--support-url",
    config.version_info.support_url,
    "--whats-new",
    config.version_info.whats_new,
  ];
  runAsc(args);
  operations.push({
    operation: `${command}_version_localization`,
    locale: config.locale,
  });
}

function upsertAppInfoLocalization(config, operations) {
  assertMutableLocale(config.locale, "app-info localization mutation");
  runAsc([
    "app-setup",
    "info",
    "set",
    "--app",
    APP_ID,
    "--locale",
    config.locale,
    "--name",
    config.app_info.name,
    "--subtitle",
    config.app_info.subtitle,
    "--privacy-policy-url",
    config.app_info.privacy_policy_url,
  ]);
  operations.push({
    operation: "upsert_app_info_localization",
    locale: config.locale,
  });
}

function upsertSubscriptionLocalizations(operations) {
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
    assertMutableLocale(
      localization.locale,
      "subscription-group localization mutation",
    );
    const current = rowByLocale(groupRows, localization.locale);
    if (current) {
      runAsc([
        "subscriptions",
        "groups",
        "localizations",
        "update",
        "--id",
        current.id,
        "--name",
        localization.name,
      ]);
    } else {
      runAsc([
        "subscriptions",
        "groups",
        "localizations",
        "create",
        "--group-id",
        SUBSCRIPTION_MANIFEST.subscription_group_id,
        "--locale",
        localization.locale,
        "--name",
        localization.name,
      ]);
    }
    operations.push({
      operation: "upsert_subscription_group_localization",
      locale: localization.locale,
    });
  }

  for (const product of SUBSCRIPTION_SOURCE.products) {
    const currentRows = rows(
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
      assertMutableLocale(
        localization.locale,
        "subscription localization mutation",
      );
      const current = rowByLocale(currentRows, localization.locale);
      if (current) {
        runAsc([
          "subscriptions",
          "localizations",
          "update",
          "--id",
          current.id,
          "--name",
          localization.name,
          "--description",
          localization.description,
        ]);
      } else {
        runAsc([
          "subscriptions",
          "localizations",
          "create",
          "--subscription-id",
          product.subscription_id,
          "--locale",
          localization.locale,
          "--name",
          localization.name,
          "--description",
          localization.description,
        ]);
      }
      operations.push({
        operation: "upsert_subscription_localization",
        locale: localization.locale,
        product_id: product.product_id,
      });
    }
  }
}

function copyReviewDetails(candidateID, liveID, operations) {
  const sourceRows = rows(
    runAsc([
      "review",
      "details-for-version",
      "--version-id",
      liveID,
      "--include-sensitive",
    ]),
  );
  const source = sourceRows[0];
  if (!source) {
    throw new Error("Live App Review details are unavailable for secure copy.");
  }
  const sourceAttributes = attributes(source);
  const candidateRows = rows(
    runAsc(["review", "details-for-version", "--version-id", candidateID]),
  );
  const candidate = candidateRows[0] ?? null;
  const args = candidate
    ? ["review", "details-update", "--id", candidate.id]
    : ["review", "details-create", "--version-id", candidateID];

  append(args, "--contact-first-name", sourceAttributes.contactFirstName);
  append(args, "--contact-last-name", sourceAttributes.contactLastName);
  append(args, "--contact-email", sourceAttributes.contactEmail);
  append(args, "--contact-phone", sourceAttributes.contactPhone);
  args.push(
    "--demo-account-required",
    sourceAttributes.demoAccountRequired === true ? "true" : "false",
  );
  if (sourceAttributes.demoAccountRequired === true) {
    append(args, "--demo-account-name", sourceAttributes.demoAccountName);
    if (
      typeof sourceAttributes.demoAccountPassword !== "string" ||
      sourceAttributes.demoAccountPassword.length === 0 ||
      /redacted/i.test(sourceAttributes.demoAccountPassword) ||
      /^[*•]+$/.test(sourceAttributes.demoAccountPassword)
    ) {
      throw new Error(
        "App Review demo password could not be retrieved securely from the live version.",
      );
    }
    append(
      args,
      "--demo-account-password",
      sourceAttributes.demoAccountPassword,
    );
  }
  append(args, "--notes", readFileSync(REVIEW_NOTES_PATH, "utf8").trim());
  runAsc(args);
  operations.push({
    operation: candidate
      ? "update_review_details"
      : "create_review_details",
    credentials_copied_in_memory: sourceAttributes.demoAccountRequired === true,
    credentials_logged_or_persisted: false,
  });
}

function uploadScreenshots(versionID, operations) {
  requireFlag("ASC_ALLOW_SCREENSHOT_UPLOAD");
  const localizations = localeRows(versionID);
  for (const locale of LOCALES) {
    assertMutableLocale(locale, "screenshot upload");
    const files = ensureScreenshotFiles(locale);
    if (!files.complete) {
      throw new Error(`Screenshot set is incomplete for ${locale}.`);
    }
    const localization = rowByLocale(localizations, locale);
    if (!localization) {
      throw new Error(`Version localization is missing for ${locale}.`);
    }
    runAsc([
      "screenshots",
      "upload",
      "--version-localization",
      localization.id,
      "--path",
      files.directory,
      "--device-type",
      "IPHONE_69",
      "--max-screenshots",
      String(APP_CONFIG.screenshots.slides_per_locale),
      "--replace",
    ]);
    operations.push({
      operation: "replace_english_screenshot_set",
      locale,
      count: APP_CONFIG.screenshots.slides_per_locale,
      device_type: "IPHONE_69",
    });
  }
}

assertReleaseCannotRun();
requireFlag("ASC_ALLOW_MUTATIONS");
assertLocalePolicy();
if (process.env.ASC_ALLOW_BUILD_UPLOAD === "1") {
  throw new Error("Build upload is unnecessary: build 78 already exists.");
}

const configs = localeConfigs();
for (const config of configs) {
  assertMutableLocale(config.locale, "metadata mutation");
}
const metadata = metadataValidation(configs);
if (!metadata.valid) {
  throw new Error(`Metadata validation failed:\n- ${metadata.errors.join("\n- ")}`);
}
if (!existsSync(protectedBaselinePath)) {
  throw new Error(
    "Protected-locale baseline is missing; run capture-protected-baseline.mjs.",
  );
}

const operations = [];
const baseline = readJSON(protectedBaselinePath);
const protectedBefore = captureProtectedState();
requireProtectedComparison(
  "Protected-locale preflight",
  compareProtectedState(baseline, protectedBefore),
);

let versionsResponse = runAsc([
  "versions",
  "list",
  "--app",
  APP_ID,
  "--platform",
  APP_CONFIG.platform,
  "--paginate",
]);
let candidate = versionRow(versionsResponse);
if (!candidate) {
  runAsc([
    "versions",
    "create",
    "--app",
    APP_ID,
    "--version",
    VERSION,
    "--platform",
    APP_CONFIG.platform,
    "--copyright",
    APP_CONFIG.release.copyright,
    "--release-type",
    APP_CONFIG.release.release_type,
  ]);
  operations.push({
    operation: "create_version",
    version: VERSION,
    release_type: APP_CONFIG.release.release_type,
  });
  versionsResponse = runAsc([
    "versions",
    "list",
    "--app",
    APP_ID,
    "--platform",
    APP_CONFIG.platform,
    "--paginate",
  ]);
  candidate = versionRow(versionsResponse);
}
if (!candidate) {
  throw new Error(`App Store version ${VERSION} could not be resolved.`);
}

runAsc([
  "versions",
  "update",
  "--version-id",
  candidate.id,
  "--copyright",
  APP_CONFIG.release.copyright,
  "--release-type",
  APP_CONFIG.release.release_type,
]);
operations.push({
  operation: "enforce_release_type",
  version_id: candidate.id,
  release_type: APP_CONFIG.release.release_type,
});

const protectedAfterVersionCreate = captureProtectedState();
requireProtectedComparison(
  "Protected-locale version-create check",
  compareProtectedState(protectedBefore, protectedAfterVersionCreate, {
    requireCandidate: true,
  }),
);

for (const config of configs) {
  upsertVersionLocalization(candidate.id, config, operations);
  upsertAppInfoLocalization(config, operations);
}
upsertSubscriptionLocalizations(operations);

runAsc([
  "versions",
  "attach-build",
  "--version-id",
  candidate.id,
  "--build",
  BUILD_ID,
]);
operations.push({
  operation: "attach_existing_build",
  build_id: BUILD_ID,
});

const live = versionRow(
  versionsResponse,
  APP_CONFIG.production_policy.current_live_version,
);
if (!live) {
  throw new Error("Current live App Store version could not be resolved.");
}
copyReviewDetails(candidate.id, live.id, operations);
uploadScreenshots(candidate.id, operations);

const protectedAfter = captureProtectedState();
requireProtectedComparison(
  "Protected-locale final check",
  compareProtectedState(protectedAfterVersionCreate, protectedAfter, {
    requireCandidate: true,
  }),
);
requireProtectedComparison(
  "Original protected-locale final check",
  compareProtectedState(protectedBefore, protectedAfter, {
    requireCandidate: true,
  }),
);

writeJSON(evidencePath, {
  schema_version: 1,
  applied_at: new Date().toISOString(),
  mutation_performed: true,
  app_id: APP_ID,
  version: VERSION,
  version_id: candidate.id,
  build_id: BUILD_ID,
  release_type: APP_CONFIG.release.release_type,
  review_submission_performed: false,
  release_performed: false,
  protected_locales: APP_CONFIG.protected_locales,
  protected_locale_mutations_performed: false,
  protected_state_before_sha256: protectedBefore.protected_state_sha256,
  protected_state_after_version_create_sha256:
    protectedAfterVersionCreate.protected_state_sha256,
  protected_state_after_sha256: protectedAfter.protected_state_sha256,
  mutable_locales: LOCALES,
  operations,
});

console.log(
  `Prepared App Store version ${VERSION} (${candidate.id}); ` +
    `${operations.length} guarded operations completed; ` +
    `review submission and release were not performed.`,
);
