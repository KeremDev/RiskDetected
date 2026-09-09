import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  assertCriticalCandidateFates,
  criticalDemotions,
  routeCandidates,
} from "./claim-router.ts";
import {
  CORE_MODULE_IDS,
  type ProviderCandidate,
  type ProviderPhotoOutput,
  V4_PROVIDER_CONTRACT_VERSION,
} from "./contracts.ts";
import { normalizeCandidates } from "./evidence-normalizer.ts";
import { missingCoreCoverage } from "./dynamic-modules.ts";

/**
 * Multi-photo regression suite.
 *
 * Two production outages reached users through this path while every
 * single-photo test stayed green: a 3-photo run lost the whole analysis to a
 * candidate_key collision, and another reported two critical demotions that
 * were really its own dedup. Single-photo fixtures cannot express either.
 */

function candidate(
  overrides: Partial<ProviderCandidate> = {},
): ProviderCandidate {
  return {
    candidate_key: "C1",
    module_id: "falls_falling_objects",
    raw_label: "Platform kenarında korkuluk eksik",
    asset_ref: "platform-1",
    affirmative_cues: ["Üst korkuluk görülüyor, aradaki açıklık kesintisiz"],
    counter_cues: [],
    evidence_region: { x: 0.1, y: 0.2, width: 0.4, height: 0.5 },
    occlusion: "none",
    event_path: {
      source: "açık platform kenarı",
      contact_or_failure: "kenardan düşme",
      consequence: "ölümcül yaralanma",
    },
    potential_consequence: "fatal",
    visually_resolvable: true,
    requires_document_or_measurement: false,
    confidence: { visibility: 0.92, localization: 0.9, mechanism: 0.92 },
    ...overrides,
  };
}

function output(
  candidates: ProviderCandidate[],
  overrides: Partial<ProviderPhotoOutput> = {},
): ProviderPhotoOutput {
  return {
    contract_version: V4_PROVIDER_CONTRACT_VERSION,
    scene_summary: "Çalışma alanı",
    scene_entities: [{
      id: "platform-1",
      kind: "platform",
      label: "çalışma platformu",
      visible: true,
      accessible: true,
    }],
    people: [],
    accessible_regions: [{
      id: "access-1",
      kind: "walkway",
      label: "erişim yolu",
      visible: true,
      accessible: true,
    }],
    energy_sources: [],
    candidates,
    positive_controls: [],
    module_coverage: CORE_MODULE_IDS.map((moduleID) => ({
      module_id: moduleID,
      activated_by: ["core"],
      outcome: candidates.some((item) => item.module_id === moduleID)
        ? "finding_present"
        : "no_actionable_issue_visible",
      entity_refs: ["platform-1"],
      candidate_keys: candidates.filter((item) => item.module_id === moduleID)
        .map((item) => item.candidate_key),
      note: "Tarama tamamlandı",
    })),
    untrusted_embedded_text: [],
    ...overrides,
  };
}

/** Normalizes several photos the way index.ts does, then routes them together. */
function runPhotos(photos: ProviderPhotoOutput[]) {
  const candidates = photos.flatMap((photo, index) =>
    normalizeCandidates(photo, index + 1)
  );
  const photoOutputs = photos.map((output, index) => ({
    photoIndex: index + 1,
    output,
  }));
  const routed = routeCandidates({
    candidates,
    photoOutputs,
    sectorID: "construction",
  });
  assertCriticalCandidateFates(
    candidates,
    routed.items,
    routed.hardRejections,
    routed.ledger,
  );
  return { candidates, routed };
}

Deno.test("çok fotoğraf: aynı candidate_key iki fotoğrafta çakışmaz", () => {
  // analysis_claim_candidates is unique on (engine_run_id, candidate_key) and
  // an engine run spans the analysis, but the provider only guarantees the key
  // inside one photo. Photos 1 and 3 of a live run both emitted C1 and C2, and
  // the insert took the whole analysis down after every model call was paid.
  const { candidates } = runPhotos([
    output([candidate({ candidate_key: "C1" })]),
    output([candidate({ candidate_key: "C2", module_id: "machinery" })]),
    output([candidate({ candidate_key: "C1" })]),
  ]);
  const keys = candidates.map((item) => item.candidate_key);
  assertEquals(keys.length, 3);
  assertEquals(new Set(keys).size, 3, keys.join(" | "));
  for (const key of keys) assertStringIncludes(key, ":");
});

Deno.test("çok fotoğraf: her aday kendi fotoğraf indeksini taşır", () => {
  const { candidates, routed } = runPhotos([
    output([candidate({ candidate_key: "a" })]),
    output([candidate({ candidate_key: "b", module_id: "machinery" })]),
    output([candidate({ candidate_key: "c", module_id: "electrical" })]),
  ]);
  assertEquals(candidates.map((item) => item.photo_index), [1, 2, 3]);
  for (const item of routed.items.filter((entry) => entry.candidate_id)) {
    assertEquals(item.source_photo_indices.length >= 1, true);
  }
});

Deno.test("çok fotoğraf: dedup ile emilen kritik aday demotion sayılmaz", () => {
  // Three crane hooks each missing a latch merged into one finding, and the
  // critical-fate audit reported two demotions for candidates that had in fact
  // been reported. The alarm fired on its own dedup.
  const hook = (key: string, side: string) =>
    candidate({
      candidate_key: key,
      module_id: "lifting",
      raw_label: `Köprülü vincin ${side} kanca mandalı eksik`,
      asset_ref: `hook-${key}`,
      affirmative_cues: ["Kanca ağzı engelsiz açık, mandal yatağı boş"],
      event_path: {
        source: "kanca mandalı",
        contact_or_failure: "yükün kancadan ayrılması",
        consequence: "ölümcül yaralanma",
      },
    });
  const { routed } = runPhotos([
    output([hook("h1", "sol"), hook("h2", "sağ"), hook("h3", "üst")]),
  ]);
  assertEquals(criticalDemotions.length, 0, criticalDemotions.join(" | "));
  const hookItems = routed.items.filter((item) =>
    item.item_class === "observed_finding" &&
    String(item.title).includes("mandal")
  );
  assertEquals(hookItems.length, 1);
  // The survivor must not claim only its own hook.
  assertEquals(hookItems[0].title, "Vinç kancasında emniyet mandalı eksikliği");
  assertStringIncludes(hookItems[0].description, "ayrı noktada");
  assertEquals(
    (hookItems[0].internal_priority.merged_candidate_ids as string[]).length,
    2,
  );
});

Deno.test("çok fotoğraf: aynı tehlike birleşir, kaynak fotoğraflar korunur", () => {
  const shared = () =>
    candidate({
      candidate_key: "edge",
      raw_label: "Aynı hat üzerinde korkuluk eksik",
    });
  const { routed } = runPhotos([
    output([shared()]),
    output([shared()]),
  ]);
  const findings = routed.items.filter((item) =>
    item.item_class === "observed_finding"
  );
  assertEquals(findings.length, 1);
  assertEquals(findings[0].source_photo_indices, [1, 2]);
});

Deno.test("çok fotoğraf: farklı olay yolları birleşmez ve başlıkları ayrışır", () => {
  const { routed } = runPhotos([
    output([candidate({
      candidate_key: "roof",
      raw_label: "Bina çatısında kenar koruması olmadan çalışma",
      affirmative_cues: ["Çatı kenarı boyunca korkuluk bulunmuyor"],
      event_path: {
        source: "çatı kenarı",
        contact_or_failure: "kenardan düşme",
        consequence: "ölümcül yaralanma",
      },
    })]),
    output([candidate({
      candidate_key: "scaffold",
      raw_label: "İskelenin üst platformunda ara korkuluk eksikliği",
      affirmative_cues: ["Üst korkuluk mevcut, ara korkuluk yok"],
      event_path: {
        source: "iskele korkuluk boşluğu",
        contact_or_failure: "boşluktan düşme",
        consequence: "ölümcül yaralanma",
      },
    })]),
  ]);
  const titles = routed.items
    .filter((item) => item.item_class === "observed_finding")
    .map((item) => String(item.title));
  assertEquals(titles.length, 2);
  assertEquals(new Set(titles).size, 2, titles.join(" | "));
});

Deno.test("çok fotoğraf: bulgusuz bir fotoğraf diğerlerini düşürmez", () => {
  // A photo that legitimately finds nothing must not remove the others'
  // candidates or leave the core scan incomplete.
  const empty = output([]);
  assertEquals(missingCoreCoverage(empty).length, 0);
  const { candidates, routed } = runPhotos([
    output([candidate({ candidate_key: "a" })]),
    empty,
    output([candidate({ candidate_key: "b", module_id: "machinery" })]),
  ]);
  assertEquals(candidates.length, 2);
  assertEquals(
    routed.items.filter((item) => item.item_class === "observed_finding")
      .length,
    2,
  );
});

Deno.test("çok fotoğraf: bir fotoğrafın kritik adayı diğerinin sıradanına karışmaz", () => {
  const { routed } = runPhotos([
    output([candidate({
      candidate_key: "fatal-edge",
      potential_consequence: "fatal",
    })]),
    output([candidate({
      candidate_key: "trip",
      module_id: "housekeeping_physical_contact",
      raw_label: "Zeminde dağınık malzeme",
      potential_consequence: "ordinary",
      affirmative_cues: ["Yerde dağınık tahtalar"],
      event_path: {
        source: "dağınık zemin",
        contact_or_failure: "takılma",
        consequence: "yaralanma",
      },
    })]),
  ]);
  const scored = routed.items.filter((item) => item.is_scored);
  assertEquals(scored.length, 2);
  const bySeverity = Object.fromEntries(
    scored.map((item) => [item.source_photo_indices[0], item.fk_severity]),
  );
  assertEquals(bySeverity[1], 40);
  assertEquals(bySeverity[2], 3);
});

Deno.test("çok fotoğraf: kritik aday hiçbir fotoğrafta sessizce düşmez", () => {
  // assertCriticalCandidateFates runs inside runPhotos and throws on a silent
  // drop; this pins the guarantee across a mixed multi-photo set.
  const { candidates, routed } = runPhotos([
    output([candidate({ candidate_key: "a", occlusion: "substantial" })]),
    output([candidate({
      candidate_key: "b",
      module_id: "electrical",
      raw_label: "Su birikintisi içinden geçen kablo",
      requires_document_or_measurement: true,
      affirmative_cues: ["Kablo su birikintisinin içinden geçiyor"],
      counter_cues: ["Kabloların enerjili olup olmadığı belirlenemiyor"],
    })]),
    output([candidate({ candidate_key: "c" })]),
  ]);
  const criticalIDs = candidates
    .filter((item) => ["fatal", "permanent"].includes(item.criticality))
    .map((item) => item.id);
  assert(criticalIDs.length > 0);
  const accounted = new Set(
    routed.items.flatMap((item) => [
      item.candidate_id,
      ...((item.internal_priority.merged_candidate_ids as string[]) ?? []),
    ]).filter(Boolean),
  );
  for (const id of criticalIDs) {
    assert(
      accounted.has(id) ||
        routed.hardRejections.some((entry) => entry.candidate_id === id),
      id,
    );
  }
});
