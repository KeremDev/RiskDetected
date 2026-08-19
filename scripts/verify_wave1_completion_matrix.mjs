#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const DEFAULT_MATRIX = resolve(
  ROOT,
  "docs/localization/phase-8/WAVE1_COMPLETION_MATRIX_2026-08-19_BUILD83.json",
);
const APP_CONFIG = JSON.parse(
  readFileSync(resolve(ROOT, "appstore/app.json"), "utf8"),
);

export const acceptedCompletionStatuses = new Set([
  "passed",
  "passed_with_explicit_owner_waiver",
  "passed_with_non_blocking_warnings",
  "deferred_until_explicit_owner_instruction",
  "reserved_to_owner_after_approval",
]);

export function validateCompletionMatrix(matrix) {
  assert.equal(matrix.schema_version, 1, "unsupported matrix schema");
  assert.equal(matrix.candidate?.version, APP_CONFIG.release.version);
  assert.equal(matrix.candidate?.build, APP_CONFIG.release.build_number);
  assert.equal(matrix.candidate?.build_id, APP_CONFIG.release.build_id);
  assert.deepEqual(matrix.protected_store_locales, APP_CONFIG.protected_locales);
  assert.deepEqual(
    [...matrix.mutable_store_locales].sort(),
    [...APP_CONFIG.mutable_locales].sort(),
  );
  assert.ok(Array.isArray(matrix.requirements));
  assert.ok(matrix.requirements.length > 0);

  const ids = matrix.requirements.map((item) => item.id);
  assert.equal(new Set(ids).size, ids.length, "requirement IDs must be unique");
  const byID = new Map(matrix.requirements.map((item) => [item.id, item]));

  for (const item of matrix.requirements) {
    assert.equal(typeof item.requirement, "string");
    assert.ok(item.requirement.length > 0);
    assert.equal(typeof item.status, "string");
    assert.ok(item.status.length > 0);
    assert.ok(Array.isArray(item.evidence));
    assert.ok(item.evidence.length > 0);
  }

  for (const id of matrix.blocking_requirement_ids) {
    assert.ok(byID.has(id), `unknown blocking requirement ${id}`);
  }
  for (const id of matrix.evidence_gap_requirement_ids) {
    assert.ok(byID.has(id), `unknown evidence-gap requirement ${id}`);
  }
  for (const id of matrix.owner_reserved_requirement_ids) {
    assert.ok(byID.has(id), `unknown owner-reserved requirement ${id}`);
  }

  const evidenceGapIDs = new Set(matrix.evidence_gap_requirement_ids);
  const ownerReservedIDs = new Set(matrix.owner_reserved_requirement_ids);
  const blockers = matrix.requirements.filter((item) =>
    matrix.blocking_requirement_ids.includes(item.id) ||
    (
      !acceptedCompletionStatuses.has(item.status) &&
      !evidenceGapIDs.has(item.id) &&
      !ownerReservedIDs.has(item.id)
    )
  );
  const evidenceGaps = matrix.requirements.filter((item) =>
    matrix.evidence_gap_requirement_ids.includes(item.id)
  );
  const ownerReserved = matrix.requirements.filter((item) =>
    matrix.owner_reserved_requirement_ids.includes(item.id)
  );

  return {
    valid: blockers.length === 0 && evidenceGaps.length === 0,
    blockers,
    evidenceGaps,
    ownerReserved,
    requirementCount: matrix.requirements.length,
  };
}

function argumentValue(name) {
  const prefix = `${name}=`;
  const raw = process.argv.find((value) => value.startsWith(prefix));
  return raw ? raw.slice(prefix.length) : null;
}

function main() {
  const matrixPath = resolve(
    ROOT,
    argumentValue("--matrix") ?? DEFAULT_MATRIX,
  );
  const expectBlocked = process.argv.includes("--expect-blocked");
  const matrix = JSON.parse(readFileSync(matrixPath, "utf8"));
  const result = validateCompletionMatrix(matrix);

  if (expectBlocked) {
    assert.ok(
      !result.valid,
      "matrix unexpectedly claims submit readiness",
    );
    assert.deepEqual(
      result.blockers.map((item) => item.id).sort(),
      [...matrix.blocking_requirement_ids].sort(),
      "declared blockers and calculated blockers differ",
    );
    assert.deepEqual(
      result.evidenceGaps.map((item) => item.id).sort(),
      [...matrix.evidence_gap_requirement_ids].sort(),
      "declared evidence gaps and calculated evidence gaps differ",
    );
    console.log(
      `Wave 1 audit is internally consistent: ` +
        `${result.requirementCount} requirements, ` +
        `${result.blockers.length} blockers, ` +
        `${result.evidenceGaps.length} evidence gap.`,
    );
    return;
  }

  if (!result.valid) {
    console.error(
      `Wave 1 is not submit-ready: ${result.blockers.length} blocker(s), ` +
        `${result.evidenceGaps.length} evidence gap(s).`,
    );
    for (const item of [...result.blockers, ...result.evidenceGaps]) {
      console.error(`- ${item.id}: ${item.requirement} [${item.status}]`);
    }
    process.exitCode = 1;
    return;
  }

  console.log(
    `Wave 1 submit-readiness passed: ` +
      `${result.requirementCount} requirements satisfied.`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
