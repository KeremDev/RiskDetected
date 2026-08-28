import {
  assert,
  assertEquals,
  assertMatch,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  firstSentenceTeaser,
  projectApprovedNotebookEntries,
  sanitizeNotebookText,
} from "./approved-notebook-projector.ts";

Deno.test("notebook sanitizer removes photo addresses and internal score language", () => {
  assertEquals(
    sanitizeNotebookText(
      "Fotoğraf 2'de, 1 numaralı alanda açık kenar var. P=3 F=6 S=40",
    ),
    "açık kenar var.",
  );
  assertEquals(
    sanitizeNotebookText(
      "Görsel 2’de, 3. bölgede makine 4 üzerinde risk var; FK 1440, P 6 F 6 S 40. Süre: 7 gün. Sorumlu: bakım ekibi.",
    ),
    "makine üzerinde risk var.",
  );
  assertEquals(
    sanitizeNotebookText("Makine 3'ün kapağı ile torna tezgahı 1'deki mil"),
    "Makinenin kapağı ile torna tezgahındaki mil",
  );
});

Deno.test("projector keeps unrelated legacy findings separate", async () => {
  const entries = await projectApprovedNotebookEntries({
    analysisID: "11111111-1111-4111-8111-111111111111",
    language: "tr",
    findings: [
      {
        id: "22222222-2222-4222-8222-222222222222",
        item_class: "observed_finding",
        is_scored: true,
        title: "Açık kenarda düşme riski",
        description:
          "Kenar koruması bulunmayan erişilebilir çalışma alanı görülüyor.",
        recommended_action: "Uygun korkuluk sistemi kurulmalıdır.",
        fk_band: "critical",
        display_order: 0,
      },
      {
        id: "33333333-3333-4333-8333-333333333333",
        item_class: "assurance_requirement",
        is_scored: false,
        title: "Elektrik panosu koruma düzeni",
        recommended_action: "Yetkili elektrik personeliyle doğrulayın.",
        display_order: 1,
      },
    ],
  });
  assertEquals(entries.length, 2);
  assert(entries[0].finding_text.includes("Açık kenarda düşme riski"));
  assert(entries[1].finding_text.includes("saha veya kayıt teyidi"));
  assertMatch(entries[0].id, /^[0-9a-f-]{36}$/);
});

Deno.test("v4 asset and mechanism metadata groups compatible sources", async () => {
  const ids = [
    "22222222-2222-4222-8222-222222222222",
    "33333333-3333-4333-8333-333333333333",
  ];
  const entries = await projectApprovedNotebookEntries({
    analysisID: "11111111-1111-4111-8111-111111111111",
    language: "en",
    findings: ids.map((id, index) => ({
      id,
      item_class: index === 0 ? "observed_finding" : "verification_request",
      is_scored: index === 0,
      title: index === 0 ? "Open edge" : "Guardrail continuity",
      recommended_action:
        "Install and verify a complete edge protection system.",
      source_photo_indices: [1],
      display_order: index,
    })),
    metadata: ids.map((id) => ({
      public_finding_id: id,
      criticality: "fatal",
      asset_ref: "scaffold_01",
      evidence_region: { x: 0.1, y: 0.2, width: 0.6, height: 0.5 },
      canonical_payload: {
        mechanism_code: "fall_from_height",
      },
    })),
  });
  assertEquals(entries.length, 1);
  assertEquals(entries[0].source_finding_ids, ids);
  assert(entries[0].recommendation_text.includes("Field verification"));
});

Deno.test("same asset and mechanism in different regions stay separate", async () => {
  const ids = [
    "22222222-2222-4222-8222-222222222222",
    "33333333-3333-4333-8333-333333333333",
  ];
  const entries = await projectApprovedNotebookEntries({
    analysisID: "11111111-1111-4111-8111-111111111111",
    language: "tr",
    findings: ids.map((id, index) => ({
      id,
      item_class: "observed_finding",
      is_scored: true,
      title: index === 0 ? "Dönen mil koruması" : "Kesme noktası koruması",
      recommended_action: "Makine durdurulup uygun koruyucu takılmalıdır.",
      source_photo_indices: [1],
    })),
    metadata: ids.map((id, index) => ({
      public_finding_id: id,
      criticality: "permanent",
      asset_ref: "lathe_01",
      evidence_region: index === 0
        ? { x: 0.1, y: 0.6, width: 0.3, height: 0.2 }
        : { x: 0.5, y: 0.2, width: 0.3, height: 0.2 },
      canonical_payload: { mechanism_code: "caught_in_pinch_shear" },
    })),
  });
  assertEquals(entries.length, 2);
});

Deno.test("projector prefers concise primary action and is deterministic", async () => {
  const input = {
    analysisID: "11111111-1111-4111-8111-111111111111",
    language: "tr" as const,
    findings: [{
      id: "22222222-2222-4222-8222-222222222222",
      item_class: "observed_finding",
      is_scored: true,
      title: "Açık kenar",
      description: "Korumasız çalışma kenarı görülüyor.",
      recommended_action: "Erişimi durdurun ve uygun kenar koruması kurun.",
      recommended_measures: [{
        kind: "corrective",
        title: "Uzun liste",
        text:
          "1. Birinci teknik adım. 2. İkinci teknik adım. 3. Üçüncü teknik adım.",
      }],
    }],
  };
  const first = await projectApprovedNotebookEntries(input);
  const second = await projectApprovedNotebookEntries(input);
  assertEquals(first, second);
  assertEquals(
    first[0].recommendation_text,
    "Erişimi durdurun ve uygun kenar koruması kurun.",
  );
});

Deno.test("unverified standard identifiers never leak from source prose", async () => {
  const entries = await projectApprovedNotebookEntries({
    analysisID: "11111111-1111-4111-8111-111111111111",
    language: "tr",
    findings: [{
      id: "22222222-2222-4222-8222-222222222222",
      item_class: "assurance_requirement",
      is_scored: false,
      title: "Tank bütünlüğü",
      description: "API 653 uygunluğu doğrulanmalıdır.",
      recommended_action:
        "Saha kontrolünü tamamlayın; API 653 kapsamını esas alın.",
    }],
  });
  assertEquals(entries.length, 1);
  assert(!entries[0].finding_text.includes("API 653"));
  assert(!entries[0].recommendation_text.includes("API 653"));
});

Deno.test("teaser returns only the first bounded sentence", () => {
  assertEquals(
    firstSentenceTeaser("İlk cümle. İkinci cümle gizli."),
    "İlk cümle.",
  );
  assert(firstSentenceTeaser("x".repeat(300)).length <= 160);
});
