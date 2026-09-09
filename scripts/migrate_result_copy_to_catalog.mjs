#!/usr/bin/env node

// One-shot, idempotent migration for the result-center copy(TR, EN) helper.
// Static pairs become copy(catalogKey, TR, EN) and are written to Analysis.xcstrings.

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const catalogPath = resolve(root, "App/Localization/Analysis.xcstrings");
const reportsCatalogPath = resolve(root, "App/Localization/Reports.xcstrings");
const targets = [
  {
    path: resolve(root, "App/Views/Result/AnalysisResultHubView.swift"),
    prefix: "analysis.result_hub.v2",
  },
  {
    path: resolve(root, "App/Views/Result/RiskDetailView.swift"),
    prefix: "analysis.risk.detail.v2",
  },
];

function splitArguments(source) {
  const parts = [];
  let start = 0;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    if (inString) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') inString = true;
    else if (["(", "[", "{"].includes(char)) depth += 1;
    else if ([")", "]", "}"].includes(char)) depth -= 1;
    else if (char === "," && depth === 0) {
      parts.push(source.slice(start, index).trim());
      start = index + 1;
    }
  }
  parts.push(source.slice(start).trim());
  return parts;
}

function literalValue(argument) {
  const match = argument.match(/^"((?:\\.|[^"\\])*)"$/su);
  if (!match || match[1].includes("\\(")) return null;
  try {
    return JSON.parse(argument);
  } catch {
    return null;
  }
}

function slug(value) {
  const normalized = value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/gu, ".")
    .replace(/^\.+|\.+$/gu, "")
    .slice(0, 42);
  return normalized || "copy";
}

const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
const manualEntries = {
  "analysis.result_hub.loading.title": ["Analiz sonuçları hazırlanıyor", "Preparing analysis results"],
  "analysis.result_hub.loading.message": ["Risk analizi, uzman görüşleri ve diğer sonuçlar yükleniyor.", "Loading risk analysis, expert advice, and other results."],
  "analysis.result_hub.error.title": ["Sonuçlar yüklenemedi", "Couldn't load results"],
  "analysis.result_hub.error.message": ["Bağlantını kontrol edip yeniden deneyebilirsin.", "Check your connection and try again."],
  "analysis.result_hub.error.retry": ["Tekrar dene", "Try again"],
  "analysis.result_hub.training.group.task_and_equipment": ["Görev ve ekipman", "Task and equipment"],
  "analysis.result_hub.training.group.qualification_and_authorization": ["Yeterlilik ve yetki", "Qualification"],
  "analysis.result_hub.training.group.emergency_and_rescue": ["Acil durum", "Emergency"],
  "analysis.result_hub.training.group.general_and_induction": ["Genel ve uyum", "General"],
  "analysis.result_hub.training.group.toolbox": ["Saha bilgilendirmesi", "Toolbox"],
  "analysis.result_hub.feedback.reason.incorrect_detection": ["Yanlış tespit", "Incorrect detection"],
  "analysis.result_hub.feedback.reason.missing_context": ["Eksik bağlam", "Missing context"],
  "analysis.result_hub.feedback.reason.wrong_score": ["Yanlış skor", "Incorrect score"],
  "analysis.result_hub.feedback.reason.wrong_recommendation": ["Yetersiz / yanlış önlem", "Insufficient or incorrect action"],
  "analysis.result_hub.feedback.reason.duplicate": ["Tekrar içerik", "Duplicate content"],
  "analysis.result_hub.feedback.reason.unclear_text": ["Metin anlaşılır değil", "Unclear wording"],
  "analysis.result_hub.feedback.thanks": ["Teşekkürler! Geri bildiriminizi en kısa sürede inceleyeceğiz.", "Thank you! We'll review your feedback as soon as possible."],
  "analysis.risk.detail.photo.short_label": ["Foto %1$@", "Photo %1$@"],
};
for (const [key, [tr, en]] of Object.entries(manualEntries)) {
  catalog.strings[key] ??= {
    comment: "RiskDetected 2.0 result UI copy; placeholders: none; review: release migration",
    extractionState: "manual",
    localizations: {
      en: { stringUnit: { state: "translated", value: en } },
      tr: { stringUnit: { state: "translated", value: tr } },
    },
  };
}
let migrated = 0;

for (const target of targets) {
  let source = readFileSync(target.path, "utf8");
  const replacements = [];
  const matcher = /\bcopy\s*\(/gu;
  for (const match of source.matchAll(matcher)) {
    const open = source.indexOf("(", match.index);
    let depth = 0;
    let inString = false;
    let escaped = false;
    let close = -1;
    for (let index = open; index < source.length; index += 1) {
      const char = source[index];
      if (inString) {
        if (escaped) escaped = false;
        else if (char === "\\") escaped = true;
        else if (char === '"') inString = false;
        continue;
      }
      if (char === '"') inString = true;
      else if (char === "(") depth += 1;
      else if (char === ")") {
        depth -= 1;
        if (depth === 0) {
          close = index;
          break;
        }
      }
    }
    if (close < 0) continue;
    const args = splitArguments(source.slice(open + 1, close));
    if (args.length !== 2) continue; // Already migrated or dynamic overload.
    const tr = literalValue(args[0]);
    const en = literalValue(args[1]);
    if (tr === null || en === null) continue;
    const hash = createHash("sha256")
      .update(`${target.prefix}\0${tr}\0${en}`)
      .digest("hex")
      .slice(0, 8);
    const key = `${target.prefix}.${slug(tr)}.${hash}`;
    catalog.strings[key] ??= {
      comment: "RiskDetected 2.0 result UI copy; placeholders: none; review: release migration",
      extractionState: "manual",
      localizations: {
        en: { stringUnit: { state: "translated", value: en } },
        tr: { stringUnit: { state: "translated", value: tr } },
      },
    };
    replacements.push({
      start: match.index,
      end: close + 1,
      value: `copy(${JSON.stringify(key)}, ${args[0]}, ${args[1]})`,
    });
  }
  for (const replacement of replacements.reverse()) {
    source = source.slice(0, replacement.start) + replacement.value +
      source.slice(replacement.end);
  }
  writeFileSync(target.path, source);
  migrated += replacements.length;
}

catalog.strings = Object.fromEntries(
  Object.entries(catalog.strings).sort(([left], [right]) => left.localeCompare(right)),
);
writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
const reportsCatalog = JSON.parse(readFileSync(reportsCatalogPath, "utf8"));
reportsCatalog.strings["reports.pdf.risk_table.field_verification"] ??= {
  comment: "Risk table label for an unscored field-verification item; placeholders: none; review: release migration",
  extractionState: "manual",
  localizations: {
    en: { stringUnit: { state: "translated", value: "Field verification" } },
    tr: { stringUnit: { state: "translated", value: "Saha teyidi" } },
  },
};
reportsCatalog.strings = Object.fromEntries(
  Object.entries(reportsCatalog.strings).sort(([left], [right]) => left.localeCompare(right)),
);
writeFileSync(reportsCatalogPath, `${JSON.stringify(reportsCatalog, null, 2)}\n`);
console.log(`Migrated ${migrated} static result copy pairs into Analysis.xcstrings.`);
