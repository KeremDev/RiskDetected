import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917113000_osgb_provider_billing.sql',import.meta.url),'utf8');
test('provider adapter persists hashes and verified normalized fields, never raw receipts',()=>{
  assert.match(sql,/payload_hash bytea/);
  assert.match(sql,/verification_status IN \('verified','rejected'\)/);
  assert.doesNotMatch(sql,/raw_(receipt|payload|token)|receipt_data|signed_payload/i);
});
test('provider identities, environment and finalization ownership are unique and explicit',()=>{
  assert.match(sql,/UNIQUE\(provider,environment,provider_event_id\)/);
  assert.match(sql,/UNIQUE\(provider,environment,transaction_id\)/);
  assert.match(sql,/\(provider='revenuecat'\)=\(finalization_owner='revenuecat'\)/);
  assert.match(sql,/PRODUCT_NOT_APPROVED/);
  assert.match(sql,/OUT_OF_ORDER/);
});
test('provider functions stay behind service role and use canonical wallet grant/refund',()=>{
  assert.match(sql,/workspace_credit_grant/);
  assert.match(sql,/workspace_credit_refund/);
  assert.match(sql,/TO service_role/);
  assert.doesNotMatch(sql,/TO authenticated/);
});
