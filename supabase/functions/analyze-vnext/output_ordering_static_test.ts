import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  PHOTO_ANALYSIS_JSON_SCHEMA,
  PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
} from "./contracts.ts";
import { SECTOR_PROFILES } from "./sector-profile.ts";

const promptSource = await Deno.readTextFile(
  new URL("./prompt.ts", import.meta.url),
);

function orderOf(schema: Record<string, unknown>, key: string): number {
  const ordering = schema.propertyOrdering as string[];
  return ordering.indexOf(key);
}

Deno.test("hazard_facts is written before the module sweep in both schemas", () => {
  // Gemini generates structured output in schema order. With the module audit,
  // mandatory outcomes and sector evidence ahead of it, findings were written
  // last out of an 8192-token budget and production sat at three facts per
  // photo whatever the photograph contained. The same ordering caused the v173
  // regression in the previous engine.
  for (
    const schema of [
      PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
      PHOTO_ANALYSIS_JSON_SCHEMA,
    ] as unknown as Record<string, unknown>[]
  ) {
    const ordering = schema.propertyOrdering as string[];
    const required = schema.required as string[];
    assertEquals(
      ordering,
      required,
      "propertyOrdering and required must not disagree",
    );

    // scene_inventory stays first: facts reference its entity_refs.
    assertEquals(orderOf(schema, "scene_inventory"), 0);
    assertEquals(orderOf(schema, "hazard_facts"), 1);

    const moduleKey = ordering.includes("module_audit")
      ? "module_audit"
      : "scanned_module_ids";
    assert(
      orderOf(schema, "hazard_facts") < orderOf(schema, moduleKey),
      "findings must precede the module record",
    );
    assert(
      orderOf(schema, "hazard_facts") <
        orderOf(schema, "mandatory_module_outcomes"),
    );
    assert(
      orderOf(schema, "hazard_facts") <
        orderOf(schema, "sector_context_evidence"),
    );
  }
});

Deno.test("the prompt separates reasoning order from writing order", () => {
  // The module sweep is a discovery mechanism, so it must still happen. It runs
  // in the thinking budget, which is separate from the output budget; only the
  // written order moves.
  assertStringIncludes(promptSource, "İNCELEME SIRASI (düşünme)");
  assertStringIncludes(promptSource, "YAZIM SIRASI (JSON)");
  assertStringIncludes(promptSource, "Bu tarama zorunludur ve atlanamaz");
  assertStringIncludes(promptSource, "Bulguları en sona bırakma");
  assert(
    !promptSource.includes("en son hazard_facts"),
    "the old writing order must be gone",
  );
});

Deno.test("a construction scene has its own mandatory scan block", () => {
  // The scan section covered mobile equipment, lifting, process plants, LNG and
  // workshops, and nothing for construction -- the sector where the product's
  // fatal hazards concentrate.
  assertStringIncludes(promptSource, "İnşaat/şantiye görünüyorsa");
  for (
    const cue of [
      "kalıp kenarı",
      "paraşüt tipi emniyet kemeri",
      "yaşam hattı",
      "güvenlik ağı",
      "iskele dikme tabanı",
      "seyyar elektrik kablosu",
    ]
  ) {
    assertStringIncludes(promptSource, cue);
  }
});

Deno.test("construction covers personal and collective fall protection", () => {
  const construction = SECTOR_PROFILES.construction;
  const families = construction.criticalEquipment.map((entry) =>
    entry.familyCode
  );
  assert(families.includes("fall_arrest_system"), "fall arrest missing");
  assert(
    families.includes("collective_fall_protection"),
    "collective protection missing",
  );

  const fallArrest = construction.criticalEquipment.find((entry) =>
    entry.familyCode === "fall_arrest_system"
  )!;
  assertEquals(fallArrest.checkCodes, ["fall_arrest_anchor_presence"]);
  // A harness with no identifiable anchor is its own finding, so the aliases
  // have to reach both halves.
  const aliases =
    fallArrest.checkComponentAliases["fall_arrest_anchor_presence"];
  assert(aliases.some((alias) => alias.includes("kemer")));
  assert(aliases.some((alias) => alias.includes("ankraj")));
});
