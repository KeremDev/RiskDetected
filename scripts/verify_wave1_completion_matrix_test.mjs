import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  acceptedCompletionStatuses,
  validateCompletionMatrix,
} from "./verify_wave1_completion_matrix.mjs";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const MATRIX_PATH = resolve(
  ROOT,
  "docs/localization/phase-8/WAVE1_COMPLETION_MATRIX_2026-08-20_BUILD86.json",
);

function matrix() {
  return JSON.parse(readFileSync(MATRIX_PATH, "utf8"));
}

test("current matrix is submit-ready with no blocker or evidence gap", () => {
  const value = matrix();
  const result = validateCompletionMatrix(value);
  assert.equal(result.valid, true);
  assert.deepEqual(result.blockers, []);
  assert.deepEqual(result.evidenceGaps, []);
  assert.deepEqual(value.blocking_requirement_ids, []);
  assert.deepEqual(value.evidence_gap_requirement_ids, []);
});

test("owner-reserved submission and release do not fabricate completion", () => {
  const value = matrix();
  const result = validateCompletionMatrix(value);
  assert.deepEqual(
    result.ownerReserved.map((item) => item.id).sort(),
    ["AUTH-01", "AUTH-02"],
  );
  for (const item of result.ownerReserved) {
    assert.ok(acceptedCompletionStatuses.has(item.status));
  }
});

test("a blocker cannot be hidden only by removing it from the declared list", () => {
  const value = matrix();
  const gate = value.requirements.find((item) => item.id === "GATE-02");
  gate.status = "blocked_synthetic_regression";
  value.blocking_requirement_ids = [];
  const result = validateCompletionMatrix(value);
  assert.ok(result.blockers.length > 0);
  assert.ok(result.blockers.some((item) => item.id === "GATE-02"));
});
