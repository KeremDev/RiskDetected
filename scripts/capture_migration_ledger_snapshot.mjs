#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import process from "node:process";

const ROOT = resolve(import.meta.dirname, "..");

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

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function migrationFiles(directory, logicalPrefix = null) {
  return readdirSync(directory)
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))
    .sort()
    .map((name) => {
      const match = name.match(/^(\d{14})_(.+)\.sql$/);
      const path = join(directory, name);
      return {
        version: match[1],
        name: match[2],
        file: logicalPrefix
          ? `${logicalPrefix}/${name}`
          : relative(ROOT, path),
        sha256: sha256(path),
      };
    });
}

function parseLinkedLedger(output) {
  const rows = [];
  for (const line of output.split(/\r?\n/)) {
    const match = line.match(
      /^\s*(\d{14})?\s*\|\s*(\d{14})?\s*\|\s*([0-9-]{10} [0-9:]{8})?\s*$/,
    );
    if (!match) continue;
    rows.push({
      local_version: match[1] ?? null,
      remote_version: match[2] ?? null,
      time_utc: match[3] ?? null,
    });
  }
  return rows;
}

const remoteDirectory = resolve(argument("--remote-dir"));
const outputPath = resolve(argument("--output"));
const capturedAt = argument("--captured-at");
const localDirectory = join(ROOT, "supabase", "migrations");

const linked = spawnSync(
  "supabase",
  ["migration", "list", "--linked"],
  {
    cwd: ROOT,
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
  },
);
if (linked.status !== 0) {
  fail(`supabase migration list failed: ${linked.stderr.trim()}`);
}

const localFiles = migrationFiles(localDirectory);
const remoteFiles = migrationFiles(remoteDirectory, "remote-fetch");
const localByVersion = new Map(localFiles.map((row) => [row.version, row]));
const remoteByVersion = new Map(remoteFiles.map((row) => [row.version, row]));
const linkedRows = parseLinkedLedger(linked.stdout);

const matched = linkedRows.filter(
  (row) => row.local_version && row.remote_version,
);
const localOnly = linkedRows
  .filter((row) => row.local_version && !row.remote_version)
  .map((row) => localByVersion.get(row.local_version))
  .filter(Boolean);
const remoteOnly = linkedRows
  .filter((row) => !row.local_version && row.remote_version)
  .map((row) => remoteByVersion.get(row.remote_version))
  .filter(Boolean);
const sameVersionHashMismatches = matched
  .map((row) => {
    const local = localByVersion.get(row.local_version);
    const remote = remoteByVersion.get(row.remote_version);
    if (!local || !remote || local.sha256 === remote.sha256) return null;
    return {
      version: row.local_version,
      local_name: local.name,
      remote_name: remote.name,
      local_sha256: local.sha256,
      remote_sha256: remote.sha256,
    };
  })
  .filter(Boolean);

const snapshot = {
  schema_version: 1,
  captured_at: capturedAt,
  project_ref: "ppcrzemgiztzcgddbins",
  command: "supabase migration list --linked",
  remote_file_reference:
    "remote-fetch/<filename> is a logical label for a read-only temporary Supabase migration fetch; retained exact files are listed in REMOTE_MIGRATION_EVIDENCE_MANIFEST_2026-07-28.json",
  counts: {
    matched: matched.length,
    local_only: localOnly.length,
    remote_only: remoteOnly.length,
    local_files: localFiles.length,
    remote_files: remoteFiles.length,
    same_version_hash_mismatches: sameVersionHashMismatches.length,
  },
  local_only: localOnly,
  remote_only: remoteOnly,
  same_version_hash_mismatches: sameVersionHashMismatches,
  local_files: localFiles,
  remote_files: remoteFiles,
};

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(snapshot, null, 2)}\n`);

console.log(
  [
    `Captured migration ledger to ${relative(ROOT, outputPath)}`,
    `matched=${snapshot.counts.matched}`,
    `local_only=${snapshot.counts.local_only}`,
    `remote_only=${snapshot.counts.remote_only}`,
    `hash_mismatches=${snapshot.counts.same_version_hash_mismatches}`,
  ].join(" "),
);
