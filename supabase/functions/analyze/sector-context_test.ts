import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  ANALYSIS_SECTOR_ALLOWLIST,
  ACTIVE_ANALYSIS_SECTOR_PROMPT_VERSION,
  analysisSectorLabel,
  buildActiveSectorPromptBlock,
  normalizeAnalysisSector,
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
  assertEquals(analysisSectorLabel("logistics_warehouse", "tr"), "Depo / Lojistik");
  assertEquals(analysisSectorLabel("construction", "en"), "Construction");
});
