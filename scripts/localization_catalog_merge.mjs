// Existing translations (including human review metadata, plural variations
// and additional locales) are authoritative. Generation may only fill gaps.
export function mergeCatalog(existing, generated) {
  if (!existing) return structuredClone(generated);
  if (existing.sourceLanguage !== generated.sourceLanguage ||
      typeof existing.strings !== 'object' || !existing.strings || Array.isArray(existing.strings)) {
    throw new Error('CATALOG_MERGE_INVALID_EXISTING');
  }
  const fill = (old, next) => {
    if (old === undefined) return structuredClone(next);
    if (!old || !next || typeof old !== 'object' || typeof next !== 'object' ||
        Array.isArray(old) || Array.isArray(next)) return structuredClone(old);
    const result = structuredClone(old);
    for (const [key, value] of Object.entries(next)) result[key] = fill(old[key], value);
    return result;
  };
  const result = fill(existing, generated);
  // Never mix a generated singular stringUnit into an existing plural/device
  // variation (or overwrite a reviewed locale). Only absent locales are added.
  for (const [key, entry] of Object.entries(existing.strings)) {
    for (const [locale, value] of Object.entries(entry.localizations ?? {})) {
      result.strings[key].localizations[locale] = structuredClone(value);
    }
  }
  result.strings = Object.fromEntries(Object.entries(result.strings).sort(([a], [b]) => a.localeCompare(b)));
  return result;
}
