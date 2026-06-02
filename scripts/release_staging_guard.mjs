#!/usr/bin/env node

import { spawnSync } from "node:child_process";

const args = new Set(process.argv.slice(2));
const scanWorktree = args.has("--worktree");

const forbiddenRules = [
  {
    name: "macOS metadata",
    pattern: /(^|\/)\.DS_Store$/,
    reason: "Do not commit local macOS metadata.",
  },
  {
    name: "env files",
    pattern: /(^|\/)(\.env|[^/]+\.env)$/,
    reason: "Do not commit local environment files.",
  },
  {
    name: "App Store Connect private keys",
    pattern: /(^|\/)(AuthKey_[A-Z0-9]+\.p8|[^/]+\.p8)$/i,
    reason: "Do not commit App Store Connect private keys.",
  },
  {
    name: "temporary QA output",
    pattern: /^QA\/tmp\//,
    reason: "Do not commit temporary QA scratch output.",
  },
  {
    name: "raw paywall device matrix",
    pattern: /^output\/paywall-device-matrix\//,
    reason: "Keep raw paywall matrix screenshots out of release commits unless explicitly archiving.",
  },
  {
    name: "raw paywall screenshots",
    pattern: /^output\/paywall-screenshots\//,
    reason: "Keep raw paywall screenshots out of release commits unless explicitly archiving.",
  },
  {
    name: "raw physical-device smoke evidence",
    pattern: /^output\/app-review-physical-smoke\//,
    reason: "Keep physical-device smoke logs and local launch artifacts out of release commits.",
  },
  {
    name: "raw image generation output",
    pattern: /^output\/imagegen\//,
    reason: "Keep raw generated image assets out of release commits; use the curated App Store screenshot candidate folder instead.",
  },
  {
    name: "temporary local exports",
    pattern: /(^|\/)(RiskDetectedExport|RiskDetectedIPA|RiskDetected-AppReview).*$/,
    reason: "Do not commit local archive/export products.",
  },
];

const warningRules = [
  {
    name: "broad output folder",
    pattern: /^output\//,
    reason: "Only final App Store marketing assets should be committed from output/.",
  },
  {
    name: "raw screenshots",
    pattern: /\.(xcresult|mov|mp4|heic)$/i,
    reason: "Large/raw QA evidence should usually stay out of release commits.",
  },
  {
    name: "marketing tooling",
    pattern: /^AppStoreScreenshots\//,
    reason: "Prefer separate marketing commit unless intentionally staging App Store screenshots.",
  },
  {
    name: "agent skill edits",
    pattern: /^\.agents\/skills\//,
    reason: "Agent skill/tooling edits should be intentional and separate from runtime release changes.",
  },
];

function runGit(args) {
  const result = spawnSync("git", args, {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.status !== 0) {
    console.error(result.stderr || result.stdout);
    process.exit(result.status ?? 1);
  }
  return result.stdout;
}

function stagedEntries() {
  const raw = runGit(["diff", "--cached", "--name-status", "-z"]);
  if (!raw) return [];
  const parts = raw.split("\0").filter(Boolean);
  const entries = [];

  for (let index = 0; index < parts.length;) {
    const status = parts[index++];
    if (/^R|^C/.test(status)) {
      const from = parts[index++];
      const to = parts[index++];
      entries.push({ status, path: from });
      entries.push({ status, path: to });
    } else {
      entries.push({ status, path: parts[index++] });
    }
  }

  return entries;
}

function worktreeEntries() {
  const raw = runGit(["status", "--porcelain", "-z", "--untracked-files=all"]);
  if (!raw) return [];
  const parts = raw.split("\0").filter(Boolean);
  const entries = [];

  for (let index = 0; index < parts.length;) {
    const token = parts[index++];
    const status = token.slice(0, 2);
    const path = token.slice(3);

    if (/^R|^C/.test(status.trim())) {
      const to = parts[index++];
      entries.push({ status, path });
      entries.push({ status, path: to });
    } else {
      entries.push({ status, path });
    }
  }

  return entries;
}

function matchRules(entries, rules) {
  const matches = [];
  for (const entry of entries) {
    for (const rule of rules) {
      if (rule.pattern.test(entry.path)) {
        matches.push({ ...entry, rule });
      }
    }
  }
  return matches;
}

const entries = scanWorktree ? worktreeEntries() : stagedEntries();
console.log(`${scanWorktree ? "Dirty worktree" : "Staged"} files checked: ${entries.length}`);

if (entries.length === 0) {
  console.log(`PASS release staging guard: nothing is ${scanWorktree ? "dirty" : "staged"}.`);
  process.exit(0);
}

const forbidden = matchRules(entries, forbiddenRules);
const warnings = matchRules(entries, warningRules);

if (warnings.length > 0) {
  console.log("\nWarnings:");
  for (const match of warnings) {
    console.log(`WARN ${match.path} [${match.rule.name}] ${match.rule.reason}`);
  }
}

if (forbidden.length > 0) {
  console.error("\nForbidden staged files:");
  for (const match of forbidden) {
    console.error(`FAIL ${match.path} [${match.rule.name}] ${match.rule.reason}`);
  }
  process.exit(1);
}

console.log(`PASS release staging guard: no forbidden ${scanWorktree ? "dirty" : "staged"} files.`);
