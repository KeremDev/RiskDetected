import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginDispatchQuotaProbe,dispatchQuotaFiles} from './dispatch_quota_probe.mjs';

const dispatch=readFileSync(resolve(ROOT,dispatchQuotaFiles[0]),'utf8');
const quota=readFileSync(resolve(ROOT,dispatchQuotaFiles[1]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginDispatchQuotaProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginDispatchQuotaProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('both migrations ship disabled and add no client privilege',()=>{
  for(const migration of [dispatch,quota]) {
    assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
    assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
    assert.match(migration,/REVOKE ALL ON FUNCTION/);
  }
  assert.match(dispatch,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('event_dispatch'\)/);
  assert.match(quota,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('quota_ledger'\)/);
});

test('every new table enables row level security',()=>{
  for(const migration of [dispatch,quota]) {
    const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
    const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
    assert.ok(created.length>0);
    for(const table of created) assert.ok(secured.has(table),table);
  }
});

test('the ledger cannot become an authority without a new migration',()=>{
  assert.match(quota,/authority text NOT NULL DEFAULT 'shadow' CHECK\(authority='shadow'\)/);
  // A limit is always supplied by the caller; no plan number is baked in here.
  assert.doesNotMatch(quota,/DEFAULT [0-9]+ *(?:--)? *(?:company|slot|plus|pro)/i);
  assert.match(quota,/p_limit bigint,p_unlimited boolean/);
});

test('a dead delivery blocks its successor and is only replayed on review',()=>{
  assert.match(dispatch,/prior\.aggregate_version<c\.aggregate_version AND prior\.state<>'done'/);
  assert.match(dispatch,/IF NOT FOUND OR d\.state<>'dead' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'/);
  assert.match(dispatch,/reason:=private_isg\.text_value\(p_reason,200\)/);
});

test('the runner wires the probe and hashes both migrations',()=>{
  assert.match(runner,/beginDispatchQuotaProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? dispatchQuotaFiles : \[\]\)/);
  assert.match(runner,/dispatchProbe\.afterLogout\(\)/);
});
