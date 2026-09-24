import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  resolveRevenueCatEventUserID,
  revenueCatTransferIDs,
  revenueCatUUIDFrom,
  revenueCatUUIDsFrom,
} from "./revenuecat-event.ts";

const userA = "11111111-1111-4111-8111-111111111111";
const userB = "22222222-2222-4222-8222-222222222222";

Deno.test("RevenueCat UUID parser ignores anonymous and invalid IDs", () => {
  assertEquals(revenueCatUUIDFrom(userA.toUpperCase()), userA);
  assertEquals(revenueCatUUIDFrom("$RCAnonymousID:abc"), null);
  assertEquals(revenueCatUUIDFrom("not-a-uuid"), null);
});

Deno.test("RevenueCat UUID array parser de-duplicates IDs", () => {
  assertEquals(
    revenueCatUUIDsFrom([
      userA,
      "$RCAnonymousID:abc",
      userA.toUpperCase(),
      userB,
    ]),
    [userA, userB],
  );
});

Deno.test("RevenueCat transfer payload exposes from and to UUID arrays", () => {
  assertEquals(
    revenueCatTransferIDs({
      transferred_from: [userA, "$RCAnonymousID:abc"],
      transferred_to: [userB],
    }),
    {
      transferredFrom: [userA],
      transferredTo: [userB],
    },
  );
});

Deno.test("RevenueCat event user resolver handles transferred_to arrays", () => {
  assertEquals(
    resolveRevenueCatEventUserID({
      type: "TRANSFER",
      transferred_to: ["$RCAnonymousID:abc", userB],
    }),
    userB,
  );
});

Deno.test("RevenueCat event user resolver prefers app_user_id for normal events", () => {
  assertEquals(
    resolveRevenueCatEventUserID({
      app_user_id: userA,
      original_app_user_id: userB,
      aliases: [userB],
    }),
    userA,
  );
});
