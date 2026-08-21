import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  hazardConfidence,
  productionConfidenceFinding,
  productionFindingNeedsFieldVerification,
} from "./finding-confidence.ts";

Deno.test("production confidence normalization is bounded", () => {
  assertEquals(hazardConfidence({ confidence: -1 }), 0);
  assertEquals(hazardConfidence({ confidence: 0.65 }), 0.65);
  assertEquals(hazardConfidence({ confidence: 4 }), 1);
  assertEquals(hazardConfidence({ confidence: "invalid" }), 0);
});

Deno.test("production confidence filter rejects findings below 0.5", () => {
  assertEquals(productionConfidenceFinding({ confidence: 0.49 }), false);
  assertEquals(productionConfidenceFinding({ confidence: 0.5 }), true);
});

Deno.test("production verification flag covers the 0.5 to 0.7 band", () => {
  assertEquals(
    productionFindingNeedsFieldVerification({ confidence: 0.5 }),
    true,
  );
  assertEquals(
    productionFindingNeedsFieldVerification({ confidence: 0.69 }),
    true,
  );
  assertEquals(
    productionFindingNeedsFieldVerification({ confidence: 0.7 }),
    false,
  );
  assertEquals(
    productionFindingNeedsFieldVerification({
      confidence: 0.9,
      needs_field_verification: true,
    }),
    false,
  );
  assertEquals(
    productionFindingNeedsFieldVerification({
      confidence: 0.69,
      needs_field_verification: false,
      verification_reason_code: "periodic_inspection_status",
      display_group: "field_verification",
    }),
    true,
  );
  assertEquals(
    productionFindingNeedsFieldVerification({
      confidence: 0.9,
      needs_field_verification: true,
      verification_reason_code: "periodic_inspection_status",
      display_group: "field_verification",
    }),
    true,
  );
  assertEquals(
    productionFindingNeedsFieldVerification({
      confidence: 0.9,
      needs_field_verification: true,
      verification_reason_code: "periodic_inspection_status",
    }),
    false,
  );
});
