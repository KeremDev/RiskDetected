import type { NormalizedCandidate, ProviderPhotoOutput } from "./contracts.ts";
import { V4_TARGETED_PROMPT_COMMON } from "./prompt.ts";

export type TargetedGroup = {
  regionKey: string;
  photoIndex: number;
  candidateIDs: string[];
  candidates: NormalizedCandidate[];
  priority: number;
};

function quantize(value: number | undefined): number {
  return Math.round(Math.max(0, Math.min(1, Number(value) || 0)) * 5);
}

function groupKey(candidate: NormalizedCandidate): string {
  const region = candidate.evidence_region;
  return `${candidate.photo_index}:${candidate.module_id}:${
    quantize(region?.x)
  }:${quantize(region?.y)}:${quantize(region?.width)}:${
    quantize(region?.height)
  }`;
}

function priority(candidate: NormalizedCandidate): number {
  const consequence = candidate.criticality === "fatal"
    ? 0
    : candidate.criticality === "permanent"
    ? 10
    : 30;
  const evidence = candidate.evidence_level === "E3"
    ? 0
    : candidate.evidence_level === "E2"
    ? 2
    : 5;
  return consequence + evidence;
}

export function buildTargetedQueue(
  candidates: NormalizedCandidate[],
  computeProfile: "premium" | "economy",
): { selected: TargetedGroup[]; budgetExcluded: TargetedGroup[] } {
  const grouped = new Map<string, TargetedGroup>();
  for (const candidate of candidates) {
    const directlyObservedStructuralAbsence =
      candidate.evidence_level === "E3" &&
      candidate.condition_code === "visible_structural_absence" &&
      candidate.accessible_event_path &&
      candidate.affirmative_cues.length > 0 &&
      candidate.counter_cues.length === 0;
    if (
      !["fatal", "permanent"].includes(candidate.criticality) ||
      !candidate.visually_resolvable ||
      candidate.requires_document_or_measurement ||
      !["E2", "E3"].includes(candidate.evidence_level) ||
      directlyObservedStructuralAbsence
    ) continue;
    const key = groupKey(candidate);
    const group = grouped.get(key) ?? {
      regionKey: key,
      photoIndex: candidate.photo_index,
      candidateIDs: [],
      candidates: [],
      priority: priority(candidate),
    };
    group.candidateIDs.push(candidate.id);
    group.candidates.push(candidate);
    group.priority = Math.min(group.priority, priority(candidate));
    grouped.set(key, group);
  }
  const ordered = [...grouped.values()].sort((a, b) =>
    a.priority - b.priority || a.regionKey.localeCompare(b.regionKey)
  );
  const limit = computeProfile === "premium" ? 2 : 1;
  return {
    selected: ordered.slice(0, limit),
    budgetExcluded: ordered.slice(limit),
  };
}

export function targetedPrompt(group: TargetedGroup): string {
  const candidateText = group.candidates.map((candidate) => ({
    candidate_key: candidate.candidate_key,
    raw_label: candidate.raw_label,
    event_path: candidate.event_path,
    evidence_region: candidate.evidence_region,
    affirmative_cues: candidate.affirmative_cues,
    counter_cues: candidate.counter_cues,
  }));
  return `${V4_TARGETED_PROMPT_COMMON.trim()}
Yalnız aşağıdaki bölge ve kardeş adayları incele; görünür işaretleri daha kesin yerelleştir.
Hedef: ${JSON.stringify(candidateText)}`;
}

export function mergeTargetedOutput(
  candidates: NormalizedCandidate[],
  group: TargetedGroup,
  targeted: NormalizedCandidate[],
  targetedOutput?: ProviderPhotoOutput | null,
): NormalizedCandidate[] {
  return candidates.map((candidate) => {
    if (!group.candidateIDs.includes(candidate.id)) return candidate;
    const match = targeted.find((item) =>
      item.module_id === candidate.module_id
    ) ?? (targeted.length === 1 ? targeted[0] : undefined);
    const coverage = targetedOutput?.module_coverage.find((item) =>
      item.module_id === candidate.module_id
    );
    if (!match) {
      if (
        coverage?.outcome === "no_actionable_issue_visible" ||
        coverage?.outcome === "positive_control_present" ||
        coverage?.outcome === "module_activation_false_positive"
      ) {
        return {
          ...candidate,
          evidence_level: "E1",
          counter_cues: [
            ...new Set([
              ...candidate.counter_cues,
              coverage.note?.trim() || "Hedefli inceleme adayı doğrulamadı",
            ]),
          ],
          hard_reject_reason: coverage.outcome ===
              "module_activation_false_positive"
            ? "targeted_module_activation_false_positive"
            : "targeted_visual_counter_evidence",
        };
      }
      return candidate;
    }
    const targetedRefuted = ["E0", "E1"].includes(match.evidence_level) &&
      (match.counter_cues.length > 0 ||
        coverage?.outcome === "no_actionable_issue_visible" ||
        coverage?.outcome === "positive_control_present");
    return {
      ...candidate,
      affirmative_cues: [
        ...new Set([...candidate.affirmative_cues, ...match.affirmative_cues]),
      ],
      counter_cues: [
        ...new Set([...candidate.counter_cues, ...match.counter_cues]),
      ],
      evidence_region: match.evidence_region ?? candidate.evidence_region,
      evidence_level: match.evidence_level,
      occlusion: match.occlusion,
      confidence: match.confidence,
      hard_reject_reason: targetedRefuted
        ? "targeted_visual_counter_evidence"
        : candidate.hard_reject_reason,
    };
  });
}
