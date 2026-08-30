import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  bandsFor,
  criticalityForSeverity,
  looksLikePlaceholder,
  parseV5Output,
  routeV5Findings,
  sanitizeFreeText,
  snapToScale,
  unfulfilledHazardLayers,
} from "./v5-engine.ts";
import {
  FK_SEVERITY,
  V5_MAX_FINDINGS,
  V5_PROMPT_VERSION,
  V5_RESPONSE_SCHEMA,
  V5_SCAN_LAYER_COUNT,
} from "./v5-contracts.ts";
import { buildV5Prompt, V5_FREE_PROMPT } from "./v5-prompt.ts";
import { computeV5PromptSHA256 } from "./prompt-integrity.ts";
import { V4_PROMPT_COMMON } from "./prompt.ts";

function finding(overrides: Record<string, unknown> = {}) {
  return {
    finding_key: "f1",
    layers: [3],
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
    layer_scan: [{ layer: 3, result: "tehlike_var", note: "Açık kenar." }],
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
  "d395dde743af72a6d4b069f2364e02d39338a59084d45bf2ae00840e9140bfe4";

Deno.test("v5 istemi sürüm bumpı olmadan değişemez", async () => {
  assertEquals(V5_PROMPT_VERSION, "v7-free-core-multidisciplinary-v7");
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

Deno.test("istemde kopyalanacak JSON iskeleti kalmadı", () => {
  // Analiz 6f72a303: model örnekteki "Tam iki cümle." metnini aynen döndürdü
  // ve bu analiz özeti olarak okuyucuya gitti. Yanıt şeması yapıyı zaten
  // dayatıyor; örnek yalnız kopyalanacak bir kalıp sağlıyordu.
  assertEquals(V5_FREE_PROMPT.includes("Tam iki cümle."), false);
  assertEquals(
    V5_FREE_PROMPT.includes("kisa_benzersiz_ascii_kimlik_01"),
    false,
  );
  assertEquals(V5_FREE_PROMPT.includes("Fotoğrafa dayalı gerekçe."), false);
  assertEquals(V5_FREE_PROMPT.includes("```json"), false);
  // Alanlar hâlâ anlatılıyor, kalıp verilmeden.
  assertStringIncludes(V5_FREE_PROMPT, "Alan içerikleri:");
  assertStringIncludes(V5_FREE_PROMPT, "Şablon metnini kopyalama");
});

Deno.test("yer tutucu metin okuyucuya ulaşmadan yakalanır", () => {
  assertEquals(looksLikePlaceholder("Tam iki cümle."), true);
  assertEquals(looksLikePlaceholder("  Kısa başlık.  "), true);
  assertEquals(
    looksLikePlaceholder("Görünür kanıt, konum ve maruziyet."),
    true,
  );
  assertEquals(
    looksLikePlaceholder(
      "Şantiye sahasında bir işçi omzunda profil taşıyor. Arka planda üst katta çalışma sürüyor.",
    ),
    false,
  );
});

Deno.test("her dayanak kendi satırında durur", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({
        regulatory_references: [
          "Mevzuat — 6331 sayılı İş Sağlığı ve Güvenliği Kanunu madde 4",
          "Mevzuat — Elle Taşıma İşleri Yönetmeliği",
        ],
      }),
    ])),
  }]);
  const text = routed.items[0].references_text;
  // Boşlukla birleştirildiğinde "…madde 4 Elle Taşıma İşleri Yönetmeliği"
  // çıkıyordu: iki ayrı dayanak, yanlış maddeyi işaret eden tek cümle.
  assertEquals(text.split("\n").length, 2);
  assertStringIncludes(text, "Kanunu madde 4.\nMevzuat — Elle Taşıma");
});

Deno.test("18 katmanın taranması şemayla zorunlu, raporla değil", () => {
  const schema = V5_RESPONSE_SCHEMA as unknown as Record<string, any>;
  // Şema dizini zorunlu kılar: "tara" bir öneriydi ve model onu sessizce
  // atlıyordu -- analiz 5e90f22d'de 18 katmandan 2 ön plan bulgusu çıktı.
  assertEquals((schema.required as string[]).includes("layer_scan"), true);
  const row = schema.properties.layer_scan.items;
  assertEquals(row.properties.result.enum, [
    "tehlike_var",
    "tehlike_yok",
    "kadrajda_yok",
  ]);
  assertEquals(V5_SCAN_LAYER_COUNT, 18);
  // Ama rapora hiç ulaşmaz: v4'ün kapsam matrisi tam olarak bunu yayımladığı
  // için bir raporun on dört maddesinin dokuzu "değerlendirilemedi" olmuştu.
  assertStringIncludes(
    V5_FREE_PROMPT,
    "rapora yazılmaz ve kullanıcıya gösterilmez",
  );
  assertStringIncludes(
    V5_FREE_PROMPT,
    "en az bir bulgu üretmen zorunludur",
  );
  assertStringIncludes(V5_FREE_PROMPT, "katman doldurmak için tehlike uydurma");
});

Deno.test("katman izi ayrıştırılır ve bulguya dönüşmez", () => {
  const raw = JSON.stringify({
    scene_summary: "Şantiye sahnesi.",
    layer_scan: [
      { layer: 3, result: "tehlike_var", note: "Açık döşeme kenarı." },
      { layer: 11, result: "kadrajda_yok", note: "Kazı görünmüyor." },
    ],
    positive_controls: [],
    findings: [finding()],
  });
  const output = parseV5Output(raw);
  assertEquals(output.layer_scan.length, 2);
  assertEquals(output.layer_scan[0].result, "tehlike_var");
  const routed = routeV5Findings([{ photoIndex: 1, output }]);
  // Tek bulgu; katman satırları madde üretmedi.
  assertEquals(routed.items.length, 1);
  assertEquals(routed.items[0].item_class, "observed_finding");
});

Deno.test("tarama listesi bulgulardan önce gelir", () => {
  const schema = V5_RESPONSE_SCHEMA as unknown as Record<string, any>;
  const keys = Object.keys(schema.properties);
  // Tarama yapılacaklar listesidir; bulgular onu karşılar. Bulgular öne
  // alındığında (v5) model taramada gördüğü kaynak dumanını bulguya
  // dönüştüremedi, çünkü dizi çoktan kapanmıştı -- analiz 0e48c1c8.
  assertEquals(keys.indexOf("layer_scan") < keys.indexOf("findings"), true);
  assertEquals(
    schema.properties.findings.items.required.includes("layers"),
    true,
  );
  assertStringIncludes(V5_FREE_PROMPT, "SENİN YAPILACAKLAR LİSTENDİR");
  assertStringIncludes(V5_FREE_PROMPT, "SON KONTROL");
  assertStringIncludes(
    V5_FREE_PROMPT,
    "bulgusuz bırakmak, tehlikeyi rapordan silmektir",
  );
  // Kaynak dumanı bu koşuda taramaya yazılıp bulgusuz kalmıştı.
  assertStringIncludes(V5_FREE_PROMPT, "Kaynak dumanını, ark radyasyonunu");
});

Deno.test("sözü tutulmayan katman ölçülür, uydurulmaz", () => {
  const raw = JSON.stringify({
    scene_summary: "Şantiye sahnesi.",
    positive_controls: [],
    findings: [finding({ layers: [3] })],
    layer_scan: [
      { layer: 3, result: "tehlike_var", note: "Açık kenar." },
      // 88a9c731'de tam olarak bu satır vardı ve karşılığı gelmedi.
      { layer: 5, result: "tehlike_var", note: "Zeminde kablo ve nem." },
      { layer: 11, result: "kadrajda_yok", note: "Kazı yok." },
    ],
  });
  const output = parseV5Output(raw);
  assertEquals(unfulfilledHazardLayers(output), [5]);
  // Ölçülür, ama sunucu eksik bulguyu kendisi yazmaz.
  const routed = routeV5Findings([{ photoIndex: 1, output }]);
  assertEquals(routed.items.length, 1);
});

Deno.test("bir bulgu birden çok katmanı karşılayabilir", () => {
  // Analiz 0e48c1c8: tank üzerindeki işçi katman 3'ü karşıladı ve aynı işçi
  // katman 1'de ("güvensiz pozisyonda kaynak") karşılıksız sayıldı. Tek sayı
  // kapsanmış bir tehlikeyi kapsanmamış gibi okuyordu; eski motorda da bu
  // alan çoğuldu.
  const raw = JSON.stringify({
    scene_summary: "Atölye sahnesi.",
    positive_controls: [],
    findings: [finding({ layers: [1, 3, 17] })],
    layer_scan: [
      { layer: 1, result: "tehlike_var", note: "Güvensiz pozisyon." },
      { layer: 3, result: "tehlike_var", note: "Korkuluksuz çalışma." },
      { layer: 16, result: "tehlike_var", note: "Kaynak dumanı." },
      { layer: 17, result: "tehlike_var", note: "Diz çökme." },
    ],
  });
  const output = parseV5Output(raw);
  // 1, 3 ve 17 karşılandı; gerçekten karşılıksız olan yalnız 16.
  assertEquals(unfulfilledHazardLayers(output), [16]);
  const routed = routeV5Findings([{ photoIndex: 1, output }]);
  assertEquals(routed.items[0].internal_priority.scan_layers, [1, 3, 17]);
});

Deno.test("olumlu kontrol bir önlemdir, bir yokluk değil", () => {
  assertStringIncludes(
    V5_FREE_PROMPT,
    'bir şeyin yokluğu ("dağınıklık yok", "hat kurulmuş") olumlu kontrol değildir',
  );
  assertStringIncludes(
    V5_FREE_PROMPT,
    "Gösterecek bir şey yoksa diziyi boş bırak",
  );
});
