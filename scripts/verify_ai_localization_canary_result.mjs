#!/usr/bin/env -S deno run --allow-read

import {
  validateCanaryResultDocument,
} from "./ai_localization_canary_result_contract.mjs";
import {
  safetyProfiles,
} from "../supabase/functions/_shared/generated/safety-profiles.generated.ts";

const resultPath = Deno.args.find((argument) => !argument.startsWith("--"));
const matrixArgument = Deno.args.find((argument) =>
  argument.startsWith("--matrix=")
);
const matrix = matrixArgument?.split("=")[1] ?? "smoke";
if (!resultPath) {
  console.error(
    "Usage: verify_ai_localization_canary_result.mjs <result.json> --matrix=smoke|full",
  );
  Deno.exit(2);
}

const manifestURL = new URL(
  "../docs/localization/phase-4/canary/CANARY_CORPUS_MANIFEST_2026-07-28.json",
  import.meta.url,
);
const manifestText = await Deno.readTextFile(manifestURL);
const manifest = JSON.parse(manifestText);
const manifestDigest = await crypto.subtle.digest(
  "SHA-256",
  new TextEncoder().encode(manifestText),
);
const manifestSHA256 = Array.from(new Uint8Array(manifestDigest))
  .map((byte) => byte.toString(16).padStart(2, "0"))
  .join("");
const document = JSON.parse(await Deno.readTextFile(resultPath));
const validation = validateCanaryResultDocument({
  document,
  manifest,
  manifestSHA256,
  profiles: safetyProfiles,
  matrix,
  requireAllPassed: true,
});
console.log(JSON.stringify(validation, null, 2));
if (!validation.ok) Deno.exit(1);
