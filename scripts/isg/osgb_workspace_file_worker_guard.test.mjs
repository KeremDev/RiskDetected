import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const finalize=readFileSync(new URL('../../supabase/functions/isg-workspace-file-finalize/index.ts',import.meta.url),'utf8');
const download=readFileSync(new URL('../../supabase/functions/isg-workspace-file-download/index.ts',import.meta.url),'utf8');

test('workspace upload worker derives scope and object path from the opaque server token',()=>{
  assert.match(finalize,/isg_workspace_upload_claim_worker_v1/);
  assert.match(finalize,/claim\.bucket/);
  assert.match(finalize,/claim\.object_path/);
  assert.match(finalize,/isg_workspace_upload_finalize_worker_v1/);
  assert.doesNotMatch(finalize,/workspace_id\?:|company_id\?:|bucket\?:|object_path\?:/);
});

test('workspace upload worker inspects landed bytes and never accepts a client verdict',()=>{
  assert.match(finalize,/inspect\(\{/);
  assert.match(finalize,/result\.verdict !== "clean"/);
  assert.match(finalize,/await sha256\(input\)/);
  assert.match(finalize,/input\.length !== Number\(claim\.expected_bytes\)/);
  assert.match(finalize,/declaredSha256: claim\.declared_sha256/);
  assert.doesNotMatch(finalize,/verdict\?: unknown|sha256\?: unknown|asset_id\?: unknown/);
});

test('workspace download worker reclaims authority and records exact delivery evidence',()=>{
  assert.match(download,/isg_workspace_download_claim_worker_v1/);
  assert.match(download,/bytes\.length !== Number\(claim\.byte_size\)/);
  assert.match(download,/await sha256\(bytes\) !== claim\.sha256/);
  assert.match(download,/isg_workspace_download_delivered_worker_v1/);
  assert.match(download,/cache-control.*private, no-store/s);
});
