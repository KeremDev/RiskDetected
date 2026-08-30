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
  V5_PROMPT_VERSION,
  V5_RESPONSE_SCHEMA,
} from "./v5-contracts.ts";
import { V5_FREE_PROMPT } from "./v5-prompt.ts";
import { computeV5PromptSHA256 } from "./prompt-integrity.ts";
import { V4_PROMPT_COMMON } from "./prompt.ts";

function finding(overrides: Record<string, unknown> = {}) {
  return {
    finding_key: "f1",
    title: "Üst kat döşeme kenarında korumasız çalışma",
    category: "Yüksekte çalışma",
    description: "İşçi açık döşeme kenarında korkuluk olmadan çalışıyor.",
    event_path: {
      source: "Açık döşeme kenarı",
      contact_or_failure: "Dengesini kaybederek kenardan düşme",
      consequence: "Ölüm",
    },
    root_cause: "Kenar koruma sistemi kurulmamış.",
    fine_kinney: {
      probability: 6,
      frequency: 6,
      severity: 40,
      rationale: "Kenar açık ve işçi orada duruyor.",
    },
    immediate_control: "Üst kat döşeme kenarındaki çalışmayı durdurun.",
    corrective_steps: ["Kenarı korkulukla kapatın.", "Erişimi sınırlandırın."],
    preventive_measure: "Kenar koruma planını iş programına bağlayın.",
    training_recommendation: "Yüksekte çalışma eğitimi verin.",
    ppe_recommendation: "Tam vücut emniyet kemeri ve çift kancalı lanyard.",
    evidence_region: { x: 0.37, y: 0.29, width: 0.06, height: 0.04 },
    confidence: 0.8,
    needs_field_verification: false,
    ...overrides,
  };
}

function envelope(findings: unknown[], positives: unknown[] = []) {
  return JSON.stringify({
    scene_summary: "Şantiye sahnesi.",
    findings,
    positive_controls: positives,
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
          probability: 3,
          frequency: 3,
          severity: 3,
          rationale: "x",
        },
      }),
      finding({ finding_key: "big" }),
    ])),
  }]);
  assertEquals(routed.items[0].internal_priority.finding_key, "big");
  assertEquals(routed.items[0].display_order, 1);
  assertEquals(routed.items[1].display_order, 2);
});

Deno.test("mevzuat atfı taşıyan cümle silinir, bulgu kalır", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({
        description:
          "İşçi açık döşeme kenarında çalışıyor. Bu durum 6331 sayılı kanuna aykırıdır.",
      }),
    ])),
  }]);
  assertEquals(routed.items.length, 1);
  assertEquals(routed.items[0].description.includes("6331"), false);
  assertStringIncludes(routed.items[0].description, "açık döşeme kenarında");
  assertEquals(routed.sanitizedCount, 1);
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
          probability: 5,
          frequency: 6,
          severity: 38,
          rationale: "x",
        },
      }),
    ])),
  }]);
  assertEquals(routed.items.length, 1);
  assertEquals(routed.items[0].fk_severity, 40);
  assertEquals(routed.snappedCount > 0, true);
});

Deno.test("yayımlanacak metni kalmayan bulgu düşer ve iz bırakır", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: parseV5Output(envelope([
      finding({
        finding_key: "empty",
        immediate_control: "6331 sayılı kanun gereğidir.",
      }),
    ])),
  }]);
  assertEquals(routed.items.length, 0);
  assertEquals(routed.droppedFindings[0], {
    finding_key: "empty",
    reason: "empty_control",
  });
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

Deno.test("serbest istem sözleşme motorunun hiçbir parçasını taşımaz", () => {
  assertEquals(V5_FREE_PROMPT.includes("module_coverage"), false);
  assertEquals(V5_FREE_PROMPT.includes("candidate_key"), false);
  assertEquals(V5_FREE_PROMPT.includes(V4_PROMPT_COMMON.trim()), false);
  // Kalan üç kural.
  assertStringIncludes(V5_FREE_PROMPT, "Yalnız fotoğrafta gördüğünü raporla");
  assertStringIncludes(V5_FREE_PROMPT, "madde numarası veya standart kodu");
  assertStringIncludes(V5_FREE_PROMPT, "Türkçe karakterlerle");
});

const RELEASED_V5_PROMPT_SHA256 =
  "04e495e52a793894c3dd1c7b8efcf96fcd703942837dd30450d3d07f1efa9efa";

Deno.test("v5 istemi sürüm bumpı olmadan değişemez", async () => {
  assertEquals(V5_PROMPT_VERSION, "v5-free-core-v2");
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

Deno.test("tarama sırası sözleşme değil, dikkat yönlendirmesidir", () => {
  // Nereye bakılacağını söyler...
  assertStringIncludes(V5_FREE_PROMPT, "TARAMA");
  assertStringIncludes(V5_FREE_PROMPT, "enerji: elektrik hattı");
  assertStringIncludes(V5_FREE_PROMPT, "yükseltilmiş yüzeyler ve kenarlar");
  // ...ama her başlık için satır üretmeyi istemez. v4'ün kapsam matrisi
  // tam olarak bunu istediği için bir raporun on dört maddesinin dokuzu
  // "değerlendirilemedi" oldu.
  assertStringIncludes(V5_FREE_PROMPT, "o başlığı sessizce geç");
  assertEquals(V5_FREE_PROMPT.includes("module_coverage"), false);
  assertEquals(V5_FREE_PROMPT.includes("not_assessable"), false);
});
