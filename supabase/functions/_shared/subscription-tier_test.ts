import {
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  isExplicitPaidUpgradeSync,
  tierFromProductIdentifier,
  tierFromProductOrEntitlements,
} from "./subscription-tier.ts";

Deno.test("Plus products always resolve to plus", () => {
  assertEquals(tierFromProductIdentifier("riskdetected_plus_monthly"), "plus");
  assertEquals(tierFromProductIdentifier("riskdetected_plus_yearly"), "plus");
});

Deno.test("Pro products resolve to pro", () => {
  assertEquals(tierFromProductIdentifier("riskdetected_pro_monthly"), "pro");
  assertEquals(tierFromProductIdentifier("riskdetected_pro_yearly"), "pro");
});

Deno.test("Product ID overrides mixed entitlement IDs", () => {
  assertEquals(
    tierFromProductOrEntitlements(
      ["plus", "pro"],
      "riskdetected_plus_yearly",
    ),
    "plus",
  );
});

Deno.test("Plus product overrides stale pro-only entitlement", () => {
  assertEquals(
    tierFromProductOrEntitlements(["pro"], "riskdetected_plus_yearly"),
    "plus",
  );
});

Deno.test("Entitlement fallback is used only when product ID is missing", () => {
  assertEquals(tierFromProductOrEntitlements(["pro"], null), "pro");
  assertEquals(tierFromProductOrEntitlements(["plus"], null), "plus");
});

Deno.test("Explicit Pro purchase can upgrade active Plus sync", () => {
  assertEquals(isExplicitPaidUpgradeSync("plus", "pro", "pro"), true);
});

Deno.test("Implicit subscriber snapshots cannot silently upgrade Plus to Pro", () => {
  assertEquals(isExplicitPaidUpgradeSync("plus", "pro", null), false);
  assertEquals(isExplicitPaidUpgradeSync("plus", "pro", "plus"), false);
  assertEquals(isExplicitPaidUpgradeSync("free", "pro", "pro"), false);
});
