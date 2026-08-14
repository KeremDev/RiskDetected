#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  baselineFor,
  scanContent,
} from "./localization_inventory.mjs";

const ROOT = resolve(import.meta.dirname, "..");
const BASELINE_PATH = resolve(
  ROOT,
  "localization/content-inventory/hardcoded-baseline.json",
);

let baseline;
try {
  baseline = JSON.parse(readFileSync(BASELINE_PATH, "utf8"));
} catch (error) {
  console.error(
    `Hard-coded localization baseline is missing or invalid: ${error.message}`,
  );
  process.exit(1);
}

const entries = scanContent();
const current = baselineFor(entries);
const allowed = new Set(baseline.fingerprints ?? []);
const additions = entries.filter((entry) => !allowed.has(entry.fingerprint));

if (additions.length > 0) {
  console.error(
    `Detected ${additions.length} new hard-coded user-facing localization candidate(s):`,
  );
  for (const entry of additions.slice(0, 20)) {
    console.error(
      `- ${entry.source_file}:${entry.line} [${entry.table}] ${entry.source_tr.slice(0, 120)}`,
    );
  }
  console.error(
    "Convert new copy to a semantic localization key; do not refresh the debt baseline for feature work.",
  );
  process.exit(1);
}

console.log(
  `Hard-coded localization guard passed: ${current.entry_count} current, ${baseline.entry_count} baseline, 0 additions.`,
);

