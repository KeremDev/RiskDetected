#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  evaluatePhase5ExternalGates,
  validateLegalHTTPResponse,
} from "./verify_phase5_external_gates.mjs";

const repositoryRoot = resolve(import.meta.dirname, "..");
let passed = 0;

const test = async (name, body) => {
  await body();
  passed += 1;
  console.log(`ok ${passed} - ${name}`);
};

await test("all evidence passes and legal requires an explicit live check", async () => {
  const report = await evaluatePhase5ExternalGates({ live: false });
  assert.deepEqual(report.integrity_errors, []);
  assert.equal(report.status, "blocked");
  assert.deepEqual(
    report.gates.map(({ id, status }) => ({ id, status })),
    [
      { id: "LEGAL-EN", status: "blocked" },
      { id: "NOTIFICATION-COPY", status: "passed" },
      { id: "AUTH-EMAIL-HOOK", status: "passed" },
    ],
  );
  const authEmail = report.gates.find(
    (gate) => gate.id === "AUTH-EMAIL-HOOK",
  );
  assert.deepEqual(authEmail.blockers, []);
  const notification = report.gates.find(
    (gate) => gate.id === "NOTIFICATION-COPY",
  );
  assert.deepEqual(notification.blockers, []);
  const legal = report.gates.find((gate) => gate.id === "LEGAL-EN");
  assert.deepEqual(legal.blockers, [
    "LEGAL-EN: live URL verification was not executed",
  ]);
});

await test("English legal response contract accepts an actual English page", () => {
  const issues = validateLegalHTTPResponse({
    key: "terms",
    requestedURL: "https://riskdetected.com/en/terms-of-use",
    finalURL: "https://riskdetected.com/en/terms-of-use",
    status: 200,
    contentType: "text/html; charset=utf-8",
    body: `<html lang="en"><title>Terms of Use</title><body>${"RiskDetected Terms of Use ".repeat(30)}</body></html>`,
  });
  assert.deepEqual(issues, []);
});

await test("Turkish SPA fallback cannot satisfy an English legal URL", () => {
  const issues = validateLegalHTTPResponse({
    key: "privacy",
    requestedURL: "https://riskdetected.com/en/privacy-policy",
    finalURL: "https://riskdetected.com/en/privacy-policy",
    status: 200,
    contentType: "text/html; charset=utf-8",
    body: `<html lang="tr"><title>RiskDetected</title><body>${"Gizlilik Politikası ".repeat(40)}</body></html>`,
  });
  assert.ok(issues.some((issue) => issue.includes("Turkish HTML locale")));
  assert.ok(issues.some((issue) => issue.includes("Turkish legal content")));
  assert.ok(issues.some((issue) => issue.includes("English document marker")));
});

await test("release mode performs the live check and passes", () => {
  const result = spawnSync(
    process.execPath,
    ["scripts/verify_phase5_external_gates.mjs", "--mode=release"],
    {
      cwd: repositoryRoot,
      encoding: "utf8",
    },
  );
  assert.equal(result.status, 0);
  assert.match(result.stdout, /Phase 5 external gates: passed/u);
});

await test("release mode passes with exact live English documents", async () => {
  const bodies = new Map([
    [
      "https://riskdetected.com/legal-documents/en/Terms-of-Use.md",
      readFileSync(
        resolve(repositoryRoot, "App/LegalDocuments/en/Terms-of-Use.md"),
        "utf8",
      ),
    ],
    [
      "https://riskdetected.com/legal-documents/en/Privacy-Policy.md",
      readFileSync(
        resolve(repositoryRoot, "App/LegalDocuments/en/Privacy-Policy.md"),
        "utf8",
      ),
    ],
    [
      "https://riskdetected.com/legal-documents/en/AI-and-Data-Processing-Notice.md",
      readFileSync(
        resolve(
          repositoryRoot,
          "App/LegalDocuments/en/AI-and-Data-Processing-Notice.md",
        ),
        "utf8",
      ),
    ],
  ]);
  const report = await evaluatePhase5ExternalGates({
    live: true,
    fetchImplementation: async (url) => ({
      status: 200,
      url,
      headers: {
        get: (name) =>
          name.toLowerCase() === "content-type"
            ? "text/markdown; charset=utf-8"
            : null,
      },
      text: async () => bodies.get(url),
    }),
  });
  assert.deepEqual(report.integrity_errors, []);
  assert.equal(report.status, "passed");
  assert.ok(report.gates.every((gate) => gate.status === "passed"));
});

console.log(`1..${passed}`);
