import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  AI_OUTPUT_VALIDATION_LAYER_IDS,
  OUTPUT_LANGUAGE_CONTRACT_FAILED,
  OutputLanguageContractError,
  validateAIOutputContract,
  validateAIOutputRepairIntegrity,
  validateAIOutputWithSingleRepair,
} from "./ai-localization-validation.ts";
import { resolveLocalizationContext } from "./localization-context-resolver.ts";
import {
  type SafetyProfileID,
  safetyProfiles,
} from "./generated/safety-profiles.generated.ts";
import { safetyProfileSourceSHA256 } from "./safety-profile-manifest.ts";

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

// Regression: analysis c42b5bc5 (2026-08-21) failed with
// PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY after both attempts. The certainty
// pattern was scanning every user-visible field, so the hedging and imperative
// phrasing the photo-evidence prompt asks for was read as a certainty claim.
Deno.test("hedged Turkish uncertainty in limitations is not a certainty claim", () => {
  const output = validOutput("tr-tr-current-v1");
  output.limitations =
    "Koruyucunun yerinde olup olmadığı fotoğraftan kesin olarak belirlenememiştir.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("tr-tr-current-v1"),
  );
  assertEquals(validation.ok, true, validation.code ?? "");
});

Deno.test("imperative Turkish safety copy is not a certainty claim", () => {
  const output = validOutput("tr-tr-current-v1");
  const finding = (output.hazards as Array<Record<string, unknown>>)[0];
  finding.corrective_action = "Bu alanda baret kesinlikle kullanılmalıdır.";
  finding.preventive_control = "Yetkisiz personel kesinlikle girmemelidir.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("tr-tr-current-v1"),
  );
  assertEquals(validation.ok, true, validation.code ?? "");
});

Deno.test("certainty asserted about the scene still fails, with the field named", () => {
  const output = validOutput("tr-tr-current-v1");
  (output.hazards as Array<Record<string, unknown>>)[0].description =
    "Bu ekipman kesinlikle arızalıdır ve şüphesiz kazaya yol açacaktır.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("tr-tr-current-v1"),
  );
  assertEquals(validation.failedLayer, "photo_evidence");
  assertEquals(validation.code, "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY");
  assertEquals(validation.failedField, "description");
  assertEquals(
    validation.failedExcerpt?.includes("kesinlikle arızalıdır"),
    true,
    validation.failedExcerpt ?? "",
  );
});

// `\b` is ASCII-only, so the old pattern could not match a Turkish word that
// starts with a non-ASCII letter after a space.
Deno.test("standalone şüphesiz is matched despite the leading non-ASCII letter", () => {
  const output = validOutput("tr-tr-current-v1");
  (output.hazards as Array<Record<string, unknown>>)[0].observed_evidence =
    "şüphesiz burada bir düşme tehlikesi vardır.";
  const validation = validateAIOutputContract(
    output,
    snapshotFor("tr-tr-current-v1"),
  );
  assertEquals(validation.code, "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY");
});

Deno.test("English hedging survives while an English certainty claim fails", () => {
  const hedged = validOutput("en-gb-generic-v1");
  hedged.limitations =
    "Guard position could not be determined with certainty from the photograph.";
  assertEquals(
    validateAIOutputContract(hedged, snapshotFor("en-gb-generic-v1")).ok,
    true,
  );

  const asserted = validOutput("en-gb-generic-v1");
  (asserted.hazards as Array<Record<string, unknown>>)[0].description =
    "This will definitely cause an incident.";
  assertEquals(
    validateAIOutputContract(asserted, snapshotFor("en-gb-generic-v1")).code,
    "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY",
  );
});

Deno.test("certainty policy v2 closed hedge and claim matrix covers over forty TR/EN cases", () => {
  const allowedCases = [
    [
      "tr-tr-current-v1",
      "limitations",
      "Koruyucu kesin olarak belirlenememiştir.",
    ],
    [
      "tr-tr-current-v1",
      "limitations",
      "Durum kesin olarak tespit edilememiştir.",
    ],
    [
      "tr-tr-current-v1",
      "limitations",
      "Koşul kesin olarak doğrulanamamıştır.",
    ],
    [
      "tr-tr-current-v1",
      "limitations",
      "Risk kesin olarak değerlendirilememiştir.",
    ],
    ["tr-tr-current-v1", "limitations", "Neden kesin olarak anlaşılamamıştır."],
    ["tr-tr-current-v1", "limitations", "Kaynak kesin olarak saptanamamıştır."],
    [
      "tr-tr-current-v1",
      "limitations",
      "Ayrıntı kesin olarak gözlemlenememiştir.",
    ],
    ["tr-tr-current-v1", "limitations", "Seviye kesin olarak ölçülememiştir."],
    [
      "tr-tr-current-v1",
      "limitations",
      "Bilgi kesin olarak teyit edilememiştir.",
    ],
    [
      "tr-tr-current-v1",
      "limitations",
      "Sayısal değerler yerinde ölçüm yapılmadan kesin olarak belirtilememiştir.",
    ],
    [
      "tr-tr-current-v1",
      "limitations",
      "Sonuç kesin olarak ifade edilememiştir.",
    ],
    [
      "tr-tr-current-v1",
      "limitations",
      "Durum kesin olarak söylenemez.",
    ],
    [
      "tr-tr-current-v1",
      "corrective_action",
      "Baret kesinlikle kullanılmalıdır.",
    ],
    [
      "tr-tr-current-v1",
      "corrective_action",
      "Alan kesinlikle kapatılmalıdır.",
    ],
    [
      "tr-tr-current-v1",
      "preventive_control",
      "Kontrol kesinlikle yapılmalıdır.",
    ],
    [
      "tr-tr-current-v1",
      "preventive_control",
      "Yetkisiz giriş kesinlikle önlenmelidir.",
    ],
    [
      "tr-tr-current-v1",
      "preventive_control",
      "Bu kontrol kesinlikle zorunludur.",
    ],
    [
      "en-gb-generic-v1",
      "limitations",
      "The guard position could not be determined with certainty.",
    ],
    [
      "en-gb-generic-v1",
      "limitations",
      "The condition cannot be verified with certainty from the photo.",
    ],
    [
      "en-gb-generic-v1",
      "limitations",
      "The cause was not reliably established with certainty.",
    ],
    [
      "en-gb-generic-v1",
      "limitations",
      "The level could not be measured with certainty.",
    ],
    [
      "en-gb-generic-v1",
      "limitations",
      "The detail cannot be confirmed with certainty.",
    ],
    [
      "en-gb-generic-v1",
      "corrective_action",
      "The guard must definitely be installed.",
    ],
    [
      "en-gb-generic-v1",
      "preventive_control",
      "This control should certainly be checked before use.",
    ],
  ] as const;
  const rejectedCases = [
    ["tr-tr-current-v1", "title", "Kesinlikle arızalı makine"],
    ["tr-tr-current-v1", "category", "Şüphesiz elektrik tehlikesi"],
    ["tr-tr-current-v1", "ai_summary", "Bu makine kesinlikle arızalıdır."],
    [
      "tr-tr-current-v1",
      "limitations",
      "Alanda şüphesiz koruyucu bulunmamaktadır.",
    ],
    [
      "tr-tr-current-v1",
      "limitations",
      "Kesinlikle önlenemez bir risk söz konusudur.",
    ],
    ["tr-tr-current-v1", "scene_summary", "Ekipman kesin olarak kusurludur."],
    [
      "tr-tr-current-v1",
      "coverage_gap_reason",
      "Şüphesiz hiçbir kontrol yoktur.",
    ],
    ["tr-tr-current-v1", "coverage_conclusion", "Risk kesinlikle yüksektir."],
    [
      "tr-tr-current-v1",
      "corrective_action",
      "Makine kesinlikle arızalıdır ve kullanılmamalıdır.",
    ],
    [
      "tr-tr-current-v1",
      "preventive_control",
      "Koruyucu şüphesiz eksiktir ve takılmalıdır.",
    ],
    [
      "tr-tr-current-v1",
      "description",
      "Bu durum kesinlikle kazaya yol açacaktır.",
    ],
    ["tr-tr-current-v1", "root_cause", "Neden şüphesiz bakım eksikliğidir."],
    [
      "tr-tr-current-v1",
      "limitations",
      "Alanda kesinlikle koruyucu yoktur çünkü nedeni belirlenememiştir.",
    ],
    [
      "tr-tr-current-v1",
      "corrective_action",
      "Makine kesinlikle arızalıdır kullanılmamalıdır.",
    ],
    ["en-gb-generic-v1", "title", "Definitely defective guard"],
    ["en-gb-generic-v1", "category", "Certainly unsafe equipment"],
    ["en-gb-generic-v1", "ai_summary", "This machine is definitely defective."],
    [
      "en-gb-generic-v1",
      "limitations",
      "There is certainly no guard in the area.",
    ],
    [
      "en-gb-generic-v1",
      "scene_summary",
      "The equipment is defective with certainty.",
    ],
    [
      "en-gb-generic-v1",
      "coverage_gap_reason",
      "Without doubt no control exists.",
    ],
    [
      "en-gb-generic-v1",
      "corrective_action",
      "The machine is definitely defective and must not be used.",
    ],
    [
      "en-gb-generic-v1",
      "preventive_control",
      "The guard is certainly missing and should be installed.",
    ],
    [
      "en-gb-generic-v1",
      "description",
      "This will definitely cause an incident.",
    ],
    [
      "en-gb-generic-v1",
      "root_cause",
      "The cause is certainly poor maintenance.",
    ],
    [
      "en-gb-generic-v1",
      "limitations",
      "The guard is definitely absent because its position could not be determined.",
    ],
    [
      "en-gb-generic-v1",
      "corrective_action",
      "The machine is definitely defective must not be used.",
    ],
  ] as const;

  for (const [profileID, field, text] of allowedCases) {
    const output = validOutput(profileID);
    if (field in output) output[field] = text;
    else (output.hazards as Array<Record<string, unknown>>)[0][field] = text;
    const validation = validateAIOutputContract(
      output,
      snapshotFor(profileID),
      {
        certaintyPolicy: "v2",
      },
    );
    assertEquals(validation.ok, true, `${profileID}/${field}/${text}`);
  }
  for (const [profileID, field, text] of rejectedCases) {
    const output = validOutput(profileID);
    if (field in output) output[field] = text;
    else (output.hazards as Array<Record<string, unknown>>)[0][field] = text;
    const validation = validateAIOutputContract(
      output,
      snapshotFor(profileID),
      {
        certaintyPolicy: "v2",
      },
    );
    assertEquals(
      validation.code,
      "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY",
      `${profileID}/${field}/${text}`,
    );
  }
  assertEquals(allowedCases.length + rejectedCases.length >= 40, true);
});

Deno.test("certainty policy v2 excludes references and returns every exact JSON path", () => {
  const first = validOutput("tr-tr-current-v1");
  const finding = (first.hazards as Array<Record<string, unknown>>)[0];
  finding.references = "Kesinlikle yalnız örnek referans metnidir.";
  assertEquals(
    validateAIOutputContract(first, snapshotFor("tr-tr-current-v1"), {
      certaintyPolicy: "v2",
    }).ok,
    true,
  );

  const findingOne = structuredClone(finding);
  const findingTwo = structuredClone(finding);
  findingOne.description = "Bu durum kesinlikle kazaya yol açar.";
  findingTwo.observed_evidence = "Gürültü seviyesi 92 dBA olarak yazılmıştır.";
  findingTwo.needs_field_verification = false;
  const output = {
    photo_findings: [
      { photo_index: 1, findings: [findingOne] },
      { photo_index: 2, findings: [findingTwo] },
    ],
    ai_summary: first.ai_summary,
    limitations: first.limitations,
  };
  const validation = validateAIOutputContract(
    output,
    snapshotFor("tr-tr-current-v1"),
    { certaintyPolicy: "v2" },
  );
  assertEquals(
    validation.failedPath,
    "photo_findings[1].findings[0].observed_evidence",
  );
  assertEquals(
    validation.violations.some((item) =>
      item.path === "photo_findings[0].findings[0].description"
    ),
    true,
  );
  assertEquals(validation.violations.length >= 2, true);
});

Deno.test("repair integrity permits only rejected finding paths or their removal", () => {
  const initial = validOutput("tr-tr-current-v1");
  const first = (initial.hazards as Array<Record<string, unknown>>)[0];
  first.description = "Bu ekipman kesinlikle arızalıdır.";
  (initial.hazards as Array<Record<string, unknown>>).push({
    ...structuredClone(first),
    title: "İkinci görünür bulgu",
    description: "Temas halinde yaralanma tehlikesi bulunuyor.",
  });
  const validation = validateAIOutputContract(
    initial,
    snapshotFor("tr-tr-current-v1"),
    { certaintyPolicy: "v2" },
  );

  const repaired = structuredClone(initial);
  (repaired.hazards as Array<Record<string, unknown>>)[0].description =
    "Ekipmanda görsel olarak olağan dışı bir durum görülüyor.";
  assertEquals(
    validateAIOutputRepairIntegrity(initial, repaired, validation).ok,
    true,
  );

  const scoreChanged = structuredClone(repaired);
  (scoreChanged.hazards as Array<Record<string, unknown>>)[0].fk_severity = 40;
  const scoreIntegrity = validateAIOutputRepairIntegrity(
    initial,
    scoreChanged,
    validation,
  );
  assertEquals(scoreIntegrity.ok, false);
  assertEquals(scoreIntegrity.path?.includes("hazards[1]"), true);

  const dropped = structuredClone(initial);
  (dropped.hazards as Array<Record<string, unknown>>).splice(0, 1);
  dropped.ai_summary = "Görselde doğrulanabilen bir bulgu kaldı.";
  const dropIntegrity = validateAIOutputRepairIntegrity(
    initial,
    dropped,
    validation,
  );
  assertEquals(dropIntegrity.ok, true);
  assertEquals(dropIntegrity.removedFindingsCount, 1);

  const unrelatedSummary = structuredClone(repaired);
  unrelatedSummary.ai_summary = "İlgisiz yeni özet.";
  assertEquals(
    validateAIOutputRepairIntegrity(initial, unrelatedSummary, validation).code,
    "REPAIR_INTEGRITY_UNRELATED_PATH_CHANGED",
  );
});

Deno.test("repair integrity permits translation but protects structure and scores", () => {
  const initial = validOutput("tr-tr-current-v1");
  const validation = validateAIOutputContract(
    initial,
    snapshotFor("en-intl-generic-v1"),
  );
  const translated = validOutput("en-intl-generic-v1");
  assertEquals(
    validateAIOutputRepairIntegrity(initial, translated, validation).ok,
    true,
  );
  const scoreChanged = structuredClone(translated);
  (scoreChanged.hazards as Array<Record<string, unknown>>)[0].m5_severity = 5;
  assertEquals(
    validateAIOutputRepairIntegrity(initial, scoreChanged, validation).ok,
    false,
  );
  const findingAdded = structuredClone(translated);
  (findingAdded.hazards as Array<Record<string, unknown>>).push(
    structuredClone(
      (findingAdded.hazards as Array<Record<string, unknown>>)[0],
    ),
  );
  assertEquals(
    validateAIOutputRepairIntegrity(initial, findingAdded, validation).code,
    "REPAIR_INTEGRITY_FINDING_ADDED",
  );
});

const fallbackCopy = {
  summary: "{{count}} visible workplace safety finding(s) remained.",
  zeroFindingsSummary:
    "No workplace safety finding could be reliably verified from the photo.",
  zeroFindingsLimitation:
    "The photo did not provide enough evidence; field verification may be needed.",
  cautiousRootCause:
    "The visible condition suggests a possible contributing factor that requires field verification.",
  coverageGapReason:
    "No actionable risk evidence could be reliably verified from the photo.",
};

Deno.test("deterministic fallback removes an unsupported finding without a third AI call", async () => {
  const initial = validOutput("en-intl-generic-v1");
  (initial.hazards as Array<Record<string, unknown>>)[0].description =
    "This machine is definitely defective.";
  let repairCalls = 0;
  const result = await validateAIOutputWithSingleRepair({
    initialResult: initial,
    snapshot: snapshotFor("en-intl-generic-v1"),
    certaintyPolicy: "v2",
    enforceRepairIntegrity: true,
    deterministicFallbackCopy: fallbackCopy,
    repair: () => {
      repairCalls += 1;
      return Promise.resolve(structuredClone(initial));
    },
  });
  assertEquals(repairCalls, 1);
  assertEquals(result.attempts, 2);
  assertEquals(result.status, "fallback");
  assertEquals(result.deterministicFallback?.zeroFindings, true);
  assertEquals((result.result.hazards as unknown[]).length, 0);
  assertEquals(result.finalValidation.ok, true);
});

Deno.test("deterministic fallback preserves initial findings when repair changes an unaffected finding", async () => {
  const initial = validOutput("en-intl-generic-v1");
  initial.limitations = "The risk is definitely high.";
  const originalFinding = structuredClone(
    (initial.hazards as Array<Record<string, unknown>>)[0],
  );
  const result = await validateAIOutputWithSingleRepair({
    initialResult: initial,
    snapshot: snapshotFor("en-intl-generic-v1"),
    certaintyPolicy: "v2",
    enforceRepairIntegrity: true,
    deterministicFallbackCopy: fallbackCopy,
    repair: () => {
      const repaired = structuredClone(initial);
      (repaired.hazards as Array<Record<string, unknown>>)[0].title =
        "Unrelated changed title";
      repaired.limitations = "The risk level requires field verification.";
      return Promise.resolve(repaired);
    },
  });
  assertEquals(result.status, "fallback");
  assertEquals(result.repairIntegrity?.ok, false);
  assertEquals(
    result.repairIntegrity?.code,
    "REPAIR_INTEGRITY_UNAFFECTED_FINDING_CHANGED",
  );
  assertEquals(
    (result.result.hazards as Array<Record<string, unknown>>)[0],
    originalFinding,
  );
  assertEquals(result.result.limitations, fallbackCopy.zeroFindingsLimitation);
  assertEquals(result.finalValidation.ok, true);
});

Deno.test("deterministic fallback retains measurement findings and marks verification", async () => {
  const initial = validOutput("en-intl-generic-v1");
  (initial.hazards as Array<Record<string, unknown>>)[0].observed_evidence =
    "A display visibly reads 92 dBA.";
  const result = await validateAIOutputWithSingleRepair({
    initialResult: initial,
    snapshot: snapshotFor("en-intl-generic-v1"),
    certaintyPolicy: "v2",
    enforceRepairIntegrity: true,
    deterministicFallbackCopy: fallbackCopy,
    repair: () => Promise.resolve(structuredClone(initial)),
  });
  const retained = (result.result.hazards as Array<Record<string, unknown>>)[0];
  assertEquals(result.status, "fallback");
  assertEquals(retained.needs_field_verification, true);
  assertEquals(result.deterministicFallback?.removedFindingsCount, 0);
});

Deno.test("deterministic fallback rewrites a definitive root cause without changing scores", async () => {
  const initial = validOutput("en-intl-generic-v1");
  const original = (initial.hazards as Array<Record<string, unknown>>)[0];
  original.root_cause = "The root cause is inadequate guarding.";
  const result = await validateAIOutputWithSingleRepair({
    initialResult: initial,
    snapshot: snapshotFor("en-intl-generic-v1"),
    certaintyPolicy: "v2",
    enforceRepairIntegrity: true,
    deterministicFallbackCopy: fallbackCopy,
    repair: () => Promise.resolve(structuredClone(initial)),
  });
  const retained = (result.result.hazards as Array<Record<string, unknown>>)[0];
  assertEquals(result.status, "fallback");
  assertEquals(retained.root_cause, fallbackCopy.cautiousRootCause);
  assertEquals(retained.needs_field_verification, true);
  assertEquals(retained.fk_severity, original.fk_severity);
  assertEquals(retained.source_photo_indices, original.source_photo_indices);
});

Deno.test("root-cause fallback also absorbs certainty on the same rejected path", async () => {
  const initial = validOutput("en-intl-generic-v1");
  (initial.hazards as Array<Record<string, unknown>>)[0].root_cause =
    "The root cause is definitely inadequate guarding.";
  const result = await validateAIOutputWithSingleRepair({
    initialResult: initial,
    snapshot: snapshotFor("en-intl-generic-v1"),
    certaintyPolicy: "v2",
    enforceRepairIntegrity: true,
    deterministicFallbackCopy: fallbackCopy,
    repair: () => Promise.resolve(structuredClone(initial)),
  });
  assertEquals(result.status, "fallback");
  assertEquals((result.result.hazards as unknown[]).length, 1);
  assertEquals(
    (result.result.hazards as Array<Record<string, unknown>>)[0].root_cause,
    fallbackCopy.cautiousRootCause,
  );
});

Deno.test("deterministic fallback replaces an offending summary and keeps findings", async () => {
  const initial = validOutput("en-intl-generic-v1");
  initial.ai_summary =
    "This workplace safety assessment is definitely complete.";
  const result = await validateAIOutputWithSingleRepair({
    initialResult: initial,
    snapshot: snapshotFor("en-intl-generic-v1"),
    certaintyPolicy: "v2",
    enforceRepairIntegrity: true,
    deterministicFallbackCopy: fallbackCopy,
    repair: () => Promise.resolve(structuredClone(initial)),
  });
  assertEquals(result.status, "fallback");
  assertEquals((result.result.hazards as unknown[]).length, 1);
  assertEquals(
    result.result.ai_summary,
    "1 visible workplace safety finding(s) remained.",
  );
  assertEquals(result.deterministicFallback?.zeroFindings, false);
});

Deno.test("deterministic fallback preserves photo records when every finding is removed", async () => {
  const base = validOutput("en-intl-generic-v1");
  const invalidFinding = structuredClone(
    (base.hazards as Array<Record<string, unknown>>)[0],
  );
  invalidFinding.observed_evidence =
    "The operator is definitely untrained for this task.";
  const initial = {
    photo_findings: [
      {
        photo_index: 1,
        coverage_status: "actionable",
        coverage_gap_reason: "",
        findings: [invalidFinding],
      },
      {
        photo_index: 2,
        coverage_status: "no_actionable_hazard",
        coverage_gap_reason: "No visible issue was found.",
        findings: [],
      },
    ],
    ai_summary: base.ai_summary,
    limitations: base.limitations,
  };
  const result = await validateAIOutputWithSingleRepair({
    initialResult: initial,
    snapshot: snapshotFor("en-intl-generic-v1"),
    certaintyPolicy: "v2",
    enforceRepairIntegrity: true,
    deterministicFallbackCopy: fallbackCopy,
    repair: () => Promise.resolve(structuredClone(initial)),
  });
  const records = result.result.photo_findings as Array<
    Record<string, unknown>
  >;
  assertEquals(records.length, 2);
  assertEquals(records.map((record) => record.photo_index), [1, 2]);
  assertEquals((records[0].findings as unknown[]).length, 0);
  assertEquals(records[0].coverage_status, "no_actionable_hazard");
  assertEquals(records[0].coverage_gap_reason, fallbackCopy.coverageGapReason);
  assertEquals(result.deterministicFallback?.zeroFindings, true);
});

Deno.test("repair integrity rejects adding findings and removing photo records", () => {
  const base = validOutput("en-intl-generic-v1");
  const invalidFinding = structuredClone(
    (base.hazards as Array<Record<string, unknown>>)[0],
  );
  invalidFinding.description = "This will definitely cause an incident.";
  const initial = {
    photo_findings: [
      { photo_index: 1, findings: [invalidFinding] },
      { photo_index: 2, findings: [] },
    ],
    ai_summary: base.ai_summary,
    limitations: base.limitations,
  };
  const validation = validateAIOutputContract(
    initial,
    snapshotFor("en-intl-generic-v1"),
    { certaintyPolicy: "v2" },
  );
  const added = structuredClone(initial);
  (added.photo_findings[0].findings as unknown[]).push(
    structuredClone(invalidFinding),
  );
  assertEquals(
    validateAIOutputRepairIntegrity(initial, added, validation).code,
    "REPAIR_INTEGRITY_FINDING_ADDED",
  );
  const removedPhoto = structuredClone(initial);
  removedPhoto.photo_findings.splice(1, 1);
  assertEquals(
    validateAIOutputRepairIntegrity(initial, removedPhoto, validation).ok,
    false,
  );
});

Deno.test("repair transport failure records not_run instead of a fake final validation", async () => {
  const error = await assertRejects(
    () =>
      validateAIOutputWithSingleRepair({
        initialResult: "broken",
        snapshot: snapshotFor("en-intl-generic-v1"),
        repair: () => Promise.reject(new TypeError("network unavailable")),
      }),
    OutputLanguageContractError,
  );
  assertEquals(error.repairTransportFailed, true);
  assertEquals(error.repairTransportErrorClass, "TypeError");
  assertEquals(error.finalValidationStatus, "not_run");
  assertEquals(error.validation, null);
  assertEquals(error.initialValidation?.failedLayer, "json_schema");
});
