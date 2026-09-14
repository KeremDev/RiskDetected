import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginNonconformityDetailProbe,nonconformityDetailFiles} from './nonconformity_detail_probe.mjs';

const migration=readFileSync(resolve(ROOT,nonconformityDetailFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginNonconformityDetailProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginNonconformityDetailProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the slice ships without opening the switch and without a client grant',()=>{
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  assert.match(migration,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.deepEqual(created,['nonconformity_details']);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('the score and the band are generated, so no caller can state one',()=>{
  assert.match(migration,/risk_score numeric GENERATED ALWAYS AS[\s\S]{0,160}?STORED,/);
  assert.match(migration,/risk_band text GENERATED ALWAYS AS \(CASE/);
  // The published Fine-Kinney and 5x5 thresholds, in the source, in one place.
  for(const bound of ['<=70','<=200','<=400','<=4','<=9','<=19']) assert.ok(migration.includes(bound),bound);
  // No action anywhere may carry a score or a band the client chose.
  const allowlist=migration.slice(migration.indexOf('allowed:=CASE p_action'),migration.indexOf('IF allowed IS NULL'));
  assert.doesNotMatch(allowlist,/'risk_score'|'m5_score'|'fk_score'/);
  assert.doesNotMatch(allowlist,/'open_detailed' THEN ARRAY\[[^\]]*'risk_band'/);
  assert.doesNotMatch(allowlist,/'open_from_expert_item' THEN ARRAY\[[^\]]*'risk_band'/);
  assert.doesNotMatch(allowlist,/'set_detail' THEN ARRAY\[[^\]]*'risk_band'/);
});

test('a scoring method arrives whole or not at all',()=>{
  assert.match(migration,/MESSAGE='RISK_INPUT_INCOMPLETE'/);
  assert.match(migration,/CHECK\(risk_method IS DISTINCT FROM 'fine_kinney' OR/);
  assert.match(migration,/CHECK\(risk_method IS DISTINCT FROM 'matrix_5x5' OR/);
  // Only the published scale values are storable.
  assert.match(migration,/fk_probability IN \(0\.2,0\.5,1,3,6,10\)/);
  assert.match(migration,/fk_frequency IN \(0\.5,1,2,3,6,10\)/);
  assert.match(migration,/fk_severity IN \(1,3,7,15,40,100\)/);
  assert.match(migration,/m5_probability BETWEEN 1 AND 5/);
  assert.match(migration,/m5_severity BETWEEN 1 AND 5/);
});

test('an improvement suggestion is a separate record kind, not a quiet nonconformity',()=>{
  assert.match(migration,/ADD COLUMN record_kind text NOT NULL DEFAULT 'nonconformity'/);
  assert.match(migration,/CHECK\(record_kind IN \('nonconformity','improvement'\)\)/);
  const allowlist=migration.slice(migration.indexOf('allowed:=CASE p_action'),migration.indexOf('IF allowed IS NULL'));
  // Only the two screens that can say which one it is carry the key.
  assert.doesNotMatch(allowlist,/'open_manual' THEN ARRAY\[[^\]]*'record_kind'/);
  assert.doesNotMatch(allowlist,/'open_from_finding' THEN ARRAY\[[^\]]*'record_kind'/);
  assert.match(allowlist,/'open_from_expert_item' THEN ARRAY\[[^\]]*'record_kind'/);
  assert.match(allowlist,/'open_detailed' THEN ARRAY\[[^\]]*'record_kind'/);
  assert.match(migration,/coalesce\(p_payload->>'record_kind','nonconformity'\)/);
});

test('widening the provenance constraint fails loudly instead of silently',()=>{
  assert.match(migration,/NONCONFORMITY_SOURCE_KIND_CONSTRAINT_MISSING/);
  assert.match(migration,/DROP CONSTRAINT nonconformities_source_kind_check/);
  assert.match(migration,/CHECK\(source_kind IN \('checklist','risk_version','legacy_finding','legacy_expert_item','manual'\)\)/);
});

test('an expert-opinion item is referenced, never rewritten, and never auto-scored',()=>{
  assert.doesNotMatch(migration,/INSERT INTO public\.findings|UPDATE public\.findings|DELETE FROM public\.findings/);
  assert.doesNotMatch(migration,/INSERT INTO public\.analyses|UPDATE public\.analyses/);
  assert.match(migration,/'legacy_finding_written',false/);
  assert.match(migration,/WHEN 'open_from_expert_item' THEN 'legacy_expert_item'/);
  // severity_for_risk_band is only ever reached when a band was actually sent.
  assert.match(migration,/WHEN p_payload \? 'severity' THEN p_payload->>'severity'/);
});

test('the older signature keeps working and keeps meaning nonconformity',()=>{
  assert.match(migration,/CREATE OR REPLACE FUNCTION private_isg\.open_nonconformity\(/);
  assert.match(migration,/private_isg\.open_nonconformity_record\(p_company,p_workplace,p_source_kind,p_source_ref,p_title,\s*\n?\s*p_severity,'nonconformity'/);
});

test('every new function is revoked and stays off the boundary',()=>{
  const revoked=migration.slice(migration.indexOf('REVOKE ALL ON FUNCTION'));
  for(const name of ['open_nonconformity_record','set_nonconformity_detail']){
    assert.match(revoked,new RegExp(name),`${name} is not revoked`);
  }
  assert.doesNotMatch(migration,/GRANT EXECUTE ON FUNCTION/);
  for(const fn of ['open_nonconformity_record','set_nonconformity_detail']){
    assert.match(migration,new RegExp(`CREATE FUNCTION private_isg\\.${fn}\\([\\s\\S]{0,400}?SECURITY INVOKER`));
  }
  assert.match(migration,/CREATE OR REPLACE FUNCTION private_isg\.mutate_nonconformity\([\s\S]{0,200}?SECURITY DEFINER/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginNonconformityDetailProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? nonconformityDetailFiles : \[\]\)/);
  assert.match(runner,/nonconformityDetailProbe\.afterLogout\(\)/);
});
