import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginEquipmentChecksProbe,equipmentChecksFiles} from './equipment_checks_probe.mjs';

const migration=readFileSync(resolve(ROOT,equipmentChecksFiles[0]),'utf8');
const periods=readFileSync(resolve(ROOT,equipmentChecksFiles[1]),'utf8');
const probe=readFileSync(resolve(ROOT,equipmentChecksFiles[2]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');
const core=readFileSync(resolve(ROOT,'supabase/migrations/20260913230000_isg_module_core.sql'),'utf8');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginEquipmentChecksProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginEquipmentChecksProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the slice adds no switch of its own and opens none',()=>{
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.module_registry SET/);
  // It rides on the two switches P10 already created.
  assert.match(code(migration),/PERFORM private_isg\.module_gate\('equipment',p_write\);/);
  assert.match(probe,/the_phase_switch_alone_closes_the_module/);
  assert.match(probe,/the_module_switch_alone_closes_the_module/);
});

test('the new tables are private, row secured and ungranted',()=>{
  assert.match(migration,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.deepEqual(created,['equipment_type_suggestions','equipment_check_receipts']);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('only the two client entries and their wrappers are granted',()=>{
  const granted=migration.slice(migration.indexOf('GRANT EXECUTE ON FUNCTION'));
  assert.match(granted,/private_isg\.read_equipment_checks/);
  assert.match(granted,/private_isg\.mutate_equipment_checks/);
  assert.doesNotMatch(granted,/equipment_check_gate|require_equipment_company|equipment_check_row|equipment_check_status|equipment_notice_days|equipment_check_group/);
  // Nothing here is reachable by the worker identity.
  assert.doesNotMatch(migration,/TO service_role/);
});

test('every default period carries the basis it rests on',()=>{
  const table=periods.slice(periods.indexOf('CREATE TABLE private_isg.equipment_default_periods'),
    periods.indexOf('INSERT INTO private_isg.equipment_default_periods'));
  // A period with no story behind it cannot be stored at all.
  assert.match(table,/basis_note text NOT NULL CHECK\(length\(basis_note\) BETWEEN 20 AND 500\)/);
  assert.match(code(periods),/'period_defaults_offered',true/);
  assert.match(code(periods),/'period_default_source','regulation_default'/);
  assert.match(code(periods),/'period_default_needs_review',true/);
  assert.match(probe,/every_type_starts_at_a_period_and_every_default_carries_its_basis/);
});

test('a default is the product’s and is never the expert’s own determination',()=>{
  // The schema forces the flag, so no function can store an unconfirmed
  // default that looks confirmed.
  assert.match(code(periods),/CHECK\(period_source<>'regulation_default' OR needs_review\)/);
  // And the expert cannot claim that source: the P10 function takes only the
  // three they stand behind.
  assert.match(code(core),/p_source NOT IN \('manufacturer','rule_version','unapproved_fixture'\)/);
  assert.doesNotMatch(code(periods),/CREATE OR REPLACE FUNCTION private_isg\.set_equipment_inspection_rule/);
  assert.match(probe,/the_schema_refuses_an_unconfirmed_default_that_hides_its_flag/);
});

test('a type the product has no default for still gets no date',()=>{
  const ensure=periods.slice(periods.indexOf('CREATE FUNCTION private_isg.ensure_equipment_period'),
    periods.indexOf('CREATE FUNCTION private_isg.equipment_period_due'));
  assert.match(code(ensure),/IF NOT FOUND THEN RETURN; END IF;/);
  assert.match(probe,/a_type_with_no_default_still_never_invents_a_due_date/);
});

test('the next date is the period’s until the expert changes it',()=>{
  assert.match(code(periods),/WHEN chosen IS NULL OR chosen=derived THEN 'period' ELSE 'expert' END/);
  assert.match(code(periods),/ADD COLUMN due_source text CHECK\(due_source IS NULL OR due_source IN \('period','expert'\)\)/);
  // A date that cannot be true is refused rather than stored.
  assert.match(code(periods),/MESSAGE='DUE_BEFORE_REPORT'/);
  assert.match(code(periods),/MESSAGE='DUE_ON_A_FAILED_CHECK'/);
  assert.match(probe,/a_next_date_the_expert_wrote_is_recorded_as_theirs_not_as_the_periods/);
  assert.match(probe,/a_date_that_matches_the_period_is_still_the_periods_answer/);
});

test('the İSG-KATİP mark is a declaration and can never be a verification',()=>{
  // The same structural guarantee the KATİP contract table already carries.
  assert.match(code(periods),/ADD COLUMN katip_official_verification boolean NOT NULL DEFAULT false\s*\n\s*CHECK\(NOT katip_official_verification\)/);
  assert.match(code(periods),/'katip_official_verification',false/);
  // A note is only storable alongside the mark it explains.
  assert.match(code(periods),/CHECK\(katip_assignment_declared OR katip_declared_note IS NULL\)/);
  // Nothing here reaches the official system.
  assert.doesNotMatch(periods,/https?:|isgkatip|csgb\.gov/i);
  assert.match(probe,/the_katip_mark_is_the_experts_own_declaration_and_never_a_verification/);
  assert.match(probe,/no_row_can_ever_claim_the_official_system_was_checked/);
});

test('this module is not a human health check',()=>{
  const check=migration.slice(migration.indexOf('CREATE TABLE private_isg.equipment_type_suggestions'),
    migration.indexOf('ordinal integer'));
  assert.doesNotMatch(check,/health|medical|saglik|sağlık|muayene|person|employee/i);
  assert.match(code(migration),/'health_records_tracked',false/);
  assert.match(code(migration),/'health_record',false/);
});

test('the second migration opens no switch either',()=>{
  assert.doesNotMatch(periods,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(periods,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(periods,/UPDATE private_isg\.module_registry SET/);
  assert.match(periods,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
  assert.match(periods,/ALTER TABLE private_isg\.equipment_default_periods ENABLE ROW LEVEL SECURITY;/);
});

test('a due date is never invented and never quietly reads as valid',()=>{
  const status=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.equipment_check_status'),
    migration.indexOf('CREATE FUNCTION private_isg.equipment_check_group'));
  // No inspection, a failed one, or no period: each is its own answer, and
  // none of them is 'valid'.
  assert.match(code(status),/IF NOT p_has_inspection THEN RETURN 'never_inspected'; END IF;/);
  assert.match(code(status),/IF p_last_result='fail' THEN RETURN 'failed'; END IF;/);
  assert.match(code(status),/IF p_next_due IS NULL THEN RETURN 'period_unknown'; END IF;/);
  // The period itself still lives in the P10 slice, which refuses to guess one.
  assert.match(code(core),/IF FOUND AND p_result<>'fail' THEN\s*\n\s*due:=\(p_performed_on\+make_interval\(months=>rule\.period_months\)\)::date; END IF;/);
  assert.match(probe,/a_type_with_no_default_still_never_invents_a_due_date/);
  assert.match(probe,/a_failed_check_produces_no_due_date_and_says_so/);
});

test('a period never appears without where it came from',()=>{
  const row=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.equipment_check_row'),
    migration.indexOf('CREATE FUNCTION private_isg.read_equipment_checks'));
  assert.match(code(row),/'period_months',rule\.period_months,'period_source',rule\.period_source,/);
  assert.match(code(row),/'period_needs_review'/);
  // An unapproved source forces review in the P10 slice; this one cannot undo it.
  assert.match(code(core),/review:=p_source='unapproved_fixture';/);
  assert.doesNotMatch(code(migration),/needs_review\s*=\s*false/);
  assert.match(probe,/an_unapproved_period_is_flagged_for_review_and_cannot_hide_it/);
});

test('a rule added later never rewrites a report already filed',()=>{
  assert.match(code(migration),/'period_defined_after_report',rule\.equipment_type IS NOT NULL/);
  assert.match(probe,/a_rule_added_later_never_rewrites_a_report_that_was_already_filed/);
});

test('the boundary is where the ownership check lives',()=>{
  // The P10 domain functions never checked an owner, because nothing could
  // reach them. The checked entry does it before delegating.
  assert.match(code(core),/PERFORM 1 FROM public\.companies WHERE id=p_company FOR SHARE;/);
  assert.match(code(migration),/PERFORM 1 FROM public\.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;/);
  assert.match(code(migration),/WHERE equipment_id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;/);
  assert.match(probe,/another_owners_company_is_refused_on_every_action/);
  assert.match(probe,/another_owners_equipment_cannot_be_inspected_through_this_company/);
});

test('every write goes through the P10 function that owns the rule',()=>{
  const mutate=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.mutate_equipment_checks'));
  for(const delegate of ['set_equipment_inspection_rule','register_equipment','record_equipment_inspection'])
    assert.match(mutate,new RegExp(`private_isg\\.${delegate}\\(`),delegate);
  // The due date is never written here.
  assert.doesNotMatch(code(mutate),/INSERT INTO private_isg\.equipment_inspections/);
  assert.doesNotMatch(code(mutate),/next_due_on\s*=/);
});

test('no client action can name the meaning of a date or a state',()=>{
  // The live allowlist is the one the newest migration replaced the entry with.
  const allowlist=periods.slice(periods.indexOf("allowed:=CASE p_action"),periods.indexOf("ELSE NULL END;"));
  for(const action of ['set_rule','register_equipment','update_equipment','archive_equipment','record_inspection'])
    assert.match(allowlist,new RegExp(`'${action}'`),action);
  // next_due_on is the expert's to set; what it MEANS is still the server's.
  for(const forbidden of ['due_source','state','needs_review','period_needs_review','status',
    'katip_official_verification'])
    assert.doesNotMatch(allowlist,new RegExp(`'${forbidden}'`),forbidden);
});

test('a report cannot be dated in the future',()=>{
  assert.match(code(migration),/IF \(p_payload->>'performed_on'\)::date>today THEN\s*\n\s*RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERFORMED_IN_THE_FUTURE'; END IF;/);
  assert.match(probe,/a_report_dated_after_today_is_refused/);
});

test('the answer is a tally and never a compliance verdict',()=>{
  assert.match(code(migration),/'compliance_verdict',NULL/);
  assert.doesNotMatch(code(migration),/uygunluk|compliant\b/i);
  assert.match(code(migration),/'state_authority','computed_at_read'/);
});

test('the slice adds no index that duplicates one already there',()=>{
  const added=[...migration.matchAll(/CREATE INDEX ([a-z_]+) ON private_isg\.([a-z_]+)\(([^)]*)\)/g)]
    .map(m=>({name:m[1],table:m[2],columns:m[3]}));
  const existing=[...core.matchAll(/CREATE INDEX ([a-z_]+) ON private_isg\.([a-z_]+)\(([^)]*)\)/g)]
    .map(m=>`${m[2]}(${m[3]})`);
  for(const index of added)
    assert.ok(!existing.includes(`${index.table}(${index.columns})`),`${index.name} duplicates a P10 index`);
  assert.match(probe,/the_slice_adds_no_index_that_duplicates_one_already_there/);
});

test('the probe runs last and reports what it left closed',()=>{
  assert.match(runner,/stage = 'equipment-checks';/);
  assert.ok(runner.indexOf("stage = 'equipment-checks';")>runner.indexOf("stage = 'file-library';"));
  assert.ok(runner.indexOf("stage = 'equipment-checks';")<runner.indexOf("stage = 'integrated-rehearsal';"));
  assert.match(probe,/module_left_disabled:true/);
  assert.match(probe,/own_rollout_feature_added:false/);
  assert.match(probe,/period_defaults_offered:true/);
  assert.match(probe,/due_date_invented_without_a_rule:false/);
  assert.match(probe,/katip_official_verification:false/);
  assert.match(probe,/production_deployed:false/);
});
