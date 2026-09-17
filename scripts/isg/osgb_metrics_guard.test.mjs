import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917133000_osgb_metrics.sql',import.meta.url),'utf8');

test('metrics use authoritative measured sources and mark unbridged domains unavailable',()=>{
  for(const source of ['workspace_usage_records','workspace_file_assets','workspace_download_intents',
    'workspace_handovers','workspace_provider_inbox'])assert.ok(sql.includes(source),source);
  assert.match(sql,/'operational_domains'.*'measured',false.*'unavailable'/s);
  assert.doesNotMatch(sql,/revenue|mrr|training_hours/);
});
test('expert snapshots are narrowed to membership and assigned companies',()=>{
  assert.match(sql,/manager OR membership_id=member\.id/);
  assert.match(sql,/manager OR uploaded_by_membership_id=member\.id/);
  assert.match(sql,/company_id=ANY\(company_ids\)/);
});
test('member usage is manager-only and no private tables are granted',()=>{
  assert.match(sql,/ARRAY\['owner','admin'\]/);
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
  assert.match(sql,/REVOKE ALL ON FUNCTION/);
});
