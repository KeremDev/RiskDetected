import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginTrainingCoreProbe,trainingCoreFiles} from './training_core_probe.mjs';

const migration=readFileSync(resolve(ROOT,trainingCoreFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginTrainingCoreProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginTrainingCoreProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('training ships disabled, private, with no seeded legal content',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('training'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  assert.doesNotMatch(migration,/INSERT INTO private_isg\.training_(catalogs|catalog_versions|class_rules|topic_groups)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,12);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('a plan is not a completion and time is credited as a union',()=>{
  assert.match(migration,/'completes_nothing',true/);
  assert.match(migration,/max\(ends_at\) OVER \(ORDER BY starts_at,ends_at\n\s*ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING\)/);
  assert.match(migration,/MESSAGE='ATTENDANCE_OVERLAP'/);
  assert.match(migration,/required:=lessons\*rules\.lesson_minutes;/);
});

test('completion needs attendance and a passing attempt, and stays immutable',()=>{
  assert.match(migration,/IF credited<required THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ATTENDANCE_INSUFFICIENT'/);
  assert.match(migration,/MESSAGE='ASSESSMENT_NOT_PASSED'/);
  assert.match(migration,/enrolment_id uuid NOT NULL UNIQUE REFERENCES private_isg\.training_enrolments/);
  assert.match(migration,/private_isg\.next_due_on\(p_on,'years',rules\.refresh_period_years\)/);
});

test('an official catalogue needs a verified source and a special one claims nothing',()=>{
  assert.match(migration,/IF catalog\.namespace='official' THEN/);
  assert.match(migration,/IF source\.needs_review THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'/);
  assert.match(migration,/ELSIF p_content_approved THEN/);
  assert.match(migration,/content_approved boolean NOT NULL DEFAULT false/);
});

test('an external certificate is never a completion of this catalogue',()=>{
  assert.match(migration,/'is_training_completion',false/);
  assert.match(migration,/IF asset_owner IS NULL OR scan IS DISTINCT FROM 'clean' THEN/);
  assert.match(migration,/CHECK\(needs_review OR asset_id IS NOT NULL\)/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginTrainingCoreProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? trainingCoreFiles : \[\]\)/);
  assert.match(runner,/trainingProbe\.afterLogout\(\)/);
});
