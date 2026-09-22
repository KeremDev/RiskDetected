#!/usr/bin/env node
// Explicit staging-only end-to-end test. Never print credentials or JWTs.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
const project = 'qlymhrrlhklcudveknih';
const credentials = JSON.parse(readFileSync(process.env.OSGB_DEVICE_CREDENTIALS ?? '/tmp/isgada-osgb-device-123-credentials.json', 'utf8'));
if (credentials.project_ref !== project) throw new Error('STAGING_REQUIRED');
const keys = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', project, '-o', 'json'], { encoding: 'utf8' }));
const anon = keys.find(x => x.name === 'anon')?.api_key;
if (!anon) throw new Error('ANON_KEY_REQUIRED');
let token = anon;
async function request(path, body, raw = false) {
  const response = await fetch(`https://${project}.supabase.co${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { apikey: anon, authorization: `Bearer ${token}`, 'content-type': raw ? 'image/jpeg' : 'application/json' },
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body), signal: AbortSignal.timeout(120000),
  });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${(await response.text()).slice(0,350)}`);
  return response.headers.get('content-type')?.includes('json') ? response.json() : new Uint8Array(await response.arrayBuffer());
}
const auth = await request('/auth/v1/token?grant_type=password', { email: credentials.expert.email, password: credentials.expert.password });
token = auth.access_token;
if (!token) throw new Error('LOGIN_FAILED');
console.log('PASS expert password login');
const workspace = credentials.workspace.id, company = credentials.company.id;
async function rpc(name, args) { return request(`/rest/v1/rpc/${name}`, args); }
async function shared(name, args) {
  const result = await rpc('isg_expert_rpc_v1', { p_workspace: workspace, p_function: name, p_arguments: args });
  if (result._expert_workspace_id !== workspace) throw new Error('SCOPE_MISMATCH');
  return result.payload;
}
const companies = await shared('isg_expert_companies_v1', {});
if (!companies.rows.some(x => x.id === company)) throw new Error('ASSIGNED_COMPANY_MISSING');
for (const name of ['isg_pilot_overview_v2', 'isg_pilot_training_detail_v3', 'isg_pilot_notice_feed_v1']) {
  await shared(name, name === 'isg_pilot_overview_v2' ? { p_company: null } : {}); console.log(`PASS ${name}`);
}
await shared('isg_statistics_v1', { p_company: null, p_months: 6 });
console.log('PASS shared statistics');
if (process.env.SHARED_IMPORT_LEGACY === '1') {
  let after = null;
  do {
    const page = await rpc('isg_workspace_file_read_v1', { p_workspace: workspace, p_company: company,
      p_id: null, p_query: '', p_category: null, p_include_archived: false, p_after: after, p_limit: 50 });
    for (const row of page.rows) {
      // Never widen private/management visibility into a team library.
      if (row.visibility !== 'company_team' || row.asset?.lifecycle !== 'active') throw new Error('LEGACY_SCOPE_REQUIRES_REVIEW');
      const tag = `old:${row.id}`;
      const existing = await shared('isg_pilot_file_library_read_v2', { p_company: company, p_kind: 'list',
        p_query: row.title, p_category: null, p_state: null, p_id: null, p_limit: 100, p_offset: 0 });
      if (existing.rows.some(x => x.tags?.includes(tag))) continue;
      const download = await rpc('isg_workspace_download_open_v1', { p_workspace: workspace, p_asset: row.asset.id,
        p_purpose: 'workspace_file_preview', p_expires_at: new Date(Date.now()+120000).toISOString() });
      const bytes = await request('/functions/v1/isg-workspace-file-download', { download_token: download.download_token });
      const opened = await shared('isg_pilot_file_library_mutate_v2', { p_company: company, p_action: 'open_upload',
        p_operation: randomUUID(), p_mutation: randomUUID(), p_payload: { title: row.title, category: row.category,
          file_name: row.original_filename, extension: row.asset.extension, bytes: bytes.length,
          sha256: createHash('sha256').update(bytes).digest('hex'), note: row.note, tags: [...row.tags,tag] } });
      await request(`/storage/v1/object/isg-quarantine/${opened.row.upload_path.split('/').map(encodeURIComponent).join('/')}`, bytes, true);
      await request('/functions/v1/isg-file-inspect', { workspace_id: workspace, entry_id: opened.entry_id });
      const checked = await shared('isg_pilot_file_library_read_v2', { p_company: company, p_kind: 'detail', p_query: null,
        p_category: null, p_state: null, p_id: opened.entry_id, p_limit: null, p_offset: null });
      if (checked.row.state !== 'promoted') throw new Error('LEGACY_REINSPECTION_FAILED');
      console.log(`PASS legacy file re-inspected and retained: ${row.id}`);
    }
    after = page.next;
  } while (after);
  process.exit(0);
}
if (process.env.SHARED_ANALYSIS_ID) {
  for (const format of ['pdf','xlsx']) {
    const created = await shared('isg_expert_analysis_v1', { p_action: 'export', p_payload: {
      analysis_id: process.env.SHARED_ANALYSIS_ID, mutation_id: randomUUID(), format, method: 'matrix_5x5', attach_company: true,
    } });
    const result = await poll(async () => {
      const r = await rpc('isg_workspace_export_get_v1', { p_workspace: workspace, p_company: company, p_job: created.row.id });
      return r.row ?? r;
    }, r => r.status === 'succeeded');
    if (!result.output_asset_id) throw new Error('EXPORT_ASSET_MISSING');
    const opened = await rpc('isg_workspace_download_open_v1', { p_workspace: workspace, p_asset: result.output_asset_id,
      p_purpose: 'workspace_file_preview', p_expires_at: new Date(Date.now()+120000).toISOString() });
    const output = await request('/functions/v1/isg-workspace-file-download', { download_token: opened.download_token });
    if (!(output instanceof Uint8Array) || output.length<100 ||
      (format==='pdf' && new TextDecoder().decode(output.slice(0,5))!=='%PDF-') ||
      (format==='xlsx' && new TextDecoder().decode(output.slice(0,2))!=='PK')) throw new Error('REPORT_BYTES_INVALID');
    console.log(`PASS ${format} report generated`);
  }
  process.exit(0);
}
const bytes = readFileSync('docs/localization/phase-4/canary/runtime-images/06-ppe.jpg');
const open = await shared('isg_pilot_file_library_mutate_v2', {
  p_company: company, p_action: 'open_upload', p_operation: randomUUID(), p_mutation: randomUUID(),
  p_payload: { title: 'Shared expert acceptance photo', category: 'inspection_report', file_name: 'shared-expert-qa.jpg',
    extension: 'jpg', bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), tags: ['shared-panel-qa'] },
});
await request(`/storage/v1/object/isg-quarantine/${open.row.upload_path.split('/').map(encodeURIComponent).join('/')}`, bytes, true);
await request('/functions/v1/isg-file-inspect', { workspace_id: workspace, entry_id: open.entry_id });
const detailArgs = { p_company: company, p_kind: 'detail', p_query: null, p_category: null, p_state: null, p_id: open.entry_id, p_limit: null, p_offset: null };
const file = await shared('isg_pilot_file_library_read_v2', detailArgs);
if (file.row.state !== 'promoted' || !file.row.asset_id) throw new Error(`FILE_NOT_PROMOTED: ${file.row.state}`);
const downloaded = await request(`/storage/v1/object/authenticated/${file.row.download_bucket}/${file.row.download_path.split('/').map(encodeURIComponent).join('/')}`);
if (createHash('sha256').update(downloaded).digest('hex') !== createHash('sha256').update(bytes).digest('hex')) throw new Error('DOWNLOAD_MISMATCH');
console.log('PASS real canonical upload, inspection, promotion, byte-exact download');
const analysis = (action, payload) => shared('isg_expert_analysis_v1', { p_action: action, p_payload: payload });
const submitted = await analysis('submit', { company_id: company, mutation_id: randomUUID(), asset_ids: [file.row.asset_id], focus_ids: ['general'], sector: 'general' });
console.log('PASS shared analysis submit');
async function poll(read, complete) {
  for (let i=0;i<100;i++) {
    const row = await read(); if (complete(row)) return row;
    if (['failed','cancelled'].includes(row.status)) throw new Error(`JOB_FAILED: ${JSON.stringify(row)}`);
    await new Promise(resolve => setTimeout(resolve, 2500));
  }
  throw new Error('JOB_TIMEOUT');
}
const job = await poll(async () => {
  const r = await rpc('isg_workspace_photo_analysis_get_v1', { p_workspace: workspace, p_job: submitted.id });
  return r.row ?? r;
}, r => r.status === 'succeeded');
const result = await analysis('detail', { analysis_id: job.analysis_id });
if (!result.analysis?.id || result.photos.length !== 1) throw new Error('ANALYSIS_DETAIL_INVALID');
console.log('PASS shared analysis provider completion and detail');
console.log(JSON.stringify({ project, production_touched: false, analysis_id: result.analysis.id, file_entry_id: open.entry_id }));
