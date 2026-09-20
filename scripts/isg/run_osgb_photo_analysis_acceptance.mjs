#!/usr/bin/env node
import { createHash, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const PROJECT_REF = 'qlymhrrlhklcudveknih';
const PRODUCTION_REF = 'ppcrzemgiztzcgddbins';
const URL = `https://${PROJECT_REF}.supabase.co`;
const credentialsPath = process.env.OSGB_DEVICE_CREDENTIALS
  ?? '/tmp/isgada-osgb-device-123-credentials.json';
const imagePath = process.env.OSGB_ANALYSIS_IMAGE
  ?? 'docs/localization/phase-4/canary/runtime-images/06-ppe.jpg';

if (PROJECT_REF === PRODUCTION_REF || process.env.SUPABASE_PROJECT_REF === PRODUCTION_REF) {
  throw new Error('PRODUCTION_TARGET_REFUSED');
}

const credentials = JSON.parse(readFileSync(credentialsPath, 'utf8'));
if (credentials.project_ref !== PROJECT_REF) throw new Error('STAGING_CREDENTIALS_REQUIRED');
const keys = JSON.parse(execFileSync('supabase', [
  'projects', 'api-keys', '--project-ref', PROJECT_REF, '-o', 'json',
], { encoding: 'utf8' }));
const anon = keys.find(row => row.name === 'anon')?.api_key;
if (!anon) throw new Error('STAGING_ANON_KEY_UNAVAILABLE');

async function request(path, { method = 'GET', bearer = anon, body, headers = {} } = {}) {
  const raw = body instanceof Uint8Array;
  const response = await fetch(URL + path, {
    method,
    headers: {
      apikey: anon,
      authorization: `Bearer ${bearer}`,
      ...(raw ? {} : { 'content-type': 'application/json' }),
      ...headers,
    },
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
    signal: AbortSignal.timeout(150_000),
  });
  const contentType = response.headers.get('content-type') ?? '';
  const payload = contentType.includes('json')
    ? await response.json().catch(() => null)
    : new Uint8Array(await response.arrayBuffer());
  if (!response.ok) {
    throw new Error(`HTTP_${response.status}_${path}_${JSON.stringify(payload)?.slice(0, 400)}`);
  }
  return payload;
}

const rpc = (name, args, access) => request(`/rest/v1/rpc/${name}`, {
  method: 'POST', bearer: access, body: args,
});
const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

const auth = await request('/auth/v1/token?grant_type=password', {
  method: 'POST',
  body: { email: credentials.expert.email, password: credentials.expert.password },
});
const access = auth.access_token;
if (!access) throw new Error('EXPERT_LOGIN_FAILED');

const workspaceID = credentials.workspace.id;
const companyID = credentials.company.id;
const context = await rpc('isg_workspace_context_v1', { p_workspace: workspaceID }, access);
if (context.membership?.role !== 'expert' || context.can_operate !== true) {
  throw new Error('EXPERT_CONTEXT_INVALID');
}

const bytes = new Uint8Array(readFileSync(imagePath));
const hash = digest(bytes);
const opened = await rpc('isg_workspace_upload_open_v1', {
  p_workspace: workspaceID,
  p_company: companyID,
  p_idempotency: randomUUID(),
  p_request_hash: `\\x${hash}`,
  p_purpose: 'workspace_file',
  p_media_type: 'image/jpeg',
  p_extension: 'jpg',
  p_expected_bytes: bytes.byteLength,
  p_expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
}, access);
const encodedPath = opened.object_path.split('/').map(encodeURIComponent).join('/');
await request(`/storage/v1/object/${encodeURIComponent(opened.bucket)}/${encodedPath}`, {
  method: 'POST', bearer: access, body: bytes,
  headers: { 'content-type': 'image/jpeg', 'x-upsert': 'false' },
});
const finalized = await request('/functions/v1/isg-workspace-file-finalize', {
  method: 'POST', bearer: access, body: { upload_token: opened.upload_token },
});

const entry = await rpc('isg_workspace_file_mutate_v1', {
  p_mutation: randomUUID(),
  p_workspace: workspaceID,
  p_company: companyID,
  p_payload: {
    action: 'create', asset_id: finalized.asset_id,
    category: 'inspection_report', visibility: 'company_team',
    title: 'OSGB fotoğraf analizi kabul testi', original_filename: 'osgb-kabul-fotografi.jpg',
    note: 'Build 128 uçtan uca analiz doğrulaması', tags: ['acceptance', 'photo-analysis'],
  },
}, access);
if (!entry.row?.entry_id && !entry.entry_id) throw new Error('FILE_ENTRY_NOT_CREATED');

const submitted = await rpc('isg_workspace_photo_analysis_submit_v1', {
  p_workspace: workspaceID,
  p_company: companyID,
  p_idempotency: randomUUID(),
  p_source_asset: finalized.asset_id,
}, access);
console.log(`PHOTO_ANALYSIS_SUBMITTED status=${submitted.status}`);

let job;
for (let attempt = 0; attempt < 60; attempt += 1) {
  job = await rpc('isg_workspace_photo_analysis_get_v1', {
    p_workspace: workspaceID, p_job: submitted.job_id,
  }, access);
  if (['succeeded', 'failed', 'cancelled', 'reconcile'].includes(job.status)) break;
  if (attempt === 0 || attempt % 10 === 9) console.log(`PHOTO_ANALYSIS_WAIT status=${job.status}`);
  await sleep(3_000);
}
if (job?.status !== 'succeeded' || !job.analysis_id) {
  throw new Error(`PHOTO_ANALYSIS_${job?.status ?? 'TIMEOUT'}_${job?.error_code ?? 'NO_ERROR_CODE'}`);
}

const analysis = await rpc('isg_workspace_analysis_read_v1', {
  p_workspace: workspaceID, p_company: companyID, p_analysis: job.analysis_id,
}, access);
if (analysis.schema_version !== 1 || analysis.company_id !== companyID
    || analysis.analysis?.id !== job.analysis_id || analysis.counts?.risk < 0) {
  throw new Error('ANALYSIS_READBACK_INVALID');
}
console.log(`PHOTO_ANALYSIS_ACCEPTANCE_OK risk=${analysis.counts.risk} expert=${analysis.counts.expert} training=${analysis.counts.training}`);
