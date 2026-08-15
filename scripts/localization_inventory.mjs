#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, extname, join, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const ROOT = resolve(import.meta.dirname, "..");
const INVENTORY_PATH = join(
  ROOT,
  "localization",
  "content-inventory",
  "app-content.csv",
);
const BASELINE_PATH = join(
  ROOT,
  "localization",
  "content-inventory",
  "hardcoded-baseline.json",
);
const SUMMARY_PATH = join(
  ROOT,
  "localization",
  "content-inventory",
  "inventory-summary.json",
);
const ASC_SNAPSHOT_PATH = join(
  ROOT,
  "docs",
  "localization",
  "baseline",
  "ASC_DISCOVERY_RAW_2026-07-28.json",
);

const INVENTORY_COLUMNS = [
  "semantic_key",
  "table",
  "surface",
  "priority",
  "source_file",
  "line",
  "source_tr",
  "en_generic",
  "en_GB",
  "en_US",
  "en_AU",
  "en_CA",
  "context",
  "placeholders",
  "owner",
  "screenshot_id",
  "review_status",
  "language_review",
  "safety_review",
  "product_approval",
  "safety_review_required",
];

const SAFETY_PATTERN =
  /\b(risk|hazard|safety|health|inspection|control|corrective|mevzuat|tehlike|güvenli|güvenlik|risk|uygunsuzluk|tedbir|6331|OSHA|HSE|WHS|OHS|İSG)\b/iu;
const HUMAN_TEXT_PATTERN =
  /[çğıöşüÇĞİÖŞÜ]|(?:[A-Za-zÀ-ž][^\s"']*\s+){1,}[A-Za-zÀ-ž]/u;
const TECHNICAL_ONLY_PATTERN =
  /^(?:[a-z0-9_.:/-]+|[A-Z0-9_]+|https?:\/\/\S+|[a-f0-9-]{20,})$/;

const SWIFT_CALL_PATTERNS = [
  {
    context: "swiftui_text",
    regex:
      /\b(?:Text|Button|Label|TextField|SecureField|Picker|Toggle|Section|GroupBox|Link|Menu)\(\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "swiftui_modifier",
    regex:
      /\.(?:navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint)\(\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "custom_ui_copy",
    regex:
      /\b(?:title|subtitle|message|text|placeholder|emptyTitle|emptyMessage|buttonTitle|label|prompt|detail|formula|points|loadingTitle|fallbackTitle)\s*:\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "swift_ui_helper_copy",
    regex:
      /\b(?:field|profileField|sectionHeader|sectionLabel|sectionTitle|settingsSection)\(\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "computed_ui_copy",
    regex: /\breturn\s+"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "localized_error_description",
    regex: /\bNSLocalizedDescriptionKey\s*:\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "swift_user_copy",
    regex: /"((?:\\.|[^"\\])*)"/g,
  },
];

const GENERIC_SWIFT_COPY_FILES = new Set([
  "App/AppState.swift",
  "App/RootView.swift",
  "App/Models/AnalysisCanvas.swift",
  "App/Models/Company.swift",
  "App/Models/Finding.swift",
  "App/Models/HistoryItem.swift",
  "App/Models/OnboardingPersonalPlan.swift",
  "App/Models/RecentAnalysis.swift",
  "App/Models/UserProfile.swift",
  "App/Services/AnalysisService.swift",
  "App/Services/AppErrorMessage.swift",
  "App/Services/AppleSignInService.swift",
  "App/Services/AuthService.swift",
  "App/Services/CompanyService.swift",
  "App/Services/DeviceIntegrityService.swift",
  "App/Services/GoogleSignInService.swift",
  "App/Services/LegalDocumentService.swift",
  "App/Services/NotificationService.swift",
  "App/Services/SubscriptionManager.swift",
  "App/Services/SupportService.swift",
]);

function isGenericSwiftCopyFile(sourceFile) {
  return (
    sourceFile.startsWith("App/Views/") ||
    sourceFile.startsWith("App/Features/") ||
    GENERIC_SWIFT_COPY_FILES.has(sourceFile)
  );
}

function shouldScanGenericSwiftLine(sourceFile, line, inPreview) {
  if (!isGenericSwiftCopyFile(sourceFile) || inPreview) return false;
  if (
    /(?:logger\.|Self\.logger\.|privacy:\s*\.|assertionFailure|fatalError|preconditionFailure)/u
      .test(line)
  ) {
    return false;
  }
  if (
    /(?:\.contains|localizedCaseInsensitiveContains|range\(of:|hasPrefix|hasSuffix)\s*\(/u
      .test(line) ||
    /\bcase\s+"/u.test(line) ||
    /#"/u.test(line)
  ) {
    return false;
  }
  if (
    /(?:accessibilityIdentifier|systemName:|hex:|dateFormat|formatOptions|CodingKeys|rawValue:|URLRequest|forResource:|withExtension:|UserDefaults|AppStorage|ProcessInfo|NSLocalizedDescriptionKey|UTType|DispatchQueue\(label:)/u
      .test(line)
  ) {
    return false;
  }
  return true;
}

function maskRDLocalizationCalls(source) {
  const characters = [...source];
  const callPattern = /RDLocalization\.(?:string|format|plural)\s*\(/g;

  for (const match of source.matchAll(callPattern)) {
    const openParenthesis = source.indexOf("(", match.index);
    if (openParenthesis < 0) continue;

    let depth = 0;
    let inString = false;
    let escaped = false;
    let end = source.length;

    for (let index = openParenthesis; index < source.length; index += 1) {
      const character = source[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character === "\\") {
          escaped = true;
        } else if (character === '"') {
          inString = false;
        }
        continue;
      }

      if (character === '"') {
        inString = true;
      } else if (character === "(") {
        depth += 1;
      } else if (character === ")") {
        depth -= 1;
        if (depth === 0) {
          end = index + 1;
          break;
        }
      }
    }

    for (let index = match.index; index < end; index += 1) {
      if (characters[index] !== "\n" && characters[index] !== "\r") {
        characters[index] = " ";
      }
    }
  }

  return characters.join("");
}

function isGenericTechnicalLiteral(value, line) {
  const decoded = decodeLiteral(value);
  const staticText = decoded.replace(/\\\([^)]*\)/g, "").trim();
  if (!/[A-Za-zÇĞİÖŞÜçğıöşü]/u.test(staticText)) return true;
  if (
    /^#[0-9A-Fa-f]{3,8}$/u.test(decoded) ||
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(decoded) ||
    /^[A-Za-z]{2}_[A-Za-z0-9_]+$/u.test(decoded) ||
    /^(?:CFBundle|NS[A-Z]|UICT|RD_|RiskDetected[._]|com\.)/u.test(decoded) ||
    /^(?:TS\s+)?EN(?:\s+ISO)?\s+\d/u.test(decoded) ||
    /^[A-ZÇĞİÖŞÜ0-9]+(?:-[A-ZÇĞİÖŞÜ0-9]+)+$/u.test(decoded)
  ) {
    return true;
  }
  if (
    !/\s/u.test(staticText) &&
    !/[ÇĞİÖŞÜçğıöşü]/u.test(staticText) &&
    !/^(?:Continue|Cancel|Close|Done|Next|Back|Retry|Save|Delete|Report|Analysis|Name|Phone|Address|Wait|Saving(?:\.\.\.)?|Devam|Rapor|Analiz|Genel|Acil|Kapat|Kaydet|Bekle|Kaydediliyor(?:\.\.\.)?|Telefon|Adres|Hesap|Ayarlar|Logo|Talep|Ek|Kamera|Galeri)$/u
      .test(staticText)
  ) {
    return true;
  }
  if (
    /^[A-Za-z0-9_]+(?:,[A-Za-z0-9_!()*]+)+$/u.test(staticText) ||
    /(?:\?\?\s*$|-photo-|free_risk_analysis_trial_exhausted|report_quota_exceeded)/u
      .test(decoded) ||
    /(?:\.pdf|\.json|\.jpg|\.jpeg|\.png|\.heic|\/p\\\(|storage_path|support_id|analysis_id|user_id)/u
      .test(decoded)
  ) {
    return true;
  }
  if (
    /(?:\.select\(|\.from\(|\.eq\(|\.rpc\(|joined\(separator:|String\(format:|replacingOccurrences|Notification\.Name|OSLog|Logger\(|print\(|debugPrint\()/u
      .test(line) ||
    /(?:messageTR:|messageEN:|UI Test|UI_TEST|E2E|fixture|testMode|test mode)/iu
      .test(line)
  ) {
    return true;
  }
  if (
    /^(?:\(sahada doğrulanmalı\)|\(sahada dogrulanmali\)|\(sahada doğrulanmalıdır\)|\(sahada dogrulanmalidir\)|sahada doğrulanmalı|sahada dogrulanmali|sahada doğrulanmalıdır|sahada dogrulanmalidir)$/u
      .test(decoded)
  ) {
    return true;
  }
  return false;
}

const EXCLUDED_DIRECTORY_NAMES = new Set([
  ".git",
  ".build",
  ".swiftpm",
  "DerivedData",
  "Generated",
  "node_modules",
  "output",
  "backups",
  "Preview Content",
]);

function walk(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (EXCLUDED_DIRECTORY_NAMES.has(entry.name)) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...walk(path));
    } else if (entry.isFile()) {
      files.push(path);
    }
  }
  return files;
}

function decodeLiteral(value) {
  return value
    .replaceAll('\\"', '"')
    .replaceAll("\\n", " ")
    .replaceAll("\\t", " ")
    .trim();
}

function placeholders(value) {
  return [
    ...(value.match(/\\\([^)]*\)/g) ?? []),
    ...(value.match(/\$\{[^}]*\}/g) ?? []),
    ...(value.match(/\{\{[^}]*\}\}/g) ?? []),
    ...(value.match(/%(?:\d+\$)?[@df]/g) ?? []),
  ].join("|");
}

function slug(value) {
  const normalized = value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("en-US")
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.+|\.+$/g, "")
    .slice(0, 42);
  return normalized || "copy";
}

function tableOwnerForPath(sourceFile, context) {
  if (context === "permission_copy") {
    return { table: "permission_copy", surface: "plist", owner: "ios" };
  }
  if (
    sourceFile.startsWith("Legal/") ||
    sourceFile.startsWith("App/LegalDocuments/")
  ) {
    return { table: "legal", surface: "legal", owner: "legal" };
  }
  if (sourceFile.startsWith("App/")) {
    if (sourceFile === "App/Services/PDFReportService.swift") {
      return { table: "report", surface: "pdf", owner: "reporting" };
    }
    return { table: "app_ui", surface: "ios_ui", owner: "ios" };
  }
  if (
    sourceFile.includes("PDF") ||
    sourceFile.includes("register-report")
  ) {
    return { table: "report", surface: "pdf", owner: "reporting" };
  }
  if (sourceFile.includes("generate-excel-report")) {
    return { table: "report", surface: "xlsx", owner: "reporting" };
  }
  if (sourceFile.includes("send-welcome-email")) {
    return {
      table: "notification_email",
      surface: "email",
      owner: "lifecycle",
    };
  }
  if (
    sourceFile.includes("send-push-notification") ||
    sourceFile.includes("send-report-ready-notification") ||
    sourceFile.includes("send-trial-reminder")
  ) {
    return { table: "notification_email", surface: "push", owner: "lifecycle" };
  }
  if (
    sourceFile.includes("notification") ||
    sourceFile.includes("Notification")
  ) {
    return {
      table: "notification_email",
      surface: "notification",
      owner: "lifecycle",
    };
  }
  if (sourceFile.startsWith("supabase/functions/")) {
    return { table: "backend", surface: "backend", owner: "backend" };
  }
  return { table: "app_ui", surface: "ios_ui", owner: "ios" };
}

function priorityFor(sourceFile, surface) {
  if (
    ["plist", "legal", "pdf", "xlsx", "email", "push", "backend"].includes(
      surface,
    )
  ) {
    return "P0";
  }
  if (
    /(?:AppState|Root|Update|Error|Auth|Onboarding|Home|Analysis|Result|Report)/u
      .test(sourceFile)
  ) {
    return "P0";
  }
  return "P1";
}

function addEntry(
  entries,
  sourcePath,
  lineNumber,
  text,
  context,
  overrides = {},
) {
  const value = decodeLiteral(text);
  if (
    !value ||
    (!overrides.allowTechnical && TECHNICAL_ONLY_PATTERN.test(value))
  ) {
    return;
  }
  const sourceFile = relative(ROOT, sourcePath);
  const inferred = tableOwnerForPath(sourceFile, context);
  const table = overrides.table ?? inferred.table;
  const surface = overrides.surface ?? inferred.surface;
  const owner = overrides.owner ?? inferred.owner;
  const fingerprint = createHash("sha256")
    .update(
      `${sourceFile}\0${table}\0${surface}\0${context}\0` +
        `${surface === "ios_ui" ? `${lineNumber}\0` : ""}` +
        `${overrides.identity ?? ""}\0${value}`,
    )
    .digest("hex");
  const safetyReviewRequired = SAFETY_PATTERN.test(value);
  entries.push({
    semantic_key: `legacy.${table}.${slug(overrides.identity ?? value)}.` +
      fingerprint.slice(0, 8),
    table,
    surface,
    priority: overrides.priority ?? priorityFor(sourceFile, surface),
    source_file: sourceFile,
    line: lineNumber,
    source_tr: value,
    en_generic: "",
    en_GB: "",
    en_US: "",
    en_AU: "",
    en_CA: "",
    context,
    placeholders: placeholders(value),
    owner,
    screenshot_id: `inventory.${surface}.${fingerprint.slice(0, 12)}`,
    review_status: "extracted",
    language_review: "not_started",
    safety_review: safetyReviewRequired ? "not_started" : "not_required",
    product_approval: "not_started",
    safety_review_required: safetyReviewRequired ? "true" : "false",
    fingerprint,
  });
}

function scanSwift(path, entries) {
  const sourceFile = relative(ROOT, path);
  const source = readFileSync(path, "utf8");
  const lines = maskRDLocalizationCalls(source).split(/\r?\n/);
  let inPreview = false;
  let debugConditionalDepth = 0;
  lines.forEach((line, index) => {
    if (line.includes("#Preview")) inPreview = true;
    if (/^\s*#if\s+DEBUG\b/u.test(line)) {
      debugConditionalDepth += 1;
      return;
    }
    if (/^\s*#endif\b/u.test(line) && debugConditionalDepth > 0) {
      debugConditionalDepth -= 1;
      return;
    }
    if (debugConditionalDepth > 0) return;
    if (
      sourceFile === "App/Services/NetworkMonitor.swift" &&
      line.includes("DispatchQueue(label:")
    ) {
      return;
    }
    if (
      relative(ROOT, path) === "App/Services/AnalysisService.swift" &&
      line.includes("requestPart.isEmpty")
    ) {
      return;
    }
    const seen = new Set();
    for (const pattern of SWIFT_CALL_PATTERNS) {
      if (
        pattern.context === "swift_user_copy" &&
        !shouldScanGenericSwiftLine(sourceFile, line, inPreview)
      ) {
        continue;
      }
      pattern.regex.lastIndex = 0;
      for (const match of line.matchAll(pattern.regex)) {
        if (
          pattern.context === "swift_user_copy" &&
          isGenericTechnicalLiteral(match[1], line)
        ) {
          continue;
        }
        const quoteStart = match.index + match[0].lastIndexOf('"');
        const identity = `${quoteStart}:${match[1]}`;
        if (seen.has(identity)) continue;
        seen.add(identity);
        const staticText = match[1].replace(/\\\([^)]*\)/g, "");
        if (
          match[1].includes("\\(") &&
          !/[A-Za-zÇĞİÖŞÜçğıöşü]/u.test(staticText)
        ) {
          continue;
        }
        addEntry(entries, path, index + 1, match[1], pattern.context, {
          allowTechnical: pattern.context !== "computed_ui_copy" &&
            pattern.context !== "swift_user_copy",
          identity: `swift-literal-${quoteStart}`,
        });
      }
    }
  });
}

function scanSwiftOutput(path, entries) {
  const sourceFile = relative(ROOT, path);
  if (sourceFile !== "App/Services/PDFReportService.swift") return;
  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  lines.forEach((line, index) => {
    if (
      line.includes("RDLocalization.") ||
      line.includes("fallback:") ||
      /(?:logger\.|Self\.logger\.|privacy:\s*\.)/u.test(line)
    ) {
      return;
    }
    const regex = /"((?:\\.|[^"\\])*)"/g;
    for (const match of line.matchAll(regex)) {
      const value = decodeLiteral(match[1]);
      if (value.length >= 4 && HUMAN_TEXT_PATTERN.test(value)) {
        addEntry(entries, path, index + 1, value, "swift_output_copy");
      }
    }
  });
}

function scanPlist(path, entries) {
  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const key = lines[index].match(
      /<key>([^<]*(?:UsageDescription|DisplayName)[^<]*)<\/key>/,
    );
    if (!key) continue;
    for (
      let valueIndex = index + 1;
      valueIndex < Math.min(index + 4, lines.length);
      valueIndex += 1
    ) {
      const value = lines[valueIndex].match(/<string>([^<]+)<\/string>/);
      if (value) {
        addEntry(
          entries,
          path,
          valueIndex + 1,
          value[1],
          "permission_copy",
        );
        break;
      }
    }
  }
}

function scanMarkdown(path, entries) {
  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  lines.forEach((line, index) => {
    const value = line
      .replace(/^#{1,6}\s+/, "")
      .replace(/^[-*]\s+/, "")
      .trim();
    if (
      !value ||
      value.startsWith("```") ||
      value === "---" ||
      /^\[[^\]]+\]:/.test(value)
    ) {
      return;
    }
    if (HUMAN_TEXT_PATTERN.test(value)) {
      addEntry(entries, path, index + 1, value, "legal_copy");
    }
  });
}

function scanTypeScript(path, entries) {
  const sourceFile = relative(ROOT, path);
  if (
    sourceFile ===
      "supabase/functions/_shared/ai-localization-prompt.ts" ||
    sourceFile === "supabase/functions/_shared/user-facing-copy.ts"
  ) {
    return;
  }
  const knownOutputSurface =
    /(?:generate-excel-report|register-report|send-push-notification|send-report-ready-notification|send-trial-reminder|send-welcome-email)/u
      .test(sourceFile);
  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  let machinePromptBlock = false;
  lines.forEach((line, index) => {
    if (line.includes("localization-inventory: machine-prompt-begin")) {
      machinePromptBlock = true;
      return;
    }
    if (line.includes("localization-inventory: machine-prompt-end")) {
      machinePromptBlock = false;
      return;
    }
    if (machinePromptBlock) return;
    const regex = /(["'`])((?:\\.|(?!\1).)*)\1/g;
    for (const match of line.matchAll(regex)) {
      const value = decodeLiteral(match[2]);
      if (
        value.length >= 4 &&
        HUMAN_TEXT_PATTERN.test(value) &&
        (
          knownOutputSurface ||
          /[çğıöşüÇĞİÖŞÜ]/u.test(value) ||
          SAFETY_PATTERN.test(value)
        )
      ) {
        addEntry(entries, path, index + 1, value, "backend_user_copy");
      }
    }
  });
}

function scanASC(entries) {
  if (!existsSync(ASC_SNAPSHOT_PATH)) return;
  const snapshot = JSON.parse(readFileSync(ASC_SNAPSHOT_PATH, "utf8"));
  for (const localization of snapshot.inspected_version?.localizations ?? []) {
    for (
      const field of [
        "description",
        "keywords",
        "marketingUrl",
        "supportUrl",
        "whatsNew",
      ]
    ) {
      const value = localization.attributes?.[field];
      if (typeof value !== "string" || !value) continue;
      addEntry(
        entries,
        ASC_SNAPSHOT_PATH,
        1,
        value,
        `asc_version_${field}`,
        {
          table: "asc_metadata",
          surface: "asc_metadata",
          owner: "aso",
          priority: "P1",
          identity: `${localization.locale}.${field}`,
          allowTechnical: true,
        },
      );
    }
  }

  for (const group of snapshot.subscription_groups ?? []) {
    for (const localization of group.localizations ?? []) {
      const name = localization.attributes?.name;
      if (typeof name === "string" && name) {
        addEntry(
          entries,
          ASC_SNAPSHOT_PATH,
          1,
          name,
          "asc_subscription_group_name",
          {
            table: "asc_subscription",
            surface: "asc_subscription",
            owner: "monetization",
            priority: "P1",
            identity: `${group.id}.${localization.attributes?.locale}.name`,
          },
        );
      }
    }
    for (const subscription of group.subscriptions ?? []) {
      for (const localization of subscription.localizations ?? []) {
        for (const field of ["name", "description"]) {
          const value = localization.attributes?.[field];
          if (typeof value !== "string" || !value) continue;
          addEntry(
            entries,
            ASC_SNAPSHOT_PATH,
            1,
            value,
            `asc_subscription_${field}`,
            {
              table: "asc_subscription",
              surface: "asc_subscription",
              owner: "monetization",
              priority: "P1",
              identity:
                `${subscription.id}.${localization.attributes?.locale}.${field}`,
            },
          );
        }
      }
    }
  }
}

export function scanContent() {
  const entries = [];

  for (const path of walk(join(ROOT, "App"))) {
    if (extname(path) === ".swift") {
      if (
        relative(ROOT, path) !== "App/Services/PDFReportService.swift"
      ) {
        scanSwift(path, entries);
      }
      scanSwiftOutput(path, entries);
    }
  }

  const plistPath = join(ROOT, "Config", "RiskDetectedInfo.plist");
  if (statSync(plistPath).isFile()) scanPlist(plistPath, entries);

  for (
    const root of [join(ROOT, "Legal"), join(ROOT, "App", "LegalDocuments")]
  ) {
    for (const path of walk(root)) {
      if (extname(path) === ".md") scanMarkdown(path, entries);
    }
  }

  for (const path of walk(join(ROOT, "supabase", "functions"))) {
    if (
      extname(path) === ".ts" &&
      !path.endsWith(".generated.ts") &&
      !path.endsWith("_test.ts") &&
      !path.endsWith("_static_test.ts")
    ) {
      scanTypeScript(path, entries);
    }
  }

  scanASC(entries);

  const uniqueEntries = [
    ...new Map(entries.map((entry) => [entry.fingerprint, entry])).values(),
  ];
  uniqueEntries.sort(
    (left, right) =>
      left.source_file.localeCompare(right.source_file) ||
      left.line - right.line ||
      left.semantic_key.localeCompare(right.semantic_key),
  );
  return uniqueEntries;
}

function csvCell(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}

export function renderCSV(entries) {
  return [
    INVENTORY_COLUMNS.map(csvCell).join(","),
    ...entries.map((entry) =>
      INVENTORY_COLUMNS.map((column) => csvCell(entry[column])).join(",")
    ),
    "",
  ].join("\n");
}

export function baselineFor(entries) {
  return {
    version: 2,
    scanner: "scripts/localization_inventory.mjs",
    entry_count: entries.length,
    fingerprints: [...new Set(entries.map((entry) => entry.fingerprint))]
      .sort(),
  };
}

function countsBy(entries, field) {
  return Object.fromEntries(
    Object.entries(
      entries.reduce((counts, entry) => {
        const value = entry[field];
        counts[value] = (counts[value] ?? 0) + 1;
        return counts;
      }, {}),
    ).sort(([left], [right]) => left.localeCompare(right)),
  );
}

export function summaryFor(entries) {
  const unownedP0P1 = entries.filter(
    (entry) =>
      ["P0", "P1"].includes(entry.priority) &&
      (!entry.owner || entry.owner === "unowned"),
  );
  return {
    schema_version: 1,
    scanner: "scripts/localization_inventory.mjs",
    entry_count: entries.length,
    by_surface: countsBy(entries, "surface"),
    by_priority: countsBy(entries, "priority"),
    by_owner: countsBy(entries, "owner"),
    review_status: countsBy(entries, "review_status"),
    human_review_state: {
      language_review: countsBy(entries, "language_review"),
      safety_review: countsBy(entries, "safety_review"),
      product_approval: countsBy(entries, "product_approval"),
    },
    unowned_p0_p1_count: unownedP0P1.length,
  };
}

function validateInventory(entries) {
  const requiredFields = [
    "semantic_key",
    "table",
    "surface",
    "priority",
    "source_file",
    "line",
    "context",
    "owner",
    "screenshot_id",
    "review_status",
    "language_review",
    "safety_review",
    "product_approval",
  ];
  for (const entry of entries) {
    for (const field of requiredFields) {
      if (entry[field] === undefined || entry[field] === "") {
        throw new Error(
          `${entry.source_file}:${entry.line} is missing inventory field ${field}`,
        );
      }
    }
    if (!["P0", "P1", "P2"].includes(entry.priority)) {
      throw new Error(
        `${entry.source_file}:${entry.line} has invalid priority ${entry.priority}`,
      );
    }
    if (
      ["P0", "P1"].includes(entry.priority) &&
      (!entry.owner || entry.owner === "unowned")
    ) {
      throw new Error(
        `${entry.source_file}:${entry.line} has an unowned ${entry.priority} surface`,
      );
    }
    if (entry.review_status !== "extracted") {
      throw new Error(
        `${entry.source_file}:${entry.line} fabricated review status ${entry.review_status}`,
      );
    }
  }
}

function write(path, content) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

function main() {
  const args = new Set(process.argv.slice(2));
  const entries = scanContent();
  validateInventory(entries);
  const renderedCSV = renderCSV(entries);
  const renderedSummary = `${JSON.stringify(summaryFor(entries), null, 2)}\n`;

  if (args.has("--write") || args.has("--write-baseline")) {
    write(INVENTORY_PATH, renderedCSV);
    write(SUMMARY_PATH, renderedSummary);
  }
  if (args.has("--write-baseline")) {
    write(BASELINE_PATH, `${JSON.stringify(baselineFor(entries), null, 2)}\n`);
  }
  if (args.has("--check")) {
    for (
      const [path, expected] of [
        [INVENTORY_PATH, renderedCSV],
        [SUMMARY_PATH, renderedSummary],
      ]
    ) {
      const current = existsSync(path) ? readFileSync(path, "utf8") : "";
      if (current !== expected) {
        throw new Error(
          `${relative(ROOT, path)} is stale; run make localization-inventory`,
        );
      }
    }
  }

  const bySurface = Object.entries(countsBy(entries, "surface"))
    .map(([surface, count]) => `${surface}=${count}`)
    .join(", ");

  console.log(
    `Localization inventory: ${entries.length} entries (${bySurface}); ` +
      `unowned P0/P1=0.`,
  );
}

if (pathToFileURL(process.argv[1]).href === import.meta.url) {
  main();
}
