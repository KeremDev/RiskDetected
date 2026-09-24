// Server identities of the checklist wizard's extension packs. The catalogue build (build.mjs) and the
// extension migration generator (generate_extension_migration.mjs) must agree on them.
export const BASE_CATALOG = "checklist-tr-2026-09-15-v1";
export const EXTENSION_CATALOG = "checklist-tr-2026-09-25-ext1";
export const EXTENSION_MIGRATION = "supabase/migrations/20260925002500_checklist_catalog_extension_v1.sql";

/** Catalogue template code (EXT-EARTHMOVE) and its runtime template (catalog_ext_earthmove). */
export const extTemplateCode = (pack) => "EXT-" + pack;
export const extRuntimeTemplate = (pack) => "catalog_ext_" + pack.toLowerCase();
/** Catalogue item code (EXT-EARTHMOVE-01) and its runtime item code (ext_earthmove_01). */
export const extItemCode = (pack, index) => "EXT-" + pack + "-" + String(index + 1).padStart(2, "0");
export const extRuntimeItem = (pack, index) => "ext_" + pack.toLowerCase() + "_" + String(index + 1).padStart(2, "0");
/** Atomic item code shared by the wizard catalogue and the server. */
export const extAtomicCode = (pack, index) => "ACX-" + pack + "-" + String(index + 1).padStart(2, "0");
