import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  AI_OUTPUT_VALIDATION_LAYER_IDS,
  OUTPUT_LANGUAGE_CONTRACT_FAILED,
  OutputLanguageContractError,
  validateAIOutputContract,
  validateAIOutputWithSingleRepair,
} from "./ai-localization-validation.ts";
import { resolveLocalizationContext } from "./localization-context-resolver.ts";
import {
  type SafetyProfileID,
  safetyProfiles,
  safetyProfileSourceSHA256,
} from "./generated/safety-profiles.generated.ts";

const enabledProfileIDs = new Set(
  safetyProfiles.filter((profile) => profile.language === "en").map((profile) =>
    profile.id
  ),
);

function snapshotFor(profileID: SafetyProfileID) {
  const profile = safetyProfiles.find((candidate) =>
    candidate.id === profileID
  );
  if (!profile) throw new Error(`Unknown fixture profile: ${profileID}`);
  return resolveLocalizationContext({
    request: {
      safety_profile_id: profile.id,
      safety_profile_version: profile.profile_version,
      output_language: profile.language,
      output_locale: profile.content_locale,
      work_jurisdiction_country: profile.jurisdiction_country,
      method: profile.default_risk_method,
    },
    persistedMethod: profile.default_risk_method,
    workerInvocation: false,
    rolloutPolicy: {
      enabledProfileIDs,
      queueSnapshotAuthorityEnabled: true,
      approvedSafetyProfileSourceSHA256: safetyProfileSourceSHA256,
    },
  });
}

const profileText: Record<SafetyProfileID, {
  title: string;
  category: string;
  evidence: string;
  description: string;
  cause: string;
  corrective: string;
  preventive: string;
  summary: string;
}> = {
  "tr-tr-current-v1": {
    title: "Koruyucusuz hareketli parça",
    category: "Makine güvenliği",
    evidence: "Dönen parça çalışan erişimine açık görünüyor.",
    description: "Temas halinde sıkışma ve yaralanma tehlikesi bulunuyor.",
    cause: "Makine koruyucusu yerinde görünmüyor.",
    corrective: "Ekipmanı durdur ve uygun koruyucuyu tak.",
    preventive: "Koruyucu kontrolünü vardiya öncesi listeye ekle.",
    summary: "Görselde doğrulanabilen bir makine güvenliği bulgusu var.",
  },
  "en-intl-generic-v1": {
    title: "Exposed moving part",
    category: "Workplace safety",
    evidence: "A rotating part is visibly accessible to a worker.",
    description: "Contact could cause an entanglement or crushing hazard.",
    cause: "The machine guard is not visible in its operating position.",
    corrective: "Stop the equipment and install an effective control measure.",
    preventive: "Add guard verification to the pre-use safety inspection.",
    summary: "One visible workplace safety finding requires control.",
  },
  "en-gb-generic-v1": {
    title: "Exposed moving part",
    category: "Health and safety",
    evidence: "A rotating part is visibly accessible to a worker.",
    description: "Contact could cause an entanglement or crushing hazard.",
    cause: "The machine guard is not visible in its operating position.",
    corrective: "Stop the equipment and install an effective control measure.",
    preventive:
      "Add guard verification to the prioritised pre-use risk assessment.",
    summary: "One visible health and safety finding requires control.",
  },
  "en-us-generic-v1": {
    title: "Exposed moving part",
    category: "Occupational safety and health",
    evidence: "A rotating part is visibly accessible to a worker.",
    description: "Contact could cause an entanglement or crushing hazard.",
    cause: "The machine guard is not visible in its operating position.",
    corrective: "Stop the equipment and install an effective control.",
    preventive: "Add guard verification to the prioritized hazard assessment.",
    summary: "One visible occupational safety and health finding needs action.",
  },
  "en-au-generic-v1": {
    title: "Exposed moving part",
    category: "Work health and safety",
    evidence: "A rotating part is visibly accessible to a worker.",
    description: "Contact could cause an entanglement or crushing hazard.",
    cause: "The machine guard is not visible in its operating position.",
    corrective: "Stop the equipment and install an effective control measure.",
    preventive: "Add guard verification to the pre-use WHS inspection.",
    summary: "One visible work health and safety finding requires control.",
  },
  "en-ca-generic-v1": {
    title: "Exposed moving part",
    category: "Occupational health and safety",
    evidence: "A rotating part is visibly accessible to a worker.",
    description: "Contact could cause an entanglement or crushing hazard.",
    cause: "The machine guard is not visible in its operating position.",
    corrective: "Stop the equipment and install an effective control measure.",
    preventive: "Add guard verification to the pre-use risk assessment.",
    summary: "One visible occupational health and safety finding needs action.",
  },
};

function validOutput(profileID: SafetyProfileID): Record<string, unknown> {
  const text = profileText[profileID];
  return {
    hazards: [{
      title: text.title,
      category: text.category,
      observed_evidence: text.evidence,
      description: text.description,
      root_cause: text.cause,
      corrective_action: text.corrective,
      preventive_control: text.preventive,
      references: "",
      confidence: 0.86,
      needs_field_verification: false,
      fk_probability: 3,
      fk_frequency: 2,
      fk_severity: 15,
      m5_probability: 3,
      m5_severity: 4,
      source_photo_indices: [1],
    }],
    ai_summary: text.summary,
    limitations: profileID === "tr-tr-current-v1"
      ? "Yalnız görünür kanıt değerlendirildi."
      : "Only visible evidence was assessed.",
  };
}

Deno.test("six-profile output validator matrix is green in fixed order", () => {
  for (const profile of safetyProfiles) {
    const validation = validateAIOutputContract(
      validOutput(profile.id),
      snapshotFor(profile.id),
    );
    assertEquals(validation.ok, true, profile.id);
    assertEquals(
      validation.layers.map((layer) => layer.id),
      [...AI_OUTPUT_VALIDATION_LAYER_IDS],
      profile.id,
    );
  }
});

Deno.test("English output rejects Turkish user-visible leakage", () => {
  const validation = validateAIOutputContract(
    validOutput("tr-tr-current-v1"),
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(validation.failedLayer, "output_language");
  assertEquals(validation.code, "OUTPUT_LANGUAGE_TURKISH_LEAK");
});

Deno.test("English output rejects third-language user-visible prose", () => {
  const thirdLanguageCases = [
    {
      language: "French",
      values: [
        "Pièce mobile exposée",
        "Sécurité au travail",
        "Une pièce rotative est visiblement accessible à un opérateur.",
        "Le contact peut provoquer un coincement ou un écrasement grave.",
        "Le protecteur de la machine ne paraît pas installé correctement.",
        "Arrêtez l’équipement et installez une protection efficace.",
        "Ajoutez la vérification du protecteur à l’inspection avant utilisation.",
        "Une situation visible nécessite une mesure de prévention.",
      ],
    },
    {
      language: "Spanish",
      values: [
        "Pieza móvil expuesta",
        "Seguridad en el trabajo",
        "Una pieza giratoria está visiblemente accesible para el operador.",
        "El contacto puede causar atrapamiento o lesiones por aplastamiento.",
        "La protección de la máquina no aparece en su posición correcta.",
        "Detenga el equipo e instale una protección eficaz.",
        "Añada la verificación a la inspección antes de cada uso.",
        "Una condición visible requiere una medida preventiva.",
      ],
    },
    {
      language: "Japanese",
      values: [
        "露出した可動部",
        "職場の安全",
        "回転部分に作業者が触れられる状態が画像で確認できます。",
        "接触すると巻き込まれや重大な負傷につながる可能性があります。",
        "機械の保護装置が所定の位置にないように見えます。",
        "装置を停止して有効な保護装置を取り付けてください。",
        "使用前点検に保護装置の確認を追加してください。",
        "画像で確認できる状態には予防措置が必要です。",
      ],
    },
  ] as const;

  for (const testCase of thirdLanguageCases) {
    const output = validOutput("en-intl-generic-v1");
    const finding = (output.hazards as Array<Record<string, unknown>>)[0];
    const [
      title,
      category,
      observedEvidence,
      description,
      rootCause,
      correctiveAction,
      preventiveControl,
      summary,
    ] = testCase.values;
    Object.assign(finding, {
      title,
      category,
      observed_evidence: observedEvidence,
      description,
      root_cause: rootCause,
      corrective_action: correctiveAction,
      preventive_control: preventiveControl,
    });
    output.ai_summary = summary;
    const validation = validateAIOutputContract(
      output,
      snapshotFor("en-intl-generic-v1"),
    );
    assertEquals(
      validation.failedLayer,
      "output_language",
      testCase.language,
    );
    assertEquals(
      validation.code,
      "OUTPUT_LANGUAGE_ENGLISH_REQUIRED",
      testCase.language,
    );
  }
});

Deno.test("a single English profile term cannot mask third-language prose", () => {
  const output = validOutput("en-intl-generic-v1");
  const finding = (output.hazards as Array<Record<string, unknown>>)[0];
  finding.category = "Workplace safety";
  finding.observed_evidence =
    "Une pièce rotative est clairement accessible à proximité de l’opérateur.";
  finding.description =
    "Le contact avec cette pièce peut provoquer une blessure grave.";
  finding.root_cause =
    "Le protecteur de la machine ne paraît pas installé correctement.";
  finding.corrective_action =
    "Arrêtez immédiatement la machine et installez une protection efficace.";
  finding.preventive_control =
    "Ajoutez cette vérification à chaque inspection avant utilisation.";
  output.ai_summary =
    "La situation visible nécessite une mesure corrective avant utilisation.";

  const validation = validateAIOutputContract(
    output,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(validation.failedLayer, "output_language");
  assertEquals(validation.code, "OUTPUT_LANGUAGE_ENGLISH_REQUIRED");
});

Deno.test("English output permits quoted Turkish text only as visible evidence", () => {
  const output = validOutput("en-intl-generic-v1");
  const finding = (output.hazards as Array<Record<string, unknown>>)[0];
  finding.observed_evidence =
    "A visible sign reads “Dikkat: Elektrik Tehlikesi”; the sign text is treated as evidence.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(validation.ok, true);
});

Deno.test("exact user-owned Turkish proper nouns are excluded from language scoring", () => {
  const companyName = "Çalışan Güvenliği Tehlike Önlem Merkezi";
  const output = validOutput("en-intl-generic-v1");
  (output.hazards as Array<Record<string, unknown>>)[0].title =
    `Guarding issue at ${companyName}`;

  const withoutExemption = validateAIOutputContract(
    output,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(withoutExemption.failedLayer, "output_language");

  const withExemption = validateAIOutputContract(
    output,
    snapshotFor("en-intl-generic-v1"),
    { allowedUserAuthoredValues: [companyName] },
  );
  assertEquals(withExemption.ok, true);
});

Deno.test("quoted system prose outside evidence cannot bypass language validation", () => {
  const output = validOutput("tr-tr-current-v1");
  const finding = (output.hazards as Array<Record<string, unknown>>)[0];
  for (
    const field of [
      "title",
      "category",
      "description",
      "root_cause",
      "corrective_action",
      "preventive_control",
    ]
  ) {
    finding[field] = `“${finding[field]}”`;
  }
  const validation = validateAIOutputContract(
    output,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(validation.failedLayer, "output_language");
  assertEquals(validation.code, "OUTPUT_LANGUAGE_TURKISH_LEAK");
});

Deno.test("country profiles reject cross-terminology before regulatory claims", () => {
  const cases = [
    ["en-gb-generic-v1", "OSHA inspection"],
    ["en-us-generic-v1", "HSE inspection"],
    ["en-au-generic-v1", "OSHA inspection"],
    ["en-ca-generic-v1", "WHS Act inspection"],
  ] as const;
  for (const [profileID, category] of cases) {
    const output = validOutput(profileID);
    (output.hazards as Array<Record<string, unknown>>)[0].category = category;
    const validation = validateAIOutputContract(
      output,
      snapshotFor(profileID),
    );
    assertEquals(
      validation.failedLayer,
      "safety_profile_terminology",
      profileID,
    );
    assertEquals(
      validation.code,
      "SAFETY_PROFILE_CROSS_TERMINOLOGY_LEAK",
      profileID,
    );
  }
});

Deno.test("English profiles require their generated primary domain terminology", () => {
  for (
    const profileID of [
      "en-intl-generic-v1",
      "en-gb-generic-v1",
      "en-us-generic-v1",
      "en-au-generic-v1",
      "en-ca-generic-v1",
    ] as const
  ) {
    const output = validOutput(profileID);
    const finding = (output.hazards as Array<Record<string, unknown>>)[0];
    finding.category = "General inspection";
    output.ai_summary = "One visible issue requires action.";
    const validation = validateAIOutputContract(
      output,
      snapshotFor(profileID),
    );
    assertEquals(
      validation.failedLayer,
      "safety_profile_terminology",
      profileID,
    );
    assertEquals(
      validation.code,
      "SAFETY_PROFILE_REQUIRED_TERMINOLOGY_MISSING",
      profileID,
    );
  }
});

Deno.test("non-TR output rejects 6331 even when references are empty", () => {
  const output = validOutput("en-intl-generic-v1");
  (output.hazards as Array<Record<string, unknown>>)[0].description =
    "The condition should be reviewed under 6331.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(validation.failedLayer, "safety_profile_terminology");
  assertEquals(
    validation.code,
    "SAFETY_PROFILE_TURKEY_TERMINOLOGY_LEAK",
  );
});

Deno.test("non-TR structured references and compliance claims fail closed", () => {
  const withReference = validOutput("en-us-generic-v1");
  (withReference.hazards as Array<Record<string, unknown>>)[0].references =
    "29 CFR citation";
  const referenceValidation = validateAIOutputContract(
    withReference,
    snapshotFor("en-us-generic-v1"),
  );
  assertEquals(referenceValidation.failedLayer, "regulatory_reference");
  assertEquals(
    referenceValidation.code,
    "REGULATORY_REFERENCE_NOT_ALLOWED",
  );

  const withClaim = validOutput("en-gb-generic-v1");
  (withClaim.hazards as Array<Record<string, unknown>>)[0].description =
    "The workplace is fully compliant.";
  const claimValidation = validateAIOutputContract(
    withClaim,
    snapshotFor("en-gb-generic-v1"),
  );
  assertEquals(claimValidation.failedLayer, "forbidden_claim");
  assertEquals(claimValidation.code, "FORBIDDEN_COMPLIANCE_CLAIM");
});

Deno.test("broken provider JSON is repaired once through the schema layer", async () => {
  let repairCalls = 0;
  const result = await validateAIOutputWithSingleRepair({
    initialResult: "{broken-json",
    snapshot: snapshotFor("en-intl-generic-v1"),
    repair: (validation) => {
      repairCalls += 1;
      assertEquals(validation.failedLayer, "json_schema");
      return Promise.resolve(validOutput("en-intl-generic-v1"));
    },
  });
  assertEquals(repairCalls, 1);
  assertEquals(result.status, "repaired");
  assertEquals(result.attempts, 2);
  assertEquals(result.code, "AI_SCHEMA_ROOT_INVALID");
});

Deno.test("wrong first language is repaired exactly once", async () => {
  let repairCalls = 0;
  const result = await validateAIOutputWithSingleRepair({
    initialResult: validOutput("tr-tr-current-v1"),
    snapshot: snapshotFor("en-ca-generic-v1"),
    repair: (validation) => {
      repairCalls += 1;
      assertEquals(validation.failedLayer, "output_language");
      return Promise.resolve(validOutput("en-ca-generic-v1"));
    },
  });
  assertEquals(repairCalls, 1);
  assertEquals(result.status, "repaired");
  assertEquals(result.attempts, 2);
});

Deno.test("third-language first output is repaired exactly once", async () => {
  const frenchOutput = validOutput("en-intl-generic-v1");
  const finding = (frenchOutput.hazards as Array<Record<string, unknown>>)[0];
  finding.observed_evidence =
    "Une pièce rotative est visiblement accessible à un opérateur.";
  finding.description =
    "Le contact peut provoquer un coincement ou un écrasement grave.";
  finding.root_cause =
    "Le protecteur de la machine ne paraît pas installé correctement.";
  finding.corrective_action =
    "Arrêtez l’équipement et installez une protection efficace.";
  finding.preventive_control =
    "Ajoutez la vérification à l’inspection avant chaque utilisation.";
  frenchOutput.ai_summary =
    "La sécurité au travail exige une mesure corrective avant utilisation.";

  let repairCalls = 0;
  const result = await validateAIOutputWithSingleRepair({
    initialResult: frenchOutput,
    snapshot: snapshotFor("en-intl-generic-v1"),
    repair: (validation) => {
      repairCalls += 1;
      assertEquals(validation.code, "OUTPUT_LANGUAGE_ENGLISH_REQUIRED");
      return Promise.resolve(validOutput("en-intl-generic-v1"));
    },
  });
  assertEquals(repairCalls, 1);
  assertEquals(result.status, "repaired");
  assertEquals(result.attempts, 2);
});

Deno.test("wrong language after repair returns the stable fail-closed error", async () => {
  let repairCalls = 0;
  const error = await assertRejects(
    () =>
      validateAIOutputWithSingleRepair({
        initialResult: validOutput("tr-tr-current-v1"),
        snapshot: snapshotFor("en-us-generic-v1"),
        repair: () => {
          repairCalls += 1;
          return Promise.resolve(validOutput("tr-tr-current-v1"));
        },
      }),
    OutputLanguageContractError,
  );
  assertEquals(repairCalls, 1);
  assertEquals(error.code, OUTPUT_LANGUAGE_CONTRACT_FAILED);
  assertEquals(error.attempts, 2);
  assertEquals(error.failedLayer, "output_language");
  assertEquals(error.validation?.failedLayer, "output_language");
});

Deno.test("unsupported certainty is rejected by the photo-evidence layer", () => {
  const output = validOutput("en-intl-generic-v1");
  (output.hazards as Array<Record<string, unknown>>)[0].description =
    "This condition will definitely cause an incident.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(validation.failedLayer, "photo_evidence");
  assertEquals(validation.code, "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY");
});

Deno.test("unseen training and record claims fail the evidence-only contract", () => {
  const output = validOutput("en-intl-generic-v1");
  (output.hazards as Array<Record<string, unknown>>)[0].root_cause =
    "The operator is not trained for this task.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(validation.failedLayer, "photo_evidence");
  assertEquals(validation.code, "PHOTO_EVIDENCE_UNSEEN_FACT");
});

Deno.test("numeric measurement claims require field verification", () => {
  const withoutVerification = validOutput("en-intl-generic-v1");
  const unverifiedFinding =
    (withoutVerification.hazards as Array<Record<string, unknown>>)[0];
  unverifiedFinding.observed_evidence =
    "The noise exposure is measured at 92 dBA.";
  const rejected = validateAIOutputContract(
    withoutVerification,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(rejected.failedLayer, "photo_evidence");
  assertEquals(
    rejected.code,
    "PHOTO_EVIDENCE_MEASUREMENT_REQUIRES_VERIFICATION",
  );

  unverifiedFinding.needs_field_verification = true;
  const accepted = validateAIOutputContract(
    withoutVerification,
    snapshotFor("en-intl-generic-v1"),
  );
  assertEquals(accepted.ok, true);
});

Deno.test("definitive root-cause claims fail closed", () => {
  const output = validOutput("en-gb-generic-v1");
  (output.hazards as Array<Record<string, unknown>>)[0].root_cause =
    "The root cause is inadequate training.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("en-gb-generic-v1"),
  );
  assertEquals(validation.failedLayer, "photo_evidence");
  assertEquals(
    validation.code,
    "PHOTO_EVIDENCE_DEFINITIVE_ROOT_CAUSE",
  );
});
