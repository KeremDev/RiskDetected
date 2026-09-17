import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917130000_osgb_asset_transport.sql',import.meta.url),'utf8');
test('client cannot choose bucket/path and plaintext credentials are not persisted',()=>{
  assert.match(sql,/bucket text NOT NULL CHECK\(bucket='isg-workspace-private'\)/);
  assert.match(sql,/token_hash bytea/); assert.doesNotMatch(sql,/token text NOT NULL/);
  assert.match(sql,/p_workspace::text\|\|'\/'\|\|p_idempotency/);
  assert.match(sql,/workspace_storage_upload_allowed/);
  assert.match(sql,/CREATE POLICY isg_workspace_private_insert_intent/);
  assert.match(sql,/FOR INSERT TO authenticated/);
  assert.doesNotMatch(sql,/FOR (SELECT|UPDATE|DELETE) TO authenticated/);
});
test('finalize, delivery and physical deletion require server-only evidence',()=>{
  for(const name of ['workspace_upload_finalize_via_token','workspace_download_claim','workspace_download_delivered','workspace_asset_delete_complete']) assert.ok(sql.includes(name),name);
  assert.match(sql,/TO service_role/); assert.match(sql,/object_version_evidence/); assert.match(sql,/delivered_bytes/);
  for(const name of ['isg_workspace_upload_claim_worker_v1','isg_workspace_upload_finalize_worker_v1',
    'isg_workspace_download_claim_worker_v1','isg_workspace_download_delivered_worker_v1']) {
    assert.match(sql,new RegExp(`GRANT EXECUTE ON FUNCTION[\\s\\S]*${name}[\\s\\S]*TO service_role`),name);
    assert.doesNotMatch(sql,new RegExp(`${name}[^;]*TO authenticated`),name);
  }
});
test('download claim rechecks membership and assignment after token issue',()=>{
  assert.match(sql,/member\.status<>'active'/); assert.match(sql,/company_assignments/);
  assert.match(sql,/status='revoked'/);
});
