#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import process from "node:process";

const ROOT = resolve(import.meta.dirname, "..");
const ACTIVE_DIR = join(ROOT, "supabase", "migrations");
const ARCHIVE_DIR = join(
  ROOT,
  "supabase",
  "migrations_archive",
  "pre-localization-ledger-2026-07-28",
);
const ARCHIVE_MANIFEST = join(ARCHIVE_DIR, "MANIFEST.json");
const LEDGER_PATH = join(
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
const EVIDENCE_MANIFEST_PATH = join(
  ROOT,
  "docs",
  "localization",
  "baseline",
  "REMOTE_MIGRATION_EVIDENCE_MANIFEST_2026-07-28.json",
);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function assertHash(path, expected) {
  if (!existsSync(path)) fail(`Missing file: ${relative(ROOT, path)}`);
  const actual = sha256(path);
  if (actual !== expected) {
    fail(
      `Checksum mismatch: ${relative(ROOT, path)} expected=${expected} actual=${actual}`,
    );
  }
}

function activeMigrationFiles() {
  return readdirSync(ACTIVE_DIR)
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))
    .sort();
}

function loadJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function applyReconciliation() {
  if (existsSync(ARCHIVE_MANIFEST)) {
    fail(
      `${relative(ROOT, ARCHIVE_MANIFEST)} already exists; reconciliation is already applied`,
    );
  }

  const ledger = loadJSON(LEDGER_PATH);
  const comparison = loadJSON(COMPARISON_PATH);
  const evidenceManifest = loadJSON(EVIDENCE_MANIFEST_PATH);
  const evidenceByVersion = new Map(
    evidenceManifest.files.map((entry) => [entry.version, entry]),
  );
  const localByVersion = new Map(
    ledger.local_files.map((entry) => [entry.version, entry]),
  );
  const remoteVersions = new Set(
    ledger.remote_files.map((entry) => entry.version),
  );
  const semanticVersions = comparison.semantic_divergences.map(
    (entry) => entry.version,
  );
  const requiredEvidenceVersions = new Set([
    ...ledger.remote_only.map((entry) => entry.version),
    ...semanticVersions,
  ]);

  for (const version of requiredEvidenceVersions) {
    const evidence = evidenceByVersion.get(version);
    if (!evidence) fail(`Missing exact remote evidence for ${version}`);
    assertHash(resolve(ROOT, evidence.file), evidence.sha256);
  }
  for (const entry of ledger.local_only) {
    const activePath = join(ACTIVE_DIR, basename(entry.file));
    assertHash(activePath, entry.sha256);
  }
  for (const version of semanticVersions) {
    const local = localByVersion.get(version);
    if (!local) fail(`Missing local semantic-diff entry for ${version}`);
    assertHash(join(ACTIVE_DIR, basename(local.file)), local.sha256);
  }

  const localOnlyArchive = join(ARCHIVE_DIR, "local-only");
  const semanticArchive = join(
    ARCHIVE_DIR,
    "same-version-semantic-divergence",
  );
  mkdirSync(localOnlyArchive, { recursive: true });
  mkdirSync(semanticArchive, { recursive: true });

  const archivedLocalOnly = ledger.local_only.map((entry) => {
    const sourcePath = join(ACTIVE_DIR, basename(entry.file));
    const targetPath = join(localOnlyArchive, basename(entry.file));
    renameSync(sourcePath, targetPath);
    return {
      version: entry.version,
      name: entry.name,
      active_file: relative(ROOT, sourcePath),
      archive_file: relative(ROOT, targetPath),
      sha256: entry.sha256,
    };
  });

  const replacedSameVersion = semanticVersions.map((version) => {
    const local = localByVersion.get(version);
    const evidence = evidenceByVersion.get(version);
    const activePath = join(ACTIVE_DIR, basename(local.file));
    const archivePath = join(semanticArchive, basename(local.file));
    renameSync(activePath, archivePath);
    copyFileSync(resolve(ROOT, evidence.file), activePath);
    assertHash(activePath, evidence.sha256);
    return {
      version,
      active_file: relative(ROOT, activePath),
      archive_file: relative(ROOT, archivePath),
      archived_local_sha256: local.sha256,
      canonical_remote_sha256: evidence.sha256,
    };
  });

  const addedRemoteOnly = ledger.remote_only.map((entry) => {
    const evidence = evidenceByVersion.get(entry.version);
    const activePath = join(ACTIVE_DIR, basename(evidence.file));
    if (existsSync(activePath)) {
      fail(`Refusing to overwrite active migration: ${relative(ROOT, activePath)}`);
    }
    copyFileSync(resolve(ROOT, evidence.file), activePath);
    assertHash(activePath, evidence.sha256);
    return {
      version: entry.version,
      active_file: relative(ROOT, activePath),
      sha256: evidence.sha256,
    };
  });

  const activeFiles = activeMigrationFiles();
  const activeVersions = activeFiles.map((name) => name.slice(0, 14));
  const unexpectedVersions = activeVersions.filter(
    (version) => !remoteVersions.has(version),
  );
  const missingVersions = [...remoteVersions].filter(
    (version) => !activeVersions.includes(version),
  );
  if (
    activeFiles.length !== remoteVersions.size ||
    unexpectedVersions.length > 0 ||
    missingVersions.length > 0
  ) {
    fail(
      `Post-reconciliation active set mismatch: active=${activeFiles.length} ` +
        `remote=${remoteVersions.size} unexpected=${unexpectedVersions.join(",")} ` +
        `missing=${missingVersions.join(",")}`,
    );
  }

  const manifest = {
    schema_version: 1,
    applied_at: "2026-07-28T20:00:00+03:00",
    production_mutation_performed: false,
    strategy:
      "remote history authoritative; exact remote-only reconstruction; semantic-diff replacement; reversible local-only archive",
    source_ledger: relative(ROOT, LEDGER_PATH),
    source_content_comparison: relative(ROOT, COMPARISON_PATH),
    source_remote_evidence: relative(ROOT, EVIDENCE_MANIFEST_PATH),
    before: ledger.counts,
    after: {
      active_migration_files: activeFiles.length,
      expected_remote_versions: remoteVersions.size,
      unexpected_versions: unexpectedVersions,
      missing_versions: missingVersions,
    },
    archived_local_only: archivedLocalOnly,
    replaced_same_version: replacedSameVersion,
    added_remote_only: addedRemoteOnly,
  };

  mkdirSync(dirname(ARCHIVE_MANIFEST), { recursive: true });
  writeFileSync(ARCHIVE_MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(
    `Migration repository reconciled: ${activeFiles.length} active versions, ` +
      `${archivedLocalOnly.length} archived local-only, ` +
      `${addedRemoteOnly.length} added remote-only, ` +
      `${replacedSameVersion.length} exact semantic replacements.`,
  );
}

function restoreInterrupted() {
  if (existsSync(ARCHIVE_MANIFEST)) {
    fail(
      `${relative(ROOT, ARCHIVE_MANIFEST)} exists; use --restore for a completed reconciliation`,
    );
  }
  const ledger = loadJSON(LEDGER_PATH);
  const comparison = loadJSON(COMPARISON_PATH);
  const evidenceManifest = loadJSON(EVIDENCE_MANIFEST_PATH);
  const evidenceByVersion = new Map(
    evidenceManifest.files.map((entry) => [entry.version, entry]),
  );
  const localByVersion = new Map(
    ledger.local_files.map((entry) => [entry.version, entry]),
  );
  const localOnlyArchive = join(ARCHIVE_DIR, "local-only");
  const semanticArchive = join(
    ARCHIVE_DIR,
    "same-version-semantic-divergence",
  );

  for (const entry of ledger.remote_only) {
    const evidence = evidenceByVersion.get(entry.version);
    const activePath = join(ACTIVE_DIR, basename(evidence.file));
    assertHash(activePath, evidence.sha256);
    rmSync(activePath);
  }
  for (const entry of comparison.semantic_divergences) {
    const local = localByVersion.get(entry.version);
    const evidence = evidenceByVersion.get(entry.version);
    const activePath = join(ACTIVE_DIR, basename(local.file));
    const archivePath = join(semanticArchive, basename(local.file));
    assertHash(activePath, evidence.sha256);
    assertHash(archivePath, local.sha256);
    rmSync(activePath);
    renameSync(archivePath, activePath);
  }
  for (const entry of ledger.local_only) {
    const activePath = join(ACTIVE_DIR, basename(entry.file));
    const archivePath = join(localOnlyArchive, basename(entry.file));
    if (existsSync(activePath)) {
      fail(`Refusing to overwrite during interrupted restore: ${entry.file}`);
    }
    assertHash(archivePath, entry.sha256);
    renameSync(archivePath, activePath);
  }
  rmSync(ARCHIVE_DIR, { recursive: true, force: true });
  console.log("Interrupted migration reconciliation restored to its verified before state.");
}

function restore() {
  if (!existsSync(ARCHIVE_MANIFEST)) {
    fail(`Missing restore manifest: ${relative(ROOT, ARCHIVE_MANIFEST)}`);
  }
  const manifest = loadJSON(ARCHIVE_MANIFEST);

  for (const entry of manifest.added_remote_only) {
    const activePath = resolve(ROOT, entry.active_file);
    assertHash(activePath, entry.sha256);
    rmSync(activePath);
  }
  for (const entry of manifest.replaced_same_version) {
    const activePath = resolve(ROOT, entry.active_file);
    const archivePath = resolve(ROOT, entry.archive_file);
    assertHash(activePath, entry.canonical_remote_sha256);
    assertHash(archivePath, entry.archived_local_sha256);
    rmSync(activePath);
    renameSync(archivePath, activePath);
  }
  for (const entry of manifest.archived_local_only) {
    const activePath = resolve(ROOT, entry.active_file);
    const archivePath = resolve(ROOT, entry.archive_file);
    if (existsSync(activePath)) {
      fail(`Refusing to overwrite during restore: ${entry.active_file}`);
    }
    assertHash(archivePath, entry.sha256);
    renameSync(archivePath, activePath);
  }
  rmSync(ARCHIVE_MANIFEST);
  console.log("Migration repository reconciliation restored.");
}

if (process.argv.includes("--restore-interrupted")) {
  restoreInterrupted();
} else if (process.argv.includes("--restore")) {
  restore();
} else {
  applyReconciliation();
}
