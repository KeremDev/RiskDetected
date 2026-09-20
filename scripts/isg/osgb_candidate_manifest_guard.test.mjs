import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {buildCandidateManifest,MANIFEST_PATH,OSGB_CANDIDATE_MIGRATIONS} from './osgb_candidate_manifest.mjs';

test('candidate manifest pins every migration in execution order',()=>{
  const stored=JSON.parse(readFileSync(MANIFEST_PATH,'utf8'));
  assert.deepEqual(stored,buildCandidateManifest());
  assert.equal(stored.status,'staging_operational_admin_deferred');
  assert.equal(stored.staging.project_ref,'qlymhrrlhklcudveknih');
  assert.deepEqual(stored.staging.excluded,['20260917120000_osgb_admin_extension.sql']);
  assert.equal(stored.candidate_count,OSGB_CANDIDATE_MIGRATIONS.length);
  assert.deepEqual(stored.candidates.map(row=>row.path.split('/').at(-1)),OSGB_CANDIDATE_MIGRATIONS);
  assert.deepEqual(OSGB_CANDIDATE_MIGRATIONS,[...OSGB_CANDIDATE_MIGRATIONS].sort());
  assert.equal(new Set(stored.candidates.map(row=>row.sha256)).size,OSGB_CANDIDATE_MIGRATIONS.length);
});

test('release candidates remain dark by default',()=>{
  const foundation=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917090000_osgb_workspace_foundation.sql',import.meta.url),'utf8');
  const domains=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917144500_osgb_personnel_domain.sql',import.meta.url),'utf8');
  assert.match(foundation,/read_enabled boolean NOT NULL DEFAULT false/);
  assert.match(foundation,/write_enabled boolean NOT NULL DEFAULT false/);
  assert.match(domains,/read_enabled boolean NOT NULL DEFAULT false/);
  assert.match(domains,/write_enabled boolean NOT NULL DEFAULT false/);
  assert.doesNotMatch(foundation,/INSERT[\s\S]*read_enabled[^;]*true/i);
  assert.doesNotMatch(domains,/INSERT[\s\S]*read_enabled[^;]*true/i);
});
