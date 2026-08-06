#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import process from "node:process";

const ROOT = resolve(import.meta.dirname, "..");
const APP_ID = "6769498181";

function fail(message) {
  console.error(message);
  process.exit(1);
}

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) {
    fail(`Missing required argument: ${name}`);
  }
  return process.argv[index + 1];
}

function runAsc(args) {
  const result = spawnSync("asc", [...args, "--output", "json"], {
    cwd: ROOT,
    encoding: "utf8",
    maxBuffer: 30 * 1024 * 1024,
  });
  if (result.status !== 0) {
    fail(`asc ${args.join(" ")} failed: ${result.stderr.trim()}`);
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`asc ${args.join(" ")} returned invalid JSON: ${error.message}`);
  }
}

function rows(response) {
  if (Array.isArray(response?.data)) return response.data;
  if (response?.data) return [response.data];
  return [];
}

function attributes(row) {
  return row?.attributes ?? {};
}

function screenshotSets(response) {
  if (!Array.isArray(response?.sets)) return [];
  return response.sets.map((entry) => ({
    id: entry?.set?.id ?? null,
    attributes: attributes(entry?.set),
    screenshots: Array.isArray(entry?.screenshots)
      ? entry.screenshots.map((screenshot) => ({
          id: screenshot.id,
          attributes: attributes(screenshot),
        }))
      : [],
  }));
}

const outputPath = resolve(argument("--output"));
const capturedAt = argument("--captured-at");

const appRow = rows(runAsc(["apps", "view", "--id", APP_ID]))[0];
const versionRows = rows(
  runAsc([
    "versions",
    "list",
    "--app",
    APP_ID,
    "--platform",
    "IOS",
    "--paginate",
  ]),
);
const liveVersion =
  versionRows.find((row) => attributes(row).versionString === "1.2.4") ??
  versionRows[0];
if (!liveVersion) fail("No iOS App Store version found.");

const versionLocalizations = rows(
  runAsc([
    "localizations",
    "list",
    "--version",
    liveVersion.id,
    "--paginate",
  ]),
);
const localizationSnapshots = versionLocalizations.map((row) => {
  const sets = screenshotSets(
    runAsc([
      "screenshots",
      "list",
      "--version-localization",
      row.id,
    ]),
  );
  return {
    id: row.id,
    locale: attributes(row).locale,
    attributes: attributes(row),
    screenshot_sets: sets,
    screenshot_count: sets.reduce(
      (count, set) => count + set.screenshots.length,
      0,
    ),
  };
});

const groupRows = rows(
  runAsc([
    "subscriptions",
    "groups",
    "list",
    "--app",
    APP_ID,
    "--paginate",
  ]),
);
const groups = groupRows.map((group) => {
  const groupLocalizations = rows(
    runAsc([
      "subscriptions",
      "groups",
      "localizations",
      "list",
      "--group-id",
      group.id,
      "--paginate",
    ]),
  );
  const subscriptions = rows(
    runAsc([
      "subscriptions",
      "list",
      "--group-id",
      group.id,
      "--paginate",
    ]),
  ).map((subscription) => {
    const localizations = rows(
      runAsc([
        "subscriptions",
        "localizations",
        "list",
        "--subscription-id",
        subscription.id,
        "--paginate",
      ]),
    );
    return {
      id: subscription.id,
      attributes: attributes(subscription),
      localizations: localizations.map((localization) => ({
        id: localization.id,
        attributes: attributes(localization),
      })),
    };
  });

  return {
    id: group.id,
    attributes: attributes(group),
    localizations: groupLocalizations.map((localization) => ({
      id: localization.id,
      attributes: attributes(localization),
    })),
    subscriptions,
  };
});

const snapshot = {
  schema_version: 1,
  captured_at: capturedAt,
  mutation_performed: false,
  app: {
    id: appRow.id,
    attributes: attributes(appRow),
  },
  versions: versionRows.map((row) => ({
    id: row.id,
    attributes: attributes(row),
  })),
  inspected_version: {
    id: liveVersion.id,
    attributes: attributes(liveVersion),
    localizations: localizationSnapshots,
  },
  subscription_groups: groups,
};

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(snapshot, null, 2)}\n`);

console.log(
  `Captured ASC discovery to ${relative(ROOT, outputPath)}: ` +
    `${snapshot.inspected_version.localizations.length} version locale(s), ` +
    `${groups.length} subscription group(s).`,
);
