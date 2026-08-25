import {
  PHOTO_ANALYSIS_JSON_SCHEMA,
  PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
  PROMPT_BUNDLE_POLICY_VERSION,
  PROMPT_BUNDLE_SHA256,
  SCHEMA_VERSION,
} from "./contracts.ts";
import { buildPrimaryPhotoPrompt, buildTargetedPrompt } from "./prompt.ts";
import { SECTOR_IDS, SECTOR_PROFILE_VERSION } from "./sector-profile.ts";

export async function sha256Text(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

/**
 * Canonical prompt bundle used by CI to prevent silent prompt mutation.
 *
 * Every sector and both output languages are included because sector content
 * is injected into the provider prompt. Targeted prompts cover the ordinary
 * local-component path and the bounded high-hazard guardrail branch. Response
 * schemas are included because Gemini's property ordering changes generation
 * behavior even when the natural-language prompt is unchanged.
 */
export function canonicalPromptBundle(): string {
  const primary = SECTOR_IDS.flatMap((sector) =>
    ["tr", "en"].map((language) => ({
      sector,
      language,
      prompt: buildPrimaryPhotoPrompt({
        photoIndex: 1,
        sector,
        focuses: ["canonical_prompt_bundle"],
        language,
        sectorProfileEnabled: true,
        sectorFrequencyPriorEnabled: true,
        sectorControlPreferencesEnabled: true,
        sectorNegativeRulesEnabled: true,
        compactProviderContractEnabled: true,
      }),
    }))
  );
  const targetedSignals = [
    {
      signal_id: "canonical-critical-hardware",
      photo_index: 1,
      reason_code: "critical_hardware_absence_requires_geometry_confirmation",
      evidence_region: {
        x: 0.2,
        y: 0.2,
        width: 0.3,
        height: 0.3,
        is_global: false,
      },
      affirmative_cues: ["visible empty retainer groove"],
      selected_targets: [{
        entity_ref: "canonical_asset_1",
        component: "pin_retainer",
        mechanism_code: "caught_in_pinch_shear",
      }],
    },
    {
      signal_id: "canonical-guardrail-coverage",
      photo_index: 1,
      reason_code: "multi_photo_high_hazard_guardrail_coverage",
      evidence_region: {
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        is_global: true,
      },
      affirmative_cues: ["elevated platform guardrail layer unresolved"],
      selected_targets: [],
    },
  ];
  const targeted = targetedSignals.flatMap((signal) =>
    ["tr", "en"].map((language) => ({
      language,
      signal_id: signal.signal_id,
      prompt: buildTargetedPrompt({
        photoIndex: 1,
        language,
        signal,
        sector: "construction",
        sectorProfileEnabled: true,
        compactProviderContractEnabled: true,
      }),
    }))
  );
  return JSON.stringify({
    policy: PROMPT_BUNDLE_POLICY_VERSION,
    schema_version: SCHEMA_VERSION,
    sector_profile_version: SECTOR_PROFILE_VERSION,
    primary,
    targeted,
    compact_schema: PHOTO_ANALYSIS_JSON_SCHEMA,
    legacy_schema: PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
  });
}

export async function computePromptBundleSHA256(): Promise<string> {
  return await sha256Text(canonicalPromptBundle());
}

export async function verifyPromptBundleIntegrity(): Promise<void> {
  const actual = await computePromptBundleSHA256();
  if (actual !== PROMPT_BUNDLE_SHA256) {
    throw new Error(
      `prompt_bundle_hash_mismatch:expected=${PROMPT_BUNDLE_SHA256}:actual=${actual}`,
    );
  }
}
