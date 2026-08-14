export type RevenueCatProductIdentity = {
  productID: string | null;
  store: string | null;
  basePlanID: string | null;
};

function nullableText(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export function normalizeRevenueCatStore(value: unknown): string | null {
  const store = nullableText(value);
  return store ? store.toUpperCase().replace(/[\s-]+/g, "_") : null;
}

/**
 * RevenueCat represents modern Google Play subscriptions as
 * `<subscription_id>:<base_plan_id>`. Persist the product and base plan
 * separately so App Store and Play can share product-tier rules without
 * erasing the store-specific evidence needed for trial routing.
 */
export function revenueCatProductIdentity(
  productIdentifier: unknown,
  storeValue: unknown,
): RevenueCatProductIdentity {
  const rawProductID = nullableText(productIdentifier)?.toLowerCase() ?? null;
  const store = normalizeRevenueCatStore(storeValue);
  if (!rawProductID) return { productID: null, store, basePlanID: null };

  if (store === "PLAY_STORE") {
    const separator = rawProductID.indexOf(":");
    if (separator > 0 && separator < rawProductID.length - 1) {
      return {
        productID: rawProductID.slice(0, separator),
        store,
        basePlanID: rawProductID.slice(separator + 1),
      };
    }
  }

  return { productID: rawProductID, store, basePlanID: null };
}

export function revenueCatNullableText(value: unknown): string | null {
  return nullableText(value);
}
