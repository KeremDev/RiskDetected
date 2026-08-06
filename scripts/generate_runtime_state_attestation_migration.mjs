#!/usr/bin/env node

import { readFileSync, writeFileSync } from "node:fs";
import { basename, join, relative, resolve } from "node:path";
import process from "node:process";

const ROOT = resolve(import.meta.dirname, "..");
const FEATURE_FLAG_BASELINE = join(
  ROOT,
  "docs",
  "localization",
  "baseline",
  "FEATURE_FLAGS_PRODUCTION_2026-07-28.json",
);
const PLAN_RULE_BASELINE = join(
  ROOT,
  "docs",
  "localization",
  "baseline",
  "PLAN_CAPABILITY_RULES_PRODUCTION_2026-07-28.json",
);
const OUTPUT = join(
  ROOT,
  "supabase",
  "migrations",
  "20260728202000_attest_current_runtime_configuration_state.sql",
);

const featureFlagBaseline = JSON.parse(readFileSync(FEATURE_FLAG_BASELINE, "utf8"));
const planRuleBaseline = JSON.parse(readFileSync(PLAN_RULE_BASELINE, "utf8"));

const attestedFlagKeys = new Set([
  "analysis_ambiguous_dispatch_guard",
  "analysis_pipeline_v2",
  "cancelled_plus_trial_free_routing",
  "multi_photo_analysis",
  "multi_photo_exact_coverage_schema",
]);

const flags = featureFlagBaseline.flags.filter(({ key }) => attestedFlagKeys.has(key));
if (flags.length !== attestedFlagKeys.size) {
  throw new Error("Feature-flag baseline is missing an attested key.");
}

const sqlLiteral = (value) => `'${String(value).replaceAll("'", "''")}'`;
const jsonLiteral = (value) => `${sqlLiteral(JSON.stringify(value))}::jsonb`;

const flagValues = flags
  .map(({ key, value }) => `  (${sqlLiteral(key)}, ${jsonLiteral(value)})`)
  .join(",\n");

const planValues = planRuleBaseline.rules
  .map(
    (rule) =>
      `  (${[
        sqlLiteral(rule.plan),
        rule.max_photos_per_analysis,
        rule.visible_photo_slots_in_ui,
        rule.max_findings_per_photo,
        rule.max_findings_per_analysis,
        rule.can_use_multi_photo_analysis,
        rule.can_edit_ai_findings,
        rule.can_add_manual_findings,
      ].join(", ")})`,
  )
  .join(",\n");

const output = `-- Forward-only attestation of mutable runtime configuration that existed in
-- production on 2026-07-28 but was not fully represented by migration history.
--
-- Existing unknown feature-flag keys are retained. Known keys are set to the
-- reviewed baseline. The nested multi_photo_analysis.features object is also
-- merged so future unknown feature switches are not deleted.

insert into public.app_feature_flags (key, value)
values
${flagValues}
on conflict (key) do update
set value =
  case
    when excluded.key = 'multi_photo_analysis' then
      jsonb_set(
        public.app_feature_flags.value
          || (excluded.value - 'features'),
        '{features}',
        coalesce(public.app_feature_flags.value -> 'features', '{}'::jsonb)
          || coalesce(excluded.value -> 'features', '{}'::jsonb),
        true
      )
    else public.app_feature_flags.value || excluded.value
  end;

insert into public.plan_capability_rules (
  plan,
  max_photos_per_analysis,
  visible_photo_slots_in_ui,
  max_findings_per_photo,
  max_findings_per_analysis,
  can_use_multi_photo_analysis,
  can_edit_ai_findings,
  can_add_manual_findings
)
values
${planValues}
on conflict (plan) do update
set
  max_photos_per_analysis = excluded.max_photos_per_analysis,
  visible_photo_slots_in_ui = excluded.visible_photo_slots_in_ui,
  max_findings_per_photo = excluded.max_findings_per_photo,
  max_findings_per_analysis = excluded.max_findings_per_analysis,
  can_use_multi_photo_analysis = excluded.can_use_multi_photo_analysis,
  can_edit_ai_findings = excluded.can_edit_ai_findings,
  can_add_manual_findings = excluded.can_add_manual_findings,
  updated_at = now();
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
    `Verified runtime state attestation for ${flags.length} flags and ${planRuleBaseline.rules.length} plan rules.`,
  );
} else {
  writeFileSync(OUTPUT, output);
  console.log(
    `Generated ${basename(OUTPUT)} for ${flags.length} flags and ${planRuleBaseline.rules.length} plan rules.`,
  );
}
