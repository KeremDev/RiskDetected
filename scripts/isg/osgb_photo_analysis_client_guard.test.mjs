import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const api = read('App/Services/ISG/IsgWorkspaceAPI.swift');
const store = read('App/Services/ISG/IsgWorkspaceStore.swift');
const screen = read('App/DesignSystem/ISG/IsgWorkspaceAnalysisScreen.swift');
const gate = read('App/Views/Components/NovaPilotMainGate.swift');
const sql = read('supabase/pilot-release/candidates/20260920183000_osgb_photo_analysis_product.sql');

test('photo analysis product pins provider and pricing on the server', () => {
  assert.match(sql, /'photo_analysis','gemini-2\.5-flash','osgb-photo-v1'/);
  assert.match(sql, /workspace_require_company\(p_workspace,p_company,true\)/);
  assert.match(sql, /media_type LIKE 'image\/%'/);
  assert.match(sql, /asset\.sha256,'photo',asset\.id::text,1/);
  assert.match(sql, /workspace_upload_finalize_via_token/);
  assert.match(sql, /p_now,intent\.media_type,intent\.extension/);
  assert.doesNotMatch(api, /gemini-2\.5-flash|osgb-photo-v1/);
});

test('workspace client submits and polls only tenant-scoped photo jobs', () => {
  assert.match(api, /isg_workspace_photo_analysis_submit_v1/);
  assert.match(api, /isg_workspace_photo_analysis_get_v1/);
  assert.match(api, /feature == "photo_analysis"/);
  assert.match(api, /sourceKind == "photo"/);
  assert.match(store, /func submitPhotoAnalysis\(/);
  assert.match(store, /func photoAnalysisJob\(/);
});

test('expert photo route opens a real intake and refreshes the analysis archive', () => {
  assert.match(gate, /case \.newAnalysis: analyses\(startInCreateMode: true\)/);
  assert.match(screen, /NovaPhotoIntakeScreen\(images: \$images, maximum: 1/);
  assert.match(screen, /store\.uploadFile\(/);
  assert.match(screen, /store\.submitPhotoAnalysis\(/);
  assert.match(screen, /store\.photoAnalysisJob\(/);
  assert.match(screen, /selectedAnalysis = \.init\(id: analysisID\)/);
});
