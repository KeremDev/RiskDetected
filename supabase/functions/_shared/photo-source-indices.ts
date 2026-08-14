export function normalizeSourcePhotoIndices(
  value: unknown,
  photoCount: number,
): number[] {
  if (photoCount <= 0) return [];
  const raw = Array.isArray(value) ? value : [1];
  const indices = [
    ...new Set(
      raw
        .map((item) => Math.round(Number(item)))
        .filter((item) =>
          Number.isFinite(item) && item >= 1 && item <= photoCount
        ),
    ),
  ].sort((a, b) => a - b);
  return indices.length > 0 ? indices : [1];
}
