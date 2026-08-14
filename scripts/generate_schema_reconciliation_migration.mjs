#!/usr/bin/env node

import { readFileSync, writeFileSync } from "node:fs";
import { basename, join, relative, resolve } from "node:path";
import process from "node:process";

const ROOT = resolve(import.meta.dirname, "..");
const ARCHIVE = join(
  ROOT,
  "supabase",
  "migrations_archive",
  "pre-localization-ledger-2026-07-28",
  "local-only",
);
const OUTPUT = join(
  ROOT,
  "supabase",
  "migrations",
  "20260728201500_reconcile_untracked_production_schema_state.sql",
);
const SOURCES = [
  "20260624194120_account_deletion_nullable_audit_user_refs.sql",
  "20260625052249_subscription_test_overrides.sql",
  "20260625111151_grant_authenticated_analyses_write.sql",
  "20260626183000_admin_recent_sign_ins_use_activity.sql",
  "20260626190000_admin_data_quality_multi_photo_edit.sql",
];

const sections = SOURCES.map((name) => {
  const body = readFileSync(join(ARCHIVE, name), "utf8").trim();
  return [
    `-- BEGIN attested source: ${name}`,
    body,
    `-- END attested source: ${name}`,
  ].join("\n");
});

sections.push(`-- BEGIN attested schema-only subset:
-- 20260630115105_analysis_prompt_limit_integration.sql
-- The historical DML is intentionally excluded. Production currently has
-- needs_field_verification, while current feature flag values are attested in
-- a separate forward migration.
alter table public.findings
  add column if not exists needs_field_verification boolean not null default false;
-- END attested schema-only subset`);

sections.push(`-- BEGIN production ACL attestation
-- Supabase function default privileges can grant execute to Data API roles
-- when the function is recreated. Preserve the hardened production ACL.
revoke all on function public.admin_recent_sign_ins(integer)
  from public, anon, authenticated;
grant execute on function public.admin_recent_sign_ins(integer)
  to service_role;

-- These column ACLs exist in production in addition to the later table-level
-- authenticated write grant. Keep them explicit so a reset reproduces the
-- attested production schema exactly.
grant insert (analysis_sector) on table public.analyses to authenticated;
grant insert (analysis_sector_source) on table public.analyses to authenticated;
grant insert (analysis_sector_prompt_version) on table public.analyses to authenticated;
-- END production ACL attestation`);

const output = `-- Forward-only reconciliation of schema state that exists in production but
-- was absent from the canonical remote migration history on 2026-07-28.
--
-- This migration is idempotent at the state level and contains no
-- localization change, user-content rewrite, or production-only identifier.
-- Source files remain checksum-preserved under supabase/migrations_archive.

${sections.join("\n\n")}
`;

if (process.argv.includes("--check")) {
  let current = "";
  try {
    current = readFileSync(OUTPUT, "utf8");
  } catch {
    console.error(`${relative(ROOT, OUTPUT)} is missing.`);
    process.exit(1);
  }
  if (current !== output) {
    console.error(`${relative(ROOT, OUTPUT)} is stale.`);
    process.exit(1);
  }
  console.log(
    `Verified schema reconciliation migration from ${SOURCES.length} full sources and 1 bounded subset.`,
  );
} else {
  writeFileSync(OUTPUT, output);
  console.log(
    `Generated ${basename(OUTPUT)} from ${SOURCES.length} full sources and 1 bounded subset.`,
  );
}
