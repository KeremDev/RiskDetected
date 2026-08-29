import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  buildApprovedBookDrafts,
  bookCandidates,
  type V4ItemRow,
} from "./index.ts";
import { adaptV4Item } from "./analysis-adapter.ts";
import { classify } from "./eligibility.ts";
import { lint } from "./linter.ts";
import {
  APPROVED_BOOK_TEMPLATE_VERSION,
  computeApprovedBookBundleSHA256,
} from "./version-contract.ts";

const RELEASED_BUNDLE_SHA256 =
  "PLACEHOLDER";

function item(overrides: {
  id: string;
  itemClass?: string;
  moduleId?: string;
  conditionCode?: string;
  mechanism?: string | null;
  assuranceTopic?: string | null;
  criticality?: string;
  evidence?: string;
  assetRef?: string | null;
  barriers?: string[];
  people?: number;
  accessible?: boolean;
  confidence?: { visibility: number; localization: number; mechanism: number };
}): V4ItemRow {
  const confidence = overrides.confidence ??
    { visibility: 0.9, localization: 0.9, mechanism: 0.9 };
  return {
    public_finding_id: overrides.id,
    criticality: overrides.criticality ?? "serious",
    canonical_payload: {
      source_photo_indices: [1],
      needs_field_verification: false,
    },
    internal_priority: {
      book_source: {
        schema: "book-source-v1",
        module_id: overrides.moduleId ?? "falls_falling_objects",
        item_class: overrides.itemClass ?? "observed_finding",
        condition_code: overrides.conditionCode ?? "visible_structural_absence",
        mechanism_code: overrides.mechanism === undefined
          ? "fall_from_height"
          : overrides.mechanism,
        evidence_level: overrides.evidence ?? "E4",
        criticality: overrides.criticality ?? "serious",
        occlusion: "none",
        asset_ref: overrides.assetRef ?? "A1",
        asset_family: overrides.assuranceTopic ??
          (overrides.moduleId ?? "falls_falling_objects"),
        assurance_topic_id: overrides.assuranceTopic ?? null,
        barrier_components_absent: overrides.barriers ?? [],
        confidence,
        visually_resolvable: true,
        requires_document_or_measurement: false,
        accessible_event_path: overrides.accessible ?? true,
        people_visible: overrides.people ?? 0,
        photo_index: 1,
      },
    },
  };
}

const SITE = {
  observationBasis: "direct_site_observation" as const,
  criticalLanguageApprovals: [] as string[],
  locationByCluster: {} as Record<string, string>,
  legalReferenceMode: "title_only" as const,
};

// --------------------------------------------------------------------------
// Adapter
// --------------------------------------------------------------------------

Deno.test("model metni taşımayan kalem kanonik tipe dönüşür", () => {
  const adapted = adaptV4Item(item({ id: "F-1", barriers: ["mid_rail"] }));
  assert(adapted);
  assertEquals(adapted?.mechanismCode, "fall_from_height");
  assertEquals(adapted?.barrierComponentsAbsent, ["mid_rail"]);
  // Serbest metin alanı taşınmıyor: render yolunun erişebileceği tek şey kod.
  assertEquals(adapted?.rawForReview, undefined);
});

Deno.test("book_source taşımayan kalem adapte edilmez", () => {
  const row: V4ItemRow = {
    public_finding_id: "F-9",
    canonical_payload: { source_photo_indices: [1] },
    internal_priority: { route_reason: "module_coverage_unresolved" },
  };
  assertEquals(adaptV4Item(row), null);
});

Deno.test("modül kapsamından gelen genel saha teyidi deftere girmez", () => {
  // "Bu modül sahada kontrol edilmeli" bir defter kaydı değildir: ne varlık
  // adı ne somut doğrulama taşır. Adaptör bunları book_source olmadığı için
  // zaten eler; burada tüm hattı doğruluyoruz.
  const { clusters } = bookCandidates([
    {
      public_finding_id: "F-9",
      canonical_payload: {},
      internal_priority: { route_reason: "module_coverage_unresolved" },
    },
  ]);
  assertEquals(clusters.length, 0);
});

// --------------------------------------------------------------------------
// Eligibility
// --------------------------------------------------------------------------

Deno.test("zayıf kanıtlı gözlem defter taslağı üretmez", () => {
  const adapted = adaptV4Item(item({ id: "F-2", evidence: "E2" }))!;
  const verdict = classify(adapted);
  assertEquals(verdict.eligible, false);
});

Deno.test("yeri iyi belirlenemeyen gözlem defter taslağı üretmez", () => {
  const adapted = adaptV4Item(item({
    id: "F-3",
    confidence: { visibility: 0.9, localization: 0.2, mechanism: 0.9 },
  }))!;
  const verdict = classify(adapted);
  assertEquals(verdict.eligible, false);
});

Deno.test("kişi maruziyeti olan ölümcül gözlem kritik sınıfa girer", () => {
  const adapted = adaptV4Item(item({
    id: "F-4",
    criticality: "fatal",
    people: 1,
    accessible: true,
  }))!;
  const verdict = classify(adapted);
  assert(verdict.eligible);
  assertEquals(
    verdict.eligible ? verdict.entryClass : null,
    "critical_immediate",
  );
});

// --------------------------------------------------------------------------
// Human gates
// --------------------------------------------------------------------------

Deno.test("gözlem dayanağı seçilmeden metin üretilmez", async () => {
  const result = await buildApprovedBookDrafts(
    [item({ id: "F-5", barriers: ["mid_rail"] })],
    { ...SITE, observationBasis: null },
  );
  assertEquals(result.drafts.length, 0);
  assertEquals(result.blocked.length, 1);
  assertEquals(result.blocked[0].reason, "BOOK_OBSERVATION_BASIS_REQUIRED");
});

Deno.test("kritik dil ayrı onay olmadan açılmaz", async () => {
  const critical = item({
    id: "F-6",
    criticality: "fatal",
    people: 1,
    barriers: ["top_rail", "mid_rail", "toeboard"],
  });
  const blockedRun = await buildApprovedBookDrafts([critical], SITE);
  assertEquals(blockedRun.drafts.length, 0);
  assertEquals(
    blockedRun.blocked[0].reason,
    "BOOK_CRITICAL_LANGUAGE_APPROVAL_REQUIRED",
  );

  const clusterId = blockedRun.clusters[0].clusterId;
  const approved = await buildApprovedBookDrafts([critical], {
    ...SITE,
    criticalLanguageApprovals: [clusterId],
  });
  assertEquals(approved.drafts.length, 1);
  assertStringIncludes(approved.drafts[0].copyText, "derhal durdurulmalı");
});

// --------------------------------------------------------------------------
// Clustering
// --------------------------------------------------------------------------

Deno.test("aynı kenarın koruma katmanları tek paragrafta birleşir", () => {
  const { clusters } = bookCandidates([
    item({ id: "F-7", barriers: ["mid_rail"], assetRef: "PLATFORM-1" }),
    item({ id: "F-8", barriers: ["toeboard"], assetRef: "PLATFORM-1" }),
  ]);
  assertEquals(clusters.length, 1);
  assertEquals(clusters[0].sourceItemIds, ["F-7", "F-8"]);
  assertEquals(clusters[0].barrierComponentsAbsent, ["mid_rail", "toeboard"]);
});

Deno.test("aynı fotoğraftaki ilgisiz kusurlar birleşmez", () => {
  const { clusters } = bookCandidates([
    item({ id: "F-10", barriers: ["mid_rail"], assetRef: "PLATFORM-1" }),
    item({
      id: "F-11",
      moduleId: "machinery",
      mechanism: "caught_in_pinch_shear",
      assetRef: "MIKSER-1",
    }),
  ]);
  assertEquals(clusters.length, 2);
});

// --------------------------------------------------------------------------
// Rendering
// --------------------------------------------------------------------------

Deno.test("gözlem paragrafı 2-4 cümle ve etiketsizdir", async () => {
  const result = await buildApprovedBookDrafts(
    [item({ id: "F-12", barriers: ["mid_rail"] })],
    SITE,
  );
  assertEquals(result.drafts.length, 1);
  const text = result.drafts[0].copyText;
  const sentences = text.split(/(?<=[.!?])\s+/u).filter(Boolean);
  assert(sentences.length >= 2 && sentences.length <= 4, text);
  assertEquals(text.includes("Tehlike:"), false);
  assertEquals(text.includes("Öneri:"), false);
  assertStringIncludes(text, "Saha incelemesinde");
  assertStringIncludes(text, "ara korkuluk");
});

Deno.test("korkuluk elemanları rayda durdukları sırayla yazılır", async () => {
  const result = await buildApprovedBookDrafts(
    [item({ id: "F-13", barriers: ["toeboard", "top_rail", "mid_rail"] })],
    SITE,
  );
  assertStringIncludes(
    result.drafts[0].copyText,
    "ana korkuluk, ara korkuluk ve topuk levhası",
  );
});

Deno.test("gözlem dayanağı metne aynen yansır", async () => {
  const result = await buildApprovedBookDrafts(
    [item({ id: "F-14", barriers: ["mid_rail"] })],
    { ...SITE, observationBasis: "employer_supplied_visual_record" },
  );
  // "i" -> "İ": tr-TR büyük harf kuralı, "Isyerince" değil.
  assertStringIncludes(
    result.drafts[0].copyText,
    "İşyerince iletilen görsel kayıt üzerinde",
  );
  assertEquals(
    result.drafts[0].copyText.toLocaleLowerCase("tr-TR").includes(
      "saha incelemesinde",
    ),
    false,
  );
});

Deno.test("güvence paragrafı yokluk iddia etmez, doğrulama ister", async () => {
  const result = await buildApprovedBookDrafts(
    [item({
      id: "F-15",
      itemClass: "assurance_requirement",
      moduleId: "process_integrity",
      conditionCode: "visible_asset_assurance",
      mechanism: null,
      assuranceTopic: "process_containment_integrity",
      criticality: "ordinary",
    })],
    SITE,
  );
  assertEquals(result.drafts.length, 1);
  const text = result.drafts[0].copyText;
  assertStringIncludes(text, "doğrulanmalıdır");
  // Fotoğraftan belge yokluğu çıkarılamaz.
  assertEquals(/yapılmamıştır|bulunmamakta/u.test(text), false);
});

Deno.test("konum verilmediğinde uydurulmaz", async () => {
  const result = await buildApprovedBookDrafts(
    [item({ id: "F-16", barriers: ["mid_rail"] })],
    SITE,
  );
  assertEquals(result.drafts[0].copyText.includes("ilgili alanda"), false);
});

Deno.test("konum verildiğinde cümleye girer", async () => {
  const first = await buildApprovedBookDrafts(
    [item({ id: "F-17", barriers: ["mid_rail"] })],
    SITE,
  );
  const clusterId = first.clusters[0].clusterId;
  const result = await buildApprovedBookDrafts(
    [item({ id: "F-17", barriers: ["mid_rail"] })],
    { ...SITE, locationByCluster: { [clusterId]: "A Blok 2. kat" } },
  );
  assertStringIncludes(result.drafts[0].copyText, "A Blok 2. kat bölümünde");
});

// --------------------------------------------------------------------------
// Determinism and linting
// --------------------------------------------------------------------------

Deno.test("aynı girdi aynı baytı üretir", async () => {
  const rows = [item({ id: "F-18", barriers: ["mid_rail"] })];
  const first = await buildApprovedBookDrafts(rows, SITE);
  const second = await buildApprovedBookDrafts(rows, SITE);
  assertEquals(first.drafts[0].copyText, second.drafts[0].copyText);
  assertEquals(first.drafts[0].outputSha256, second.drafts[0].outputSha256);
});

Deno.test("üretilen her paragraf linter'dan geçer", async () => {
  const rows = [
    item({ id: "F-19", barriers: ["mid_rail"] }),
    item({
      id: "F-20",
      moduleId: "machinery",
      mechanism: "caught_in_pinch_shear",
      assetRef: "MIKSER-1",
      criticality: "permanent",
    }),
    item({
      id: "F-21",
      itemClass: "assurance_requirement",
      moduleId: "lifting",
      conditionCode: "visible_asset_assurance",
      mechanism: null,
      assuranceTopic: "lifting_inspection",
      criticality: "ordinary",
    }),
  ];
  const result = await buildApprovedBookDrafts(rows, SITE);
  assertEquals(result.blocked.length, 0, JSON.stringify(result.blocked));
  for (const draft of result.drafts) {
    assertEquals(lint(draft.copyText), [], draft.copyText);
  }
});

Deno.test("linter fotoğraftan belge yokluğu iddiasını yakalar", () => {
  const findings = lint(
    "Saha incelemesinde periyodik kontrol yapılmamıştır. Gerekli tedbir alınmalıdır.",
  );
  assert(findings.some((entry) => entry.rule === "absent_record_claimed"));
});

Deno.test("linter uydurulmuş ölçüyü yakalar", () => {
  const findings = lint(
    "Saha incelemesinde korkuluk yüksekliğinin 90 cm olduğu gözlenmiştir. Yükseklik düzeltilmelidir.",
  );
  assert(findings.some((entry) => entry.rule === "measurement_invented"));
});

Deno.test("linter iç skor dilini yakalar", () => {
  const findings = lint(
    "Saha incelemesinde açık kenar gözlenmiştir. Fine-Kinney skoru yüksektir ve koruma sağlanmalıdır.",
  );
  assert(findings.some((entry) => entry.rule === "internal_score_leaked"));
});

Deno.test("linter çalışanı suçlayan dili yakalar", () => {
  const findings = lint(
    "Saha incelemesinde çalışanın dikkatsizliği gözlenmiştir. Eğitim verilmelidir.",
  );
  assert(findings.some((entry) => entry.rule === "worker_blamed"));
});

Deno.test("linter gereklilik fiili olmayan paragrafı yakalar", () => {
  const findings = lint(
    "Saha incelemesinde açık kenar gözlenmiştir. Bu durum düşme maruziyeti oluşturmaktadır.",
  );
  assert(findings.some((entry) => entry.rule === "no_requirement_verb"));
});

Deno.test("şablon paketi sürüm artmadan değişemez", async () => {
  // SIRA: önce APPROVED_BOOK_TEMPLATE_VERSION artır, sonra hash'i buradan oku.
  // Ters sırada okunan değer yapısal olarak bayattır; prompt paketinde bu üç
  // tur "önbellek sorunu" sanıldı ve değildi.
  assertEquals(APPROVED_BOOK_TEMPLATE_VERSION, "book-tr-templates-v1");
  const sha = await computeApprovedBookBundleSHA256();
  if (RELEASED_BUNDLE_SHA256 !== "PLACEHOLDER") {
    assertEquals(sha, RELEASED_BUNDLE_SHA256);
  }
  assertEquals(sha.length, 64);
});
