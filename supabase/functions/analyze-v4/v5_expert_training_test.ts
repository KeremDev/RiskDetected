import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { parseV5Output, routeV5Findings } from "./v5-engine.ts";
import { V5_RESPONSE_SCHEMA } from "./v5-contracts.ts";
import {
  EXPERT_ASSET_FAMILIES,
  V5_LAYER_BOOK_CODES,
} from "./v5-taxonomy.ts";
import {
  EXPERT_REGISTRY,
  expertRecommendationsFor,
} from "../_shared/expert-recommendations/index.ts";
import {
  type TrainingItemRow,
  trainingRecommendationsFor,
} from "../_shared/training-recommendations/index.ts";

function finding(overrides: Record<string, unknown> = {}) {
  return {
    finding_key: "f1",
    layers: [3],
    title: "Tank üzerinde korkuluksuz çalışma.",
    category: "Yüksekte çalışma",
    description: "İşçi kavisli tank yüzeyinde korkuluk olmadan kaynak yapıyor.",
    event_path: "Kavisli yüzey → kayarak düşme → ölüm.",
    root_cause: "Toplu koruma kurulmamış.",
    regulatory_references: ["Mevzuat — 6331 sayılı Kanun."],
    fine_kinney: {
      "olasılık": 6,
      frekans: 6,
      "şiddet": 40,
      "gerekçe": "İşçi yüzeyde duruyor.",
    },
    immediate_control: "Tank üzerindeki çalışmayı durdurun.",
    corrective_steps: ["Sepetli platform kullanın.", "Erişimi kapatın."],
    preventive_measure: "Yüksekte çalışma iznini zorunlu kılın.",
    training_recommendation: "",
    ppe_recommendation: "",
    confidence: 0.9,
    needs_field_verification: false,
    ...overrides,
  };
}

function envelope(params: {
  findings: unknown[];
  assets?: string[];
  scan?: Array<Record<string, unknown>>;
}) {
  return JSON.stringify({
    scene_summary: "Atölyede tank üzerinde kaynak yapılıyor.",
    layer_scan: params.scan ?? [
      { layer: 1, result: "tehlike_var", note: "İşçi güvensiz duruşta." },
      { layer: 3, result: "tehlike_var", note: "Korkuluksuz yüzey." },
    ],
    observed_assets: params.assets ?? [],
    positive_controls: [],
    findings: params.findings,
  });
}

const RECORDS_FINDING = finding({
  finding_key: "records_lifting",
  layers: [19],
  title: "Kaldırma ekipmanları için periyodik kontrol doğrulaması.",
  category: "Periyodik Kontroller",
  description: "Vinç ve rotatorların periyodik kontrol kaydı doğrulanmalıdır.",
  immediate_control: "Periyodik kontrol raporunu yetkili kişiyle doğrulayın.",
  fine_kinney: {
    "olasılık": 1,
    frekans: 2,
    "şiddet": 15,
    "gerekçe": "Kayıt görünmüyor.",
  },
});

// --------------------------------------------------------------------------
// The registry: every sentence is written here, none of it by the model
// --------------------------------------------------------------------------

Deno.test("kayıt defterindeki her aile kapalı listede yer alır", () => {
  for (const [key, entry] of Object.entries(EXPERT_REGISTRY)) {
    assertEquals(key, entry.family);
    assert(
      (EXPERT_ASSET_FAMILIES as readonly string[]).includes(entry.family),
      `${entry.family} kapalı listede yok`,
    );
  }
});

Deno.test("uzman kartı gözlem, gereklilik ve dayanak taşır", () => {
  const built = expertRecommendationsFor(["storage_tank"]);
  assertEquals(built.recommendations.length, 1);
  const card = built.recommendations[0];
  // The number is the point: a registry chose it, not a language model.
  assertStringIncludes(card.text, "API 653");
  assertStringIncludes(card.text, "kalınlık");
  assertStringIncludes(card.references, "API 653");
  // One reference per line, so an article never attaches to the wrong source.
  assert(card.references.split("\n").length >= 2);
  assertStringIncludes(card.action, "inceleyin");
  assertStringIncludes(card.ifAbsent, "yaptırın");
});

Deno.test("her kayıt cümlesi noktayla biter ve boş kalmaz", () => {
  const built = expertRecommendationsFor(Object.keys(EXPERT_REGISTRY));
  assertEquals(built.recommendations.length, Object.keys(EXPERT_REGISTRY).length);
  for (const card of built.recommendations) {
    assert(card.title.length > 8, card.family);
    assert(card.text.length > 120, card.family);
    for (const line of card.references.split("\n")) {
      assert(line.trim().endsWith("."), `${card.family}: ${line}`);
    }
    assert(card.action.endsWith("."), card.family);
    assert(card.ifAbsent.endsWith("."), card.family);
    assert(card.ongoing.endsWith("."), card.family);
  }
});

// --------------------------------------------------------------------------
// bc85eccd -- the notebook was showing 345-511 character paragraphs where a
// one-line record request belonged
// --------------------------------------------------------------------------

Deno.test("her kayıt kendi defter cümlesini taşır, uzman paragrafından kesilmez", () => {
  const built = expertRecommendationsFor(Object.keys(EXPERT_REGISTRY));
  for (const card of built.recommendations) {
    assert(card.notebookTespit.endsWith("."), card.family);
    assert(card.notebookOneri.endsWith("."), card.family);
    // A log line, not a slice of the specialist paragraph: short enough to
    // read as one sentence, and not a truncated fragment of `text`.
    assert(
      card.notebookTespit.length < 170,
      `${card.family}: ${card.notebookTespit.length} karakter`,
    );
    assert(
      card.notebookOneri.length < 170,
      `${card.family}: ${card.notebookOneri.length} karakter`,
    );
    assert(!card.text.startsWith(card.notebookTespit), card.family);
  }
});

// --------------------------------------------------------------------------
// The operator: "emir kipinden ziyade önerilmektedir yazılması daha
// mantıklı ... daha çok önerilmektedir, tavsiye edilmektedir tarzında
// bitmesi daha uygun olacaktır"
// --------------------------------------------------------------------------

const IMPERATIVE_VERB_ENDING = /(?:in|ın|ün|un|yin|yın|yün|yun)\.$/u;
const ADVISORY_ENDING = /(?:önerilmektedir|tavsiye edilmektedir|gerekmektedir)\.$/u;

Deno.test("kayıt defteri önerisi tavsiye kipinde biter, emir kipinde değil", () => {
  const built = expertRecommendationsFor(Object.keys(EXPERT_REGISTRY));
  for (const card of built.recommendations) {
    assert(
      ADVISORY_ENDING.test(card.notebookOneri),
      `${card.family}: "${card.notebookOneri}"`,
    );
    assert(
      !IMPERATIVE_VERB_ENDING.test(card.notebookOneri),
      `${card.family}: "${card.notebookOneri}"`,
    );
  }
});

Deno.test("kayıt defterinde karşılığı olmayan aile uydurulmaz, sayılır", () => {
  // All 22 EXPERT_ASSET_FAMILIES now have a registry entry; this exercises the
  // missing-entry path with a family the registry has never heard of, which is
  // what happens the day a 23rd family is added to the enum before its card is
  // written.
  const built = expertRecommendationsFor([
    "storage_tank",
    "unmapped_future_family",
    "storage_tank",
  ]);
  assertEquals(built.recommendations.length, 1);
  assertEquals(built.familiesWithoutEntry, ["unmapped_future_family"]);
});

Deno.test("kapalı listedeki 22 ailenin tamamı kayıt defterinde", () => {
  for (const family of EXPERT_ASSET_FAMILIES) {
    assert(EXPERT_REGISTRY[family], `${family} için kayıt yok`);
  }
  assertEquals(
    Object.keys(EXPERT_REGISTRY).length,
    EXPERT_ASSET_FAMILIES.length,
  );
});

// --------------------------------------------------------------------------
// The model supplies the family code and nothing else
// --------------------------------------------------------------------------

Deno.test("şema ekipman ailelerini kapalı listeyle dayatır", () => {
  const schema = V5_RESPONSE_SCHEMA as unknown as Record<string, any>;
  assertEquals(
    schema.properties.observed_assets.items.enum.length,
    EXPERT_ASSET_FAMILIES.length,
  );
  assert(schema.required.includes("observed_assets"));
});

Deno.test("listede olmayan ekipman kodu ayrıştırmada düşer", () => {
  const output = parseV5Output(
    envelope({
      findings: [finding()],
      assets: ["storage_tank", "uzay_gemisi", "electrical_panel"],
    }),
  );
  assertEquals(output.observed_assets, ["storage_tank", "electrical_panel"]);
});

Deno.test("uzman kartları puanlanmaz ve toplam skoru şişirmez", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(
      envelope({ findings: [finding()], assets: ["overhead_crane"] }),
    ),
  }]);
  const cards = routed.items.filter((item) =>
    item.item_class === "assurance_requirement"
  );
  assertEquals(cards.length, 1);
  assertEquals(cards[0].is_scored, false);
  assertEquals(cards[0].fk_severity ?? null, null);
  assertEquals(cards[0].needs_field_verification, true);
  assertEquals(cards[0].internal_priority.control_source, "registry");
  assertEquals(routed.expertCardCount, 1);
  // The notebook reads these two fields directly off internal_priority; if
  // routing stops carrying them the log book silently falls back to the
  // generic template and the full specialist paragraph again.
  assertStringIncludes(
    String(cards[0].internal_priority.notebook_tespit),
    "köprülü vinç",
  );
  assert(String(cards[0].internal_priority.notebook_oneri).endsWith("."));
});

// --------------------------------------------------------------------------
// 1f6c5ea2 -- a paperwork check was published with a Fine-Kinney score of 30
// --------------------------------------------------------------------------

Deno.test("yalnız 19. katmanı karşılayan bulgu puanlanmaz", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope({ findings: [RECORDS_FINDING] })),
  }]);
  assertEquals(routed.items.length, 1);
  const item = routed.items[0];
  assertEquals(item.item_class, "assurance_requirement");
  assertEquals(item.is_scored, false);
  assertEquals(item.fk_severity ?? null, null);
});

Deno.test("19. katmanı fiziksel katmanla paylaşan bulgu puanlı kalır", () => {
  // The safe direction: a finding that mixes the records layer with a physical
  // one is still a hazard, and demoting it would delete it from the score.
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(
      envelope({ findings: [finding({ layers: [7, 19] })] }),
    ),
  }]);
  assertEquals(routed.items[0].item_class, "observed_finding");
  assertEquals(routed.items[0].is_scored, true);
});

Deno.test("kayıt defteri konuştuğunda modelin genel kayıt bulgusu düşer", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(
      envelope({
        findings: [finding(), RECORDS_FINDING],
        assets: ["overhead_crane"],
      }),
    ),
  }]);
  assertEquals(routed.recordsFindingsSuperseded, ["records_lifting"]);
  const assurance = routed.items.filter((item) =>
    item.item_class === "assurance_requirement"
  );
  assertEquals(assurance.length, 1);
  assertStringIncludes(assurance[0].title, "Köprülü Vinç");
});

Deno.test("kayıt defteri suskunsa modelin kayıt bulgusu yayımlanır", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(
      envelope({ findings: [finding(), RECORDS_FINDING], assets: [] }),
    ),
  }]);
  assertEquals(routed.recordsFindingsSuperseded, []);
  const assurance = routed.items.filter((item) =>
    item.item_class === "assurance_requirement"
  );
  assertEquals(assurance.length, 1);
  assertStringIncludes(assurance[0].title, "periyodik kontrol");
});

// --------------------------------------------------------------------------
// The training catalogue was not empty, it was starved
// --------------------------------------------------------------------------

Deno.test("her katman geçerli bir kitap koduna eşlenir", () => {
  for (let layer = 1; layer <= 18; layer += 1) {
    const codes = V5_LAYER_BOOK_CODES[layer];
    assert(codes, `${layer}. katmanın eşlemesi yok`);
    assert(codes.moduleID.length > 0);
  }
  // Layer 19 asks about a record, which teaches nobody anything.
  assertEquals(V5_LAYER_BOOK_CODES[19], undefined);
});

// --------------------------------------------------------------------------
// The operator's revision -- three layers the catalogue had no card for
// --------------------------------------------------------------------------

Deno.test("katman 15/16/17 kendi mekanizma kodunu taşır, katman 10'u paylaşmaz", () => {
  assertEquals(
    V5_LAYER_BOOK_CODES[15].mechanismCode,
    "confined_space_atmosphere_entrapment",
  );
  assertEquals(
    V5_LAYER_BOOK_CODES[16].mechanismCode,
    "noise_vibration_dust_exposure",
  );
  assertEquals(
    V5_LAYER_BOOK_CODES[17].mechanismCode,
    "manual_handling_overexertion",
  );
  // 10 and 16 used to share chemical_contact_release, which meant a dust or
  // noise hazard could fire the chemical-spill training card instead of its
  // own, or nothing at all.
  assert(
    V5_LAYER_BOOK_CODES[16].mechanismCode !==
      V5_LAYER_BOOK_CODES[10].mechanismCode,
  );
});

Deno.test("kapalı alan, gürültü-titreşim-toz ve elle taşıma katmanları artık eğitim kartı üretir", () => {
  for (
    const [layer, expectedCode] of [
      [15, "TRN-CFS-001"],
      [16, "TRN-HYG-001"],
      [17, "TRN-ERG-001"],
    ] as const
  ) {
    const routed = routeV5Findings([{
      photoIndex: 1,
      output: parseV5Output(
        envelope({
          findings: [finding({ finding_key: `layer-${layer}`, layers: [layer] })],
          scan: [{ layer: 1, result: "tehlike_var", note: "İşçi görülüyor." }, {
            layer,
            result: "tehlike_var",
            note: "Tehlike var.",
          }],
        }),
      ),
    }]);
    const rows = routed.items.map((item) => ({
      public_finding_id: item.id,
      internal_priority: item.internal_priority,
    })) as TrainingItemRow[];
    const cards = trainingRecommendationsFor({
      sectorId: null,
      hazardClass: null,
      rows,
    });
    const codes = cards.map((card) => card.catalogCode);
    assert(
      codes.includes(expectedCode),
      `katman ${layer}: beklenen ${expectedCode}, gelen ${codes.join(", ")}`,
    );
  }
});

Deno.test("bulgular eğitim motoruna kanonik kod taşır", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope({ findings: [finding()] })),
  }]);
  const book = routed.items[0].internal_priority.book_source as Record<
    string,
    unknown
  >;
  assertEquals(book.schema, "book-source-v1");
  assertEquals(book.module_id, "work_at_height");
  assertEquals(book.mechanism_code, "fall_from_height");
  assertEquals(book.assurance_topic_id, "working_at_height_access");
  // Layer 1 said a person is in the hazard line, which is what turns a card
  // from conditional phrasing into direct phrasing.
  assertEquals(book.people_visible, 1);
});

Deno.test("serbest motorun bulguları eğitim kartı üretir", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope({ findings: [finding()] })),
  }]);
  const rows = routed.items.map((item) => ({
    public_finding_id: item.id,
    internal_priority: item.internal_priority,
  })) as TrainingItemRow[];
  const cards = trainingRecommendationsFor({
    sectorId: "manufacturing",
    hazardClass: "high",
    rows,
  });
  // Before the book_source block existed this list was empty for every
  // analysis, and the three `always: true` cards never reached a reader
  // because the early return sat in front of them.
  assert(cards.length >= 4, `beklenen >=4, gelen ${cards.length}`);
  const codes = cards.map((card) => card.catalogCode);
  assert(codes.includes("TRN-GEN-002"), codes.join(", "));
  assert(codes.includes("TRN-WAH-001"), codes.join(", "));
});
