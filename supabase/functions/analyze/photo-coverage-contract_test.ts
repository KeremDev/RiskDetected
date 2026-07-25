import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  coverageRecordRequiresRepair,
  exactCoverageSchemaConstraints,
  inspectPhotoCoverageContract,
  normalizeExpectedPhotoIndices,
} from "./photo-coverage-contract.ts";

Deno.test("coverage contract accepts exact records in any order", () => {
  assertEquals(
    inspectPhotoCoverageContract(
      [{ photo_index: 3 }, { photo_index: 1 }, { photo_index: 2 }],
      [1, 2, 3],
    ),
    {
      expected_indices: [1, 2, 3],
      expected_records: 3,
      returned_records: 3,
      valid_indices: [1, 2, 3],
      missing_indices: [],
      duplicate_indices: [],
      invalid_indices: [],
      normalized_records: 3,
      outcome: "complete",
    },
  );
});

Deno.test("coverage contract reports missing records", () => {
  const report = inspectPhotoCoverageContract(
    [{ photo_index: 1 }, { photo_index: 3 }],
    [1, 2, 3],
  );
  assertEquals(report.missing_indices, [2]);
  assertEquals(report.outcome, "missing_records");
});

Deno.test("coverage contract separates duplicates and invalid indices", () => {
  const report = inspectPhotoCoverageContract(
    [
      { photo_index: 1 },
      { photo_index: 1 },
      { photo_index: 2 },
      { photo_index: 9 },
      { photo_index: "bad" },
    ],
    [1, 2],
  );
  assertEquals(report.missing_indices, []);
  assertEquals(report.duplicate_indices, [1]);
  assertEquals(report.invalid_indices, [9, null]);
  assertEquals(report.outcome, "normalized_contract_violation");
});

Deno.test("coverage contract supports targeted repair indices", () => {
  assertEquals(
    inspectPhotoCoverageContract([{ photo_index: 3 }], [3]).outcome,
    "complete",
  );
  assertEquals(normalizeExpectedPhotoIndices([3, 3, 2]), [2, 3]);
});

Deno.test("exact coverage schema supports two, three and targeted repair records", () => {
  assertEquals(
    exactCoverageSchemaConstraints({
      schemaVersion: 2,
      originalPhotoCount: 2,
      expectedPhotoIndices: [1, 2],
    }),
    {
      enabled: true,
      minItems: 2,
      maxItems: 2,
      photoIndexEnum: ["1", "2"],
    },
  );
  assertEquals(
    exactCoverageSchemaConstraints({
      schemaVersion: 2,
      originalPhotoCount: 3,
      expectedPhotoIndices: [1, 2, 3],
    }).maxItems,
    3,
  );
  assertEquals(
    exactCoverageSchemaConstraints({
      schemaVersion: 2,
      originalPhotoCount: 3,
      expectedPhotoIndices: [3],
    }).photoIndexEnum,
    ["3"],
  );
  assertEquals(
    exactCoverageSchemaConstraints({
      schemaVersion: 2,
      originalPhotoCount: 1,
      expectedPhotoIndices: [1],
    }),
    { enabled: false },
  );
});

Deno.test("coverage contract is not applicable without trusted indices", () => {
  assertEquals(
    inspectPhotoCoverageContract([{ photo_index: 1 }], []).outcome,
    "not_applicable",
  );
});

Deno.test("repair candidates preserve explicit clean and low-quality records", () => {
  assertEquals(
    coverageRecordRequiresRepair({
      recordMissing: false,
      coverageStatus: "no_actionable_hazard",
      findingCount: 0,
      targetMin: 1,
    }),
    false,
  );
  assertEquals(
    coverageRecordRequiresRepair({
      recordMissing: false,
      coverageStatus: "low_quality",
      findingCount: 0,
      targetMin: 1,
    }),
    false,
  );
  assertEquals(
    coverageRecordRequiresRepair({
      recordMissing: false,
      coverageStatus: "actionable",
      findingCount: 0,
      targetMin: 1,
    }),
    true,
  );
  assertEquals(
    coverageRecordRequiresRepair({
      recordMissing: true,
      coverageStatus: "no_actionable_hazard",
      findingCount: 0,
      targetMin: 1,
    }),
    true,
  );
});
