import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
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
import {
  coverageIsStructurallyValid,
  coverageValidationIssues,
  initialActiveModules,
  missingCoreCoverage,
  recoverCoverageDeterministically,
} from "./dynamic-modules.ts";
import { topicConsequenceRank } from "./assurance-playbook.ts";
import { controlPlaybook } from "./control-playbook.ts";
import { reconcileVerificationPass } from "./verification-pass.ts";
import { outputLanguageFailure } from "./language-contract.ts";
import { normalizeCandidates } from "./evidence-normalizer.ts";
import { buildCoverageRepairPrompt } from "./provider.ts";
import { buildTargetedQueue, mergeTargetedOutput } from "./targeted-queue.ts";

function candidate(
  overrides: Partial<ProviderCandidate> = {},
): ProviderCandidate {
  return {
    candidate_key: "edge-1",
    module_id: "work_at_height",
    raw_label: "Erişilebilir platform kenarında orta korkuluk eksik",
    asset_ref: "platform-1",
    affirmative_cues: [
      "Platform döşemesi ve üst korkuluk görülüyor; aradaki açıklık kesintisiz",
    ],
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

function output(candidates: ProviderCandidate[]): ProviderPhotoOutput {
  return {
    contract_version: V4_PROVIDER_CONTRACT_VERSION,
    scene_summary: "İskele ve erişilebilir çalışma platformu",
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
  };
}

Deno.test("C: kişi görünmese de erişilebilir yapısal korkuluk eksikliği observed olur", () => {
  const photo = output([candidate()]);
  const normalized = normalizeCandidates(photo, 1);
  const routed = routeCandidates({
    candidates: normalized,
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(routed.items[0].item_class, "observed_finding");
  assertEquals(routed.items[0].is_scored, true);
  assertEquals(routed.items[0].fk_frequency, 3);
  assertEquals(routed.items[0].fk_probability, 3);
  assertEquals(routed.items[0].fk_severity, 15);
  assertEquals(routed.items[0].m5_probability, 3);
  assertEquals(routed.items[0].m5_severity, 3);
  assertEquals(routed.items[0].needs_field_verification, true);
});

Deno.test("tam kenar koruması yokluğu kişi doğrudan maruzsa mevcut P/S tavanlarıyla kritik olur", () => {
  const photo = output([candidate({
    raw_label: "Çalışanın yanında açık platform kenarında korkuluk sistemi yok",
    person_ref: "worker-1",
    affirmative_cues: [
      "Çalışan erişilebilir platform kenarında; üst, orta ve alt koruma elemanları görünmüyor",
    ],
  })]);
  const normalized = normalizeCandidates(photo, 1);
  const routed = routeCandidates({
    candidates: normalized,
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(routed.items[0].fk_probability, 6);
  assertEquals(routed.items[0].fk_frequency, 6);
  assertEquals(routed.items[0].fk_severity, 40);
  assertEquals(routed.items[0].fk_band, "critical");
  assertEquals(routed.items[0].m5_probability, 4);
  assertEquals(routed.items[0].m5_severity, 4);
  assertStringIncludes(
    routed.items[0].root_cause_text,
    "toplu koruma",
  );
  assertEquals(routed.items[0].recommended_measures.length, 2);
  assertEquals(routed.items[0].recommended_measures[0].kind, "corrective");
  assertEquals(routed.items[0].recommended_measures[1].kind, "preventive");
});

Deno.test("E3 korkuluk eksikliği görünür çalışanla skorlu kritik bulguya yönlenir", () => {
  const photo = output([candidate({
    raw_label: "İşçi 1 yanında açık çalışma kenarında korkuluk sistemi yok",
    person_ref: "worker-1",
    affirmative_cues: [
      "İşçi 1 çalışma kenarında; üst ve ara korkuluk elemanları görünmüyor",
    ],
    occlusion: "partial",
    confidence: { visibility: 0.78, localization: 0.75, mechanism: 0.85 },
  })]);
  photo.people = [{
    id: "worker-1",
    kind: "worker",
    label: "çalışan",
    visible: true,
    cues: ["kenar yakınında çalışıyor"],
  }];
  const normalized = normalizeCandidates(photo, 1);
  const routed = routeCandidates({
    candidates: normalized,
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const finding = routed.items.find((item) => item.is_scored)!;
  assertEquals(finding.item_class, "observed_finding");
  assertEquals(finding.fk_probability, 6);
  assertEquals(finding.fk_frequency, 6);
  assertEquals(finding.fk_severity, 40);
  assertEquals(finding.fk_band, "critical");
  // The narrow escape hatch this used to take is gone: an E3 critical
  // candidate with an accessible event path now takes the ordinary finding
  // route, so the reason code is the general one.
  assertEquals(
    finding.internal_priority.route_reason,
    "visible_structural_absence",
  );
  assertEquals(finding.title.includes("İşçi 1"), false);
  assertEquals(finding.description.includes("İşçi 1"), false);
  assertEquals(finding.root_cause_text.length > 20, true);
  assertEquals(finding.recommended_measures.length, 2);
  assertEquals(buildTargetedQueue(normalized, "premium").selected.length, 0);
});

Deno.test("kablo-hortum belirsizliği enerjili elektrik bulgusu olarak skorlanmaz", () => {
  const photo = output([candidate({
    candidate_key: "ambiguous-line",
    module_id: "electrical",
    raw_label: "Su birikintisi içindeki kablolar/hortumlar",
    affirmative_cues: [
      "Islak zeminde kablolar/hortumlar görülüyor; hattın niteliği belirsiz",
    ],
    event_path: {
      source: "ıslak zemindeki hat",
      contact_or_failure: "hatla temas",
      consequence: "ciddi yaralanma",
    },
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const verification = routed.items[0];
  assertEquals(verification.item_class, "verification_request");
  assertEquals(verification.is_scored, false);
  assertEquals(verification.root_cause_text, "");
  assertEquals(verification.title.includes("enerjili"), false);
  assertStringIncludes(verification.description, "kesinleştirilemiyor");
  // Unscored items carry the module playbook: temporary protection, numbered
  // field steps and the standing arrangement.
  assertEquals(verification.recommended_measures.length, 3);
  assertStringIncludes(
    verification.recommended_measures[1].text,
    "1. ",
  );
  assertStringIncludes(verification.references_text, "");
});

Deno.test("aynı zemindeki düzen ve erişim adayları tek olay yolu olarak birleşir", () => {
  const photo = output([
    candidate({
      candidate_key: "ground-housekeeping",
      module_id: "housekeeping_physical_contact",
      raw_label: "Islak zeminde dağınık malzemeler",
      affirmative_cues: ["Yürüme alanında su ve dağınık parçalar görülüyor"],
      event_path: {
        source: "ıslak ve dağınık zemin",
        contact_or_failure: "takılma veya kayma",
        consequence: "düşme ve yaralanma",
      },
      potential_consequence: "serious",
    }),
    candidate({
      candidate_key: "ground-access",
      module_id: "access_egress",
      raw_label: "Geçiş yolunda malzeme ve su birikmesi",
      affirmative_cues: ["Geçiş hattı su ve malzemelerle daralmış"],
      event_path: {
        source: "engellenmiş geçiş hattı",
        contact_or_failure: "takılma veya kayma",
        consequence: "düşme ve yaralanma",
      },
      potential_consequence: "serious",
    }),
  ]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(routed.items.filter((item) => item.is_scored).length, 1);
  assertEquals(routed.ledger.length, 2);
});

Deno.test("görünür vinç için model çağrısı olmadan skorsuz güvence kaydı oluşur", () => {
  const photo = output([]);
  photo.scene_entities.push({
    id: "crane-1",
    kind: "mobile_crane",
    label: "mobil vinç",
    visible: true,
  });
  const secondPhoto = output([]);
  secondPhoto.scene_entities.push({
    id: "crane-other-angle",
    kind: "crane",
    label: "aynı mobil vinç",
    visible: true,
  });
  const routed = routeCandidates({
    candidates: [],
    photoOutputs: [
      { photoIndex: 1, output: photo },
      { photoIndex: 2, output: secondPhoto },
    ],
    sectorID: "construction",
  });
  const assuranceItems = routed.items.filter((item) =>
    item.item_class === "assurance_requirement"
  );
  assertEquals(assuranceItems.length, 1);
  const assurance = assuranceItems[0];
  assertEquals(assurance.is_scored, false);
  assertEquals(assurance.needs_field_verification, true);
  assertEquals(assurance.source_photo_indices, [1, 2]);
  assertStringIncludes(assurance.title, "Kaldırma ekipmanı");
});

Deno.test("L: görünen ekipmanın belge/ölçüm konusu assurance ve skorsuz olur", () => {
  const photo = output([candidate({
    candidate_key: "lift-check",
    module_id: "lifting",
    raw_label: "Kaldırma aksesuarının kapasite ve kontrol güvencesi",
    requires_document_or_measurement: true,
    potential_consequence: "permanent",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(routed.items[0].item_class, "assurance_requirement");
  assertEquals(routed.items[0].is_scored, false);
  assertEquals(routed.items[0].fk_probability, undefined);
});

Deno.test("E: örtülü kritik elektrik geometrisi verification olarak korunur", () => {
  const photo = output([candidate({
    candidate_key: "panel-gap",
    module_id: "electrical",
    raw_label: "Pano açıklığında enerji temas yolu olasılığı",
    affirmative_cues: [
      "Pano kapağının bir bölümü açık ve iç bölüm kısmen örtülü",
    ],
    occlusion: "substantial",
    confidence: { visibility: 0.55, localization: 0.5, mechanism: 0.65 },
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "energy",
  });
  assertEquals(routed.items[0].item_class, "verification_request");
  assertEquals(routed.items[0].needs_field_verification, true);
});

Deno.test("T: kanıtsız aday hard reject ledger'a gider", () => {
  const photo = output([candidate({ affirmative_cues: [] })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(
    routed.hardRejections[0].reason_code,
    "no_affirmative_visual_evidence",
  );
  assertEquals(routed.items.length, 0);
});

Deno.test("M: fotoğraftan ölçüm çıkarımı hard reject olur", () => {
  const photo = output([candidate({
    raw_label: "Gürültü 95 dB ve ölçüm sonucu uygunsuz",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routed.hardRejections[0].reason_code,
    "forbidden_photo_measurement_or_document_claim",
  );
});

Deno.test("belge yokluğu görünen varlık için hard reject değil assurance olur", () => {
  const photo = output([candidate({
    candidate_key: "lift-document",
    module_id: "lifting",
    raw_label:
      "Kaldırma ekipmanının periyodik kontrolü yok iddiası saha teyidi gerektiriyor",
    requires_document_or_measurement: true,
    asset_ref: "lift-1",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(routed.hardRejections.length, 0);
  assertEquals(routed.items[0].item_class, "assurance_requirement");
  assertEquals(routed.items[0].is_scored, false);
});

Deno.test("geçerli fiziksel iddianın ikincil ölçüm cümlesi temizlenir", () => {
  const photo = output([candidate({
    raw_label: "Erişilebilir açık platform kenarı",
    affirmative_cues: [
      "Platform kenarında koruyucu eleman görünmüyor",
      "Açıklık 1,2 m olarak ölçülmüş görünüyor",
    ],
  })]);
  const normalized = normalizeCandidates(photo, 1);
  assertEquals(normalized[0].affirmative_cues, [
    "Platform kenarında koruyucu eleman görünmüyor",
  ]);
  const routed = routeCandidates({
    candidates: normalized,
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(routed.items[0].item_class, "observed_finding");
});

Deno.test("W: positive control yalnız private item olur", () => {
  const photo = output([]);
  photo.positive_controls = [{
    control_key: "guard-ok",
    module_id: "machinery",
    asset_ref: "machine-1",
    description: "Hareketli bölgeyi çevreleyen sabit koruyucu",
    affirmative_cues: ["Koruyucu gövde kesintisiz görünüyor"],
  }];
  const routed = routeCandidates({
    candidates: [],
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(routed.items[0].item_class, "positive_control");
  assertEquals(routed.items[0].is_scored, false);
});

Deno.test("P: core-7 kapsamı eksiksiz ve boş sonuçsuz olmalı", () => {
  const photo = output([candidate()]);
  assertEquals(missingCoreCoverage(photo), []);
  assertEquals(coverageIsStructurallyValid(photo), false);
  photo.module_coverage.push({
    module_id: "work_at_height",
    activated_by: ["visible_platform"],
    outcome: "finding_present",
    entity_refs: ["platform-1"],
    candidate_keys: ["edge-1"],
    note: "Etkin dinamik modül kapatıldı",
  });
  assertEquals(coverageIsStructurallyValid(photo), true);
  photo.module_coverage.pop();
  assertEquals(coverageIsStructurallyValid(photo), false);
});

Deno.test("coverage aynı modülü iki kez veya başka modülün adayıyla kapatamaz", () => {
  const photo = output([candidate({
    candidate_key: "fall-candidate",
    module_id: "falls_falling_objects",
  })]);
  photo.scene_entities = [];
  const falls = photo.module_coverage.find((item) =>
    item.module_id === "falls_falling_objects"
  )!;
  assertEquals(coverageIsStructurallyValid(photo), true);
  photo.module_coverage.push({ ...falls });
  assertEquals(coverageIsStructurallyValid(photo), false);
  photo.module_coverage.pop();
  falls.module_id = "people_exposure";
  assertEquals(coverageIsStructurallyValid(photo), false);
});

Deno.test("coverage retry eksik inşaat modüllerini açık reason-code ile hedefler", () => {
  const photo = output([candidate()]);
  const required = initialActiveModules("construction");
  const issues = coverageValidationIssues(photo, required);
  assertEquals(issues.includes("missing_module:work_at_height"), true);
  assertEquals(issues.includes("missing_module:lifting"), true);
  const repair = buildCoverageRepairPrompt("BASE", issues, required);
  assertEquals(repair.includes("missing_module:work_at_height"), true);
  assertEquals(repair.includes("Görsel kanıt yoksa bulgu uydurma"), true);
});

Deno.test("ikinci coverage kusuru adayları silmeden güvenli biçimde tamamlanır", () => {
  const photo = output([candidate()]);
  photo.module_coverage.push({ ...photo.module_coverage[0] });
  const required = initialActiveModules("construction");
  const recovered = recoverCoverageDeterministically(photo, required);
  assertEquals(coverageIsStructurallyValid(recovered.output, required), true);
  assertEquals(recovered.output.candidates.length, 1);
  assertEquals(
    recovered.output.module_coverage.find((item) =>
      item.module_id === "work_at_height"
    )?.outcome,
    "finding_present",
  );
  assertEquals(
    recovered.output.module_coverage.find((item) =>
      item.module_id === "lifting"
    )?.outcome,
    "not_assessable_due_to_image",
  );
  assertEquals(recovered.recoveredModules.includes("lifting"), true);
});

Deno.test("S: kritik sessiz düşme invariant'ı kaderi olmayan adayı durdurur", () => {
  const normalized = normalizeCandidates(output([candidate()]), 1);
  assertThrows(
    () => assertCriticalCandidateFates(normalized, [], []),
    Error,
    "critical_silent_drop",
  );
});

Deno.test("targeted queue Premium 2, Economy 1 ve belge konusu 0", () => {
  const photo = output([
    candidate({
      candidate_key: "a",
      occlusion: "substantial",
      confidence: { visibility: 0.5, localization: 0.5, mechanism: 0.6 },
    }),
    candidate({
      candidate_key: "b",
      module_id: "electrical",
      occlusion: "substantial",
      confidence: { visibility: 0.5, localization: 0.5, mechanism: 0.6 },
    }),
    candidate({
      candidate_key: "c",
      module_id: "lifting",
      occlusion: "substantial",
      confidence: { visibility: 0.5, localization: 0.5, mechanism: 0.6 },
    }),
    candidate({
      candidate_key: "document",
      requires_document_or_measurement: true,
      occlusion: "substantial",
    }),
  ]);
  const normalized = normalizeCandidates(photo, 1);
  assertEquals(buildTargetedQueue(normalized, "premium").selected.length, 2);
  assertEquals(buildTargetedQueue(normalized, "economy").selected.length, 1);
});

Deno.test("targeted çıktı bağımsız bulgu eklemez, primary adayı günceller", () => {
  const primary = normalizeCandidates(
    output([candidate({
      occlusion: "substantial",
      confidence: { visibility: 0.5, localization: 0.5, mechanism: 0.6 },
    })]),
    1,
  );
  const queue = buildTargetedQueue(primary, "premium").selected[0];
  const targeted = normalizeCandidates(
    output([candidate({
      candidate_key: "targeted",
      affirmative_cues: ["Ara korkuluk açıklığı net biçimde görülüyor"],
    })]),
    1,
  );
  const merged = mergeTargetedOutput(primary, queue, targeted);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].affirmative_cues.length, 2);
});

Deno.test("targeted karşıt kanıt primary kritik adayı açıklanabilir biçimde reddeder", () => {
  const primaryPhoto = output([candidate({
    occlusion: "substantial",
    confidence: { visibility: 0.4, localization: 0.4, mechanism: 0.5 },
  })]);
  const primary = normalizeCandidates(primaryPhoto, 1);
  const queue = buildTargetedQueue(primary, "premium");
  const targetedPhoto = output([]);
  targetedPhoto.module_coverage.push({
    module_id: "work_at_height",
    activated_by: ["targeted_region"],
    outcome: "no_actionable_issue_visible",
    entity_refs: ["platform-1"],
    candidate_keys: [],
    note: "Hedef bölgede sürekli üst ve ara korkuluk görülüyor",
  });
  const merged = mergeTargetedOutput(
    primary,
    queue.selected[0],
    [],
    targetedPhoto,
  );
  const routed = routeCandidates({
    candidates: merged,
    photoOutputs: [{ photoIndex: 1, output: primaryPhoto }],
    sectorID: "construction",
  });
  assertEquals(routed.items.length, 0);
  assertEquals(
    routed.hardRejections[0].reason_code,
    "targeted_visual_counter_evidence",
  );
});

Deno.test("200+ claim değerlendirme setinde her kritik adayın kaderi vardır", () => {
  for (let index = 0; index < 240; index += 1) {
    const criticality = index % 3 === 0
      ? "fatal"
      : index % 3 === 1
      ? "permanent"
      : "serious";
    const occlusion = index % 4 === 0 ? "substantial" : "none";
    const photo = output([candidate({
      candidate_key: `golden-${index}`,
      potential_consequence: criticality,
      occlusion,
      confidence: occlusion === "none"
        ? { visibility: 0.9, localization: 0.9, mechanism: 0.9 }
        : { visibility: 0.5, localization: 0.5, mechanism: 0.6 },
    })]);
    const normalized = normalizeCandidates(photo, 1);
    const routed = routeCandidates({
      candidates: normalized,
      photoOutputs: [{ photoIndex: 1, output: photo }],
      sectorID: "construction",
    });
    assertCriticalCandidateFates(
      normalized,
      routed.items,
      routed.hardRejections,
      routed.ledger,
    );
  }
});

Deno.test("aynı olay yolunda birleşen kritik kardeşlerin ledger kaderi sessiz düşme değildir", () => {
  const photo = output([
    candidate({ candidate_key: "edge-a" }),
    candidate({ candidate_key: "edge-b" }),
  ]);
  const normalized = normalizeCandidates(photo, 1);
  const routed = routeCandidates({
    candidates: normalized,
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(routed.items.length, 1);
  assertEquals(routed.ledger.length, 2);
  assertCriticalCandidateFates(
    normalized,
    routed.items,
    routed.hardRejections,
    routed.ledger,
  );
});

Deno.test("ölümcül aday, sıradan adayla aynı kanıt seviyesinde eşit muamele görür", () => {
  // Live run b5c46b89: three ordinary E3 candidates became findings while the
  // single fatal E3 candidate - accessible path, no occlusion - was demoted to
  // a verification request. The critical branch ran before the finding branch,
  // so severity raised the evidence bar instead of the consequence.
  const fatalAtE3 = candidate({
    candidate_key: "fatal-e3",
    raw_label: "Yüksekte çalışan personelin kenar koruması eksikliği",
    person_ref: "person_2",
    evidence_region: undefined,
    // partial occlusion pins the candidate at E3, which is where the live run
    // lost it.
    occlusion: "partial",
    affirmative_cues: [
      "binanın üst katında çalışan kişi",
      "kişinin çalıştığı alanın kenarında net bir kenar korumasının görünmemesi",
    ],
    counter_cues: [
      "kişinin tam olarak kenarda durmaması",
      "yapının geniş bir betonarme yüzeyi olması",
    ],
    confidence: { visibility: 0.7, localization: 0.7, mechanism: 0.8 },
  });
  const photo = output([fatalAtE3]);
  photo.people = [{
    id: "person_2",
    kind: "person",
    label: "üst katta çalışan",
    visible: true,
    accessible: true,
    region: { x: 0.4, y: 0.2, width: 0.1, height: 0.2 },
  }];
  const normalized = normalizeCandidates(photo, 1);
  const routed = routeCandidates({
    candidates: normalized,
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(normalized[0].evidence_level, "E3");
  assertEquals(normalized[0].criticality, "fatal");
  const item = routed.items.find((entry) => entry.candidate_id)!;
  assertEquals(item.item_class, "observed_finding");
  assertEquals(item.is_scored, true);
  assertEquals(item.fk_severity, 40);
  // The counter-cues the prompt asks for must not disqualify the claim.
  assertEquals(normalized[0].counter_cues.length, 2);
});

Deno.test("Türkçe ekli yokluk ifadeleri yapısal eksiklik olarak tanınır", () => {
  // "\beksik\b" never fires on "eksikliği": the suffix is word characters, so
  // the live fatal candidate was normalized as an ordinary condition.
  for (
    const label of [
      "kenar koruması eksikliği",
      "korkuluğun bulunmaması",
      "ara korkuluk görünmüyor",
      "etek tahtası mevcut değil",
      "kenar korunmasız durumda",
    ]
  ) {
    const photo = output([candidate({
      candidate_key: `abs-${label}`,
      raw_label: label,
      affirmative_cues: ["üst korkuluk görülüyor, aradaki açıklık kesintisiz"],
    })]);
    assertEquals(
      normalizeCandidates(photo, 1)[0].condition_code,
      "visible_structural_absence",
      label,
    );
  }
});

Deno.test("adayın işaret ettiği kişinin bölgesi yerelleştirme için devralınır", () => {
  const photo = output([candidate({
    person_ref: "worker-9",
    evidence_region: undefined,
  })]);
  photo.people = [{
    id: "worker-9",
    kind: "person",
    label: "çalışan",
    visible: true,
    region: { x: 0.3, y: 0.3, width: 0.2, height: 0.3 },
  }];
  const normalized = normalizeCandidates(photo, 1);
  assertEquals(normalized[0].evidence_region?.width, 0.2);
  assertEquals(normalized[0].evidence_level, "E5");
});

Deno.test("sıradan sonuç ilk yardım şiddetini alır, ciddi olanla eşitlenmez", () => {
  // severity() returned 7 for both "ordinary" and "serious", so a trip hazard
  // and an impalement were indistinguishable in the report.
  const trip = output([candidate({
    candidate_key: "trip-1",
    module_id: "housekeeping_physical_contact",
    raw_label: "Dağınık malzeme ve su birikintisi",
    person_ref: undefined,
    potential_consequence: "ordinary",
    affirmative_cues: ["yerde su birikintisi ve dağınık tahtalar"],
    event_path: {
      source: "ıslak ve dağınık zemin",
      contact_or_failure: "takılma",
      consequence: "yaralanma",
    },
  })]);
  const tripItem = routeCandidates({
    candidates: normalizeCandidates(trip, 1),
    photoOutputs: [{ photoIndex: 1, output: trip }],
    sectorID: "construction",
  }).items.find((item) => item.is_scored)!;
  assertEquals(tripItem.fk_severity, 3);

  const rebar = output([candidate({
    candidate_key: "rebar-1",
    module_id: "housekeeping_physical_contact",
    raw_label: "Açıkta kalan sivri donatı filizleri",
    person_ref: undefined,
    potential_consequence: "permanent",
    affirmative_cues: ["betonarme yapıdan uzanan sivri donatı uçları"],
    event_path: {
      source: "başlıksız donatı ucu",
      contact_or_failure: "saplanma",
      consequence: "kalıcı yaralanma",
    },
  })]);
  const rebarItem = routeCandidates({
    candidates: normalizeCandidates(rebar, 1),
    photoOutputs: [{ photoIndex: 1, output: rebar }],
    sectorID: "construction",
  }).items.find((item) => item.is_scored)!;
  assertEquals(rebarItem.fk_severity, 15);
  // Present on a reachable path: not "practically impossible".
  assertEquals(rebarItem.fk_probability, 3);
});

Deno.test("modül kimliği ve sahne kimliği kullanıcı metnine sızmaz", () => {
  const photo = output([candidate({
    raw_label:
      "Yüksekte çalışan personelin (person_2) kenar koruması eksikliği",
    person_ref: "person_2",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const published = JSON.stringify(
    routed.items.map((item) => ({
      title: item.title,
      category: item.category,
      description: item.description,
    })),
  );
  for (
    const leak of [
      "person_2",
      "work_at_height",
      "housekeeping_physical_contact",
      "people_exposure",
    ]
  ) {
    assertEquals(published.includes(leak), false, leak);
  }
  assertStringIncludes(published, "Yüksekte çalışma");
});

Deno.test("kritik adayın bulguya dönüşmemesi kayıt altına alınır", () => {
  // The invariant treated any record as success, so the demotion that hid a
  // fatal hazard among the field-check items reported zero silent drops.
  const occluded = candidate({
    candidate_key: "occluded-critical",
    occlusion: "substantial",
    evidence_region: undefined,
    confidence: { visibility: 0.3, localization: 0.3, mechanism: 0.4 },
  });
  const photo = output([occluded]);
  const normalized = normalizeCandidates(photo, 1);
  const routed = routeCandidates({
    candidates: normalized,
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertCriticalCandidateFates(
    normalized,
    routed.items,
    routed.hardRejections,
    routed.ledger,
  );
  // Genuinely occluded: demotion is correct and must not be flagged.
  assertEquals(criticalDemotions.length, 0);

  const visible = output([candidate({ candidate_key: "visible-critical" })]);
  const visibleNormalized = normalizeCandidates(visible, 1);
  const visibleRouted = routeCandidates({
    candidates: visibleNormalized,
    photoOutputs: [{ photoIndex: 1, output: visible }],
    sectorID: "construction",
  });
  assertCriticalCandidateFates(
    visibleNormalized,
    visibleRouted.items,
    visibleRouted.hardRejections,
    visibleRouted.ledger,
  );
  assertEquals(criticalDemotions.length, 0);
});

Deno.test("su içindeki kablo belge konusu değil, doğrulama konusudur", () => {
  // Live run 5093c58b: cables in standing water arrived fatal at E4 with an
  // accessible path and were published as an unscored "electrical integrity"
  // paperwork item, because the model also ticked
  // requires_document_or_measurement. The counter-cues named exactly what was
  // unresolved.
  const photo = output([candidate({
    candidate_key: "electrical_cables_in_puddles",
    module_id: "electrical",
    raw_label: "Yerdeki elektrik kablolarının su birikintileriyle teması",
    asset_ref: "electrical_cables_ground",
    requires_document_or_measurement: true,
    affirmative_cues: [
      "Yerdeki siyah kablolar su birikintilerinin içinden geçiyor",
    ],
    counter_cues: [
      "Kabloların enerjili olup olmadığı görsel olarak belirlenemiyor",
      "kabloların yalıtım durumu görsel olarak belirlenemiyor",
    ],
  })]);
  const normalized = normalizeCandidates(photo, 1);
  assertEquals(normalized[0].condition_code, "electrical_identity_unresolved");
  const routed = routeCandidates({
    candidates: normalized,
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const item = routed.items.find((entry) => entry.candidate_id)!;
  assertEquals(item.item_class, "verification_request");
});

Deno.test("yüksekte kemer eksikliği düşme şiddetini alır, 15'e kırpılmaz", () => {
  // people_exposure had no mechanism entry, so a worker at an unprotected edge
  // with no harness capped at 15 while the edge beside it scored 40.
  const photo = output([candidate({
    candidate_key: "person_2_no_fall_protection",
    module_id: "people_exposure",
    raw_label:
      "Yüksekte, korumasız kenara yakın çalışanın paraşüt tipi emniyet kemeri kullanmaması",
    person_ref: "worker-2",
    affirmative_cues: [
      "Çatı kenarına yakın çalışanın gövdesinde kemer veya lanyard görünmüyor",
    ],
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const item = routed.items.find((entry) => entry.is_scored)!;
  assertEquals(item.fk_severity, 40);
  assertEquals(
    item.title,
    "Yüksekte çalışanda düşme durdurma sistemi bulunmaması",
  );
});

Deno.test("iki farklı düşme tehlikesi aynı başlıkla yayınlanmaz", () => {
  // The roof edge and the scaffold mid-rail were both published as "Çalışma
  // kenarında düşmeye karşı koruma eksikliği" at FK 1440.
  const photo = output([
    candidate({
      candidate_key: "unprotected_roof_edge",
      module_id: "falls_falling_objects",
      raw_label: "Bina çatısında kenar koruması olmadan çalışma",
      affirmative_cues: ["Çatı kenarı boyunca korkuluk bulunmuyor"],
    }),
    candidate({
      candidate_key: "scaffolding_missing_midrail",
      module_id: "falls_falling_objects",
      raw_label: "İskelenin üst platformunda ara korkuluk eksikliği",
      evidence_region: { x: 0.6, y: 0.3, width: 0.2, height: 0.2 },
      affirmative_cues: [
        "İskele platformunda üst korkuluk mevcut, ara korkuluk yok",
      ],
      // Distinct event path: the dedup key is semantic, and two hazards that
      // genuinely share one are meant to merge.
      event_path: {
        source: "iskele platformu korkuluk boşluğu",
        contact_or_failure: "boşluktan düşme",
        consequence: "ölümcül yaralanma",
      },
    }),
  ]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const titles = routed.items.filter((item) => item.is_scored).map((item) =>
    String(item.title)
  );
  assertEquals(new Set(titles).size, titles.length, titles.join(" | "));
  assertEquals(
    titles.includes("Korkuluk sisteminde ara korkuluk eksikliği"),
    true,
  );
  assertEquals(
    titles.includes("Çatı kenarında düşmeye karşı koruma bulunmaması"),
    true,
  );
});

Deno.test("aynı anahtarı üreten iki fotoğraf koşuyu düşürmez", () => {
  // analysis_claim_candidates is unique on (engine_run_id, candidate_key), but
  // the provider only guarantees uniqueness inside one photo. A 3-photo run
  // whose photos both produced "unprotected_roof_edge" failed the whole
  // analysis with v4_finalize_failed, after all three model calls were paid.
  const shared = candidate({ candidate_key: "unprotected_roof_edge" });
  const photoOne = output([shared]);
  const photoTwo = output([shared]);
  const keys = [
    ...normalizeCandidates(photoOne, 1),
    ...normalizeCandidates(photoTwo, 2),
  ].map((item) => item.candidate_key);
  assertEquals(keys.length, 2);
  assertEquals(new Set(keys).size, 2, keys.join(" | "));
  assertStringIncludes(keys[0], "unprotected_roof_edge");
});

Deno.test("falls modülünün kendi adı mekanizmayı düşen cisme çeviremez", () => {
  // `falls_falling_objects` metni "falling" ve "object" içerdiği için mekanizma
  // testi her adayda eşleşiyordu; ara korkuluk eksikliği düşen cisim sayılıp
  // kısmi bariyer tavanını atlıyor ve FK 720 / critical yayınlanıyordu.
  const photo = output([candidate({
    candidate_key: "midrail-gap",
    module_id: "falls_falling_objects",
    raw_label: "Korumasız kenar",
    affirmative_cues: [
      "Üst korkuluk ve etek tahtası mevcutken ara korkuluğun bir kısmı eksik",
    ],
    event_path: {
      source: "korumasız kenar",
      contact_or_failure: "kişinin düşmesi",
      consequence: "yüksekten düşme",
    },
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const item = routed.items[0];
  assertEquals(item.score_payload?.mechanism_code, "fall_from_height");
  assertEquals(item.fk_severity, 15);
  assertEquals(item.score_payload?.severity_cap, 15);
  assertEquals(item.fk_band, "high");
  assertEquals(item.recommended_action.includes("düşen cisim"), false);
});

Deno.test("gerçek düşen cisim kanıtı düşen cisim mekanizmasını korur", () => {
  const photo = output([candidate({
    candidate_key: "falling-load",
    module_id: "falls_falling_objects",
    raw_label: "Kenarda istiflenmiş malzeme",
    affirmative_cues: [
      "Platform kenarında istiflenmiş malzeme; altta geçiş yolu görülüyor",
    ],
    event_path: {
      source: "kenardaki istif",
      contact_or_failure: "malzemenin devrilmesi",
      consequence: "düşen cisim çarpması",
    },
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(routed.items[0].score_payload?.mechanism_code, "falling_object");
});

Deno.test("ıslaklık kanıtı yokken başlık ıslak zemin iddia etmez", () => {
  const photo = output([candidate({
    candidate_key: "clutter",
    module_id: "housekeeping_physical_contact",
    raw_label: "Zeminde dağınık malzeme",
    affirmative_cues: [
      "Zeminde karton parçaları; zeminde çeşitli küçük eşyalar",
    ],
    event_path: {
      source: "zemindeki malzeme",
      contact_or_failure: "kişinin eşyalara takılması",
      consequence: "düşme ve yaralanma",
    },
    potential_consequence: "ordinary",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(routed.items[0].title.includes("ıslak"), false);
  assertEquals(routed.items[0].title.includes("Islak"), false);
  assertStringIncludes(routed.items[0].title, "takılma");
});

Deno.test("gözlem açıklaması büyük harfle başlar", () => {
  const photo = output([candidate({
    affirmative_cues: ["üst korkuluk görülüyor; ara korkuluk eksik"],
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const first = routed.items[0].description.charAt(0);
  assertEquals(first, first.toLocaleUpperCase("tr-TR"));
});

Deno.test("çözülemeyen modül sessizce düşmez, doğrulama isteği olur", () => {
  const photo = output([candidate()]);
  photo.module_coverage = photo.module_coverage.map((entry) =>
    entry.module_id === "energy"
      ? {
        ...entry,
        outcome: "unresolved_requires_verification" as const,
        candidate_keys: [],
        note: "Enerji hattı bölgesi kısmen örtülü",
      }
      : entry
  );
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
    referencePolicy: "tr_current",
  });
  const unresolved = routed.items.find((item) =>
    item.internal_priority.route_reason === "module_coverage_unresolved"
  );
  assertEquals(unresolved?.item_class, "verification_request");
  assertEquals(unresolved?.is_scored, false);
  assertEquals(unresolved?.category, "Tehlikeli enerji");
  assertEquals(unresolved?.title.includes("energy"), false);
  assertStringIncludes(unresolved?.recommended_measures[0].text ?? "", "1. ");
  assertStringIncludes(unresolved?.references_text ?? "", "TS EN ISO 14118");
});

Deno.test("skorsuz güvence maddesi ayrıntılı saha adımı ve standart taşır", () => {
  const photo = output([candidate({
    candidate_key: "tank-integrity",
    module_id: "process_integrity",
    raw_label: "Depolama tankı ve borulama",
    asset_ref: "platform-1",
    requires_document_or_measurement: true,
    affirmative_cues: ["Tank gövdesi ve bağlı borulama görülüyor"],
    event_path: {
      source: "tank gövdesi",
      contact_or_failure: "bütünlük kaybı",
      consequence: "salım",
    },
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
    referencePolicy: "tr_current",
  });
  const assurance = routed.items.find((item) =>
    item.item_class === "assurance_requirement"
  );
  assertEquals(assurance?.recommended_measures.length, 2);
  assertStringIncludes(assurance?.recommended_measures[0].text ?? "", "API 653");
  assertStringIncludes(assurance?.recommended_measures[0].text ?? "", "API 570");
  assertStringIncludes(assurance?.references_text ?? "", "API 510");
});

Deno.test("referansa izin vermeyen profilde standart metni boş kalır", () => {
  const photo = output([candidate({
    candidate_key: "tank-integrity-en",
    module_id: "process_integrity",
    asset_ref: "platform-1",
    requires_document_or_measurement: true,
    raw_label: "Depolama tankı",
    affirmative_cues: ["Tank gövdesi görülüyor"],
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
    referencePolicy: "none",
  });
  for (const item of routed.items) assertEquals(item.references_text, "");
});

Deno.test("skorsuz madde başlıkları sınıf etiketini tekrarlamaz", () => {
  const photo = output([candidate()]);
  photo.scene_entities = [
    ...photo.scene_entities,
    {
      id: "tank-1",
      kind: "process_vessel",
      label: "Sol proses tankı",
      visible: true,
      accessible: true,
    },
  ];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const assurance = routed.items.find((item) =>
    item.item_class === "assurance_requirement"
  );
  assertEquals(assurance?.title, "Proses tankı ve borulama bütünlüğü");
  for (const item of routed.items) {
    assertEquals(item.title.includes("saha teyidi"), false);
    assertEquals(item.title.includes("saha doğrulaması gerekli"), false);
    assertEquals(item.title.includes("saha güvencesi gerekli"), false);
  }
});

Deno.test("ipucu metni noktayla bitse de açıklamada çift nokta olmaz", () => {
  const photo = output([candidate({
    affirmative_cues: [
      "Üst platformun sağ tarafındaki makinede açıkta dönen şaft görülmektedir.",
    ],
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(routed.items[0].description.includes(".."), false);
});

Deno.test("rapor bütçesi tank güvencesini alfabeye göre atmaz", () => {
  // abeb5b5b'nin birebir şekli: dört gözlem, bir doğrulama isteği ve dört
  // güvence. Eski bütçe dokuzuncu maddeyi kesiyordu ve kesilen, adı Türk
  // alfabesinde sona düşen "Proses bütünlüğü" oluyordu.
  const unscored = [
    { topic: "process_containment_integrity", title: "Proses tankı" },
    { topic: "lifting_inspection", title: "Kaldırma ekipmanı" },
    { topic: "machine_protective_systems", title: "Makine koruyucuları" },
    { topic: "mobile_equipment_controls", title: "Hareketli ekipman" },
    { topic: "biosecurity_controls", title: "Biyogüvenlik" },
    { topic: "fire_emergency_readiness", title: "Yangın hazırlığı" },
    { topic: "asset_assurance_generic", title: "Genel varlık" },
  ];
  const ranked = [...unscored].sort((a, b) =>
    topicConsequenceRank(a.topic) - topicConsequenceRank(b.topic)
  );
  assertEquals(ranked[0].title, "Proses tankı");
  assertEquals(ranked[ranked.length - 1].title, "Genel varlık");
  assertEquals(
    topicConsequenceRank("process_containment_integrity") <
      topicConsequenceRank("machine_protective_systems"),
    true,
  );
  assertEquals(
    topicConsequenceRank("lifting_inspection") <
      topicConsequenceRank("mobile_equipment_controls"),
    true,
  );
});

Deno.test("her skorsuz madde bütçe sıralaması için consequence_rank taşır", () => {
  const photo = output([candidate()]);
  photo.scene_entities = [
    ...photo.scene_entities,
    {
      id: "tank-1",
      kind: "process_vessel",
      label: "Sol proses tankı",
      visible: true,
      accessible: true,
    },
    {
      id: "crane-1",
      kind: "asset",
      label: "gezer köprülü vinç",
      visible: true,
      accessible: true,
    },
  ];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const unscored = routed.items.filter((item) =>
    ["assurance_requirement", "verification_request"].includes(item.item_class)
  );
  assertEquals(unscored.length > 0, true);
  for (const item of unscored) {
    assertEquals(typeof item.internal_priority.consequence_rank, "number");
  }
  const tank = unscored.find((item) =>
    item.internal_priority.assurance_topic_id ===
      "process_containment_integrity"
  );
  const crane = unscored.find((item) =>
    item.internal_priority.assurance_topic_id === "lifting_inspection"
  );
  assertEquals(
    (tank?.internal_priority.consequence_rank as number) <
      (crane?.internal_priority.consequence_rank as number),
    true,
  );
});

Deno.test("skorlu bulgu jenerik tek cümle yerine mekanizmaya özgü adım taşır", () => {
  const photo = output([candidate({
    candidate_key: "hook-latch",
    module_id: "lifting",
    raw_label: "Vinç kancasında emniyet mandalı yok",
    affirmative_cues: ["Üst vincin kancasında mandal mekanizması görünmüyor"],
    event_path: {
      source: "vinç kancası",
      contact_or_failure: "kancadan yükün ayrılması",
      consequence: "yükün düşmesi",
    },
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const item = routed.items[0];
  const corrective = item.recommended_measures[0].text;
  assertEquals(item.recommended_measures[0].kind, "corrective");
  assertStringIncludes(corrective, "1. ");
  assertStringIncludes(corrective, "3. ");
  assertStringIncludes(corrective, "mandal");
  assertEquals(
    corrective.includes("görünen fiziksel koşulu güvenli hale getirin"),
    false,
  );
  assertEquals(
    item.recommended_measures[1].text.includes(
      "sorumluluk, kontrol sıklığı ve fiziksel koruma standardını belirleyin",
    ),
    false,
  );
});

Deno.test("kök neden modülden değil mekanizmadan gelir", () => {
  // Kepçeden düşen malzemeye korkuluk kök nedeni yazılıyordu: aynı modülü
  // kenar koruması ile paylaşıyor.
  const bucket = output([candidate({
    candidate_key: "bucket-spill",
    module_id: "falls_falling_objects",
    raw_label: "Ekskavatör kepçesinden düşen malzeme",
    affirmative_cues: ["Kepçe toprak kazıyor; gevşek taşlar kepçeden düşüyor"],
    event_path: {
      source: "ekskavatör kepçesi",
      contact_or_failure: "malzemenin düşmesi",
      consequence: "çarpma",
    },
    potential_consequence: "serious",
  })]);
  const routedBucket = routeCandidates({
    candidates: normalizeCandidates(bucket, 1),
    photoOutputs: [{ photoIndex: 1, output: bucket }],
    sectorID: "construction",
  });
  assertEquals(
    routedBucket.items[0].score_payload?.mechanism_code,
    "falling_object",
  );
  assertEquals(
    routedBucket.items[0].root_cause_text.includes("çalışma kenarında"),
    false,
  );
  assertStringIncludes(routedBucket.items[0].root_cause_text, "düşme yolu");
});

Deno.test("etek tahtası eksikken nesne düşmesi kişi düşmesi sayılmaz", () => {
  const photo = output([candidate({
    candidate_key: "toeboard-gap",
    module_id: "falls_falling_objects",
    raw_label: "Platform kenarında etek tahtası eksik",
    affirmative_cues: ["Orta korkuluk altında boşluk; etek tahtası yok"],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "nesne düşmesi",
      consequence: "aşağıdaki kişiye çarpma",
    },
    potential_consequence: "serious",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routed.items[0].score_payload?.mechanism_code,
    "falling_object",
  );
});

Deno.test("yüksek basınçlı hidrolik hat enerji modülünde jenerike düşmez", () => {
  const photo = output([candidate({
    candidate_key: "hydraulic-line",
    module_id: "energy",
    raw_label: "Ekskavatör kolu üzerindeki yüksek basınçlı hidrolik hatlar",
    affirmative_cues: ["Kol boyunca uzanan hidrolik hortumlar; hidrolik silindirler"],
    event_path: {
      source: "hidrolik hat",
      contact_or_failure: "hattın yırtılması",
      consequence: "sıvı enjeksiyonu",
    },
    potential_consequence: "permanent",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const item = routed.items[0];
  assertEquals(
    item.score_payload?.mechanism_code,
    "hydraulic_pneumatic_release",
  );
  assertStringIncludes(item.recommended_measures[0].text, "basınc");
  assertStringIncludes(item.root_cause_text, "asınçlı akışkan hattının");
});

Deno.test("her mekanizmanın kök nedeni ve en az üç adımı vardır", () => {
  const mechanisms = [
    "fall_from_height",
    "falling_object",
    "caught_in_pinch_shear",
    "vehicle_equipment_strike",
    "electrical_contact_arc",
    "hydraulic_pneumatic_release",
    "mechanical_separation_release",
    "fire_explosion",
    "chemical_contact_release",
    "excavation_collapse_rockfall",
    "structural_collapse",
    "equipment_overturn",
    "thermal_contact",
    "sharp_edge_contact",
    "fall_same_level",
    "ergonomic_overexertion",
    "environmental_release",
    "other_visible_physical",
  ];
  for (const mechanism of mechanisms) {
    const playbook = controlPlaybook(mechanism);
    assertEquals(playbook.corrective.length >= 3, true);
    assertEquals(playbook.rootCause.length > 40, true);
    assertEquals(playbook.preventive.length > 40, true);
  }
});

Deno.test("modelin olumlu kontrolüyle çelişen yokluk iddiası skorlanmaz", () => {
  // 4534c158: dört korkuluk adayı da yokluk iddia etti, fotoğrafta üç eleman da
  // yerindeydi. Model aynı fotoğrafta elemanın varlığını beyan ettiyse kendi
  // kendisiyle çelişiyordur; doğru çıktı skorlu bulgu değil saha teyididir.
  const photo = output([candidate({
    candidate_key: "toeboard-absent",
    module_id: "falls_falling_objects",
    raw_label: "Alt platform korkuluğunda etek tahtası eksikliği",
    affirmative_cues: [
      "alt platformun kenarındaki sarı korkulukta etek tahtası bulunmamaktadır",
    ],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "nesne düşmesi",
      consequence: "alttaki kişiye çarpma",
    },
    potential_consequence: "serious",
  })]);
  photo.positive_controls = [{
    control_key: "rail-complete",
    module_id: "falls_falling_objects",
    description:
      "Alt platformda tam korkuluk sistemi (üst korkuluk, ara korkuluk, etek tahtası) mevcuttur.",
    affirmative_cues: ["sarı üst korkuluk", "ara korkuluk", "etek tahtası"],
    evidence_region: { x: 0.1, y: 0.2, width: 0.3, height: 0.2 },
  }];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const item = routed.items.find((entry) => entry.candidate_id);
  assertEquals(item?.item_class, "verification_request");
  assertEquals(item?.is_scored, false);
  assertStringIncludes(
    String(item?.internal_priority.route_reason),
    "provider_self_contradiction",
  );
});

Deno.test("çelişki yoksa yokluk iddiası skorlu bulgu olarak kalır", () => {
  const photo = output([candidate({
    candidate_key: "toeboard-absent-2",
    module_id: "falls_falling_objects",
    raw_label: "Platform korkuluğunda etek tahtası eksikliği",
    affirmative_cues: ["korkulukta etek tahtası bulunmamaktadır"],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "nesne düşmesi",
      consequence: "alttaki kişiye çarpma",
    },
    potential_consequence: "serious",
  })]);
  photo.positive_controls = [{
    control_key: "top-rail-only",
    module_id: "falls_falling_objects",
    description: "Platform kenarında sarı üst korkuluk mevcuttur.",
    affirmative_cues: ["sarı üst korkuluk"],
    evidence_region: { x: 0.1, y: 0.2, width: 0.3, height: 0.2 },
  }];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const item = routed.items.find((entry) => entry.candidate_id);
  assertEquals(item?.item_class, "observed_finding");
  assertEquals(item?.is_scored, true);
});

Deno.test("engebeli kayalık zemin dağınık malzeme başlığını almaz", () => {
  const rocky = output([candidate({
    candidate_key: "rocky-ground",
    module_id: "housekeeping_physical_contact",
    raw_label: "Engebeli, kayalık zemin",
    affirmative_cues: ["engebeli ve kayalık zemin görülüyor"],
    event_path: {
      source: "engebeli zemin",
      contact_or_failure: "kişinin takılması",
      consequence: "düşme",
    },
    potential_consequence: "ordinary",
  })]);
  const routedRocky = routeCandidates({
    candidates: normalizeCandidates(rocky, 3),
    photoOutputs: [{ photoIndex: 3, output: rocky }],
    sectorID: "construction",
  });
  const clutter = output([candidate({
    candidate_key: "clutter-ground",
    module_id: "housekeeping_physical_contact",
    raw_label: "Zeminde dağınık malzemeler",
    affirmative_cues: ["zeminde karton kutular ve dağınık eşyalar"],
    event_path: {
      source: "zemindeki malzeme",
      contact_or_failure: "kişinin takılması",
      consequence: "düşme",
    },
    potential_consequence: "ordinary",
  })]);
  const routedClutter = routeCandidates({
    candidates: normalizeCandidates(clutter, 2),
    photoOutputs: [{ photoIndex: 2, output: clutter }],
    sectorID: "manufacturing",
  });
  assertStringIncludes(routedRocky.items[0].title, "Engebeli");
  assertStringIncludes(routedClutter.items[0].title, "dağınık");
  assertEquals(routedRocky.items[0].title === routedClutter.items[0].title, false);
});

Deno.test("olumlu kontrol adayı hariç tutuyorsa bu çelişki sayılmaz", () => {
  // Model "Korkuluklarda ara korkuluk mevcut (C1 hariç)" yazdığında kendisiyle
  // çelişmiyor; tutarlı konuşuyor. Bunu düz onay saymak, gerçekten tek gözde
  // ara korkuluğu eksik olan bir korkuluğu da bastırırdı.
  const photo = output([candidate({
    candidate_key: "C1",
    module_id: "falls_falling_objects",
    raw_label: "Korkulukta ara korkuluk eksikliği",
    affirmative_cues: ["üst korkuluk ile etek tahtası arasında ara korkuluk bulunmuyor"],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "kişinin boşluktan düşmesi",
      consequence: "yüksekten düşme",
    },
    potential_consequence: "fatal",
  })]);
  photo.positive_controls = [{
    control_key: "midrail-general",
    module_id: "falls_falling_objects",
    description: "Korkuluklarda ara korkuluk mevcut (C1 hariç).",
    affirmative_cues: ["Sarı metal ara korkuluk görünür"],
    evidence_region: { x: 0.1, y: 0.2, width: 0.3, height: 0.2 },
  }];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const item = routed.items.find((entry) => entry.candidate_id);
  // Çelişki değil ama yerel bir boşluk iddiası: düz fotoğraftan çözülemez.
  assertEquals(item?.item_class, "verification_request");
  assertStringIncludes(
    String(item?.internal_priority.route_reason),
    "localized_barrier_gap_unresolved",
  );
  assertEquals(
    String(item?.internal_priority.route_reason).includes(
      "provider_self_contradiction",
    ),
    false,
  );
});

Deno.test("elemanın tamamen yokluğu skorlu bulgu olarak kalır", () => {
  // Yalnız üst korkuluğu olan korkuluk gerçek ve yaygın bir kusur; hiçbir kapı
  // bunu doğrulama isteğine düşürmemeli.
  const photo = output([candidate({
    candidate_key: "C9",
    module_id: "falls_falling_objects",
    raw_label: "Korkulukta ara korkuluk eksikliği",
    affirmative_cues: ["üst korkuluk mevcut; ara korkuluk hiçbir gözde bulunmuyor"],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "kişinin boşluktan düşmesi",
      consequence: "yüksekten düşme",
    },
    potential_consequence: "fatal",
  })]);
  photo.positive_controls = [{
    control_key: "toprail-only",
    module_id: "falls_falling_objects",
    description: "Korkuluklarda üst korkuluk mevcut.",
    affirmative_cues: ["Sarı metal üst korkuluk görünür"],
    evidence_region: { x: 0.1, y: 0.2, width: 0.3, height: 0.2 },
  }];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const item = routed.items.find((entry) => entry.candidate_id);
  assertEquals(item?.item_class, "observed_finding");
  assertEquals(item?.is_scored, true);
});

Deno.test("aynı cümlede var denen eleman yok sayılmaz", () => {
  // "üst korkuluk mevcut; ara korkuluk bulunmuyor" ifadesinde yalnız ara
  // korkuluk yokluk iddiasıdır.
  const photo = output([candidate({
    candidate_key: "C7",
    module_id: "falls_falling_objects",
    raw_label: "Korkulukta ara korkuluk eksikliği",
    affirmative_cues: [
      "üst korkuluk mevcut; etek tahtası mevcut; ara korkuluk bulunmuyor",
    ],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "kişinin boşluktan düşmesi",
      consequence: "yüksekten düşme",
    },
    potential_consequence: "fatal",
  })]);
  photo.positive_controls = [{
    control_key: "toprail",
    module_id: "falls_falling_objects",
    description: "Korkuluklarda üst korkuluk ve etek tahtası mevcut.",
    affirmative_cues: ["üst korkuluk", "etek tahtası"],
    evidence_region: { x: 0.1, y: 0.2, width: 0.3, height: 0.2 },
  }];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const item = routed.items.find((entry) => entry.candidate_id);
  // Üst korkuluk ve etek tahtası hakkında çelişki yok; ara korkuluk hakkında
  // olumlu kontrol de yok. Skorlu kalmalı.
  assertEquals(item?.item_class, "observed_finding");
  assertEquals(item?.is_scored, true);
});

Deno.test("zemine dağılmış donatı saplanma bulgusu sayılmaz", () => {
  // 35264d07: çamurlu zemin, su birikintileri ve dağınık demir donatı,
  // "Açıkta kalan sivri filiz veya donatı uçları (2)" başlığıyla ve
  // sharp_edge_contact mekanizmasıyla yayınlanmıştı.
  const clutter = output([candidate({
    candidate_key: "ground-rebar",
    module_id: "housekeeping_physical_contact",
    raw_label: "Düzensiz zemin, su birikintileri ve dağınık malzemeler",
    affirmative_cues: [
      "zemin çamurlu ve düzensiz",
      "demir donatılar ve diğer inşaat malzemeleri geçiş yollarında dağınık halde",
    ],
    event_path: {
      source: "Düzensiz zemin ve dağınık malzemeler",
      contact_or_failure: "Takılma, kayma veya düşme",
      consequence: "Aynı seviyede düşme",
    },
    potential_consequence: "ordinary",
  })]);
  const routedClutter = routeCandidates({
    candidates: normalizeCandidates(clutter, 1),
    photoOutputs: [{ photoIndex: 1, output: clutter }],
    sectorID: "construction",
  });
  assertEquals(
    routedClutter.items[0].score_payload?.mechanism_code,
    "fall_same_level",
  );
  assertEquals(routedClutter.items[0].title.includes("saplanma"), false);
  assertEquals(routedClutter.items[0].title.includes("donatı uçları"), false);
  assertEquals(
    routedClutter.items[0].root_cause_text.includes("sivri"),
    false,
  );

  const protruding = output([candidate({
    candidate_key: "starter-bars",
    module_id: "housekeeping_physical_contact",
    raw_label: "Açıkta kalan sivri filiz/donatı uçları",
    affirmative_cues: [
      "beton kolonların üst kısımlarından sivri demir donatı uçları çıkıntı yapıyor",
    ],
    event_path: {
      source: "Açıkta kalan sivri donatı ucu",
      contact_or_failure: "Düşme veya temas",
      consequence: "Saplanma yaralanması",
    },
    potential_consequence: "permanent",
  })]);
  const routedProtruding = routeCandidates({
    candidates: normalizeCandidates(protruding, 1),
    photoOutputs: [{ photoIndex: 1, output: protruding }],
    sectorID: "construction",
  });
  assertEquals(
    routedProtruding.items[0].score_payload?.mechanism_code,
    "sharp_edge_contact",
  );
  assertStringIncludes(routedProtruding.items[0].title, "donatı uçları");
});

Deno.test("sahne kimliği ekli hâlde de kullanıcı metnine sızmaz", () => {
  const photo = output([candidate({
    affirmative_cues: [
      "person_2 yükseltilmiş döşemede çalışıyor",
      "person_2'de kişisel düşme önleyici sistem görünmüyor",
    ],
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  const text = routed.items[0].description;
  assertEquals(text.includes("person"), false);
  assertEquals(text.includes("'de"), false);
  assertEquals(text.includes("_2"), false);
  assertStringIncludes(text, "çalışanda");
});

Deno.test("kısmi bariyer tavanı fiil seçimine göre değişmez", () => {
  const build = (cue: string) =>
    output([candidate({
      candidate_key: `rail-${cue.length}`,
      module_id: "falls_falling_objects",
      raw_label: "İskele platformunda eksik ara korkuluk",
      affirmative_cues: ["platformda üst korkuluk mevcut", cue],
      event_path: {
        source: "iskele platformu kenarı",
        contact_or_failure: "kişinin denge kaybı",
        consequence: "yüksekten düşme",
      },
      potential_consequence: "fatal",
    })]);
  for (
    const cue of [
      "ara korkuluk ve etek tahtası görünmüyor",
      "ara korkuluk ve etek tahtası eksik",
      "ara korkuluk ve etek tahtası mevcut değil",
    ]
  ) {
    const photo = build(cue);
    const routed = routeCandidates({
      candidates: normalizeCandidates(photo, 1),
      photoOutputs: [{ photoIndex: 1, output: photo }],
      sectorID: "construction",
    });
    assertEquals(routed.items[0].score_payload?.severity_cap, 15);
    assertEquals(routed.items[0].fk_severity, 15);
  }
});

Deno.test("uzun malzeme çarpması zorlanma tavanına kırpılmaz", () => {
  const photo = output([candidate({
    candidate_key: "carry-strike",
    module_id: "people_exposure",
    raw_label: "Uzun malzeme taşıyan kişinin çevresindeki tehlikeler",
    affirmative_cues: ["omzunda uzun, sert bir nesne taşıyor"],
    event_path: {
      source: "Uzun malzeme taşıma",
      contact_or_failure: "Malzemenin kayması veya çarpması",
      consequence: "Kişinin nesne tarafından çarpılması",
    },
    potential_consequence: "serious",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "construction",
  });
  assertEquals(
    routed.items[0].score_payload?.mechanism_code === "ergonomic_overexertion",
    false,
  );
});

Deno.test("kaplin ayrılması hidrolik enjeksiyon tavanına kırpılmaz", () => {
  // 1e738d1c: en ağır aday (fatal, kaplin ayrılması) 15 tavanını aldı, yanındaki
  // iki hafif korozyon bulgusu 40 tavanındaydı.
  const separation = output([candidate({
    candidate_key: "coupling-pin",
    module_id: "process_integrity",
    raw_label: "Hortum bağlantı elemanında emniyet pimi eksik",
    affirmative_cues: ["bağlantı pimi üzerinde bükülmüş gevşek bir tel parçası var"],
    event_path: {
      source: "Basınçlı hortum bağlantısı",
      contact_or_failure: "Emniyet pimi arızası",
      consequence: "Bağlantının ayrılması ve basınçlı akışkanın kontrolsüz salınımı",
    },
    potential_consequence: "fatal",
  })]);
  const routedSep = routeCandidates({
    candidates: normalizeCandidates(separation, 1),
    photoOutputs: [{ photoIndex: 1, output: separation }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routedSep.items[0].score_payload?.mechanism_code,
    "mechanical_separation_release",
  );
  assertEquals(routedSep.items[0].score_payload?.severity_cap, 40);
  assertEquals(routedSep.items[0].fk_severity, 40);

  const injection = output([candidate({
    candidate_key: "pinhole-jet",
    module_id: "process_integrity",
    raw_label: "Hidrolik hortumda iğne deliği sızıntısı",
    affirmative_cues: ["hidrolik hortumda ince püskürme izi"],
    event_path: {
      source: "Hidrolik hat",
      contact_or_failure: "İğne deliğinden püskürme",
      consequence: "Deri altına sıvı enjeksiyonu",
    },
    potential_consequence: "permanent",
  })]);
  const routedInj = routeCandidates({
    candidates: normalizeCandidates(injection, 1),
    photoOutputs: [{ photoIndex: 1, output: injection }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routedInj.items[0].score_payload?.mechanism_code,
    "hydraulic_pneumatic_release",
  );
});

Deno.test("görünen hortum ve kaplin güvence maddesi üretir", () => {
  const photo = output([candidate()]);
  photo.scene_entities = [
    ...photo.scene_entities,
    {
      id: "hose-1",
      kind: "asset",
      label: "Hortum",
      visible: true,
      accessible: true,
    },
    {
      id: "coupling-1",
      kind: "asset",
      label: "Paslı bağlantı elemanı",
      visible: true,
      accessible: true,
    },
  ];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
    referencePolicy: "tr_current",
  });
  // Hose assemblies carry their own topic: same non-visual assurance, but the
  // tank copy and the API tank standards do not describe them.
  const assurance = routed.items.find((item) =>
    item.internal_priority.assurance_topic_id === "hose_assembly_integrity"
  );
  assertEquals(assurance?.item_class, "assurance_requirement");
  assertStringIncludes(assurance?.references_text ?? "", "TS EN ISO 4413");
});

Deno.test("aynı modüldeki farklı mekanizmalar aynı öneriyi almaz", () => {
  const build = (key: string, cons: string, path: Record<string, string>) =>
    output([candidate({
      candidate_key: key,
      module_id: "process_integrity",
      raw_label: key,
      affirmative_cues: [cons],
      event_path: path as never,
      potential_consequence: "serious",
    })]);
  const sep = build("ayrilma", "kaplin gevşek", {
    source: "hortum bağlantısı",
    contact_or_failure: "bağlantının ayrılması",
    consequence: "basıncın boşalması",
  });
  const inj = build("enjeksiyon", "ince püskürme", {
    source: "hidrolik hat",
    contact_or_failure: "püskürme",
    consequence: "deri altına enjeksiyon",
  });
  const a = routeCandidates({
    candidates: normalizeCandidates(sep, 1),
    photoOutputs: [{ photoIndex: 1, output: sep }],
    sectorID: "manufacturing",
  }).items[0];
  const b = routeCandidates({
    candidates: normalizeCandidates(inj, 1),
    photoOutputs: [{ photoIndex: 1, output: inj }],
    sectorID: "manufacturing",
  }).items[0];
  assertEquals(a.recommended_action === b.recommended_action, false);
  assertStringIncludes(b.recommended_action, "basıncı kontrollü boşaltın");
});

Deno.test("yürüme güzergâhı olmayan yakın çekimde takılma bulgusu üretilmez", () => {
  // 41f14e70: hortum kaplininin makro çekiminde, çakıl içindeki bir tel parçası
  // ve kuru otlar "takılma tehlikesi" olarak yayınlanmıştı.
  const photo = output([candidate({
    candidate_key: "debris-trip",
    module_id: "housekeeping_physical_contact",
    raw_label: "Yerdeki gevşek tel ve döküntülerden kaynaklanan takılma tehlikesi",
    affirmative_cues: ["yerde gevşek tel parçası", "yerde kuru otlar ve yapraklar"],
    event_path: {
      source: "gevşek döküntüler",
      contact_or_failure: "kişinin takılması",
      consequence: "düşme",
    },
    potential_consequence: "ordinary",
  })]);
  photo.people = [];
  photo.accessible_regions = [{
    id: "ground_1",
    kind: "surface",
    label: "zemin",
    visible: true,
    accessible: true,
    region: { x: 0, y: 0, width: 1, height: 1, is_global: true },
  }] as never;
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routed.items.some((item) => item.item_class === "observed_finding"),
    false,
  );
  assertEquals(
    routed.hardRejections[0].reason_code,
    "no_walkable_route_in_scene",
  );
});

Deno.test("adlandırılmış geçiş yolu varsa takılma bulgusu korunur", () => {
  const photo = output([candidate({
    candidate_key: "site-trip",
    module_id: "housekeeping_physical_contact",
    raw_label: "Geçiş yolunda dağınık malzemeler",
    affirmative_cues: ["geçiş yolunda kutular ve ekipman parçaları"],
    event_path: {
      source: "zemindeki malzeme",
      contact_or_failure: "kişinin takılması",
      consequence: "düşme",
    },
    potential_consequence: "ordinary",
  })]);
  photo.people = [];
  photo.accessible_regions = [{
    id: "path_1",
    kind: "path",
    label: "Zemin geçiş yolu",
    visible: true,
    accessible: true,
    region: { x: 0.1, y: 0.6, width: 0.8, height: 0.3 },
  }] as never;
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(routed.items[0].item_class, "observed_finding");
  assertEquals(routed.items[0].recommended_action.includes("ıslak"), false);
});

Deno.test("hortum güvencesi tank başlığı taşımaz", () => {
  const photo = output([candidate()]);
  photo.scene_entities = [
    ...photo.scene_entities,
    {
      id: "coupling_1",
      kind: "component",
      label: "hortum bağlantısı",
      visible: true,
      accessible: true,
    },
  ];
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
    referencePolicy: "tr_current",
  });
  const assurance = routed.items.find((item) =>
    item.internal_priority.assurance_topic_id === "hose_assembly_integrity"
  );
  assertEquals(assurance?.title, "Hortum ve bağlantı elemanı bütünlüğü");
  assertEquals(assurance?.title.includes("tank"), false);
  assertEquals(assurance?.description.includes("tank"), false);
  assertStringIncludes(
    assurance?.recommended_measures[0].text ?? "",
    "kamçı emniyeti",
  );
  assertStringIncludes(assurance?.references_text ?? "", "TS EN 853");
  assertEquals((assurance?.references_text ?? "").includes("API 653"), false);
});

Deno.test("tüm korkuluk yokken başlık tek eleman eksikliği demez", () => {
  // 58057767: "Platformun kenarında korkuluk, ara korkuluk veya etek tahtası
  // bulunmamaktadır" tamamen korumasız bir kenar, ama "ara korkuluk" geçtiği
  // için kısmi eksiklik başlığıyla yayınlanmıştı.
  const photo = output([candidate({
    candidate_key: "open-edge",
    module_id: "falls_falling_objects",
    raw_label: "Yükseltilmiş platform kenarında toplu koruma eksikliği",
    affirmative_cues: [
      "Platformun kenarında korkuluk, ara korkuluk veya etek tahtası bulunmamaktadır",
      "açıkta kalan kenar",
    ],
    event_path: {
      source: "yükseltilmiş platform kenarı",
      contact_or_failure: "kişinin düşmesi",
      consequence: "yere çarpma",
    },
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routed.items[0].title,
    "Çalışma kenarında düşmeye karşı koruma eksikliği",
  );
  assertEquals(routed.items[0].fk_severity, 40);
});

Deno.test("sabitlenmemiş merdiven takılma bulgusu olarak yayınlanmaz", () => {
  const photo = output([candidate({
    candidate_key: "ladder-access",
    module_id: "access_egress",
    raw_label: "Platforma erişim için uygun olmayan portatif merdiven",
    affirmative_cues: [
      "Platforma dayalı portatif alüminyum merdiven",
      "merdiven üstten sabitlenmemiş",
    ],
    event_path: {
      source: "portatif merdiven",
      contact_or_failure: "merdivenden düşme",
      consequence: "yere çarpma",
    },
    potential_consequence: "serious",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const item = routed.items[0];
  assertStringIncludes(item.title, "merdiven");
  assertEquals(item.title.includes("dağınık malzeme"), false);
  assertEquals(item.score_payload?.mechanism_code, "fall_from_height");
  assertEquals(item.score_payload?.severity_cap, 40);
  assertEquals(
    item.recommended_action.includes("Geçiş yolundaki malzemeyi"),
    false,
  );
});

Deno.test("gerçekten tıkalı geçiş yolu kendi başlığını korur", () => {
  const photo = output([candidate({
    candidate_key: "blocked-route",
    module_id: "access_egress",
    raw_label: "Geçiş yolu malzemelerle kapalı",
    affirmative_cues: ["geçiş yolunda dağınık malzeme yığını"],
    event_path: {
      source: "geçiş yolundaki malzeme",
      contact_or_failure: "kişinin takılması",
      consequence: "aynı seviyede düşme",
    },
    potential_consequence: "ordinary",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routed.items[0].title,
    "Güvenli geçiş yolunun dağınık malzemelerle engellenmesi",
  );
  assertEquals(routed.items[0].score_payload?.mechanism_code, "fall_same_level");
});

Deno.test("varlık tahmini yapan modül kapsamı saha teyidi üretmez", () => {
  // 58057767: on iki maddenin dördü "şu tehlike sınıfı burada olabilir"
  // tahminiydi. Görünen bir varlığın durumu çözülemiyorsa madde kalır.
  const photo = output([candidate()]);
  const speculative = [
    ["chemical", "Proses ortamında kimyasallar kullanılıyor olabilir, ancak dökülme veya diğer kimyasal tehlikeler görsel olarak çözümlenememektedir."],
    ["electrical", "Endüstriyel ekipmanların elektrik bağlantıları veya panoları mevcut olabilir, ancak açıkta kablo görsel olarak çözümlenememektedir."],
    ["energy", "Endüstriyel ekipman ve boru tesisatı enerji içeriyor olabilir, ancak yalıtımsız yüzey görsel olarak çözümlenememektedir."],
  ] as const;
  const grounded = [
    "process_integrity",
    "Boru tesisatı ve ekipmanların proses bütünlüğü (sızıntı, korozyon vb.) görsel olarak tam olarak değerlendirilememektedir.",
  ] as const;

  photo.module_coverage = [
    ...photo.module_coverage.filter((entry) =>
      !["energy"].includes(entry.module_id)
    ),
    ...[...speculative, grounded].map(([moduleID, note]) => ({
      module_id: moduleID,
      activated_by: ["core"],
      outcome: "unresolved_requires_verification" as const,
      entity_refs: ["platform-1"],
      candidate_keys: [],
      note,
    })),
  ] as never;

  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const unresolved = routed.items.filter((item) =>
    item.internal_priority.route_reason === "module_coverage_unresolved"
  );
  assertEquals(unresolved.length, 1);
  assertEquals(unresolved[0].category, "Proses bütünlüğü");

  const dropped = routed.ledger.filter((entry) =>
    entry.reason_code === "speculative_module_coverage"
  );
  assertEquals(dropped.length, 3);
  assertEquals(dropped.every((entry) => entry.candidate_id === undefined), true);
});

Deno.test("gerçek gözleme dayanan çözülemeyen modül maddesi korunur", () => {
  const photo = output([candidate()]);
  photo.module_coverage = photo.module_coverage.map((entry) =>
    entry.module_id === "energy"
      ? {
        ...entry,
        outcome: "unresolved_requires_verification" as const,
        candidate_keys: [],
        note:
          "Pano bölgesi kısmen örtülü görünmekte; izolasyon düzeni bu açıdan çözümlenememektedir.",
      }
      : entry
  );
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routed.items.some((item) =>
      item.internal_priority.route_reason === "module_coverage_unresolved"
    ),
    true,
  );
});

Deno.test("etek tahtası da yokken kenardan düşme kişi düşmesi kalır", () => {
  // c42829fa: "korumasız kenardan düşme -> zeminle çarpışma", ama ipuçları her
  // şeyi saydığı için etek tahtası kestirmesi düşen cisim mekanizmasını verdi.
  const photo = output([candidate({
    candidate_key: "open-edge-all",
    module_id: "falls_falling_objects",
    raw_label: "Yükseltilmiş platformun kenarında korkuluk eksikliği",
    affirmative_cues: [
      "platform kenarı açıkta",
      "üst korkuluk yok",
      "ara korkuluk yok",
      "etek tahtası yok",
    ],
    event_path: {
      source: "yükseltilmiş platform",
      contact_or_failure: "korumasız kenardan düşme",
      consequence: "zeminle çarpışma",
    },
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routed.items[0].score_payload?.mechanism_code,
    "fall_from_height",
  );
  assertStringIncludes(routed.items[0].root_cause_text, "Açık kenarda");
});

Deno.test("aynı merdiven iki modülden gelse de tek bulgu olur", () => {
  const photo = output([
    candidate({
      candidate_key: "falls_02",
      module_id: "falls_falling_objects",
      asset_ref: "ladder_01",
      raw_label: "Portatif merdivenin sabitlenmemiş olması",
      affirmative_cues: [
        "merdiven platforma yaslanmış",
        "görünür sabitleme mekanizması yok",
      ],
      event_path: {
        source: "portatif merdiven",
        contact_or_failure: "merdivenin kayması",
        consequence: "merdivenden düşme",
      },
      potential_consequence: "serious",
    }),
    candidate({
      candidate_key: "access_01",
      module_id: "access_egress",
      asset_ref: "ladder_01",
      raw_label: "Kalıcı platforma erişim için portatif merdiven kullanılması",
      affirmative_cues: ["platforma tek erişim portatif merdiven"],
      event_path: {
        source: "portatif merdiven",
        contact_or_failure: "yetersiz erişim",
        consequence: "merdivenden düşme",
      },
      potential_consequence: "serious",
    }),
  ]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const ladder = routed.items.filter((item) =>
    item.is_scored && item.title.includes("merdiven")
  );
  assertEquals(ladder.length, 1);
  assertEquals(ladder[0].title.includes("Çalışma kenarında"), false);
  assertEquals(ladder[0].score_payload?.mechanism_code, "fall_from_height");
});

Deno.test("düşük görünürlükte model ekipmana isim veremez", () => {
  const photo = output([candidate({
    candidate_key: "bg-machine",
    module_id: "machinery",
    raw_label: "Arka plandaki taşlama makinesinin dönen parçasında koruyucu eksikliği",
    affirmative_cues: ["dönen parça açıkta ve koruyucusuz görünüyor"],
    event_path: {
      source: "koruyucusuz dönen parça",
      contact_or_failure: "temas/sıkışma",
      consequence: "ciddi yaralanma",
    },
    potential_consequence: "permanent",
    confidence: { visibility: 0.7, localization: 0.8, mechanism: 0.9 },
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  const title = routed.items[0].title;
  assertEquals(title.includes("taşlama"), false);
  assertStringIncludes(title, "makine");
  assertStringIncludes(title, "dönen parça");
});

Deno.test("net görülen ekipmanın adı başlıkta kalır", () => {
  const photo = output([candidate({
    candidate_key: "clear-lathe",
    module_id: "machinery",
    raw_label: "Torna tezgahında ayna alanında koruyucu eksikliği",
    affirmative_cues: ["ayna alanı tamamen açıkta", "görünür koruyucu yok"],
    event_path: {
      source: "dönen ayna",
      contact_or_failure: "temas/dolama",
      consequence: "ciddi yaralanma",
    },
    potential_consequence: "permanent",
    confidence: { visibility: 1, localization: 1, mechanism: 1 },
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertStringIncludes(routed.items[0].title, "Torna");
});

Deno.test("kendi olumsuzuyla kapanan spekülatif not kapıdan geçemez", () => {
  const photo = output([candidate()]);
  photo.module_coverage = photo.module_coverage.map((entry) =>
    entry.module_id === "energy"
      ? {
        ...entry,
        outcome: "unresolved_requires_verification" as const,
        candidate_keys: [],
        note:
          "Proses ekipmanları içinde elektriksel bileşenler olabilir ancak belirgin bir elektriksel tehlike görsel olarak tespit edilemiyor.",
      }
      : entry
  );
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertEquals(
    routed.items.some((item) =>
      item.internal_priority.route_reason === "module_coverage_unresolved"
    ),
    false,
  );
  assertEquals(
    routed.ledger.some((entry) =>
      entry.reason_code === "speculative_module_coverage"
    ),
    true,
  );
});

Deno.test("ekipman sıra numarası kullanıcı metnine sızmaz", () => {
  // 12063bd4: model varlıkları numaralıyor ("Makine 3", "Torna tezgahı 1") ve bu
  // numaralar başlığa geçiyordu. Okuyucunun eşleştireceği bir numaralandırma yok
  // -- person_2 sızıntısıyla aynı sınıf. Türkçede rakamı silmek yetmiyor: hâl
  // eki rakamın üzerinde duruyor, isme yeniden bağlanması gerekiyor.
  const cases: Array<[string, string, string]> = [
    [
      "Torna tezgahı 1'de açıkta bulunan kurşun vida",
      "Torna tezgahında açıkta bulunan kurşun vida",
      "vida açıkta",
    ],
    [
      "Torna tezgahı 1'in çalışma noktasında koruyucu eksikliği",
      "Torna tezgahının çalışma noktasında koruyucu eksikliği",
      "koruyucu yok",
    ],
    [
      "Makine 3 üzerinde açıkta kalan elektrik kabloları",
      "Makine üzerinde açıkta kalan elektrik kabloları",
      "kablolar açıkta",
    ],
    ["Pompa 2'de sızıntı", "Pompada sızıntı", "sızıntı var"],
    // Sert ünsüzle biten isimde ünsüz benzeşmesi: "Tank 4'te" -> "Tankta".
    ["Tank 4'te korozyon", "Tankta korozyon", "korozyon var"],
  ];
  for (const [rawLabel, expected, cue] of cases) {
    const photo = output([candidate({
      candidate_key: `ord-${expected.length}`,
      module_id: "machinery",
      raw_label: rawLabel,
      affirmative_cues: [cue],
      event_path: {
        source: "dönen parça",
        contact_or_failure: "temas",
        consequence: "uzuv kaybı",
      },
      potential_consequence: "permanent",
    })]);
    const routed = routeCandidates({
      candidates: normalizeCandidates(photo, 1),
      photoOutputs: [{ photoIndex: 1, output: photo }],
      sectorID: "manufacturing",
    });
    assertEquals(routed.items[0].title, expected);
    assertEquals(/\d/.test(routed.items[0].title), false);
  }
});

Deno.test("açıklamadaki ekipman numarası da temizlenir", () => {
  const photo = output([candidate({
    candidate_key: "ord-descr",
    module_id: "electrical",
    raw_label: "Açıkta kalan elektrik kabloları",
    affirmative_cues: ["Makine 3'ün üst kısmında açıkta kalan kablolar"],
    event_path: {
      source: "açıkta kablo",
      contact_or_failure: "temas",
      consequence: "elektrik çarpması",
    },
    potential_consequence: "fatal",
  })]);
  const routed = routeCandidates({
    candidates: normalizeCandidates(photo, 1),
    photoOutputs: [{ photoIndex: 1, output: photo }],
    sectorID: "manufacturing",
  });
  assertStringIncludes(routed.items[0].description, "Makinenin üst kısmında");
  assertEquals(routed.items[0].description.includes("Makine 3"), false);
});

Deno.test("ikinci geçiş: birinci geçişin kaçırdığı tehlike eklenir", () => {
  // 96c7f819: model tankların üzerindeki korumasız karıştırıcıları hiç
  // görmemiş, makine modülünü "sorun yok" diye kapatmıştı.
  const primary = output([candidate({
    candidate_key: "P1",
    module_id: "falls_falling_objects",
    raw_label: "Korkulukta etek tahtası eksikliği",
    affirmative_cues: ["etek tahtası görünmüyor"],
    potential_consequence: "serious",
  })]);
  const second = output([candidate({
    candidate_key: "S1",
    module_id: "machinery",
    asset_ref: "agitator",
    raw_label: "Tank üzerindeki karıştırıcının korumasız dönen parçaları",
    affirmative_cues: ["dönen şaft ve kaplin açıkta"],
    event_path: {
      source: "dönen karıştırıcı",
      contact_or_failure: "temas",
      consequence: "uzuv kaybı",
    },
    potential_consequence: "permanent",
  })]);
  const reconciled = reconcileVerificationPass({
    primaryCandidates: normalizeCandidates(primary, 1),
    second,
    secondCandidates: normalizeCandidates(second, 1),
  });
  assertEquals(reconciled.added.length, 1);
  assertEquals(reconciled.added[0].module_id, "machinery");
  assertEquals(reconciled.disputed.length, 0);
});

Deno.test("ikinci geçiş: aynı tehlikeyi iki kez yayınlamaz", () => {
  const make = (key: string, label: string) =>
    output([candidate({
      candidate_key: key,
      module_id: "machinery",
      asset_ref: "lathe_01",
      raw_label: label,
      affirmative_cues: ["koruyucu yok"],
      event_path: {
        source: "dönen ayna",
        contact_or_failure: "temas",
        consequence: "uzuv kaybı",
      },
      potential_consequence: "permanent",
    })]);
  const primary = make("P1", "Torna aynasında koruyucu eksikliği");
  const second = make("S1", "Torna tezgahı aynasında koruyucu bulunmuyor");
  const reconciled = reconcileVerificationPass({
    primaryCandidates: normalizeCandidates(primary, 1),
    second,
    secondCandidates: normalizeCandidates(second, 1),
  });
  assertEquals(reconciled.added.length, 0);
  assertEquals(reconciled.duplicateCount, 1);
});

Deno.test("ikinci geçiş elemanı görürse yokluk iddiası saha teyidine düşer", () => {
  // 96c7f819'un yanlış bulgusu: etek tahtası fotoğrafta duruyordu.
  const primary = output([candidate({
    candidate_key: "P1",
    module_id: "falls_falling_objects",
    raw_label: "Korkuluk sisteminde etek tahtası eksikliği",
    affirmative_cues: [
      "korkuluk sisteminin en alt kısmında etek tahtası görünmüyor",
    ],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "nesne düşmesi",
      consequence: "aşağıdaki kişiye çarpma",
    },
    potential_consequence: "serious",
  })]);
  const second = output([]);
  second.positive_controls = [{
    control_key: "toeboard-seen",
    module_id: "falls_falling_objects",
    description: "Platform kenarında etek tahtası mevcut.",
    affirmative_cues: ["sarı etek tahtası boydan boya görülüyor"],
    evidence_region: { x: 0, y: 0.55, width: 1, height: 0.15 },
  }] as never;
  const primaryCandidates = normalizeCandidates(primary, 1);
  const reconciled = reconcileVerificationPass({
    primaryCandidates,
    second,
    secondCandidates: normalizeCandidates(second, 1),
  });
  assertEquals(reconciled.disputed.length, 1);
  assertStringIncludes(reconciled.disputed[0].reason, "second_pass_saw");

  const routed = routeCandidates({
    candidates: primaryCandidates,
    photoOutputs: [{ photoIndex: 1, output: primary }],
    sectorID: "manufacturing",
  });
  const item = routed.items.find((entry) => entry.candidate_id);
  assertEquals(item?.item_class, "verification_request");
  assertEquals(item?.is_scored, false);
  assertStringIncludes(
    String(item?.internal_priority.route_reason),
    "second_pass_disagreement",
  );
});

Deno.test("ikinci geçişin sessizliği itiraz sayılmaz", () => {
  // İkinci geçiş modülü "değerlendirilemedi" ile kapatırsa bu bir karşı kanıt
  // değildir; doğru bulguyu bastırmamalı.
  const primary = output([candidate({
    candidate_key: "P1",
    module_id: "falls_falling_objects",
    raw_label: "Korkulukta etek tahtası eksikliği",
    affirmative_cues: ["etek tahtası görünmüyor"],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "nesne düşmesi",
      consequence: "çarpma",
    },
    potential_consequence: "serious",
  })]);
  const second = output([]);
  second.module_coverage = second.module_coverage.map((entry) =>
    entry.module_id === "falls_falling_objects"
      ? {
        ...entry,
        outcome: "not_assessable_due_to_image" as const,
        note: "Kenar bölgesi bu açıdan çözülemiyor.",
      }
      : entry
  );
  const primaryCandidates = normalizeCandidates(primary, 1);
  const reconciled = reconcileVerificationPass({
    primaryCandidates,
    second,
    secondCandidates: [],
  });
  assertEquals(reconciled.disputed.length, 0);
  const routed = routeCandidates({
    candidates: primaryCandidates,
    photoOutputs: [{ photoIndex: 1, output: primary }],
    sectorID: "manufacturing",
  });
  assertEquals(routed.items[0].item_class, "observed_finding");
});

Deno.test("varlık iddiası ikinci geçişle çürütülmez, yalnız yokluk iddiası", () => {
  // Görünen bir tehlike (açıkta dönen parça) ikinci geçiş sessiz kalsa da
  // skorlu kalır; kapı yalnız yokluk iddialarına bakar.
  const primary = output([candidate({
    candidate_key: "P1",
    module_id: "machinery",
    raw_label: "Açıkta dönen kaplin",
    affirmative_cues: ["kaplin dönerken görülüyor"],
    event_path: {
      source: "dönen kaplin",
      contact_or_failure: "temas",
      consequence: "uzuv kaybı",
    },
    potential_consequence: "permanent",
  })]);
  const second = output([]);
  second.module_coverage = second.module_coverage.map((entry) =>
    entry.module_id === "machinery"
      ? {
        ...entry,
        outcome: "no_actionable_issue_visible" as const,
        note: "Görünürde korumasız hareketli parça yok.",
      }
      : entry
  );
  const primaryCandidates = normalizeCandidates(primary, 1);
  const reconciled = reconcileVerificationPass({
    primaryCandidates,
    second,
    secondCandidates: [],
  });
  assertEquals(reconciled.disputed.length, 0);
});

Deno.test("İngilizce cevap Türkçe sözleşmesini ihlal eder", () => {
  // 8747d7c1: beş birincil adayın hepsi İngilizce döndü ve rapora çıktı --
  // "Bu durum contact with exposed rotating parts yoluyla entanglement or
  // crushing injury sonucuna neden olabilir."
  const english = output([
    candidate({
      candidate_key: "C1",
      module_id: "falls_falling_objects",
      raw_label: "Missing toeboard on elevated platform guardrail.",
      affirmative_cues: [
        "Gap between platform surface and mid-rail",
        "no visible toeboard on the front edge of the walkway",
      ],
      event_path: {
        source: "person on platform",
        contact_or_failure: "object falling from platform edge",
        consequence: "injury to person below",
      },
    }),
    candidate({
      candidate_key: "C2",
      module_id: "machinery",
      raw_label: "Unguarded rotating machinery parts.",
      affirmative_cues: [
        "Exposed motor casing with a visible shaft connection to the tank",
      ],
      event_path: {
        source: "rotating machinery",
        contact_or_failure: "contact with exposed rotating parts",
        consequence: "entanglement or crushing injury",
      },
    }),
  ]);
  assertStringIncludes(
    String(outputLanguageFailure(english, "tr")),
    "output_language_not_turkish",
  );
  // Only Turkish is judged; an English analysis must pass untouched.
  assertEquals(outputLanguageFailure(english, "en"), null);
});

Deno.test("Türkçe cevap dil denetiminden geçer", () => {
  const turkish = output([candidate({
    candidate_key: "C1",
    module_id: "falls_falling_objects",
    raw_label: "Yükseltilmiş platform korkuluğunda etek tahtası eksikliği",
    affirmative_cues: [
      "Platform yüzeyi ile ara korkuluk arasında boşluk görülmektedir",
      "korkuluğun alt kısmında etek tahtası bulunmamaktadır",
    ],
    event_path: {
      source: "platform kenarı",
      contact_or_failure: "nesnenin kenardan düşmesi",
      consequence: "aşağıdaki çalışana çarpma",
    },
  })]);
  assertEquals(outputLanguageFailure(turkish, "tr"), null);
});

Deno.test("kısa Türkçe metin diakritiksiz olsa da yanlış alarm vermez", () => {
  // "motor kaplini" gibi kısa bir etiket ünlü işareti taşımayabilir; bunun için
  // retry harcanmamalı.
  const short = output([candidate({
    candidate_key: "C1",
    module_id: "machinery",
    raw_label: "Motor kaplini",
    affirmative_cues: ["kaplin acikta"],
    event_path: {
      source: "kaplin",
      contact_or_failure: "temas",
      consequence: "yaralanma",
    },
  })]);
  assertEquals(outputLanguageFailure(short, "tr"), null);
});
