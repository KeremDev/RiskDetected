#!/usr/bin/env node

import { relative, resolve } from "node:path";
import { ROOT, writeJSON } from "./_shared.mjs";
import { captureProtectedState } from "./protected-state.mjs";

const outputIndex = process.argv.indexOf("--output");
const outputPath = resolve(
  outputIndex >= 0
    ? process.argv[outputIndex + 1]
    : ".asc/evidence/protected-locales-before.json",
);
const state = captureProtectedState();
writeJSON(outputPath, {
  ...state,
  captured_at: new Date().toISOString(),
  mutation_performed: false,
});
console.log(
  `Captured ${state.protected_locales.join(", ")} protected baseline at ` +
    `${relative(ROOT, outputPath)} (${state.protected_state_sha256}).`,
);
