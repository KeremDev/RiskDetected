#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import process from "node:process";

function option(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1]
    ? process.argv[index + 1]
    : fallback;
}

const testsDirectory = resolve(option("--tests-dir", "supabase/tests"));
const port = option("--port", "54322");
const files = readdirSync(testsDirectory)
  .filter((name) => name.endsWith("_test.sql"))
  .sort();

let passed = 0;
let failed = 0;

for (const file of files) {
  const result = spawnSync(
    "psql",
    [
      "-X",
      "-v",
      "ON_ERROR_STOP=1",
      "-h",
      "127.0.0.1",
      "-p",
      port,
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-f",
      join(testsDirectory, file),
    ],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        PGPASSWORD: process.env.PGPASSWORD ?? "postgres",
      },
      maxBuffer: 20 * 1024 * 1024,
    },
  );
  const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  const fileFailed = result.status !== 0 || /^\s*not ok\b/im.test(output);
  const planned = [...output.matchAll(/^\s*1\.\.(\d+)\s*$/gm)]
    .map((match) => Number(match[1]))
    .at(-1);
  if (fileFailed || !Number.isInteger(planned)) {
    failed += 1;
    console.error(`not ok - ${file}`);
    console.error(output.trim().slice(-4000));
  } else {
    passed += planned;
    console.log(`ok - ${file} (${planned} assertions)`);
  }
}

if (failed > 0) {
  console.error(
    `pgTAP failed: ${failed} file(s) failed, ${passed} assertions passed.`,
  );
  process.exit(1);
}

console.log(
  `pgTAP passed: ${files.length} file(s), ${passed} assertions, 0 failures.`,
);
