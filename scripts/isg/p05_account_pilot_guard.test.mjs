import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ROOT} from './lib.mjs';
import {p05AccountPilotFiles,beginP05AccountPilotProbe} from './p05_account_pilot_probe.mjs';
import {p05UpgradeFiles} from './p05_upgrade_probe.mjs';
const source=readFileSync(`${ROOT}/${p05AccountPilotFiles[0]}`,'utf8');
test('account pilot cannot run against a live target',async()=>{
  let touched=false;
  await assert.rejects(beginP05AccountPilotProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  assert.equal(touched,false);
});
test('no production identity or open rollout is seeded',()=>{
  assert.doesNotMatch(source,/INSERT INTO private_isg.p05_pilot_accounts|@gmail|f3be34f9/);
  assert.match(source,/SET read_enabled=false,write_enabled=false WHERE feature='personnel'/);
  assert.match(source,/CHECK\(NOT write_enabled OR read_enabled\)/);
});
test('new company provenance is mandatory and clients cannot pick its owner',()=>{
  assert.match(source,/JOIN private_isg.p05_pilot_company_origins o ON o.company_id=g.company_id AND o.actor_id=g.actor_id/);
  assert.match(source,/actor uuid:=private_isg.active_actor\(\)/);
  assert.match(source,/VALUES\(actor,name,p_hazard_class\)/);
  assert.match(source,/ALTER TABLE private_isg.p05_pilot_company_origins ENABLE ROW LEVEL SECURITY/);
  assert.doesNotMatch(source,/UPDATE public.companies|ALTER POLICY/);
});
test('creation retains quota, receipt and atomic initialization',()=>{
  assert.match(source,/private.company_limit_for_user\(actor\)/);
  assert.match(source,/MESSAGE='PAID_PLAN_REQUIRED'/);
  assert.match(source,/UNIQUE\(actor_id,mutation_id\)/);
  assert.match(source,/MESSAGE='IDEMPOTENCY_CONFLICT'/);
  assert.match(source,/SELECT \* INTO account FROM private_isg.p05_pilot_accounts WHERE actor_id=actor FOR UPDATE/);
  assert.match(source,/PERFORM private_isg.ensure_default\(company.id\)/);
});
test('ordinary legacy company insertion no longer performs global ISG initialization',()=>{
  assert.match(source,/DROP TRIGGER companies_isg_default ON public.companies/);
  assert.doesNotMatch(source,/DROP TRIGGER companies_enforce_write_rules|SELECT private_isg.ensure_default\(id\) FROM public.companies/);
});
test('candidate is fingerprinted and chronologically upgrade tested',()=>{
  const runner=readFileSync(`${ROOT}/scripts/isg/run_auth_restore.mjs`,'utf8');
  assert.match(runner,/concat\(mode.synthetic \? p05AccountPilotFiles : \[\]\)/);
  assert.match(runner,/beginP05AccountPilotProbe\(\{synthetic:true/);
  assert.ok(p05UpgradeFiles.includes(p05AccountPilotFiles[0]));
});
