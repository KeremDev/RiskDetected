export function revenueCatUUIDFrom(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const clean = value.trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      clean,
    )
    ? clean
    : null;
}

export function revenueCatUUIDsFrom(value: unknown): string[] {
  const values = Array.isArray(value) ? value : [value];
  const seen = new Set<string>();
  const result: string[] = [];

  for (const item of values) {
    const id = revenueCatUUIDFrom(item);
    if (!id || seen.has(id)) continue;
    seen.add(id);
    result.push(id);
  }

  return result;
}

export function revenueCatTransferIDs(event: Record<string, unknown>): {
  transferredFrom: string[];
  transferredTo: string[];
} {
  return {
    transferredFrom: revenueCatUUIDsFrom(event.transferred_from),
    transferredTo: revenueCatUUIDsFrom(event.transferred_to),
  };
}

export function resolveRevenueCatEventUserID(
  event: Record<string, unknown>,
): string | null {
  const candidates: unknown[] = [
    event.app_user_id,
    event.original_app_user_id,
    event.transferred_to,
  ];
  if (Array.isArray(event.aliases)) candidates.push(...event.aliases);

  for (const candidate of candidates) {
    const ids = revenueCatUUIDsFrom(candidate);
    if (ids[0]) return ids[0];
  }

  return null;
}
