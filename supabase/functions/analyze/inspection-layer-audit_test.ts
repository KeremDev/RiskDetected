import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  applyInspectionLayerEvidenceGuard,
  hasCompleteInspectionLayerContract,
  INSPECTION_LAYER_KEYS,
  invalidInspectionLayerKeyCount,
  normalizeInspectionLayerKeys,
  normalizeInspectionLayers,
} from "./inspection-layer-audit.ts";

function completeFixture() {
  return INSPECTION_LAYER_KEYS.map((layer_key, index) => ({
    layer_key,
    status: index === 3 ? "actionable" : "checked_no_hazard",
    visual_evidence: `evidence-${index + 1}`,
  }));
}

Deno.test("normalizes a complete 12-layer Gemini fixture", () => {
  const normalized = normalizeInspectionLayers(completeFixture());
  assertEquals(normalized.layers.length, 12);
  assertEquals(normalized.missing, []);
  assertEquals(normalized.duplicates, []);
  assertEquals(normalized.invalidKeyCount, 0);
  assertEquals(normalized.invalidStatusCount, 0);
});

Deno.test("audits incomplete Groq coverage without throwing", () => {
  const fixture = completeFixture();
  fixture[11] = { ...fixture[0] };
  fixture[1] = { ...fixture[1], status: "unexpected" };
  fixture.push({
    layer_key: "unknown_layer" as typeof fixture[number]["layer_key"],
    status: "actionable",
    visual_evidence: "invalid",
  });

  const normalized = normalizeInspectionLayers(fixture);
  assertEquals(normalized.layers.length, 11);
  assertEquals(normalized.missing, [
    "environment_emergency_signage_competence",
  ]);
  assertEquals(normalized.duplicates, ["ground_housekeeping"]);
  assertEquals(normalized.invalidKeyCount, 1);
  assertEquals(normalized.invalidStatusCount, 1);
});

Deno.test("cleans invalid finding links while preserving valid layer keys", () => {
  const raw = ["electrical_energy", "unknown", "electrical_energy"];
  assertEquals(normalizeInspectionLayerKeys(raw), ["electrical_energy"]);
  assertEquals(invalidInspectionLayerKeyCount(raw), 1);
});

Deno.test("normalizes Gemini Turkish layer aliases to the canonical contract", () => {
  const aliases = [
    "zemin_saha_duzeni_duzen_tertip",
    "calisan_kkd",
    "yuksekte_calisma",
    "elektrik_enerji",
    "makine_ekipman_is_ekipmani",
    "kaldirma_tasima_istifleme",
    "kimyasal_tehlikeli_madde",
    "yangin_patlama",
    "fiziksel_ortam_etkenleri",
    "ergonomi_elle_tasima",
    "kazi_kapali_alan_ozel_isler",
    "cevre_acil_durum_isaretleme_yetkinlik",
  ];
  const normalized = normalizeInspectionLayers(
    aliases.map((layer_key) => ({
      layer_key,
      status: "checked_no_hazard",
      visual_evidence: "kontrol edildi",
    })),
  );

  assertEquals(normalized.layers.map((layer) => layer.layer_key), [
    ...INSPECTION_LAYER_KEYS,
  ]);
  assertEquals(hasCompleteInspectionLayerContract(normalized), true);
  assertEquals(
    normalizeInspectionLayerKeys(["elektrik_enerji"]),
    ["electrical_energy"],
  );
  assertEquals(invalidInspectionLayerKeyCount(aliases), 0);
});

Deno.test("evidence guard keeps actionable and marks uncertain findings", () => {
  const fixture = completeFixture();
  fixture[0] = { ...fixture[0], status: "uncertain" };
  const normalized = normalizeInspectionLayers(fixture);
  assertEquals(hasCompleteInspectionLayerContract(normalized), true);

  const guarded = applyInspectionLayerEvidenceGuard(
    [
      {
        title: "Belirsiz zemin durumu",
        confidence: 0.91,
        inspection_layer_keys: ["ground_housekeeping"],
      },
      {
        title: "Elektrik tehlikesi",
        confidence: 0.88,
        inspection_layer_keys: ["electrical_energy"],
      },
    ],
    normalized,
    true,
  );

  assertEquals(guarded.applied, true);
  assertEquals(guarded.findings.length, 2);
  assertEquals(guarded.marked_uncertain_count, 1);
  assertEquals(guarded.findings[0].confidence, 0.69);
  assertEquals(guarded.findings[0].needs_field_verification, true);
});

Deno.test("evidence guard rejects unlinked and non-actionable findings", () => {
  const normalized = normalizeInspectionLayers(completeFixture());
  const guarded = applyInspectionLayerEvidenceGuard(
    [
      { title: "Bağlantısız", confidence: 0.8 },
      {
        title: "Desteksiz KKD iddiası",
        confidence: 0.8,
        inspection_layer_keys: ["ppe"],
      },
    ],
    normalized,
    true,
  );

  assertEquals(guarded.findings, []);
  assertEquals(guarded.rejected_unlinked_count, 1);
  assertEquals(guarded.rejected_non_actionable_count, 1);
});

Deno.test("evidence guard rejects image-limited non-observations mislabeled actionable", () => {
  const fixture = completeFixture();
  fixture[1] = {
    ...fixture[1],
    status: "actionable",
    visual_evidence:
      "İş ayakkabıları fotoğrafın alt kısmı bulanık olduğu için görünmüyor.",
  };
  const normalized = normalizeInspectionLayers(fixture);
  assertEquals(normalized.layers[1].status, "not_visible");
  assertEquals(hasCompleteInspectionLayerContract(normalized), true);

  const guarded = applyInspectionLayerEvidenceGuard(
    [{
      title: "Doğrulanmamış iş ayakkabısı",
      confidence: 0.75,
      needs_field_verification: true,
      inspection_layer_keys: ["ppe"],
    }],
    normalized,
    true,
  );

  assertEquals(guarded.findings, []);
  assertEquals(guarded.rejected_non_actionable_count, 1);
});

Deno.test("image-limited guard preserves a clearly visible missing safeguard", () => {
  const fixture = completeFixture();
  fixture[4] = {
    ...fixture[4],
    status: "actionable",
    visual_evidence:
      "Makinenin dönen bölgesi bütünüyle görünür ve koruyucu muhafaza bulunmuyor.",
  };

  const normalized = normalizeInspectionLayers(fixture);
  assertEquals(normalized.layers[4].status, "actionable");
});

Deno.test("evidence guard fails open for incomplete layer coverage", () => {
  const normalized = normalizeInspectionLayers(completeFixture().slice(0, 11));
  const findings = [{ title: "Legacy bulgu", confidence: 0.8 }];
  const guarded = applyInspectionLayerEvidenceGuard(findings, normalized, true);

  assertEquals(guarded.applied, false);
  assertEquals(guarded.findings, findings);
});

Deno.test("evidence guard leaves complete coverage unchanged when disabled", () => {
  const normalized = normalizeInspectionLayers(completeFixture());
  const findings = [{ title: "Mevcut production bulgusu", confidence: 0.8 }];
  const guarded = applyInspectionLayerEvidenceGuard(
    findings,
    normalized,
    false,
  );

  assertEquals(guarded.applied, false);
  assertEquals(guarded.findings, findings);
});

Deno.test("re-examination accepts a checked_no_hazard layer as field-verifiable", () => {
  // The live case: excavation_confined_special_work came back
  // checked_no_hazard on a photo that had produced a slope-stability finding
  // on two earlier runs of the same image.
  const normalized = normalizeInspectionLayers(completeFixture());
  const findings = [{
    title: "Şev stabilitesi riski",
    confidence: 0.92,
    inspection_layer_keys: ["excavation_confined_special_work"],
  }];

  const blocked = applyInspectionLayerEvidenceGuard(findings, normalized, true);
  assertEquals(blocked.findings.length, 0);
  assertEquals(blocked.rejected_non_actionable_count, 1);
  assertEquals(blocked.reexamined_checked_layer_count, 0);

  const reopened = applyInspectionLayerEvidenceGuard(
    findings,
    normalized,
    true,
    true,
  );
  assertEquals(reopened.findings.length, 1);
  assertEquals(reopened.reexamined_checked_layer_count, 1);
  assertEquals(reopened.findings[0].confidence, 0.69);
  assertEquals(reopened.findings[0].needs_field_verification, true);
});

Deno.test("re-examination never reopens a not_visible layer", () => {
  // not_visible means the layer could not be seen. There is no judgement to
  // question, so a finding built on it would be invention.
  const fixture = completeFixture().map((layer) =>
    layer.layer_key === "fire_explosion"
      ? { ...layer, status: "not_visible" }
      : layer
  );
  const normalized = normalizeInspectionLayers(fixture);
  const findings = [{
    title: "Yangın yükü",
    confidence: 0.9,
    inspection_layer_keys: ["fire_explosion"],
  }];

  const guarded = applyInspectionLayerEvidenceGuard(
    findings,
    normalized,
    true,
    true,
  );
  assertEquals(guarded.findings.length, 0);
  assertEquals(guarded.rejected_non_actionable_count, 1);
  assertEquals(guarded.reexamined_checked_layer_count, 0);
});

Deno.test("re-examination does not downgrade a finding on an actionable layer", () => {
  const normalized = normalizeInspectionLayers(completeFixture());
  const actionableKey = INSPECTION_LAYER_KEYS[3];
  const findings = [{
    title: "Doğrudan görülen tehlike",
    confidence: 0.95,
    inspection_layer_keys: [actionableKey],
  }];

  const guarded = applyInspectionLayerEvidenceGuard(
    findings,
    normalized,
    true,
    true,
  );
  assertEquals(guarded.findings.length, 1);
  assertEquals(guarded.findings[0].confidence, 0.95);
  assertEquals(guarded.findings[0].needs_field_verification, undefined);
  assertEquals(guarded.reexamined_checked_layer_count, 0);
});

Deno.test("a finding spanning an uncertain and a checked layer counts once", () => {
  const fixture = completeFixture().map((layer) =>
    layer.layer_key === "ppe" ? { ...layer, status: "uncertain" } : layer
  );
  const normalized = normalizeInspectionLayers(fixture);
  const findings = [{
    title: "KKD ve makine koruyucusu",
    confidence: 0.9,
    inspection_layer_keys: ["ppe", "machinery_equipment"],
  }];

  const guarded = applyInspectionLayerEvidenceGuard(
    findings,
    normalized,
    true,
    true,
  );
  assertEquals(guarded.findings.length, 1);
  assertEquals(guarded.marked_uncertain_count, 1);
  // It would have been accepted on the uncertain layer alone, so it is not a
  // recovery and must not inflate the recovered count.
  assertEquals(guarded.reexamined_checked_layer_count, 0);
});
