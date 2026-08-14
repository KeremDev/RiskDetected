import {
  defaultSafetyProfileID,
  hierarchyOfControls,
  riskMethodDisclaimer,
  type SafetyProfileID,
  safetyProfileManifestVersion,
  safetyProfiles,
  safetyProfileSourceSHA256,
} from "./approved-safety-profiles.generated.ts";
import {
  LOCALIZATION_ERROR_CODES,
  LocalizationContractError,
} from "./localization-contract.ts";

export type SafetyProfile = (typeof safetyProfiles)[number];

const profilesByID = new Map<string, SafetyProfile>(
  safetyProfiles.map((profile) => [profile.id, profile]),
);

export {
  defaultSafetyProfileID,
  hierarchyOfControls,
  riskMethodDisclaimer,
  safetyProfileManifestVersion,
  safetyProfileSourceSHA256,
};

export function safetyProfileByID(
  profileID: unknown,
): SafetyProfile | undefined {
  if (typeof profileID !== "string") return undefined;
  return profilesByID.get(profileID.trim());
}

export function requireSafetyProfile(profileID: unknown): SafetyProfile {
  const profile = safetyProfileByID(profileID);
  if (!profile) {
    throw new LocalizationContractError(
      LOCALIZATION_ERROR_CODES.profileUnknown,
      400,
    );
  }
  return profile;
}

export function isSafetyProfileID(value: unknown): value is SafetyProfileID {
  return safetyProfileByID(value) !== undefined;
}
