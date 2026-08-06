import type { SafetyProfile } from "./safety-profile-manifest.ts";
import {
  LOCALIZATION_ERROR_CODES,
  LocalizationContractError,
} from "./localization-contract.ts";

export const LEGISLATION_CANVAS_ID = "legislation" as const;

export function assertCanvasAvailableForSafetyProfile(
  profile: SafetyProfile,
  canvasIDs: readonly string[],
): void {
  if (
    !profile.legislation_canvas_enabled &&
    canvasIDs.includes(LEGISLATION_CANVAS_ID)
  ) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.canvasUnavailable,
      400,
    );
  }
}
