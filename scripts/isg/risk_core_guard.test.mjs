import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginRiskCoreProbe,riskCoreFiles} from './risk_core_probe.mjs';

const migration=readFileSync(resolve(ROOT,riskCoreFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginRiskCoreProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginRiskCoreProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('risk versioning ships disabled, private and writes no legacy row',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('risk'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  assert.doesNotMatch(migration,/(INSERT INTO|UPDATE) public\.(analyses|findings|reports)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,5);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('only a full renewal opens a period and it runs from the assessment date',()=>{
  assert.match(migration,/IF revision\.kind='full' THEN/);
  assert.match(migration,/valid:=private_isg\.next_due_on\(revision\.assessment_on,'years',years\)/);
  assert.match(migration,/valid:=entry\.valid_until;/);
  assert.match(migration,/period_source text CHECK\(period_source IS NULL OR period_source IN \('rule_version','unapproved_fixture'\)\)/);
});

test('a rescan or correction can never move the legal date',()=>{
  assert.match(migration,/MESSAGE='ASSESSMENT_DATE_IMMUTABLE'/);
  assert.match(migration,/MESSAGE='ASSESSMENT_DATE_IN_FUTURE'/);
  assert.match(migration,/'renews_period',false/);
  assert.doesNotMatch(migration,/uploaded_at|created_at::date AS assessment_on/);
});

test('a finding is transferred by explicit selection and drift only suggests review',()=>{
  assert.match(migration,/'legacy_analysis_written',false/);
  assert.match(migration,/'action','review_suggested'/);
  assert.match(migration,/'document_unchanged',before/);
});

test('finalisation has a single winner and a stale document is stopped',()=>{
  assert.match(migration,/IF entry\.current_version<>p_expected_current THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'/);
  assert.match(migration,/CREATE FUNCTION private_isg\.assert_current_risk_version/);
  assert.match(migration,/'dispatch_allowed',true/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginRiskCoreProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? riskCoreFiles : \[\]\)/);
  assert.match(runner,/riskProbe\.afterLogout\(\)/);
});
