#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, relative, resolve } from "node:path";
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

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function lexicalNormalize(sql) {
  return sql
    .replace(/^\uFEFF/, "")
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/--[^\n\r]*/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function stripTerminators(sql) {
  return sql.replace(/(?:\s*;\s*)+$/g, "").trim();
}

function commonPrefixLength(left, right) {
  let index = 0;
  while (
    index < left.length &&
    index < right.length &&
    left[index] === right[index]
  ) {
    index += 1;
  }
  return index;
}

function commonSuffixLength(left, right, prefixLength) {
  let length = 0;
  while (
    length < left.length - prefixLength &&
    length < right.length - prefixLength &&
    left[left.length - 1 - length] === right[right.length - 1 - length]
  ) {
    length += 1;
  }
  return length;
}

const ledgerPath = resolve(argument("--ledger"));
const outputPath = resolve(argument("--output"));
const capturedAt = argument("--captured-at");
const remoteDirectoryIndex = process.argv.indexOf("--remote-dir");
const remoteDirectory =
  remoteDirectoryIndex >= 0 && process.argv[remoteDirectoryIndex + 1]
    ? resolve(process.argv[remoteDirectoryIndex + 1])
    : null;
const ledger = JSON.parse(readFileSync(ledgerPath, "utf8"));
const localByVersion = new Map(
  ledger.local_files.map((entry) => [entry.version, entry]),
);
const remoteByVersion = new Map(
  ledger.remote_files.map((entry) => [entry.version, entry]),
);

const comparisons = [];
for (const [version, local] of localByVersion) {
  const remote = remoteByVersion.get(version);
  if (!remote) continue;

  const localSql = readFileSync(resolve(ROOT, local.file), "utf8");
  const remotePath = remoteDirectory
    ? resolve(remoteDirectory, remote.file.split("/").at(-1))
    : resolve(ROOT, remote.file);
  const remoteSql = readFileSync(remotePath, "utf8");
  const localNormalized = lexicalNormalize(localSql);
  const remoteNormalized = lexicalNormalize(remoteSql);
  const localWithoutTerminators = stripTerminators(localNormalized);
  const remoteWithoutTerminators = stripTerminators(remoteNormalized);

  let classification = "semantic_divergence";
  if (local.sha256 === remote.sha256) {
    classification = "byte_identical";
  } else if (localNormalized === remoteNormalized) {
    classification = "comment_or_whitespace_only";
  } else if (localWithoutTerminators === remoteWithoutTerminators) {
    classification = "statement_terminator_only";
  }

  const prefixLength = commonPrefixLength(
    localWithoutTerminators,
    remoteWithoutTerminators,
  );
  const suffixLength = commonSuffixLength(
    localWithoutTerminators,
    remoteWithoutTerminators,
    prefixLength,
  );

  comparisons.push({
    version,
    local_name: local.name,
    remote_name: remote.name,
    classification,
    local_sha256: local.sha256,
    remote_sha256: remote.sha256,
    local_normalized_sha256: sha256(localWithoutTerminators),
    remote_normalized_sha256: sha256(remoteWithoutTerminators),
    local_normalized_characters: localWithoutTerminators.length,
    remote_normalized_characters: remoteWithoutTerminators.length,
    common_prefix_characters: prefixLength,
    common_suffix_characters: suffixLength,
  });
}

const counts = Object.fromEntries(
  [
    "byte_identical",
    "comment_or_whitespace_only",
    "statement_terminator_only",
    "semantic_divergence",
  ].map((classification) => [
    classification,
    comparisons.filter((entry) => entry.classification === classification)
      .length,
  ]),
);

const snapshot = {
  schema_version: 1,
  captured_at: capturedAt,
  source_ledger: relative(ROOT, ledgerPath),
  production_mutation_performed: false,
  method:
    "byte comparison followed by comment/whitespace normalization and trailing SQL terminator normalization",
  limitation:
    "Lexical equality is strong reproducibility evidence but is not a full PostgreSQL AST equivalence proof.",
  counts: {
    matched_versions: comparisons.length,
    ...counts,
  },
  semantic_divergences: comparisons.filter(
    (entry) => entry.classification === "semantic_divergence",
  ),
  comparisons,
};

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(snapshot, null, 2)}\n`);

console.log(
  `Compared ${comparisons.length} matched versions: ` +
    `${counts.semantic_divergence} semantic divergence(s).`,
);
