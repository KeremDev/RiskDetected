#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, resolve } from "node:path";

export const ROOT = resolve(import.meta.dirname, "../..");
export const APP_CONFIG_PATH = resolve(ROOT, "appstore/app.json");
export const APP_CONFIG = readJSON(APP_CONFIG_PATH);
export const APP_ID = APP_CONFIG.app_id;
export const VERSION = APP_CONFIG.release.version;
export const BUILD_ID = APP_CONFIG.release.build_id;
export const ALL_LOCALES = [...APP_CONFIG.locales];
export const LOCALES = [...APP_CONFIG.mutable_locales];
export const PROTECTED_LOCALES = [...APP_CONFIG.protected_locales];
export const VERSION_DIR = resolve(ROOT, "appstore/versions", VERSION);
export const SCREENSHOT_ROOT = resolve(
  ROOT,
  APP_CONFIG.screenshots.final_root,
);
export const REVIEW_NOTES_PATH = resolve(
  ROOT,
  "appstore/review/app-review-notes.md",
);
export const SUBSCRIPTION_MANIFEST = readJSON(
  resolve(ROOT, APP_CONFIG.subscriptions_manifest),
);
export const SUBSCRIPTION_SOURCE = readJSON(
  resolve(ROOT, SUBSCRIPTION_MANIFEST.source),
);

const MAX_ASC_ATTEMPTS = 5;
const RETRYABLE_PATTERN =
  /\b(429|500|502|503|504|rate.?limit|temporar(?:y|ily)|timeout|timed out)\b/i;

export function readJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

export function writeJSON(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

export function localePath(locale) {
  return resolve(VERSION_DIR, `${locale}.json`);
}

export function localeConfigs() {
  return LOCALES.map((locale) => readJSON(localePath(locale)));
}

export function assertMutableLocale(locale, operation = "ASC mutation") {
  if (PROTECTED_LOCALES.includes(locale)) {
    throw new Error(
      `${operation} refused: protected locale ${locale} must remain untouched.`,
    );
  }
  if (!LOCALES.includes(locale)) {
    throw new Error(
      `${operation} refused: locale ${locale} is not in mutable_locales.`,
    );
  }
}

export function assertLocalePolicy() {
  const mutable = new Set(LOCALES);
  const protectedSet = new Set(PROTECTED_LOCALES);
  const all = new Set(ALL_LOCALES);
  const errors = [];

  if (LOCALES.length !== mutable.size) {
    errors.push("mutable_locales contains duplicates.");
  }
  if (PROTECTED_LOCALES.length !== protectedSet.size) {
    errors.push("protected_locales contains duplicates.");
  }
  for (const locale of mutable) {
    if (protectedSet.has(locale)) {
      errors.push(`${locale} cannot be both mutable and protected.`);
    }
    if (!all.has(locale)) {
      errors.push(`${locale} is mutable but absent from locales.`);
    }
  }
  for (const locale of protectedSet) {
    if (!all.has(locale)) {
      errors.push(`${locale} is protected but absent from locales.`);
    }
  }
  if (!protectedSet.has(APP_CONFIG.primary_locale)) {
    errors.push("The primary locale must be protected.");
  }
  const subscriptionLocales = SUBSCRIPTION_MANIFEST.target_locales ?? [];
  if (
    subscriptionLocales.length !== LOCALES.length ||
    subscriptionLocales.some((locale) => !mutable.has(locale)) ||
    LOCALES.some((locale) => !subscriptionLocales.includes(locale))
  ) {
    errors.push(
      "Subscription target_locales must exactly match mutable_locales.",
    );
  }
  for (const locale of PROTECTED_LOCALES) {
    const screenshotDirectory = resolve(SCREENSHOT_ROOT, locale);
    if (existsSync(screenshotDirectory)) {
      errors.push(
        `Protected screenshot output exists and must not be uploaded: ${locale}.`,
      );
    }
  }
  if (errors.length > 0) {
    throw new Error(`ASC locale policy invalid:\n- ${errors.join("\n- ")}`);
  }
}

export function rows(response) {
  if (Array.isArray(response?.data)) return response.data;
  if (response?.data) return [response.data];
  return [];
}

export function attributes(row) {
  return row?.attributes ?? {};
}

export function versionRow(response, version = VERSION) {
  return rows(response).find(
    (row) => attributes(row).versionString === version,
  );
}

function sleep(milliseconds) {
  const signal = new Int32Array(new SharedArrayBuffer(4));
  Atomics.wait(signal, 0, 0, milliseconds);
}

function redactedCommand(args) {
  const copy = [...args];
  for (let index = 0; index < copy.length; index += 1) {
    if (copy[index] === "--demo-account-password") {
      copy[index + 1] = "<redacted>";
    }
  }
  return `asc ${copy.join(" ")}`;
}

function redactSensitiveMessage(args, message) {
  let redacted = message;
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--demo-account-password" && args[index + 1]) {
      redacted = redacted.split(args[index + 1]).join("<redacted>");
    }
  }
  return redacted;
}

export function runAsc(args, options = {}) {
  const outputArgs = args.includes("--output")
    ? [...args]
    : [...args, "--output", "json"];
  let lastMessage = "";

  for (let attempt = 1; attempt <= MAX_ASC_ATTEMPTS; attempt += 1) {
    const result = spawnSync("asc", outputArgs, {
      cwd: ROOT,
      encoding: "utf8",
      env: {
        ...process.env,
        ASC_RETRY_LOG: "false",
      },
      maxBuffer: 50 * 1024 * 1024,
    });

    if (result.status === 0) {
      if (options.raw === true) return result.stdout;
      const output = result.stdout.trim();
      return output ? JSON.parse(output) : {};
    }

    lastMessage = [result.stderr, result.stdout]
      .filter(Boolean)
      .join("\n")
      .trim();
    lastMessage = redactSensitiveMessage(outputArgs, lastMessage);
    const retryable = RETRYABLE_PATTERN.test(lastMessage);
    if (!retryable || attempt === MAX_ASC_ATTEMPTS) {
      throw new Error(
        `${redactedCommand(outputArgs)} failed after ${attempt} attempt(s): ` +
          lastMessage,
      );
    }
    sleep(500 * 2 ** (attempt - 1));
  }

  throw new Error(lastMessage || "Unknown App Store Connect CLI failure.");
}

export function requireFlag(name) {
  if (process.env[name] !== "1") {
    throw new Error(`${name}=1 is required for this mutation.`);
  }
}

export function assertReleaseCannotRun() {
  if (process.env.ASC_ALLOW_RELEASE === "1") {
    throw new Error(
      "Final App Store release is owner-only and is not implemented by this automation.",
    );
  }
  if (process.env.ASC_ALLOW_REVIEW_SUBMISSION === "1") {
    throw new Error(
      "Review submission is intentionally excluded from the preparation command.",
    );
  }
}

export function metadataValidation(configs = localeConfigs()) {
  const limits = {
    name: 30,
    subtitle: 30,
    promotional_text: 170,
    description: 4000,
    keywords_bytes: 100,
    whats_new: 4000,
  };
  const errors = [];
  const warnings = [];
  const metrics = [];
  const forbiddenClaims = [
    /\b(?:100%|fully) (?:safe|accurate|compliant)\b/i,
    /\b(?:guarantee|guaranteed|guarantees) (?:safety|accuracy|compliance)\b/i,
    /\b(?:legally|regulatorily) compliant\b/i,
    /\b(?:OSHA|HSE|WHS|OHS)[ -]?(?:approved|certified|compliant)\b/i,
    /\b(?:officially|government) approved\b/i,
    /\b(?:eliminates?|prevents?) all (?:hazards|incidents|risks)\b/i,
  ];
  const marketTerms = {
    "en-GB": /\b(?:risk assessment|UK|site)\b/i,
    "en-US": /\b(?:job hazard analysis|JHA|US)\b/i,
    "en-AU": /\b(?:WHS|Australian)\b/i,
    "en-CA": /\b(?:OHS|Canadian)\b/i,
  };

  for (const config of configs) {
    const { locale, app_info: appInfo, version_info: versionInfo } = config;
    const keywordBytes = Buffer.byteLength(versionInfo.keywords, "utf8");
    const row = {
      locale,
      name: appInfo.name.length,
      subtitle: appInfo.subtitle.length,
      promotional_text: versionInfo.promotional_text.length,
      description: versionInfo.description.length,
      keywords_bytes: keywordBytes,
      whats_new: versionInfo.whats_new.length,
      screenshot_count: config.screenshots?.captions?.length ?? 0,
      screenshot_theme: config.screenshots?.source_theme ?? null,
    };
    metrics.push(row);

    for (const field of [
      "name",
      "subtitle",
      "promotional_text",
      "description",
      "whats_new",
    ]) {
      if (row[field] > limits[field]) {
        errors.push(
          `${locale}.${field} is ${row[field]}, limit is ${limits[field]}.`,
        );
      }
    }
    if (keywordBytes > limits.keywords_bytes) {
      errors.push(
        `${locale}.keywords is ${keywordBytes} bytes, limit is ` +
          `${limits.keywords_bytes}.`,
      );
    }
    if (row.screenshot_count !== APP_CONFIG.screenshots.slides_per_locale) {
      errors.push(
        `${locale} must define exactly ` +
          `${APP_CONFIG.screenshots.slides_per_locale} screenshot captions.`,
      );
    }
    if (row.screenshot_theme !== APP_CONFIG.screenshots.theme) {
      errors.push(
        `${locale} screenshot theme must be ${APP_CONFIG.screenshots.theme}.`,
      );
    }

    const searchableText = [
      appInfo.name,
      appInfo.subtitle,
      versionInfo.promotional_text,
      versionInfo.description,
      versionInfo.keywords,
      versionInfo.whats_new,
      ...(config.screenshots?.captions ?? []),
    ].join("\n");
    for (const pattern of forbiddenClaims) {
      if (pattern.test(searchableText)) {
        errors.push(`${locale} contains forbidden claim pattern ${pattern}.`);
      }
    }
    if (marketTerms[locale] && !marketTerms[locale].test(searchableText)) {
      errors.push(`${locale} is missing its market-specific terminology.`);
    }

    const titleTokens = new Set(
      `${appInfo.name} ${appInfo.subtitle}`
        .toLocaleLowerCase("en-US")
        .split(/[^a-z0-9çğıöşü×]+/u)
        .filter((token) => token.length > 2),
    );
    const duplicateKeywordTokens = versionInfo.keywords
      .toLocaleLowerCase("en-US")
      .split(",")
      .map((token) => token.trim())
      .filter((token) => titleTokens.has(token));
    if (duplicateKeywordTokens.length > 0) {
      warnings.push(
        `${locale} repeats title/subtitle token(s) in keywords: ` +
          duplicateKeywordTokens.join(", "),
      );
    }
  }

  const localeSet = new Set(configs.map((config) => config.locale));
  for (const locale of LOCALES) {
    if (!localeSet.has(locale)) errors.push(`Missing locale file: ${locale}.`);
  }

  return {
    valid: errors.length === 0,
    limits,
    metrics,
    errors,
    warnings,
  };
}

export function ensureScreenshotFiles(locale) {
  const localeDirectory = resolve(SCREENSHOT_ROOT, locale);
  const files = Array.from({ length: APP_CONFIG.screenshots.slides_per_locale })
    .map((_, index) =>
      resolve(localeDirectory, `${String(index + 1).padStart(2, "0")}.png`)
    );
  return {
    locale,
    directory: localeDirectory,
    files,
    complete: files.every((path) => existsSync(path)),
  };
}
