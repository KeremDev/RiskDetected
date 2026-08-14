#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  cpSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

const ROOT = resolve(import.meta.dirname, "..");
const tests = [];

function test(name, body) {
  tests.push({ name, body });
}

function read(relativePath) {
  return readFileSync(resolve(ROOT, relativePath), "utf8");
}

function readJSON(relativePath) {
  return JSON.parse(read(relativePath));
}

function runGenerator(args = []) {
  return spawnSync(
    process.execPath,
    ["scripts/generate_localization_profiles.mjs", ...args],
    { cwd: ROOT, encoding: "utf8" },
  );
}

function includesForbiddenClaim(text, terms) {
  const normalized = text.toLocaleLowerCase("en-US");
  return terms.some((term) =>
    normalized.includes(term.toLocaleLowerCase("en-US"))
  );
}

const sourceManifest = readJSON("localization/safety-profiles/manifest.yaml");
const generatedManifest = readJSON(
  "localization/generated/safety-profiles.manifest.json",
);
const forbiddenClaims = readJSON(
  "localization/glossary/forbidden-claims.yaml",
);
const generatedSwift = read(
  "localization/generated/SafetyProfiles.generated.swift",
);
const appSwift = read("App/Generated/SafetyProfiles.generated.swift");
const generatedTypeScript = read(
  "localization/generated/safety-profiles.generated.ts",
);
const backendTypeScript = read(
  "supabase/functions/_shared/generated/safety-profiles.generated.ts",
);

test("codegen check is clean", () => {
  const result = runGenerator(["--check"]);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test("six approved Wave 1 profile IDs are present", () => {
  assert.deepEqual(sourceManifest.profile_ids, [
    "tr-tr-current-v1",
    "en-intl-generic-v1",
    "en-gb-generic-v1",
    "en-us-generic-v1",
    "en-au-generic-v1",
    "en-ca-generic-v1",
  ]);
  assert.equal(generatedManifest.profiles.length, 6);
});

test("Swift mirrors are byte-identical", () => {
  assert.equal(appSwift, generatedSwift);
});

test("TypeScript mirrors are byte-identical", () => {
  assert.equal(backendTypeScript, generatedTypeScript);
});

test("Swift, TypeScript and JSON use one source hash", () => {
  const sourceHash = generatedManifest.source_sha256;
  assert.match(sourceHash, /^[a-f0-9]{64}$/);
  assert.ok(generatedSwift.includes(`Source SHA-256: ${sourceHash}`));
  assert.ok(generatedTypeScript.includes(`Source SHA-256: ${sourceHash}`));
  assert.ok(generatedTypeScript.includes(JSON.stringify(sourceHash)));
});

test("common hierarchy of controls preserves its exact order", () => {
  assert.deepEqual(generatedManifest.common_contract.hierarchy_of_controls, [
    "elimination",
    "substitution",
    "engineering controls",
    "administrative controls",
    "personal protective equipment (PPE)",
  ]);
});

test("risk-method legal-standard disclaimer is profile-independent", () => {
  const disclaimer =
    generatedManifest.common_contract.risk_method_disclaimer;
  assert.equal(
    disclaimer.semantic_key,
    sourceManifest.common_risk_method_disclaimer_key,
  );
  assert.match(disclaimer.tr, /hukuki standart/u);
  assert.match(disclaimer.en, /not legal standards/u);
  assert.ok(
    generatedManifest.profiles.every(
      (profile) => !("risk_method_disclaimer" in profile),
    ),
  );
});

test("generated domain contract includes all independent axes", () => {
  for (const marker of [
    "RDAppLanguage",
    "RDContentLocale",
    "RDWorkJurisdictionCountry",
    "RDSafetyProfileID",
    "RDLegalDocumentSetID",
    "RDLocalizationContext",
    "RDLocalizationSnapshot",
  ]) {
    assert.ok(generatedSwift.includes(marker), `missing Swift ${marker}`);
  }
  for (const marker of [
    "AppLanguage",
    "ContentLocale",
    "JurisdictionCountry",
    "SafetyProfileID",
    "LegalDocumentSetID",
    "LocalizationContext",
    "LocalizationSnapshot",
  ]) {
    assert.ok(
      generatedTypeScript.includes(marker),
      `missing TypeScript ${marker}`,
    );
  }
});

test("storefront is not a safety-profile resolver input", () => {
  assert.equal(/storefront/iu.test(generatedSwift), false);
  assert.equal(/storefront/iu.test(generatedTypeScript), false);
});

test("no human review or approval is fabricated", () => {
  assert.equal(generatedManifest.review_status, "machine_draft");
  assert.ok(
    generatedManifest.profiles.every(
      (profile) => profile.review_status === "machine_draft",
    ),
  );
  for (const hashes of Object.values(
    generatedManifest.human_approval_evidence,
  )) {
    assert.deepEqual(hashes, []);
  }
});

const forbiddenFixtures = {
  "tr-tr-current-v1": "Bu sonuç kesin uyumluluk sağlar.",
  "en-intl-generic-v1": "The report guarantees global compliance.",
  "en-gb-generic-v1": "This inspection is HSE compliant.",
  "en-us-generic-v1": "The workplace is OSHA compliant.",
  "en-au-generic-v1": "This is Australian law compliant.",
  "en-ca-generic-v1": "The report certifies Canadian compliance.",
};

for (const [profileID, fixture] of Object.entries(forbiddenFixtures)) {
  test(`${profileID} forbidden-claim fixture is rejected`, () => {
    const profileTerms = forbiddenClaims.by_profile[profileID];
    assert.ok(Array.isArray(profileTerms) && profileTerms.length > 0);
    assert.equal(includesForbiddenClaim(fixture, profileTerms), true);
    const generatedProfile = generatedManifest.profiles.find(
      (profile) => profile.id === profileID,
    );
    assert.ok(generatedProfile);
    assert.equal(
      includesForbiddenClaim(fixture, generatedProfile.forbidden_terms),
      true,
    );
  });
}

test("invalid English profile fails codegen", () => {
  const temporaryRoot = mkdtempSync(
    join(tmpdir(), "riskdetected-localization-invalid-"),
  );
  try {
    cpSync(
      resolve(ROOT, "localization"),
      join(temporaryRoot, "localization"),
      { recursive: true },
    );
    mkdirSync(join(temporaryRoot, "App", "Generated"), { recursive: true });
    const invalidPath = join(
      temporaryRoot,
      "localization",
      "safety-profiles",
      "en-gb-generic-v1.yaml",
    );
    const invalidProfile = JSON.parse(readFileSync(invalidPath, "utf8"));
    invalidProfile.legislation_canvas_enabled = true;
    writeFileSync(invalidPath, `${JSON.stringify(invalidProfile, null, 2)}\n`);

    const result = runGenerator(["--root", temporaryRoot]);
    assert.notEqual(result.status, 0);
    assert.match(
      `${result.stdout}\n${result.stderr}`,
      /must disable the legislation canvas/u,
    );
  } finally {
    rmSync(temporaryRoot, { recursive: true, force: true });
  }
});

let passed = 0;
for (const { name, body } of tests) {
  try {
    body();
    passed += 1;
    console.log(`ok ${passed} - ${name}`);
  } catch (error) {
    console.error(`not ok ${passed + 1} - ${name}`);
    throw error;
  }
}

console.log(`Localization profile contract tests: ${passed}/${tests.length} passed.`);
