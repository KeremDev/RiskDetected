import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const migration = await readFile(
  new URL('supabase/migrations/20260921225116_referral_rewards_activation.sql', root),
  'utf8',
);
const campaignCore = await readFile(
  new URL('supabase/migrations/20260914110000_isg_campaign_core.sql', root),
  'utf8',
);
const qualificationFix = await readFile(
  new URL('supabase/migrations/20260921232553_referral_qualification_period_fix.sql', root),
  'utf8',
);
const rateLimitFix = await readFile(
  new URL('supabase/migrations/20260921232803_referral_claim_rate_limit_fix.sql', root),
  'utf8',
);
const diagnosticsIndex = await readFile(
  new URL('supabase/migrations/20260922024100_referral_processing_error_owner_index.sql', root),
  'utf8',
);
const service = await readFile(new URL('App/Services/ReferralRewardsService.swift', root), 'utf8');
const view = await readFile(new URL('App/Views/Profile/ReferralRewardsView.swift', root), 'utf8');
const profile = await readFile(new URL('App/Views/Profile/ProfileView.swift', root), 'utf8');
const app = await readFile(new URL('App/RiskDetectedApp.swift', root), 'utf8');
const state = await readFile(new URL('App/AppState.swift', root), 'utf8');
const sync = await readFile(
  new URL('supabase/functions/sync-revenuecat-subscription/index.ts', root),
  'utf8',
);
const webhook = await readFile(
  new URL('supabase/functions/revenuecat-webhook/index.ts', root),
  'utf8',
);

test('referral campaign is double-sided, approved and qualified only by server work', () => {
  assert.match(migration, /friend_referral_plus_7d/);
  assert.match(migration, /'published', 2, 30/);
  assert.match(migration, /'sponsor_gift_plus_7d', 'sponsor_gift_plus_7d'/);
  assert.match(migration, /values_approved', true/);
  assert.match(migration, /private_isg\.record_qualification_event\(/);
  for (const kind of [
    'employee_created',
    'workplace_created',
    'department_created',
    'training_plan_created',
    'risk_assessment_created',
    'document_exported',
    'checklist_run_completed',
  ]) {
    assert.match(migration, new RegExp(kind));
  }
  assert.doesNotMatch(migration, /TRIGGER[^;]+referral_client_events/is);
});

test('referral claims and rewards remain server-owned and abuse bounded', () => {
  assert.match(campaignCore, /SELF_REFERRAL/);
  assert.match(campaignCore, /CYCLE_DETECTED/);
  assert.match(migration, /referral_claim_attempts/);
  assert.match(migration, />= 10[\s\S]*RATE_LIMITED/);
  assert.match(migration, /REVOKE ALL ON private_isg\.referral_claim_attempts[\s\S]*service_role/);
  assert.match(migration, /FROM PUBLIC, anon;[\s\S]*TO authenticated, service_role/);
  assert.match(migration, /cap_amount[\s\S]*100[\s\S]*cap_approved[\s\S]*true/);
  assert.match(qualificationFix, /budget_period/);
  assert.doesNotMatch(
    qualificationFix,
    /VALUES\s*\(version_row\.version_id,\s*period_key,\s*100,\s*true\)/i,
  );
  assert.match(rateLimitFix, /'error_code', 'RATE_LIMITED'/);
  assert.match(rateLimitFix, /'error_code', 'INVALID_REFERRAL_CODE'/);
  assert.match(diagnosticsIndex, /referral_processing_errors_owner_idx/);
});

test('gift activation does not overwrite paid access or auto-renew', () => {
  assert.match(migration, /PAID_ACCESS_ACTIVE/);
  assert.match(migration, /GIFT_ALREADY_ACTIVE/);
  assert.match(migration, /source = 'referral_reward'/);
  assert.match(migration, /d\.capability = 'plus_access'/);
  assert.match(sync, /previousSubscription\?\.source === "referral_reward"/);
  assert.match(webhook, /sponsorReward\?\.source === "referral_reward"/);
});

test('native app exposes dashboard, code fallback, share and deep-link routing', () => {
  assert.match(service, /rpc\("referral_dashboard_v1"\)/);
  assert.match(service, /rpc\("referral_claim_v1"/);
  assert.match(service, /rpc\("referral_activate_reward_v1"/);
  assert.match(service, /let errorCode: String\?/);
  assert.match(service, /ReferralRewardsError\.server\(code\)/);
  assert.match(service, /io\.supabase\.riskdetected/);
  assert.match(view, /Arkadaşını davet et/);
  assert.match(view, /Davet bağlantısını paylaş/);
  assert.match(view, /İlerleme:/);
  assert.match(profile, /profile\.row\.referral/);
  assert.match(app, /ReferralDeepLinkStore\.shared\.capture\(url\)/);
  assert.match(state, /routePendingReferralIfReady\(\)/);
});
