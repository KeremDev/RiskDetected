import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginRuleCoreProbe,ruleCoreFiles} from './rule_core_probe.mjs';

const migration=readFileSync(resolve(ROOT,ruleCoreFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginRuleCoreProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginRuleCoreProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the rule engine ships disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('rule_engine'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,7);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('a source needs a checksum, a reviewer and a written note to leave review',()=>{
  assert.match(migration,/document_sha256 bytea NOT NULL CHECK\(octet_length\(document_sha256\)=32\)/);
  assert.match(migration,/CHECK\(needs_review OR \(verified_by IS NOT NULL AND evidence_note IS NOT NULL\)\)/);
  assert.match(migration,/review:=p_verified_by IS NULL OR p_evidence IS NULL;/);
});

test('publishing needs a simulation and a named human approval',()=>{
  assert.match(migration,/CHECK\(status<>'published' OR \(approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL\)\)/);
  assert.match(migration,/IF rule\.status<>'simulated' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'/);
  assert.match(migration,/IF source\.needs_review THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'/);
  assert.match(migration,/CREATE UNIQUE INDEX rule_single_published_idx/);
});

test('the expression grammar is bounded and an unknown fact stays in review',()=>{
  assert.match(migration,/NOT IN \('hazard_class','industry_code','jurisdiction','employee_count'\)/);
  assert.match(migration,/IF operator NOT IN \('in','not_in','eq','gte','lte'\)/);
  assert.match(migration,/RETURN jsonb_build_object\('state','needs_review','reason','FACT_UNKNOWN'/);
  assert.doesNotMatch(migration,/EXECUTE format|EXECUTE '/);
});

test('periods use calendar arithmetic and a Turkish rule is not applied abroad',()=>{
  assert.match(migration,/make_interval\(months=>p_length\) ELSE make_interval\(years=>p_length\)/);
  assert.doesNotMatch(migration,/interval '365 days'|interval '30 days'/);
  assert.match(migration,/JURISDICTION_MISMATCH/);
  assert.match(migration,/JURISDICTION_UNKNOWN/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginRuleCoreProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? ruleCoreFiles : \[\]\)/);
  assert.match(runner,/ruleProbe\.afterLogout\(\)/);
});
