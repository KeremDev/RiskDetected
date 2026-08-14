#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import process from "node:process";

const root = resolve(import.meta.dirname, "..");
const port = process.env.SUPABASE_DB_PORT ?? "54322";
const files = [
  "supabase/migrations/20260728203000_global_localization_context_wave1.sql",
  "supabase/migrations/20260730213000_global_localization_delivery_wave1.sql",
  "supabase/migrations/20260731103000_global_localization_release_telemetry.sql",
  "supabase/migrations/20260801191332_sync_pipeline_v2_language_validation_telemetry.sql",
  "supabase/migrations/20260731120000_legal_acknowledgement_integrity.sql",
  "supabase/migrations/20260731121000_auth_email_delivery_idempotency.sql",
  "supabase/tests/global_localization_release_telemetry_test.sql",
];
const args = [
  "-X",
  "-v",
  "ON_ERROR_STOP=1",
  "-1",
  "-h",
  "127.0.0.1",
  "-p",
  port,
  "-U",
  "postgres",
  "-d",
  "postgres",
  ...files.flatMap((file) => ["-f", resolve(root, file)]),
];
function persistedTelemetryColumnCount() {
  return spawnSync(
    "psql",
    [
      "-X",
      "-h",
      "127.0.0.1",
      "-p",
      port,
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-Atc",
      "select count(*) from information_schema.columns where table_schema='public' and table_name='analyses' and column_name='client_build';",
    ],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        PGPASSWORD: process.env.PGPASSWORD ?? "postgres",
      },
    },
  );
}

const beforeColumnCheck = persistedTelemetryColumnCount();
const result = spawnSync("psql", args, {
  encoding: "utf8",
  env: {
    ...process.env,
    PGPASSWORD: process.env.PGPASSWORD ?? "postgres",
  },
  maxBuffer: 20 * 1024 * 1024,
});
const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
const planned = [...output.matchAll(/^\s*1\.\.(\d+)\s*$/gm)]
  .map((match) => Number(match[1]))
  .at(-1);
const afterColumnCheck = persistedTelemetryColumnCount();
const beforeColumns = Number(beforeColumnCheck.stdout?.trim() ?? "-1");
const afterColumns = Number(afterColumnCheck.stdout?.trim() ?? "-1");
const failed = result.status !== 0 ||
  /^\s*not ok\b/im.test(output) ||
  !Number.isInteger(planned) ||
  planned !== 45 ||
  beforeColumnCheck.status !== 0 ||
  afterColumnCheck.status !== 0 ||
  beforeColumns !== afterColumns;

if (failed) {
  console.error(output.trim().slice(-8_000));
  console.error(
    `Phase 6 pgTAP failed: status=${result.status}, planned=${planned}, persistent_columns_before=${beforeColumns}, persistent_columns_after=${afterColumns}.`,
  );
  process.exit(1);
}

console.log(
  `Phase 6 pgTAP passed: 45/45; migration transaction rolled back; persistent local column count unchanged (${beforeColumns}).`,
);
