#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  console.error("Usage: node scripts/generate_play_data_safety_csv.mjs <export.csv> <output.csv>");
  process.exit(2);
}

function parseCsv(source) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (quoted) {
      if (character === '"' && source[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        field += character;
      }
    } else if (character === '"') {
      quoted = true;
    } else if (character === ",") {
      row.push(field);
      field = "";
    } else if (character === "\n") {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += character;
    }
  }

  if (field || row.length) {
    row.push(field.replace(/\r$/, ""));
    rows.push(row);
  }
  return rows;
}

function encodeCsvField(value) {
  const text = String(value ?? "");
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

const declarations = {
  PSL_NAME: { control: "OPTIONAL", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_PERSONALIZATION", "PSL_ACCOUNT_MANAGEMENT"] },
  PSL_EMAIL: { control: "REQUIRED", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_DEVELOPER_COMMUNICATIONS", "PSL_FRAUD_PREVENTION_SECURITY", "PSL_ACCOUNT_MANAGEMENT"] },
  PSL_USER_ACCOUNT: { control: "REQUIRED", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_FRAUD_PREVENTION_SECURITY", "PSL_ACCOUNT_MANAGEMENT"] },
  PSL_ADDRESS: { control: "OPTIONAL", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_PERSONALIZATION"] },
  PSL_PHONE: { control: "OPTIONAL", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_ACCOUNT_MANAGEMENT"] },
  PSL_OTHER_PERSONAL: { control: "OPTIONAL", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_PERSONALIZATION"] },
  PSL_PURCHASE_HISTORY: { control: "OPTIONAL", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_FRAUD_PREVENTION_SECURITY", "PSL_ACCOUNT_MANAGEMENT"] },
  PSL_PHOTOS: { control: "OPTIONAL", purposes: ["PSL_APP_FUNCTIONALITY"] },
  PSL_FILES_AND_DOCS: { control: "OPTIONAL", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_DEVELOPER_COMMUNICATIONS"] },
  PSL_CRASH_LOGS: { control: "REQUIRED", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_ANALYTICS"] },
  PSL_PERFORMANCE_DIAGNOSTICS: { control: "REQUIRED", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_ANALYTICS"] },
  PSL_USER_INTERACTION: { control: "REQUIRED", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_FRAUD_PREVENTION_SECURITY"] },
  PSL_USER_GENERATED_CONTENT: { control: "OPTIONAL", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_DEVELOPER_COMMUNICATIONS"] },
  PSL_OTHER_APP_ACTIVITY: { control: "REQUIRED", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_FRAUD_PREVENTION_SECURITY"] },
  PSL_DEVICE_ID: { control: "REQUIRED", purposes: ["PSL_APP_FUNCTIONALITY", "PSL_ANALYTICS", "PSL_FRAUD_PREVENTION_SECURITY"] },
};

const rows = parseCsv(fs.readFileSync(inputPath, "utf8"));
for (let index = 1; index < rows.length; index += 1) {
  const row = rows[index];
  const questionId = row[0] ?? "";
  const responseId = row[1] ?? "";

  if (questionId === "PSL_ACCOUNT_DELETION_URL") row[2] = "https://riskdetected.com/hesap-silme";
  if (questionId.startsWith("PSL_DATA_TYPES_")) row[2] = "";
  if (questionId.startsWith("PSL_DATA_USAGE_RESPONSES:")) row[2] = "";

  for (const [dataType, declaration] of Object.entries(declarations)) {
    if (responseId === dataType && questionId.startsWith("PSL_DATA_TYPES_")) row[2] = "true";
    if (!questionId.startsWith(`PSL_DATA_USAGE_RESPONSES:${dataType}:`)) continue;

    if (responseId === "PSL_DATA_USAGE_ONLY_COLLECTED") row[2] = "true";
    if (responseId === "PSL_DATA_USAGE_ONLY_SHARED") row[2] = "";
    if (questionId.endsWith(":PSL_DATA_USAGE_EPHEMERAL")) row[2] = "false";
    if (responseId === `PSL_DATA_USAGE_USER_CONTROL_${declaration.control}`) row[2] = "true";
    if (responseId === `PSL_DATA_USAGE_USER_CONTROL_${declaration.control === "OPTIONAL" ? "REQUIRED" : "OPTIONAL"}`) row[2] = "";
    if (questionId.endsWith(":DATA_USAGE_COLLECTION_PURPOSE")) row[2] = declaration.purposes.includes(responseId) ? "true" : "";
    if (questionId.endsWith(":DATA_USAGE_SHARING_PURPOSE")) row[2] = "";
  }
}

const output = `${rows.map((row) => row.map(encodeCsvField).join(",")).join("\r\n")}\r\n`;
fs.mkdirSync(path.dirname(path.resolve(outputPath)), { recursive: true });
fs.writeFileSync(outputPath, output);
console.log(`Wrote ${outputPath}`);
