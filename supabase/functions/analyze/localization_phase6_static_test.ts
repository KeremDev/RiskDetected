import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const indexSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const resolverSource = await Deno.readTextFile(
  new URL("../_shared/localization-context-resolver.ts", import.meta.url),
);
const validationSource = await Deno.readTextFile(
  new URL("../_shared/ai-localization-validation.ts", import.meta.url),
);
const safetyApprovalSource = await Deno.readTextFile(
  new URL("../_shared/safety-profile-approval.ts", import.meta.url),
);
const analysisServiceSource = await Deno.readTextFile(
  new URL("../../../App/Services/AnalysisService.swift", import.meta.url),
);
const buildGateSource = await Deno.readTextFile(
  new URL(
    "../../../App/Localization/RDGlobalLocalizationBuildGate.swift",
    import.meta.url,
  ),
);
const contextMigrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260728203000_global_localization_context_wave1.sql",
    import.meta.url,
  ),
);
const deliveryMigrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260730213000_global_localization_delivery_wave1.sql",
    import.meta.url,
  ),
);
const telemetryMigrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260731103000_global_localization_release_telemetry.sql",
    import.meta.url,
  ),
);
const legalServiceSource = await Deno.readTextFile(
  new URL("../../../App/Services/LegalDocumentService.swift", import.meta.url),
);
const legalSheetSource = await Deno.readTextFile(
  new URL("../../../App/Views/Legal/LegalInfoSheet.swift", import.meta.url),
);
const legalManifest = JSON.parse(
  await Deno.readTextFile(
    new URL("../../../App/LegalDocuments/en/manifest.json", import.meta.url),
  ),
) as { documents?: Array<{ kind?: string; change_type?: string }> };
// Uygulamadaki her paywall giris noktasi artik tek bir Claude Design ekranini kullanir;
// OBPaywallView/OBTimelinePaywallView/InAppPaywallView bu gecisle silindi.
const [
  paywallDesignFlowSource,
  paywallDesignKitSource,
  paywallDesignScreenSource,
  trialInviteSource,
  planSummarySource,
  notificationPermissionSource,
] = await Promise.all(
  [
    "../../../App/Views/Paywall/Design/PaywallDesignFlowView.swift",
    "../../../App/Views/Paywall/Design/PaywallDesignKit.swift",
    "../../../App/Views/Paywall/Design/PaywallDesignScreen.swift",
    "../../../App/Views/Onboarding/V2/Screens/OBTrialInviteView.swift",
    "../../../App/Views/Onboarding/V2/Screens/OBPlanSummaryView.swift",
    "../../../App/Views/Onboarding/V2/Screens/OBNotificationPermissionView.swift",
  ].map((path) => Deno.readTextFile(new URL(path, import.meta.url))),
);

/// Deneme suresi iddiasi tasiyabilecek tek yer akis gorunumudur; oradaki her iddia
/// StoreKit teklifine bagli oldugu icin metin taramasindan ayri denetlenir.
const paywallSources = [
  paywallDesignKitSource,
  paywallDesignScreenSource,
  planSummarySource,
  notificationPermissionSource,
];

/// Deneme metnini uretmesine izin verilen anahtarlar. Her biri
/// `PaywallDesignFlowView` icinde StoreKit'in dondurdugu tanitim teklifine baglidir;
/// asagidaki test bu bagi dogrular.
const STOREKIT_GATED_TRIAL_KEYS = [
  "paywall.design.hero.trial_headline",
  "paywall.design.plan.trial_note_format",
  "paywall.design.cta.start_trial",
];
const paywallCatalogs = await Promise.all(
  [
    "../../../App/Localization/Onboarding.xcstrings",
    "../../../App/Localization/Paywall.xcstrings",
  ].map((path) => Deno.readTextFile(new URL(path, import.meta.url))),
);

function sourceBetween(
  source: string,
  start: string,
  end: string,
): string {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert(startIndex >= 0, `Missing start marker: ${start}`);
  assert(endIndex > startIndex, `Missing end marker: ${end}`);
  return source.slice(startIndex, endIndex);
}

Deno.test("SEC/ASC candidate binary reports localization capability only when compiled in", () => {
  assertStringIncludes(
    analysisServiceSource,
    '"global_localization_wave1":\n                RDGlobalLocalizationBuildGate.isCompiledIn',
  );
  assertStringIncludes(
    analysisServiceSource,
    "app_language: RDLanguage.current.rawValue",
  );
  assertStringIncludes(
    analysisServiceSource,
    "client_app_build: AppClientMetadata.appBuild",
  );
  assertStringIncludes(
    buildGateSource,
    "#if RD_GLOBAL_LOCALIZATION_WAVE1",
  );
  assertStringIncludes(
    buildGateSource,
    "#if DEBUG",
  );
  assertStringIncludes(
    buildGateSource,
    "RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED",
  );
});

Deno.test("candidate rollout requires capability plus all three global gates", () => {
  for (
    const gate of [
      '"localization_v2"',
      '"english_product_enabled"',
      '"global_localization_wave1"',
    ]
  ) {
    assertStringIncludes(resolverSource, gate);
  }
  assertStringIncludes(
    resolverSource,
    "const globalEnabled = approvedSourceSHA256 !== null &&",
  );
  assertStringIncludes(resolverSource, "preReleaseLocalizationFlagEnabled");
  assertStringIncludes(resolverSource, "reviewerCohortAllows");
  assertStringIncludes(resolverSource, 'mode === "build_allowlist"');
  assertStringIncludes(resolverSource, "value.enabled_ios_builds");
  assertStringIncludes(resolverSource, 'mode === "min_build"');
  assertStringIncludes(resolverSource, "value?.min_ios_build");
  assertStringIncludes(resolverSource, "value?.kill_switch === true");
  assertStringIncludes(
    indexSource,
    "clientBuild: clientRelease.appBuild",
  );
  assertStringIncludes(
    indexSource,
    "clientRelease.capabilities.global_localization_wave1 === true",
  );
});

Deno.test("machine-draft profiles fail closed while legacy Turkish behavior is isolated", () => {
  assertStringIncludes(
    safetyApprovalSource,
    "SAFETY_PROFILE_APPROVAL_RECORD",
  );
  assertStringIncludes(
    safetyApprovalSource,
    "3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932",
  );
  assertStringIncludes(
    safetyApprovalSource,
    "RD-SPR-20260801-3A68229B",
  );
  assertStringIncludes(
    resolverSource,
    "LOCALIZATION_ERROR_CODES.profileNotApproved",
  );
  assertStringIncludes(
    indexSource,
    'snapshot.source === "legacy_tr_default"',
  );
  assertStringIncludes(
    indexSource,
    "prompt: CORE_ANALYSIS_PROMPT",
  );
  assertStringIncludes(
    indexSource,
    'localizationSnapshot.source === "explicit_request"',
  );
});

Deno.test("English legal routing and acknowledgement metadata fail closed", () => {
  assertStringIncludes(
    legalServiceSource,
    'case materialPrivacy = "material_privacy"',
  );
  assertStringIncludes(
    legalServiceSource,
    '"acknowledge_legal_document_v1"',
  );
  assertStringIncludes(
    legalSheetSource,
    "&& initialDocument == .kvkk",
  );
  assertEquals(
    legalManifest.documents?.find((document) => document.kind === "privacy")
      ?.change_type,
    "material_privacy",
  );
});

Deno.test("purchase paywall copy does not promise an unverified introductory offer", () => {
  const forbiddenClaim =
    /7\s*(?:days?|gün)\s*(?:free|ücretsiz)|free\s+trial|ücretsiz\s+deneme|₺0[,.]00|no payments at this time|şu an ödeme yok/iu;
  // The invite is an informational route to the StoreKit-backed paywall; it does not purchase.
  // Its fixed CTA is product copy approved by the owner and remains separate from transactional
  // price/offer claims, which must continue to come from StoreKit.
  assertStringIncludes(trialInviteSource, "onContinue()");
  assertEquals(trialInviteSource.includes("onPurchase"), false);
  for (const source of paywallSources) {
    const fallbacks = [...source.matchAll(/fallback:\s*"([^"]*)"/gu)]
      .map((match) => match[1]);
    assertEquals(
      fallbacks.some((fallback) => forbiddenClaim.test(fallback)),
      false,
    );
  }

  // Akis gorunumu deneme metnini tasiyabilir, ama yalnizca App Store'un gercekten
  // dondurdugu tanitim teklifine bagli oldugu icin. Bagi metin yasagiyla degil,
  // uretildikleri bloklarin StoreKit kosuluna bagli olmasiyla dogruluyoruz.
  assertStringIncludes(paywallDesignFlowSource, "introductoryFreeTrialDays");
  assertStringIncludes(
    sourceBetween(
      paywallDesignFlowSource,
      "private var trialDays: Int? {",
      "private var heroLabel",
    ),
    "introductoryFreeTrialDays",
  );
  for (
    const [region, start, end] of [
      [
        "hero",
        "private var heroLabel: String {",
        "private var comparisonColumns",
      ],
      [
        "plan",
        "private var trialNoteText: String? {",
        "private var discountText",
      ],
      [
        "cta",
        "private var primaryButtonTitle: String {",
        "private var primaryButtonDisabled",
      ],
    ] as Array<[string, string, string]>
  ) {
    const block = sourceBetween(paywallDesignFlowSource, start, end);
    assert(
      block.includes("trialDays"),
      `${region} copy must be gated on the StoreKit trial offer`,
    );
  }
  const flowTrialFallbacks = [
    ...paywallDesignFlowSource.matchAll(
      /RDLocalization\.(?:string|format)\(\s*"([^"]+)"[\s\S]*?fallback:\s*"([^"]*)"/gu,
    ),
  ];
  for (const [, key, fallback] of flowTrialFallbacks) {
    if (!forbiddenClaim.test(fallback)) continue;
    assert(
      STOREKIT_GATED_TRIAL_KEYS.includes(key),
      `Unreviewed trial claim in paywall flow: ${key}`,
    );
  }
  for (const [index, catalog] of paywallCatalogs.entries()) {
    const parsed = JSON.parse(catalog) as {
      strings?: Record<
        string,
        { localizations?: Record<string, { stringUnit?: { value?: string } }> }
      >;
    };
    const values = Object.entries(parsed.strings ?? {}).flatMap(
      ([key, entry]) => {
        if (index === 0 && key.startsWith("onboarding.obtrial.invite.")) {
          return [];
        }
        if (STOREKIT_GATED_TRIAL_KEYS.includes(key)) {
          return [];
        }
        return Object.values(entry.localizations ?? {}).flatMap((
          localization,
        ) =>
          typeof localization.stringUnit?.value === "string"
            ? [localization.stringUnit.value]
            : []
        );
      },
    );
    assertEquals(
      values.some((value) => forbiddenClaim.test(value)),
      false,
    );
  }
});

Deno.test("minimum analysis telemetry is present in audit, success, failure and completion", () => {
  const minimumAnalysisFields = [
    "app_language",
    "output_language",
    "output_locale",
    "work_jurisdiction_country",
    "safety_profile_id",
    "safety_profile_version",
    "language_validation_status",
    "language_validation_attempts",
    "language_contract_repair_used",
    "forbidden_claim_validation_status",
    "client_build",
    "prompt_profile_version",
  ];
  const inputAuditBlock = sourceBetween(
    indexSource,
    "const inputAudit: Record<string, unknown> = {",
    "// deno-lint-ignore no-explicit-any\n  let geminiResult",
  );
  const successUsageBlock = sourceBetween(
    indexSource,
    "successUsageLogID = await logUsage",
    "} catch (err) {",
  );
  const failureUsageBlock = sourceBetween(
    indexSource,
    "await logUsage(supabase, {\n        analysis_id: analysisID",
    "if (isPipelineV2Worker) {",
  );
  const completionBlock = sourceBetween(
    indexSource,
    "const completedAnalysisResult = {",
    "if (isPipelineV2Worker) {",
  );

  for (const field of minimumAnalysisFields) {
    const auditHasField = inputAuditBlock.includes(`${field}:`) ||
      indexSource.includes(`inputAudit.${field} =`);
    assert(auditHasField, `audit ${field}`);
  }
  for (
    const field of [
      "app_language",
      "output_language",
      "output_locale",
      "work_jurisdiction_country",
      "safety_profile_id",
      "safety_profile_version",
      "language_validation_status",
      "language_validation_attempts",
      "language_contract_repair_used",
      "forbidden_claim_validation_status",
      "client_build",
      "prompt_profile_version",
    ]
  ) {
    assertStringIncludes(successUsageBlock, `${field}:`, `success ${field}`);
    assertStringIncludes(failureUsageBlock, `${field}:`, `failure ${field}`);
  }
  for (
    const field of [
      "app_language",
      "language_validation_status",
      "language_validation_attempts",
      "language_contract_repair_used",
      "forbidden_claim_validation_status",
      "client_build",
    ]
  ) {
    assertStringIncludes(completionBlock, `${field}:`, `completion ${field}`);
  }
});

Deno.test("report and notification telemetry remain exact-locale and snapshot bound", () => {
  for (
    const field of [
      "report_language",
      "report_locale",
      "safety_profile_id",
      "safety_profile_version",
      "localization_snapshot",
    ]
  ) {
    assertStringIncludes(contextMigrationSource, field);
  }
  for (
    const field of [
      "language",
      "locale",
      "template_locale",
      "template_localization_id",
      "localization_snapshot",
    ]
  ) {
    assertStringIncludes(contextMigrationSource, field);
  }
  assertStringIncludes(
    deliveryMigrationSource,
    "notification_jobs_localization_guard_v1",
  );
  assertStringIncludes(
    deliveryMigrationSource,
    "TEMPLATE_EXACT_LOCALE_MISSING",
  );
});

Deno.test("release telemetry migration is additive, bounded and default-off", () => {
  for (
    const field of [
      "app_language",
      "client_build",
      "language_contract_repair_used",
      "forbidden_claim_validation_status",
      "safety_profile_version",
      "prompt_profile_version",
    ]
  ) {
    assertStringIncludes(telemetryMigrationSource, field);
  }
  assertStringIncludes(
    telemetryMigrationSource,
    "tg_sync_analysis_localization_telemetry",
  );
  assertStringIncludes(telemetryMigrationSource, "limit 500");
  assertStringIncludes(telemetryMigrationSource, "for update skip locked");
  assertStringIncludes(telemetryMigrationSource, "'localization_v2'");
  assertStringIncludes(
    telemetryMigrationSource,
    "'english_product_enabled'",
  );
  assertStringIncludes(
    telemetryMigrationSource,
    '"rollout_mode":"off"',
  );
  assertStringIncludes(
    telemetryMigrationSource,
    '"enabled_ios_builds":[]',
  );
  assertStringIncludes(
    telemetryMigrationSource,
    '"kill_switch":false',
  );
  assertEquals(
    telemetryMigrationSource.includes('"enabled_ios_builds":["78"]'),
    false,
    "migration must not activate candidate build",
  );
  assertEquals(
    telemetryMigrationSource.includes('"rollout_mode":"on"'),
    false,
    "migration must not enable a public rollout",
  );
});

Deno.test("release telemetry schema cannot store prompts, photos, tokens or contact content", () => {
  const additiveColumnLines = telemetryMigrationSource
    .split("\n")
    .filter((line) => line.includes("add column if not exists"))
    .join("\n");
  for (
    const forbidden of [
      "prompt_text",
      "system_prompt",
      "photo",
      "image",
      "jwt",
      "token",
      "email",
      "phone",
      "user_message",
      "user_content",
    ]
  ) {
    assertEquals(
      additiveColumnLines.includes(forbidden),
      false,
      forbidden,
    );
  }
  assertStringIncludes(
    telemetryMigrationSource,
    "Aggregate-safe boolean; no prompt, photo or user-authored text.",
  );
});

Deno.test("forbidden-claim outcome is derived from the validator layer and fails closed", () => {
  assertStringIncludes(
    validationSource,
    'layer(\n      "forbidden_claim"',
  );
  assertStringIncludes(
    validationSource,
    "readonly failedLayer: AIOutputValidationLayerID | null;",
  );
  assertStringIncludes(validationSource, "readonly validation:");
  assertStringIncludes(indexSource, "initialForbiddenClaimPassed");
  assertStringIncludes(indexSource, "forbiddenClaimValidationStatus");
  assertStringIncludes(indexSource, '? "failed"');
  assertStringIncludes(indexSource, '? "repaired"');
  assertStringIncludes(indexSource, ': "passed";');
});
