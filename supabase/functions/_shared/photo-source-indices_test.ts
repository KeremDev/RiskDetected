import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { normalizeSourcePhotoIndices } from "./photo-source-indices.ts";

Deno.test("source photo indices stay unique, sorted and in range", () => {
  assertEquals(normalizeSourcePhotoIndices([2, 1, 2, 3], 2), [1, 2]);
  assertEquals(normalizeSourcePhotoIndices(["2", 1.2], 2), [1, 2]);
});

Deno.test("invalid or missing source indices use the production fallback", () => {
  assertEquals(normalizeSourcePhotoIndices(undefined, 1), [1]);
  assertEquals(normalizeSourcePhotoIndices([], 3), [1]);
  assertEquals(normalizeSourcePhotoIndices([0, 4, "invalid"], 3), [1]);
  assertEquals(normalizeSourcePhotoIndices([99], 0), []);
});
