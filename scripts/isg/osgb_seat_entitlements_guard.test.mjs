import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {ROOT} from './lib.mjs';
const sql=readFileSync(`${ROOT}/supabase/pilot-release/candidates/20260917100000_osgb_seat_entitlements.sql`,'utf8');
test('seat authority is store-neutral, locked and leaves Scale undecided',()=>{
  assert.match(sql,/\('starter',5,1\),\('growth',10,1\),\('pro',20,1\)/);
  assert.doesNotMatch(sql,/\('scale',/);
  assert.match(sql,/FOR UPDATE/);
  assert.match(sql,/SEAT_LIMIT_REACHED/);
  assert.match(sql,/workspace_seat_reservations/);
  assert.match(sql,/provider IN \('apple','google','revenuecat','admin'\)/);
  assert.doesNotMatch(sql,/\bTRY\b|monthly_credit|price_(amount|tl)/i);
  assert.doesNotMatch(sql,/GRANT .* ON private_isg\./i);
});
