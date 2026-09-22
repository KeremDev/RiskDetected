#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, chmodSync} from 'node:fs';

const PRODUCTION_REF = 'ppcrzemgiztzcgddbins';
const STAGING_REF = 'qlymhrrlhklcudveknih';
const EMAIL = 'kayalar.kerem21@gmail.com';
const APPLY = process.argv.includes('--apply');
const COPY_STORAGE = process.argv.includes('--storage');
const ACCESS_TOKEN_PATH = '/Users/keremkayalar/.supabase/access-token';
const RECEIPT_PATH = '/tmp/isgada-production-to-staging-user-copy.json';

if (PRODUCTION_REF === STAGING_REF) throw new Error('PRODUCTION_TARGET_REFUSED');
if (COPY_STORAGE && !APPLY) throw new Error('STORAGE_REQUIRES_APPLY');

const accessToken = readFileSync(ACCESS_TOKEN_PATH, 'utf8').trim();
const quoteLiteral = value => `'${String(value).replaceAll("'", "''")}'`;
const quoteIdent = value => `"${String(value).replaceAll('"', '""')}"`;
const tableIdent = ({schema, table}) => `${quoteIdent(schema)}.${quoteIdent(table)}`;

async function management(projectRef, query) {
  const response = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/database/query`, {
    method: 'POST',
    headers: {authorization: `Bearer ${accessToken}`, 'content-type': 'application/json'},
    body: JSON.stringify({query}),
    signal: AbortSignal.timeout(150_000),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(`MANAGEMENT_SQL_${projectRef}_${response.status}_${JSON.stringify(body)?.slice(0, 800)}`);
  }
  return body;
}

function apiKeys(projectRef) {
  return JSON.parse(execFileSync('supabase', [
    'projects', 'api-keys', '--project-ref', projectRef, '--reveal', '--output', 'json',
  ], {encoding: 'utf8'}));
}

function serviceKey(projectRef) {
  const keys = apiKeys(projectRef);
  const key = keys.find(row => row.name === 'service_role')?.api_key
    ?? keys.find(row => row.type === 'secret' && row.name === 'default')?.api_key;
  if (!key) throw new Error(`SERVICE_KEY_UNAVAILABLE_${projectRef}`);
  return key;
}

async function authUser(projectRef) {
  const rows = await management(projectRef, `
    select id,email,created_at from auth.users
    where lower(email)=lower(${quoteLiteral(EMAIL)})
    order by created_at limit 2;`);
  if (rows.length !== 1) throw new Error(`AUTH_USER_COUNT_${projectRef}_${rows.length}`);
  return rows[0];
}

const TABLES = [
  {schema: 'public', table: 'companies', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'analyses', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'photos', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'findings', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'analysis_photo_summaries', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'finding_edit_events', filter: user => `analysis_id in (select id from public.analyses where user_id=${quoteLiteral(user)}::uuid)`},
  {schema: 'public', table: 'reports', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'ai_usage_logs', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'professional_progress_profiles', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'professional_progress_competency_stats', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'professional_progress_badges', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'professional_progress_weekly_summaries', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'professional_progress_finding_classifications', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'professional_progress_events', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'professional_progress_messages', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'notification_preferences', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'user_engagement_state', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'public', table: 'user_onboarding_answers', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_claim_candidates', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_engine_routes', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_engine_runs', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_fact_lineage', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_hard_rejection_ledger', filter: user => `analysis_id in (select id from public.analyses where user_id=${quoteLiteral(user)}::uuid)`},
  {schema: 'private', table: 'analysis_human_reviews', filter: user => `analysis_id in (select id from public.analyses where user_id=${quoteLiteral(user)}::uuid)`},
  {schema: 'private', table: 'analysis_inspection_signals', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_notebook_entries', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_notebook_entry_revisions', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_item_feedback', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_items_v4', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_job_events', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_job_state', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_module_audits', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_notebook_advisories', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_openai_background_responses', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_photo_runs', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  // Provider-attempt telemetry is intentionally not copied. Its enum evolves
  // with provider workers and is neither user-visible nor required to render
  // a completed analysis result.
  {schema: 'private', table: 'analysis_quality_trace_v4', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_result_events', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_routing_ledger', filter: user => `analysis_id in (select id from public.analyses where user_id=${quoteLiteral(user)}::uuid)`},
  {schema: 'private', table: 'analysis_targeted_runs', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_targeted_runs_v4', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private', table: 'analysis_training_cards', filter: user => `user_id=${quoteLiteral(user)}::uuid`},
];

const companyIds = user => `select id from public.companies where user_id=${quoteLiteral(user)}::uuid`;
const workplaceIds = user => `
  select id from private_isg.workplaces where company_id in (${companyIds(user)})`;
const trainingSessionIds = user => `
  select id from private_isg.pilot_training_sessions where owner_id=${quoteLiteral(user)}::uuid`;
const annualPlanIds = user => `
  select plan_id from private_isg.annual_work_plans where company_id in (${companyIds(user)})`;
const riskAssessmentIds = user => `
  select assessment_id from private_isg.risk_assessments where company_id in (${companyIds(user)})`;
const nonconformityIds = user => `
  select nonconformity_id from private_isg.nonconformities where company_id in (${companyIds(user)})`;

// User-visible ISG module records. Technical receipts, audit ledgers, auth,
// billing, telemetry and device data are deliberately excluded.
// The order keeps every parent ahead of its children for both old and new schemas.
const MODULE_TABLES = [
  {schema: 'private_isg', table: 'workplaces', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'workplace_initializations', filter: user => `workplace_id in (${workplaceIds(user)})`},
  {schema: 'private_isg', table: 'departments', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'employees', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'pilot_training_sessions', filter: user => `owner_id=${quoteLiteral(user)}::uuid`},
  {schema: 'private_isg', table: 'pilot_training_session_revisions', filter: user => `session_id in (${trainingSessionIds(user)})`},
  {schema: 'private_isg', table: 'appointments', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'annual_work_plans', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'annual_work_plan_items', filter: user => `plan_id in (${annualPlanIds(user)})`},
  {schema: 'private_isg', table: 'equipment_items', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'equipment_inspection_rules', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'document_obligations', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'document_obligation_records', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'risk_assessments', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'risk_assessment_versions', filter: user => `assessment_id in (${riskAssessmentIds(user)})`},
  {schema: 'private_isg', table: 'risk_source_links', filter: user => `assessment_id in (${riskAssessmentIds(user)})`},
  {schema: 'private_isg', table: 'pilot_training_records', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'pilot_training_participants', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'nonconformities', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'nonconformity_details', filter: user => `nonconformity_id in (${nonconformityIds(user)})`},
  {schema: 'private_isg', table: 'nonconformity_actions', filter: user => `nonconformity_id in (${nonconformityIds(user)})`},
  {schema: 'private_isg', table: 'nonconformity_transitions', filter: user => `nonconformity_id in (${nonconformityIds(user)})`},
  {schema: 'private_isg', table: 'verification_records', filter: user => `nonconformity_id in (${nonconformityIds(user)})`},
  {schema: 'private_isg', table: 'pilot_finding_sources', filter: user => `nonconformity_id in (${nonconformityIds(user)})`},
  {schema: 'private_isg', table: 'module_record_links', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'workplace_context_versions', filter: user => `company_id in (${companyIds(user)})`},
  {schema: 'private_isg', table: 'process_record_meta', filter: user => `company_id in (${companyIds(user)})`},
];

const ALL_TABLES = [...TABLES, ...MODULE_TABLES];

async function columns(projectRef, descriptor) {
  return management(projectRef, `
    select column_name,is_generated,identity_generation,is_nullable,column_default
    from information_schema.columns
    where table_schema=${quoteLiteral(descriptor.schema)}
      and table_name=${quoteLiteral(descriptor.table)}
    order by ordinal_position;`);
}

function transformRows(rows, sourceUser, targetUser, descriptor = null) {
  const transformed = JSON.parse(JSON.stringify(rows).replaceAll(sourceUser, targetUser));
  if (descriptor?.schema === 'public' && descriptor.table === 'findings') {
    for (const row of transformed) {
      const unscored = row.is_scored === false
        || ['assurance_requirement', 'verification_request'].includes(row.item_class)
        || row.fk_probability == null || row.fk_frequency == null || row.fk_severity == null
        || row.m5_probability == null || row.m5_severity == null;
      if (unscored) {
        row.is_scored = false;
        if (!['assurance_requirement', 'verification_request'].includes(row.item_class)) {
          row.item_class = 'verification_request';
        }
        row.fk_probability = null;
        row.fk_frequency = null;
        row.fk_severity = null;
        row.fk_score = null;
        row.fk_band = 'unknown';
        row.m5_probability = null;
        row.m5_severity = null;
        row.m5_score = null;
        row.m5_band = 'unknown';
        row.needs_field_verification = true;
      } else {
        row.is_scored = true;
        row.item_class = 'observed_finding';
        row.fk_score ??= Number(row.fk_probability) * Number(row.fk_frequency) * Number(row.fk_severity);
        row.m5_score ??= Number(row.m5_probability) * Number(row.m5_severity);
      }
    }
  }
  if (descriptor?.schema === 'public' && descriptor.table === 'reports') {
    for (const row of transformed) {
      if (row.document_no) row.document_no = `${row.document_no}-MIG-${sourceUser.slice(0, 8).toUpperCase()}`;
    }
  }
  return transformed;
}

function batches(rows, maxBytes = 1_250_000) {
  const output = [];
  let current = [];
  let bytes = 2;
  for (const row of rows) {
    const size = Buffer.byteLength(JSON.stringify(row)) + 1;
    if (current.length && bytes + size > maxBytes) {
      output.push(current);
      current = [];
      bytes = 2;
    }
    current.push(row);
    bytes += size;
  }
  if (current.length) output.push(current);
  return output;
}

async function sourceRows(descriptor, sourceUser) {
  return management(PRODUCTION_REF, `
    select to_jsonb(t) as row
    from ${tableIdent(descriptor)} t
    where ${descriptor.filter(sourceUser)};`);
}

async function insertRows(descriptor, rows, commonColumns, sourceUser, targetUser) {
  if (!rows.length) return;
  const transformed = transformRows(rows.map(item => item.row), sourceUser, targetUser, descriptor);
  const effectiveColumns = commonColumns.filter(column => !(
    column.is_nullable === 'NO'
      && column.column_default != null
      && transformed.some(row => row[column.column_name] == null)
  ));
  const names = effectiveColumns.map(column => quoteIdent(column.column_name));
  const selection = effectiveColumns.map(column => `r.${quoteIdent(column.column_name)}`);
  const override = effectiveColumns.some(column => column.identity_generation === 'ALWAYS')
    ? ' overriding system value' : '';
  for (const batch of batches(transformed)) {
    const json = quoteLiteral(JSON.stringify(batch));
    const conflict = descriptor.schema === 'public' && descriptor.table === 'findings'
      ? `on conflict(id) do update set ${effectiveColumns
        .filter(column => column.column_name !== 'id')
        .map(column => `${quoteIdent(column.column_name)}=excluded.${quoteIdent(column.column_name)}`)
        .join(',')}`
      : 'on conflict do nothing';
    await management(STAGING_REF, `
      begin;
      set local session_replication_role='replica';
      insert into ${tableIdent(descriptor)} (${names.join(',')})${override}
      select ${selection.join(',')}
      from jsonb_populate_recordset(null::${tableIdent(descriptor)},${json}::jsonb) r
      ${conflict};
      commit;`);
  }
}

async function ensureProfileAndWorkspace(sourceUser, targetUser) {
  const source = await management(PRODUCTION_REF, `
    select to_jsonb(p) as row from public.profiles p where id=${quoteLiteral(sourceUser)}::uuid;`);
  if (source.length !== 1) throw new Error('SOURCE_PROFILE_MISSING');
  const profile = transformRows([source[0].row], sourceUser, targetUser)[0];
  const safe = [
    'full_name','initials','title','certificate_number','company_name','company_logo_url','phone',
    'preferred_method','avatar_url','app_language','preferred_content_locale','work_jurisdiction_country',
    'work_jurisdiction_region','safety_profile_id','safety_profile_version','legal_document_set','client_platform',
  ];
  const stageColumns = new Set((await columns(STAGING_REF, {schema: 'public', table: 'profiles'}))
    .map(column => column.column_name));
  const available = safe.filter(column => stageColumns.has(column) && Object.hasOwn(profile, column));
  const assignments = available.map(column => `${quoteIdent(column)}=src.${quoteIdent(column)}`);
  await management(STAGING_REF, `
    update public.profiles p set ${assignments.join(',')},tier='plus',daily_quota_used=0,
      daily_quota_reset_at=clock_timestamp(),subscription_period=null,subscription_renewal_at=null,
      updated_at=clock_timestamp()
    from (select * from jsonb_populate_record(null::public.profiles,
      ${quoteLiteral(JSON.stringify(profile))}::jsonb)) src
    where p.id=${quoteLiteral(targetUser)}::uuid;
    insert into private_isg.workspaces(kind,name,status,timezone,created_by_user_id,personal_owner_user_id)
      values('personal','Kişisel Çalışma Alanı','active','Europe/Istanbul',
        ${quoteLiteral(targetUser)}::uuid,${quoteLiteral(targetUser)}::uuid)
      on conflict do nothing;
    insert into private_isg.workspace_memberships(workspace_id,user_id,role,status)
      select id,${quoteLiteral(targetUser)}::uuid,'owner','active'
      from private_isg.workspaces
      where kind='personal' and personal_owner_user_id=${quoteLiteral(targetUser)}::uuid
      on conflict(workspace_id,user_id) do update set role='owner',status='active',suspended_at=null,ended_at=null;
    select id as workspace_id from private_isg.workspaces
      where kind='personal' and personal_owner_user_id=${quoteLiteral(targetUser)}::uuid;`);
  const rows = await management(STAGING_REF, `
    select id as workspace_id from private_isg.workspaces
    where kind='personal' and personal_owner_user_id=${quoteLiteral(targetUser)}::uuid;`);
  if (rows.length !== 1) throw new Error('TARGET_PERSONAL_WORKSPACE_MISSING');
  return rows[0].workspace_id;
}

async function bindCompaniesToWorkspace(targetUser, workspaceId) {
  await management(STAGING_REF, `
    update public.companies set workspace_id=${quoteLiteral(workspaceId)}::uuid
    where user_id=${quoteLiteral(targetUser)}::uuid and workspace_id is null;
    select count(*)::int as count from private_isg.workspace_companies
    where workspace_id=${quoteLiteral(workspaceId)}::uuid;`);
}

async function ensureStagingPilotAccess(targetUser) {
  const reference = 'staging/data-copy-20260921';
  await management(STAGING_REF, `
    begin;
    update private_isg.rollout set read_enabled=true,write_enabled=true;
    update private_isg.module_registry set read_enabled=true,write_enabled=true;
    update private_isg.workspace_rollout
      set read_enabled=true,write_enabled=true,updated_at=clock_timestamp()
      where feature<>'workspace_admin';
    update private_isg.workspace_domain_rollout
      set read_enabled=true,write_enabled=true,updated_at=clock_timestamp();
    insert into public.user_subscriptions(
      user_id,tier,source,status,revenuecat_app_user_id,product_id,entitlement_id,entitlement_ids,
      environment,current_period_ends_at,last_event_id,updated_at
    ) values (
      ${quoteLiteral(targetUser)}::uuid,'pro','staging_data_copy','active',
      ${quoteLiteral(`staging:${targetUser}`)},'riskdetected_pro_staging','riskdetected_pro',
      array['riskdetected_pro'],'staging',clock_timestamp()+interval '29 days',
      'staging-data-copy-20260921',clock_timestamp()
    ) on conflict(user_id) do update set
      tier='pro',source='staging_data_copy',status='active',
      revenuecat_app_user_id='staging:'||excluded.user_id::text,
      product_id='riskdetected_pro_staging',entitlement_id='riskdetected_pro',
      entitlement_ids=array['riskdetected_pro'],environment='staging',
      current_period_ends_at=clock_timestamp()+interval '29 days',
      last_event_id='staging-data-copy-20260921',store=null,store_transaction_id=null,
      updated_at=clock_timestamp();
    update public.profiles set tier='pro',subscription_period=null,subscription_renewal_at=null,
      updated_at=clock_timestamp() where id=${quoteLiteral(targetUser)}::uuid;
    insert into private_isg.p05_pilot_accounts(
      actor_id,read_enabled,write_enabled,approved_reference,created_at,expires_at,revoked_at
    ) values (${quoteLiteral(targetUser)}::uuid,true,true,${quoteLiteral(reference)},
      clock_timestamp(),clock_timestamp()+interval '29 days',null)
    on conflict(actor_id) do update set read_enabled=true,write_enabled=true,
      approved_reference=excluded.approved_reference,created_at=clock_timestamp(),
      expires_at=clock_timestamp()+interval '29 days',revoked_at=null;
    insert into private.analysis_result_hub_allowlist(user_id,enabled,note,created_at,updated_at)
      values (${quoteLiteral(targetUser)}::uuid,true,'Staging production-data validation',
        clock_timestamp(),clock_timestamp())
      on conflict(user_id) do update set enabled=true,note=excluded.note,
        updated_at=clock_timestamp();
    insert into private_isg.p05_pilot_company_origins(company_id,actor_id,mutation_id,request_sha256)
      select c.id,c.user_id,gen_random_uuid(),
        sha256(convert_to('staging-data-copy-20260921/'||c.id::text,'UTF8'))
      from public.companies c where c.user_id=${quoteLiteral(targetUser)}::uuid
      on conflict(company_id) do update set actor_id=excluded.actor_id,
        request_sha256=excluded.request_sha256;
    insert into private_isg.p05_pilot_grants(
      actor_id,company_id,approved_reference,created_at,expires_at,revoked_at
    ) select ${quoteLiteral(targetUser)}::uuid,c.id,${quoteLiteral(reference)},clock_timestamp(),
        clock_timestamp()+interval '29 days',null
      from public.companies c where c.user_id=${quoteLiteral(targetUser)}::uuid
      on conflict(actor_id,company_id) do update set
        approved_reference=excluded.approved_reference,created_at=clock_timestamp(),
        expires_at=clock_timestamp()+interval '29 days',revoked_at=null;
    commit;`);
}

async function objectRows(sourceUser) {
  return management(PRODUCTION_REF, `
    select bucket_id,name,metadata
    from storage.objects
    where owner_id::text=${quoteLiteral(sourceUser)} or owner::text=${quoteLiteral(sourceUser)}
    order by bucket_id,name;`);
}

const encodePath = path => path.split('/').map(encodeURIComponent).join('/');

async function copyStorage(sourceUser, targetUser, expected) {
  const sourceKey = serviceKey(PRODUCTION_REF);
  const targetKey = serviceKey(STAGING_REF);
  const sourceUrl = `https://${PRODUCTION_REF}.supabase.co`;
  const targetUrl = `https://${STAGING_REF}.supabase.co`;
  const existingRows = await management(STAGING_REF, `
    select bucket_id,name from storage.objects
    where owner_id::text=${quoteLiteral(targetUser)} or owner::text=${quoteLiteral(targetUser)}
      or name like ${quoteLiteral(`${targetUser}/%`)};`);
  const existing = new Set(existingRows.map(row => `${row.bucket_id}/${row.name}`));
  let copied = 0;
  let skipped = 0;
  let bytes = 0;

  async function transfer(object) {
    const targetName = object.name.replaceAll(sourceUser, targetUser);
    const key = `${object.bucket_id}/${targetName}`;
    if (existing.has(key)) { skipped += 1; return; }
    const download = await fetch(`${sourceUrl}/storage/v1/object/authenticated/${encodeURIComponent(object.bucket_id)}/${encodePath(object.name)}`, {
      headers: {apikey: sourceKey, authorization: `Bearer ${sourceKey}`},
      signal: AbortSignal.timeout(150_000),
    });
    if (!download.ok) throw new Error(`STORAGE_DOWNLOAD_${download.status}_${key}`);
    const body = new Uint8Array(await download.arrayBuffer());
    const contentType = object.metadata?.mimetype ?? object.metadata?.['content-type'] ?? 'application/octet-stream';
    const upload = await fetch(`${targetUrl}/storage/v1/object/${encodeURIComponent(object.bucket_id)}/${encodePath(targetName)}`, {
      method: 'POST',
      headers: {apikey: targetKey, authorization: `Bearer ${targetKey}`, 'content-type': contentType, 'x-upsert': 'false'},
      body,
      signal: AbortSignal.timeout(150_000),
    });
    if (!upload.ok) {
      const detail = await upload.text().catch(() => '');
      throw new Error(`STORAGE_UPLOAD_${upload.status}_${key}_${detail.slice(0, 250)}`);
    }
    copied += 1;
    bytes += body.byteLength;
    if (copied % 20 === 0) console.log(`storage ${copied}/${expected.length}`);
  }

  const queue = [...expected];
  const workers = Array.from({length: 4}, async () => {
    while (queue.length) await transfer(queue.shift());
  });
  await Promise.all(workers);
  await management(STAGING_REF, `
    update storage.objects set owner_id=${quoteLiteral(targetUser)},owner=${quoteLiteral(targetUser)}
    where name like ${quoteLiteral(`${targetUser}/%`)}
      and bucket_id in ('avatars','logos','photos','reports');`);
  return {source: expected.length, copied, skipped, bytes};
}

async function verify(sourceUser, targetUser, descriptors) {
  const result = [];
  for (const descriptor of descriptors) {
    const source = await management(PRODUCTION_REF, `select count(*)::int as count from ${tableIdent(descriptor)} where ${descriptor.filter(sourceUser)};`);
    const target = await management(STAGING_REF, `select count(*)::int as count from ${tableIdent(descriptor)} where ${descriptor.filter(targetUser)};`);
    result.push({table: `${descriptor.schema}.${descriptor.table}`, source: Number(source[0].count), target: Number(target[0].count)});
  }
  return result;
}

const source = await authUser(PRODUCTION_REF);
const target = await authUser(STAGING_REF);
const sourceObjects = await objectRows(source.id);
const descriptors = [];
const inventory = [];

for (const descriptor of ALL_TABLES) {
  const [sourceColumns, targetColumns] = await Promise.all([
    columns(PRODUCTION_REF, descriptor), columns(STAGING_REF, descriptor),
  ]);
  if (!sourceColumns.length || !targetColumns.length) continue;
  const targetByName = new Map(targetColumns.map(column => [column.column_name, column]));
  const common = sourceColumns
    .filter(column => targetByName.has(column.column_name))
    .map(column => ({...targetByName.get(column.column_name)}))
    .filter(column => column.is_generated === 'NEVER');
  const rows = await sourceRows(descriptor, source.id);
  descriptors.push({...descriptor, common});
  inventory.push({table: `${descriptor.schema}.${descriptor.table}`, rows: rows.length, common_columns: common.length});
  if (APPLY && rows.length) {
    await insertRows(descriptor, rows, common, source.id, target.id);
    console.log(`copied ${descriptor.schema}.${descriptor.table}: ${rows.length}`);
  }
}

let workspaceId = null;
let storage = {source: sourceObjects.length, copied: 0, skipped: 0, bytes: 0};
if (APPLY) {
  workspaceId = await ensureProfileAndWorkspace(source.id, target.id);
  // Company rows were inserted with triggers suppressed. This scope-only update
  // uses the deployed backfill exception and creates canonical workspace mirrors.
  await bindCompaniesToWorkspace(target.id, workspaceId);
  await ensureStagingPilotAccess(target.id);
  if (COPY_STORAGE) storage = await copyStorage(source.id, target.id, sourceObjects);
}

const verification = APPLY ? await verify(source.id, target.id, descriptors) : [];
const mismatches = verification.filter(row => row.source !== row.target);
const receipt = {
  mode: APPLY ? 'apply' : 'dry-run',
  production_ref: PRODUCTION_REF,
  staging_ref: STAGING_REF,
  email: EMAIL,
  source_user_id: source.id,
  target_user_id: target.id,
  workspace_id: workspaceId,
  inventory,
  storage,
  verification,
  mismatches,
  excluded: [
    'auth.password_hashes_and_sessions','push_device_tokens','billing_and_store_transactions',
    'subscription_events','paywall_telemetry','usage_telemetry','notification_delivery_history',
    'admin_overrides_and_user_engine_allowlists','provider_attempt_telemetry',
  ],
  completed_at: new Date().toISOString(),
};
receipt.sha256 = createHash('sha256').update(JSON.stringify(receipt)).digest('hex');
writeFileSync(RECEIPT_PATH, `${JSON.stringify(receipt, null, 2)}\n`);
chmodSync(RECEIPT_PATH, 0o600);
console.log(JSON.stringify({
  mode: receipt.mode,
  source_user_id: receipt.source_user_id,
  target_user_id: receipt.target_user_id,
  workspace_id: receipt.workspace_id,
  tables: inventory.filter(row => row.rows > 0).length,
  rows: inventory.reduce((sum, row) => sum + row.rows, 0),
  objects: storage,
  mismatches,
  receipt: RECEIPT_PATH,
  sha256: receipt.sha256,
}, null, 2));

if (mismatches.length) process.exitCode = 2;
