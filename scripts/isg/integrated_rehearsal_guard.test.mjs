import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginIntegratedRehearsalProbe,integratedRehearsalFiles} from './integrated_rehearsal_probe.mjs';

const probe=readFileSync(resolve(ROOT,integratedRehearsalFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginIntegratedRehearsalProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginIntegratedRehearsalProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the rehearsal covers every gated feature this transition added',()=>{
  const listed=[...probe.matchAll(/p_feature='([a-z_]+)'/g)].map(m=>m[1]);
  const migrations=readFileSync(resolve(ROOT,'supabase/migrations/20260914150000_isg_score_portfolio.sql'),'utf8');
  const features=[...migrations.matchAll(/'([a-z_]+)'/g)].map(m=>m[1]);
  // The newest migration carries the whole feature list in its CHECK constraint.
  const declared=features.filter(name=>listed.includes(name));
  assert.ok(listed.length>=16,`only ${listed.length} features are exercised`);
  assert.ok(declared.length>=16,'the probe drifted from the rollout feature list');
  // personnel is gated inside its own checked entry, so it is asserted on the row.
  assert.match(probe,/count\(\*\)=17 AND bool_and\(NOT read_enabled AND NOT write_enabled\) FROM private_isg\.rollout/);
});

test('the rehearsal proves the legacy product survives a full kill switch',()=>{
  assert.match(probe,/private\.user_plan_tier/);
  assert.match(probe,/private\.company_limit_for_user/);
  assert.match(probe,/legacyFingerprint\(\)===legacyBefore&&helperFingerprint\(\)===helpersBefore/);
  assert.match(probe,/the_legacy_company_rule_still_refuses_an_over_limit_write/);
});

test('the rehearsal never claims what it did not run',()=>{
  assert.match(probe,/cross_layer_user_journey_run:false/);
  assert.match(probe,/old_binary_matrix_run:false/);
  assert.match(probe,/account_deletion_run:false/);
  assert.match(probe,/restore_drill_run_here:false/);
  assert.match(probe,/production_deployed:false/);
});

test('a definer function stays the client boundary and never a gate',()=>{
  assert.match(probe,/only_the_known_client_rpc_boundary_runs_as_a_definer/);
  assert.match(probe,/!name\.endsWith\('_gate'\)/);
});

test('the runner wires the rehearsal after every phase probe',()=>{
  assert.match(runner,/beginIntegratedRehearsalProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? integratedRehearsalFiles : \[\]\)/);
  assert.match(runner,/rehearsalProbe\.afterLogout\(\)/);
  const rehearsal=runner.indexOf("stage = 'integrated-rehearsal'");
  const score=runner.indexOf("stage = 'score-portfolio'");
  const advisors=runner.indexOf('report.personnel_advisors=await probePersonnelAdvisors(');
  assert.ok(score<rehearsal&&rehearsal<advisors,'the rehearsal must run after the phases and before the advisors');
});
