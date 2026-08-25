import type {
  EvidenceLevel,
  NormalizedCandidate,
  ProviderCandidate,
  ProviderPhotoOutput,
} from "./contracts.ts";

const FABRICATED_MEASUREMENT =
  /\b(?:\d+(?:[.,]\d+)?\s*(?:db|lux|ppm|bar|volt|kv|kg|ton|km\/?h|m\/s|mm|cm|m|°c)|ölçüm sonucu|olcum sonucu)\b/iu;
const UNSUPPORTED_DOCUMENT_ABSENCE =
  /\b(?:sertifika(?:sı)?\s+yok|eğitim(?:i)?\s+yok|periyodik\s+kontrol(?:ü)?\s+yok|ce\s+(?:işareti\s+)?yok)\b/iu;
const IDENTITY_CLAIM =
  /\b(?:kimyasalın adı|madde kimliği|gazın türü|gerilim değeri)\b/iu;
/**
 * Turkish is agglutinative, so a trailing \b never fires on the words that
 * actually appear. A live fatal candidate labelled "kenar koruması eksikliği"
 * failed `\beksik\b` - the suffix "liği" is word characters - and was
 * classified as an ordinary fall-protection condition instead of a visible
 * structural absence. Stems are matched here, and the verbs that can go either
 * way ("bulunmakta" is presence, "bulunmuyor" is absence) carry their negative
 * endings explicitly.
 */
const STRUCTURAL_ABSENCE =
  /(?:\beksik|\byok(?:tur|luğu|lugu)?\b|bulunmuyor|bulunmama|bulunmadı|bulunmadi|bulunmaz|görünmüyor|gorunmuyor|görünmeme|gorunmeme|görünmedi|gorunmedi|mevcut değil|mevcut degil|takılı değil|takili degil|\bkorumasız|\bkorumasiz|\bkorunmasız|\bkorunmasiz|açık kenar|acik kenar|kapaksız|kapaksiz|bariyersiz|korkuluksuz|muhafazasız|muhafazasiz)/iu;
const AMBIGUOUS_ELECTRICAL_IDENTITY =
  /\b(?:kablo(?:lar)?\s*[\/]\s*hortum(?:lar)?|kablo\s+veya\s+hortum|hat(?:tın)?\s+(?:niteliği|türü)\s+belirsiz)\b/iu;

function clamp(value: unknown): number {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.min(1, number)) : 0;
}

function validRegion(candidate: ProviderCandidate): boolean {
  const region = candidate.evidence_region;
  return Boolean(region) &&
    [region!.x, region!.y, region!.width, region!.height]
      .every((value) => Number.isFinite(value) && value >= 0 && value <= 1) &&
    region!.width > 0 && region!.height > 0;
}

function evidenceLevel(candidate: ProviderCandidate): EvidenceLevel {
  const cues = candidate.affirmative_cues.filter((cue) =>
    cue.trim().length > 2
  );
  if (cues.length === 0) return "E0";
  const confidence = (
    clamp(candidate.confidence.visibility) +
    clamp(candidate.confidence.localization) +
    clamp(candidate.confidence.mechanism)
  ) / 3;
  const local = validRegion(candidate);
  // The prompt asks for counter_cues, so a careful model always writes some.
  // Demoting on a simple majority made honesty cost evidence level; only
  // clearly overwhelming contrary detail should.
  if (candidate.counter_cues.length > cues.length * 2 || confidence < 0.25) {
    return "E1";
  }
  if (candidate.occlusion === "substantial" || confidence < 0.45) return "E2";
  if (!local || candidate.occlusion === "partial" || confidence < 0.62) {
    return "E3";
  }
  if (confidence >= 0.84 && candidate.occlusion === "none") return "E5";
  return "E4";
}

function conditionCode(candidate: ProviderCandidate): string {
  const text = `${candidate.raw_label} ${candidate.affirmative_cues.join(" ")}`
    .toLocaleLowerCase("tr-TR");
  if (candidate.requires_document_or_measurement) return "assurance_only_topic";
  if (
    candidate.module_id === "electrical" &&
    AMBIGUOUS_ELECTRICAL_IDENTITY.test(text)
  ) return "electrical_identity_unresolved";
  if (STRUCTURAL_ABSENCE.test(text)) return "visible_structural_absence";
  const byModule: Record<string, string> = {
    falls_falling_objects: "fall_or_falling_object_path",
    work_at_height: "fall_protection_condition",
    energy: "hazardous_energy_contact_path",
    electrical: "electrical_contact_or_arc_path",
    vehicles_mobile_equipment: "vehicle_person_interface",
    logistics: "vehicle_person_interface",
    machinery: "machine_contact_or_entanglement",
    fire_explosion_release: "fire_explosion_or_release",
    chemical: "chemical_release_or_contact",
    process_integrity: "loss_of_containment_path",
    lifting: "suspended_or_dropped_load_path",
    excavation: "excavation_collapse_or_fall",
    confined_space: "confined_space_entry_path",
    hot_work: "hot_work_ignition_path",
    combustible_dust: "combustible_dust_event_path",
    biosecurity: "biological_exposure_path",
    access_egress: "access_egress_obstruction",
    housekeeping_physical_contact: "physical_contact_or_trip_path",
    people_exposure: "person_exposure_path",
  };
  return byModule[candidate.module_id] ?? "visible_physical_condition";
}

function accessiblePath(
  candidate: ProviderCandidate,
  output: ProviderPhotoOutput,
): boolean {
  if (candidate.person_ref) return true;
  if (output.accessible_regions.some((region) => region.accessible !== false)) {
    return true;
  }
  const text = `${candidate.raw_label} ${candidate.affirmative_cues.join(" ")}`;
  return /\b(?:yürüme|geçiş|çalışma|erişim|platform|merdiven|walkway|access)\b/iu
    .test(text);
}

/**
 * Borrows the region of the entity a candidate names.
 *
 * A missing evidence_region capped every candidate at E3, and E3 used to demote
 * critical candidates to verification. The person or asset the candidate points
 * at is usually already localized in the scene graph, so localization is
 * recovered rather than assumed lost.
 */
function withInheritedRegion(
  candidate: ProviderCandidate,
  output: ProviderPhotoOutput,
): ProviderCandidate {
  if (validRegion(candidate)) return candidate;
  const refs = [candidate.person_ref, candidate.asset_ref].filter(Boolean);
  for (const ref of refs) {
    const entity = [...output.people, ...output.scene_entities]
      .find((item) => item.id === ref);
    if (
      entity?.region &&
      validRegion({ ...candidate, evidence_region: entity.region })
    ) {
      return { ...candidate, evidence_region: entity.region };
    }
  }
  return candidate;
}

export function normalizeCandidates(
  output: ProviderPhotoOutput,
  photoIndex: number,
): NormalizedCandidate[] {
  const seen = new Set<string>();
  return output.candidates.flatMap((candidate) => {
    const key = candidate.candidate_key.trim().slice(0, 200);
    if (!key || seen.has(key)) return [];
    seen.add(key);
    const coreClaim =
      `${candidate.raw_label} ${candidate.event_path.source} ${candidate.event_path.contact_or_failure} ${candidate.event_path.consequence}`;
    const assuranceOnVisibleAsset =
      candidate.requires_document_or_measurement &&
      Boolean(candidate.asset_ref?.trim());
    const sanitizedCues = candidate.affirmative_cues.filter((cue) =>
      !FABRICATED_MEASUREMENT.test(cue) &&
      !UNSUPPORTED_DOCUMENT_ABSENCE.test(cue)
    );
    const sanitizedCandidate: ProviderCandidate = withInheritedRegion({
      ...candidate,
      affirmative_cues: sanitizedCues,
    }, output);
    let hardRejectReason: string | undefined;
    if (
      !assuranceOnVisibleAsset &&
      (FABRICATED_MEASUREMENT.test(coreClaim) ||
        UNSUPPORTED_DOCUMENT_ABSENCE.test(coreClaim))
    ) {
      hardRejectReason = "forbidden_photo_measurement_or_document_claim";
    } else if (
      !assuranceOnVisibleAsset && IDENTITY_CLAIM.test(coreClaim) &&
      candidate.confidence.visibility < 0.8
    ) {
      hardRejectReason = "unreadable_identity_claim";
    }
    return [{
      ...sanitizedCandidate,
      id: crypto.randomUUID(),
      candidate_key: key,
      photo_index: photoIndex,
      evidence_level: evidenceLevel(sanitizedCandidate),
      criticality: candidate.potential_consequence,
      condition_code: conditionCode(sanitizedCandidate),
      normalized_label: candidate.raw_label.trim().replace(/\s+/g, " ").slice(
        0,
        300,
      ),
      accessible_event_path: accessiblePath(sanitizedCandidate, output),
      evidence_region: sanitizedCandidate.evidence_region,
      hard_reject_reason: hardRejectReason,
    }];
  });
}
