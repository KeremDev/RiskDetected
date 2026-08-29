import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  lintTrainingText,
  trainingRecommendationsFor,
  type TrainingItemRow,
} from "./index.ts";
import { equipmentFamilyOf } from "./engine.ts";
import { TRAINING_CATALOG, TRAINING_RULES } from "./catalog.tr.ts";

function item(overrides: {
  id: string;
  module?: string;
  mechanism?: string | null;
  topic?: string | null;
  asset?: string | null;
  barriers?: string[];
  people?: number;
}): TrainingItemRow {
  return {
    public_finding_id: overrides.id,
    internal_priority: {
      book_source: {
        schema: "book-source-v1",
        module_id: overrides.module ?? "falls_falling_objects",
        mechanism_code: overrides.mechanism === undefined
          ? "fall_from_height"
          : overrides.mechanism,
        assurance_topic_id: overrides.topic ?? null,
        asset_ref: overrides.asset ?? null,
        barrier_components_absent: overrides.barriers ?? [],
        people_visible: overrides.people ?? 0,
      },
    },
  };
}

// --------------------------------------------------------------------------
// Catalogue integrity
// --------------------------------------------------------------------------

Deno.test("her kural katalogda karşılığı olan bir kayda bağlı", () => {
  for (const rule of TRAINING_RULES) {
    assert(TRAINING_CATALOG[rule.entry], `katalogda yok: ${rule.entry}`);
  }
});

Deno.test("katalogdaki her kayıt en fazla beş konu sıralar", () => {
  for (const entry of Object.values(TRAINING_CATALOG)) {
    assert(entry.topics.length <= 5, entry.code);
  }
});

// --------------------------------------------------------------------------
// Equipment resolution
// --------------------------------------------------------------------------

Deno.test("ekipman ailesi varlık kodundan çözülür", () => {
  assertEquals(equipmentFamilyOf("forklift_01"), "forklift");
  assertEquals(equipmentFamilyOf("crane_01"), "crane");
  assertEquals(equipmentFamilyOf("scaffolding_01"), "scaffold");
  assertEquals(equipmentFamilyOf("tank_02"), "tank");
});

Deno.test("tanınmayan varlık kodu ekipman önerisi üretmez", () => {
  // Yaklaşık eşleşmeyle forklift yetkisi önermek, bu kataloğun önlemek için
  // var olduğu hatanın ta kendisi.
  assertEquals(equipmentFamilyOf("mixer_01"), null);
  assertEquals(equipmentFamilyOf(null), null);
  const cards = trainingRecommendationsFor({
    sectorId: "manufacturing",
    rows: [item({ id: "F1", mechanism: null, asset: "mixer_01" })],
  });
  assertEquals(cards.some((card) => card.catalogCode.startsWith("TRN-OPR")), false);
});

// --------------------------------------------------------------------------
// Mood
// --------------------------------------------------------------------------

Deno.test("kişi görünüyorsa doğrudan dil kullanılır", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [item({ id: "F1", mechanism: "fall_from_height", people: 4 })],
  });
  const card = cards.find((entry) => entry.catalogCode === "TRN-WAH-001");
  assert(card);
  assertStringIncludes(card!.text, "görev yapan personele");
});

Deno.test("yalnız ekipman görünüyorsa koşullu dil kullanılır", () => {
  // Fotoğraf kimsenin forklifti kullandığını göstermiyor; "kullanan personel"
  // demek bir kişi hakkında iddia olurdu.
  const cards = trainingRecommendationsFor({
    sectorId: "logistics",
    rows: [item({ id: "F1", mechanism: null, asset: "forklift_01" })],
  });
  const card = cards.find((entry) => entry.catalogCode === "TRN-OPR-FORKLIFT");
  assert(card);
  assertStringIncludes(card!.text, "kullanacak personelin");
  assertStringIncludes(card!.text, "operatörlük yetkisini taşıması");
});

Deno.test("özel görev eğitimi görevlendirme koşuluna bağlı kalır", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [item({ id: "F1", mechanism: "fall_from_height", people: 4 })],
  });
  const rescue = cards.find((entry) => entry.catalogCode === "TRN-EMR-008");
  assert(rescue);
  assertStringIncludes(rescue!.text, "görevlendirilecek personele");
});

// --------------------------------------------------------------------------
// Regulated credentials
// --------------------------------------------------------------------------

Deno.test("MYK bir kurs gibi sunulmaz", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [item({ id: "F1", mechanism: null, asset: "scaffolding_01" })],
  });
  const card = cards.find((entry) => entry.catalogCode === "TRN-QUA-SCAFFOLD");
  assert(card);
  assertStringIncludes(card!.text, "doğrulanması önerilir");
  assertEquals(/kurs/iu.test(card!.text), false);
});

Deno.test("alçak gerilim panosu özel yetki iddiası üretmez", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "manufacturing",
    rows: [item({
      id: "F1",
      module: "electrical",
      mechanism: "electrical_contact_arc",
      asset: "cable_01",
    })],
  });
  const card = cards.find((entry) => entry.catalogCode === "TRN-ELE-001");
  assert(card);
  // Yüksek gerilim koşulu ayrı cümlede ve koşullu; doğrudan belge adı yok.
  assertStringIncludes(card!.text, "Yüksek gerilim tesisinde çalışma söz konusuysa");
  assertEquals(/ekat/iu.test(card!.text), false);
});

// --------------------------------------------------------------------------
// Merging and ordering
// --------------------------------------------------------------------------

Deno.test("aynı kazanım iki bulgudan gelse tek kart olur", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [
      item({ id: "F1", mechanism: "fall_from_height", people: 2 }),
      item({
        id: "F2",
        module: "work_at_height",
        mechanism: "fall_from_height",
        topic: "working_at_height_access",
        people: 2,
      }),
    ],
  });
  const height = cards.filter((entry) => entry.catalogCode === "TRN-WAH-001");
  assertEquals(height.length, 1);
  assertEquals(height[0].sourceItemIds, ["F1", "F2"]);
});

Deno.test("sahada görülene dayanan kartlar temel eğitimlerin üstünde", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [item({ id: "F1", mechanism: "fall_from_height", people: 4 })],
  });
  const height = cards.findIndex((entry) => entry.catalogCode === "TRN-WAH-001");
  const baseline = cards.findIndex((entry) => entry.catalogCode === "TRN-GEN-002");
  assert(height >= 0 && baseline >= 0);
  assert(height < baseline, "tehlikeye dayalı kart temel eğitimin altında kalmış");
});

Deno.test("temel eğitim analiz başına bir kez üretilir", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [
      item({ id: "F1", mechanism: "fall_from_height" }),
      item({ id: "F2", mechanism: "sharp_edge_contact" }),
      item({ id: "F3", mechanism: "fall_same_level" }),
    ],
  });
  assertEquals(
    cards.filter((entry) => entry.catalogCode === "TRN-GEN-002").length,
    1,
  );
});

// --------------------------------------------------------------------------
// Source and output discipline
// --------------------------------------------------------------------------

Deno.test("kanonik kod taşımayan analiz öneri üretmez", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [{ public_finding_id: "F1", internal_priority: { route_reason: "x" } }],
  });
  assertEquals(cards.length, 0);
});

Deno.test("aynı girdi aynı çıktıyı üretir", () => {
  const rows = [
    item({ id: "F1", mechanism: "fall_from_height", people: 3 }),
    item({ id: "F2", mechanism: null, asset: "crane_01" }),
  ];
  const first = trainingRecommendationsFor({ sectorId: "construction", rows });
  const second = trainingRecommendationsFor({ sectorId: "construction", rows });
  assertEquals(JSON.stringify(first), JSON.stringify(second));
});

Deno.test("üretilen her metin linter'dan geçer", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [
      item({ id: "F1", mechanism: "fall_from_height", people: 4 }),
      item({ id: "F2", mechanism: "caught_in_pinch_shear", people: 4 }),
      item({ id: "F3", mechanism: "electrical_contact_arc" }),
      item({ id: "F4", mechanism: "sharp_edge_contact", people: 4 }),
      item({ id: "F5", mechanism: null, asset: "crane_01" }),
      item({ id: "F6", mechanism: null, asset: "forklift_01" }),
      item({ id: "F7", mechanism: null, asset: "scaffolding_01" }),
      item({ id: "F8", mechanism: null, topic: "process_containment_integrity" }),
    ],
  });
  assert(cards.length >= 8, `yalnız ${cards.length} kart üretildi`);
  for (const card of cards) {
    assertEquals(lintTrainingText(card.text), [], card.text);
    assert(card.text.length > 0);
    assert(card.title.length <= 90, card.title);
  }
});

Deno.test("hiçbir metin kişisel eksiklik, skor veya termin taşımaz", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [
      item({ id: "F1", mechanism: "fall_from_height", people: 4 }),
      item({ id: "F2", mechanism: null, asset: "forklift_01" }),
      item({ id: "F3", mechanism: null, asset: "scaffolding_01" }),
    ],
  });
  for (const card of cards) {
    assertEquals(
      /belgesi yok|eğitimsiz|yetkisiz|zorunludur|termin|sorumlu birim|risk skoru/iu
        .test(card.text),
      false,
      card.text,
    );
  }
});

// --------------------------------------------------------------------------
// Linter
// --------------------------------------------------------------------------

Deno.test("konu listesi çift bağlaç üretmez", () => {
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [
      item({ id: "F1", mechanism: "fall_same_level", people: 2 }),
      item({ id: "F2", mechanism: "fall_from_height", people: 2 }),
      item({ id: "F3", mechanism: "chemical_contact_release", people: 2 }),
    ],
  });
  for (const card of cards) {
    assertEquals(/ ve [^,.]* ve /u.test(card.text), false, card.text);
  }
});

Deno.test("cümlede fiil tekrarı olmaz", () => {
  // "görevlendirilecek görev yapacak personele" gibi çift fiil, bağlam
  // metninin şablonla çakışmasından çıkıyordu.
  const cards = trainingRecommendationsFor({
    sectorId: "construction",
    rows: [item({ id: "F1", mechanism: "fall_from_height" })],
  });
  for (const card of cards) {
    assertEquals(/görevlendirilecek görev/u.test(card.text), false, card.text);
    assertEquals(/personele[;,]? .*personele/u.test(card.text), false, card.text);
  }
});

Deno.test("linter kişisel eksiklik iddiasını yakalar", () => {
  const findings = lintTrainingText(
    "Fotoğraftaki forklift operatörünün belgesi yoktur; eğitim verilmesi önerilir.",
  );
  assert(findings.some((entry) => entry.rule === "personal_deficiency_claimed"));
});

Deno.test("linter MYK'yı kurs gibi sunan metni yakalar", () => {
  const findings = lintTrainingText(
    "İskele kurucularının MYK kursuna katılması önerilir.",
  );
  assert(findings.some((entry) => entry.rule === "myk_as_course"));
});

Deno.test("linter zorunluluk dilini yakalar", () => {
  const findings = lintTrainingText(
    "Tank görüldüğü için SRC-5 belgesi zorunludur ve alınması önerilir.",
  );
  assert(findings.some((entry) => entry.rule === "obligation_asserted"));
});

Deno.test("linter içeriksiz öneriyi yakalar", () => {
  const findings = lintTrainingText("Çalışanlara ISG eğitimi verilsin önerilir.");
  assert(findings.some((entry) => entry.rule === "contentless_recommendation"));
});

Deno.test("linter termin ve sorumlu ifadesini yakalar", () => {
  const findings = lintTrainingText(
    "Eğitimin 7 gün içinde tamamlanması önerilir.",
  );
  assert(findings.some((entry) => entry.rule === "deadline_or_assignment"));
});

// --------------------------------------------------------------------------
// Statutory durations
// --------------------------------------------------------------------------

function generalOHS(hazardClass?: "low" | "medium" | "high" | null) {
  const cards = trainingRecommendationsFor({
    sectorId: null,
    hazardClass: hazardClass ?? null,
    rows: [item({ id: "f1" })],
  });
  return cards.find((card) => card.catalogCode === "TRN-GEN-002");
}

Deno.test("temel İSG eğitimi bilinen tehlike sınıfında tek satır süre verir", () => {
  const high = generalOHS("high");
  assertEquals(high?.duration?.value, "Çok tehlikeli sınıf · en az 16 saat");
  assertEquals(high?.duration?.note, "Yenileme: yılda bir");

  const medium = generalOHS("medium");
  assertEquals(medium?.duration?.value, "Tehlikeli sınıf · en az 12 saat");
  assertEquals(medium?.duration?.note, "Yenileme: iki yılda bir");

  const low = generalOHS("low");
  assertEquals(low?.duration?.value, "Az tehlikeli sınıf · en az 8 saat");
  assertEquals(low?.duration?.note, "Yenileme: üç yılda bir");
});

Deno.test("tehlike sınıfı bilinmiyorsa üç sınıf da yazılır, biri seçilmez", () => {
  const card = generalOHS(null);
  assertEquals(
    card?.duration?.value,
    "Az tehlikeli 8 · Tehlikeli 12 · Çok tehlikeli 16 saat",
  );
  assertStringIncludes(card?.duration?.note ?? "", "sırasıyla");
});

Deno.test("işbaşı eğitimi sınıftan bağımsız iki saatlik asgari süre taşır", () => {
  for (const hazardClass of ["low", "high", null] as const) {
    const card = trainingRecommendationsFor({
      sectorId: null,
      hazardClass,
      rows: [item({ id: "f1" })],
    }).find((entry) => entry.catalogCode === "TRN-GEN-001");
    assertEquals(card?.duration?.value, "En az 2 saat");
    assertEquals(card?.duration?.note, "İşe başlamadan önce");
  }
});

Deno.test("mevzuatın süre bağlamadığı eğitimlerde saat uydurulmaz", () => {
  const cards = trainingRecommendationsFor({
    sectorId: null,
    hazardClass: "high",
    rows: [item({ id: "f1", people: 2, asset: "seyyar merdiven" })],
  });
  const withoutStatute = cards.filter((card) =>
    !["TRN-GEN-001", "TRN-GEN-002"].includes(card.catalogCode)
  );
  assert(withoutStatute.length > 0, "karşılaştıracak kart yok");
  for (const card of withoutStatute) {
    assertEquals(card.duration, null, card.catalogCode);
  }
});

Deno.test("süre metne sızmaz; cümlelerde saat geçmez", () => {
  const cards = trainingRecommendationsFor({
    sectorId: null,
    hazardClass: "high",
    rows: [item({ id: "f1", people: 1 })],
  });
  for (const card of cards) {
    assert(
      !/\d+\s*saat/u.test(card.text),
      `${card.catalogCode} metninde süre var: ${card.text}`,
    );
  }
});

Deno.test("yalnızca iki kayıt yasal süre taşır", () => {
  const withDuration = Object.values(TRAINING_CATALOG)
    .filter((entry) => entry.statutoryDuration)
    .map((entry) => entry.code)
    .sort();
  assertEquals(withDuration, ["TRN-GEN-001", "TRN-GEN-002"]);
});
