export function normalizeRevenueCatAppUserID(
  value: string | null | undefined,
): string | null {
  const normalized = value?.trim().toLowerCase() ?? "";
  return normalized ? normalized : null;
}

export function isRevenueCatAnonymousAppUserID(
  value: string | null | undefined,
): boolean {
  const normalized = normalizeRevenueCatAppUserID(value);
  return normalized?.startsWith("$rcanonymousid:") ?? false;
}

export function isIdentifiedRevenueCatOwnerMismatch(
  originalAppUserID: string | null | undefined,
  currentUserID: string,
): boolean {
  const original = normalizeRevenueCatAppUserID(originalAppUserID);
  const current = currentUserID.trim().toLowerCase();
  if (!original || !current) return false;
  if (isRevenueCatAnonymousAppUserID(original)) return false;
  return original !== current;
}
