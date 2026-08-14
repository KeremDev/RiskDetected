import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import {
  APP_CONFIG,
  APP_ID,
  PROTECTED_LOCALES,
  ROOT,
  SUBSCRIPTION_MANIFEST,
  SUBSCRIPTION_SOURCE,
  VERSION,
  assertLocalePolicy,
  attributes,
  localePath,
  rows,
  runAsc,
  versionRow,
} from "./_shared.mjs";

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonical(value[key])]),
    );
  }
  return value;
}

export function digest(value) {
  return createHash("sha256")
    .update(JSON.stringify(canonical(value)))
    .digest("hex");
}

function semanticRows(value) {
  const contentRows = value.map((row) => {
    const content = { ...row.attributes };
    // ASC creates a draft copy of an approved subscription localization when
    // another locale is added. The workflow state and the duplicate resource
    // are server-managed; protected user-authored content must still match.
    delete content.state;
    return canonical(content);
  });
  return Array.from(
    new Map(
      contentRows.map((row) => [JSON.stringify(row), row]),
    ).values(),
  ).sort((left, right) =>
    JSON.stringify(left).localeCompare(JSON.stringify(right)),
  );
}

function semanticVersion(value) {
  return {
    version: value.version,
    localizations: semanticRows(value.localizations),
    screenshots: value.screenshots
      .map((set) => ({
        locale: set.locale,
        screenshots: semanticRows(set.screenshots),
      }))
      .sort((left, right) => left.locale.localeCompare(right.locale)),
  };
}

function semanticState(value) {
  return {
    protected_locales: value.protected_locales,
    app_info_localizations: semanticRows(value.app_info_localizations),
    versions: value.versions
      .map(semanticVersion)
      .sort((left, right) => left.version.localeCompare(right.version)),
    subscription_group_localizations: semanticRows(
      value.subscription_group_localizations,
    ),
    subscription_localizations: value.subscription_localizations
      .map((product) => ({
        product_id: product.product_id,
        localizations: semanticRows(product.localizations),
      }))
      .sort((left, right) => left.product_id.localeCompare(right.product_id)),
    local_drafts: value.local_drafts,
  };
}

function projectedRows(response) {
  return rows(response).map((row) => ({
    id: row.id,
    type: row.type,
    attributes: attributes(row),
    relationships: row.relationships ?? null,
  }));
}

function protectedRows(response) {
  return projectedRows(response).filter((row) =>
    PROTECTED_LOCALES.includes(row.attributes.locale)
  );
}

function screenshotsFor(localizations) {
  return localizations.map((localization) => ({
    locale: localization.attributes.locale,
    localization_id: localization.id,
    screenshots: projectedRows(
      runAsc([
        "screenshots",
        "list",
        "--version-localization",
        localization.id,
      ]),
    ),
  }));
}

export function captureProtectedState() {
  assertLocalePolicy();

  const versionsResponse = runAsc([
    "versions",
    "list",
    "--app",
    APP_ID,
    "--platform",
    APP_CONFIG.platform,
    "--paginate",
  ]);
  const live = versionRow(
    versionsResponse,
    APP_CONFIG.production_policy.current_live_version,
  );
  const candidate = versionRow(versionsResponse, VERSION);
  const appInfo = protectedRows(
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

  const versionState = [];
  for (const row of [live, candidate].filter(Boolean)) {
    const localizations = protectedRows(
      runAsc([
        "localizations",
        "list",
        "--version",
        row.id,
        "--paginate",
      ]),
    );
    versionState.push({
      version_id: row.id,
      version: attributes(row).versionString,
      state: attributes(row).appStoreState,
      localizations,
      screenshots: screenshotsFor(localizations),
    });
  }

  const subscriptionGroupLocalizations = protectedRows(
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
  const subscriptionLocalizations = SUBSCRIPTION_SOURCE.products.map(
    (product) => ({
      subscription_id: product.subscription_id,
      product_id: product.product_id,
      localizations: protectedRows(
        runAsc([
          "subscriptions",
          "localizations",
          "list",
          "--subscription-id",
          product.subscription_id,
          "--paginate",
        ]),
      ),
    }),
  );

  const localDrafts = PROTECTED_LOCALES.map((locale) => {
    const path = localePath(locale);
    return {
      locale,
      path: path.slice(ROOT.length + 1),
      sha256: createHash("sha256").update(readFileSync(path)).digest("hex"),
    };
  });

  const state = {
    schema_version: 1,
    app_id: APP_ID,
    protected_locales: PROTECTED_LOCALES,
    app_info_localizations: appInfo,
    versions: versionState,
    subscription_group_localizations: subscriptionGroupLocalizations,
    subscription_localizations: subscriptionLocalizations,
    local_drafts: localDrafts,
  };
  return {
    ...state,
    protected_state_sha256: digest(state),
    protected_content_sha256: digest(semanticState(state)),
  };
}

export function compareProtectedState(before, after, options = {}) {
  const beforeVersions = new Map(
    before.versions.map((row) => [row.version, row]),
  );
  const afterVersions = new Map(
    after.versions.map((row) => [row.version, row]),
  );
  const errors = [];

  for (const [version, value] of beforeVersions) {
    const next = afterVersions.get(version);
    if (!next) {
      errors.push(`Protected version ${version} disappeared.`);
      continue;
    }
    if (digest(semanticVersion(value)) !== digest(semanticVersion(next))) {
      errors.push(`Protected version ${version} changed.`);
    }
  }
  if (
    digest(semanticRows(before.app_info_localizations)) !==
      digest(semanticRows(after.app_info_localizations))
  ) {
    errors.push("Protected app-info localization changed.");
  }
  if (
    digest(semanticRows(before.subscription_group_localizations)) !==
      digest(semanticRows(after.subscription_group_localizations))
  ) {
    errors.push("Protected subscription-group localization changed.");
  }
  if (
    digest(
      semanticState({
        protected_locales: [],
        app_info_localizations: [],
        versions: [],
        subscription_group_localizations: [],
        subscription_localizations: before.subscription_localizations,
        local_drafts: [],
      }).subscription_localizations,
    ) !==
      digest(
        semanticState({
          protected_locales: [],
          app_info_localizations: [],
          versions: [],
          subscription_group_localizations: [],
          subscription_localizations: after.subscription_localizations,
          local_drafts: [],
        }).subscription_localizations,
      )
  ) {
    errors.push("Protected subscription localization changed.");
  }
  if (digest(before.local_drafts) !== digest(after.local_drafts)) {
    errors.push("Protected local metadata draft changed.");
  }
  if (options.requireCandidate === true && !afterVersions.has(VERSION)) {
    errors.push(`Protected candidate snapshot for ${VERSION} is absent.`);
  }
  return { valid: errors.length === 0, errors };
}
