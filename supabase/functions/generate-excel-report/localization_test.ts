import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import XLSX from "npm:xlsx-js-style@1.2.0";
import { makeEnglishWorkbook } from "./index.ts";

Deno.test("English XLSX parser sees localized sheets and no TR regulatory template", () => {
  const workbook = makeEnglishWorkbook(
    {
      id: "11111111-1111-4111-8111-111111111111",
      user_id: "22222222-2222-4222-8222-222222222222",
      title: "Loading-bay inspection",
      canvas: "mobile_equipment",
      kind: "photo",
      status: "completed",
      ai_summary: "One vehicle–pedestrian interface requires controls.",
      total_score_fk: 90,
      total_score_m5: 12,
      highest_band_fk: "medium",
      highest_band_m5: "high",
      finding_count: 1,
      created_at: "2026-07-30T12:00:00Z",
      completed_at: "2026-07-30T12:01:00Z",
      analysis_sector: null,
    },
    [{
      ordinal: 1,
      title: "Forklift and pedestrian routes overlap",
      category: "Vehicle movement",
      description: "A marked separation is not visible in the loading area.",
      recommended_action:
        "Separate the routes and verify the controls on site.",
      recommended_measures: [{
        kind: "corrective",
        title: "",
        text: "Install a physical barrier where practicable.",
      }],
      references_text: null,
      root_cause_text: "Shared route design",
      fk_probability: 3,
      fk_frequency: 3,
      fk_severity: 10,
      fk_score: 90,
      fk_band: "medium",
      m5_probability: 3,
      m5_severity: 4,
      m5_score: 12,
      m5_band: "high",
    }],
    {
      display_name: "Alex Morgan",
      company_name: "Example Works",
    },
    "matrix_5x5",
    "request-1",
    "RD-TEST1234",
    "XLSX-5X5-11111111-TEST1234",
    {
      language: "en",
      locale: "en-GB",
      safetyProfileID: "en-gb-generic-v1",
      safetyProfileVersion: 1,
      regulatorySectionsEnabled: false,
      snapshot: {
        schema_version: 1,
        output_language: "en",
        output_locale: "en-GB",
      },
    },
  );

  const summaryTitle = workbook.Sheets["Summary"]["A1"] as XLSX.CellObject;
  const registerHeader = workbook
    .Sheets["Risk register"]["A1"] as XLSX.CellObject;
  const registerNumber = workbook
    .Sheets["Risk register"]["E2"] as XLSX.CellObject;
  assertEquals(summaryTitle.s?.fill?.fgColor?.rgb, "E8F8EE");
  assertEquals(registerHeader.s?.fill?.fgColor?.rgb, "DDF3FB");
  assertEquals(registerNumber.s?.fill?.fgColor?.rgb, "FFFFFF");

  const bytes = XLSX.write(workbook, {
    bookType: "xlsx",
    type: "buffer",
    cellStyles: true,
  }) as Uint8Array;
  const parsed = XLSX.read(bytes, { type: "buffer" });

  assertEquals(parsed.SheetNames, [
    "Summary",
    "Risk register",
    "Report information",
  ]);

  const rows = parsed.SheetNames.flatMap((name) =>
    XLSX.utils.sheet_to_json<unknown[]>(parsed.Sheets[name], {
      header: 1,
      raw: false,
    })
  );
  const text = rows.flat().map(String).join("\n").toLocaleLowerCase("en");
  assert(text.includes("workplace-safety risk assessment"));
  assert(text.includes("30 july 2026"));
  assert(text.includes("does not determine legal compliance"));
  assertFalse(text.includes("mevzuat"));
  assertFalse(text.includes("osgb"));
  assertFalse(text.includes("6331"));
  assertFalse(text.includes("tehlike sınıfı"));
  assertFalse(text.includes("belge no"));
});
