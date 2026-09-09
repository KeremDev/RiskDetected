export function hazardConfidence(hazard: Record<string, unknown>): number {
  const value = Number(hazard.confidence);
  return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
}

export function productionFindingNeedsFieldVerification(
  hazard: Record<string, unknown>,
): boolean {
  const confidence = hazardConfidence(hazard);
  const verificationReason = String(
    hazard.verification_reason_code ?? "",
  ).trim();
  const displayGroup = String(hazard.display_group ?? "").trim();
  const explicitPeriodicVerification =
    verificationReason === "periodic_inspection_status" &&
    displayGroup === "field_verification";

  // The model sometimes emits needs_field_verification=true even for a
  // directly visible finding with 0.85-0.90 confidence. Keep the production
  // contract deterministic: ordinary findings use the 0.50-0.69 band, while
  // server-created periodic-inspection items use their explicit reason/group.
  return explicitPeriodicVerification ||
    (confidence >= 0.5 && confidence < 0.7);
}

export function productionConfidenceFinding(
  hazard: Record<string, unknown>,
): boolean {
  return hazardConfidence(hazard) >= 0.5;
}
