#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  copyFileSync,
  mkdirSync,
  readFileSync,
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

const ledgerPath = resolve(argument("--ledger"));
const outputDirectory = resolve(argument("--output-dir"));
const manifestPath = resolve(argument("--manifest"));
const capturedAt = argument("--captured-at");
const remoteDirectory = resolve(argument("--remote-dir"));
const ledger = JSON.parse(readFileSync(ledgerPath, "utf8"));
const extraVersions = process.argv.flatMap((value, index) =>
  value === "--include-version" && process.argv[index + 1]
    ? [process.argv[index + 1]]
    : [],
);

if (!Array.isArray(ledger.remote_only)) {
  fail("Ledger does not contain a remote_only array.");
}

mkdirSync(outputDirectory, { recursive: true });

const remoteByVersion = new Map(
  (ledger.remote_files ?? []).map((entry) => [entry.version, entry]),
);
const extraFiles = extraVersions.map((version) => {
  const entry = remoteByVersion.get(version);
  if (!entry) fail(`Remote migration version not found: ${version}`);
  return entry;
});
const selectedFiles = [
  ...ledger.remote_only,
  ...extraFiles.filter(
    (candidate) =>
      !ledger.remote_only.some((entry) => entry.version === candidate.version),
  ),
];

const files = selectedFiles.map((entry) => {
  const sourcePath = resolve(remoteDirectory, basename(entry.file));
  const sourceHash = sha256(sourcePath);
  if (sourceHash !== entry.sha256) {
    fail(`Checksum mismatch before export: ${entry.file}`);
  }

  const targetPath = join(outputDirectory, basename(sourcePath));
  copyFileSync(sourcePath, targetPath);
  const targetHash = sha256(targetPath);
  if (targetHash !== entry.sha256) {
    fail(`Checksum mismatch after export: ${targetPath}`);
  }

  return {
    version: entry.version,
    name: entry.name,
    file: relative(ROOT, targetPath),
    sha256: targetHash,
  };
});

const manifest = {
  schema_version: 1,
  captured_at: capturedAt,
  source_ledger: relative(ROOT, ledgerPath),
  production_mutation_performed: false,
  scope:
    "exact remote-only statements plus explicitly selected semantic-diff evidence",
  remote_only_versions: ledger.remote_only.map((entry) => entry.version),
  extra_evidence_versions: extraVersions,
  files,
};

mkdirSync(dirname(manifestPath), { recursive: true });
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(
  `Exported ${files.length} remote migration evidence files to ` +
    `${relative(ROOT, outputDirectory)}.`,
);
