import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917141500_osgb_member_quotas.sql',import.meta.url),'utf8');
test('quota is optional, monthly and membership scoped',()=>{
  assert.match(sql,/PRIMARY KEY\(workspace_id,membership_id,period_key\)/);
  assert.match(sql,/quota\.membership_id IS NOT NULL/);
  assert.match(sql,/MEMBER_QUOTA_EXCEEDED/);
});
test('reserve locks wallet then quota and counts settled actual plus open reservations',()=>{
  const wallet=sql.indexOf('workspace_wallets WHERE workspace_id=p_workspace FOR UPDATE');
  const quota=sql.indexOf('workspace_member_credit_quotas\n    WHERE workspace_id=p_workspace',wallet);
  assert.ok(wallet>=0&&quota>wallet);
  assert.match(sql,/WHEN 'reserved' THEN reserved_units WHEN 'settled' THEN settled_units/);
});
test('expert can read only own budget and managers own writes',()=>{
  assert.match(sql,/actor_member\.role='expert' AND actor_member\.id<>p_membership/);
  assert.match(sql,/ARRAY\['owner','admin'\]/);
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
});
