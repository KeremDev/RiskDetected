import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginBillingLifecycleProbe,billingLifecycleFiles} from './billing_lifecycle_probe.mjs';

const migration=readFileSync(resolve(ROOT,billingLifecycleFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginBillingLifecycleProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginBillingLifecycleProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the billing ledger ships disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('billing_lifecycle'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,11);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('this slice can never become the access authority on its own',()=>{
  assert.match(migration,/access_authority text NOT NULL DEFAULT 'legacy' CHECK\(access_authority='legacy'\)/);
  assert.match(migration,/'decides_access',false/);
  // The legacy paid helpers and the store catalogue keep deciding and are untouched.
  assert.doesNotMatch(migration,/user_plan_tier|company_limit_for_user|user_subscriptions|public\.companies/);
});

test('a discount can not carry a capability and a gift can not be a store trial',()=>{
  assert.match(migration,/CHECK\(benefit_kind<>'discount_coupon' OR \(NOT grants_capability AND capability IS NULL/);
  assert.match(migration,/CHECK\(benefit_kind<>'gift_access' OR \(grants_capability AND capability IS NOT NULL/);
  assert.match(migration,/resets_quota boolean NOT NULL DEFAULT false CHECK\(NOT resets_quota\)/);
  assert.match(migration,/is_store_trial boolean NOT NULL DEFAULT false CHECK\(NOT is_store_trial\)/);
  assert.match(migration,/'discount_grants_access',false/);
});

test('no signing material is stored and the price always comes from the store',()=>{
  assert.match(migration,/signature_material_stored boolean NOT NULL DEFAULT false CHECK\(NOT signature_material_stored\)/);
  assert.match(migration,/price_authority text NOT NULL DEFAULT 'store' CHECK\(price_authority='store'\)/);
  assert.match(migration,/excluded_from_default_offering boolean NOT NULL DEFAULT true CHECK\(excluded_from_default_offering\)/);
  // No local percentage arithmetic may stand in for a real store price.
  assert.doesNotMatch(migration,/current_price_micros\s*\*\s*[0-9.]/);
  assert.match(migration,/CHECK\(advantage=\(offer_price_micros<current_price_micros\)\)/);
});

test('an unreadable lifecycle is reviewed instead of being read as Free',()=>{
  assert.match(migration,/CHECK\(lifecycle_state<>'unknown' OR needs_review\)/);
  assert.doesNotMatch(migration,/'unknown'[^)]{0,40}'free'/i);
});

test('the benefit state machine lives as rows and activation is separate',()=>{
  assert.match(migration,/CREATE TABLE private_isg\.benefit_state_edges/);
  const edges=[...migration.matchAll(/^\s*\('[a-z_]+','[a-z_]+','[^']+'\)[,;]?$/gm)].length;
  assert.equal(edges,18);
  assert.match(migration,/MESSAGE='BENEFIT_STATE_INVALID'/);
  assert.match(migration,/IF p_target='active' THEN RAISE EXCEPTION/);
});

test('one payment settles once and family is absent from the economic key',()=>{
  assert.match(migration,/UNIQUE\(environment,store,purchase_ref,billing_period\)/);
  const settlement=migration.slice(migration.indexOf('CREATE TABLE private_isg.benefit_settlements'));
  assert.doesNotMatch(settlement.slice(0,settlement.indexOf(');')),/family_key/);
  assert.match(migration,/MESSAGE='SETTLEMENT_CONFLICT'/);
  assert.match(migration,/'period_released',false/);
});

test('one quote opens at most one checkout and a timeout waits in review',()=>{
  assert.match(migration,/CREATE UNIQUE INDEX checkout_intent_live_idx ON private_isg\.checkout_intents\(quote_id\) WHERE state='awaiting_store'/);
  assert.match(migration,/MESSAGE='INTENT_ALREADY_OPEN'/);
  assert.match(migration,/'second_checkout_possible',false/);
  assert.match(migration,/'benefit_returned',false/);
});

test('the payment identity is read from store evidence, never from the caller',()=>{
  assert.match(migration,/IF entry\.event_kind NOT IN \('purchase','renewal'\) THEN/);
  assert.match(migration,/MESSAGE='NO_PAYMENT_EVIDENCE'/);
  assert.match(migration,/MESSAGE='PURCHASE_OWNED_ELSEWHERE'/);
  assert.match(migration,/'family_in_key',false/);
});

test('the commercial numbers are fixtures, not an approved catalogue',()=>{
  assert.match(migration,/value_source text NOT NULL DEFAULT 'unapproved_fixture'/);
  assert.match(migration,/CHECK\(value_source<>'unapproved_fixture' OR \(NOT content_approved AND needs_review\)\)/);
  assert.match(migration,/limit_approved boolean NOT NULL DEFAULT false CHECK\(NOT limit_approved\)/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginBillingLifecycleProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? billingLifecycleFiles : \[\]\)/);
  assert.match(runner,/billingProbe\.afterLogout\(\)/);
});
