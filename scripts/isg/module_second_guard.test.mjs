import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginModuleSecondProbe,moduleSecondFiles} from './module_second_probe.mjs';

const migration=readFileSync(resolve(ROOT,moduleSecondFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginModuleSecondProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginModuleSecondProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('seven more modules ship closed, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.module_registry\(module\) VALUES\n\s*\('katip_contract'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.(rollout|module_registry) SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,10);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('three claims are structurally impossible, not merely unset',()=>{
  assert.match(migration,/official_integration boolean NOT NULL DEFAULT false CHECK\(NOT official_integration\)/);
  assert.match(migration,/authorises_work boolean NOT NULL DEFAULT false CHECK\(NOT authorises_work\)/);
  assert.match(migration,/ai_text_is_official_record boolean NOT NULL DEFAULT false CHECK\(NOT ai_text_is_official_record\)/);
});

test('an open ended contract is a state and a plan year is enforced',()=>{
  assert.match(migration,/term_state text GENERATED ALWAYS AS\(CASE WHEN ends_before IS NULL THEN 'open_ended'/);
  assert.match(migration,/MESSAGE='PLAN_YEAR_MISMATCH'/);
  assert.match(migration,/MESSAGE='CARRY_OVER_INVALID'/);
  assert.match(migration,/'items_marked_performed_by_closing',0/);
});

test('a training plan is not a completion and a voluntary board stays out of the score',()=>{
  assert.match(migration,/'is_training_completion',false/);
  assert.match(migration,/CHECK\(counts_towards_legal_score=\(applicability='mandatory'\)\)/);
  assert.match(migration,/'creates_account_or_role',false/);
});

test('a site visit is company scoped and carries no health column',()=>{
  assert.match(migration,/'merged_with_personal_notes',false/);
  // No column of any table may be a health or clinical field.
  assert.doesNotMatch(migration,/^\s*\w*(health|medical|clinic|diagnos|vaccin)\w*\s+(text|jsonb|boolean|date|uuid|integer|numeric)/mi);
  assert.match(migration,/MESSAGE='SIGNED_COPY_REQUIRED'/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginModuleSecondProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? moduleSecondFiles : \[\]\)/);
  assert.match(runner,/moduleSecondProbe\.afterLogout\(\)/);
});
