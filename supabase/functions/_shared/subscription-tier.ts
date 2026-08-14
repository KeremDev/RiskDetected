export type PlanTier = "free" | "plus" | "pro";

export function tierFromProductIdentifier(
  productID: string | null | undefined,
): PlanTier | null {
  const product = productID?.trim().toLowerCase() ?? "";
  if (!product) return null;

  if (
    product === "riskdetected_plus_monthly" ||
    product === "riskdetected_plus_yearly"
  ) return "plus";
  if (
    product === "riskdetected_pro_monthly" ||
    product === "riskdetected_pro_yearly"
  ) return "pro";

  const parts = new Set(product.split(/[^a-z0-9]+/).filter(Boolean));
  if (parts.has("plus")) return "plus";
  if (parts.has("pro")) return "pro";
  return null;
}

export function tierFromProductOrEntitlements(
  entitlementIDs: string[],
  productID: string | null | undefined,
): PlanTier {
  const productTier = tierFromProductIdentifier(productID);
  if (productTier) return productTier;

  if (entitlementIDs.includes("pro")) return "pro";
  if (entitlementIDs.includes("plus")) return "plus";
  return "free";
}

export function isExplicitPaidUpgradeSync(
  previousTier: PlanTier | null,
  resolvedTier: PlanTier,
  expectedTier: PlanTier | null,
): boolean {
  return previousTier === "plus" && resolvedTier === "pro" &&
    expectedTier === "pro";
}
