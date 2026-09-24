import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION,
  ANALYSIS_SECTOR_ALLOWLIST,
  analysisSectorLabel,
  buildActiveSectorPromptBlock,
  normalizeAnalysisSector,
  resolveActiveSectorState,
} from "./sector-context.ts";

Deno.test("analysis sector allowlist matches canonical set", () => {
  assertEquals([...ANALYSIS_SECTOR_ALLOWLIST].sort(), [
    "agriculture_livestock",
    "chemical_laboratory",
    "construction",
    "education",
    "energy",
    "food_production",
    "general",
    "healthcare",
    "hospitality",
    "logistics_warehouse",
    "manufacturing",
    "mining",
    "municipal_field_services",
    "office",
    "retail",
  ]);
});

Deno.test("normalizeAnalysisSector accepts valid ids and rejects invalid input", () => {
  assertEquals(normalizeAnalysisSector("construction"), "construction");
  assertEquals(normalizeAnalysisSector(" general "), "general");
  assertEquals(normalizeAnalysisSector("other"), null);
  assertEquals(normalizeAnalysisSector("'; drop table analyses; --"), null);
  assertEquals(normalizeAnalysisSector(null), null);
});

Deno.test("construction prompt block includes sector guidance", () => {
  const block = buildActiveSectorPromptBlock({
    sector: "construction",
    outputLanguage: "tr",
  });
  assert(block.includes("İnşaat"));
  assert(block.includes("Yüksekte çalışma"));
  assert(block.includes(ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION));
});

Deno.test("general prompt block avoids sector-specific guidance", () => {
  const block = buildActiveSectorPromptBlock({
    sector: "general",
    outputLanguage: "tr",
  });
  assert(block.includes("genel İSG"));
  assert(!block.includes("SEKTÖR REHBERİ — İNŞAAT"));
});

Deno.test("missing sector uses legacy prompt block", () => {
  const block = buildActiveSectorPromptBlock({ sector: null });
  assert(block.includes("eski istemciden"));
});

Deno.test("analysisSectorLabel returns Turkish labels", () => {
  assertEquals(
    analysisSectorLabel("logistics_warehouse", "tr"),
    "Depo / Lojistik",
  );
  assertEquals(analysisSectorLabel("construction", "en"), "Construction");
});

Deno.test("resolveActiveSectorState rejects invalid requested sector", () => {
  const result = resolveActiveSectorState({
    requestedSector: "other",
    persistedSector: null,
  });

  assertEquals(result.ok, false);
  if (!result.ok) {
    assertEquals(result.status, 400);
    assertEquals(result.code, "invalid_analysis_sector");
  }
});

Deno.test("resolveActiveSectorState backfills request sector when DB is empty", () => {
  const result = resolveActiveSectorState({
    requestedSector: "logistics_warehouse",
    persistedSector: null,
    requestedSource: "user_selected",
    requestedPromptVersion: ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION,
  });

  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.sector, "logistics_warehouse");
    assertEquals(result.shouldBackfill, true);
    assertEquals(result.backfillPatch, {
      analysis_sector: "logistics_warehouse",
      analysis_sector_source: "user_selected",
      analysis_sector_prompt_version: ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION,
    });
  }
});

Deno.test("resolveActiveSectorState rejects non-worker sector mismatch", () => {
  const result = resolveActiveSectorState({
    requestedSector: "construction",
    persistedSector: "manufacturing",
    isWorkerInvocation: false,
  });

  assertEquals(result.ok, false);
  if (!result.ok) {
    assertEquals(result.status, 409);
    assertEquals(result.code, "sector_mismatch");
    assertEquals(result.persistedSector, "manufacturing");
  }
});

Deno.test("resolveActiveSectorState prioritizes DB sector for worker mismatch", () => {
  const result = resolveActiveSectorState({
    requestedSector: "construction",
    persistedSector: "manufacturing",
    persistedSource: "user_selected",
    persistedPromptVersion: ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION,
    isWorkerInvocation: true,
  });

  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.sector, "manufacturing");
    assertEquals(result.shouldBackfill, false);
  }
});

Deno.test("resolveActiveSectorState ignores invalid worker request when DB sector exists", () => {
  const result = resolveActiveSectorState({
    requestedSector: "invalid_sector",
    persistedSector: "manufacturing",
    persistedSource: "user_selected",
    persistedPromptVersion: ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION,
    isWorkerInvocation: true,
  });

  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.sector, "manufacturing");
    assertEquals(result.shouldBackfill, false);
  }
});

Deno.test("resolveActiveSectorState keeps legacy null sector neutral", () => {
  const result = resolveActiveSectorState({
    requestedSector: null,
    persistedSector: null,
  });

  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.sector, null);
    assertEquals(result.source, null);
    assertEquals(result.promptVersion, null);
    assertEquals(result.shouldBackfill, false);
  }
});
