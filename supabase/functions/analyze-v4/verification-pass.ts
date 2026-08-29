// A second, independent look at the same photograph.
//
// Analysis 96c7f819 is the case this exists for. On a photo that earlier runs
// had read as four heavy candidates, the model produced one -- and that one was
// false: it reported a missing toeboard over an evidence region where the
// toeboard is plainly visible, at visibility 0.9, while closing machinery as
// "görünürde korumasız hareketli makine parçaları yok" over two unguarded
// agitator drives. Neither failure is reachable from the router: it can only
// classify what it is handed, and it cannot recover a candidate that was never
// produced or dispute a claim nothing contradicts.
//
// So the engine looks twice and compares. The second pass sees the same image
// and the same contract, plus a compact statement of what the first pass
// claimed, and is asked to work the gaps rather than restate the agreement.
//
// Two directions, deliberately asymmetric:
//
//   Recall  -- anything the second pass finds that the first did not is added.
//              A missed hazard is the more dangerous error, so agreement is not
//              required to publish.
//
//   Caution -- a first-pass ABSENCE claim is demoted to a field check, never
//              deleted, when the second pass says it can SEE the very component
//              the first pass called missing. Absence claims are the
//              failure-prone class; a claim about something visibly present is
//              left alone. Silence is not contradiction, and neither is a module
//              closed as "nothing actionable": this model closes modules
//              wholesale, so accepting that would demote more true findings than
//              false ones.
//
// Single photo only for now. A multi-photo analysis already spends one call per
// photo, and doubling that is a cost decision that has not been taken.

import type {
  NormalizedCandidate,
  ProviderPhotoOutput,
} from "./contracts.ts";

/** Instructions for the second look. Part of the hashed prompt bundle. */
export const V4_VERIFICATION_PROMPT_COMMON =
  `İKİNCİ İNCELEME GÖREVİ
- Bu, aynı fotoğrafın ikinci ve bağımsız incelemesidir. Birinci incelemenin ne iddia ettiği aşağıda özetlenmiştir.
- Görevin birinci incelemeyi onaylamak değil; kaçırdığını bulmak ve dayanaksız iddiasını göstermektir.
- Fotoğrafa sıfırdan bak. Birinci incelemenin bulduğu bir koşulu tekrar yazma; yalnızca onun görmediği tehlikeler için aday üret.
- Birinci incelemenin bir yokluk iddiası varsa (bir korkuluk elemanı, bir koruyucu, bir emniyet parçası yok deniyorsa) o noktaya özellikle bak. Elemanı GÖRÜYORSAN bunu ilgili modülün positive_controls kaydına açık biçimde yaz.
- Bir modülde gerçekten değerlendirilecek bir şey yoksa o modülü no_actionable_issue_visible ile ve gördüğünü anlatan bir not ile kapat. Emin değilsen veya görüntü yetersizse not_assessable_due_to_image ya da unresolved_requires_verification kullan; bu ikisi "sorun yok" anlamına gelmez.
- Uydurma yapma. Görmediğin bir ekipmana isim verme, görmediğin bir koşulu rapor etme.`;

/** Compact statement of the first pass, small enough to prepend to the prompt. */
export function summarizePrimaryPass(output: ProviderPhotoOutput): string {
  const claims = output.candidates.slice(0, 12).map((candidate) =>
    `- [${candidate.module_id}] ${candidate.raw_label.slice(0, 140)}`
  );
  const closed = output.module_coverage
    .filter((entry) => entry.outcome === "no_actionable_issue_visible")
    .map((entry) => entry.module_id);
  return [
    "BİRİNCİ İNCELEMENİN İDDİALARI",
    claims.length > 0 ? claims.join("\n") : "- (aday üretilmedi)",
    closed.length > 0
      ? `\nBirinci inceleme şu modülleri "sorun yok" diye kapattı: ${
        closed.join(", ")
      }. Bunların her birine yeniden bak.`
      : "",
  ].filter(Boolean).join("\n");
}

function compact(value: string): string {
  return value.toLocaleLowerCase("tr-TR")
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9çğıöşü]+/giu, " ")
    .trim();
}

/** Same hazard seen twice: one finding, not two. */
function sameHazard(
  left: NormalizedCandidate,
  right: NormalizedCandidate,
): boolean {
  if (left.module_id !== right.module_id) return false;
  if (left.asset_ref && right.asset_ref && left.asset_ref === right.asset_ref) {
    return true;
  }
  const key = (candidate: NormalizedCandidate) =>
    compact(
      `${candidate.event_path.source} ${candidate.event_path.contact_or_failure} ${candidate.event_path.consequence}`,
    );
  if (key(left) === key(right)) return true;
  // Different wording for one condition: the distinguishing nouns still overlap.
  const words = (candidate: NormalizedCandidate) =>
    new Set(
      compact(candidate.normalized_label).split(" ").filter((word) =>
        word.length > 4
      ),
    );
  const leftWords = words(left);
  const rightWords = words(right);
  if (leftWords.size === 0 || rightWords.size === 0) return false;
  const shared = [...leftWords].filter((word) => rightWords.has(word)).length;
  return shared / Math.min(leftWords.size, rightWords.size) >= 0.6;
}

const BARRIER_COMPONENT: Array<{ code: string; pattern: RegExp }> = [
  { code: "mid_rail", pattern: /(?:ara korkuluk|orta korkuluk|midrail)/u },
  {
    code: "toeboard",
    pattern:
      /(?:etek tahtası|etek tahtasi|topuk levhası|topuk levhasi|toeboard)/u,
  },
  {
    code: "top_rail",
    pattern: /(?:üst korkuluk|ust korkuluk|ana korkuluk|top rail)/u,
  },
  { code: "guard", pattern: /(?:koruyucu|muhafaza|guard)/u },
];

function componentsIn(text: string): string[] {
  const lowered = text.toLocaleLowerCase("tr-TR");
  return BARRIER_COMPONENT.filter((item) => item.pattern.test(lowered)).map((
    item,
  ) => item.code);
}

/**
 * Did the second pass positively contradict this absence claim?
 *
 * One way only, and it has to be explicit: the second pass says it can see the
 * component. Silence is not contradiction.
 */
function contradictionFor(
  candidate: NormalizedCandidate,
  second: ProviderPhotoOutput,
): string | null {
  if (candidate.condition_code !== "visible_structural_absence") return null;

  const claimed = componentsIn(
    `${candidate.normalized_label} ${candidate.affirmative_cues.join(" ")}`,
  );
  for (const control of second.positive_controls) {
    if (control.module_id !== candidate.module_id) continue;
    const affirmed = componentsIn(
      `${control.description} ${control.affirmative_cues.join(" ")}`,
    );
    const overlap = claimed.filter((code) => affirmed.includes(code));
    if (overlap.length > 0) {
      return `second_pass_saw:${overlap.join("+")}`;
    }
  }

  // A module closed as "no_actionable_issue_visible" is deliberately NOT treated
  // as contradiction. This model closes modules wholesale -- one run shut eleven
  // of thirteen that way -- so accepting silence-plus-a-note would demote far
  // more true absence findings than false ones. Only an explicit sighting
  // counts, which is exactly what the second-pass prompt asks for.
  return null;
}

export type VerificationReconciliation = {
  /** Hazards the first pass missed. Published without requiring agreement. */
  added: NormalizedCandidate[];
  /** Absence claims the second pass contradicted, demoted rather than dropped. */
  disputed: Array<{ candidate_id: string; label: string; reason: string }>;
  /** Second-pass candidates dropped as duplicates of a first-pass claim. */
  duplicateCount: number;
};

export function reconcileVerificationPass(params: {
  primaryCandidates: NormalizedCandidate[];
  second: ProviderPhotoOutput;
  secondCandidates: NormalizedCandidate[];
}): VerificationReconciliation {
  const added: NormalizedCandidate[] = [];
  let duplicateCount = 0;
  for (const candidate of params.secondCandidates) {
    if (
      params.primaryCandidates.some((primary) =>
        sameHazard(primary, candidate)
      ) || added.some((other) => sameHazard(other, candidate))
    ) {
      duplicateCount += 1;
      continue;
    }
    added.push(candidate);
  }

  const disputed: VerificationReconciliation["disputed"] = [];
  for (const candidate of params.primaryCandidates) {
    const reason = contradictionFor(candidate, params.second);
    if (reason) {
      candidate.verification_disputed = reason;
      disputed.push({
        candidate_id: candidate.id,
        label: candidate.normalized_label.slice(0, 160),
        reason,
      });
    }
  }

  return { added, disputed, duplicateCount };
}
