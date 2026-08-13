import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  normalizeRevenueCatStore,
  revenueCatProductIdentity,
} from "./revenuecat-store.ts";

Deno.test("normalizes RevenueCat store names", () => {
  assertEquals(normalizeRevenueCatStore("play-store"), "PLAY_STORE");
  assertEquals(normalizeRevenueCatStore(" app store "), "APP_STORE");
  assertEquals(normalizeRevenueCatStore(null), null);
});

Deno.test("splits Google Play product and base plan identity", () => {
  assertEquals(
    revenueCatProductIdentity(
      "riskdetected_plus_yearly:yearly",
      "PLAY_STORE",
    ),
    {
      productID: "riskdetected_plus_yearly",
      store: "PLAY_STORE",
      basePlanID: "yearly",
    },
  );
});

Deno.test("keeps App Store product identity intact", () => {
  assertEquals(
    revenueCatProductIdentity("RISKDETECTED_PLUS_YEARLY", "APP_STORE"),
    {
      productID: "riskdetected_plus_yearly",
      store: "APP_STORE",
      basePlanID: null,
    },
  );
});

Deno.test("does not guess a base plan without Play store evidence", () => {
  assertEquals(
    revenueCatProductIdentity("product:offer", null),
    { productID: "product:offer", store: null, basePlanID: null },
  );
});
