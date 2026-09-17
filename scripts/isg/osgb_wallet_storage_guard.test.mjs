import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {ROOT} from './lib.mjs';
const sql=readFileSync(`${ROOT}/supabase/pilot-release/candidates/20260917103000_osgb_wallet_usage_storage.sql`,'utf8');
test('workspace wallet and storage use immutable ledger, reservations and server byte facts',()=>{
  for(const token of ['workspace_wallet_entries','workspace_credit_reservations','workspace_usage_records','workspace_file_assets','INSUFFICIENT_CREDITS','refund_reversal','debt_repayment','byte_size','object_version']) assert.match(sql,new RegExp(token));
  assert.match(sql,/CHECK\(reserved_units<=posted_units\)/);
  assert.match(sql,/UNIQUE\(workspace_id,entry_key\)/);
  assert.match(sql,/UNIQUE\(workspace_id,bucket,object_path,object_version\)/);
  assert.doesNotMatch(sql,/prompt|email|phone|full_name/i);
  assert.doesNotMatch(sql,/GRANT EXECUTE ON FUNCTION private_isg\.workspace_credit_(grant|settle|refund)/i);
});
