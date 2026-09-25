#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { join, relative, resolve } from "node:path";
import { scanContent } from "./localization_inventory.mjs";

const ROOT = resolve(import.meta.dirname, "..");
const LOCALIZATION_ROOT = resolve(ROOT, "App/Localization");
const tests = [];

const EXPECTED_CATALOGS = [
  "Analysis",
  "Auth",
  "InfoPlist",
  "Legal",
  "Localizable",
  "Notifications",
  "Onboarding",
  "Paywall",
  "ProfessionalProgress",
  "Reports",
  "SafetyTerminology",
];

const TABLE_CASE_TO_CATALOG = {
  analysis: "Analysis",
  auth: "Auth",
  legal: "Legal",
  localizable: "Localizable",
  notifications: "Notifications",
  onboarding: "Onboarding",
  paywall: "Paywall",
  professionalProgress: "ProfessionalProgress",
  reports: "Reports",
  safetyTerminology: "SafetyTerminology",
};

function test(id, name, body) {
  tests.push({ id, name, body });
}

function read(relativePath) {
  return readFileSync(resolve(ROOT, relativePath), "utf8");
}

function readJSON(relativePath) {
  return JSON.parse(read(relativePath));
}

const SWIFT_SOURCE_EXCLUDED_DIRECTORIES = new Set([
  "Assets.xcassets",
  "Preview Content",
  "Resources",
]);

function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isDirectory() && SWIFT_SOURCE_EXCLUDED_DIRECTORIES.has(entry.name)) {
      return [];
    }
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return walk(path);
    return statSync(path).isFile() ? [path] : [];
  });
}

function swiftSources() {
  return walk(resolve(ROOT, "App"))
    .filter((path) => path.endsWith(".swift"))
    .map((path) => ({
      path,
      relativePath: relative(ROOT, path),
      source: readFileSync(path, "utf8"),
    }));
}

function catalog(name) {
  return readJSON(`App/Localization/${name}.xcstrings`);
}

function assertLiteralSurfaceSnapshot(
  surfaces,
  expectedCount,
  expectedSHA256,
) {
  const entries = scanContent().filter((entry) =>
    surfaces.includes(entry.surface)
  );
  const approvedBaseline = new Set(
    readJSON(
      "localization/content-inventory/hardcoded-baseline.json",
    ).fingerprints,
  );
  assert.equal(entries.length, expectedCount, `${surfaces} literal count`);
  assert.ok(
    entries.every((entry) => approvedBaseline.has(entry.fingerprint)),
    `${surfaces} contains a literal outside the approved inventory baseline`,
  );
  const digest = createHash("sha256")
    .update(entries.map((entry) => entry.fingerprint).sort().join("\n"))
    .digest("hex");
  assert.equal(digest, expectedSHA256, `${surfaces} literal snapshot`);
}

function collectStringUnits(localization) {
  const units = new Map();

  function visit(node, path = []) {
    if (!node || typeof node !== "object") return;
    if (node.stringUnit) {
      units.set(path.join(".") || "base", node.stringUnit);
    }
    for (const [key, value] of Object.entries(node)) {
      if (key === "stringUnit") continue;
      if (value && typeof value === "object") {
        visit(value, [...path, key]);
      }
    }
  }

  visit(localization);
  return units;
}

function placeholderTypes(value) {
  const matches = value.match(
    /%(?:\d+\$)?[-+#0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|L|q|z|t|j)?[@diuoxXfFeEgGaAcCsSp%]/g,
  ) ?? [];
  return matches
    .filter((token) => token !== "%%")
    .map((token) => {
      const canonical = token.replace(/^%\d+\$/, "%");
      return canonical.match(/(?:hh|h|ll|l|L|q|z|t|j)?[@a-zA-Z]$/)?.[0]
        ?? canonical;
    })
    .sort();
}

function decodeSwiftLiteral(value) {
  return JSON.parse(`"${value}"`);
}

function localizedStringCalls(source) {
  const calls = [];
  const explicitTable =
    /RDLocalization\.(?:string|format)\(\s*"((?:\\.|[^"\\])*)"\s*,\s*table:\s*\.([A-Za-z]+)\s*,\s*fallback:\s*"((?:\\.|[^"\\])*)"/gs;
  const defaultTable =
    /RDLocalization\.(?:string|format)\(\s*"((?:\\.|[^"\\])*)"\s*,\s*fallback:\s*"((?:\\.|[^"\\])*)"/gs;

  for (const match of source.matchAll(explicitTable)) {
    calls.push({
      key: decodeSwiftLiteral(match[1]),
      catalog: TABLE_CASE_TO_CATALOG[match[2]],
      fallback: decodeSwiftLiteral(match[3]),
    });
  }
  for (const match of source.matchAll(defaultTable)) {
    calls.push({
      key: decodeSwiftLiteral(match[1]),
      catalog: "Localizable",
      fallback: decodeSwiftLiteral(match[2]),
    });
  }
  return calls;
}

function localizedPluralCalls(source) {
  const calls = [];
  const regex =
    /RDLocalization\.plural\(\s*"((?:\\.|[^"\\])*)"\s*,\s*table:\s*\.([A-Za-z]+)\s*,[\s\S]*?fallbackOne:\s*"((?:\\.|[^"\\])*)"\s*,\s*fallbackOther:\s*"((?:\\.|[^"\\])*)"/g;
  for (const match of source.matchAll(regex)) {
    calls.push({
      key: decodeSwiftLiteral(match[1]),
      catalog: TABLE_CASE_TO_CATALOG[match[2]],
      fallbackOne: decodeSwiftLiteral(match[3]),
      fallbackOther: decodeSwiftLiteral(match[4]),
    });
  }
  return calls;
}

test("L10N-001", "shipping catalog tr/en key parity is complete", () => {
  const actualCatalogs = readdirSync(LOCALIZATION_ROOT)
    .filter((name) => name.endsWith(".xcstrings"))
    .map((name) => name.replace(/\.xcstrings$/u, ""))
    .sort();
  assert.deepEqual(actualCatalogs, EXPECTED_CATALOGS);

  let keyCount = 0;
  for (const name of EXPECTED_CATALOGS) {
    const parsed = catalog(name);
    assert.equal(parsed.sourceLanguage, "tr", `${name} sourceLanguage`);
    assert.equal(parsed.version, "1.0", `${name} catalog version`);

    for (const [key, entry] of Object.entries(parsed.strings ?? {})) {
      keyCount += 1;
      assert.ok(entry.comment?.trim(), `${name}:${key} lacks context comment`);
      assert.match(
        entry.comment,
        /placeholders?/iu,
        `${name}:${key} lacks placeholder metadata`,
      );
      for (const language of ["tr", "en"]) {
        const units = collectStringUnits(entry.localizations?.[language]);
        assert.ok(units.size > 0, `${name}:${key} lacks ${language}`);
        for (const [path, unit] of units) {
          assert.equal(
            unit.state,
            "translated",
            `${name}:${key}:${language}:${path} is not translated`,
          );
          assert.ok(
            typeof unit.value === "string" && unit.value.trim().length > 0,
            `${name}:${key}:${language}:${path} is empty`,
          );
        }
      }
    }
  }
  assert.ok(keyCount >= 2_000, `unexpected catalog key count ${keyCount}`);
});

test("L10N-002", "placeholder type and count parity is complete", () => {
  for (const name of EXPECTED_CATALOGS) {
    const parsed = catalog(name);
    for (const [key, entry] of Object.entries(parsed.strings ?? {})) {
      const turkish = collectStringUnits(entry.localizations?.tr);
      const english = collectStringUnits(entry.localizations?.en);
      assert.deepEqual(
        [...english.keys()].sort(),
        [...turkish.keys()].sort(),
        `${name}:${key} variation structure differs`,
      );
      for (const [path, unit] of turkish) {
        assert.deepEqual(
          placeholderTypes(english.get(path).value),
          placeholderTypes(unit.value),
          `${name}:${key}:${path} placeholder mismatch`,
        );
      }
    }
  }
});

test("L10N-003", "native plural one/other variations are complete", () => {
  const expected = {
    Analysis: [
      "analysis.count.analysis_photos",
      "analysis.count.findings",
      "analysis.count.photos_added",
      "analysis.count.records",
    ],
    Reports: [
      "reports.count.files",
      "reports.count.findings",
    ],
  };
  for (const [name, keys] of Object.entries(expected)) {
    const parsed = catalog(name);
    for (const key of keys) {
      const entry = parsed.strings[key];
      assert.ok(entry, `${name}:${key} missing`);
      for (const language of ["tr", "en"]) {
        const plural = entry.localizations?.[language]?.variations?.plural;
        for (const category of ["one", "other"]) {
          const value = plural?.[category]?.stringUnit?.value;
          assert.ok(value, `${name}:${key}:${language}:${category} missing`);
          assert.deepEqual(
            placeholderTypes(value),
            ["lld"],
            `${name}:${key}:${language}:${category} placeholder`,
          );
        }
      }
    }
  }
});

test("L10N-004", "Swift user-facing hard-coded literal debt is zero", () => {
  const debt = scanContent().filter((entry) => entry.surface === "ios_ui");
  assert.deepEqual(
    debt.map((entry) => `${entry.source_file}:${entry.line}:${entry.source_tr}`),
    [],
  );
});

test("L10N-005", "backend user-facing literal scan matches approved baseline", () => {
  assertLiteralSurfaceSnapshot(
    ["backend"],
    // 2026-09-24: reviewed against 63a338fe: 21 new units, none removed:
    // Turkish fallbacks and PDF headings in the OSGB photo-analysis job
    // (process-isg-workspace-jobs). The notebook reminder push moved to
    // _shared/user-facing-copy.ts with an English pair.
    269,
    "c6d946b40f95eccde254828a0e0ab56791ad3e77b769b5962c34c9f5e12bdab1",
  );
});

test("L10N-006", "PDF/XLSX literal scan matches approved baseline", () => {
  assertLiteralSurfaceSnapshot(
    ["pdf", "xlsx"],
    // Multiline console diagnostics are not PDF/XLSX document copy (12 removed).
    // Training Recommendations export adds 11 reviewed TR/EN XLSX literals.
    437,
    "e9acc2e255581c1bf75311baccb57d755fd03c374dc7c7139733dbfd07c63fd7",
  );
});

test("L10N-007", "notification/email literal scan matches approved baseline", () => {
  assertLiteralSurfaceSnapshot(
    ["notification", "push", "email"],
    // Five baseline diagnostics were logs, not notification/email messages.
    // 2026-09-24: reviewed against 63a338fe: 12 new units, none removed; the
    // OSGB workspace transactional notifications (overdue, due soon,
    // assignment, report ready, handover), paired TR/EN.
    69,
    "22845f843f2e21aab5a7ff22dbd3bfbf4c468fbdaa9d6bad2c0f070869e5d239",
  );
});

test("L10N-008", "InfoPlist usage descriptions cover tr and en", () => {
  const parsed = catalog("InfoPlist");
  assert.deepEqual(Object.keys(parsed.strings).sort(), [
    "CFBundleDisplayName",
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
  ]);
  const plist = read("Config/RiskDetectedInfo.plist");
  for (const key of [
    "CFBundleDisplayName",
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
  ]) {
    assert.match(plist, new RegExp(`<key>${key}</key>`, "u"));
    for (const language of ["tr", "en"]) {
      assert.ok(parsed.strings[key].localizations[language].stringUnit.value);
    }
  }
});

test("L10N-009", "P0/P1 accessibility identifiers and labels are wired", () => {
  const allSwift = swiftSources().map(({ source }) => source).join("\n");
  const requiredIdentifiers = [
    "onboarding.splash.start",
    "onboarding.pain.continue",
    "onboarding.role.continue",
    "onboarding.safety_profile.continue",
    "home.photo_tray.primary",
    "home.start_scan",
    "profile.root",
    "report.root",
    "result.original_language_badge",
  ];
  for (const identifier of requiredIdentifiers) {
    assert.ok(
      allSwift.includes(`"${identifier}"`),
      `missing accessibility identifier ${identifier}`,
    );
  }
  const components = read(
    "App/Views/Onboarding/V2/Components/OBComponents.swift",
  );
  assert.match(components, /\.accessibilityLabel\(displayTitle\)/u);
  const home = read("App/Views/Home/HomeView.swift");
  assert.match(
    home,
    /\.accessibilityIdentifier\("home\.photo_tray\.primary"\)/u,
  );
  assert.match(home, /\.accessibilityLabel\(\s*photos\.isEmpty/su);
});

test("L10N-010", "Wave 1 country profile and safety keys are complete", () => {
  const manifest = readJSON(
    "localization/generated/safety-profiles.manifest.json",
  );
  assert.deepEqual(
    manifest.profiles.map((profile) => profile.id),
    [
      "tr-tr-current-v1",
      "en-intl-generic-v1",
      "en-gb-generic-v1",
      "en-us-generic-v1",
      "en-au-generic-v1",
      "en-ca-generic-v1",
    ],
  );

  const safety = catalog("SafetyTerminology");
  const requiredKeys = [
    "safety.profile.title",
    "safety.profile.body",
    "safety.profile.footer",
    ...["tr", "intl", "gb", "us", "au", "ca"].flatMap((profile) => [
      `safety.profile.${profile}.title`,
      `safety.profile.${profile}.subtitle`,
    ]),
  ];
  assert.deepEqual(Object.keys(safety.strings).sort(), requiredKeys.sort());
  assert.equal(
    safety.strings["safety.profile.title"].localizations.en.stringUnit.value,
    "Choose your safety terminology",
  );
  assert.equal(
    safety.strings["safety.profile.body"].localizations.en.stringUnit.value,
    "Select the terminology used for your work. This changes wording in analyses and reports; it does not certify legal compliance.",
  );
  assert.equal(
    safety.strings["safety.profile.footer"].localizations.en.stringUnit.value,
    "You can change this for future analyses in Profile.",
  );
  assert.deepEqual(
    ["intl", "gb", "us", "au", "ca"].map(
      (profile) =>
        safety.strings[`safety.profile.${profile}.title`]
          .localizations.en.stringUnit.value,
    ),
    ["International", "UK", "US", "AU", "CA"],
  );
});

test("L10N-011", "unapproved safety-sensitive English copy cannot ship", () => {
  const localization = read("App/Services/RDLocalization.swift");
  assert.match(
    localization,
    /static let englishShippingApproved = false/u,
  );
  assert.match(
    localization,
    /RDLanguage\.current == \.turkish \|\| englishShippingApproved/u,
  );

  const progress = catalog("ProfessionalProgress");
  for (const [key, entry] of Object.entries(progress.strings)) {
    assert.match(
      entry.comment,
      /review: machine_draft/u,
      `ProfessionalProgress:${key} review state`,
    );
    assert.match(
      entry.comment,
      /shipping: native_language_and_safety_review_required/u,
      `ProfessionalProgress:${key} shipping gate`,
    );
  }

  const manifest = readJSON(
    "localization/generated/safety-profiles.manifest.json",
  );
  assert.equal(manifest.review_status, "machine_draft");
  assert.ok(
    manifest.profiles.every(
      (profile) => profile.review_status === "machine_draft",
    ),
  );
  for (const evidence of Object.values(manifest.human_approval_evidence)) {
    assert.deepEqual(evidence, []);
  }
});

test("L10N-012", "pseudolocalization and accessibility layout UI gate exists", () => {
  const uiTests = read("RiskDetectedUITests/RiskDetectedUITests.swift");
  assert.match(
    uiTests,
    /func testEnglishPseudolocalizationKeepsPrimaryNavigationReachable\(\)/u,
  );
  assert.match(uiTests, /"-NSDoubleLocalizedStrings", "YES"/u);
  assert.match(
    uiTests,
    /UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge/u,
  );
  assert.match(
    uiTests,
    /func testEnglishMainAccessibilityLayoutAtLargestDynamicType\(\)/u,
  );
});

test("L10N-013", "every fallback is the Turkish value for the same key", () => {
  const parsedCatalogs = Object.fromEntries(
    EXPECTED_CATALOGS.map((name) => [name, catalog(name)]),
  );
  let callCount = 0;
  for (const { relativePath, source } of swiftSources()) {
    for (const call of localizedStringCalls(source)) {
      callCount += 1;
      assert.ok(call.catalog, `${relativePath}:${call.key} unknown table`);
      const entry = parsedCatalogs[call.catalog].strings[call.key];
      assert.ok(entry, `${relativePath}:${call.catalog}:${call.key} missing`);
      const turkish = entry.localizations?.tr?.stringUnit?.value;
      assert.equal(
        call.fallback,
        turkish,
        `${relativePath}:${call.key} fallback differs from tr`,
      );
    }
    for (const call of localizedPluralCalls(source)) {
      callCount += 1;
      const entry = parsedCatalogs[call.catalog].strings[call.key];
      assert.ok(entry, `${relativePath}:${call.catalog}:${call.key} missing`);
      assert.equal(
        call.fallbackOne,
        entry.localizations.tr.variations.plural.one.stringUnit.value,
        `${relativePath}:${call.key} one fallback`,
      );
      assert.equal(
        call.fallbackOther,
        entry.localizations.tr.variations.plural.other.stringUnit.value,
        `${relativePath}:${call.key} other fallback`,
      );
    }
  }
  // Eşik, eski paywall ekranları (InAppPaywallView/OBTimelinePaywallView) Claude
  // Design paywall akışıyla değiştirilip silindikten sonra güncellendi.
  assert.ok(callCount >= 1_850, `unexpected localized call count ${callCount}`);
});

test("L10N-014", "user-owned content remains outside system translation", () => {
  const history = read("App/Models/HistoryItem.swift");
  const recent = read("App/Models/RecentAnalysis.swift");
  const result = read("App/Views/Result/ResultView.swift");
  const reports = read("App/Views/Report/ReportView.swift");
  assert.match(history, /title: row\.title/u);
  assert.match(recent, /title: row\.title/u);
  assert.match(result, /preparedBy: app\.profile\?\.displayName \?\? ""/u);
  assert.match(result, /preparedTitle: app\.profile\?\.title \?\? ""/u);
  assert.match(reports, /preparedBy: app\.profile\?\.displayName \?\? ""/u);
  assert.match(reports, /preparedTitle: app\.profile\?\.title \?\? ""/u);
  assert.doesNotMatch(
    `${history}\n${recent}`,
    /RDLocalization\.(?:string|format)\([^)]*row\.title/su,
  );
});

test("L10N-015", "historical Turkish content is labelled and export-gated", () => {
  const result = read("App/Views/Result/ResultView.swift");
  const analysis = catalog("Analysis");
  assert.match(
    result,
    /app\.languagePreference == \.english && analysisOutputLanguage == \.turkish/u,
  );
  assert.match(result, /historicalLanguageBadge/u);
  assert.match(result, /showsLanguageMismatchWarning: showsHistoricalLanguageBadge/u);
  assert.match(
    result,
    /ForEach\(\[options\.language\]\)/u,
    "report language selector must expose only the analysis language",
  );
  const englishValues = Object.values(analysis.strings)
    .map((entry) => entry.localizations?.en?.stringUnit?.value)
    .filter(Boolean);
  assert.ok(englishValues.includes("Original content: Turkish"));
  assert.ok(
    englishValues.includes(
      "System and user-entered fields remain in their original language. English export is not available for this analysis.",
    ),
  );
  assert.ok(
    englishValues.includes(
      "This analysis was created in Turkish. Edit only the fields you intend to change; unchanged content stays in its original language.",
    ),
  );
});

test("L10N-016", "reviewer-found English action labels stay corrected", () => {
  const analysis = catalog("Analysis");
  const localizable = catalog("Localizable");
  const expected = [
    [
      analysis,
      "analysis.analysis.sector.picker.view.devam.et.04ec7e11",
      "Continue",
    ],
    [
      analysis,
      "analysis.analysis.sector.picker.view.kapat.c36ab4f2",
      "Close",
    ],
    [
      analysis,
      "analysis.canvas.sheet.kapat.3bb9ffb8",
      "Close",
    ],
    [
      analysis,
      "analysis.home.view.kapat.349873ed",
      "Close",
    ],
    [
      localizable,
      "localizable.root.view.devam.et.3ce8f48e",
      "Continue",
    ],
  ];

  for (const [parsed, key, value] of expected) {
    assert.equal(
      parsed.strings[key]?.localizations?.en?.stringUnit?.value,
      value,
      `${key} English reviewer correction`,
    );
  }

  const allEnglishValues = EXPECTED_CATALOGS.flatMap((name) =>
    Object.values(catalog(name).strings ?? {}).flatMap((entry) =>
      [...collectStringUnits(entry.localizations?.en).values()]
        .map((unit) => unit.value),
    )
  );
  assert.ok(!allEnglishValues.includes("Deva and"));
  assert.ok(!allEnglishValues.includes("Quarter"));
});

test("L10N-017", "machine-translation artifacts cannot re-enter English catalogs", () => {
  const expected = [
    ["Localizable", "localizable.profile.view.logo.ekle.c6da0e71", "Add logo"],
    ["Localizable", "localizable.annotation.daire.a28877ec", "Circle"],
    ["Localizable", "localizable.annotation.kutu.ed6d70b4", "Rectangle"],
    ["Analysis", "analysis.analysis.sector.maden.87eb5434", "Mining"],
    ["Analysis", "analysis.result.view.siddet.833f9fd6", "Severity"],
    ["Analysis", "analysis.result.view.olasilik.d9d3070a", "PROBABILITY →"],
    ["Onboarding", "onboarding.obpaywall.view.gizlilik.120a8da1", "Privacy"],
    ["Onboarding", "onboarding.onboarding.view.risk.hesaplamasi.91234ce8", "RISK SCORING"],
    ["Paywall", "paywall.in.app.paywall.view.coklu.fotograf.analizi.c5d7318b", "Multi-Photo Analysis"],
    ["ProfessionalProgress", "professionalprogress.professional.progress.competency.map.view.maden.cba516d8", "Mining"],
    ["Reports", "reports.report.view.raporu.sil.2d768ded", "Delete report"],
  ];
  for (const [catalogName, key, value] of expected) {
    assert.equal(
      catalog(catalogName).strings[key]?.localizations?.en?.stringUnit?.value,
      value,
      `${catalogName}:${key} English quality correction`,
    );
  }

  const forbidden = [
    "Annoyed",
    "Belgian not",
    "Bulguyu strength",
    "Deva and",
    "Dodgy",
    "Force report",
    "Her is",
    "logo ekle",
    "Quarter",
    "RISK HESAPLAMASI",
    "The food",
    "Violence",
  ];
  const allEnglishValues = EXPECTED_CATALOGS.flatMap((name) =>
    Object.values(catalog(name).strings ?? {}).flatMap((entry) =>
      [...collectStringUnits(entry.localizations?.en).values()]
        .map((unit) => unit.value),
    )
  );
  for (const artifact of forbidden) {
    assert.ok(
      !allEnglishValues.some((value) => value.includes(artifact)),
      `forbidden English machine-translation artifact: ${artifact}`,
    );
  }
});

test("L10N-017A", "subscription plan names remain untranslated in Turkish", () => {
  const localizable = catalog("Localizable");
  const paywall = catalog("Paywall");
  const expectedPlanLabels = [
    [
      localizable,
      "localizable.user.profile.free.42029988",
      "FREE",
    ],
    [
      localizable,
      "localizable.user.profile.plus.4afa6f60",
      "PLUS",
    ],
    [
      localizable,
      "localizable.user.profile.pro.a455761d",
      "PRO",
    ],
    [
      paywall,
      "paywall.in.app.paywall.view.ucretsiz.61d66735",
      "FREE",
    ],
    [
      paywall,
      "paywall.in.app.paywall.view.plus.6c6df3b6",
      "PLUS",
    ],
  ];

  for (const [parsed, key, value] of expectedPlanLabels) {
    assert.equal(
      parsed.strings[key]?.localizations?.tr?.stringUnit?.value,
      value,
      `${key} Turkish plan label`,
    );
  }

  for (const catalogName of EXPECTED_CATALOGS) {
    for (
      const [key, entry] of Object.entries(
        catalog(catalogName).strings ?? {},
      )
    ) {
      const englishUnits = collectStringUnits(entry.localizations?.en);
      const turkishUnits = collectStringUnits(entry.localizations?.tr);
      for (const [path, englishUnit] of englishUnits) {
        const turkishValue = turkishUnits.get(path)?.value ?? "";
        for (const planName of ["Plus", "Pro"]) {
          const englishPlanPattern = new RegExp(
            `(^|[^A-Za-z])${planName}([^A-Za-z]|$)`,
          );
          if (!englishPlanPattern.test(englishUnit.value)) continue;
          const turkishPlanPattern = new RegExp(
            `(^|[^A-Za-z])${planName}([^A-Za-z]|$)`,
            "i",
          );
          assert.match(
            turkishValue,
            turkishPlanPattern,
            `${catalogName}:${key}:${path} must preserve ${planName} in Turkish`,
          );
        }
      }
    }
  }
});

test("L10N-017B", "risk-method proper nouns survive translation", () => {
  // "Fine-Kinney" iki arastirmacinin soyadidir (W.T. Fine, G.F. Kinney) ve
  // uluslararasi bir yontem adidir; hicbir dilde cevrilmez. 2026-08-19'da makine
  // cevirisi "Fine" sifatini "Ince" diye cevirip dort anahtari bozmustu, besincisinde
  // de "Kinnet" yazim hatasi vardi — ikisi de canli iOS ekranlarina cikti.
  const forbidden = [/\bİnce[\s-]?Kinney\b/i, /\bKinnet\b/i];

  for (const catalogName of EXPECTED_CATALOGS) {
    const parsed = catalog(catalogName);
    for (const key of Object.keys(parsed.strings)) {
      for (const language of ["tr", "en"]) {
        for (const [path, unit] of collectStringUnits(
          parsed.strings[key].localizations?.[language],
        )) {
          const value = unit.value ?? "";
          for (const pattern of forbidden) {
            assert.ok(
              !pattern.test(value),
              `${catalogName}:${key}:${path} (${language}) must spell the method "Fine-Kinney": ${value}`,
            );
          }
          // "Kinney" gecen her yerde ozel ad ya tam yazilir ya da dar rozetlerde
          // "F-KINNEY" kisaltmasiyla gecer; ikisi de her dilde aynidir.
          if (/\bKinney\b/i.test(value)) {
            assert.match(
              value,
              /(Fine[\s-]?Kinney|\bF-KINNEY\b)/i,
              `${catalogName}:${key}:${path} (${language}) must keep the full "Fine-Kinney" name`,
            );
          }
        }
      }
    }
  }
});

test("L10N-018", "approved Turkish catalog source remains locked", () => {
  const rows = [];
  for (const name of EXPECTED_CATALOGS) {
    const parsed = catalog(name);
    for (const key of Object.keys(parsed.strings).sort()) {
      for (const [path, unit] of collectStringUnits(
        parsed.strings[key].localizations?.tr,
      )) {
        rows.push([name, key, path, unit.value].join("\t"));
      }
    }
  }
  assert.equal(rows.length, 6_540, "Turkish localized-unit count");
  assert.equal(
    createHash("sha256").update(rows.join("\n")).digest("hex"),
    // 2026-08-19: "Fine-Kinney" dort anahtarda makine cevirisiyle "Ince Kinney"
    // olmustu ve bir anahtarda "Kinnet" yazim hatasi vardi. Fine-Kinney bir ozel
    // ad (W.T. Fine + G.F. Kinney) ve uluslararasi terim; hicbir dilde cevrilmez.
    // Yazim hatasi anahtar adinda da vardi; anahtar uretecin kendi kuraliyla
    // yeniden hesaplandi (...fine.kinney.5.5.rapor.hazir.fdc34345).
    // 2026-08-19: plan ozeti kilit metni sahip istegiyle yeniden yazildi.
    // 2026-08-19: paywall zaman cizelgesinde "Bugun" aciklamasi basligin altina
    // alindi; satir ici tire on eki ("— ") artik gereksiz oldugu icin kaldirildi.
    // 2026-08-19: kayan ozellik seridine alti yeni etiket, plan kartina yillik toplam
    // satiri ve alt bara yenileme fiyati eklendi; 7. gun aciklamasi sadelestirildi.
    // 2026-08-19: onboarding yukleme adimlarinda secim etiketi metne uc uca ekleniyordu
    // ("Insaaticin ..."); uc metin yer tutuculu bicime cevrildi. Plan ozeti sablon
    // sayisi 47'den 896'ya guncellendi.
    // 2026-08-20: paywall 7. gun aciklamasi ekranda yer kazanmak icin tek satira indi.
    // 2026-08-30: yeni sonuc merkezi ve bulgu detay ekranlarindaki kullanici
    // metinleri Analysis kataloguna tasindi; rapor saha-dogrulamasi etiketi eklendi.
    // 2026-08-30: egitim onerileri filtresine varsayilan "Tumu" secenegi eklendi.
    // 2026-09-06: reviewed against 12d85089: exactly 26 new Paywall units
    // (24 dark-paywall labels/features, trial and cancellation disclosures).
    // All other Turkish catalog units are unchanged; owner-requested copy.
    // 2026-09-08: ATT prompt removed; original catalog snapshot restored.
    // 2026-09-24: reviewed against 63a338fe: 3,925 new units (Localizable
    // 3,765, Reports 116, Analysis 44) from the İSGADA/Nova screens and the
    // L10N-004 move of Swift copy into the catalogs; none removed. Two
    // existing units changed on purpose: CFBundleDisplayName "RiskDetected"
    // -> "İSGADA" (matches INFOPLIST_KEY_CFBundleDisplayName since 7fa86431)
    // and the history search prompt "Analiz ara" -> "Analiz, firma veya
    // sektör ara".
    // 2026-09-25: reviewed against b5d911e1: 98 new units (Localizable 96,
    // Analysis 2) for the risk/emergency document wizard, the PPE sample form,
    // follow-up v2 and the report download error; none removed or changed.
    // 2026-09-25: the risk wizard's score note drops "Yeni maddeler uzman
    // incelemesi bekleyen taslaklardır." (no expert-approval step, owner
    // decision); that one unit changed, none added or removed.
    // 2026-09-24: 106 new Localizable units: 103 localizable.nova.foryou.*
    // for the "Senin İçin" home section and 3 localizable.nova.shell.pending.*
    // for the home header's pending count; none removed or changed.
    // 2026-09-25: 1 new Localizable unit, localizable.nova.checklist.wizard.open
    // ("Sihirbaz ile liste oluştur") for the checklist wizard entry; the
    // wizard's own copy ships in rd-checklist.js. None removed or changed.
    // 2026-09-25: reviewed against 93be1f66: 18 new units (Localizable 16,
    // Reports 2) for list-screen copy that 9f52156b left hard-coded or
    // uncatalogued: list hints, section titles and counts, the equipment and
    // nonconformity action and stat labels, and the missing
    // localizable.nova.document.filter.all ("Tüm durumlar"). One unit changed:
    // localizable.nova.file.add.short "Dosya" -> "Dosya Ekle", the label the
    // restyled add button asks for. None removed.
    // 2026-09-25: 5 new Localizable units for the "Senin İçin" progress card
    // that covers the whole record: localizable.nova.foryou.performance.
    // analyses_total.{title,detail}, trainings_total.{title,detail} and
    // nonconformities_total.title. None removed or changed.
    "ddf921fbf68c0bea7cbd246c5de21f9cfb58d4a900fd603d9f57fadc55dbbdf3",
    "Turkish catalog snapshot changed",
  );
  assert.equal(
    catalog("Onboarding").strings[
      "onboarding.obtrial.invite.view.uygulamayi.faee4cf2"
    ].localizations.tr.stringUnit.value,
    "Ücretsiz ",
    "approved Turkish source spacing correction",
  );
});

test("L10N-NATIVE", "native per-app language architecture is enforced", () => {
  const localization = read("App/Services/RDLocalization.swift");
  const profile = read("App/Views/Profile/ProfileView.swift");
  const project = read("RiskDetected.xcodeproj/project.pbxproj");
  const appSource = swiftSources().map(({ source }) => source).join("\n");

  assert.match(localization, /Bundle\.main\.preferredLocalizations/u);
  assert.match(profile, /UIApplication\.openSettingsURLString/u);
  assert.match(project, /developmentRegion = tr;/u);
  assert.match(project, /knownRegions = \([\s\S]*\ben,[\s\S]*\btr,/u);
  assert.doesNotMatch(
    appSource,
    /UserDefaults[\s\S]{0,160}AppleLanguages|AppleLanguages[\s\S]{0,160}(?:set|setValue)/u,
  );
  assert.doesNotMatch(
    appSource,
    /method_exchangeImplementations|object_setClass|class_replaceMethod/u,
  );
});

test("JUR-005/006/007", "English onboarding excludes Türkiye credentials", () => {
  const onboarding = read(
    "App/Views/Onboarding/V2/OnboardingViewV2.swift",
  );
  const state = read("App/Views/Onboarding/V2/OnboardingV2State.swift");
  const uiTests = read("RiskDetectedUITests/RiskDetectedUITests.swift");
  assert.match(
    onboarding,
    /if state\.appLanguage == \.turkish \{\s*OBCertificateView/su,
  );
  assert.match(
    onboarding,
    /else \{\s*OBProfessionalRoleView/su,
  );
  assert.match(
    onboarding,
    /if state\.appLanguage == \.turkish \{\s*OBHazardClassView/su,
  );
  assert.match(
    onboarding,
    /else \{\s*OBSafetyProfileSelectionView/su,
  );
  assert.match(
    state,
    /certificateClass: appLanguage == \.turkish[\s\S]*?: nil/u,
  );
  assert.match(
    state,
    /hazardClasses: appLanguage == \.turkish[\s\S]*?: \[\]/u,
  );
  assert.match(uiTests, /XCTAssertFalse\(exists\("A Sınıfı İSG Uzmanı"/u);
  assert.match(uiTests, /XCTAssertFalse\(exists\("OSGB"/u);
});

test("JUR-008", "storefront cannot select a safety profile", () => {
  const generatedSwift = read("App/Generated/SafetyProfiles.generated.swift");
  const appState = read("App/AppState.swift");
  assert.doesNotMatch(generatedSwift, /storefront/iu);
  assert.match(
    appState,
    /RDGlobalLocalizationBuildGate\.isEnabled\s+&&\s+languagePreference == \.english\s+&&\s+safetyProfileID == nil/u,
  );
});

test("JUR-009", "profile changes only affect new analysis snapshots", () => {
  const appState = read("App/AppState.swift");
  assert.match(
    appState,
    /var localizationRequestForNewAnalysis: RDAnalysisLocalizationRequest\?/u,
  );
  assert.match(
    appState,
    /func setSafetyProfile\(_ profileID: RDSafetyProfileID\)/u,
  );
  assert.doesNotMatch(
    appState,
    /setSafetyProfile[\s\S]{0,900}(?:update|patch)[\s\S]{0,120}analyses/iu,
  );
});

test(
  "JUR-010",
  "onboarding persists terminology and standalone English auth defaults to International",
  () => {
    const appState = read("App/AppState.swift");
    const onboardingAnswers = read("App/Services/OnboardingAnswersService.swift");
    const migration = read(
      "supabase/migrations/20260801214500_default_english_international_safety_profile.sql",
    );
    const uiTests = read("RiskDetectedUITests/RiskDetectedUITests.swift");

    assert.match(
      onboardingAnswers,
      /draft\.appLanguage == RDLanguage\.english\.rawValue[\s\S]*draft\.safetyProfileID[\s\S]*safety_profile_id: definition\.id\.rawValue/su,
    );
    assert.match(
      onboardingAnswers,
      /\.from\("profiles"\)[\s\S]*\.update\([\s\S]*LocalizationPayload/su,
    );
    assert.match(
      appState,
      /ensureAuthenticatedSafetyProfileDefaultIfNeeded\(\)[\s\S]*RDSafetyProfileCatalog\.englishFallbackProfileID/su,
    );
    assert.match(
      appState,
      /flow != \.onboarding \|\| hasSeenOnboarding/u,
    );
    assert.match(
      migration,
      /else[\s\S]*new\.safety_profile_id := 'en-intl-generic-v1';[\s\S]*new\.preferred_content_locale := 'en-001';[\s\S]*new\.work_jurisdiction_country := 'INTL';/su,
    );
    assert.match(
      migration,
      /when 'en-gb-generic-v1'[\s\S]*when 'en-us-generic-v1'[\s\S]*when 'en-au-generic-v1'[\s\S]*when 'en-ca-generic-v1'/su,
    );
    assert.match(
      uiTests,
      /testEnglishPaidPhotoTrayShowsThreeSlotsAndTwoPhotos[\s\S]*waitFor\("2\/3"\)[\s\S]*home\.photo_slot\.3/su,
    );
  },
);

let passed = 0;
for (const current of tests) {
  try {
    await current.body();
    passed += 1;
    console.log(`PASS ${current.id} — ${current.name}`);
  } catch (error) {
    console.error(`FAIL ${current.id} — ${current.name}`);
    throw error;
  }
}

console.log(`Localization catalog gates: ${passed}/${tests.length} passed.`);
