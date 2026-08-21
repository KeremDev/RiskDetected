import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  areLikelyDuplicateCoverageFindings,
  evaluateCoverageQualityRecord,
  isCoverageRepairSubfindingAlreadyCovered,
  normalizeCoverageQualityNoAdditionalReasonCode,
  preferredCoverageFinding,
  tokenJaccardSimilarity,
} from "./photo-finding-quality.ts";

function qualityRecord(
  overrides: Record<string, unknown> = {},
): Parameters<typeof evaluateCoverageQualityRecord>[0] {
  return {
    photo_index: 1,
    coverage_status: "actionable",
    candidate_findings_count: 2,
    findings: [
      { title: "A", inspection_layer_keys: ["ground_housekeeping"] },
      { title: "B", inspection_layer_keys: ["fire_explosion"] },
    ],
    record_missing: false,
    inspection_layers: [
      { layer_key: "ground_housekeeping", status: "actionable" },
      { layer_key: "fire_explosion", status: "actionable" },
    ],
    layer_audit: {
      missing_layer_keys: [],
      duplicate_layer_keys: [],
      invalid_layer_keys_count: 0,
      invalid_layer_statuses_count: 0,
    },
    evidence_guard: {
      rejected_unlinked_count: 0,
      rejected_non_actionable_count: 0,
      marked_uncertain_count: 0,
    },
    ...overrides,
  } as Parameters<typeof evaluateCoverageQualityRecord>[0];
}

Deno.test("merges the reported title suffix variation with identical evidence", () => {
  const first = {
    title: "Elektrikli Cihazın Dış Hasarlara Karşı Korunması",
    observed_evidence:
      "Asansör interkom ünitesi dış etkenlere karşı belirgin bir korumaya sahip değildir.",
    corrective_action: "Koruyucu muhafaza tak.",
    root_cause: "Fiziksel koruma eksikliği.",
  };
  const second = {
    ...first,
    title: "Elektrikli Cihazın Dış Hasarlara Karşı Koruması",
  };

  assert(areLikelyDuplicateCoverageFindings(first, second));
});

Deno.test("does not merge distinct findings that share generic evidence and category", () => {
  const traffic = {
    title: "Yaya ve forklift trafiği ayrımı eksikliği",
    category: "Çevre, Acil Durum, İşaretleme ve Yetkinlik",
    observed_evidence: "Saha gözlemiyle doğrulanması gereken risk göstergesi.",
    corrective_action: "Yaya yollarını fiziksel bariyerlerle ayır.",
    root_cause: "Saha trafik planlamasının yetersizliği.",
  };
  const competence = {
    title: "Forklift operatörü yetkinlik belgesi eksikliği",
    category: "Çevre, Acil Durum, İşaretleme ve Yetkinlik",
    observed_evidence: "Saha gözlemiyle doğrulanması gereken risk göstergesi.",
    corrective_action: "Operatör yetkinlik belgelerini kontrol et.",
    root_cause: "Yetkinlik doğrulama sürecinin eksikliği.",
  };

  assertFalse(areLikelyDuplicateCoverageFindings(traffic, competence));
});

Deno.test("balanced evidence similarity preserves a finding with additional evidence", () => {
  const exposedCable = {
    title: "Açık kabloya temas riski",
    observed_evidence:
      "Pano kapağı açık ve enerji kabloları çalışanların erişimine açıktır.",
    corrective_action: "Panoyu kapat ve erişimi sınırla.",
    root_cause: "Pano erişim kontrolü eksikliği.",
  };
  const grounding = {
    title: "Topraklama bağlantısı eksikliği",
    observed_evidence:
      "Pano kapağı açık ve enerji kabloları çalışanların erişimine açıktır; ayrıca topraklama bağlantısı görünmemektedir.",
    corrective_action: "Topraklama sürekliliğini ölç ve bağlantıyı tamamla.",
    root_cause: "Elektrik tesisatı kontrolü eksikliği.",
  };

  assert(
    tokenJaccardSimilarity(
      exposedCable.observed_evidence,
      grounding.observed_evidence,
    ) < 0.8,
  );
  assertFalse(areLikelyDuplicateCoverageFindings(exposedCable, grounding));
});

Deno.test("strong evidence action and root cause agreement can merge different titles", () => {
  const first = {
    title: "Geçici kabloda izolasyon hasarı",
    observed_evidence:
      "Geçici enerji kablosunun dış izolasyonunda yırtılma ve iletken açığa çıkma görülmektedir.",
    corrective_action: "Hasarlı kabloyu enerjisiz bırak ve yenisiyle değiştir.",
    root_cause: "Geçici kabloların periyodik kontrolünün yapılmaması.",
  };
  const second = {
    title: "Elektrik hattında fiziksel yıpranma",
    observed_evidence:
      "Geçici enerji kablosunun dış izolasyonunda yırtılma ve iletken açığa çıkma görülmüştür.",
    corrective_action: "Hasarlı kabloyu enerjisiz bırak ve yenisiyle değiştir.",
    root_cause: "Geçici kabloların periyodik kontrolünün yapılmaması.",
  };

  assert(areLikelyDuplicateCoverageFindings(first, second));
});

Deno.test("quality repair rejects a sharp-wire subfinding already covered by a compound finding", () => {
  const compound = {
    title: "Korozyonlu ve hasarlı bağlantı elemanı ile bükülmüş tel",
    observed_evidence:
      "Bağlantı elemanında yoğun korozyon ve etrafına sarılmış bükülmüş tel görülmektedir.",
    description:
      "Bağlantıdaki bozulmanın yanında dışarıya doğru uzanan keskin uçlu tel kesilme ve delinme riski oluşturur.",
    corrective_action:
      "Bağlantıyı değiştir ve keskin tel ucunu keserek veya kapatarak güvenli hale getir.",
    preventive_control:
      "Bağlantı elemanlarını ve tel uçlarını periyodik saha kontrolüne ekle.",
    root_cause: "Bakım ve fiziksel bağlantı kontrolünün yetersizliği.",
  };
  const sharpWire = {
    title: "Keskin ve dışarı çıkık tel ucu",
    observed_evidence:
      "Bağlantının yanında dışarı doğru uzanan keskin tel ucu açıkça görülmektedir.",
    corrective_action:
      "Keskin tel ucunu keserek veya koruyucu kapakla güvenli hale getir.",
    preventive_control: "Tel uçlarını düzenli fiziksel kontrolde doğrula.",
    root_cause: "Tel ucunun güvenli biçimde sonlandırılmaması.",
  };

  assertFalse(areLikelyDuplicateCoverageFindings(compound, sharpWire));
  assert(isCoverageRepairSubfindingAlreadyCovered(compound, sharpWire));
});

Deno.test("quality repair rejects an English subfinding covered inside a compound finding", () => {
  const compound = {
    title: "Corroded connector with protruding wire",
    observed_evidence:
      "The connector is heavily corroded and a sharp wire end protrudes beside it.",
    description:
      "The protruding sharp wire can cause a cut or puncture injury.",
    corrective_action:
      "Replace the connector and cut back or cap the sharp wire end.",
    preventive_control:
      "Include connectors and exposed wire ends in routine inspections.",
    root_cause: "Inadequate maintenance of the connection assembly.",
  };
  const sharpWire = {
    title: "Protruding sharp wire end",
    observed_evidence:
      "A sharp wire end is visibly protruding beside the connector.",
    corrective_action: "Cut back or cap the sharp wire end immediately.",
    preventive_control: "Inspect exposed wire ends routinely.",
    root_cause: "The wire end was not safely terminated.",
  };

  assert(isCoverageRepairSubfindingAlreadyCovered(compound, sharpWire));
});

Deno.test("quality repair preserves distinct hazards on the same equipment", () => {
  const exposedCable = {
    title: "Açık kabloya temas riski",
    observed_evidence:
      "Pano kapağı açık ve enerji kabloları çalışanların erişimine açıktır.",
    description: "Açık iletkene temas elektrik çarpmasına yol açabilir.",
    corrective_action: "Panoyu kapat ve erişimi sınırla.",
    preventive_control: "Pano kapaklarını vardiya öncesi kontrol et.",
    root_cause: "Pano erişim kontrolü eksikliği.",
  };
  const grounding = {
    title: "Topraklama bağlantısı eksikliği",
    observed_evidence:
      "Pano gövdesinde doğrulanabilir bir topraklama bağlantısı görünmemektedir.",
    corrective_action: "Topraklama sürekliliğini ölç ve bağlantıyı tamamla.",
    preventive_control: "Topraklama ölçümlerini periyodik olarak kaydet.",
    root_cause: "Elektrik tesisatı kontrolü eksikliği.",
  };

  assertFalse(
    isCoverageRepairSubfindingAlreadyCovered(exposedCable, grounding),
  );
});

Deno.test("quality repair preserves sharp wire when the corrosion finding never covered it", () => {
  const corrosionOnly = {
    title: "Korozyonlu bağlantı elemanı",
    observed_evidence:
      "Metal bağlantı elemanının yüzeyinde yoğun paslanma ve kesit kaybı görülmektedir.",
    description: "Korozyon bağlantının taşıma kapasitesini azaltabilir.",
    corrective_action: "Korozyonlu bağlantı elemanını yenisiyle değiştir.",
    preventive_control: "Bağlantıları korozyon açısından düzenli kontrol et.",
    root_cause: "Çevresel etkiye karşı bakım eksikliği.",
  };
  const sharpWire = {
    title: "Keskin ve dışarı çıkık tel ucu",
    observed_evidence:
      "Bağlantının yanında dışarı doğru uzanan keskin tel ucu görülmektedir.",
    corrective_action: "Keskin tel ucunu kes ve koruyucu kapak tak.",
    preventive_control: "Tel uçlarını saha kontrol listesine ekle.",
    root_cause: "Tel ucunun güvenli sonlandırılmaması.",
  };

  assertFalse(
    isCoverageRepairSubfindingAlreadyCovered(corrosionOnly, sharpWire),
  );
});

Deno.test("keeps the higher-confidence and more complete duplicate", () => {
  const brief = {
    title: "Hasarlı kablo",
    observed_evidence: "Kablo izolasyonu hasarlıdır.",
    corrective_action: "Kabloyu değiştir.",
    root_cause: "Kontrol eksikliği.",
    confidence: 0.72,
  };
  const detailed = {
    title: "Hasarlı kablo izolasyonu",
    observed_evidence:
      "Enerji kablosunun dış izolasyonunda yırtılma görülmektedir.",
    description: "Açık iletkene temas elektrik çarpmasına neden olabilir.",
    corrective_action: "Hattı enerjisiz bırak ve kabloyu yenisiyle değiştir.",
    preventive_control: "Kabloları haftalık fiziksel kontrol listesine ekle.",
    root_cause: "Geçici kablo kontrolünün yapılmaması.",
    confidence: 0.91,
  };

  assertEquals(preferredCoverageFinding(brief, detailed), detailed);
  assertEquals(preferredCoverageFinding(detailed, brief), detailed);
});

Deno.test("coverage quality selector covers 30 TR/EN structural scenarios", () => {
  const cases: Array<{
    name: string;
    record: Parameters<typeof evaluateCoverageQualityRecord>[0];
    semanticsV2?: boolean;
    repair: boolean;
    reason?: string;
  }> = [
    { name: "clean two findings", record: qualityRecord(), repair: false },
    {
      name: "one finding",
      record: qualityRecord({
        findings: [{ inspection_layer_keys: ["ground_housekeeping"] }],
      }),
      repair: true,
      reason: "low_finding_count",
    },
    {
      name: "zero findings actionable",
      record: qualityRecord({ findings: [], candidate_findings_count: 0 }),
      repair: true,
      reason: "low_finding_count",
    },
    {
      name: "candidate gap v2",
      record: qualityRecord({ candidate_findings_count: 3 }),
      semanticsV2: true,
      repair: true,
      reason: "candidate_gap",
    },
    {
      name: "candidate gap legacy ignored",
      record: qualityRecord({ candidate_findings_count: 3 }),
      repair: false,
    },
    {
      name: "multi layer finding",
      record: qualityRecord({
        findings: [
          { inspection_layer_keys: ["ground_housekeeping", "fire_explosion"] },
          { inspection_layer_keys: ["fire_explosion"] },
        ],
      }),
      repair: true,
      reason: "multi_layer_finding",
    },
    {
      name: "duplicate layer keys in one finding are normalized",
      record: qualityRecord({
        findings: [
          {
            inspection_layer_keys: [
              "ground_housekeeping",
              "ground_housekeeping",
            ],
          },
          { inspection_layer_keys: ["fire_explosion"] },
        ],
      }),
      repair: false,
    },
    {
      name: "unrepresented actionable layer",
      record: qualityRecord({
        findings: [
          { inspection_layer_keys: ["ground_housekeeping"] },
          { inspection_layer_keys: ["ground_housekeeping"] },
        ],
      }),
      repair: true,
      reason: "unrepresented_actionable_layer",
    },
    {
      name: "uncertain layer need not be represented",
      record: qualityRecord({
        inspection_layers: [
          { layer_key: "ground_housekeeping", status: "actionable" },
          { layer_key: "fire_explosion", status: "uncertain" },
        ],
      }),
      repair: false,
    },
    {
      name: "unlinked rejection",
      record: qualityRecord({
        evidence_guard: {
          rejected_unlinked_count: 1,
          rejected_non_actionable_count: 0,
          marked_uncertain_count: 0,
        },
      }),
      repair: true,
      reason: "evidence_guard_rejection",
    },
    {
      name: "non actionable rejection",
      record: qualityRecord({
        evidence_guard: {
          rejected_unlinked_count: 0,
          rejected_non_actionable_count: 1,
          marked_uncertain_count: 0,
        },
      }),
      repair: true,
      reason: "evidence_guard_rejection",
    },
    {
      name: "uncertain finding marked",
      record: qualityRecord({
        evidence_guard: {
          rejected_unlinked_count: 0,
          rejected_non_actionable_count: 0,
          marked_uncertain_count: 1,
        },
      }),
      repair: true,
      reason: "evidence_guard_uncertain",
    },
    {
      name: "record missing",
      record: qualityRecord({ record_missing: true }),
      repair: true,
      reason: "record_incomplete",
    },
    {
      name: "missing layer",
      record: qualityRecord({
        layer_audit: {
          missing_layer_keys: ["ppe"],
          duplicate_layer_keys: [],
          invalid_layer_keys_count: 0,
          invalid_layer_statuses_count: 0,
        },
      }),
      repair: true,
      reason: "record_incomplete",
    },
    {
      name: "duplicate layer",
      record: qualityRecord({
        layer_audit: {
          missing_layer_keys: [],
          duplicate_layer_keys: ["ppe"],
          invalid_layer_keys_count: 0,
          invalid_layer_statuses_count: 0,
        },
      }),
      repair: true,
      reason: "record_incomplete",
    },
    {
      name: "invalid layer key",
      record: qualityRecord({
        layer_audit: {
          missing_layer_keys: [],
          duplicate_layer_keys: [],
          invalid_layer_keys_count: 1,
          invalid_layer_statuses_count: 0,
        },
      }),
      repair: true,
      reason: "record_incomplete",
    },
    {
      name: "invalid layer status",
      record: qualityRecord({
        layer_audit: {
          missing_layer_keys: [],
          duplicate_layer_keys: [],
          invalid_layer_keys_count: 0,
          invalid_layer_statuses_count: 1,
        },
      }),
      repair: true,
      reason: "record_incomplete",
    },
    {
      name: "low quality skipped",
      record: qualityRecord({ coverage_status: "low_quality", findings: [] }),
      repair: false,
    },
    {
      name: "no actionable skipped",
      record: qualityRecord({
        coverage_status: "no_actionable_hazard",
        findings: [],
      }),
      repair: false,
    },
    {
      name: "low quality candidate gap skipped",
      record: qualityRecord({
        coverage_status: "low_quality",
        candidate_findings_count: 9,
      }),
      semanticsV2: true,
      repair: false,
    },
    {
      name: "no actionable malformed skipped",
      record: qualityRecord({
        coverage_status: "no_actionable_hazard",
        record_missing: true,
      }),
      repair: false,
    },
    {
      name: "negative candidate normalized",
      record: qualityRecord({ candidate_findings_count: -4 }),
      semanticsV2: true,
      repair: false,
    },
    {
      name: "nan candidate normalized",
      record: qualityRecord({ candidate_findings_count: Number.NaN }),
      semanticsV2: true,
      repair: false,
    },
    {
      name: "three complete findings",
      record: qualityRecord({
        candidate_findings_count: 3,
        findings: [
          { inspection_layer_keys: ["ground_housekeeping"] },
          { inspection_layer_keys: ["fire_explosion"] },
          { inspection_layer_keys: ["ppe"] },
        ],
        inspection_layers: [
          { layer_key: "ground_housekeeping", status: "actionable" },
          { layer_key: "fire_explosion", status: "actionable" },
          { layer_key: "ppe", status: "actionable" },
        ],
      }),
      semanticsV2: true,
      repair: false,
    },
    {
      name: "mixed case layer keys normalized",
      record: qualityRecord({
        findings: [
          { inspection_layer_keys: ["GROUND_HOUSEKEEPING"] },
          { inspection_layer_keys: ["FIRE_EXPLOSION"] },
        ],
      }),
      repair: false,
    },
    {
      name: "empty layer key exposes actionable layer",
      record: qualityRecord({
        findings: [
          { inspection_layer_keys: [""] },
          { inspection_layer_keys: ["fire_explosion"] },
        ],
      }),
      repair: true,
      reason: "unrepresented_actionable_layer",
    },
    {
      name: "missing finding layer array exposes layer",
      record: qualityRecord({
        findings: [{}, { inspection_layer_keys: ["fire_explosion"] }],
      }),
      repair: true,
      reason: "unrepresented_actionable_layer",
    },
    {
      name: "all diagnostics can coexist",
      record: qualityRecord({
        candidate_findings_count: 4,
        findings: [{ inspection_layer_keys: ["ground_housekeeping", "ppe"] }],
        evidence_guard: {
          rejected_unlinked_count: 1,
          rejected_non_actionable_count: 1,
          marked_uncertain_count: 1,
        },
      }),
      semanticsV2: true,
      repair: true,
      reason: "candidate_gap",
    },
    {
      name: "photo index preserved",
      record: qualityRecord({ photo_index: 7 }),
      repair: false,
    },
    {
      name: "candidate equals finding count",
      record: qualityRecord({ candidate_findings_count: 2 }),
      semanticsV2: true,
      repair: false,
    },
  ];

  assertEquals(cases.length, 30);
  for (const scenario of cases) {
    const result = evaluateCoverageQualityRecord(scenario.record, {
      candidateSemanticsV2: scenario.semanticsV2 === true,
    });
    assertEquals(result.should_repair, scenario.repair, scenario.name);
    if (scenario.reason) {
      assert(
        result.trigger_reasons.includes(
          scenario.reason as typeof result.trigger_reasons[number],
        ),
        scenario.name,
      );
    }
  }
});

Deno.test("quality no-additional reason codes fail closed", () => {
  assertEquals(
    normalizeCoverageQualityNoAdditionalReasonCode(
      "no_distinct_additional_hazard",
    ),
    "no_distinct_additional_hazard",
  );
  assertEquals(
    normalizeCoverageQualityNoAdditionalReasonCode(
      "insufficient_visual_evidence",
    ),
    "insufficient_visual_evidence",
  );
  assertEquals(
    normalizeCoverageQualityNoAdditionalReasonCode(
      "existing_findings_cover_scene",
    ),
    "existing_findings_cover_scene",
  );
  assertEquals(
    normalizeCoverageQualityNoAdditionalReasonCode("invented"),
    null,
  );
});
