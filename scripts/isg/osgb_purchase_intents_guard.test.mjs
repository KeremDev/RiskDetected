import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917140000_osgb_purchase_intents.sql',import.meta.url),'utf8');
test('purchase intent is bound to workspace actor membership revision and approved product',()=>{
  for(const token of ['workspace_id','membership_id','actor_user_id','permission_revision',
    'workspace_billing_products','PRODUCT_NOT_APPROVED'])assert.ok(sql.includes(token),token);
});
test('only hash of app intent credential is stored and replay never returns it',()=>{
  assert.match(sql,/intent_token_hash bytea/);
  assert.doesNotMatch(sql,/receipt\s+(text|jsonb)|provider_token\s+(text|jsonb)/i);
  assert.match(sql,/credential_returned',false/);
});
test('client open cannot grant and verified service reconciliation owns effects',()=>{
  assert.match(sql,/workspace_provider_event_record/);
  assert.match(sql,/workspace_provider_event_process/);
  assert.match(sql,/TO service_role/);
  assert.doesNotMatch(sql,/GRANT EXECUTE ON FUNCTION\s+private_isg\.workspace_purchase_record_verified[\s\S]*TO authenticated/);
});
