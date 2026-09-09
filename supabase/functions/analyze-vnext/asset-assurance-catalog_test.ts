import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type AssetInventoryItem,
  resolveAssetAssuranceProfiles,
} from "./asset-assurance-catalog.ts";

function item(overrides: Partial<AssetInventoryItem> = {}): AssetInventoryItem {
  return {
    entity_ref: "container_1",
    equipment_family: "Kimyasal kap",
    component: "Kova",
    visible_condition_summary: "Mavi plastik kova zeminde duruyor",
    ...overrides,
  };
}

function profileIDs(inventory: AssetInventoryItem[]): string[] {
  return resolveAssetAssuranceProfiles(inventory).map((entry) =>
    entry.profile.profileID
  );
}

Deno.test("an unmarked bucket does not raise chemical-management assurance", () => {
  // The live 2026-08-24 construction analysis produced a chemical inventory and
  // SDS assurance item from a plain blue bucket, because the model happened to
  // call it a container. Nothing identified its contents.
  assertFalse(profileIDs([item()]).includes("chemical_material_management"));
});

Deno.test("a labelled container does raise chemical-management assurance", () => {
  assert(
    profileIDs([
      item({
        visible_condition_summary:
          "Kap üzerinde tehlike piktogramı ve ürün etiketi okunuyor",
      }),
    ]).includes("chemical_material_management"),
  );
});

Deno.test("bulk vessels and containment furniture carry their own identification", () => {
  for (
    const summary of [
      "IBC tank sundurma altında",
      "Dökülme tavası üzerinde duran kap",
      "Kimyasal depolama dolabında duran kap",
    ]
  ) {
    assert(
      profileIDs([item({ visible_condition_summary: summary })]).includes(
        "chemical_material_management",
      ),
      summary,
    );
  }
});

Deno.test("an unmarked drum is not a chemical inventory subject", () => {
  // A plain blue barrel on a construction site produced an SDS and
  // chemical-storage record whose own text read "kimyasal icerebilecek
  // kaplar". Drum geometry was being treated as proof of contents.
  for (
    const summary of [
      "Zeminde mavi renkli metal bir varil duruyor",
      "Paletlenmiş 200 litrelik varil",
      "Duvar dibinde plastik bidon",
    ]
  ) {
    assertFalse(
      profileIDs([item({ visible_condition_summary: summary })]).includes(
        "chemical_material_management",
      ),
      summary,
    );
  }
});

Deno.test("condition evidence can withhold a profile but never create one", () => {
  // The gate reads equipment_family and component first. A vivid condition
  // summary on unrelated equipment must not conjure the chemical profile.
  assertFalse(
    profileIDs([
      item({
        equipment_family: "Mobil iş ekipmanı",
        component: "Şasi",
        visible_condition_summary:
          "Üzerinde tehlike piktogramı ve ürün etiketi bulunan uyarı levhası",
      }),
    ]).includes("chemical_material_management"),
  );
});
