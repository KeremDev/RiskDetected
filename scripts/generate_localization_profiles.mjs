#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import process from "node:process";

const rawArgs = process.argv.slice(2);
function option(name) {
  const index = rawArgs.indexOf(name);
  return index >= 0 && rawArgs[index + 1] ? rawArgs[index + 1] : null;
}

const ROOT = resolve(option("--root") ?? resolve(import.meta.dirname, ".."));
const PROFILE_DIR = join(ROOT, "localization", "safety-profiles");
const GLOSSARY_DIR = join(ROOT, "localization", "glossary");
const MANIFEST_PATH = join(PROFILE_DIR, "manifest.yaml");
const SCHEMA_PATH = join(PROFILE_DIR, "schema.json");
const CORE_GLOSSARY_PATH = join(GLOSSARY_DIR, "core.yaml");
const FORBIDDEN_PATH = join(GLOSSARY_DIR, "forbidden-claims.yaml");

const OUTPUTS = {
  swiftCanonical: join(ROOT, "localization", "generated", "SafetyProfiles.generated.swift"),
  swiftApp: join(ROOT, "App", "Generated", "SafetyProfiles.generated.swift"),
  tsCanonical: join(ROOT, "localization", "generated", "safety-profiles.generated.ts"),
  manifest: join(
    ROOT,
    "localization",
    "generated",
    "safety-profiles.manifest.json",
  ),
  tsBackend: join(
    ROOT,
    "supabase",
    "functions",
    "_shared",
    "generated",
    "safety-profiles.generated.ts",
  ),
};

const args = new Set(rawArgs);
const checkOnly = args.has("--check");

function readJsonYaml(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new Error(
      `${relative(ROOT, path)} JSON-compatible YAML parse failed: ${error.message}`,
    );
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertString(value, field, profileID) {
  assert(
    typeof value === "string" && value.length > 0,
    `${profileID}.${field} must be a non-empty string`,
  );
}

function validateProfile(profile, schema) {
  const profileID = profile.id ?? "<missing-id>";
  const required = new Set(schema.required);
  const allowed = new Set(Object.keys(schema.properties));
  const keys = Object.keys(profile);

  for (const field of required) {
    assert(field in profile, `${profileID} is missing required field ${field}`);
  }
  for (const field of keys) {
    assert(allowed.has(field), `${profileID} contains unsupported field ${field}`);
  }

  const enumFields = [
    "language",
    "content_locale",
    "jurisdiction_country",
    "status",
    "review_status",
    "default_risk_method",
    "regulatory_reference_policy",
    "spelling_style",
  ];
  for (const field of enumFields) {
    assert(
      schema.properties[field].enum.includes(profile[field]),
      `${profileID}.${field} has unsupported value ${profile[field]}`,
    );
  }

  for (const field of [
    "id",
    "display_name_key",
    "primary_product_term",
    "primary_domain_term",
    "finding_term",
    "hazard_term",
    "risk_assessment_term",
    "control_term",
    "corrective_action_term",
    "forbidden_claims_key",
  ]) {
    assertString(profile[field], field, profileID);
  }
  for (const field of ["id", "display_name_key", "forbidden_claims_key"]) {
    const pattern = schema.properties[field]?.pattern;
    if (pattern) {
      assert(
        new RegExp(pattern).test(profile[field]),
        `${profileID}.${field} does not match ${pattern}`,
      );
    }
  }

  assert(
    profile.jurisdiction_region === null ||
      (typeof profile.jurisdiction_region === "string" &&
        profile.jurisdiction_region.length >= 2),
    `${profileID}.jurisdiction_region must be null or a region identifier`,
  );
  assert(
    Array.isArray(profile.allowed_risk_methods) &&
      profile.allowed_risk_methods.length > 0,
    `${profileID}.allowed_risk_methods must not be empty`,
  );
  assert(
    new Set(profile.allowed_risk_methods).size ===
      profile.allowed_risk_methods.length,
    `${profileID}.allowed_risk_methods contains duplicates`,
  );
  assert(
    profile.allowed_risk_methods.every((method) =>
      schema.properties.allowed_risk_methods.items.enum.includes(method)
    ),
    `${profileID}.allowed_risk_methods contains an unsupported method`,
  );
  assert(
    profile.allowed_risk_methods.includes(profile.default_risk_method),
    `${profileID}.default_risk_method must be allowed`,
  );
  assert(
    Array.isArray(profile.prompt_directives) &&
      profile.prompt_directives.length > 0 &&
      profile.prompt_directives.every(
        (value) => typeof value === "string" && value.length > 0,
      ),
    `${profileID}.prompt_directives must contain non-empty strings`,
  );
  assert(
    new Set(profile.prompt_directives).size === profile.prompt_directives.length,
    `${profileID}.prompt_directives contains duplicates`,
  );
  assert(
    Number.isInteger(profile.profile_version) && profile.profile_version >= 1,
    `${profileID}.profile_version must be a positive integer`,
  );
  assert(
    profile.id.endsWith(`-v${profile.profile_version}`),
    `${profileID} suffix and profile_version differ`,
  );
  assert(
    profile.forbidden_claims_key === profile.id,
    `${profileID}.forbidden_claims_key must equal the versioned profile id`,
  );

  const booleanFields = [
    "legislation_canvas_enabled",
    "structured_regulatory_references_enabled",
    "legal_compliance_claims_allowed",
  ];
  for (const field of booleanFields) {
    assert(
      typeof profile[field] === "boolean",
      `${profileID}.${field} must be boolean`,
    );
  }

  if (profile.language === "en") {
    assert(
      profile.status === "terminology_only",
      `${profileID} English Wave 1 profiles must be terminology_only`,
    );
    assert(
      profile.legislation_canvas_enabled === false,
      `${profileID} must disable the legislation canvas`,
    );
    assert(
      profile.structured_regulatory_references_enabled === false,
      `${profileID} must disable structured regulatory references`,
    );
    assert(
      profile.regulatory_reference_policy === "none",
      `${profileID} must use regulatory_reference_policy=none`,
    );
    assert(
      profile.legal_compliance_claims_allowed === false,
      `${profileID} must prohibit legal compliance claims`,
    );
  }
}

function loadContract() {
  const manifest = readJsonYaml(MANIFEST_PATH);
  const schema = readJsonYaml(SCHEMA_PATH);
  const coreGlossary = readJsonYaml(CORE_GLOSSARY_PATH);
  const forbidden = readJsonYaml(FORBIDDEN_PATH);
  const glossaryFiles = readdirSync(GLOSSARY_DIR)
    .filter((name) => name.endsWith(".yaml"))
    .sort();
  const glossaryContracts = new Map(
    glossaryFiles.map((name) => [
      name,
      readJsonYaml(join(GLOSSARY_DIR, name)),
    ]),
  );
  const allowedReviewStatuses = new Set([
    "extracted",
    "machine_draft",
    "language_reviewed",
    "safety_reviewed",
    "product_approved",
    "shipping",
  ]);
  for (const [name, glossary] of glossaryContracts) {
    assert(
      Number.isInteger(glossary.version) && glossary.version >= 1,
      `${name}.version must be a positive integer`,
    );
    assert(
      allowedReviewStatuses.has(glossary.review_status),
      `${name}.review_status is invalid`,
    );
  }
  assert(
    Array.isArray(forbidden.global) &&
      forbidden.global.length > 0 &&
      new Set(forbidden.global).size === forbidden.global.length,
    "forbidden-claims global terms must be non-empty and unique",
  );
  const profileFiles = readdirSync(PROFILE_DIR)
    .filter((name) => name.endsWith(".yaml") && name !== "manifest.yaml")
    .sort();
  const byID = new Map(
    profileFiles.map((name) => {
      const profile = readJsonYaml(join(PROFILE_DIR, name));
      return [profile.id, profile];
    }),
  );

  assert(
    byID.size === profileFiles.length,
    "Safety profile ids must be unique",
  );
  assert(
    Array.isArray(manifest.profile_ids) &&
      manifest.profile_ids.length === byID.size,
    "manifest.profile_ids must list every profile exactly once",
  );
  assert(
    new Set(manifest.profile_ids).size === manifest.profile_ids.length,
    "manifest.profile_ids contains duplicates",
  );
  assert(
    manifest.review_status === "machine_draft",
    "manifest.review_status must remain machine_draft until human review",
  );
  assert(
    Array.isArray(manifest.legal_document_set_ids) &&
      manifest.legal_document_set_ids.length >= 2 &&
      new Set(manifest.legal_document_set_ids).size ===
        manifest.legal_document_set_ids.length,
    "manifest.legal_document_set_ids must be unique",
  );

  const expectedHierarchy = [
    "elimination",
    "substitution",
    "engineering controls",
    "administrative controls",
    "personal protective equipment (PPE)",
  ];
  assert(
    JSON.stringify(coreGlossary.hierarchy_of_controls) ===
      JSON.stringify(expectedHierarchy),
    "core glossary hierarchy_of_controls must preserve the approved order",
  );
  const disclaimer = coreGlossary.risk_method_disclaimer;
  assert(
    disclaimer?.semantic_key === manifest.common_risk_method_disclaimer_key,
    "risk method disclaimer key must match the manifest",
  );
  assert(
    disclaimer?.review_status === "machine_draft",
    "risk method disclaimer must remain machine_draft until human review",
  );
  for (const language of ["tr", "en"]) {
    assert(
      typeof disclaimer?.[language] === "string" &&
        disclaimer[language].length > 40,
      `risk method disclaimer ${language} copy is missing`,
    );
  }

  const profiles = manifest.profile_ids.map((id) => {
    assert(byID.has(id), `manifest references missing profile ${id}`);
    const profile = byID.get(id);
    validateProfile(profile, schema);
    const terms = forbidden.by_profile?.[profile.forbidden_claims_key];
    assert(
      Array.isArray(terms) && terms.length > 0,
      `${id} has no forbidden claims glossary entry`,
    );
    assert(
      new Set(terms).size === terms.length,
      `${id} forbidden claims contains duplicates`,
    );
    return {
      ...profile,
      forbidden_terms: [...new Set([...(forbidden.global ?? []), ...terms])],
    };
  });

  assert(
    profiles.some((profile) => profile.id === manifest.default_profile_id),
    "default_profile_id is not present",
  );
  assert(
    profiles.some(
      (profile) => profile.id === manifest.english_fallback_profile_id,
    ),
    "english_fallback_profile_id is not present",
  );

  const expectedPairs = {
    "tr-tr-current-v1": ["tr-TR", "TR"],
    "en-intl-generic-v1": ["en-001", "INTL"],
    "en-gb-generic-v1": ["en-GB", "GB"],
    "en-us-generic-v1": ["en-US", "US"],
    "en-au-generic-v1": ["en-AU", "AU"],
    "en-ca-generic-v1": ["en-CA", "CA"],
  };
  for (const profile of profiles) {
    const expected = expectedPairs[profile.id];
    assert(expected, `${profile.id} is not an approved Wave 1 profile`);
    assert(
      profile.content_locale === expected[0] &&
        profile.jurisdiction_country === expected[1],
      `${profile.id} locale/jurisdiction mapping is invalid`,
    );
  }

  const sourcePaths = [
    MANIFEST_PATH,
    SCHEMA_PATH,
    ...glossaryFiles.map((name) => join(GLOSSARY_DIR, name)),
    ...profileFiles.map((name) => join(PROFILE_DIR, name)),
  ];
  const sourceHash = createHash("sha256");
  for (const path of sourcePaths.sort()) {
    sourceHash.update(relative(ROOT, path));
    sourceHash.update("\0");
    sourceHash.update(readFileSync(path));
    sourceHash.update("\0");
  }

  return {
    manifest,
    profiles,
    commonContract: {
      hierarchy_of_controls: coreGlossary.hierarchy_of_controls,
      risk_method_disclaimer: disclaimer,
      risk_band_drafts: coreGlossary.risk_band_drafts,
    },
    glossaryVersions: Object.fromEntries(
      glossaryFiles.map((name) => [name, glossaryContracts.get(name).version]),
    ),
    sourceHash: sourceHash.digest("hex"),
  };
}

function swiftString(value) {
  return JSON.stringify(value)
    .replaceAll("\\/", "/")
    .replaceAll("\\u2028", "\\u{2028}")
    .replaceAll("\\u2029", "\\u{2029}");
}

function swiftArray(values) {
  return `[${values.map(swiftString).join(", ")}]`;
}

const swiftAppLanguageCases = {
  tr: "turkish",
  en: "english",
};
const swiftLocaleCases = {
  "tr-TR": "turkishTurkey",
  "en-001": "englishInternational",
  "en-GB": "englishUnitedKingdom",
  "en-US": "englishUnitedStates",
  "en-AU": "englishAustralia",
  "en-CA": "englishCanada",
};
const swiftCountryCases = {
  TR: "turkey",
  INTL: "international",
  GB: "unitedKingdom",
  US: "unitedStates",
  AU: "australia",
  CA: "canada",
};
const swiftProfileCases = {
  "tr-tr-current-v1": "turkeyCurrentV1",
  "en-intl-generic-v1": "englishInternationalGenericV1",
  "en-gb-generic-v1": "englishUnitedKingdomGenericV1",
  "en-us-generic-v1": "englishUnitedStatesGenericV1",
  "en-au-generic-v1": "englishAustraliaGenericV1",
  "en-ca-generic-v1": "englishCanadaGenericV1",
};
const swiftLegalDocumentSetCases = {
  "tr-current": "turkeyCurrent",
  "en-global-v1": "englishGlobalV1",
};
const swiftRiskMethodCases = {
  fine_kinney: "fineKinney",
  matrix_5x5: "matrix5x5",
};

function generateSwift(contract) {
  const { manifest, profiles, commonContract, sourceHash } = contract;
  const enumCases = (values, names) =>
    values
      .map((value) => `    case ${names[value]} = ${swiftString(value)}`)
      .join("\n");
  const profileRows = profiles
    .map(
      (profile) => `        RDSafetyProfileDefinition(
            id: .${swiftProfileCases[profile.id]},
            language: .${swiftAppLanguageCases[profile.language]},
            contentLocale: .${swiftLocaleCases[profile.content_locale]},
            jurisdictionCountry: .${swiftCountryCases[profile.jurisdiction_country]},
            jurisdictionRegion: ${profile.jurisdiction_region === null ? "nil" : swiftString(profile.jurisdiction_region)},
            status: ${swiftString(profile.status)},
            reviewStatus: ${swiftString(profile.review_status)},
            displayNameKey: ${swiftString(profile.display_name_key)},
            primaryProductTerm: ${swiftString(profile.primary_product_term)},
            primaryDomainTerm: ${swiftString(profile.primary_domain_term)},
            findingTerm: ${swiftString(profile.finding_term)},
            hazardTerm: ${swiftString(profile.hazard_term)},
            riskAssessmentTerm: ${swiftString(profile.risk_assessment_term)},
            controlTerm: ${swiftString(profile.control_term)},
            correctiveActionTerm: ${swiftString(profile.corrective_action_term)},
            defaultRiskMethod: .${swiftRiskMethodCases[profile.default_risk_method]},
            allowedRiskMethods: [${profile.allowed_risk_methods.map((method) => `.${swiftRiskMethodCases[method]}`).join(", ")}],
            legislationCanvasEnabled: ${profile.legislation_canvas_enabled},
            structuredRegulatoryReferencesEnabled: ${profile.structured_regulatory_references_enabled},
            regulatoryReferencePolicy: .${profile.regulatory_reference_policy === "tr_current" ? "turkeyCurrent" : profile.regulatory_reference_policy === "explicit_question_only" ? "explicitQuestionOnly" : "none"},
            legalComplianceClaimsAllowed: ${profile.legal_compliance_claims_allowed},
            spellingStyle: ${swiftString(profile.spelling_style)},
            promptDirectives: ${swiftArray(profile.prompt_directives)},
            forbiddenTerms: ${swiftArray(profile.forbidden_terms)},
            profileVersion: ${profile.profile_version}
        )`,
    )
    .join(",\n");

  return `// Generated by scripts/generate_localization_profiles.mjs.
// Do not edit manually. Source SHA-256: ${sourceHash}

import Foundation

enum RDAppLanguage: String, Codable, CaseIterable, Sendable {
${enumCases(manifest.app_languages, swiftAppLanguageCases)}
}

enum RDContentLocale: String, Codable, CaseIterable, Sendable {
${enumCases(manifest.content_locales, swiftLocaleCases)}
}

enum RDWorkJurisdictionCountry: String, Codable, CaseIterable, Sendable {
${enumCases(manifest.jurisdiction_countries, swiftCountryCases)}
}

enum RDRegulatoryReferencePolicy: String, Codable, Sendable {
    case turkeyCurrent = "tr_current"
    case none = "none"
    case explicitQuestionOnly = "explicit_question_only"
}

enum RDSafetyProfileID: String, Codable, CaseIterable, Sendable {
${enumCases(manifest.profile_ids, swiftProfileCases)}
}

enum RDLegalDocumentSetID: String, Codable, CaseIterable, Sendable {
${enumCases(manifest.legal_document_set_ids, swiftLegalDocumentSetCases)}
}

enum RDRiskMethod: String, Codable, CaseIterable, Sendable {
${enumCases(["fine_kinney", "matrix_5x5"], swiftRiskMethodCases)}
}

struct RDSafetyProfileDefinition: Sendable {
    let id: RDSafetyProfileID
    let language: RDAppLanguage
    let contentLocale: RDContentLocale
    let jurisdictionCountry: RDWorkJurisdictionCountry
    let jurisdictionRegion: String?
    let status: String
    let reviewStatus: String
    let displayNameKey: String
    let primaryProductTerm: String
    let primaryDomainTerm: String
    let findingTerm: String
    let hazardTerm: String
    let riskAssessmentTerm: String
    let controlTerm: String
    let correctiveActionTerm: String
    let defaultRiskMethod: RDRiskMethod
    let allowedRiskMethods: [RDRiskMethod]
    let legislationCanvasEnabled: Bool
    let structuredRegulatoryReferencesEnabled: Bool
    let regulatoryReferencePolicy: RDRegulatoryReferencePolicy
    let legalComplianceClaimsAllowed: Bool
    let spellingStyle: String
    let promptDirectives: [String]
    let forbiddenTerms: [String]
    let profileVersion: Int
}

struct RDLocalizationContext: Codable, Equatable, Sendable {
    let appLanguage: RDAppLanguage
    let outputLanguage: RDAppLanguage
    let outputLocale: RDContentLocale
    let workJurisdictionCountry: RDWorkJurisdictionCountry
    let workJurisdictionRegion: String?
    let safetyProfileID: RDSafetyProfileID
    let safetyProfileVersion: Int
    let riskMethod: RDRiskMethod
    let legalDocumentSetID: RDLegalDocumentSetID
}

struct RDLocalizationSnapshot: Codable, Equatable, Sendable {
    let context: RDLocalizationContext
    let regulatoryReferencePolicy: RDRegulatoryReferencePolicy
    let promptProfileVersion: Int
}

enum RDSafetyProfileCatalog {
    static let manifestVersion = ${manifest.manifest_version}
    static let sourceSHA256 = ${swiftString(sourceHash)}
    static let defaultProfileID = RDSafetyProfileID.${swiftProfileCases[manifest.default_profile_id]}
    static let englishFallbackProfileID = RDSafetyProfileID.${swiftProfileCases[manifest.english_fallback_profile_id]}
    static let hierarchyOfControls = ${swiftArray(commonContract.hierarchy_of_controls)}
    static let riskMethodDisclaimerKey = ${swiftString(commonContract.risk_method_disclaimer.semantic_key)}
    static let riskMethodDisclaimerTurkish = ${swiftString(commonContract.risk_method_disclaimer.tr)}
    static let riskMethodDisclaimerEnglish = ${swiftString(commonContract.risk_method_disclaimer.en)}

    static let profiles: [RDSafetyProfileDefinition] = [
${profileRows}
    ]

    static func profile(id: RDSafetyProfileID) -> RDSafetyProfileDefinition {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            preconditionFailure("Generated safety profile manifest is incomplete.")
        }
        return profile
    }
}
`;
}

function generateTypeScript(contract) {
  const { manifest, profiles, commonContract, sourceHash } = contract;
  const generatedProfiles = profiles.map(
    ({ forbidden_claims_key: _key, ...profile }) => profile,
  );
  return `// Generated by scripts/generate_localization_profiles.mjs.
// Do not edit manually. Source SHA-256: ${sourceHash}

export const safetyProfileManifestVersion = ${manifest.manifest_version} as const;
export const safetyProfileSourceSHA256 = ${JSON.stringify(sourceHash)} as const;
export const safetyProfileReviewStatus = ${JSON.stringify(manifest.review_status)} as const;

export const appLanguages = ${JSON.stringify(manifest.app_languages)} as const;
export type AppLanguage = (typeof appLanguages)[number];

export const contentLocales = ${JSON.stringify(manifest.content_locales)} as const;
export type ContentLocale = (typeof contentLocales)[number];

export const jurisdictionCountries = ${JSON.stringify(manifest.jurisdiction_countries)} as const;
export type JurisdictionCountry = (typeof jurisdictionCountries)[number];

export const legalDocumentSetIDs = ${JSON.stringify(manifest.legal_document_set_ids)} as const;
export type LegalDocumentSetID = (typeof legalDocumentSetIDs)[number];

export const riskMethods = ["fine_kinney", "matrix_5x5"] as const;
export type RiskMethod = (typeof riskMethods)[number];

export const safetyProfileIDs = ${JSON.stringify(manifest.profile_ids)} as const;
export type SafetyProfileID = (typeof safetyProfileIDs)[number];

export type RegulatoryReferencePolicy =
  | "tr_current"
  | "none"
  | "explicit_question_only";

export const defaultSafetyProfileID: SafetyProfileID =
  ${JSON.stringify(manifest.default_profile_id)};
export const englishFallbackSafetyProfileID: SafetyProfileID =
  ${JSON.stringify(manifest.english_fallback_profile_id)};

export const hierarchyOfControls = ${JSON.stringify(commonContract.hierarchy_of_controls)} as const;
export const riskMethodDisclaimer = ${JSON.stringify(commonContract.risk_method_disclaimer, null, 2)} as const;
export const riskBandDrafts = ${JSON.stringify(commonContract.risk_band_drafts, null, 2)} as const;

export const safetyProfiles = ${JSON.stringify(generatedProfiles, null, 2)} as const;
export type SafetyProfileDefinition = (typeof safetyProfiles)[number];

export interface LocalizationContext {
  app_language: AppLanguage;
  output_language: AppLanguage;
  output_locale: ContentLocale;
  work_jurisdiction_country: JurisdictionCountry;
  work_jurisdiction_region: string | null;
  safety_profile_id: SafetyProfileID;
  safety_profile_version: number;
  method: RiskMethod;
  legal_document_set: LegalDocumentSetID;
}

export interface LocalizationSnapshot {
  context: LocalizationContext;
  regulatory_reference_policy: RegulatoryReferencePolicy;
  prompt_profile_version: number;
}

const safetyProfileByID = new Map<SafetyProfileID, SafetyProfileDefinition>(
  safetyProfiles.map((profile) => [profile.id, profile]),
);

export function isSafetyProfileID(value: unknown): value is SafetyProfileID {
  return typeof value === "string" &&
    (safetyProfileIDs as readonly string[]).includes(value);
}

export function getSafetyProfile(id: SafetyProfileID): SafetyProfileDefinition {
  const profile = safetyProfileByID.get(id);
  if (!profile) {
    throw new Error("safety_profile_manifest_incomplete");
  }
  return profile;
}
`;
}

function generateManifestJSON(contract) {
  const {
    manifest,
    profiles,
    commonContract,
    glossaryVersions,
    sourceHash,
  } = contract;
  return `${JSON.stringify(
    {
      schema_version: 1,
      manifest_version: manifest.manifest_version,
      source_sha256: sourceHash,
      review_status: manifest.review_status,
      default_profile_id: manifest.default_profile_id,
      english_fallback_profile_id: manifest.english_fallback_profile_id,
      app_languages: manifest.app_languages,
      content_locales: manifest.content_locales,
      jurisdiction_countries: manifest.jurisdiction_countries,
      legal_document_set_ids: manifest.legal_document_set_ids,
      common_contract: commonContract,
      profiles,
      glossary_versions: glossaryVersions,
      human_approval_evidence: {
        language_review_hashes: [],
        safety_review_hashes: [],
        product_approval_hashes: [],
      },
    },
    null,
    2,
  )}\n`;
}

function writeOrCheck(path, content) {
  if (checkOnly) {
    let existing = "";
    try {
      existing = readFileSync(path, "utf8");
    } catch {
      throw new Error(`${relative(ROOT, path)} is missing; run codegen`);
    }
    assert(
      existing === content,
      `${relative(ROOT, path)} is stale; run codegen`,
    );
    return;
  }
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

const contract = loadContract();
const swift = generateSwift(contract);
const typeScript = generateTypeScript(contract);
const generatedManifest = generateManifestJSON(contract);

writeOrCheck(OUTPUTS.swiftCanonical, swift);
writeOrCheck(OUTPUTS.swiftApp, swift);
writeOrCheck(OUTPUTS.tsCanonical, typeScript);
writeOrCheck(OUTPUTS.tsBackend, typeScript);
writeOrCheck(OUTPUTS.manifest, generatedManifest);

console.log(
  `${checkOnly ? "Verified" : "Generated"} ${contract.profiles.length} safety profiles (${contract.sourceHash.slice(0, 16)}).`,
);
