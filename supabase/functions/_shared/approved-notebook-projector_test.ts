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

// --------------------------------------------------------------------------
// bc85eccd -- five registry cards published a 345-511 character paragraph as
// the notebook recommendation, because the assurance branch dumped the
// specialist card's full recommended_action instead of a line written for
// the log book.
// --------------------------------------------------------------------------

Deno.test("registry-authored notebook line replaces the generic template and the long dump", async () => {
  const entries = await projectApprovedNotebookEntries({
    analysisID: "44444444-4444-4444-8444-444444444444",
    language: "tr",
    findings: [{
      id: "55555555-5555-4555-8555-555555555555",
      item_class: "assurance_requirement",
      is_scored: false,
      title: "Basınçlı Kap ve Hava Tankı — Periyodik Kontrol, Basınç Deneyi ve Kalan Ömür Doğrulaması",
      description: "Sahada basınçlı kap görülmektedir. (uzun uzman paragrafı burada devam eder)",
      recommended_action:
        "Rapor mevcutsa; “1,5 kat yapıldı” ifadesine tek başına güvenmeyin. Yıllık veya üç yıllık/onarım sonrası hangi rejimin uygulandığını, test basıncının etiket ve tasarım dosyasından nasıl türetildiğini, test ortamı/sıcaklığı/hava tahliyesini, kalibrasyonlu referans manometreyi ve deformasyon-kaçak kabul kriterlerini inceleyin.",
      display_order: 0,
    }],
    metadata: [{
      public_finding_id: "55555555-5555-4555-8555-555555555555",
      internal_priority: {
        engine_mode: "free",
        control_source: "registry",
        expert_family: "pressure_vessel",
        notebook_tespit:
          "Sahada basınçlı kap veya hava tankı bulunmakta, periyodik kontrol ve basınç deneyi kaydı doğrulanmamıştır.",
        notebook_oneri: "Hidrostatik test ve et kalınlığı ölçüm raporu istenmelidir.",
      },
    }],
  });
  assertEquals(entries.length, 1);
  assertEquals(
    entries[0].finding_text,
    "Sahada basınçlı kap veya hava tankı bulunmakta, periyodik kontrol ve basınç deneyi kaydı doğrulanmamıştır.",
  );
  assertEquals(
    entries[0].recommendation_text,
    "Hidrostatik test ve et kalınlığı ölçüm raporu istenmelidir.",
  );
  // Neither the generic "saha veya kayıt teyidi gerektirmektedir" template nor
  // the specialist card's long paragraph reaches the reader.
  assert(!entries[0].finding_text.includes("saha veya kayıt teyidi"));
  assert(!entries[0].recommendation_text.includes("İlgili güvence kayıt"));
  assert(!entries[0].recommendation_text.includes("1,5 kat"));
  assert(entries[0].finding_text.length < 150);
  assert(entries[0].recommendation_text.length < 100);
});

Deno.test("assurance items without a registry line keep the prior behaviour", async () => {
  // A v4 legacy item, or a model-sourced records finding the registry never
  // covered: no internal_priority.notebook_tespit/notebook_oneri, so the
  // generic template and the short model action still apply.
  const entries = await projectApprovedNotebookEntries({
    analysisID: "66666666-6666-4666-8666-666666666666",
    language: "tr",
    findings: [{
      id: "77777777-7777-4777-8777-777777777777",
      item_class: "assurance_requirement",
      is_scored: false,
      title: "Elektrik panosu koruma düzeni",
      recommended_action: "Yetkili elektrik personeliyle doğrulayın.",
      display_order: 0,
    }],
  });
  assertEquals(entries.length, 1);
  assert(entries[0].finding_text.includes("saha veya kayıt teyidi"));
  assert(entries[0].recommendation_text.includes("İlgili güvence kayıt"));
});

// --------------------------------------------------------------------------
// The operator: "işciyi derhal indirin ve çalışmayı durdurun ... bu dil iyi
// değil. emir kipinden ziyade önerilmektedir yazılması daha mantıklı."
// --------------------------------------------------------------------------

Deno.test("scored finding uses the model's advisory-register line over the imperative action", async () => {
  const entries = await projectApprovedNotebookEntries({
    analysisID: "88888888-8888-4888-8888-888888888888",
    language: "tr",
    findings: [{
      id: "99999999-9999-4999-8999-999999999999",
      item_class: "observed_finding",
      is_scored: true,
      title: "Silindirik Tank Üzerinde Korkuluksuz Yüksekte Çalışma",
      description:
        "İşçi, yüksek konumdaki silindirik metal tankın üzerinde korkuluk olmaksızın çalışmaktadır.",
      recommended_action:
        "İşçiyi derhal tank üzerinden güvenli bir platforma indirin ve çalışmayı durdurun.",
      fk_band: "critical",
      display_order: 0,
    }],
    metadata: [{
      public_finding_id: "99999999-9999-4999-8999-999999999999",
      internal_priority: {
        engine_mode: "free",
        control_source: "model",
        notebook_oneri: "Çalışmanın derhal durdurulması önerilmektedir.",
      },
    }],
  });
  assertEquals(entries.length, 1);
  assertEquals(
    entries[0].recommendation_text,
    "Çalışmanın derhal durdurulması önerilmektedir.",
  );
  assert(!entries[0].recommendation_text.includes("indirin"));
});

Deno.test("scored finding without notebook_oneri keeps the imperative action (v4 legacy)", async () => {
  const entries = await projectApprovedNotebookEntries({
    analysisID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    language: "tr",
    findings: [{
      id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      item_class: "observed_finding",
      is_scored: true,
      title: "Açık kenarda düşme riski",
      description: "Kenar koruması bulunmayan erişilebilir çalışma alanı.",
      recommended_action: "Uygun korkuluk sistemi kurulmalıdır.",
      display_order: 0,
    }],
  });
  assertEquals(
    entries[0].recommendation_text,
    "Uygun korkuluk sistemi kurulmalıdır.",
  );
});

Deno.test("teaser returns only the first bounded sentence", () => {
  assertEquals(
    firstSentenceTeaser("İlk cümle. İkinci cümle gizli."),
    "İlk cümle.",
  );
  assert(firstSentenceTeaser("x".repeat(300)).length <= 160);
});
