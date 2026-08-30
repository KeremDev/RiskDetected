import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  bandsFor,
  criticalityForSeverity,
  parseV5Output,
  routeV5Findings,
  sanitizeFreeText,
  snapToScale,
} from "./v5-engine.ts";
import {
  FK_SEVERITY,
  V5_MAX_FINDINGS,
  V5_PROMPT_VERSION,
  V5_RESPONSE_SCHEMA,
} from "./v5-contracts.ts";
import { buildV5Prompt, V5_FREE_PROMPT } from "./v5-prompt.ts";
import { computeV5PromptSHA256 } from "./prompt-integrity.ts";
import { V4_PROMPT_COMMON } from "./prompt.ts";

function finding(overrides: Record<string, unknown> = {}) {
  return {
    finding_key: "f1",
    title: "Üst kat döşeme kenarında korumasız çalışma.",
    category: "Yüksekte çalışma",
    description: "İşçi açık döşeme kenarında korkuluk olmadan çalışıyor.",
    event_path: "Açık döşeme kenarı → dengesini kaybederek düşme → ölüm.",
    root_cause: "Kenar koruma sistemi kurulmamış.",
    regulatory_references: [
      "Mevzuat — 6331 sayılı İş Sağlığı ve Güvenliği Kanunu.",
      "Standart/iyi mühendislik uygulaması — TS EN 13374 kenar koruma.",
    ],
    fine_kinney: {
      "olasılık": 6,
      frekans: 6,
      "şiddet": 40,
      "gerekçe": "Kenar açık ve işçi orada duruyor.",
    },
    immediate_control: "Üst kat döşeme kenarındaki çalışmayı durdurun.",
    corrective_steps: ["Kenarı korkulukla kapatın.", "Erişimi sınırlandırın."],
    preventive_measure: "Kenar koruma planını iş programına bağlayın.",
    training_recommendation: "Yüksekte çalışma eğitimi verin.",
    ppe_recommendation: "Tam vücut emniyet kemeri ve çift kancalı lanyard.",
    evidence_region: { x_min: 0.37, y_min: 0.29, x_max: 0.43, y_max: 0.33 },
    confidence: 0.8,
    needs_field_verification: false,
    ...overrides,
  };
}

function envelope(findings: unknown[], positives: unknown[] = []) {
  return JSON.stringify({
    scene_summary: "Şantiye sahnesi.",
    positive_controls: positives,
    findings,
  });
}

Deno.test("modelin bulgusu olduğu gibi rapora geçer", () => {
  const routed = routeV5Findings([
    { photoIndex: 1, output: parseV5Output(envelope([finding()])) },
  ]);
  assertEquals(routed.items.length, 1);
  const item = routed.items[0];
  assertEquals(item.item_class, "observed_finding");
  assertEquals(item.is_scored, true);
  assertEquals(item.criticality, "fatal");
  assertEquals(item.fk_severity, 40);
  assertEquals(item.fk_band, "critical");
  assertEquals(item.category, "Yüksekte çalışma");
  assertStringIncludes(item.recommended_action, "döşeme kenarındaki");
  assertEquals(item.internal_priority.control_source, "model");
  // KKD düzeltici adımların sonuna, eğitim önleyici kontrolün yanına gider:
  // uygulamanın bildiği iki tür bunlar, üçüncüsü çözümlemeyi bozar.
  assertStringIncludes(
    item.recommended_measures[0].text,
    "Kişisel koruyucu donanım:",
  );
  assertStringIncludes(item.recommended_measures[1].text, "Eğitim:");
});

Deno.test("bulgular skora göre sıralanır, modelin sırasına göre değil", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({
        finding_key: "small",
        title: "Zeminde dağınık malzeme",
        fine_kinney: {
          "olasılık": 3,
          frekans: 3,
          "şiddet": 3,
          "gerekçe": "x",
        },
      }),
      finding({ finding_key: "big" }),
    ])),
  }]);
  assertEquals(routed.items[0].internal_priority.finding_key, "big");
  assertEquals(routed.items[0].display_order, 1);
  assertEquals(routed.items[1].display_order, 2);
});

Deno.test("görünmeyen kayıt hakkında yokluk iddiası silinir, öneri kalır", () => {
  const claim = sanitizeFreeText(
    "Kenarı korkulukla kapatın. Çalışanların yüksekte çalışma eğitimi yoktur.",
  );
  assertEquals(claim.removed, ["asserts_invisible_absence"]);
  assertStringIncludes(claim.text, "korkulukla kapatın");

  const advice = sanitizeFreeText(
    "Yüksekte çalışma eğitimi verin ve izin sistemini kurun.",
  );
  assertEquals(advice.removed.length, 0);
});

Deno.test("ölçek dışı Fine-Kinney değeri en yakınına oturur, bulgu düşmez", () => {
  assertEquals(snapToScale(38, FK_SEVERITY, 7), { value: 40, snapped: true });
  assertEquals(snapToScale(15, FK_SEVERITY, 7), { value: 15, snapped: false });
  assertEquals(snapToScale("abc", FK_SEVERITY, 7), { value: 7, snapped: true });

  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({
        fine_kinney: {
          "olasılık": 5,
          frekans: 6,
          "şiddet": 38,
          "gerekçe": "x",
        },
      }),
    ])),
  }]);
  assertEquals(routed.items.length, 1);
  assertEquals(routed.items[0].fk_severity, 40);
  assertEquals(routed.snappedCount > 0, true);
});

Deno.test("tehlike yoksa boş rapor üretilir, uydurma bulgu değil", () => {
  const routed = routeV5Findings([
    { photoIndex: 1, output: parseV5Output(envelope([])) },
  ]);
  assertEquals(routed.items.length, 0);
  assertEquals(routed.candidates.length, 0);
});

Deno.test("olumlu kontrol skorlanmaz ve bulguların altına düşer", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([finding()], [{
      title: "İşçiler baret kullanıyor",
      description: "Sahadaki üç işçide de baret görülüyor.",
    }])),
  }]);
  assertEquals(routed.items.length, 2);
  assertEquals(routed.items[1].item_class, "positive_control");
  assertEquals(routed.items[1].is_scored, false);
  assertEquals(
    routed.items[1].display_order > routed.items[0].display_order,
    true,
  );
});

Deno.test("kritiklik şiddetten türer", () => {
  assertEquals(criticalityForSeverity(100), "fatal");
  assertEquals(criticalityForSeverity(40), "fatal");
  assertEquals(criticalityForSeverity(15), "permanent");
  assertEquals(criticalityForSeverity(7), "serious");
  assertEquals(criticalityForSeverity(3), "ordinary");
});

Deno.test("bantlar v4 ile aynı eşikleri kullanır", () => {
  assertEquals(bandsFor(70, 4).fkBand, "low");
  assertEquals(bandsFor(71, 5).fkBand, "medium");
  assertEquals(bandsFor(201, 10).fkBand, "high");
  assertEquals(bandsFor(1440, 20).fkBand, "critical");
  assertEquals(bandsFor(1440, 20).m5Band, "critical");
});

Deno.test("mevzuat dayanağı yayımlanır, silinmez", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({
        regulatory_references: [
          "Mevzuat — 6331 sayılı İş Sağlığı ve Güvenliği Kanunu.",
          "Standart/iyi mühendislik uygulaması — TS EN 13374 kenar koruma sistemleri.",
        ],
        description:
          "İşçi açık döşeme kenarında çalışıyor. 6331 sayılı kanun işverene toplu koruma yükümlülüğü getirir.",
      }),
    ])),
  }]);
  assertEquals(routed.items.length, 1);
  assertStringIncludes(routed.items[0].references_text, "TS EN 13374");
  // Metin içindeki atıf da artık silinmiyor.
  assertStringIncludes(routed.items[0].description, "6331");
  assertEquals(routed.sanitizedCount, 0);
});

Deno.test("görünmeyen kayıt iddiası hâlâ silinir", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({
        description:
          "İşçi açık döşeme kenarında çalışıyor. Çalışanın yüksekte çalışma eğitimi yoktur.",
      }),
    ])),
  }]);
  assertEquals(routed.items.length, 1);
  assertEquals(routed.items[0].description.includes("eğitimi yoktur"), false);
  assertEquals(routed.sanitizedCount, 1);
});

Deno.test("yayımlanacak metni kalmayan bulgu düşer ve iz bırakır", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({ finding_key: "empty", immediate_control: "   " }),
    ])),
  }]);
  assertEquals(routed.items.length, 0);
  assertEquals(routed.droppedFindings[0], {
    finding_key: "empty",
    reason: "empty_control",
  });
});

Deno.test("on sekiz katman ve disiplin kurulu istemde", () => {
  assertStringIncludes(V5_FREE_PROMPT, "ŞU 18 KATMANDA TARA");
  assertStringIncludes(V5_FREE_PROMPT, "çok disiplinli sanal denetim kurulu");
  assertStringIncludes(V5_FREE_PROMPT, "Tank, silo, IBC ve transfer");
  assertStringIncludes(V5_FREE_PROMPT, "Proses güvenliği ve büyük kaza");
  // Katman rapora yazılmaz, katman başına bulgu istenmez.
  assertStringIncludes(
    V5_FREE_PROMPT,
    "Katmanları çıktıya yazma ve katman başına bulgu üretme",
  );
  assertStringIncludes(V5_FREE_PROMPT, "sonucuna göre değerlendir");
  // Sözleşme motorunun makinesi hâlâ yok.
  for (
    const token of [
      "module_coverage",
      "candidate_key",
      "condition_code",
      "not_assessable",
      "inspection_layer_keys",
      "checked_no_hazard",
    ]
  ) {
    assertEquals(V5_FREE_PROMPT.includes(token), false, token);
  }
  assertEquals(V5_FREE_PROMPT.includes(V4_PROMPT_COMMON.trim()), false);
});

Deno.test("periyodik kontrol bölümü kayıt ister, yokluk iddia etmez", () => {
  assertStringIncludes(V5_FREE_PROMPT, "PERİYODİK KONTROL, MUAYENE VE ÖLÇÜM");
  // Üç başlık adıyla.
  assertStringIncludes(V5_FREE_PROMPT, "Kaldırma ekipmanları ve aksesuarları");
  assertStringIncludes(V5_FREE_PROMPT, "Topraklama direnci ölçüm raporu");
  assertStringIncludes(V5_FREE_PROMPT, "Basınçlı kaplar ve kaplar");
  assertStringIncludes(V5_FREE_PROMPT, "Hidrostatik test");
  // Ve kanıt kuralıyla çelişmemesi için: doğrulat, yoktur deme.
  assertStringIncludes(
    V5_FREE_PROMPT,
    '"Periyodik kontrolü yoktur" yazma; "periyodik kontrol raporunu yetkili kişiyle doğrulayın" yaz',
  );
  assertStringIncludes(V5_FREE_PROMPT, "Ekipmanın görünür olması kanıttır");
});

Deno.test("mevzuat yazılır, uydurma numara yasak", () => {
  assertStringIncludes(V5_FREE_PROMPT, "MEVZUAT VE STANDARTLAR");
  assertStringIncludes(V5_FREE_PROMPT, "6331 sayılı Kanun");
  assertStringIncludes(V5_FREE_PROMPT, "yalnız kesin biliyorsan yaz; uydurma");
  assertStringIncludes(V5_FREE_PROMPT, "Türkiye mevzuatı gibi sunma");
  assertStringIncludes(
    V5_FREE_PROMPT,
    "Elektrik Tesislerinde Topraklamalar Yönetmeliği",
  );
});

Deno.test("kanıt kuralları ve tavansızlık yerinde", () => {
  assertStringIncludes(V5_FREE_PROMPT, "DEĞİŞMEZ KANIT KURALLARI");
  assertStringIncludes(
    V5_FREE_PROMPT,
    "muayene kaydının bulunmadığını fotoğraftan iddia etme",
  );
  assertEquals(V5_MAX_FINDINGS, 24);
});

Deno.test("köşe kutusu depolanan biçime çevrilir", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(
      envelope([
        finding({
          evidence_region: {
            x_min: 0.37,
            y_min: 0.29,
            x_max: 0.43,
            y_max: 0.33,
          },
        }),
      ]),
    ),
  }]);
  const region = routed.candidates[0].evidence_region as Record<string, number>;
  assertEquals(region.x, 0.37);
  assertEquals(region.y, 0.29);
  assertEquals(Number(region.width.toFixed(4)), 0.06);
  assertEquals(Number(region.height.toFixed(4)), 0.04);
});

const RELEASED_V5_PROMPT_SHA256 =
  "ba4f4fd7eca958738bd14b361c01689ef9f4b750addf2d506de6d92d848084df";

Deno.test("v5 istemi sürüm bumpı olmadan değişemez", async () => {
  assertEquals(V5_PROMPT_VERSION, "v7-free-core-multidisciplinary-v2");
  assertEquals(await computeV5PromptSHA256(), RELEASED_V5_PROMPT_SHA256);
});

Deno.test("v5 şeması bulgunun tamamını ister", () => {
  const schema = V5_RESPONSE_SCHEMA as unknown as Record<string, any>;
  const required = schema.properties.findings.items.required as string[];
  for (
    const field of [
      "title",
      "category",
      "description",
      "event_path",
      "root_cause",
      "fine_kinney",
      "immediate_control",
      "corrective_steps",
      "preventive_measure",
    ]
  ) {
    assertEquals(required.includes(field), true, field);
  }
  // Eğitim ve KKD isteğe bağlı: her bulguda karşılığı yok.
  assertEquals(required.includes("training_recommendation"), false);
  assertEquals(required.includes("ppe_recommendation"), false);
});

Deno.test("bitmemiş cümleler birbirine yapışmaz", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({
        // Analiz 5eae6972: model noktasız bitirdi ve rapor
        // "...denetlenmesi Eğitim: ..." diye yayımladı.
        preventive_measure: "Yüksekte çalışma prosedürlerinin denetlenmesi",
        training_recommendation: "Yüksekte güvenli çalışma eğitimi",
        corrective_steps: ["Kenarlara korkuluk kurun", "Erişimi kısıtlayın"],
        ppe_recommendation: "Paraşüt tipi emniyet kemeri",
      }),
    ])),
  }]);
  const measures = routed.items[0].recommended_measures;
  assertStringIncludes(measures[1].text, "denetlenmesi. Eğitim:");
  assertStringIncludes(measures[0].text, "1. Kenarlara korkuluk kurun.");
  assertStringIncludes(measures[0].text, "3. Kişisel koruyucu donanım:");
  assertEquals(measures[0].text.includes("kurun2"), false);
});

Deno.test("sektör bir kelime olarak gelir, katalog olarak değil", () => {
  const built = buildV5Prompt({
    photoIndex: 1,
    photoCount: 1,
    outputLanguage: "tr",
    sectorID: "construction",
    analysisContext: "general",
  });
  assertStringIncludes(built, "- Saha türü: inşaat / şantiye");
  // v4'ün sektör bloğu buraya bağlanmıştı ve istemin elli satır yukarıda
  // "sana kontrol listesi verilmiyor" demesine rağmen tam olarak onu
  // veriyordu. İnşaat için 1500 karakter, kabloyu "Geçici elektrik"
  // altında, suyu "Kazı" altında listeleyerek.
  for (
    const token of [
      "Zorunlu tarama",
      "Öncelikli tarama",
      "Görünürse kritik ekipman",
      "Ölümcül mekanizma çapaları",
      "Negatif varsayım kodları",
      "seyyar kablo güzergâhı",
      "access_and_work_at_height",
    ]
  ) {
    assertEquals(built.includes(token), false, token);
  }
  // "general" bir not değil, varsayılan. Kullanıcı bağlamı olarak geçmez.
  assertEquals(built.includes("Kullanıcının notu"), false);
});

Deno.test("bilinmeyen sektör satırı hiç yazılmaz", () => {
  const built = buildV5Prompt({
    photoIndex: 1,
    photoCount: 1,
    outputLanguage: "tr",
    sectorID: null,
  });
  assertEquals(built.includes("Saha türü"), false);
  assertStringIncludes(built, "BAĞLAM");
});
