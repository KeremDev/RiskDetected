#!/usr/bin/env node

import {
  APP_ID,
  ROOT,
  VERSION,
  attributes,
  rows,
  runAsc,
  versionRow,
  writeJSON,
} from "./_shared.mjs";
import { relative, resolve } from "node:path";

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
const live = versionRow(versionsResponse, "1.2.4");
const appResponse = runAsc(["apps", "view", "--id", APP_ID]);
const appInfoResponse = runAsc([
  "localizations",
  "list",
  "--app",
  APP_ID,
  "--type",
  "app-info",
  "--paginate",
]);
const groupsResponse = runAsc([
  "subscriptions",
  "groups",
  "list",
  "--app",
  APP_ID,
  "--paginate",
]);

const snapshot = {
  schema_version: 1,
  captured_at: new Date().toISOString(),
  mutation_performed: false,
  app: {
    id: rows(appResponse)[0]?.id ?? null,
    attributes: attributes(rows(appResponse)[0]),
  },
  candidate_version: candidate
    ? { id: candidate.id, attributes: attributes(candidate) }
    : null,
  live_version: live
    ? { id: live.id, attributes: attributes(live) }
    : null,
  app_info_localizations: rows(appInfoResponse).map((row) => ({
    id: row.id,
    attributes: attributes(row),
  })),
  subscription_groups: rows(groupsResponse).map((row) => ({
    id: row.id,
    attributes: attributes(row),
  })),
  expected_version: VERSION,
};

const outputIndex = process.argv.indexOf("--output");
if (outputIndex >= 0) {
  const outputPath = resolve(process.argv[outputIndex + 1]);
  writeJSON(outputPath, snapshot);
  console.log(`Wrote ${relative(ROOT, outputPath)}.`);
} else {
  console.log(JSON.stringify(snapshot, null, 2));
}
