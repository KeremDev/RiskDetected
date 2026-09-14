import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginNonconformityHTTPProbe,nonconformityHTTPFiles} from './nonconformity_http_probe.mjs';

const migration=readFileSync(resolve(ROOT,nonconformityHTTPFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginNonconformityHTTPProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginNonconformityHTTPProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the client boundary ships without opening the switch',()=>{
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/INSERT INTO private_isg\.rollout/);
  assert.match(migration,/feature='nonconformity' AND read_enabled AND \(NOT p_write OR write_enabled\)/);
});

test('a legacy finding is referenced and never rewritten',()=>{
  assert.doesNotMatch(migration,/INSERT INTO public\.findings|UPDATE public\.findings|DELETE FROM public\.findings/);
  assert.doesNotMatch(migration,/INSERT INTO public\.analyses|UPDATE public\.analyses/);
  assert.match(migration,/'legacy_finding_written',false/);
  assert.match(migration,/'legacy_findings_written',false/);
  assert.match(migration,/THEN 'manual' ELSE 'legacy_finding' END/);
});

test('an unreadable risk band reaches a person instead of becoming low',()=>{
  assert.match(migration,/IF p_band IS NULL OR p_band='unknown' THEN/);
  assert.match(migration,/MESSAGE='SEVERITY_UNKNOWN'/);
  // The four real bands map across unchanged; nothing else is invented.
  assert.match(migration,/IF p_band NOT IN \('low','medium','high','critical'\) THEN/);
  assert.match(migration,/RETURN p_band;/);
});

test('the write path checks session, subscription and ownership',()=>{
  assert.match(migration,/private_isg\.active_actor\(\)/);
  assert.match(migration,/MESSAGE='PAID_PLAN_REQUIRED'/);
  assert.match(migration,/MESSAGE='ACCESS_DENIED'/);
  assert.match(migration,/private\.user_plan_tier\(actor\) NOT IN \('plus','pro'\)/);
});

test('a payload key nobody allowed cannot be smuggled in',()=>{
  assert.match(migration,/MESSAGE='PAYLOAD_NOT_ALLOWED'/);
  for(const action of ['open_manual','open_from_finding','transition','add_action','verify']){
    assert.match(migration,new RegExp(`WHEN '${action}' THEN ARRAY\\[`),`${action} has no allowlist`);
  }
});

test('a retry returns the first answer instead of a second record',()=>{
  assert.match(migration,/CREATE TABLE private_isg\.nonconformity_receipts/);
  assert.match(migration,/PRIMARY KEY\(actor_id,mutation_id\)/);
  assert.match(migration,/MESSAGE='IDEMPOTENCY_CONFLICT'/);
  assert.match(migration,/'replayed',true/);
});

test('only the two checked entries are exposed, and they are the boundary',()=>{
  const granted=migration.slice(migration.indexOf('GRANT EXECUTE ON FUNCTION'));
  for(const name of ['read_nonconformities','mutate_nonconformity','isg_nonconformity_read_v1','isg_nonconformity_mutate_v1']){
    assert.match(granted,new RegExp(name),`${name} is not granted`);
  }
  assert.doesNotMatch(granted,/require_nonconformity_company|nonconformity_row|open_nonconformity/);
  // The boundary runs as definer; the public wrappers stay invoker.
  assert.match(migration,/read_nonconformities\([\s\S]{0,160}?SECURITY DEFINER/);
  assert.match(migration,/mutate_nonconformity\([\s\S]{0,160}?SECURITY DEFINER/);
  assert.match(migration,/CREATE FUNCTION public\.isg_nonconformity_read_v1[\s\S]{0,200}?SECURITY INVOKER/);
  assert.match(migration,/CREATE FUNCTION public\.isg_nonconformity_mutate_v1[\s\S]{0,200}?SECURITY INVOKER/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginNonconformityHTTPProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? nonconformityHTTPFiles : \[\]\)/);
  assert.match(runner,/nonconformityHTTPProbe\.afterLogout\(\)/);
});
