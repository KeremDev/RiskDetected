import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginModuleCoreProbe,moduleCoreFiles} from './module_core_probe.mjs';

const migration=readFileSync(resolve(ROOT,moduleCoreFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginModuleCoreProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginModuleCoreProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('modules ship disabled twice over and grant nothing to a client',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('modules'\)/);
  assert.match(migration,/read_enabled boolean NOT NULL DEFAULT false,\n  write_enabled boolean NOT NULL DEFAULT false/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.(rollout|module_registry) SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  assert.match(migration,/MESSAGE='MODULE_UNAVAILABLE'/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,9);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('a plan renewal is a version and planning a drill is not performing it',()=>{
  assert.match(migration,/CREATE UNIQUE INDEX emergency_plan_single_active_idx/);
  assert.match(migration,/'performed',false/);
  assert.match(migration,/CHECK\(\(state='performed'\)=\(performed_on IS NOT NULL\)\)/);
  assert.match(migration,/MESSAGE='PARTICIPANT_OUT_OF_SCOPE'/);
});

test('no single fixed period is applied to all equipment',()=>{
  assert.match(migration,/PRIMARY KEY\(company_id,equipment_type\)/);
  assert.match(migration,/period_source text NOT NULL CHECK\(period_source IN \('manufacturer','rule_version','unapproved_fixture'\)\)/);
  assert.match(migration,/exception_note/);
  assert.doesNotMatch(migration,/interval '1 year'|make_interval\(years=>1\)/);
});

test('appointments exclude overlaps and PPE refuses impossible quantities',()=>{
  assert.match(migration,/EXCLUDE USING gist\(company_id WITH =,employee_id WITH =,kind WITH =,scope_workplace_id WITH =,effective_dates WITH &&\)/);
  assert.match(migration,/MESSAGE='APPOINTMENT_OVERLAP'/);
  assert.match(migration,/quantity numeric\(12,3\) NOT NULL CHECK\(quantity>0\)/);
  assert.match(migration,/MESSAGE='RETURN_BEFORE_HANDOVER'/);
  assert.match(migration,/MESSAGE='RETURN_EXCEEDS_HANDOVER'/);
  assert.match(migration,/MESSAGE='SIGNED_COPY_REQUIRED'/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginModuleCoreProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? moduleCoreFiles : \[\]\)/);
  assert.match(runner,/moduleProbe\.afterLogout\(\)/);
});
