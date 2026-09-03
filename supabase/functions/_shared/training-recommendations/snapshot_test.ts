import {
  assert,
  assertEquals,
  assertMatch,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { buildTrainingCardSnapshots, trainingCardID } from "./snapshot.ts";

const ANALYSIS_ID = "11111111-2222-4333-8444-555555555555";

function sourceRow(id: string) {
  return {
    public_finding_id: id,
    internal_priority: {
      book_source: {
        schema: "book-source-v1",
        module_id: "falls_falling_objects",
        mechanism_code: "fall_from_height",
        assurance_topic_id: null,
        asset_ref: null,
        barrier_components_absent: [],
        people_visible: 2,
      },
    },
  };
}

Deno.test("training snapshot id is stable and UUID-shaped", () => {
  const first = trainingCardID(ANALYSIS_ID, "TRN-WAH-001");
  const second = trainingCardID(ANALYSIS_ID, "TRN-WAH-001");
  assertEquals(first, second);
  assertMatch(
    first,
    /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-a[0-9a-f]{3}-[0-9a-f]{12}$/,
  );
});

Deno.test("training snapshot preserves canonical audit fields", () => {
  const cards = buildTrainingCardSnapshots({
    analysisID: ANALYSIS_ID,
    sectorID: "construction",
    hazardClass: "high",
    rows: [sourceRow("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")],
  });
  const card = cards.find((value) => value.catalog_code === "TRN-WAH-001");
  assert(card);
  assertEquals(card.source_finding_ids, [
    "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  ]);
  assert(card.recommendation_class.length > 0);
  assert(card.applicability.length > 0);
  assert(card.trigger_codes.length > 0);
  assert(card.recommendation_text.length > 0);
});
