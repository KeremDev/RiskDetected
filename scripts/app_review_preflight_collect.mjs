#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const APP_ID = "6769498181";
const VERSION_ID = "e97f1de1-7e8c-448b-a5b9-80869f0a8816";
const VERSION = "1.0";
const BUILD_NUMBER = "31";
const BUILD_ID = "fca919e5-b12a-4129-8d82-cf46ce1736c8";
const PROJECT_REF = "ppcrzemgiztzcgddbins";
const BUNDLE_ID = "com.riskdetected.app";
const now = new Date();
const REPORT_DATE = [
  now.getFullYear(),
  String(now.getMonth() + 1).padStart(2, "0"),
  String(now.getDate()).padStart(2, "0"),
].join("-");
const DEFAULT_IPA_APP = "/tmp/RiskDetectedIPA31/Payload/RiskDetected.app";
const MANUAL_EVIDENCE_FORM = "QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md";
const REVIEW_NOTES_DRAFT = "QA/APP_STORE_REVIEW_NOTES_2026-06-02.md";
const REVIEW_NOTES_AUXILIARY_FILES = [
  "QA/App_Review_Webmail_OTP_Access_2026-06-01.md",
  "QA/App_Store_Submission_Preparation_2026-05-16.md",
];
const SUBMISSION_DAY_RUNBOOK = "QA/APP_REVIEW_SUBMISSION_DAY_RUNBOOK_2026-06-01.md";
const SCREENSHOT_VISUAL_QA_FILE = "QA/APP_STORE_SCREENSHOT_VISUAL_QA_2026-06-02.md";
const SCREENSHOT_PROJECT_FILE = "AppStoreScreenshots/app-store-screenshots.json";
const IPHONE_TR_SCREENSHOT_DIR = "AppStoreScreenshots/public/screenshots/apple/iphone/tr";
const IPHONE_TR_FINAL_SCREENSHOT_DIR = "AppStoreScreenshots/public/screenshots/apple/iphone/tr-6-9-final";
const SUPABASE_CONFIG_FILE = "supabase/config.toml";
const RELEASE_STAGING_GUARD_FILE = "scripts/release_staging_guard.mjs";
const GITIGNORE_FILE = ".gitignore";
const PHYSICAL_SMOKE_EVIDENCE_DIR = "output/app-review-physical-smoke/iphone-17-pro-max";
const SUPABASE_PUBLIC_AUTH_SETTINGS_COMMAND = `
KEY=$(awk '/supabasePublishableKey/{getline; if (match($0, /"[^"]+"/)) print substr($0, RSTART + 1, RLENGTH - 2)}' App/Services/RDConfig.swift)
if [ -z "$KEY" ]; then
  echo "missing publishable key"
  exit 2
fi
curl -fsS -H "apikey: $KEY" https://${PROJECT_REF}.supabase.co/auth/v1/settings
`;
const ACCEPTED_IPHONE_SCREENSHOT_SIZES = new Map([
  ["1260x2736", "iPhone 6.9"],
  ["1290x2796", "iPhone 6.9"],
  ["1320x2868", "iPhone 6.9"],
  ["1179x2556", "iPhone 6.3"],
  ["1206x2622", "iPhone 6.3"],
  ["1170x2532", "iPhone 6.1"],
  ["1125x2436", "iPhone 6.1"],
  ["1080x2340", "iPhone 6.1"],
  ["1284x2778", "iPhone 6.5"],
  ["1242x2688", "iPhone 6.5"],
  ["1242x2208", "iPhone 5.5"],
]);
const PHYSICAL_DEVICE_CANDIDATES = [
  { name: "iPhone Kerem", id: "F8EB649B-8963-59F6-90D0-CE4176B7D1DE", model: "iPhone 17 Pro Max" },
  { name: "Kerem iPhone", id: "36B37C26-C0CB-556F-8A6C-3A07FD290F11", model: "iPhone 14 Pro Max" },
];
const EXPECTED_TURKEY_PRICES = new Map([
  ["riskdetected_plus_monthly", { amount: "199.99", currency: "TRY" }],
  ["riskdetected_plus_yearly", { amount: "1999.99", currency: "TRY" }],
  ["riskdetected_pro_monthly", { amount: "499.99", currency: "TRY" }],
  ["riskdetected_pro_yearly", { amount: "4999.99", currency: "TRY" }],
]);
const PUBLIC_REVIEW_URLS = [
  "https://riskdetected.com",
  "https://riskdetected.com/gizlilik",
  "https://riskdetected.com/kullanim-kosullari",
  "https://riskdetected.com/kvkk",
  "https://riskdetected.com/acik-riza",
  "https://riskdetected.com/cerez-politikasi",
  "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/",
];
const EXPECTED_APP_WEB_URLS = [
  'static let websiteURL = URL(string: "https://riskdetected.com")!',
  'static let supportURL = URL(string: "https://riskdetected.com")!',
  'static let privacyPolicyURL = URL(string: "https://riskdetected.com/gizlilik")!',
  'static let termsURL = URL(string: "https://riskdetected.com/kullanim-kosullari")!',
  'static let kvkkURL = URL(string: "https://riskdetected.com/kvkk")!',
  'static let explicitConsentURL = URL(string: "https://riskdetected.com/acik-riza")!',
];
const BUNDLED_LEGAL_DOCS = [
  "App/LegalDocuments/Gizlilik-Politikasi.md",
  "App/LegalDocuments/Kullanim-Kosullari.md",
  "App/LegalDocuments/KVKK-Aydinlatma-ve-Acik-Riza-Metni.md",
  "App/LegalDocuments/Acik-Riza-Beyani.md",
];
const AI_DISCLOSURE_SOURCE_CHECKS = [
  {
    path: REVIEW_NOTES_DRAFT,
    patterns: [
      "AI-assisted risk analysis",
      "AI output is advisory",
      "does not replace a qualified occupational safety professional",
      "Google Gemini/Google AI with possible Groq-compatible fallback",
    ],
  },
  {
    path: "App/LegalDocuments/Kullanim-Kosullari.md",
    patterns: [
      "Yapay zeka çıktıları",
      "AI çıktıları öneri ve karar destek niteliğindedir.",
      "yetkili iş güvenliği uzmanı",
      "kesin uzman raporu",
    ],
  },
  {
    path: "App/LegalDocuments/Gizlilik-Politikasi.md",
    patterns: [
      "AI",
      "analiz",
      "Üçüncü taraf",
    ],
  },
  {
    path: "App/LegalDocuments/KVKK-Aydinlatma-ve-Acik-Riza-Metni.md",
    patterns: [
      "AI",
      "analiz",
      "açık rıza",
    ],
  },
];
const SUBSCRIPTION_PAYWALL_SOURCE_CHECKS = [
  {
    path: "App/Views/Paywall/PaywallView.swift",
    patterns: [
      "Geri yükle",
      "Satın alımları geri yükle",
      "legalLink(\"Şartlar\", RDConfig.Web.termsURL)",
      "legalLink(\"Gizlilik\", RDConfig.Web.privacyPolicyURL)",
      "legalLink(\"İptal hakkı\", URL(string: \"https://apps.apple.com/account/subscriptions\")!)",
      "Dilediğin zaman App Store ayarlarından iptal edebilirsin.",
      "Yıllık abonelik",
      "Aylık abonelik",
      "shouldUseTRYFallback",
      "normalized.contains(\"$\") || normalized.contains(\"USD\")",
    ],
  },
  {
    path: "App/Views/Paywall/InAppPaywallView.swift",
    patterns: [
      "Geri yükle",
      "legalLink(\"Şartlar\", RDConfig.Web.termsURL)",
      "legalLink(\"Gizlilik\", RDConfig.Web.privacyPolicyURL)",
      "legalLink(\"İptal hakkı\", URL(string: \"https://apps.apple.com/account/subscriptions\")!)",
      "Yıllık abonelik",
      "Aylık abonelik",
      "shouldUseTRYFallback",
      "normalized.contains(\"$\") || normalized.contains(\"USD\")",
      "Yıllık \\(annualPrice) ödeme alınır.",
    ],
  },
  {
    path: "App/AppState.swift",
    patterns: [
      "func purchaseSubscription(packageID: String) async throws",
      "func restoreSubscriptions() async throws -> SubscriptionState",
      "await syncBackendSubscription()",
    ],
  },
];
const RELEASE_SIMULATION_SOURCE_CHECKS = [
  {
    path: "App/Services/ReportFailureSimulation.swift",
    patterns: [
      "#if DEBUG",
      'env["RISKDETECTED_ENABLE_REPORT_TEST_SIMULATION"] == "true"',
      'env["SIMULATE_REPORT_ERROR"] == mode.rawValue',
      "#else\n        return false\n        #endif",
    ],
  },
  {
    path: "App/Services/DataActionFailureSimulation.swift",
    patterns: [
      "#if DEBUG",
      'env["RISKDETECTED_ENABLE_DATA_TEST_SIMULATION"] == "true"',
      'env["SIMULATE_DATA_ERROR"] == mode.rawValue',
      "#else\n        return false\n        #endif",
    ],
  },
  {
    path: "supabase/functions/analyze/index.ts",
    patterns: [
      'Deno.env.get("RISKDETECTED_ENABLE_TEST_SIMULATION") === "true"',
      'Deno.env.get("SIMULATE_AI_ERROR_CODE")',
      'Deno.env.get("SIMULATE_AI_ERROR_ONCE")',
      "enabled: enabled && mode !== null",
    ],
  },
  {
    path: "QA/Production_Log_Privacy_Support_Runbook_2026-05-16.md",
    patterns: [
      "Production secrets must not contain:",
      "supabase secrets list --project-ref ppcrzemgiztzcgddbins",
      "supabase secrets unset RISKDETECTED_ENABLE_TEST_SIMULATION SIMULATE_AI_ERROR_CODE SIMULATE_AI_ERROR_ONCE",
    ],
  },
];
const FORBIDDEN_PRODUCTION_SIMULATION_SECRETS = [
  "RISKDETECTED_ENABLE_TEST_SIMULATION",
  "SIMULATE_AI_ERROR_CODE",
  "SIMULATE_AI_ERROR_ONCE",
];
const ACCOUNT_DELETION_SOURCE_CHECKS = [
  {
    path: "App/Services/RDConfig.swift",
    patterns: ['static let accountDeletionRequestFunctionName = "request-account-deletion"'],
  },
  {
    path: "App/Services/AnalysisService.swift",
    patterns: [
      "func requestAccountDeletion",
      "RDConfig.accountDeletionRequestFunctionName",
      "FunctionInvokeOptions(body: payload)",
    ],
  },
  {
    path: "App/Views/Profile/ProfileView.swift",
    patterns: [
      "ProfileDataControlsSheet",
      "Hesabımı ve verilerimi sil",
      "case requestAccountDeletion",
      "AnalysisService.shared.requestAccountDeletion",
      "Abonelik Apple’dan yönetilir",
    ],
  },
  {
    path: "supabase/functions/request-account-deletion/index.ts",
    patterns: [
      "request-account-deletion",
      "account_deletion_requests",
      "supabase.auth.getUser",
      "account-deletion-complete",
    ],
  },
  {
    path: "supabase/functions/account-deletion-complete/index.ts",
    patterns: [
      "account-deletion-complete",
      "deleteUser",
      "auth_user_deleted",
    ],
  },
];
const RELEASE_GATING_SOURCE_CHECKS = [
  {
    path: "App/RootView.swift",
    patterns: ["private static var isUITestLaunch", "#if DEBUG", "#else\n        false\n        #endif"],
  },
  {
    path: "App/Services/NetworkMonitor.swift",
    patterns: ["private static var isUITestLaunch", "#if DEBUG", "#else\n        false\n        #endif"],
  },
  {
    path: "App/Services/NotificationService.swift",
    patterns: ["private static var isUITestLaunch", "#if DEBUG", "#else\n        false\n        #endif"],
  },
  {
    path: "App/Views/Auth/AuthView.swift",
    patterns: [
      "#if DEBUG\n    @State private var signingInDemo",
      "#if DEBUG\n    enum DemoAccount",
      "#if DEBUG\n    private func demoButton",
      "private func runDemoSignIn",
    ],
  },
  {
    path: "App/Views/Home/MainTabView.swift",
    patterns: ["private static var isUITestLaunch", "#if DEBUG", "#else\n        false\n        #endif"],
  },
  {
    path: "App/Views/Onboarding/V2/OnboardingViewV2.swift",
    patterns: ["private static var isUITestLaunch", "#if DEBUG", "#else\n        false\n        #endif"],
  },
];

const args = parseArgs(process.argv.slice(2));
const checks = [];
const commands = [];

function parseArgs(argv) {
  const parsed = {
    output: `QA/App_Review_Preflight_Evidence_${REPORT_DATE}.md`,
    ipaApp: DEFAULT_IPA_APP,
    skipAsc: false,
    skipSupabase: false,
    skipDevices: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--output") parsed.output = argv[++index];
    else if (value === "--ipa-app") parsed.ipaApp = argv[++index];
    else if (value === "--skip-asc") parsed.skipAsc = true;
    else if (value === "--skip-supabase") parsed.skipSupabase = true;
    else if (value === "--skip-devices") parsed.skipDevices = true;
    else if (value === "--help") {
      printHelp();
      process.exit(0);
    }
  }

  return parsed;
}

function printHelp() {
  console.log(`Usage: node scripts/app_review_preflight_collect.mjs [options]

Options:
  --output <path>   Markdown evidence report path. Defaults to QA/App_Review_Preflight_Evidence_${REPORT_DATE}.md
  --ipa-app <path>  Unpacked .app path. Defaults to ${DEFAULT_IPA_APP}
  --skip-asc        Skip App Store Connect read-only checks.
  --skip-supabase   Skip Supabase read-only checks.
  --skip-devices    Skip physical-device candidate install checks.
`);
}

function run(name, command, commandArgs, options = {}) {
  const startedAt = Date.now();
  const result = spawnSync(command, commandArgs, {
    cwd: options.cwd ?? process.cwd(),
    encoding: "utf8",
    maxBuffer: options.maxBuffer ?? 25 * 1024 * 1024,
    timeout: options.timeoutMs,
    env: {
      ASC_TIMEOUT: process.env.ASC_TIMEOUT ?? "180s",
      ...process.env,
      ...(options.env ?? {}),
    },
  });

  const commandResult = {
    name,
    command: options.displayCommand ?? [command, ...commandArgs].join(" "),
    status: result.status ?? 1,
    signal: result.signal,
    durationMs: Date.now() - startedAt,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    error: result.error?.message ?? null,
  };
  commands.push(commandResult);
  return commandResult;
}

function addCheck(name, status, detail, evidence = "") {
  checks.push({ name, status, detail, evidence });
}

function statusCounts() {
  return checks.reduce((acc, check) => {
    acc[check.status] = (acc[check.status] ?? 0) + 1;
    return acc;
  }, {});
}

function truncate(text, max = 4000) {
  const value = sanitizeCommandOutput(text).trim();
  if (value.length <= max) return value;
  return `${value.slice(0, max)}\n... truncated ${value.length - max} chars`;
}

function escapeTable(value) {
  return sanitizeCommandOutput(value).replace(/\n/g, "<br>").replace(/\|/g, "\\|");
}

function sanitizeCommandOutput(value) {
  return String(value ?? "")
    .replace(/\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g, "")
    .replace(/[│◒◐◓◑▲]/g, "")
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "");
}

function containsAll(text, needles) {
  return needles.every((needle) => text.includes(needle));
}

function parseMarkdownTableRows(section) {
  return section
    .split("\n")
    .filter((line) => line.trim().startsWith("|") && !line.includes("---"))
    .map((line) => line.trim().slice(1, -1).split("|").map((field) => field.trim()))
    .filter((fields) => fields.length > 0);
}

function formatOpenMarkdownRows(rows, labelIndex, statusIndex, noteIndex = null) {
  return rows
    .filter((fields) => ["TODO", "HOLD", "PARTIAL PASS", "NOT TESTED"].includes(fields[statusIndex] ?? ""))
    .map((fields) => {
      const label = fields[labelIndex] ?? "Unknown row";
      const status = fields[statusIndex] ?? "UNKNOWN";
      const note = noteIndex === null ? "" : fields[noteIndex] ?? "";
      return note ? `${label}: ${status} - ${note}` : `${label}: ${status}`;
    });
}

function scanTextFilesForSecrets() {
  const result = run("repo-secret-file-scan", "find", [
    ".",
    "-type",
    "f",
    "(",
    "-name",
    "*.p8",
    "-o",
    "-name",
    ".env",
    "-o",
    "-name",
    "*.env",
    "-o",
    "-name",
    "AuthKey_*.p8",
    "-o",
    "-name",
    "*AuthKey*",
    ")",
    "-not",
    "-path",
    "./.git/*",
    "-not",
    "-path",
    "./node_modules/*",
    "-not",
    "-path",
    "./AppStoreScreenshots/node_modules/*",
    "-not",
    "-path",
    "./.agents/skills/app-store-screenshots/template/node_modules/*",
    "-print",
  ]);

  addCheck(
    "Repo secret/key file scan",
    result.status === 0 && result.stdout.trim() === "" ? "PASS" : "FAIL",
    result.stdout.trim() === "" ? "No .p8/.env/AuthKey files found." : "Potential secret/key files found.",
    truncate(result.stdout || result.stderr),
  );
}

function checkManualEvidenceForm() {
  if (!existsSync(MANUAL_EVIDENCE_FORM)) {
    addCheck(
      "Manual evidence form exists",
      "FAIL",
      `Missing ${MANUAL_EVIDENCE_FORM}.`,
    );
    return;
  }

  const content = readFileSync(MANUAL_EVIDENCE_FORM, "utf8");
  const todoCount = (content.match(/\bTODO\b/g) ?? []).length;
  const placeholderCount = (content.match(/<PASTE_ONLY_IN_APP_STORE_CONNECT_NOTES>|<PHYSICAL_DEVICE_DEMO_VIDEO_URL>/g) ?? []).length;
  const physicalSmokeStart = content.indexOf("## Physical-Device Smoke Test");
  const finalDecisionStart = content.indexOf("## Final Manual Decision");
  const manualGateSection = physicalSmokeStart === -1 ? content : content.slice(0, physicalSmokeStart);
  const finalDecisionSection = finalDecisionStart === -1 ? "" : content.slice(finalDecisionStart);
  const manualGateOpenRows = formatOpenMarkdownRows(parseMarkdownTableRows(manualGateSection), 0, 2, 4);
  const finalDecisionOpenRows = formatOpenMarkdownRows(parseMarkdownTableRows(finalDecisionSection), 0, 1, 2);
  const secretLikePatterns = [
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
    /AuthKey_[A-Z0-9]+\.p8/,
    /SUPABASE_[A-Z0-9_]*SERVICE_ROLE[A-Z0-9_]*/i,
    /sk-[A-Za-z0-9_-]{20,}/,
    /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/,
  ];
  const secretMatches = secretLikePatterns
    .flatMap((pattern) => content.match(pattern) ?? []);

  addCheck(
    "Manual evidence form completion",
    todoCount === 0 && placeholderCount === 0 ? "PASS" : "HOLD",
    todoCount === 0 && placeholderCount === 0
      ? "Manual evidence form has no TODO or ASC placeholder markers."
      : `Manual evidence form still has ${todoCount} TODO marker(s) and ${placeholderCount} ASC placeholder marker(s).`,
    [
      `Form: ${MANUAL_EVIDENCE_FORM}`,
      ...manualGateOpenRows,
      ...finalDecisionOpenRows,
    ].join("\n"),
  );

  addCheck(
    "Manual evidence form secret hygiene",
    secretMatches.length === 0 ? "PASS" : "FAIL",
    "Manual evidence form should not contain private keys, service-role markers, API keys, or JWT-like secrets.",
    secretMatches.join("\n"),
  );
}

function checkPhysicalSmokeEvidence() {
  if (!existsSync(MANUAL_EVIDENCE_FORM)) {
    addCheck(
      "Physical-device smoke evidence completion",
      "FAIL",
      `Missing ${MANUAL_EVIDENCE_FORM}.`,
    );
    return;
  }

  const content = readFileSync(MANUAL_EVIDENCE_FORM, "utf8");
  const smokeStart = content.indexOf("## Physical-Device Smoke Test");
  const finalDecisionStart = content.indexOf("## Final Manual Decision");
  if (smokeStart === -1 || finalDecisionStart === -1 || finalDecisionStart <= smokeStart) {
    addCheck(
      "Physical-device smoke evidence completion",
      "FAIL",
      "Manual evidence form should contain a Physical-Device Smoke Test section before Final Manual Decision.",
      `Form: ${MANUAL_EVIDENCE_FORM}`,
    );
    return;
  }

  const smokeSection = content.slice(smokeStart, finalDecisionStart);
  const todoCount = (smokeSection.match(/\|\s*TODO\s*\|/g) ?? []).length;
  const partialCount = (smokeSection.match(/\|\s*PARTIAL PASS\s*\|/g) ?? []).length;
  const notTestedCount = (smokeSection.match(/\|\s*NOT TESTED\s*\|/g) ?? []).length;
  const holdCount = (smokeSection.match(/\|\s*HOLD\s*\|/g) ?? []).length;
  const openCount = todoCount + partialCount + notTestedCount + holdCount;
  const openRows = formatOpenMarkdownRows(parseMarkdownTableRows(smokeSection), 0, 1, 2);

  addCheck(
    "Physical-device smoke evidence completion",
    openCount === 0 ? "PASS" : "HOLD",
    openCount === 0
      ? "Physical-device smoke section has no TODO, HOLD, PARTIAL PASS, or NOT TESTED rows."
      : `Physical-device smoke still has ${todoCount} TODO, ${partialCount} PARTIAL PASS, ${notTestedCount} NOT TESTED, and ${holdCount} HOLD row(s).`,
    [
      `Form: ${MANUAL_EVIDENCE_FORM}`,
      ...openRows,
    ].join("\n"),
  );
}

function checkPhysicalSmokeSubgateEvidence() {
  if (!existsSync(MANUAL_EVIDENCE_FORM)) {
    addCheck(
      "Physical-device smoke subgate evidence",
      "FAIL",
      `Missing ${MANUAL_EVIDENCE_FORM}.`,
    );
    return;
  }

  const content = readFileSync(MANUAL_EVIDENCE_FORM, "utf8");
  const smokeStart = content.indexOf("## Physical-Device Smoke Test");
  const finalDecisionStart = content.indexOf("## Final Manual Decision");
  if (smokeStart === -1 || finalDecisionStart === -1 || finalDecisionStart <= smokeStart) {
    addCheck(
      "Physical-device smoke subgate evidence",
      "FAIL",
      "Manual evidence form should contain a Physical-Device Smoke Test section before Final Manual Decision.",
      `Form: ${MANUAL_EVIDENCE_FORM}`,
    );
    return;
  }

  const smokeRows = content.slice(smokeStart, finalDecisionStart)
    .split("\n")
    .filter((line) => line.startsWith("| ") && !line.startsWith("| ---"))
    .map((line) => line.split("|").map((field) => field.trim()).filter(Boolean))
    .filter((fields) => fields.length >= 3 && fields[0] !== "Check");
  const rowByCheck = new Map(smokeRows.map((fields) => [fields[0], fields]));
  const subgates = [
    {
      name: "Physical-device auth smoke",
      detail: "Email OTP, Apple login, and Google login should be manually verified on the physical candidate device.",
      rows: [
        "Email OTP login with `riskdetected.appreview@fastmail.com`",
        "Apple login",
        "Google login",
      ],
    },
    {
      name: "Physical-device onboarding paywall smoke",
      detail: "Onboarding Plus monthly/yearly TL prices should be verified with no USD/fallback copy.",
      rows: [
        "Onboarding Plus monthly price shows TL",
        "Onboarding Plus yearly price shows TL",
        "No fallback price copy appears",
        "No USD storefront price appears",
      ],
    },
    {
      name: "Physical-device purchase and restore smoke",
      detail: "A non-entitled sandbox path should open Apple purchase sheet, update entitlement, sync backend state, and restore purchases.",
      rows: [
        "Sandbox purchase flow opens Apple sheet",
        "Successful sandbox purchase updates entitlement",
        "Restore purchases works",
        "Plus/Pro entitlement sync reaches backend-visible state",
      ],
    },
    {
      name: "Physical-device fresh analysis and report smoke",
      detail: "A fresh free analysis plus fresh PDF/Excel generation should complete without crash, blank screen, stuck loader, or inaccessible CTA.",
      rows: [
        "One Free analysis flow works",
        "PDF report generation starts/completes",
        "Excel report generation starts/completes",
        "No crash, blank screen, stuck loader, or inaccessible CTA",
      ],
    },
  ];

  for (const subgate of subgates) {
    const evidence = [];
    let allPass = true;
    for (const rowName of subgate.rows) {
      const row = rowByCheck.get(rowName);
      if (!row) {
        allPass = false;
        evidence.push(`${rowName}: MISSING`);
        continue;
      }
      const status = row[1] ?? "UNKNOWN";
      if (status !== "PASS") allPass = false;
      evidence.push(`${rowName}: ${status}`);
    }
    addCheck(
      subgate.name,
      allPass ? "PASS" : "HOLD",
      allPass ? `${subgate.detail} All required rows are PASS.` : subgate.detail,
      evidence.join("\n"),
    );
  }
}

function checkPhysicalDeviceReadinessEvidence() {
  const issues = [];
  const evidence = [];
  const readJson = (filePath) => {
    if (!existsSync(filePath)) {
      issues.push(`Missing ${filePath}.`);
      return null;
    }
    try {
      return JSON.parse(readFileSync(filePath, "utf8"));
    } catch (error) {
      issues.push(`${filePath}: could not parse JSON: ${error.message}`);
      return null;
    }
  };
  const readOptionalJson = (filePath) => {
    if (!existsSync(filePath)) return null;
    try {
      return JSON.parse(readFileSync(filePath, "utf8"));
    } catch (error) {
      issues.push(`${filePath}: could not parse JSON: ${error.message}`);
      return null;
    }
  };

  const appsPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/apps-2026-06-02.json`;
  const apps = readJson(appsPath);
  const app = apps?.result?.apps?.find((candidate) => candidate.bundleIdentifier === BUNDLE_ID);
  if (app?.version === VERSION && app?.bundleVersion === BUILD_NUMBER) {
    evidence.push(`${appsPath}: candidate app ${VERSION} (${BUILD_NUMBER}) installed`);
  } else if (apps) {
    issues.push(`${appsPath}: ${BUNDLE_ID} ${VERSION} (${BUILD_NUMBER}) not found`);
  }

  const displayPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/display-2026-06-02.json`;
  const display = readJson(displayPath);
  const primaryDisplay = display?.result?.displays?.find((candidate) => candidate.primary);
  const nativeSize = primaryDisplay?.nativeSize ?? [];
  const displayOk = display?.result?.backlightState === "off"
    && nativeSize[0] === 1320
    && nativeSize[1] === 2868
    && display?.result?.orientation?.currentDeviceNonFlatOrientation === "portrait";
  if (displayOk) {
    evidence.push(`${displayPath}: display 1320x2868 portrait and backlight off`);
  } else if (display) {
    issues.push(`${displayPath}: expected 1320x2868 portrait/backlight-off evidence not found`);
  }

  const lockPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/lockstate-2026-06-02.json`;
  const lockState = readJson(lockPath);
  if (lockState?.result?.passcodeRequired === true && lockState?.result?.unlockedSinceBoot === true) {
    evidence.push(`${lockPath}: passcode required and unlocked since boot`);
  } else if (lockState) {
    issues.push(`${lockPath}: expected passcodeRequired=true and unlockedSinceBoot=true`);
  }

  const launchPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/launch-2026-06-02.json`;
  const launch = readJson(launchPath);
  const launchText = launchPath && existsSync(launchPath) ? readFileSync(launchPath, "utf8") : "";
  if (launch?.info?.outcome === "failed" && launchText.includes("Unable to launch com.riskdetected.app because the device was not, or could not be, unlocked")) {
    evidence.push(`${launchPath}: locked launch retry correctly denied; unlock required for functional smoke`);
  } else if (launch) {
    issues.push(`${launchPath}: expected locked-device launch denial evidence not found`);
  }

  const detailsLatestPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/details-2026-06-02-latest.json`;
  const detailsLatest = readOptionalJson(detailsLatestPath);
  const detailsProps = detailsLatest?.result?.deviceProperties;
  const connectionProps = detailsLatest?.result?.connectionProperties;
  if (
    detailsLatest?.info?.outcome === "success"
    && detailsProps?.name === "iPhone Kerem"
    && detailsProps?.osVersionNumber === "26.5"
    && connectionProps?.tunnelState === "connected"
  ) {
    evidence.push(`${detailsLatestPath}: iPhone Kerem iOS 26.5 booted, developer mode enabled, tunnel connected`);
  } else if (detailsLatest) {
    issues.push(`${detailsLatestPath}: expected iPhone Kerem iOS 26.5 connected-device evidence not found`);
  }

  const launchLatestPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/launch-2026-06-02-latest.json`;
  const launchLatest = readOptionalJson(launchLatestPath);
  const launchLatestText = launchLatest ? readFileSync(launchLatestPath, "utf8") : "";
  if (launchLatest?.error?.code === 10002 && launchLatestText.includes("Unable to launch com.riskdetected.app because the device was not, or could not be, unlocked")) {
    evidence.push(`${launchLatestPath}: latest foreground launch retry was denied because the iPhone is locked`);
  } else if (launchLatest) {
    issues.push(`${launchLatestPath}: expected latest locked-device launch denial evidence not found`);
  }

  const launchRetryPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/launch-2026-06-02-retry-2.json`;
  const launchRetry = readOptionalJson(launchRetryPath);
  if (launchRetry?.info?.outcome === "failed" && launchRetry?.error?.code === 4000) {
    evidence.push(`${launchRetryPath}: later retry acquired the tunnel but device connection could not be established`);
  }

  const lockRetryPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/lockstate-2026-06-02-retry-2.json`;
  const lockRetry = readOptionalJson(lockRetryPath);
  if (lockRetry?.info?.outcome === "failed" && lockRetry?.error?.code === 1010) {
    evidence.push(`${lockRetryPath}: later lock-state retry timed out; unlock and keep device awake before functional smoke`);
  }

  const lockCurrentPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/lockstate-2026-06-02-current.json`;
  const lockCurrent = readOptionalJson(lockCurrentPath);
  if (lockCurrent?.info?.outcome === "success" && lockCurrent?.result?.passcodeRequired === true && lockCurrent?.result?.unlockedSinceBoot === true) {
    evidence.push(`${lockCurrentPath}: current lock-state retry confirms passcode required and unlocked since boot`);
  } else if (lockCurrent) {
    issues.push(`${lockCurrentPath}: expected current lock-state evidence not found`);
  }

  const launchCurrentPath = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/launch-2026-06-02-current.json`;
  const launchCurrent = readOptionalJson(launchCurrentPath);
  const launchCurrentText = launchCurrent ? readFileSync(launchCurrentPath, "utf8") : "";
  if (launchCurrent?.error?.code === 10002 && launchCurrentText.includes("Unable to launch com.riskdetected.app because the device was not, or could not be, unlocked")) {
    evidence.push(`${launchCurrentPath}: current foreground launch retry was denied because the iPhone is locked`);
  } else if (launchCurrent) {
    issues.push(`${launchCurrentPath}: expected current locked-device launch denial evidence not found`);
  }

  const lockCurrent2Path = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/lockstate-2026-06-02-current-2.json`;
  const lockCurrent2 = readOptionalJson(lockCurrent2Path);
  if (lockCurrent2?.info?.outcome === "failed" && lockCurrent2?.error?.code === 4000) {
    evidence.push(`${lockCurrent2Path}: newest lock-state retry timed out while establishing CoreDevice tunnel`);
  }

  const appsCurrent2Path = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/apps-2026-06-02-current-2.json`;
  const appsCurrent2 = readOptionalJson(appsCurrent2Path);
  if (appsCurrent2?.info?.outcome === "failed" && appsCurrent2?.error?.code === 4000) {
    evidence.push(`${appsCurrent2Path}: newest app-info retry timed out while establishing CoreDevice tunnel`);
  }

  const detailsRefresh1Path = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/details-2026-06-02-refresh-1.json`;
  const detailsRefresh1 = readOptionalJson(detailsRefresh1Path);
  const detailsRefresh1Props = detailsRefresh1?.result?.deviceProperties;
  const detailsRefresh1Connection = detailsRefresh1?.result?.connectionProperties;
  if (
    detailsRefresh1?.info?.outcome === "success"
    && detailsRefresh1Props?.name === "iPhone Kerem"
    && detailsRefresh1Props?.osVersionNumber === "26.5"
    && detailsRefresh1Connection?.tunnelState === "connected"
  ) {
    evidence.push(`${detailsRefresh1Path}: refreshed device details show iPhone Kerem iOS 26.5, developer mode enabled, tunnel connected`);
  } else if (detailsRefresh1) {
    issues.push(`${detailsRefresh1Path}: expected refreshed connected-device evidence not found`);
  }

  const appsRefresh1Path = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/apps-2026-06-02-refresh-1.json`;
  const appsRefresh1 = readOptionalJson(appsRefresh1Path);
  const appRefresh1 = appsRefresh1?.result?.apps?.find((candidate) => candidate.bundleIdentifier === BUNDLE_ID);
  if (appRefresh1?.version === VERSION && appRefresh1?.bundleVersion === BUILD_NUMBER) {
    evidence.push(`${appsRefresh1Path}: refreshed app-info confirms candidate app ${VERSION} (${BUILD_NUMBER}) installed`);
  } else if (appsRefresh1) {
    issues.push(`${appsRefresh1Path}: refreshed app-info did not find ${BUNDLE_ID} ${VERSION} (${BUILD_NUMBER})`);
  }

  const lockRefresh1Path = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/lockstate-2026-06-02-refresh-1.json`;
  const lockRefresh1 = readOptionalJson(lockRefresh1Path);
  if (lockRefresh1?.info?.outcome === "success" && lockRefresh1?.result?.passcodeRequired === true && lockRefresh1?.result?.unlockedSinceBoot === true) {
    evidence.push(`${lockRefresh1Path}: refreshed lock-state confirms passcode required and unlocked since boot`);
  } else if (lockRefresh1) {
    issues.push(`${lockRefresh1Path}: expected refreshed lock-state evidence not found`);
  }

  const launchRefresh1Path = `${PHYSICAL_SMOKE_EVIDENCE_DIR}/launch-2026-06-02-refresh-1.json`;
  const launchRefresh1 = readOptionalJson(launchRefresh1Path);
  if (launchRefresh1?.info?.outcome === "failed" && launchRefresh1?.error?.code === 4000) {
    evidence.push(`${launchRefresh1Path}: refreshed foreground launch reached CoreDevice but disconnected immediately; keep iPhone unlocked/awake before functional smoke`);
  } else if (launchRefresh1?.info?.outcome === "success") {
    evidence.push(`${launchRefresh1Path}: refreshed foreground launch succeeded`);
  } else if (launchRefresh1) {
    issues.push(`${launchRefresh1Path}: refreshed launch evidence had an unexpected outcome`);
  }

  addCheck(
    "Physical-device readiness evidence",
    issues.length === 0 ? "PASS" : "FAIL",
    "Physical device evidence should prove the candidate build is installed and that the next functional smoke run needs an unlocked iPhone.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function checkAppPrivacyPublishEvidence() {
  if (!existsSync(MANUAL_EVIDENCE_FORM)) {
    addCheck(
      "App Privacy publish evidence",
      "FAIL",
      `Missing ${MANUAL_EVIDENCE_FORM}.`,
    );
    return;
  }

  const content = readFileSync(MANUAL_EVIDENCE_FORM, "utf8");
  const row = content
    .split("\n")
    .find((line) => line.includes("| App Privacy completed/published |"));
  if (!row) {
    addCheck(
      "App Privacy publish evidence",
      "FAIL",
      "Manual evidence form should include an App Privacy completed/published row.",
      `Form: ${MANUAL_EVIDENCE_FORM}`,
    );
    return;
  }

  const fields = row.split("|").map((field) => field.trim()).filter(Boolean);
  const status = fields[2] ?? "";
  addCheck(
    "App Privacy publish evidence",
    status === "PASS" ? "PASS" : "HOLD",
    status === "PASS"
      ? "Manual evidence says ASC App Privacy is completed/published."
      : "ASC App Privacy still needs final manual publish evidence before submission.",
    row,
  );
}

function checkAppStoreScreenshotApprovalEvidence() {
  if (!existsSync(MANUAL_EVIDENCE_FORM)) {
    addCheck(
      "App Store screenshot visual approval evidence",
      "FAIL",
      `Missing ${MANUAL_EVIDENCE_FORM}.`,
    );
    return;
  }

  const content = readFileSync(MANUAL_EVIDENCE_FORM, "utf8");
  const row = content
    .split("\n")
    .find((line) => line.includes("| App Store screenshots visually approved/uploaded |"));
  if (!row) {
    addCheck(
      "App Store screenshot visual approval evidence",
      "FAIL",
      "Manual evidence form should include an App Store screenshots visually approved/uploaded row.",
      `Form: ${MANUAL_EVIDENCE_FORM}`,
    );
    return;
  }

  const fields = row.split("|").map((field) => field.trim()).filter(Boolean);
  const status = fields[2] ?? "";
  addCheck(
    "App Store screenshot visual approval evidence",
    status === "PASS" ? "PASS" : "HOLD",
    status === "PASS"
      ? "Manual evidence says the final App Store screenshot set is visually approved/uploaded."
      : "Final App Store screenshot visual approval and ASC upload still need manual evidence before submission.",
    row,
  );
}

function checkSupabaseLeakedPasswordDecisionEvidence() {
  if (!existsSync(MANUAL_EVIDENCE_FORM)) {
    addCheck(
      "Supabase leaked-password decision evidence",
      "FAIL",
      `Missing ${MANUAL_EVIDENCE_FORM}.`,
    );
    return;
  }

  const content = readFileSync(MANUAL_EVIDENCE_FORM, "utf8");
  const row = content
    .split("\n")
    .find((line) => line.includes("| Supabase leaked-password toggle decision |"));
  if (!row) {
    addCheck(
      "Supabase leaked-password decision evidence",
      "FAIL",
      "Manual evidence form should include a Supabase leaked-password toggle decision row.",
      `Form: ${MANUAL_EVIDENCE_FORM}`,
    );
    return;
  }

  const fields = row.split("|").map((field) => field.trim()).filter(Boolean);
  const status = fields[2] ?? "";
  addCheck(
    "Supabase leaked-password decision evidence",
    status === "PASS" ? "PASS" : "HOLD",
    status === "PASS"
      ? "Manual evidence says leaked-password protection is enabled or the known risk is accepted."
      : "Manual evidence must record leaked-password protection as enabled or accepted known risk for this submission path.",
    row,
  );
}

function checkReviewNotesDraft() {
  if (!existsSync(REVIEW_NOTES_DRAFT)) {
    addCheck(
      "App Store Review Notes draft exists",
      "FAIL",
      `Missing ${REVIEW_NOTES_DRAFT}.`,
    );
    return;
  }

  const content = readFileSync(REVIEW_NOTES_DRAFT, "utf8");
  const requiredSections = [
    "Reviewer login:",
    "Review mailbox:",
    "OTP validity:",
    "Physical-device demo video:",
    "External services:",
    "Regional differences:",
    "China mainland availability decision",
    "Regulated industry documentation:",
    "Subscriptions:",
    "Permissions:",
    "Legal and privacy:",
  ];
  const missingSections = requiredSections.filter((section) => !content.includes(section));
  const placeholderMatches = content.match(/<PASTE_ONLY_IN_APP_STORE_CONNECT_NOTES>|<PHYSICAL_DEVICE_DEMO_VIDEO_URL>/g) ?? [];
  const secretLikePatterns = [
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
    /AuthKey_[A-Z0-9]+\.p8/,
    /SUPABASE_[A-Z0-9_]*SERVICE_ROLE[A-Z0-9_]*/i,
    /sk-[A-Za-z0-9_-]{20,}/,
    /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/,
  ];
  const secretMatches = secretLikePatterns
    .flatMap((pattern) => content.match(pattern) ?? []);

  addCheck(
    "App Store Review Notes draft structure",
    missingSections.length === 0 ? "PASS" : "FAIL",
    "Review Notes draft should cover reviewer access, OTP, demo video, external services, regional differences, regulated-industry status, subscriptions, permissions, and legal links.",
    missingSections.length === 0 ? `Draft: ${REVIEW_NOTES_DRAFT}` : missingSections.join("\n"),
  );

  addCheck(
    "App Store Review Notes placeholder status",
    placeholderMatches.length === 0 ? "PASS" : "HOLD",
    placeholderMatches.length === 0
      ? "Review Notes draft has no ASC-only placeholder markers."
      : `Review Notes draft still has ${placeholderMatches.length} ASC-only placeholder marker(s). Replace them in App Store Connect only before submission.`,
    placeholderMatches.join("\n"),
  );

  addCheck(
    "App Store Review Notes secret hygiene",
    secretMatches.length === 0 ? "PASS" : "FAIL",
    "Review Notes draft should not contain private keys, service-role markers, API keys, JWT-like secrets, or real OTP/mailbox passwords.",
    secretMatches.join("\n"),
  );
}

function checkAuxiliaryReviewNotesChinaDecisionCoverage() {
  const missing = [];
  const evidence = [];
  const requiredMarkers = [
    "Regional differences:",
    "China mainland availability decision",
    "China-specific compliance decision",
  ];

  for (const filePath of REVIEW_NOTES_AUXILIARY_FILES) {
    if (!existsSync(filePath)) {
      missing.push(`${filePath}: missing`);
      continue;
    }
    const content = readFileSync(filePath, "utf8");
    const missingMarkers = requiredMarkers.filter((marker) => !content.includes(marker));
    if (missingMarkers.length > 0) {
      missing.push(`${filePath}: missing ${missingMarkers.join(", ")}`);
    } else {
      evidence.push(`${filePath}: regional differences include China mainland decision reminder`);
    }
  }

  addCheck(
    "Auxiliary Review Notes China decision coverage",
    missing.length === 0 ? "PASS" : "FAIL",
    "All copy/paste helper notes should remind the submitter to resolve China mainland availability before App Review submission.",
    missing.length === 0 ? evidence.join("\n") : missing.join("\n"),
  );
}

function checkSubmissionDayRunbookCoverage() {
  if (!existsSync(SUBMISSION_DAY_RUNBOOK)) {
    addCheck(
      "Submission-day runbook coverage",
      "FAIL",
      `Missing ${SUBMISSION_DAY_RUNBOOK}.`,
    );
    return;
  }

  const content = readFileSync(SUBMISSION_DAY_RUNBOOK, "utf8");
  const requiredMarkers = [
    "## 1. Confirm Candidate Build",
    "## 2. Fill App Review Information",
    "## 3. Confirm App Privacy",
    "## 4. Attach Subscriptions To Review",
    "## 5. Confirm Pricing And Storefront",
    "## 6. Decide China Mainland Availability",
    "CHN available=true",
    "CHN available=false",
    "## 7. Supabase Security Toggle",
    "Prevent use of leaked passwords",
    "## 8. Physical-Device Smoke Test",
    "## 9. Final Validation Before Tapping Add For Review",
    "## 10. Release Staging",
    "node scripts/app_review_preflight_collect.mjs",
    "node scripts/release_staging_guard.mjs",
  ];
  const missingMarkers = requiredMarkers.filter((marker) => !content.includes(marker));

  addCheck(
    "Submission-day runbook coverage",
    missingMarkers.length === 0 ? "PASS" : "FAIL",
    "Runbook should cover final build, ASC contact/privacy/subscription gates, Turkey pricing, China availability decision, Supabase leaked-password gate, physical smoke, final validation, and release staging.",
    missingMarkers.length === 0 ? `Runbook: ${SUBMISSION_DAY_RUNBOOK}` : missingMarkers.join("\n"),
  );
}

function runPublicUrlChecks() {
  const issues = [];
  const evidence = [];

  for (const url of PUBLIC_REVIEW_URLS) {
    const slug = url.replace(/^https?:\/\//, "").replace(/[^A-Za-z0-9]+/g, "-").replace(/-$/, "");
    let result;
    let output = "";
    let statusCode = 0;
    for (let attempt = 1; attempt <= 2; attempt += 1) {
      result = run(`public-url-${slug}-attempt-${attempt}`, "curl", [
        "-L",
        "-I",
        "--max-time",
        "15",
        "-o",
        "/dev/null",
        "-s",
        "-w",
        "%{http_code} %{url_effective}",
        url,
      ]);
      output = (result.stdout || result.stderr).trim();
      statusCode = Number.parseInt(output.split(/\s+/)[0] ?? "0", 10);
      if (result.status === 0 && Number.isFinite(statusCode) && statusCode >= 200 && statusCode < 400) {
        break;
      }
    }
    if (result.status !== 0 || !Number.isFinite(statusCode) || statusCode < 200 || statusCode >= 400) {
      issues.push(`${url}: ${output || `curl exited ${result.status}`}`);
    }
    evidence.push(`${url}: ${output || `curl exited ${result.status}`}`);
  }

  addCheck(
    "Public legal/support URL health",
    issues.length === 0 ? "PASS" : "FAIL",
    "Expected public website, legal pages, and Apple Standard EULA URL to return HTTP 2xx/3xx.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function runAppLegalConfigChecks() {
  const issues = [];
  const evidence = [];
  const configPath = "App/Services/RDConfig.swift";

  if (!existsSync(configPath)) {
    issues.push(`Missing ${configPath}.`);
  } else {
    const config = readFileSync(configPath, "utf8");
    for (const expected of EXPECTED_APP_WEB_URLS) {
      if (!config.includes(expected)) {
        issues.push(`RDConfig missing expected URL line: ${expected}`);
      } else {
        evidence.push(`RDConfig contains ${expected.match(/https:\/\/[^"]+/)?.[0] ?? expected}`);
      }
    }
  }

  for (const docPath of BUNDLED_LEGAL_DOCS) {
    if (!existsSync(docPath)) {
      issues.push(`Missing bundled legal document: ${docPath}`);
      continue;
    }
    const content = readFileSync(docPath, "utf8");
    if (content.trim().length < 1000) {
      issues.push(`${docPath}: unexpectedly short (${content.trim().length} chars)`);
    } else {
      evidence.push(`${docPath}: ${content.trim().length} chars`);
    }
  }

  addCheck(
    "App legal URL config and bundled docs",
    issues.length === 0 ? "PASS" : "FAIL",
    "Expected app web/legal URL config and bundled in-app legal documents to be present.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function runAiDisclosureChecks() {
  const issues = [];
  const evidence = [];

  for (const check of AI_DISCLOSURE_SOURCE_CHECKS) {
    if (!existsSync(check.path)) {
      issues.push(`Missing ${check.path}.`);
      continue;
    }
    const content = readFileSync(check.path, "utf8");
    const missing = check.patterns.filter((pattern) => !content.includes(pattern));
    if (missing.length > 0) {
      issues.push(`${check.path}: missing ${missing.map((pattern) => `"${pattern}"`).join(", ")}`);
    } else {
      evidence.push(`${check.path}: AI disclosure/professional-responsibility markers present`);
    }
  }

  addCheck(
    "AI-assisted analysis disclosure",
    issues.length === 0 ? "PASS" : "FAIL",
    "AI-assisted risk analysis should be disclosed in Review Notes and legal documents, with clear professional-responsibility limits and provider context.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function runSubscriptionPaywallDisclosureChecks() {
  const issues = [];
  const evidence = [];

  for (const check of SUBSCRIPTION_PAYWALL_SOURCE_CHECKS) {
    if (!existsSync(check.path)) {
      issues.push(`Missing ${check.path}.`);
      continue;
    }
    const content = readFileSync(check.path, "utf8");
    const missing = check.patterns.filter((pattern) => !content.includes(pattern));
    if (missing.length > 0) {
      issues.push(`${check.path}: missing ${missing.map((pattern) => `"${pattern}"`).join(", ")}`);
    } else {
      evidence.push(`${check.path}: subscription purchase/restore/legal/period/TRY-fallback markers present`);
    }
  }

  addCheck(
    "Subscription paywall disclosure",
    issues.length === 0 ? "PASS" : "FAIL",
    "Subscription paywalls should expose restore purchases, Terms/Privacy/cancel links, billing period copy, purchase/restore backend sync, and TRY fallback guards.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function runReleaseSimulationSourceGatingChecks() {
  const issues = [];
  const evidence = [];

  for (const check of RELEASE_SIMULATION_SOURCE_CHECKS) {
    if (!existsSync(check.path)) {
      issues.push(`Missing ${check.path}.`);
      continue;
    }
    const content = readFileSync(check.path, "utf8");
    const missing = check.patterns.filter((pattern) => !content.includes(pattern));
    if (missing.length > 0) {
      issues.push(`${check.path}: missing ${missing.map((pattern) => `"${pattern}"`).join(", ")}`);
    } else {
      evidence.push(`${check.path}: release/test-simulation guard markers present`);
    }
  }

  addCheck(
    "Release simulation source gating",
    issues.length === 0 ? "PASS" : "FAIL",
    "iOS simulation helpers should be DEBUG-only, Edge Function AI simulation should require explicit env flags, and the production runbook should document remote secret cleanup.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function runAccountDeletionReadinessChecks() {
  const issues = [];
  const evidence = [];

  for (const check of ACCOUNT_DELETION_SOURCE_CHECKS) {
    if (!existsSync(check.path)) {
      issues.push(`Missing ${check.path}.`);
      continue;
    }
    const content = readFileSync(check.path, "utf8");
    for (const pattern of check.patterns) {
      if (!content.includes(pattern)) {
        issues.push(`${check.path}: missing "${pattern}"`);
      }
    }
    evidence.push(`${check.path}: ${check.patterns.length} expected marker(s) present`);
  }

  addCheck(
    "Account deletion path readiness",
    issues.length === 0 ? "PASS" : "FAIL",
    "Expected in-app account deletion UI, client function invocation, and Supabase deletion functions to be present.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function runReleaseDebugGatingChecks() {
  const issues = [];
  const evidence = [];

  for (const check of RELEASE_GATING_SOURCE_CHECKS) {
    if (!existsSync(check.path)) {
      issues.push(`Missing ${check.path}.`);
      continue;
    }
    const content = readFileSync(check.path, "utf8");
    for (const pattern of check.patterns) {
      if (!content.includes(pattern)) {
        issues.push(`${check.path}: missing release/debug gate marker "${pattern.replace(/\n/g, "\\n")}"`);
      }
    }
    evidence.push(`${check.path}: ${check.patterns.length} release/debug marker(s) present`);
  }

  addCheck(
    "Release debug/test gating source markers",
    issues.length === 0 ? "PASS" : "FAIL",
    "Expected UI-test launch hooks and demo auth helpers to be gated for non-DEBUG builds.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function runReleaseStagingGuardChecks() {
  const stagedGuard = run("release-staging-guard", "node", [
    "scripts/release_staging_guard.mjs",
  ]);
  addCheck(
    "Release staging guard",
    stagedGuard.status === 0 ? "PASS" : "FAIL",
    "No forbidden files should be staged for the release commit.",
    truncate(stagedGuard.stdout || stagedGuard.stderr),
  );

  const worktreeGuard = run("release-worktree-guard", "node", [
    "scripts/release_staging_guard.mjs",
    "--worktree",
  ]);
  addCheck(
    "Release dirty worktree guard",
    worktreeGuard.status === 0 ? "PASS" : "FAIL",
    "Dirty/untracked worktree should contain no forbidden release-risk files; warnings are expected until staging is curated.",
    truncate(worktreeGuard.stdout || worktreeGuard.stderr),
  );

  const issues = [];
  const evidence = [];
  const coverageChecks = [
    {
      path: GITIGNORE_FILE,
      markers: ["output/app-review-physical-smoke/", "output/imagegen/", "QA/tmp/", "AuthKey_*.p8"],
      evidence: ".gitignore excludes local physical-smoke evidence, raw imagegen output, QA temp output, and ASC private keys",
    },
    {
      path: RELEASE_STAGING_GUARD_FILE,
      markers: ["raw physical-device smoke evidence", "output\\/app-review-physical-smoke", "raw image generation output", "output\\/imagegen", "App Store Connect private keys"],
      evidence: "release guard fails raw physical-smoke evidence, raw imagegen output, and private-key staging",
    },
  ];
  for (const check of coverageChecks) {
    if (!existsSync(check.path)) {
      issues.push(`Missing ${check.path}.`);
      continue;
    }
    const content = readFileSync(check.path, "utf8");
    const missing = check.markers.filter((marker) => !content.includes(marker));
    if (missing.length > 0) {
      issues.push(`${check.path}: missing marker(s): ${missing.join(", ")}`);
    } else {
      evidence.push(`${check.path}: ${check.evidence}`);
    }
  }

  addCheck(
    "Release local evidence hygiene guard coverage",
    issues.length === 0 ? "PASS" : "FAIL",
    "Release hygiene should keep raw physical-device smoke artifacts, raw generated image output, and private local files out of release commits.",
    issues.length === 0 ? evidence.join("\n") : issues.join("\n"),
  );
}

function runAppStoreScreenshotChecks() {
  const screenshotDir = existsSync(IPHONE_TR_FINAL_SCREENSHOT_DIR)
    ? IPHONE_TR_FINAL_SCREENSHOT_DIR
    : IPHONE_TR_SCREENSHOT_DIR;
  const usingFinalSet = screenshotDir === IPHONE_TR_FINAL_SCREENSHOT_DIR;
  const filesResult = run("app-store-screenshot-file-list", "find", [
    screenshotDir,
    "-maxdepth",
    "1",
    "-type",
    "f",
    "-name",
    "*.png",
    "-print",
  ]);

  if (filesResult.status !== 0) {
    addCheck(
      "App Store screenshot local set",
      "FAIL",
      `Could not list ${screenshotDir}.`,
      truncate(filesResult.stdout || filesResult.stderr),
    );
    return;
  }

  const files = filesResult.stdout
    .trim()
    .split("\n")
    .filter(Boolean)
    .sort();

  let slideCount = null;
  if (existsSync(SCREENSHOT_PROJECT_FILE)) {
    try {
      const project = JSON.parse(readFileSync(SCREENSHOT_PROJECT_FILE, "utf8"));
      slideCount = project.slidesByDevice?.iphone?.length ?? null;
    } catch {
      slideCount = null;
    }
  }

  const dimensions = [];
  for (const file of files) {
    const result = run(`screenshot-size-${path.basename(file)}`, "sips", [
      "-g",
      "pixelWidth",
      "-g",
      "pixelHeight",
      file,
    ]);
    const width = result.stdout.match(/pixelWidth:\s*(\d+)/)?.[1];
    const height = result.stdout.match(/pixelHeight:\s*(\d+)/)?.[1];
    dimensions.push({
      file,
      width: width ? Number(width) : null,
      height: height ? Number(height) : null,
      raw: result.stdout || result.stderr,
    });
  }

  const dimensionIssues = dimensions.filter((item) => !ACCEPTED_IPHONE_SCREENSHOT_SIZES.has(`${item.width}x${item.height}`));
  const displayClasses = new Set(
    dimensions
      .map((item) => ACCEPTED_IPHONE_SCREENSHOT_SIZES.get(`${item.width}x${item.height}`))
      .filter(Boolean),
  );
  const sizeEvidence = dimensions
    .map((item) => `${path.basename(item.file)}: ${item.width}x${item.height} (${ACCEPTED_IPHONE_SCREENSHOT_SIZES.get(`${item.width}x${item.height}`) ?? "not accepted"})`)
    .join("\n");

  addCheck(
    "App Store screenshot count",
    files.length >= 1 && files.length <= 10 && (usingFinalSet || slideCount === null || (slideCount >= 1 && slideCount <= 10)) ? "PASS" : "HOLD",
    usingFinalSet
      ? `Final iPhone TR upload candidate should contain 1-10 screenshots; found ${files.length} PNG file(s) in ${screenshotDir}. Source project still has ${slideCount ?? "unknown"} iPhone slide(s).`
      : `Local iPhone TR screenshot set should be curated to 1-10 screenshots before ASC upload; found ${files.length} PNG file(s)${slideCount === null ? "" : ` and ${slideCount} iPhone slide(s)`}.`,
    [`Directory: ${screenshotDir}`, ...files.map((file) => path.basename(file))].join("\n"),
  );

  addCheck(
    "App Store screenshot dimensions",
    dimensionIssues.length === 0 && displayClasses.has("iPhone 6.9") ? "PASS" : "HOLD",
    dimensionIssues.length > 0
      ? "One or more screenshots do not match accepted iPhone App Store screenshot sizes."
      : displayClasses.has("iPhone 6.9")
        ? "Screenshot set includes accepted current large-display iPhone dimensions."
        : "Current screenshots use accepted iPhone dimensions, but no iPhone 6.9 screenshot set is present; export a 6.9 set before submission if targeting the current large-display slot.",
    sizeEvidence,
  );

  checkAppStoreScreenshotVisualQaDocument(files);
}

function checkAppStoreScreenshotVisualQaDocument(candidateFiles) {
  if (!existsSync(SCREENSHOT_VISUAL_QA_FILE)) {
    addCheck(
      "App Store screenshot visual QA document",
      "HOLD",
      `Missing ${SCREENSHOT_VISUAL_QA_FILE}.`,
    );
    return;
  }

  const content = readFileSync(SCREENSHOT_VISUAL_QA_FILE, "utf8");
  const expectedMarkers = [
    "PASS WITH OWNER APPROVAL REQUIRED",
    "No visible email address.",
    "No visible phone number.",
    "No visible API key, token, support ID, JWT-like string, or App Store Connect/Supabase secret.",
    "No visible localhost/debug/beta/test-only label.",
    "No visible USD/fallback subscription price.",
  ];
  const missingMarkers = expectedMarkers.filter((marker) => !content.includes(marker));
  const missingFiles = candidateFiles
    .map((file) => path.basename(file))
    .filter((name) => !content.includes(`\`${name}\``));

  const status = missingMarkers.length === 0 && missingFiles.length === 0 ? "PASS" : "HOLD";
  const evidence = [
    `Document: ${SCREENSHOT_VISUAL_QA_FILE}`,
    `Candidate files referenced: ${candidateFiles.length - missingFiles.length}/${candidateFiles.length}`,
    missingMarkers.length === 0 ? "Required privacy/owner-approval markers present." : `Missing marker(s): ${missingMarkers.join("; ")}`,
    missingFiles.length === 0 ? "All candidate screenshot filenames are referenced." : `Missing screenshot reference(s): ${missingFiles.join(", ")}`,
  ].join("\n");

  addCheck(
    "App Store screenshot visual QA document",
    status,
    status === "PASS"
      ? "Codex visual QA document exists for the final screenshot set and records privacy/owner-approval observations."
      : "Codex visual QA document is missing required final-set references or privacy/owner-approval observations.",
    evidence,
  );
}

function runAscChecks() {
  if (args.skipAsc) {
    addCheck("ASC checks", "SKIP", "Skipped by --skip-asc.");
    return;
  }

  const build = run("asc-build-info", "asc", [
    "builds",
    "info",
    "--app",
    APP_ID,
    "--build-number",
    BUILD_NUMBER,
    "--platform",
    "IOS",
    "--output",
    "json",
    "--pretty",
  ]);
  addCheck(
    "ASC build valid",
    build.status === 0 && build.stdout.includes(BUILD_ID) && build.stdout.includes("\"processingState\": \"VALID\"") ? "PASS" : "FAIL",
    `Build ${BUILD_NUMBER} should be VALID and match ${BUILD_ID}.`,
    truncate(build.stdout || build.stderr),
  );

  const review = run("asc-review-status", "asc", ["review", "status", "--app", APP_ID, "--output", "markdown"]);
  addCheck(
    "ASC review intentionally not submitted",
    review.status === 0 && review.stdout.includes("NOT_SUBMITTED") && review.stdout.includes("reviewDetail") ? "HOLD" : "FAIL",
    "Expected hold until App Review contact fields are filled.",
    truncate(review.stdout || review.stderr),
  );

  const validate = run("asc-validate", "asc", [
    "validate",
    "--app",
    APP_ID,
    "--version-id",
    VERSION_ID,
    "--platform",
    "IOS",
    "--output",
    "markdown",
  ]);
  const expectedContactBlockers = containsAll(validate.stdout, [
    "contactFirstName",
    "contactLastName",
    "contactEmail",
    "contactPhone",
  ]) && validate.stdout.includes("| 6769498181 |") &&
    validate.stdout.includes("| 4      | 8") &&
    validate.stdout.includes("| 4        |") &&
    !validate.stdout.includes("build.required.missing");
  addCheck(
    "ASC validation expected contact blockers",
    expectedContactBlockers ? "HOLD" : "FAIL",
    "Only acceptable current blocking errors are the intentionally unfilled App Review contact fields.",
    truncate(validate.stdout || validate.stderr),
  );

  const subs = run("asc-validate-subscriptions", "asc", [
    "validate",
    "subscriptions",
    "--app",
    APP_ID,
    "--output",
    "markdown",
  ]);
  addCheck(
    "ASC subscription validation",
    subs.status === 0 && subs.stdout.includes("| 6769498181 | 4") && subs.stdout.includes("| 0      |") ? "PASS" : "FAIL",
    "Expected 4 subscriptions, 0 errors, warnings only.",
    truncate(subs.stdout || subs.stderr),
  );

  const turkeyPricing = run("asc-subscription-turkey-pricing", "asc", [
    "subscriptions",
    "pricing",
    "summary",
    "--app",
    APP_ID,
    "--territory",
    "Turkey",
    "--output",
    "json",
    "--pretty",
  ]);
  let turkeyPricingIssues = [];
  let turkeyPricingEvidence = turkeyPricing.stdout || turkeyPricing.stderr;
  if (turkeyPricing.status === 0) {
    try {
      const parsed = JSON.parse(turkeyPricing.stdout);
      const subscriptions = parsed.subscriptions ?? [];
      for (const [productId, expected] of EXPECTED_TURKEY_PRICES.entries()) {
        const actual = subscriptions.find((subscription) => subscription.productId === productId);
        if (!actual) {
          turkeyPricingIssues.push(`${productId}: missing from Turkey pricing summary`);
          continue;
        }
        const actualPrice = actual.currentPrice ?? {};
        if (actualPrice.amount !== expected.amount || actualPrice.currency !== expected.currency) {
          turkeyPricingIssues.push(
            `${productId}: expected ${expected.amount} ${expected.currency}, got ${actualPrice.amount ?? "n/a"} ${actualPrice.currency ?? "n/a"}`,
          );
        }
      }
      if (subscriptions.length !== EXPECTED_TURKEY_PRICES.size) {
        turkeyPricingIssues.push(`Expected ${EXPECTED_TURKEY_PRICES.size} subscriptions, found ${subscriptions.length}.`);
      }
      turkeyPricingEvidence = subscriptions
        .map((subscription) => `${subscription.productId}: ${subscription.currentPrice?.amount} ${subscription.currentPrice?.currency}`)
        .join("\n");
    } catch (error) {
      turkeyPricingIssues.push(`Could not parse Turkey pricing summary JSON: ${error.message}`);
    }
  } else {
    turkeyPricingIssues.push("Turkey pricing summary command failed.");
  }
  addCheck(
    "ASC Turkey storefront pricing",
    turkeyPricingIssues.length === 0 ? "PASS" : "FAIL",
    "Expected Plus monthly/yearly and Pro monthly/yearly Turkey storefront prices in TRY.",
    turkeyPricingIssues.length === 0 ? turkeyPricingEvidence : turkeyPricingIssues.join("\n"),
  );

  const appAvailability = run("asc-app-availability", "asc", [
    "pricing",
    "availability",
    "view",
    "--app",
    APP_ID,
    "--output",
    "json",
    "--pretty",
  ]);
  let availabilityId = APP_ID;
  let chinaAvailabilityIssues = [];
  let chinaAvailabilityEvidence = appAvailability.stdout || appAvailability.stderr;
  if (appAvailability.status === 0) {
    try {
      const parsed = JSON.parse(appAvailability.stdout);
      availabilityId = parsed.data?.id ?? APP_ID;
      chinaAvailabilityEvidence = `availableInNewTerritories=${parsed.data?.attributes?.availableInNewTerritories ?? "unknown"}\navailabilityId=${availabilityId}`;
    } catch (error) {
      chinaAvailabilityIssues.push(`Could not parse app availability JSON: ${error.message}`);
    }
  } else {
    chinaAvailabilityIssues.push("App availability command failed.");
  }

  const territoryAvailability = run("asc-app-territory-availability", "asc", [
    "pricing",
    "availability",
    "territory-availabilities",
    "--availability",
    availabilityId,
    "--paginate",
    "--output",
    "json",
    "--pretty",
  ]);
  let chinaAvailable = null;
  if (territoryAvailability.status === 0) {
    try {
      const parsed = JSON.parse(territoryAvailability.stdout);
      const rows = parsed.data ?? [];
      const china = rows.find((row) => row.relationships?.territory?.data?.id === "CHN");
      if (!china) {
        chinaAvailabilityIssues.push("CHN territory availability row missing.");
      } else {
        chinaAvailable = Boolean(china.attributes?.available);
        chinaAvailabilityEvidence = [
          chinaAvailabilityEvidence,
          `territoryCount=${rows.length}`,
          `CHN available=${chinaAvailable}`,
          `CHN row=${china.id}`,
        ].join("\n");
      }
    } catch (error) {
      chinaAvailabilityIssues.push(`Could not parse territory availability JSON: ${error.message}`);
    }
  } else {
    chinaAvailabilityIssues.push("Territory availability command failed.");
  }
  addCheck(
    "ASC China mainland availability decision",
    chinaAvailabilityIssues.length > 0 ? "FAIL" : chinaAvailable ? "HOLD" : "PASS",
    chinaAvailable
      ? "China mainland is currently available while the app metadata/legal docs describe AI-assisted analysis; exclude China mainland for first release or record a China-specific compliance decision before submission."
      : "China mainland availability should be excluded or explicitly approved for this AI-assisted app.",
    chinaAvailabilityIssues.length === 0 ? chinaAvailabilityEvidence : chinaAvailabilityIssues.join("\n"),
  );

  const metadataDir = mkdtempSync(path.join(tmpdir(), "rd-asc-metadata-"));
  const metadataPull = run("asc-metadata-pull", "asc", [
    "metadata",
    "pull",
    "--app",
    APP_ID,
    "--version",
    VERSION,
    "--dir",
    metadataDir,
  ]);
  if (metadataPull.status !== 0) {
    addCheck("ASC metadata pull", "FAIL", "Metadata pull failed.", truncate(metadataPull.stdout || metadataPull.stderr));
    return;
  }

  const appInfoPath = path.join(metadataDir, "app-info", "tr.json");
  const versionPath = path.join(metadataDir, "version", VERSION, "tr.json");
  const metadataText = [appInfoPath, versionPath]
    .filter((filePath) => existsSync(filePath))
    .map((filePath) => readFileSync(filePath, "utf8"))
    .join("\n");
  const metadataNeedle = /TODO|FIXME|PLACEHOLDER|Lorem|dummy|staging|debug|test|beta|sample|example\.com|localhost|127\.0\.0\.1|ChatGPT|GPT-4|GPT|OpenAI|Claude|Anthropic|Midjourney|DALL|Stable Diffusion/i;
  addCheck(
    "ASC metadata placeholder/brand scan",
    metadataNeedle.test(metadataText) ? "FAIL" : "PASS",
    `Pulled metadata to ${metadataDir}; no placeholder/test/localhost or AI brand stuffing terms expected.`,
    metadataNeedle.test(metadataText) ? truncate(metadataText) : `Metadata dir: ${metadataDir}`,
  );
}

function runIpaChecks() {
  const appPath = args.ipaApp;
  if (!existsSync(appPath)) {
    addCheck("Unpacked IPA app path", "WARN", `Missing ${appPath}; rerun after unpacking the IPA.`);
    return;
  }

  const riskyFiles = run("ipa-risky-file-scan", "find", [
    appPath,
    "-maxdepth",
    "4",
    "(",
    "-iname",
    "*Marketing*",
    "-o",
    "-iname",
    "*mockup*",
    "-o",
    "-iname",
    "*screenshot*",
    "-o",
    "-iname",
    "*AppStoreScreenshots*",
    "-o",
    "-iname",
    "*RiskDetectedUITests*",
    "-o",
    "-iname",
    "*QA*",
    "-o",
    "-iname",
    "*Temporary*",
    "-o",
    "-iname",
    "*.p8",
    "-o",
    "-iname",
    "*.env",
    "-o",
    "-iname",
    "*AuthKey*",
    ")",
    "-print",
  ]);
  addCheck(
    "IPA risky file scan",
    riskyFiles.status === 0 && riskyFiles.stdout.trim() === "" ? "PASS" : "FAIL",
    "No QA/screenshot/marketing/key files should ship inside the .app.",
    truncate(riskyFiles.stdout || riskyFiles.stderr),
  );

  const binaryPath = path.join(appPath, "RiskDetected");
  if (existsSync(binaryPath)) {
    const stringsResult = run("ipa-binary-marker-scan", "strings", [binaryPath]);
    const markerRegex = /demo@riskdetected\.app|plus@riskdetected\.app|free@riskdetected\.app|demo123456|plus123456|free123456|Pro demo|Plus demo|Free demo|RD_UI_TEST|AuthKey_|SERVICE_ROLE|GROQ_QA_SECRET|AI_QA_SECRET|REVENUECAT_WEBHOOK_AUTHORIZATION|APNS_PRIVATE_KEY|SUPABASE_SERVICE_ROLE|SUPABASE_SECRET|\.p8/i;
    const matches = stringsResult.stdout
      .split("\n")
      .filter((line) => markerRegex.test(line));
    addCheck(
      "IPA binary secret/test marker scan",
      matches.length === 0 ? "PASS" : "FAIL",
      "No demo credentials, UI-test flags, secret names, or key markers should appear in the shipped binary.",
      matches.join("\n"),
    );

    const trackingRegex = /ATTracking|AppTrackingTransparency|NSUserTrackingUsageDescription|ASIdentifierManager|advertisingIdentifier|AdSupport|GADApplicationIdentifier|FacebookAppID|SKAdNetwork/i;
    const trackingMatches = stringsResult.stdout
      .split("\n")
      .filter((line) => trackingRegex.test(line));
    addCheck(
      "IPA binary tracking marker scan",
      trackingMatches.length === 0 ? "PASS" : "WARN",
      "No ATT/ad identifier markers expected. RevenueCat attribution support strings are reviewed separately in the main report.",
      trackingMatches.slice(0, 30).join("\n"),
    );
  } else {
    addCheck("IPA binary exists", "FAIL", `Missing ${binaryPath}.`);
  }

  const privacyFiles = run("ipa-privacy-manifest-list", "find", [appPath, "-name", "PrivacyInfo.xcprivacy", "-print"]);
  const privacyPaths = privacyFiles.stdout.trim().split("\n").filter(Boolean);
  let privacyIssues = [];
  for (const privacyPath of privacyPaths) {
    const json = run(`privacy-${path.basename(path.dirname(privacyPath))}`, "plutil", [
      "-convert",
      "json",
      "-o",
      "-",
      privacyPath,
    ]);
    try {
      const parsed = JSON.parse(json.stdout);
      const tracking = parsed.NSPrivacyTracking ?? false;
      const domains = parsed.NSPrivacyTrackingDomains ?? [];
      if (tracking !== false || domains.length !== 0) {
        privacyIssues.push(`${privacyPath}: tracking=${tracking}, domains=${domains.length}`);
      }
    } catch (error) {
      privacyIssues.push(`${privacyPath}: could not parse (${error.message})`);
    }
  }
  addCheck(
    "IPA privacy manifests no tracking",
    privacyPaths.length === 12 && privacyIssues.length === 0 ? "PASS" : "FAIL",
    `Expected 12 privacy manifests, all tracking=false and zero tracking domains; found ${privacyPaths.length}.`,
    privacyIssues.join("\n"),
  );

  const infoPlist = path.join(appPath, "Info.plist");
  if (existsSync(infoPlist)) {
    const info = run("ipa-info-plist", "plutil", ["-p", infoPlist]);
    const ok = containsAll(info.stdout, [
      "\"CFBundleShortVersionString\" => \"1.0\"",
      "\"CFBundleVersion\" => \"31\"",
      "\"ITSAppUsesNonExemptEncryption\" => false",
      "\"NSCameraUsageDescription\"",
      "\"NSPhotoLibraryUsageDescription\"",
    ]) && !/NSUserTrackingUsageDescription|GADApplicationIdentifier|FacebookAppID|SKAdNetworkItems/.test(info.stdout);
    addCheck(
      "IPA Info.plist release/privacy keys",
      ok ? "PASS" : "FAIL",
      "Expected 1.0 (31), non-exempt encryption=false, camera/photo strings, and no ad/tracking keys.",
      truncate(info.stdout || info.stderr),
    );
  }
}

function runSupabaseChecks() {
  if (args.skipSupabase) {
    addCheck("Supabase checks", "SKIP", "Skipped by --skip-supabase.");
    return;
  }

  const deno = run("supabase-functions-deno-check", "sh", [
    "-lc",
    "deno check $(find supabase/functions -maxdepth 2 -name index.ts | sort)",
  ]);
  addCheck(
    "Supabase Edge Functions deno check",
    deno.status === 0 ? "PASS" : "FAIL",
    "All Edge Function index.ts files should type-check.",
    truncate(deno.stdout || deno.stderr),
  );

  let functionListSource = "Supabase CLI";
  let remoteFunctions = run("supabase-functions-list", "supabase", [
    "functions",
    "list",
    "--project-ref",
    PROJECT_REF,
    "--output",
    "json",
  ]);
  if (remoteFunctions.status !== 0) {
    const fallbackFunctions = run(
      "supabase-functions-list-management-api",
      "node",
      ["scripts/analyze_readiness_check.mjs", "--functions-json"],
      {
        displayCommand:
          "node scripts/analyze_readiness_check.mjs --functions-json",
      },
    );
    if (fallbackFunctions.status === 0) {
      remoteFunctions = fallbackFunctions;
      functionListSource = "Supabase Management API fallback";
    }
  }
  const functionIssues = [];
  const functionEvidence = [`source: ${functionListSource}`];
  if (remoteFunctions.status !== 0) {
    functionIssues.push(truncate(remoteFunctions.stdout || remoteFunctions.stderr));
  } else if (!existsSync(SUPABASE_CONFIG_FILE)) {
    functionIssues.push(`Missing ${SUPABASE_CONFIG_FILE}.`);
  } else {
    try {
      const remote = JSON.parse(remoteFunctions.stdout);
      const remoteBySlug = new Map(remote.map((fn) => [fn.slug, fn]));
      const config = readFileSync(SUPABASE_CONFIG_FILE, "utf8");
      const expected = [...config.matchAll(/\[functions\.([^\]]+)\]\s+verify_jwt\s*=\s*(true|false)/g)]
        .map((match) => ({ slug: match[1], verifyJwt: match[2] === "true" }));
      for (const fn of expected) {
        const deployed = remoteBySlug.get(fn.slug);
        if (!deployed) {
          functionIssues.push(`${fn.slug}: missing from remote functions list`);
          continue;
        }
        if (deployed.status !== "ACTIVE") {
          functionIssues.push(`${fn.slug}: remote status is ${deployed.status}`);
        }
        if (deployed.verify_jwt !== fn.verifyJwt) {
          functionIssues.push(`${fn.slug}: verify_jwt remote=${deployed.verify_jwt} local=${fn.verifyJwt}`);
        }
        functionEvidence.push(`${fn.slug}: ${deployed.status}, verify_jwt=${deployed.verify_jwt}, version=${deployed.version}`);
      }
    } catch (error) {
      functionIssues.push(`Could not parse Supabase functions list JSON: ${error.message}`);
    }
  }
  addCheck(
    "Supabase deployed Edge Functions",
    functionIssues.length === 0 ? "PASS" : "FAIL",
    "Every locally configured Supabase Edge Function should be deployed, ACTIVE, and match local verify_jwt settings.",
    functionIssues.length === 0 ? functionEvidence.sort().join("\n") : functionIssues.join("\n"),
  );

  checkSupabaseLocalAuthConfig();
  checkSupabasePublicAuthSettings();

  const advisors = run("supabase-db-advisors", "sh", [
    "-lc",
    "supabase db advisors --linked --type all --level warn --fail-on none --output json | jq -r 'group_by(.name)[] | \"\\(.[0].name): \\(length)\"'",
  ]);
  addCheck(
    "Supabase advisors known warnings",
    advisors.status === 0 && advisors.stdout.includes("auth_leaked_password_protection: 1") ? "WARN" : "FAIL",
    "Known remaining warnings are accepted leaked-password risk plus profiles permissive-policy performance cleanup; they are not App Review blockers for this submission path.",
    truncate(advisors.stdout || advisors.stderr),
  );

  const secretsOutput = "Skipped by current release-preflight decision: do not access or enumerate Supabase production secrets from this collector. Source gating still verifies that test-simulation behavior is not active by default; manually confirm remote production secrets before submission if required.";
  const forbiddenSecrets = [];
  const secretsStatus = "SKIP";
  addCheck(
    "Supabase production simulation secrets",
    secretsStatus,
    "Remote Supabase secret enumeration is intentionally skipped by release decision; this is no longer counted as an App Review preflight blocker.",
    truncate(secretsOutput),
  );

  const lint = run("supabase-db-lint", "supabase", [
    "db",
    "lint",
    "--linked",
    "--level",
    "warning",
    "--fail-on",
    "none",
  ]);
  addCheck(
    "Supabase db lint final rerun",
    lint.status === 0 ? "PASS" : "FAIL",
    "Linked DB lint should complete through the linked Supabase CLI profile.",
    truncate(lint.stdout || lint.stderr),
  );
}

function checkSupabaseLocalAuthConfig() {
  if (!existsSync(SUPABASE_CONFIG_FILE)) {
    addCheck("Supabase local Auth config baseline", "FAIL", `Missing ${SUPABASE_CONFIG_FILE}.`);
    return;
  }

  const config = readFileSync(SUPABASE_CONFIG_FILE, "utf8");
  const required = [
    'site_url = "http://localhost:3000"',
    'additional_redirect_urls = ["io.supabase.riskdetected://login-callback"]',
    "enable_confirmations = true",
    'max_frequency = "1m0s"',
    "[auth.external.apple]\nenabled = true",
    'client_id = "com.riskdetected.app.service,com.riskdetected.app"',
    "[auth.external.google]\nenabled = true",
  ];
  const forbidden = [
    'additional_redirect_urls = ["https://127.0.0.1:3000"]',
    'site_url = "http://127.0.0.1:3000"',
    "enable_confirmations = false",
    'max_frequency = "1s"',
    "[auth.external.apple]\nenabled = false",
  ];
  const missing = required.filter((marker) => !config.includes(marker));
  const presentForbidden = forbidden.filter((marker) => config.includes(marker));
  const issues = [
    ...missing.map((marker) => `Missing required marker: ${marker}`),
    ...presentForbidden.map((marker) => `Forbidden local Auth marker present: ${marker}`),
  ];

  addCheck(
    "Supabase local Auth config baseline",
    issues.length === 0 ? "PASS" : "FAIL",
    "Local config should preserve the production Auth baseline before any config push is considered.",
    issues.length === 0
      ? [
          "iOS redirect allow-list marker present.",
          "Email confirmations enabled.",
          "Email max frequency restored to 1m0s.",
          "Apple and Google providers marked enabled without storing provider secrets.",
        ].join("\n")
      : issues.join("\n"),
  );
}

function checkSupabasePublicAuthSettings() {
  const settings = run("supabase-public-auth-settings", "sh", ["-lc", SUPABASE_PUBLIC_AUTH_SETTINGS_COMMAND]);
  if (settings.status !== 0) {
    addCheck(
      "Supabase public Auth settings baseline",
      "FAIL",
      "Public Auth settings should be readable with the app publishable key.",
      truncate(settings.stdout || settings.stderr),
    );
    return;
  }

  try {
    const parsed = JSON.parse(settings.stdout);
    const evidence = [
      `external.email=${parsed.external?.email}`,
      `external.apple=${parsed.external?.apple}`,
      `external.google=${parsed.external?.google}`,
      `external.phone=${parsed.external?.phone}`,
      `disable_signup=${parsed.disable_signup}`,
      `mailer_autoconfirm=${parsed.mailer_autoconfirm}`,
    ];
    const ok = parsed.external?.email === true
      && parsed.external?.apple === true
      && parsed.external?.google === true
      && parsed.external?.phone === false
      && parsed.disable_signup === false
      && parsed.mailer_autoconfirm === false;
    addCheck(
      "Supabase public Auth settings baseline",
      ok ? "PASS" : "FAIL",
      "Release Auth surface should expose Email, Apple, and Google; phone should remain disabled; email signups should require confirmation.",
      evidence.join("\n"),
    );
  } catch (error) {
    addCheck(
      "Supabase public Auth settings baseline",
      "FAIL",
      `Could not parse /auth/v1/settings JSON: ${error.message}`,
      truncate(settings.stdout),
    );
  }
}

function parseDevicectlAppLine(line) {
  const fields = line.trim().split(/\s{2,}/);
  if (fields.length < 4) return null;
  return {
    name: fields[0],
    bundleId: fields[1],
    version: fields[2],
    build: fields[3],
  };
}

function runPhysicalDeviceChecks() {
  if (args.skipDevices) {
    addCheck("Physical-device candidate install", "SKIP", "Skipped by --skip-devices.");
    return;
  }

  const deviceList = run("physical-device-list", "xcrun", ["devicectl", "list", "devices"]);
  if (deviceList.status !== 0) {
    addCheck(
      "Physical-device candidate install",
      "HOLD",
      "Could not list physical devices; run manually before submission.",
      truncate(deviceList.stdout || deviceList.stderr),
    );
    return;
  }

  const evidence = [];
  let reachableDeviceCount = 0;
  let candidateInstallCount = 0;
  let staleInstallCount = 0;

  for (const device of PHYSICAL_DEVICE_CANDIDATES) {
    const row = deviceList.stdout
      .split("\n")
      .find((line) => line.includes(device.id) || line.includes(device.name));
    const reachable = Boolean(row && /(available|connected)/i.test(row));
    if (reachable) reachableDeviceCount += 1;

    if (!reachable) {
      evidence.push(`${device.name} (${device.model}): not available via devicectl`);
      continue;
    }

    const apps = run(`physical-device-apps-${device.name.replaceAll(" ", "-")}`, "xcrun", [
      "devicectl",
      "device",
      "info",
      "apps",
      "--device",
      device.id,
    ]);
    if (apps.status !== 0) {
      evidence.push(`${device.name} (${device.model}): available, app list failed`);
      continue;
    }

    const installedApp = apps.stdout
      .split("\n")
      .map(parseDevicectlAppLine)
      .find((app) => app?.bundleId === BUNDLE_ID);

    if (!installedApp) {
      evidence.push(`${device.name} (${device.model}): ${BUNDLE_ID} not installed`);
      continue;
    }

    const isCandidate = installedApp.version === VERSION && installedApp.build === BUILD_NUMBER;
    if (isCandidate) {
      candidateInstallCount += 1;
      evidence.push(`${device.name} (${device.model}): candidate installed ${installedApp.version} (${installedApp.build})`);
    } else {
      staleInstallCount += 1;
      evidence.push(`${device.name} (${device.model}): installed ${installedApp.version} (${installedApp.build}), expected ${VERSION} (${BUILD_NUMBER})`);
    }
  }

  let status = "HOLD";
  let detail = `No target physical device currently has candidate ${VERSION} (${BUILD_NUMBER}) installed.`;
  if (candidateInstallCount > 0) {
    status = "PASS";
    detail = `At least one target physical device has candidate ${VERSION} (${BUILD_NUMBER}) installed.`;
  } else if (reachableDeviceCount === 0) {
    detail = "No target physical devices are currently available via devicectl.";
  } else if (staleInstallCount > 0) {
    detail = `Target physical device is reachable, but installed app is not candidate ${VERSION} (${BUILD_NUMBER}).`;
  }

  addCheck("Physical-device candidate install", status, detail, evidence.join("\n"));
}

function writeReport() {
  const outputPath = path.resolve(args.output);
  mkdirSync(path.dirname(outputPath), { recursive: true });
  const counts = statusCounts();
  const lines = [
    `# App Review Preflight Evidence - ${REPORT_DATE}`,
    "",
    `Candidate: RiskDetected ${VERSION} (${BUILD_NUMBER}) / ${BUILD_ID}`,
    "",
    "This report is generated by `scripts/app_review_preflight_collect.mjs`. It is read-only for App Store Connect and Supabase; it does not fill contact fields and does not submit the app.",
    "",
    "## Summary",
    "",
    `- PASS: ${counts.PASS ?? 0}`,
    `- WARN: ${counts.WARN ?? 0}`,
    `- HOLD: ${counts.HOLD ?? 0}`,
    `- FAIL: ${counts.FAIL ?? 0}`,
    `- SKIP: ${counts.SKIP ?? 0}`,
    "",
    "## Checks",
    "",
    "| Status | Check | Detail | Evidence |",
    "| --- | --- | --- | --- |",
    ...checks.map((check) =>
      `| ${check.status} | ${escapeTable(check.name)} | ${escapeTable(check.detail)} | ${escapeTable(check.evidence)} |`
    ),
    "",
    "## Commands",
    "",
    "| Status | Duration ms | Name | Command |",
    "| --- | ---: | --- | --- |",
    ...commands.map((command) =>
      `| ${command.status} | ${command.durationMs} | ${escapeTable(command.name)} | \`${escapeTable(command.command)}\` |`
    ),
    "",
  ];

  writeFileSync(outputPath, `${lines.join("\n")}\n`);
  console.log(`Wrote ${outputPath}`);
  const failCount = counts.FAIL ?? 0;
  if (failCount > 0) process.exit(1);
}

scanTextFilesForSecrets();
checkManualEvidenceForm();
checkPhysicalSmokeEvidence();
checkPhysicalSmokeSubgateEvidence();
checkPhysicalDeviceReadinessEvidence();
checkAppPrivacyPublishEvidence();
checkAppStoreScreenshotApprovalEvidence();
checkSupabaseLeakedPasswordDecisionEvidence();
checkReviewNotesDraft();
checkAuxiliaryReviewNotesChinaDecisionCoverage();
checkSubmissionDayRunbookCoverage();
runPublicUrlChecks();
runAppLegalConfigChecks();
runAiDisclosureChecks();
runSubscriptionPaywallDisclosureChecks();
runReleaseSimulationSourceGatingChecks();
runAccountDeletionReadinessChecks();
runReleaseDebugGatingChecks();
runReleaseStagingGuardChecks();
runAppStoreScreenshotChecks();
runAscChecks();
runIpaChecks();
runSupabaseChecks();
runPhysicalDeviceChecks();
writeReport();
