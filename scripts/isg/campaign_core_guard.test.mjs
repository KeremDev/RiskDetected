import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginCampaignCoreProbe,campaignCoreFiles} from './campaign_core_probe.mjs';

const migration=readFileSync(resolve(ROOT,campaignCoreFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginCampaignCoreProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginCampaignCoreProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the campaign ledger ships disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('campaigns'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,11);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('nothing reaches a user without a recorded human decision',()=>{
  assert.match(migration,/CHECK\(status<>'published' OR \(approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL\)\)/);
  assert.match(migration,/CHECK\(value_source<>'unapproved_fixture' OR \(NOT content_approved AND needs_review\)\)/);
  assert.match(migration,/cap_approved boolean NOT NULL DEFAULT false CHECK\(NOT cap_approved\)/);
  assert.match(migration,/'timing_approved',false/);
});

test('only a server mutation qualifies and a heartbeat has no row shape',()=>{
  assert.match(migration,/proof_source text NOT NULL DEFAULT 'server_mutation' CHECK\(proof_source='server_mutation'\)/);
  const kinds=migration.slice(migration.indexOf('event_kind text NOT NULL CHECK'));
  assert.doesNotMatch(kinds.slice(0,400),/heartbeat|screen_view|personal_note|failed_analysis|note_created/);
  assert.match(migration,/UNIQUE\(owner_id,operation_id\)/);
  assert.match(migration,/count\(DISTINCT occurred_on\)/);
  // Marketing consent is never a condition of earning a reward.
  assert.match(migration,/'marketing_consent_required',false/);
});

test('abuse guards are canonical account only',()=>{
  assert.match(migration,/MESSAGE='SELF_REFERRAL'/);
  assert.match(migration,/MESSAGE='CYCLE_DETECTED'/);
  assert.match(migration,/MESSAGE='ALREADY_CLAIMED'/);
  assert.match(migration,/CREATE UNIQUE INDEX referral_claim_invitee_once_idx/);
  // Column definitions only: an address or a network is never stored here.
  assert.doesNotMatch(migration,/^\s*\w*(email|ip_address|device_id|fingerprint|user_agent)\w*\s+(uuid|text|jsonb|inet)/mi);
});

test('an annual or unreadable inviter takes no branch and is not read as Free',()=>{
  assert.match(migration,/WHEN paid_state='unknown' THEN 'unknown'/);
  assert.match(migration,/'UNSUPPORTED_BRANCH'/);
  assert.match(migration,/'auto_plan_conversion',false/);
  assert.match(migration,/'treated_as_free',false/);
  assert.match(migration,/'capability_opened',false/);
});

test('winback needs a really finished monthly period with a positive payment',()=>{
  assert.match(migration,/WHEN NOT paid_before THEN 'TRIAL_OR_GIFT_ONLY'/);
  assert.match(migration,/WHEN other_active THEN 'OTHER_STORE_ACTIVE'/);
  assert.match(migration,/WHEN paid_state IN \('on_hold','paused'\) THEN 'HOLD_OR_PAUSE'/);
  assert.match(migration,/WHEN paid_state IN \('refunded','revoked'\) THEN 'REFUNDED_OR_REVOKED'/);
  assert.match(migration,/WHEN gift_on THEN 'GIFT_ACTIVE'/);
  assert.match(migration,/UNIQUE\(campaign_id,owner_id\)/);
  assert.match(migration,/MESSAGE='EPISODE_EXISTS'/);
});

test('a suppression never resets the clock and a contact claims no delivery',()=>{
  assert.match(migration,/ttl_reset boolean NOT NULL DEFAULT false CHECK\(NOT ttl_reset\)/);
  assert.match(migration,/delivery_claimed boolean NOT NULL DEFAULT false CHECK\(NOT delivery_claimed\)/);
  assert.match(migration,/'ttl_reset',false/);
  // The send-time re-read: consent for this exact channel, then the lifecycle.
  assert.match(migration,/purpose='marketing' AND channel=p_channel AND granted/);
  assert.match(migration,/IF paid_now IN \('active','in_trial','grace'\) THEN refusal:='resubscribed'/);
});

test('a pause stops production without revoking anything earned',()=>{
  assert.match(migration,/'earned_benefits_revoked',false/);
  assert.match(migration,/'settlements_revoked',false/);
  assert.doesNotMatch(migration,/DELETE FROM private_isg\.benefit_/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.benefit_settlements/);
});

test('rewards are created through the P14 ledger, never as a direct capability',()=>{
  assert.match(migration,/private_isg\.grant_benefit\(/);
  assert.doesNotMatch(migration,/INSERT INTO private_isg\.benefit_instances/);
  assert.doesNotMatch(migration,/user_plan_tier|company_limit_for_user|user_subscriptions/);
  assert.match(migration,/REFERENCES private_isg\.benefit_definitions\(code\)/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginCampaignCoreProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? campaignCoreFiles : \[\]\)/);
  assert.match(runner,/campaignProbe\.afterLogout\(\)/);
});
