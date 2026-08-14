#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  existsSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { basename, join, relative, resolve } from "node:path";
import process from "node:process";

const ROOT = resolve(import.meta.dirname, "..");
const ACTIVE_DIR = join(ROOT, "supabase", "migrations");
const ARCHIVE_MANIFEST_PATH = join(
  ROOT,
  "supabase",
  "migrations_archive",
  "pre-localization-ledger-2026-07-28",
  "MANIFEST.json",
);
const BEFORE_LEDGER_PATH = join(
  ROOT,
  "docs",
  "localization",
  "baseline",
  "MIGRATION_LEDGER_BEFORE_RECONCILIATION_2026-07-28.json",
);
const COMPARISON_PATH = join(
  ROOT,
  "docs",
  "localization",
  "baseline",
  "MIGRATION_MATCHED_CONTENT_COMPARISON_2026-07-28.json",
);
const OUTPUT_PATH = join(
  ROOT,
  "docs",
  "localization",
  "baseline",
  "MIGRATION_LEDGER_AFTER_RECONCILIATION_2026-07-28.json",
);
const FORWARD_VERSIONS = new Set([
  "20260728201500",
  "20260728202000",
  "20260728203000",
  "20260730213000",
  "20260731103000",
  "20260731120000",
  "20260731121000",
  "20260801170000",
  "20260801170100",
  "20260801191332",
  "20260801213000",
  "20260801214500",
  "20260801220000",
  "20260802203947",
  "20260802205501",
  "20260802214159",
  "20260803113000",
]);

const loadJSON = (path) => JSON.parse(readFileSync(path, "utf8"));
const sha256 = (path) =>
  createHash("sha256").update(readFileSync(path)).digest("hex");
const fail = (message) => {
  console.error(message);
  process.exit(1);
};

if (!existsSync(ARCHIVE_MANIFEST_PATH)) {
  fail(`Missing ${relative(ROOT, ARCHIVE_MANIFEST_PATH)}`);
}

const before = loadJSON(BEFORE_LEDGER_PATH);
const comparison = loadJSON(COMPARISON_PATH);
const archiveManifest = loadJSON(ARCHIVE_MANIFEST_PATH);
const localBeforeByVersion = new Map(
  before.local_files.map((entry) => [entry.version, entry]),
);
const remoteByVersion = new Map(
  before.remote_files.map((entry) => [entry.version, entry]),
);
const remoteOnlyVersions = new Set(
  before.remote_only.map((entry) => entry.version),
);
const semanticVersions = new Set(
  comparison.semantic_divergences.map((entry) => entry.version),
);

const activeFiles = readdirSync(ACTIVE_DIR)
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
const activeEntries = activeFiles.map((name) => {
  const version = name.slice(0, 14);
  const path = join(ACTIVE_DIR, name);
  return {
    version,
    name: name.slice(15, -4),
    file: relative(ROOT, path),
    sha256: sha256(path),
    classification: FORWARD_VERSIONS.has(version)
      ? "forward_after_reconciliation"
      : "canonical_remote_history",
  };
});

const duplicateVersions = activeEntries
  .map((entry) => entry.version)
  .filter((version, index, values) => values.indexOf(version) !== index);
if (duplicateVersions.length > 0) {
  fail(`Duplicate active migration versions: ${duplicateVersions.join(",")}`);
}

for (const [version, remote] of remoteByVersion) {
  const active = activeEntries.find((entry) => entry.version === version);
  if (!active) fail(`Missing canonical remote version ${version}`);
  const expected = remoteOnlyVersions.has(version) ||
      semanticVersions.has(version)
    ? remote.sha256
    : localBeforeByVersion.get(version)?.sha256;
  if (!expected || active.sha256 !== expected) {
    fail(
      `Canonical migration hash mismatch ${version}: expected=${expected} actual=${active.sha256}`,
    );
  }
}

const unexpectedVersions = activeEntries
  .filter((entry) =>
    !remoteByVersion.has(entry.version) && !FORWARD_VERSIONS.has(entry.version)
  )
  .map((entry) => entry.version);
if (unexpectedVersions.length > 0) {
  fail(`Unexpected active versions: ${unexpectedVersions.join(",")}`);
}

for (const version of FORWARD_VERSIONS) {
  if (!activeEntries.some((entry) => entry.version === version)) {
    fail(`Missing forward migration ${version}`);
  }
}

for (const entry of archiveManifest.archived_local_only) {
  const path = resolve(ROOT, entry.archive_file);
  if (!existsSync(path) || sha256(path) !== entry.sha256) {
    fail(`Archived local-only checksum mismatch: ${entry.archive_file}`);
  }
}
for (const entry of archiveManifest.replaced_same_version) {
  const path = resolve(ROOT, entry.archive_file);
  if (!existsSync(path) || sha256(path) !== entry.archived_local_sha256) {
    fail(`Archived semantic-diff checksum mismatch: ${entry.archive_file}`);
  }
}

const output = {
  schema_version: 1,
  verified_at: "2026-07-28T21:00:00+03:00",
  production_mutation_performed: false,
  canonical_remote_history_count: remoteByVersion.size,
  forward_after_reconciliation_count: FORWARD_VERSIONS.size,
  active_migration_count: activeEntries.length,
  archived_local_only_count: archiveManifest.archived_local_only.length,
  archived_semantic_divergence_count:
    archiveManifest.replaced_same_version.length,
  duplicate_versions: duplicateVersions,
  unexpected_versions: unexpectedVersions,
  source_before_ledger: relative(ROOT, BEFORE_LEDGER_PATH),
  source_content_comparison: relative(ROOT, COMPARISON_PATH),
  source_archive_manifest: relative(ROOT, ARCHIVE_MANIFEST_PATH),
  active_files: activeEntries,
  forward_versions: [...FORWARD_VERSIONS].sort(),
};
const serialized = `${JSON.stringify(output, null, 2)}\n`;

if (process.argv.includes("--check")) {
  if (!existsSync(OUTPUT_PATH)) {
    fail(`${relative(ROOT, OUTPUT_PATH)} is missing`);
  }
  if (readFileSync(OUTPUT_PATH, "utf8") !== serialized) {
    fail(`${relative(ROOT, OUTPUT_PATH)} is stale`);
  }
  console.log(
    `Verified ${activeEntries.length} active migrations: ` +
      `${remoteByVersion.size} canonical remote + ${FORWARD_VERSIONS.size} forward.`,
  );
} else {
  writeFileSync(OUTPUT_PATH, serialized);
  console.log(
    `Wrote ${basename(OUTPUT_PATH)} with ${activeEntries.length} verified active migrations.`,
  );
}
