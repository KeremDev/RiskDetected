import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const bridge=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917171500_osgb_provider_worker_bridge.sql',import.meta.url),'utf8');
const security=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917172000_osgb_provider_worker_rpc_security.sql',import.meta.url),'utf8');
const source=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917173000_osgb_ai_worker_source_validation.sql',import.meta.url),'utf8');

test('workers lease queue rows without blocking peer workers',()=>{
  assert.match(bridge,/FOR UPDATE SKIP LOCKED LIMIT p_limit/);
  assert.match(bridge,/worker_token=token/);
  assert.match(bridge,/worker_lease_until/);
});

test('public worker RPCs execute privately and remain service-role only',()=>{
  assert.match(security,/ALTER FUNCTION public\.isg_workspace_worker_ai_claim_v1[\s\S]*SECURITY DEFINER/);
  assert.match(bridge,/SECURITY INVOKER SET search_path=''/);
  assert.match(bridge,/REVOKE ALL[\s\S]*FROM PUBLIC,anon,authenticated,service_role/);
  assert.match(bridge,/GRANT EXECUTE[\s\S]*TO service_role/);
});

test('missing file input fails before provider start',()=>{
  const fail=source.indexOf("workspace_ai_fail(job.id,'SOURCE_NOT_FOUND',false,p_now)");
  const start=source.indexOf('workspace_ai_start(job.id,provider_hash,p_now)');
  assert.ok(fail>0&&start>fail);
  assert.match(source,/job\.source_kind IN \('photo','document'\)/);
});
