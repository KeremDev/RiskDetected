export function hazardConfidence(hazard: Record<string, unknown>): number {
  const value = Number(hazard.confidence);
  return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
}

export function productionFindingNeedsFieldVerification(
  hazard: Record<string, unknown>,
): boolean {
  const confidence = hazardConfidence(hazard);
  return Boolean(hazard.needs_field_verification) ||
    (confidence >= 0.5 && confidence < 0.7);
}

export function productionConfidenceFinding(
  hazard: Record<string, unknown>,
): boolean {
  return hazardConfidence(hazard) >= 0.5;
}
