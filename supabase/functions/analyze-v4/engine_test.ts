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
  assertEquals(verification.recommended_measures.length, 2);
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
