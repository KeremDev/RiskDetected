import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source=readFileSync(new URL('./run_osgb_staging_acceptance.mjs',import.meta.url),'utf8');

test('acceptance runner is pinned to staging and refuses production',()=>{
  assert.match(source,/PROJECT_REF='qlymhrrlhklcudveknih'/);
  assert.match(source,/PRODUCTION_REF='ppcrzemgiztzcgddbins'/);
  assert.match(source,/PRODUCTION_TARGET_REFUSED/);
  assert.doesNotMatch(source,/projects\/\$\{PRODUCTION_REF\}/);
});

test('acceptance covers tenant domains real storage AI and exports',()=>{
  for(const marker of ['isg_osgb_workspace_create_v1','isg_workspace_company_create_v1',
    'isg_workspace_personnel_read_v1','isg_workspace_training_advanced_read_v1',
    'isg_workspace_upload_open_v1','isg-workspace-file-finalize','isg-workspace-file-download',
    'isg_workspace_ai_submit_v1','gemini-2.5-flash','isg_workspace_export_create_v1',
    "for(const format of ['pdf','xlsx'])"]){
    assert.ok(source.includes(marker),marker);
  }
});

test('acceptance admits only the exact Android QA build after safety checks',()=>{
  assert.match(source,/android_client_enabled/);
  assert.match(source,/enabled_android_version_codes/);
  assert.match(source,/\|\|'\[14\]'::jsonb/);
  assert.match(source,/ANDROID_QA_RUNTIME_GATES_NOT_READY/);
});

test('credentials stay outside the repository with restrictive permissions',()=>{
  assert.match(source,/\/tmp\/isg-staging-qa-credentials\.json/);
  assert.match(source,/chmodSync\(CREDENTIALS,0o600\)/);
  assert.doesNotMatch(source,/console\.log\([^\n]*password/);
});
