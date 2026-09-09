export type ContextualFindingGuardResult = {
  findings: Array<Record<string, unknown>>;
  rejected_enclosed_cab_ppe_count: number;
};

function normalizedText(value: unknown): string {
  return value == null ? "" : String(value).toLocaleLowerCase("tr-TR")
    .replace(/ı/gu, "i")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/gu, "")
    .replace(/[^a-z0-9]+/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
}

function findingSearchText(finding: Record<string, unknown>): string {
  return [
    finding.title,
    finding.category,
    finding.observed_evidence,
    finding.description,
    finding.root_cause,
    finding.corrective_action,
    finding.preventive_control,
  ].map(normalizedText).filter(Boolean).join(" ");
}

function isPPEFinding(finding: Record<string, unknown>, text: string): boolean {
  const layers = Array.isArray(finding.inspection_layer_keys)
    ? finding.inspection_layer_keys.map(normalizedText)
    : [];
  return layers.includes("ppe") ||
    /(?:kisisel koruyucu|personal protective|\bppe\b|\bkkd\b)/u.test(text);
}

/**
 * A photograph cannot establish a head-protection or high-visibility clothing
 * violation for an operator who remains inside an enclosed machine cab. Site
 * rules and the operator's later exposure are outside the image. Reject only
 * that narrow claim; other visible PPE and seat-belt findings are untouched.
 */
export function applyContextualFindingGuard(
  findings: Array<Record<string, unknown>>,
  context: { scene_elements?: unknown; scene_summary?: unknown },
): ContextualFindingGuardResult {
  const sceneText = [
    ...(Array.isArray(context.scene_elements) ? context.scene_elements : []),
    context.scene_summary,
  ].map(normalizedText).filter(Boolean).join(" ");
  const sceneHasCab =
    /(?:operator kabin|surucu kabin|\bkabin\b|operator cab|enclosed cab|\bcabin\b)/u
      .test(sceneText);
  if (!sceneHasCab) {
    return { findings, rejected_enclosed_cab_ppe_count: 0 };
  }

  let rejected = 0;
  const accepted = findings.filter((finding) => {
    const findingText = findingSearchText(finding);
    const claimsHeadOrVisibilityPPE =
      /(?:\bbaret\b|\bkask\b|hard hat|safety helmet|\bhelmet\b|reflektorlu yelek|reflektif yelek|high visibility|hi vis|reflective vest)/u
        .test(findingText);
    const saysOperatorIsInsideCab =
      /(?:kabin\w* (?:icinde|icerisinde)|kabininde|inside (?:the )?(?:operator )?cab|inside (?:the )?cabin|within (?:the )?(?:operator )?cab)/u
        .test(findingText);
    const reject = isPPEFinding(finding, findingText) &&
      claimsHeadOrVisibilityPPE && saysOperatorIsInsideCab;
    if (reject) rejected += 1;
    return !reject;
  });
  return {
    findings: accepted,
    rejected_enclosed_cab_ppe_count: rejected,
  };
}
