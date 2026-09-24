import {
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  isIdentifiedRevenueCatOwnerMismatch,
  isRevenueCatAnonymousAppUserID,
  normalizeRevenueCatAppUserID,
} from "./revenuecat-owner-guard.ts";

const currentUserID = "11111111-1111-4111-8111-111111111111";
const otherUserID = "22222222-2222-4222-8222-222222222222";

Deno.test("RevenueCat anonymous original app user id is not owner mismatch", () => {
  assertEquals(isRevenueCatAnonymousAppUserID("$RCAnonymousID:abc123"), true);
  assertEquals(
    isIdentifiedRevenueCatOwnerMismatch("$RCAnonymousID:abc123", currentUserID),
    false,
  );
});

Deno.test("Same identified original app user id is accepted", () => {
  assertEquals(
    isIdentifiedRevenueCatOwnerMismatch(currentUserID.toUpperCase(), currentUserID),
    false,
  );
});

Deno.test("Different identified original app user id is owner mismatch", () => {
  assertEquals(
    isIdentifiedRevenueCatOwnerMismatch(otherUserID, currentUserID),
    true,
  );
});

Deno.test("Empty original app user id is treated as unknown owner, not mismatch", () => {
  assertEquals(normalizeRevenueCatAppUserID("  "), null);
  assertEquals(isIdentifiedRevenueCatOwnerMismatch(null, currentUserID), false);
});
