-- RiskDetected notification automation and Operations Center infrastructure.
-- Filename timestamp matches the production migration history entry.
--
-- This migration is additive and ships disabled. Existing transactional,
-- report, trial, progress, analysis, subscription and AI flows are unchanged.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- User preference, engagement heartbeat and notification-open tracking
-- ---------------------------------------------------------------------------

alter table public.notification_preferences
  add column if not exists app_reminders boolean;

update public.notification_preferences
set app_reminders = enabled
where app_reminders is null;

alter table public.notification_preferences
  alter column app_reminders set default true,
  alter column app_reminders set not null;

create table if not exists public.user_engagement_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_foreground_at timestamptz not null default now(),
  timezone text not null,
  locale text,
  authorization_status text not null,
  authorization_synced_at timestamptz not null default now(),
  app_version text,
  app_build text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_engagement_authorization_status_check
    check (
      authorization_status in (
        'not_determined',
        'denied',
        'authorized',
        'provisional',
        'ephemeral'
      )
    ),
  constraint user_engagement_timezone_length_check
    check (char_length(timezone) between 1 and 100),
  constraint user_engagement_locale_length_check
    check (locale is null or char_length(locale) <= 35),
  constraint user_engagement_app_version_length_check
    check (app_version is null or char_length(app_version) <= 40),
  constraint user_engagement_app_build_length_check
    check (app_build is null or char_length(app_build) <= 40)
);

create index if not exists user_engagement_last_foreground_idx
  on public.user_engagement_state (last_foreground_at);

alter table public.user_engagement_state enable row level security;
revoke all on table public.user_engagement_state from public, anon, authenticated;
grant select, insert, update, delete on table public.user_engagement_state to service_role;

alter table public.notification_events
  add column if not exists source text not null default 'transactional',
  add column if not exists job_id uuid,
  add column if not exists campaign_id uuid,
  add column if not exists template_id uuid,
  add column if not exists destination text,
  add column if not exists dedupe_key text,
  add column if not exists opened_at timestamptz,
  add column if not exists open_count integer not null default 0;

alter table public.notification_events
  drop constraint if exists notification_events_source_check;
alter table public.notification_events
  add constraint notification_events_source_check
  check (source in ('transactional', 'trial', 'progress', 'automation', 'manual'));

alter table public.notification_events
  drop constraint if exists notification_events_destination_check;
alter table public.notification_events
  add constraint notification_events_destination_check
  check (
    destination is null
    or destination in ('home', 'history', 'new_analysis', 'profile', 'reports')
  );

alter table public.notification_events
  drop constraint if exists notification_events_open_count_check;
alter table public.notification_events
  add constraint notification_events_open_count_check
  check (open_count >= 0);

create unique index if not exists notification_events_dedupe_key_unique
  on public.notification_events (dedupe_key)
  where dedupe_key is not null;

create index if not exists notification_events_kind_status_created_idx
  on public.notification_events (kind, status, created_at desc);

create index if not exists notification_events_opened_idx
  on public.notification_events (opened_at desc)
  where opened_at is not null;

create or replace function public.record_user_engagement_state_v1(
  p_timezone text,
  p_locale text default null,
  p_authorization_status text default 'not_determined',
  p_app_version text default null,
  p_app_build text default null
)
returns public.user_engagement_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_timezone text := btrim(coalesce(p_timezone, ''));
  v_authorization_status text := lower(btrim(coalesce(p_authorization_status, '')));
  v_now timestamptz := now();
  v_existing public.user_engagement_state;
  v_row public.user_engagement_state;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_timezone = ''
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names
       where name = v_timezone
     ) then
    raise exception 'invalid_timezone' using errcode = '22023';
  end if;

  if v_authorization_status not in (
    'not_determined',
    'denied',
    'authorized',
    'provisional',
    'ephemeral'
  ) then
    raise exception 'invalid_authorization_status' using errcode = '22023';
  end if;

  select * into v_existing
  from public.user_engagement_state
  where user_id = v_user_id;

  if found
     and v_existing.authorization_status = v_authorization_status
     and v_existing.updated_at > v_now - interval '1 minute' then
    return v_existing;
  end if;

  insert into public.user_engagement_state (
    user_id,
    last_foreground_at,
    timezone,
    locale,
    authorization_status,
    authorization_synced_at,
    app_version,
    app_build,
    created_at,
    updated_at
  )
  values (
    v_user_id,
    v_now,
    v_timezone,
    nullif(left(btrim(coalesce(p_locale, '')), 35), ''),
    v_authorization_status,
    v_now,
    nullif(left(btrim(coalesce(p_app_version, '')), 40), ''),
    nullif(left(btrim(coalesce(p_app_build, '')), 40), ''),
    v_now,
    v_now
  )
  on conflict (user_id) do update set
    last_foreground_at = case
      when public.user_engagement_state.last_foreground_at <= v_now - interval '6 hours'
        then v_now
      else public.user_engagement_state.last_foreground_at
    end,
    timezone = excluded.timezone,
    locale = excluded.locale,
    authorization_status = excluded.authorization_status,
    authorization_synced_at = v_now,
    app_version = excluded.app_version,
    app_build = excluded.app_build,
    updated_at = v_now
  returning * into v_row;

  if v_authorization_status = 'denied' then
    update public.push_device_tokens
    set notifications_enabled = false,
        last_failure_at = v_now,
        last_failure_reason = 'system_authorization_denied'
    where user_id = v_user_id
      and notifications_enabled = true;
  end if;

  return v_row;
end;
$$;

revoke all on function public.record_user_engagement_state_v1(
  text, text, text, text, text
) from public, anon;
grant execute on function public.record_user_engagement_state_v1(
  text, text, text, text, text
) to authenticated, service_role;

create or replace function public.record_notification_open_v1(
  p_notification_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_updated integer := 0;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  update public.notification_events
  set opened_at = coalesce(opened_at, now()),
      open_count = open_count + 1
  where id = p_notification_event_id
    and user_id = v_user_id;

  get diagnostics v_updated = row_count;
  return jsonb_build_object(
    'recorded', v_updated = 1,
    'event_id', p_notification_event_id
  );
end;
$$;

revoke all on function public.record_notification_open_v1(uuid)
  from public, anon;
grant execute on function public.record_notification_open_v1(uuid)
  to authenticated, service_role;

create or replace function public.set_notification_master_preference_v1(
  p_enabled boolean
)
returns public.notification_preferences
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.notification_preferences;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  insert into public.notification_preferences (
    user_id,
    enabled,
    analysis_complete,
    report_ready,
    account_updates,
    marketing,
    trial_reminder,
    progress_weekly_summary,
    progress_monthly_summary,
    progress_milestones,
    app_reminders
  )
  values (
    v_user_id,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled,
    false,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled
  )
  on conflict (user_id) do update set
    enabled = excluded.enabled
  returning * into v_row;

  update public.push_device_tokens
  set notifications_enabled = p_enabled
  where user_id = v_user_id
    and notifications_enabled is distinct from p_enabled;

  return v_row;
end;
$$;

revoke all on function public.set_notification_master_preference_v1(boolean)
  from public, anon;
grant execute on function public.set_notification_master_preference_v1(boolean)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Private automation configuration and durable delivery data
-- ---------------------------------------------------------------------------

create table if not exists private.notification_templates (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  title text not null,
  body text not null,
  destination text not null default 'home',
  status text not null default 'draft',
  variables jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_templates_key_check
    check (key ~ '^[a-z0-9][a-z0-9_]{2,79}$'),
  constraint notification_templates_title_check
    check (char_length(title) between 1 and 80),
  constraint notification_templates_body_check
    check (char_length(body) between 1 and 240),
  constraint notification_templates_destination_check
    check (destination in ('home', 'new_analysis', 'profile')),
  constraint notification_templates_status_check
    check (status in ('draft', 'active', 'archived')),
  constraint notification_templates_variables_check
    check (jsonb_typeof(variables) = 'array')
);

create table if not exists private.notification_rules (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  rule_type text not null,
  status text not null default 'draft',
  template_id uuid not null references private.notification_templates(id),
  current_version_id uuid,
  priority integer not null default 100,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_rules_key_check
    check (key ~ '^[a-z0-9][a-z0-9_]{2,79}$'),
  constraint notification_rules_type_check
    check (rule_type in ('first_analysis', 'inactivity')),
  constraint notification_rules_status_check
    check (status in ('draft', 'shadow', 'allowlist', 'active', 'paused', 'archived')),
  constraint notification_rules_priority_check
    check (priority between 1 and 1000)
);

create table if not exists private.notification_rule_versions (
  id uuid primary key default gen_random_uuid(),
  rule_id uuid not null references private.notification_rules(id) on delete cascade,
  version integer not null,
  conditions jsonb not null,
  template_snapshot jsonb not null,
  enabled_user_hashes text[] not null default '{}'::text[],
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  constraint notification_rule_versions_version_check check (version > 0),
  constraint notification_rule_versions_conditions_check
    check (jsonb_typeof(conditions) = 'object'),
  constraint notification_rule_versions_template_snapshot_check
    check (jsonb_typeof(template_snapshot) = 'object'),
  constraint notification_rule_versions_hash_count_check
    check (cardinality(enabled_user_hashes) <= 1000),
  unique (rule_id, version)
);

alter table private.notification_rules
  drop constraint if exists notification_rules_current_version_fk;
alter table private.notification_rules
  add constraint notification_rules_current_version_fk
  foreign key (current_version_id)
  references private.notification_rule_versions(id)
  on delete set null;

create table if not exists private.notification_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  status text not null default 'draft',
  template_id uuid references private.notification_templates(id) on delete set null,
  title text not null,
  body text not null,
  destination text not null default 'home',
  target_spec jsonb not null default '{"audience":"allowlist","user_hashes":[]}'::jsonb,
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_campaigns_status_check
    check (status in ('draft', 'scheduled', 'running', 'paused', 'cancelled', 'completed')),
  constraint notification_campaigns_title_check
    check (char_length(title) between 1 and 80),
  constraint notification_campaigns_body_check
    check (char_length(body) between 1 and 240),
  constraint notification_campaigns_destination_check
    check (destination in ('home', 'new_analysis', 'profile')),
  constraint notification_campaigns_target_spec_check
    check (jsonb_typeof(target_spec) = 'object')
);

create table if not exists private.notification_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  rule_id uuid references private.notification_rules(id) on delete cascade,
  rule_version_id uuid references private.notification_rule_versions(id) on delete cascade,
  campaign_id uuid references private.notification_campaigns(id) on delete cascade,
  template_id uuid references private.notification_templates(id) on delete set null,
  kind text not null,
  episode_key text not null,
  dedupe_key text not null unique,
  status text not null default 'pending',
  due_at timestamptz not null default now(),
  timezone text not null,
  title text not null,
  body text not null,
  destination text not null,
  payload_data jsonb not null default '{}'::jsonb,
  eligibility_snapshot jsonb not null default '{}'::jsonb,
  attempt_count integer not null default 0,
  claim_token uuid,
  claimed_at timestamptz,
  lease_expires_at timestamptz,
  notification_event_id uuid references public.notification_events(id) on delete set null,
  last_error_code text,
  last_error_text text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_jobs_owner_check
    check ((rule_id is not null)::integer + (campaign_id is not null)::integer = 1),
  constraint notification_jobs_kind_check
    check (kind in ('first_analysis_reminder', 'inactivity_reminder', 'manual_app_reminder')),
  constraint notification_jobs_status_check
    check (status in ('shadow', 'pending', 'claimed', 'sent', 'skipped', 'failed', 'cancelled', 'ambiguous')),
  constraint notification_jobs_attempt_count_check
    check (attempt_count between 0 and 3),
  constraint notification_jobs_title_check
    check (char_length(title) between 1 and 80),
  constraint notification_jobs_body_check
    check (char_length(body) between 1 and 240),
  constraint notification_jobs_destination_check
    check (destination in ('home', 'new_analysis', 'profile')),
  constraint notification_jobs_payload_check
    check (jsonb_typeof(payload_data) = 'object'),
  constraint notification_jobs_snapshot_check
    check (jsonb_typeof(eligibility_snapshot) = 'object')
);

alter table public.notification_events
  drop constraint if exists notification_events_job_fk;
alter table public.notification_events
  add constraint notification_events_job_fk
  foreign key (job_id) references private.notification_jobs(id) on delete set null;

alter table public.notification_events
  drop constraint if exists notification_events_campaign_fk;
alter table public.notification_events
  add constraint notification_events_campaign_fk
  foreign key (campaign_id) references private.notification_campaigns(id) on delete set null;

alter table public.notification_events
  drop constraint if exists notification_events_template_fk;
alter table public.notification_events
  add constraint notification_events_template_fk
  foreign key (template_id) references private.notification_templates(id) on delete set null;

create table if not exists private.notification_delivery_attempts (
  id bigint generated always as identity primary key,
  notification_event_id uuid not null references public.notification_events(id) on delete cascade,
  job_id uuid references private.notification_jobs(id) on delete set null,
  push_device_token_id uuid references public.push_device_tokens(id) on delete set null,
  environment text not null,
  attempt_number integer not null,
  outcome text not null,
  http_status integer,
  apns_id text,
  reason text,
  duration_ms integer,
  created_at timestamptz not null default now(),
  constraint notification_delivery_environment_check
    check (environment in ('sandbox', 'production')),
  constraint notification_delivery_attempt_check
    check (attempt_number between 1 and 3),
  constraint notification_delivery_outcome_check
    check (outcome in ('accepted', 'transient', 'permanent', 'ambiguous')),
  constraint notification_delivery_http_status_check
    check (http_status is null or http_status between 100 and 599),
  constraint notification_delivery_duration_check
    check (duration_ms is null or duration_ms >= 0),
  constraint notification_delivery_reason_length_check
    check (reason is null or char_length(reason) <= 500),
  unique (notification_event_id, push_device_token_id, attempt_number)
);

create index if not exists notification_rules_runtime_idx
  on private.notification_rules (status, priority, updated_at);

create unique index if not exists notification_rules_one_runtime_per_type
  on private.notification_rules (rule_type)
  where status in ('shadow', 'allowlist', 'active');

create index if not exists notification_templates_created_by_idx
  on private.notification_templates (created_by)
  where created_by is not null;

create index if not exists notification_rules_template_idx
  on private.notification_rules (template_id);

create index if not exists notification_rules_current_version_idx
  on private.notification_rules (current_version_id)
  where current_version_id is not null;

create index if not exists notification_rules_created_by_idx
  on private.notification_rules (created_by)
  where created_by is not null;

create index if not exists notification_rule_versions_created_by_idx
  on private.notification_rule_versions (created_by)
  where created_by is not null;

create index if not exists notification_campaigns_due_idx
  on private.notification_campaigns (status, scheduled_at)
  where status in ('scheduled', 'running');

create index if not exists notification_campaigns_template_idx
  on private.notification_campaigns (template_id)
  where template_id is not null;

create index if not exists notification_campaigns_created_by_idx
  on private.notification_campaigns (created_by)
  where created_by is not null;

create index if not exists notification_jobs_due_idx
  on private.notification_jobs (due_at, created_at)
  where status in ('pending', 'claimed');

create index if not exists notification_jobs_user_created_idx
  on private.notification_jobs (user_id, created_at desc);

create index if not exists notification_jobs_rule_status_idx
  on private.notification_jobs (rule_id, status, created_at desc);

create index if not exists notification_jobs_rule_version_idx
  on private.notification_jobs (rule_version_id)
  where rule_version_id is not null;

create index if not exists notification_jobs_campaign_status_idx
  on private.notification_jobs (campaign_id, status, created_at desc)
  where campaign_id is not null;

create unique index if not exists notification_jobs_active_episode_unique
  on private.notification_jobs (user_id, kind, episode_key)
  where status in ('pending', 'claimed', 'sent', 'ambiguous');

create index if not exists notification_jobs_template_idx
  on private.notification_jobs (template_id)
  where template_id is not null;

create index if not exists notification_jobs_event_idx
  on private.notification_jobs (notification_event_id)
  where notification_event_id is not null;

create index if not exists notification_delivery_event_idx
  on private.notification_delivery_attempts (notification_event_id, created_at);

create index if not exists notification_delivery_job_idx
  on private.notification_delivery_attempts (job_id)
  where job_id is not null;

create index if not exists notification_delivery_token_idx
  on private.notification_delivery_attempts (push_device_token_id)
  where push_device_token_id is not null;

create index if not exists notification_delivery_outcome_idx
  on private.notification_delivery_attempts (outcome, created_at desc);

create index if not exists notification_events_job_idx
  on public.notification_events (job_id)
  where job_id is not null;

create index if not exists notification_events_campaign_idx
  on public.notification_events (campaign_id)
  where campaign_id is not null;

create index if not exists notification_events_template_idx
  on public.notification_events (template_id)
  where template_id is not null;

alter table private.notification_templates enable row level security;
alter table private.notification_rules enable row level security;
alter table private.notification_rule_versions enable row level security;
alter table private.notification_campaigns enable row level security;
alter table private.notification_jobs enable row level security;
alter table private.notification_delivery_attempts enable row level security;

revoke all on all tables in schema private from public, anon, authenticated;
grant select, insert, update, delete on table
  private.notification_templates,
  private.notification_rules,
  private.notification_rule_versions,
  private.notification_campaigns,
  private.notification_jobs,
  private.notification_delivery_attempts
to service_role;
grant usage, select on sequence private.notification_delivery_attempts_id_seq
  to service_role;

-- ---------------------------------------------------------------------------
-- Runtime helpers and service-role RPCs
-- ---------------------------------------------------------------------------

create or replace function private.notification_user_hash(p_user_id uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(p_user_id::text, 'sha256'), 'hex');
$$;

revoke all on function private.notification_user_hash(uuid)
  from public, anon, authenticated;
grant execute on function private.notification_user_hash(uuid) to service_role;

create or replace function private.notification_feature_flag()
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value jsonb;
  v_rollout_mode text;
  v_percentage integer;
begin
  select value into v_value
  from public.app_feature_flags
  where key = 'engagement_notification_automation';

  if jsonb_typeof(v_value) is distinct from 'object'
     or coalesce(v_value->>'rollout_mode', '')
       not in ('off', 'allowlist', 'on')
     or jsonb_typeof(v_value->'enabled_user_hashes') is distinct from 'array'
     or jsonb_typeof(v_value->'kill_switch') is distinct from 'boolean' then
    raise exception 'invalid_notification_feature_flag';
  end if;

  v_rollout_mode := v_value->>'rollout_mode';
  v_percentage := case
    when v_value ? 'rollout_percentage'
      then (v_value->>'rollout_percentage')::integer
    when v_rollout_mode = 'on'
      then 100
    else 0
  end;

  if v_percentage not between 0 and 100 then
    raise exception 'invalid_notification_rollout_percentage';
  end if;

  return jsonb_build_object(
    'rollout_mode', v_rollout_mode,
    'enabled_user_hashes', v_value->'enabled_user_hashes',
    'rollout_percentage', v_percentage,
    'kill_switch', (v_value->>'kill_switch')::boolean
  );
exception
  when others then
    return '{
      "rollout_mode":"off",
      "enabled_user_hashes":[],
      "rollout_percentage":0,
      "kill_switch":true
    }'::jsonb;
end;
$$;

revoke all on function private.notification_feature_flag()
  from public, anon, authenticated;
grant execute on function private.notification_feature_flag() to service_role;

create or replace function private.notification_user_bucket(p_user_id uuid)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (
    get_byte(extensions.digest(p_user_id::text, 'sha256'), 0) * 256
    + get_byte(extensions.digest(p_user_id::text, 'sha256'), 1)
  ) % 100;
$$;

revoke all on function private.notification_user_bucket(uuid)
  from public, anon, authenticated;
grant execute on function private.notification_user_bucket(uuid)
  to service_role;

create or replace function private.notification_rollout_allows(
  p_flag jsonb,
  p_user_id uuid
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select
    coalesce((p_flag->>'kill_switch')::boolean, true) = false
    and (
      p_flag->>'rollout_mode' = 'on'
      and private.notification_user_bucket(p_user_id)
        < coalesce((p_flag->>'rollout_percentage')::integer, 100)
      or (
        p_flag->>'rollout_mode' = 'allowlist'
        and coalesce(p_flag->'enabled_user_hashes', '[]'::jsonb)
          ? private.notification_user_hash(p_user_id)
      )
    );
$$;

revoke all on function private.notification_rollout_allows(jsonb, uuid)
  from public, anon, authenticated;
grant execute on function private.notification_rollout_allows(jsonb, uuid)
  to service_role;

create or replace function public.record_notification_delivery_attempt_v1(
  p_notification_event_id uuid,
  p_job_id uuid,
  p_push_device_token_id uuid,
  p_environment text,
  p_attempt_number integer,
  p_outcome text,
  p_http_status integer default null,
  p_apns_id text default null,
  p_reason text default null,
  p_duration_ms integer default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  insert into private.notification_delivery_attempts (
    notification_event_id,
    job_id,
    push_device_token_id,
    environment,
    attempt_number,
    outcome,
    http_status,
    apns_id,
    reason,
    duration_ms
  )
  values (
    p_notification_event_id,
    p_job_id,
    p_push_device_token_id,
    p_environment,
    p_attempt_number,
    p_outcome,
    p_http_status,
    nullif(left(btrim(coalesce(p_apns_id, '')), 200), ''),
    nullif(left(btrim(coalesce(p_reason, '')), 500), ''),
    p_duration_ms
  )
  on conflict (
    notification_event_id,
    push_device_token_id,
    attempt_number
  ) do update set
    outcome = excluded.outcome,
    http_status = excluded.http_status,
    apns_id = excluded.apns_id,
    reason = excluded.reason,
    duration_ms = excluded.duration_ms
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.record_notification_delivery_attempt_v1(
  uuid, uuid, uuid, text, integer, text, integer, text, text, integer
) from public, anon, authenticated;
grant execute on function public.record_notification_delivery_attempt_v1(
  uuid, uuid, uuid, text, integer, text, integer, text, text, integer
) to service_role;

create or replace function public.enqueue_notification_jobs_v1(
  p_now timestamptz default now(),
  p_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_flag jsonb := private.notification_feature_flag();
  v_limit integer := greatest(1, least(coalesce(p_limit, 500), 2000));
  v_first_analysis integer := 0;
  v_inactivity integer := 0;
  v_manual integer := 0;
  v_shadow integer := 0;
begin
  if coalesce((v_flag->>'kill_switch')::boolean, true)
     or coalesce(v_flag->>'rollout_mode', 'off') = 'off' then
    return jsonb_build_object(
      'enabled', false,
      'reason', case
        when coalesce((v_flag->>'kill_switch')::boolean, true)
          then 'kill_switch'
        else 'rollout_off'
      end,
      'first_analysis', 0,
      'inactivity', 0,
      'manual', 0,
      'shadow', 0
    );
  end if;

  with runtime_rules as (
    select
      r.id as rule_id,
      r.rule_type,
      r.status as rule_status,
      r.template_id,
      rv.id as rule_version_id,
      rv.version,
      rv.conditions,
      rv.enabled_user_hashes,
      coalesce(rv.template_snapshot->>'title', t.title) as title,
      coalesce(rv.template_snapshot->>'body', t.body) as body,
      coalesce(
        rv.template_snapshot->>'destination',
        t.destination
      ) as destination
    from private.notification_rules r
    join private.notification_rule_versions rv
      on rv.id = r.current_version_id
    join private.notification_templates t
      on t.id = r.template_id
    where r.rule_type = 'first_analysis'
      and r.status in ('shadow', 'allowlist', 'active')
      and t.status = 'active'
  ),
  eligible_users as (
    select
      e.user_id,
      e.timezone,
      coalesce(o.completed_at, u.created_at) as onboarding_anchor
    from public.user_engagement_state e
    join auth.users u on u.id = e.user_id
    left join public.user_onboarding_answers o on o.user_id = e.user_id
    join public.notification_preferences p on p.user_id = e.user_id
    where p.enabled
      and p.app_reminders
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and exists (
        select 1
        from public.push_device_tokens dt
        where dt.user_id = e.user_id
          and dt.environment = 'production'
          and dt.notifications_enabled
      )
      and (p_now at time zone e.timezone)::time >= time '10:00'
      and (p_now at time zone e.timezone)::time < time '20:00'
      and private.notification_rollout_allows(v_flag, e.user_id)
      and not exists (
        select 1
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '24 hours'
      )
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '7 days'
      ) < 1
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '30 days'
      ) < 2
  ),
  candidates as (
    select rr.*, eu.*
    from runtime_rules rr
    cross join eligible_users eu
    where p_now >= eu.onboarding_anchor + (
      case
        when jsonb_typeof(rr.conditions->'min_hours') = 'number'
          then (rr.conditions->>'min_hours')::numeric
        else 24
      end
    ) * interval '1 hour'
      and p_now < eu.onboarding_anchor + (
        case
          when jsonb_typeof(rr.conditions->'max_hours') = 'number'
            then (rr.conditions->>'max_hours')::numeric
          else 72
        end
      ) * interval '1 hour'
      and (
        rr.rule_status <> 'allowlist'
        or private.notification_user_hash(eu.user_id)
          = any(rr.enabled_user_hashes)
      )
      and not exists (
        select 1
        from public.analyses a
        where a.user_id = eu.user_id
          and (
            a.status::text <> 'pending'
            or a.queued_at is not null
            or a.worker_started_at is not null
          )
      )
      and not exists (
        select 1
        from private.notification_jobs existing_job
        where existing_job.user_id = eu.user_id
          and existing_job.kind = 'first_analysis_reminder'
          and existing_job.status = 'sent'
      )
      and not exists (
        select 1
        from public.notification_events sent_event
        where sent_event.user_id = eu.user_id
          and sent_event.kind = 'first_analysis_reminder'
          and sent_event.status = 'sent'
      )
    order by eu.onboarding_anchor
    limit v_limit
  ),
  inserted as (
    insert into private.notification_jobs (
      user_id,
      rule_id,
      rule_version_id,
      template_id,
      kind,
      episode_key,
      dedupe_key,
      status,
      due_at,
      timezone,
      title,
      body,
      destination,
      payload_data,
      eligibility_snapshot
    )
    select
      c.user_id,
      c.rule_id,
      c.rule_version_id,
      c.template_id,
      'first_analysis_reminder',
      'lifetime',
      concat(
        case when c.rule_status = 'shadow' then 'shadow:' else 'send:' end,
        c.rule_id::text,
        ':',
        c.rule_version_id::text,
        ':',
        c.user_id::text,
        ':lifetime'
      ),
      case when c.rule_status = 'shadow' then 'shadow' else 'pending' end,
      p_now,
      c.timezone,
      c.title,
      c.body,
      c.destination,
      jsonb_build_object(
        'destination', c.destination,
        'event', 'first_analysis_reminder'
      ),
      jsonb_build_object(
        'evaluated_at', p_now,
        'onboarding_anchor', c.onboarding_anchor,
        'rule_version', c.version
      )
    from candidates c
    on conflict do nothing
    returning status
  )
  select
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'shadow')
  into v_first_analysis, v_shadow
  from inserted;

  with runtime_rules as (
    select
      r.id as rule_id,
      r.rule_type,
      r.status as rule_status,
      r.template_id,
      rv.id as rule_version_id,
      rv.version,
      rv.conditions,
      rv.enabled_user_hashes,
      coalesce(rv.template_snapshot->>'title', t.title) as title,
      coalesce(rv.template_snapshot->>'body', t.body) as body,
      coalesce(
        rv.template_snapshot->>'destination',
        t.destination
      ) as destination
    from private.notification_rules r
    join private.notification_rule_versions rv
      on rv.id = r.current_version_id
    join private.notification_templates t
      on t.id = r.template_id
    where r.rule_type = 'inactivity'
      and r.status in ('shadow', 'allowlist', 'active')
      and t.status = 'active'
  ),
  user_activity as (
    select
      e.user_id,
      e.timezone,
      greatest(
        e.last_foreground_at,
        coalesce(
          (
            select max(greatest(a.updated_at, coalesce(a.completed_at, a.created_at)))
            from public.analyses a
            where a.user_id = e.user_id
              and a.status::text = 'completed'
          ),
          '-infinity'::timestamptz
        ),
        coalesce(
          (
            select max(r.created_at)
            from public.reports r
            where r.user_id = e.user_id
          ),
          '-infinity'::timestamptz
        )
      ) as last_meaningful_activity_at
    from public.user_engagement_state e
    join public.notification_preferences p on p.user_id = e.user_id
    where p.enabled
      and p.app_reminders
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and exists (
        select 1
        from public.push_device_tokens dt
        where dt.user_id = e.user_id
          and dt.environment = 'production'
          and dt.notifications_enabled
      )
      and exists (
        select 1
        from public.analyses a
        where a.user_id = e.user_id
          and a.status::text = 'completed'
      )
      and (p_now at time zone e.timezone)::time >= time '10:00'
      and (p_now at time zone e.timezone)::time < time '20:00'
      and private.notification_rollout_allows(v_flag, e.user_id)
      and not exists (
        select 1
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '24 hours'
      )
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '7 days'
      ) < 1
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '30 days'
      ) < 2
  ),
  candidates as (
    select rr.*, ua.*
    from runtime_rules rr
    cross join user_activity ua
    where ua.last_meaningful_activity_at <= p_now - (
      case
        when jsonb_typeof(rr.conditions->'inactivity_days') = 'number'
          then (rr.conditions->>'inactivity_days')::numeric
        else 5
      end
    ) * interval '1 day'
      and (
        rr.rule_status <> 'allowlist'
        or private.notification_user_hash(ua.user_id)
          = any(rr.enabled_user_hashes)
      )
      and not exists (
        select 1
        from private.notification_jobs existing_job
        where existing_job.user_id = ua.user_id
          and existing_job.kind = 'inactivity_reminder'
          and existing_job.episode_key =
            extract(epoch from ua.last_meaningful_activity_at)::bigint::text
          and existing_job.status in ('pending', 'claimed', 'sent', 'ambiguous')
      )
      and not exists (
        select 1
        from public.notification_events sent_event
        join private.notification_jobs event_job
          on event_job.id = sent_event.job_id
        where sent_event.user_id = ua.user_id
          and sent_event.kind = 'inactivity_reminder'
          and sent_event.status = 'sent'
          and event_job.episode_key =
            extract(epoch from ua.last_meaningful_activity_at)::bigint::text
      )
    order by ua.last_meaningful_activity_at
    limit v_limit
  ),
  inserted as (
    insert into private.notification_jobs (
      user_id,
      rule_id,
      rule_version_id,
      template_id,
      kind,
      episode_key,
      dedupe_key,
      status,
      due_at,
      timezone,
      title,
      body,
      destination,
      payload_data,
      eligibility_snapshot
    )
    select
      c.user_id,
      c.rule_id,
      c.rule_version_id,
      c.template_id,
      'inactivity_reminder',
      extract(epoch from c.last_meaningful_activity_at)::bigint::text,
      concat(
        case when c.rule_status = 'shadow' then 'shadow:' else 'send:' end,
        c.rule_id::text,
        ':',
        c.rule_version_id::text,
        ':',
        c.user_id::text,
        ':',
        extract(epoch from c.last_meaningful_activity_at)::bigint::text
      ),
      case when c.rule_status = 'shadow' then 'shadow' else 'pending' end,
      p_now,
      c.timezone,
      c.title,
      c.body,
      c.destination,
      jsonb_build_object(
        'destination', c.destination,
        'event', 'inactivity_reminder'
      ),
      jsonb_build_object(
        'evaluated_at', p_now,
        'last_meaningful_activity_at', c.last_meaningful_activity_at,
        'rule_version', c.version
      )
    from candidates c
    on conflict do nothing
    returning status
  )
  select
    count(*) filter (where status = 'pending'),
    v_shadow + count(*) filter (where status = 'shadow')
  into v_inactivity, v_shadow
  from inserted;

  with due_campaigns as (
    select c.*
    from private.notification_campaigns c
    where c.status in ('scheduled', 'running')
      and c.scheduled_at is not null
      and c.scheduled_at <= p_now
    order by c.scheduled_at
  ),
  eligible_users as (
    select e.user_id, e.timezone
    from public.user_engagement_state e
    join public.notification_preferences p on p.user_id = e.user_id
    where p.enabled
      and p.app_reminders
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and exists (
        select 1
        from public.push_device_tokens dt
        where dt.user_id = e.user_id
          and dt.environment = 'production'
          and dt.notifications_enabled
      )
      and (p_now at time zone e.timezone)::time >= time '10:00'
      and (p_now at time zone e.timezone)::time < time '20:00'
      and private.notification_rollout_allows(v_flag, e.user_id)
      and not exists (
        select 1
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '24 hours'
      )
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '7 days'
      ) < 1
      and (
        select count(*)
        from public.notification_events ne
        where ne.user_id = e.user_id
          and ne.kind in (
            'first_analysis_reminder',
            'inactivity_reminder',
            'manual_app_reminder'
          )
          and ne.status = 'sent'
          and ne.created_at > p_now - interval '30 days'
      ) < 2
  ),
  candidates as (
    select dc.*, eu.user_id, eu.timezone
    from due_campaigns dc
    cross join eligible_users eu
    where (
      dc.target_spec->>'audience' = 'all_eligible'
      or (
        dc.target_spec->>'audience' = 'allowlist'
        and coalesce(dc.target_spec->'user_hashes', '[]'::jsonb)
          ? private.notification_user_hash(eu.user_id)
      )
    )
      and not exists (
        select 1
        from private.notification_jobs existing_job
        where existing_job.campaign_id = dc.id
          and existing_job.user_id = eu.user_id
      )
    order by dc.scheduled_at, eu.user_id
    limit v_limit
  ),
  inserted as (
    insert into private.notification_jobs (
      user_id,
      campaign_id,
      template_id,
      kind,
      episode_key,
      dedupe_key,
      status,
      due_at,
      timezone,
      title,
      body,
      destination,
      payload_data,
      eligibility_snapshot
    )
    select
      c.user_id,
      c.id,
      c.template_id,
      'manual_app_reminder',
      c.id::text,
      concat('campaign:', c.id::text, ':', c.user_id::text),
      'pending',
      p_now,
      c.timezone,
      c.title,
      c.body,
      c.destination,
      jsonb_build_object(
        'destination', c.destination,
        'event', 'manual_app_reminder'
      ),
      jsonb_build_object(
        'evaluated_at', p_now,
        'campaign_id', c.id
      )
    from candidates c
    on conflict do nothing
    returning campaign_id
  )
  select count(*) into v_manual from inserted;

  update private.notification_campaigns c
  set status = 'running',
      started_at = coalesce(started_at, p_now),
      updated_at = p_now
  where c.status = 'scheduled'
    and c.scheduled_at <= p_now
    and exists (
      select 1
      from private.notification_jobs j
      where j.campaign_id = c.id
    );

  return jsonb_build_object(
    'enabled', true,
    'rollout_mode', v_flag->>'rollout_mode',
    'first_analysis', v_first_analysis,
    'inactivity', v_inactivity,
    'manual', v_manual,
    'shadow', v_shadow
  );
end;
$$;

revoke all on function public.enqueue_notification_jobs_v1(
  timestamptz, integer
) from public, anon, authenticated;
grant execute on function public.enqueue_notification_jobs_v1(
  timestamptz, integer
) to service_role;

create or replace function public.claim_notification_jobs_v1(
  p_now timestamptz default now(),
  p_limit integer default 50,
  p_lease_seconds integer default 300
)
returns table (
  job_id uuid,
  claim_token uuid,
  user_id uuid,
  rule_id uuid,
  rule_version_id uuid,
  campaign_id uuid,
  template_id uuid,
  kind text,
  title text,
  body text,
  destination text,
  payload_data jsonb,
  dedupe_key text,
  attempt_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_flag jsonb := private.notification_feature_flag();
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
  v_lease_seconds integer := greatest(60, least(coalesce(p_lease_seconds, 300), 900));
begin
  update private.notification_jobs j
  set status = 'failed',
      claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      completed_at = p_now,
      last_error_code = 'max_attempts_after_lease_expiry',
      last_error_text = null,
      updated_at = p_now
  where j.status = 'claimed'
    and j.lease_expires_at <= p_now
    and j.attempt_count >= 3;

  if coalesce((v_flag->>'kill_switch')::boolean, true)
     or coalesce(v_flag->>'rollout_mode', 'off') = 'off' then
    return;
  end if;

  return query
  with claimable as (
    select j.id
    from private.notification_jobs j
    left join private.notification_rules r on r.id = j.rule_id
    left join private.notification_campaigns c on c.id = j.campaign_id
    where (
      j.status = 'pending'
      or (
        j.status = 'claimed'
        and j.lease_expires_at <= p_now
      )
    )
      and j.due_at <= p_now
      and j.attempt_count < 3
      and (
        (j.rule_id is not null and r.status in ('allowlist', 'active'))
        or
        (j.campaign_id is not null and c.status in ('scheduled', 'running'))
      )
    order by j.due_at, j.created_at
    for update of j skip locked
    limit v_limit
  ),
  claimed as (
    update private.notification_jobs j
    set status = 'claimed',
        claim_token = gen_random_uuid(),
        claimed_at = p_now,
        lease_expires_at = p_now + make_interval(secs => v_lease_seconds),
        attempt_count = j.attempt_count + 1,
        updated_at = p_now
    from claimable c
    where j.id = c.id
    returning j.*
  )
  select
    c.id,
    c.claim_token,
    c.user_id,
    c.rule_id,
    c.rule_version_id,
    c.campaign_id,
    c.template_id,
    c.kind,
    c.title,
    c.body,
    c.destination,
    c.payload_data,
    c.dedupe_key,
    c.attempt_count
  from claimed c;
end;
$$;

revoke all on function public.claim_notification_jobs_v1(
  timestamptz, integer, integer
) from public, anon, authenticated;
grant execute on function public.claim_notification_jobs_v1(
  timestamptz, integer, integer
) to service_role;

create or replace function public.validate_notification_job_v1(
  p_job_id uuid,
  p_claim_token uuid,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.notification_jobs;
  v_flag jsonb := private.notification_feature_flag();
  v_rule_status text;
  v_campaign_status text;
  v_last_meaningful_activity timestamptz;
  v_onboarding_anchor timestamptz;
  v_existing_sent_event_id uuid;
  v_reason text;
  v_defer_until timestamptz;
begin
  select * into v_job
  from private.notification_jobs
  where id = p_job_id
  for update;

  if not found
     or v_job.status <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token then
    return jsonb_build_object('allowed', false, 'reason', 'lost_claim');
  end if;

  if v_job.lease_expires_at <= p_now then
    return jsonb_build_object('allowed', false, 'reason', 'lease_expired');
  end if;

  select ne.id into v_existing_sent_event_id
  from public.notification_events ne
  where ne.job_id = v_job.id
    and ne.status = 'sent'
  order by ne.created_at
  limit 1;

  if v_existing_sent_event_id is not null then
    update private.notification_jobs
    set status = 'sent',
        notification_event_id = v_existing_sent_event_id,
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        completed_at = p_now,
        last_error_code = 'already_delivered_current_job',
        last_error_text = null,
        updated_at = p_now
    where id = p_job_id
      and claim_token = p_claim_token;

    return jsonb_build_object(
      'allowed', false,
      'reason', 'already_delivered_current_job',
      'event_id', v_existing_sent_event_id
    );
  end if;

  if coalesce((v_flag->>'kill_switch')::boolean, true)
     or coalesce(v_flag->>'rollout_mode', 'off') = 'off'
     or not private.notification_rollout_allows(v_flag, v_job.user_id) then
    v_reason := 'automation_disabled';
  end if;

  if v_reason is null and v_job.rule_id is not null then
    select status into v_rule_status
    from private.notification_rules
    where id = v_job.rule_id;
    if v_rule_status = 'paused' then
      v_reason := 'rule_paused';
    elsif v_rule_status not in ('allowlist', 'active') then
      v_reason := 'rule_inactive';
    end if;
  end if;

  if v_reason is null and v_job.campaign_id is not null then
    select status into v_campaign_status
    from private.notification_campaigns
    where id = v_job.campaign_id;
    if v_campaign_status = 'paused' then
      v_reason := 'campaign_paused';
    elsif v_campaign_status not in ('scheduled', 'running') then
      v_reason := 'campaign_inactive';
    end if;
  end if;

  if v_reason is null and not exists (
    select 1
    from public.notification_preferences p
    where p.user_id = v_job.user_id
      and p.enabled
      and p.app_reminders
  ) then
    v_reason := 'user_preference_disabled';
  end if;

  if v_reason is null and not exists (
    select 1
    from public.user_engagement_state e
    where e.user_id = v_job.user_id
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and e.timezone = v_job.timezone
  ) then
    v_reason := 'authorization_or_timezone_changed';
  end if;

  if v_reason is null and (
    (p_now at time zone v_job.timezone)::time < time '10:00'
    or (p_now at time zone v_job.timezone)::time >= time '20:00'
  ) then
    v_reason := 'outside_local_window';
    v_defer_until := (
      case
        when (p_now at time zone v_job.timezone)::time < time '10:00'
          then (p_now at time zone v_job.timezone)::date
        else (p_now at time zone v_job.timezone)::date + 1
      end + time '10:00'
    ) at time zone v_job.timezone;
  end if;

  if v_reason is null and not exists (
    select 1
    from public.push_device_tokens dt
    where dt.user_id = v_job.user_id
      and dt.environment = 'production'
      and dt.notifications_enabled
  ) then
    v_reason := 'no_active_production_token';
  end if;

  if v_reason is null and exists (
    select 1
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '24 hours'
  ) then
    v_reason := 'recent_push';
    select max(ne.created_at) + interval '24 hours 1 second'
    into v_defer_until
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '24 hours';
  end if;

  if v_reason is null and (
    select count(*)
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.kind in (
        'first_analysis_reminder',
        'inactivity_reminder',
        'manual_app_reminder'
      )
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '7 days'
  ) >= 1 then
    v_reason := 'frequency_cap_7d';
    select max(ne.created_at) + interval '7 days 1 second'
    into v_defer_until
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.kind in (
        'first_analysis_reminder',
        'inactivity_reminder',
        'manual_app_reminder'
      )
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '7 days';
  end if;

  if v_reason is null and (
    select count(*)
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.kind in (
        'first_analysis_reminder',
        'inactivity_reminder',
        'manual_app_reminder'
      )
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '30 days'
  ) >= 2 then
    v_reason := 'frequency_cap_30d';
    select min(ne.created_at) + interval '30 days 1 second'
    into v_defer_until
    from public.notification_events ne
    where ne.user_id = v_job.user_id
      and ne.kind in (
        'first_analysis_reminder',
        'inactivity_reminder',
        'manual_app_reminder'
      )
      and ne.status = 'sent'
      and ne.created_at > p_now - interval '30 days';
  end if;

  if v_reason is null and v_job.kind = 'first_analysis_reminder' then
    select coalesce(o.completed_at, u.created_at)
    into v_onboarding_anchor
    from auth.users u
    left join public.user_onboarding_answers o on o.user_id = u.id
    where u.id = v_job.user_id;

    if v_onboarding_anchor is null
       or p_now < v_onboarding_anchor + interval '24 hours'
       or p_now >= v_onboarding_anchor + interval '72 hours' then
      v_reason := 'first_analysis_window_closed';
    elsif exists (
      select 1
      from public.notification_events ne
      where ne.user_id = v_job.user_id
        and ne.kind = 'first_analysis_reminder'
        and ne.status = 'sent'
    ) then
      v_reason := 'first_analysis_already_sent';
    elsif exists (
      select 1
      from public.analyses a
      where a.user_id = v_job.user_id
        and (
          a.status::text <> 'pending'
          or a.queued_at is not null
          or a.worker_started_at is not null
        )
    ) then
      v_reason := 'analysis_submitted';
    end if;
  end if;

  if v_reason is null and v_job.kind = 'inactivity_reminder' then
    select greatest(
      e.last_foreground_at,
      coalesce(
        (
          select max(greatest(a.updated_at, coalesce(a.completed_at, a.created_at)))
          from public.analyses a
          where a.user_id = v_job.user_id
            and a.status::text = 'completed'
        ),
        '-infinity'::timestamptz
      ),
      coalesce(
        (
          select max(r.created_at)
          from public.reports r
          where r.user_id = v_job.user_id
        ),
        '-infinity'::timestamptz
      )
    )
    into v_last_meaningful_activity
    from public.user_engagement_state e
    where e.user_id = v_job.user_id;

    if v_last_meaningful_activity is null
       or v_last_meaningful_activity > p_now - interval '5 days'
       or extract(epoch from v_last_meaningful_activity)::bigint::text
          <> v_job.episode_key then
      v_reason := 'inactivity_episode_changed';
    elsif exists (
      select 1
      from public.notification_events ne
      join private.notification_jobs prior_job
        on prior_job.id = ne.job_id
      where ne.user_id = v_job.user_id
        and ne.kind = 'inactivity_reminder'
        and ne.status = 'sent'
        and prior_job.episode_key = v_job.episode_key
        and prior_job.id <> v_job.id
    ) then
      v_reason := 'inactivity_episode_already_sent';
    end if;
  end if;

  if v_reason in (
    'automation_disabled',
    'rule_paused',
    'campaign_paused',
    'outside_local_window',
    'recent_push',
    'frequency_cap_7d',
    'frequency_cap_30d'
  ) then
    v_defer_until := greatest(
      coalesce(v_defer_until, p_now + interval '15 minutes'),
      p_now + interval '1 minute'
    );

    update private.notification_jobs
    set status = 'pending',
        due_at = v_defer_until,
        attempt_count = greatest(attempt_count - 1, 0),
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        completed_at = null,
        last_error_code = v_reason,
        last_error_text = null,
        updated_at = p_now
    where id = p_job_id
      and claim_token = p_claim_token;

    return jsonb_build_object(
      'allowed', false,
      'reason', v_reason,
      'deferred', true,
      'due_at', v_defer_until
    );
  end if;

  if v_reason is not null then
    update private.notification_jobs
    set status = case
          when v_reason in ('rule_inactive', 'campaign_inactive')
            then 'cancelled'
          else 'skipped'
        end,
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        completed_at = p_now,
        last_error_code = v_reason,
        last_error_text = null,
        updated_at = p_now
    where id = p_job_id
      and claim_token = p_claim_token;

    return jsonb_build_object('allowed', false, 'reason', v_reason);
  end if;

  return jsonb_build_object(
    'allowed', true,
    'reason', 'allowed',
    'job_id', v_job.id,
    'attempt_count', v_job.attempt_count
  );
end;
$$;

revoke all on function public.validate_notification_job_v1(
  uuid, uuid, timestamptz
) from public, anon, authenticated;
grant execute on function public.validate_notification_job_v1(
  uuid, uuid, timestamptz
) to service_role;

create or replace function public.complete_notification_job_v1(
  p_job_id uuid,
  p_claim_token uuid,
  p_result text,
  p_notification_event_id uuid default null,
  p_retryable boolean default false,
  p_error_code text default null,
  p_error_text text default null,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.notification_jobs;
  v_next_status text;
  v_next_due timestamptz;
begin
  select * into v_job
  from private.notification_jobs
  where id = p_job_id
  for update;

  if not found
     or v_job.status <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token then
    return jsonb_build_object('updated', false, 'reason', 'lost_claim');
  end if;

  if p_result not in ('sent', 'skipped', 'failed', 'ambiguous') then
    raise exception 'invalid_job_result' using errcode = '22023';
  end if;

  if p_result = 'failed' and p_retryable and v_job.attempt_count < 3 then
    v_next_status := 'pending';
    v_next_due := p_now + make_interval(
      secs => case v_job.attempt_count
        when 1 then 300
        when 2 then 900
        else 1800
      end
    );
  else
    v_next_status := p_result;
    v_next_due := v_job.due_at;
  end if;

  update private.notification_jobs
  set status = v_next_status,
      due_at = v_next_due,
      notification_event_id = coalesce(
        p_notification_event_id,
        notification_event_id
      ),
      claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      completed_at = case
        when v_next_status in ('sent', 'skipped', 'failed', 'ambiguous')
          then p_now
        else null
      end,
      last_error_code = nullif(left(btrim(coalesce(p_error_code, '')), 100), ''),
      last_error_text = nullif(left(btrim(coalesce(p_error_text, '')), 500), ''),
      updated_at = p_now
  where id = p_job_id
    and claim_token = p_claim_token;

  return jsonb_build_object(
    'updated', true,
    'status', v_next_status,
    'attempt_count', v_job.attempt_count,
    'next_due_at', v_next_due
  );
end;
$$;

revoke all on function public.complete_notification_job_v1(
  uuid, uuid, text, uuid, boolean, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.complete_notification_job_v1(
  uuid, uuid, text, uuid, boolean, text, text, timestamptz
) to service_role;

-- ---------------------------------------------------------------------------
-- Operations Center service-only contracts
-- ---------------------------------------------------------------------------

create or replace function private.notification_admin_has_scope(
  p_actor_user_id uuid,
  p_scope text
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_users au
    where au.user_id = p_actor_user_id
      and au.is_active
      and (
        '*' = any(au.allowed_scopes)
        or p_scope = any(au.allowed_scopes)
      )
  );
$$;

revoke all on function private.notification_admin_has_scope(uuid, text)
  from public, anon, authenticated;
grant execute on function private.notification_admin_has_scope(uuid, text)
  to service_role;

create or replace function private.notification_conditions_valid(
  p_rule_type text,
  p_conditions jsonb
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
begin
  if jsonb_typeof(p_conditions) <> 'object' then
    return false;
  end if;

  for v_key in select jsonb_object_keys(p_conditions)
  loop
    if p_rule_type = 'first_analysis'
       and v_key not in ('min_hours', 'max_hours') then
      return false;
    elsif p_rule_type = 'inactivity'
       and v_key not in ('inactivity_days') then
      return false;
    end if;
  end loop;

  if p_rule_type = 'first_analysis' then
    return jsonb_typeof(p_conditions->'min_hours') = 'number'
      and jsonb_typeof(p_conditions->'max_hours') = 'number'
      and (p_conditions->>'min_hours')::numeric between 1 and 168
      and (p_conditions->>'max_hours')::numeric between 2 and 336
      and (p_conditions->>'max_hours')::numeric
        > (p_conditions->>'min_hours')::numeric;
  end if;

  if p_rule_type = 'inactivity' then
    return jsonb_typeof(p_conditions->'inactivity_days') = 'number'
      and (p_conditions->>'inactivity_days')::numeric between 1 and 90;
  end if;

  return false;
exception
  when others then
    return false;
end;
$$;

revoke all on function private.notification_conditions_valid(text, jsonb)
  from public, anon, authenticated;
grant execute on function private.notification_conditions_valid(text, jsonb)
  to service_role;

create or replace function public.admin_notification_snapshot_v1(
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not private.notification_admin_has_scope(
    p_actor_user_id,
    'notifications.read'
  ) then
    raise exception 'admin_scope_required:notifications.read'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'feature_flag', private.notification_feature_flag(),
    'rules', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'key', r.key,
            'name', r.name,
            'rule_type', r.rule_type,
            'status', r.status,
            'priority', r.priority,
            'template_id', r.template_id,
            'current_version_id', r.current_version_id,
            'version', rv.version,
            'conditions', rv.conditions,
            'enabled_user_hashes', rv.enabled_user_hashes,
            'updated_at', r.updated_at
          )
          order by r.priority, r.created_at
        )
        from private.notification_rules r
        left join private.notification_rule_versions rv
          on rv.id = r.current_version_id
      ),
      '[]'::jsonb
    ),
    'templates', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', t.id,
            'key', t.key,
            'name', t.name,
            'title', t.title,
            'body', t.body,
            'destination', t.destination,
            'status', t.status,
            'updated_at', t.updated_at
          )
          order by t.key
        )
        from private.notification_templates t
      ),
      '[]'::jsonb
    ),
    'campaigns', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', c.id,
            'name', c.name,
            'status', c.status,
            'title', c.title,
            'body', c.body,
            'destination', c.destination,
            'target_spec', c.target_spec,
            'scheduled_at', c.scheduled_at,
            'started_at', c.started_at,
            'completed_at', c.completed_at,
            'created_at', c.created_at
          )
          order by c.created_at desc
        )
        from private.notification_campaigns c
        where c.created_at > now() - interval '180 days'
      ),
      '[]'::jsonb
    ),
    'metrics', jsonb_build_object(
      'jobs_24h', (
        select count(*)
        from private.notification_jobs
        where created_at > now() - interval '24 hours'
      ),
      'sent_24h', (
        select count(*)
        from private.notification_jobs
        where status = 'sent'
          and completed_at > now() - interval '24 hours'
      ),
      'skipped_24h', (
        select count(*)
        from private.notification_jobs
        where status = 'skipped'
          and completed_at > now() - interval '24 hours'
      ),
      'failed_24h', (
        select count(*)
        from private.notification_jobs
        where status in ('failed', 'ambiguous')
          and completed_at > now() - interval '24 hours'
      ),
      'pending', (
        select count(*)
        from private.notification_jobs
        where status in ('pending', 'claimed')
      ),
      'apns_accepted_24h', (
        select count(*)
        from private.notification_delivery_attempts
        where outcome = 'accepted'
          and created_at > now() - interval '24 hours'
      ),
      'apns_permanent_24h', (
        select count(*)
        from private.notification_delivery_attempts
        where outcome = 'permanent'
          and created_at > now() - interval '24 hours'
      ),
      'apns_transient_24h', (
        select count(*)
        from private.notification_delivery_attempts
        where outcome = 'transient'
          and created_at > now() - interval '24 hours'
      ),
      'apns_ambiguous_24h', (
        select count(*)
        from private.notification_delivery_attempts
        where outcome = 'ambiguous'
          and created_at > now() - interval '24 hours'
      ),
      'opened_24h', (
        select count(*)
        from public.notification_events
        where opened_at > now() - interval '24 hours'
      )
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_notification_snapshot_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_notification_snapshot_v1(uuid)
  to service_role;

create or replace function public.admin_notification_preview_v1(
  p_actor_user_id uuid,
  p_rule_id uuid default null,
  p_campaign_id uuid default null,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule_type text;
  v_conditions jsonb;
  v_target_spec jsonb;
  v_count bigint := 0;
begin
  if not private.notification_admin_has_scope(
    p_actor_user_id,
    'notifications.read'
  ) then
    raise exception 'admin_scope_required:notifications.read'
      using errcode = '42501';
  end if;

  if (p_rule_id is null) = (p_campaign_id is null) then
    raise exception 'exactly_one_preview_target_required'
      using errcode = '22023';
  end if;

  if p_rule_id is not null then
    select r.rule_type, rv.conditions
    into v_rule_type, v_conditions
    from private.notification_rules r
    join private.notification_rule_versions rv
      on rv.id = r.current_version_id
    where r.id = p_rule_id;

    if not found then
      raise exception 'rule_not_found' using errcode = 'P0002';
    end if;

    if v_rule_type = 'first_analysis' then
      select count(*) into v_count
      from public.user_engagement_state e
      join auth.users u on u.id = e.user_id
      left join public.user_onboarding_answers o on o.user_id = e.user_id
      join public.notification_preferences p on p.user_id = e.user_id
      where p.enabled
        and p.app_reminders
        and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
        and exists (
          select 1
          from public.push_device_tokens dt
          where dt.user_id = e.user_id
            and dt.environment = 'production'
            and dt.notifications_enabled
        )
        and p_now >= coalesce(o.completed_at, u.created_at)
          + (v_conditions->>'min_hours')::numeric * interval '1 hour'
        and p_now < coalesce(o.completed_at, u.created_at)
          + (v_conditions->>'max_hours')::numeric * interval '1 hour'
        and not exists (
          select 1
          from public.analyses a
          where a.user_id = e.user_id
            and (
              a.status::text <> 'pending'
              or a.queued_at is not null
              or a.worker_started_at is not null
            )
        );
    else
      select count(*) into v_count
      from public.user_engagement_state e
      join public.notification_preferences p on p.user_id = e.user_id
      where p.enabled
        and p.app_reminders
        and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
        and exists (
          select 1
          from public.push_device_tokens dt
          where dt.user_id = e.user_id
            and dt.environment = 'production'
            and dt.notifications_enabled
        )
        and exists (
          select 1
          from public.analyses a
          where a.user_id = e.user_id
            and a.status::text = 'completed'
        )
        and e.last_foreground_at <= p_now
          - (v_conditions->>'inactivity_days')::numeric * interval '1 day';
    end if;
  else
    select target_spec into v_target_spec
    from private.notification_campaigns
    where id = p_campaign_id;

    if not found then
      raise exception 'campaign_not_found' using errcode = 'P0002';
    end if;

    select count(*) into v_count
    from public.user_engagement_state e
    join public.notification_preferences p on p.user_id = e.user_id
    where p.enabled
      and p.app_reminders
      and e.authorization_status in ('authorized', 'provisional', 'ephemeral')
      and exists (
        select 1
        from public.push_device_tokens dt
        where dt.user_id = e.user_id
          and dt.environment = 'production'
          and dt.notifications_enabled
      )
      and (
        v_target_spec->>'audience' = 'all_eligible'
        or (
          v_target_spec->>'audience' = 'allowlist'
          and coalesce(v_target_spec->'user_hashes', '[]'::jsonb)
            ? private.notification_user_hash(e.user_id)
        )
      );
  end if;

  return jsonb_build_object(
    'eligible_count', v_count,
    'evaluated_at', p_now,
    'note', 'Preview excludes final send-time revalidation and frequency deferrals.'
  );
end;
$$;

revoke all on function public.admin_notification_preview_v1(
  uuid, uuid, uuid, timestamptz
) from public, anon, authenticated;
grant execute on function public.admin_notification_preview_v1(
  uuid, uuid, uuid, timestamptz
) to service_role;

create or replace function public.admin_notification_mutation_v1(
  p_actor_user_id uuid,
  p_action text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_required_scope text;
  v_admin_email text;
  v_id uuid;
  v_rule_id uuid;
  v_rule_type text;
  v_template_id uuid;
  v_version_id uuid;
  v_version integer;
  v_status text;
  v_rollout_percentage integer;
  v_conditions jsonb;
  v_target_spec jsonb;
  v_result jsonb;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'payload_must_be_object' using errcode = '22023';
  end if;

  v_required_scope := case
    when v_action in (
      'create_template',
      'update_template',
      'create_rule',
      'create_rule_version'
    )
      then 'notifications.rules.write'
    when v_action in (
      'set_rule_status',
      'set_campaign_status',
      'set_rollout'
    )
      then 'notifications.publish'
    when v_action = 'create_campaign'
      then 'notifications.campaigns.write'
    when v_action = 'set_kill_switch'
      then 'notifications.kill_switch'
    else null
  end;

  if v_required_scope is null then
    raise exception 'unsupported_notification_action' using errcode = '22023';
  end if;

  if not private.notification_admin_has_scope(
    p_actor_user_id,
    v_required_scope
  ) then
    raise exception 'admin_scope_required:%', v_required_scope
      using errcode = '42501';
  end if;

  select email into v_admin_email
  from public.admin_users
  where user_id = p_actor_user_id
    and is_active;

  if v_action = 'create_template' then
    insert into private.notification_templates (
      key,
      name,
      title,
      body,
      destination,
      status,
      variables,
      created_by
    )
    values (
      lower(btrim(v_payload->>'key')),
      left(btrim(v_payload->>'name'), 120),
      btrim(v_payload->>'title'),
      btrim(v_payload->>'body'),
      coalesce(nullif(v_payload->>'destination', ''), 'home'),
      coalesce(nullif(v_payload->>'status', ''), 'draft'),
      coalesce(v_payload->'variables', '[]'::jsonb),
      p_actor_user_id
    )
    returning id into v_id;
    v_result := jsonb_build_object('id', v_id, 'action', v_action);

  elsif v_action = 'update_template' then
    v_id := (v_payload->>'template_id')::uuid;
    if exists (
      select 1
      from private.notification_rules
      where template_id = v_id
        and status in ('shadow', 'allowlist', 'active')
    ) then
      raise exception 'active_template_requires_new_rule_version'
        using errcode = '55000';
    end if;

    update private.notification_templates
    set name = coalesce(
          nullif(left(btrim(v_payload->>'name'), 120), ''),
          name
        ),
        title = coalesce(
          nullif(btrim(v_payload->>'title'), ''),
          title
        ),
        body = coalesce(
          nullif(btrim(v_payload->>'body'), ''),
          body
        ),
        destination = coalesce(
          nullif(v_payload->>'destination', ''),
          destination
        ),
        status = coalesce(nullif(v_payload->>'status', ''), status),
        updated_at = now()
    where id = v_id
    returning id into v_rule_id;

    if v_rule_id is null then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;
    v_result := jsonb_build_object('id', v_id, 'action', v_action);

  elsif v_action = 'create_rule' then
    v_rule_type := lower(btrim(v_payload->>'rule_type'));
    v_template_id := (v_payload->>'template_id')::uuid;
    v_conditions := coalesce(v_payload->'conditions', '{}'::jsonb);

    if not private.notification_conditions_valid(
      v_rule_type,
      v_conditions
    ) then
      raise exception 'invalid_rule_conditions' using errcode = '22023';
    end if;

    if not exists (
      select 1
      from private.notification_templates
      where id = v_template_id
        and status <> 'archived'
    ) then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;

    insert into private.notification_rules (
      key,
      name,
      rule_type,
      status,
      template_id,
      priority,
      created_by
    )
    values (
      lower(btrim(v_payload->>'key')),
      left(btrim(v_payload->>'name'), 120),
      v_rule_type,
      'draft',
      v_template_id,
      greatest(
        1,
        least(coalesce((v_payload->>'priority')::integer, 100), 1000)
      ),
      p_actor_user_id
    )
    returning id into v_rule_id;

    insert into private.notification_rule_versions (
      rule_id,
      version,
      conditions,
      template_snapshot,
      enabled_user_hashes,
      created_by
    )
    select
      v_rule_id,
      1,
      v_conditions,
      jsonb_build_object(
        'template_id', t.id,
        'title', t.title,
        'body', t.body,
        'destination', t.destination
      ),
      coalesce(
        array(
          select jsonb_array_elements_text(
            coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb)
          )
        ),
        '{}'::text[]
      ),
      p_actor_user_id
    from private.notification_templates t
    where t.id = v_template_id
    returning id into v_version_id;

    update private.notification_rules
    set current_version_id = v_version_id,
        updated_at = now()
    where id = v_rule_id;

    v_result := jsonb_build_object(
      'id', v_rule_id,
      'version_id', v_version_id,
      'action', v_action
    );

  elsif v_action = 'create_rule_version' then
    v_rule_id := (v_payload->>'rule_id')::uuid;
    select rule_type, template_id
    into v_rule_type, v_template_id
    from private.notification_rules
    where id = v_rule_id
      and status <> 'archived'
    for update;

    if not found then
      raise exception 'rule_not_found' using errcode = 'P0002';
    end if;

    v_template_id := coalesce(
      nullif(v_payload->>'template_id', '')::uuid,
      v_template_id
    );
    v_conditions := coalesce(v_payload->'conditions', '{}'::jsonb);

    if not private.notification_conditions_valid(
      v_rule_type,
      v_conditions
    ) then
      raise exception 'invalid_rule_conditions' using errcode = '22023';
    end if;

    select coalesce(max(version), 0) + 1
    into v_version
    from private.notification_rule_versions
    where rule_id = v_rule_id;

    insert into private.notification_rule_versions (
      rule_id,
      version,
      conditions,
      template_snapshot,
      enabled_user_hashes,
      created_by
    )
    select
      v_rule_id,
      v_version,
      v_conditions,
      jsonb_build_object(
        'template_id', t.id,
        'title', t.title,
        'body', t.body,
        'destination', t.destination
      ),
      coalesce(
        array(
          select jsonb_array_elements_text(
            coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb)
          )
        ),
        '{}'::text[]
      ),
      p_actor_user_id
    from private.notification_templates t
    where t.id = v_template_id
      and t.status <> 'archived'
    returning id into v_version_id;

    if v_version_id is null then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;

    update private.notification_rules
    set current_version_id = v_version_id,
        template_id = v_template_id,
        status = 'draft',
        updated_at = now()
    where id = v_rule_id;

    update private.notification_jobs
    set status = 'cancelled',
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        completed_at = now(),
        last_error_code = 'rule_version_superseded',
        last_error_text = null,
        updated_at = now()
    where rule_id = v_rule_id
      and rule_version_id is distinct from v_version_id
      and status in ('pending', 'claimed');

    v_result := jsonb_build_object(
      'id', v_rule_id,
      'version_id', v_version_id,
      'version', v_version,
      'action', v_action
    );

  elsif v_action = 'set_rule_status' then
    v_rule_id := (v_payload->>'rule_id')::uuid;
    v_status := lower(btrim(v_payload->>'status'));
    if v_status not in (
      'shadow',
      'allowlist',
      'active',
      'paused',
      'archived'
    ) then
      raise exception 'invalid_rule_status' using errcode = '22023';
    end if;

    update private.notification_rules
    set status = v_status,
        updated_at = now()
    where id = v_rule_id
      and current_version_id is not null
    returning id into v_id;

    if v_id is null then
      raise exception 'rule_not_found' using errcode = 'P0002';
    end if;

    if v_status = 'paused' then
      update private.notification_jobs
      set status = 'pending',
          attempt_count = case
            when status = 'claimed' then greatest(attempt_count - 1, 0)
            else attempt_count
          end,
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = null,
          last_error_code = 'rule_paused',
          updated_at = now()
      where rule_id = v_rule_id
        and status in ('pending', 'claimed');
    elsif v_status = 'archived' then
      update private.notification_jobs
      set status = 'cancelled',
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = now(),
          last_error_code = 'rule_' || v_status,
          updated_at = now()
      where rule_id = v_rule_id
        and status in ('pending', 'claimed');
    else
      update private.notification_rule_versions
      set published_at = coalesce(published_at, now())
      where id = (
        select current_version_id
        from private.notification_rules
        where id = v_rule_id
      );
    end if;

    v_result := jsonb_build_object(
      'id', v_rule_id,
      'status', v_status,
      'action', v_action
    );

  elsif v_action = 'create_campaign' then
    v_target_spec := coalesce(
      v_payload->'target_spec',
      '{"audience":"allowlist","user_hashes":[]}'::jsonb
    );
    if jsonb_typeof(v_target_spec) <> 'object'
       or v_target_spec->>'audience' not in ('allowlist', 'all_eligible') then
      raise exception 'invalid_campaign_target_spec' using errcode = '22023';
    end if;

    if v_target_spec->>'audience' = 'allowlist'
       and (
         jsonb_typeof(v_target_spec->'user_hashes') <> 'array'
         or jsonb_array_length(v_target_spec->'user_hashes') > 1000
       ) then
      raise exception 'invalid_campaign_target_spec' using errcode = '22023';
    end if;

    insert into private.notification_campaigns (
      name,
      status,
      template_id,
      title,
      body,
      destination,
      target_spec,
      scheduled_at,
      created_by
    )
    values (
      left(btrim(v_payload->>'name'), 120),
      'draft',
      nullif(v_payload->>'template_id', '')::uuid,
      btrim(v_payload->>'title'),
      btrim(v_payload->>'body'),
      coalesce(nullif(v_payload->>'destination', ''), 'home'),
      v_target_spec,
      nullif(v_payload->>'scheduled_at', '')::timestamptz,
      p_actor_user_id
    )
    returning id into v_id;
    v_result := jsonb_build_object('id', v_id, 'action', v_action);

  elsif v_action = 'set_campaign_status' then
    v_id := (v_payload->>'campaign_id')::uuid;
    v_status := lower(btrim(v_payload->>'status'));
    if v_status not in ('scheduled', 'paused', 'cancelled', 'completed') then
      raise exception 'invalid_campaign_status' using errcode = '22023';
    end if;

    if v_status = 'completed'
       and exists (
         select 1
         from private.notification_jobs
         where campaign_id = v_id
           and status in ('pending', 'claimed')
       ) then
      raise exception 'campaign_has_unfinished_jobs' using errcode = '55000';
    end if;

    update private.notification_campaigns
    set status = v_status,
        scheduled_at = case
          when v_status = 'scheduled'
            then coalesce(
              nullif(v_payload->>'scheduled_at', '')::timestamptz,
              scheduled_at,
              now()
            )
          else scheduled_at
        end,
        completed_at = case
          when v_status in ('cancelled', 'completed') then now()
          else completed_at
        end,
        updated_at = now()
    where id = v_id
      and status not in ('completed', 'cancelled')
    returning id into v_rule_id;

    if v_rule_id is null then
      raise exception 'campaign_not_found_or_terminal' using errcode = 'P0002';
    end if;

    if v_status = 'paused' then
      update private.notification_jobs
      set status = 'pending',
          attempt_count = case
            when status = 'claimed' then greatest(attempt_count - 1, 0)
            else attempt_count
          end,
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = null,
          last_error_code = 'campaign_paused',
          updated_at = now()
      where campaign_id = v_id
        and status in ('pending', 'claimed');
    elsif v_status = 'cancelled' then
      update private.notification_jobs
      set status = 'cancelled',
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = now(),
          last_error_code = 'campaign_' || v_status,
          updated_at = now()
      where campaign_id = v_id
        and status in ('pending', 'claimed');
    end if;

    v_result := jsonb_build_object(
      'id', v_id,
      'status', v_status,
      'action', v_action
    );

  elsif v_action = 'set_kill_switch' then
    insert into public.app_feature_flags (key, value)
    values (
      'engagement_notification_automation',
      jsonb_build_object(
        'rollout_mode', 'off',
        'enabled_user_hashes', jsonb_build_array(),
        'kill_switch', coalesce((v_payload->>'enabled')::boolean, true)
      )
    )
    on conflict (key) do update set
      value = jsonb_set(
        public.app_feature_flags.value,
        '{kill_switch}',
        to_jsonb(coalesce((v_payload->>'enabled')::boolean, true)),
        true
      ),
      updated_at = now();

    if coalesce((v_payload->>'enabled')::boolean, true) then
      update private.notification_jobs
      set status = 'pending',
          attempt_count = case
            when status = 'claimed' then greatest(attempt_count - 1, 0)
            else attempt_count
          end,
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = null,
          last_error_code = 'global_kill_switch',
          updated_at = now()
      where status in ('pending', 'claimed');
    end if;

    v_result := jsonb_build_object(
      'enabled', coalesce((v_payload->>'enabled')::boolean, true),
      'action', v_action
    );

  elsif v_action = 'set_rollout' then
    v_status := lower(btrim(v_payload->>'rollout_mode'));
    if v_status not in ('off', 'allowlist', 'on') then
      raise exception 'invalid_rollout_mode' using errcode = '22023';
    end if;

    v_rollout_percentage := case
      when v_status = 'on'
        then coalesce((v_payload->>'rollout_percentage')::integer, 100)
      else 0
    end;
    if v_rollout_percentage not between 0 and 100 then
      raise exception 'invalid_rollout_percentage' using errcode = '22023';
    end if;

    if jsonb_typeof(
      coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb)
    ) <> 'array'
       or jsonb_array_length(
         coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb)
       ) > 1000 then
      raise exception 'invalid_rollout_allowlist' using errcode = '22023';
    end if;

    insert into public.app_feature_flags (key, value)
    values (
      'engagement_notification_automation',
      jsonb_build_object(
        'rollout_mode', v_status,
        'enabled_user_hashes',
          coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb),
        'rollout_percentage', v_rollout_percentage,
        'kill_switch', false
      )
    )
    on conflict (key) do update set
      value = jsonb_set(
        jsonb_set(
          jsonb_set(
            public.app_feature_flags.value,
            '{rollout_mode}',
            to_jsonb(v_status),
            true
          ),
          '{enabled_user_hashes}',
          coalesce(v_payload->'enabled_user_hashes', '[]'::jsonb),
          true
        ),
        '{rollout_percentage}',
        to_jsonb(v_rollout_percentage),
        true
      ),
      updated_at = now();

    if v_status = 'off' then
      update private.notification_jobs
      set status = 'pending',
          attempt_count = case
            when status = 'claimed' then greatest(attempt_count - 1, 0)
            else attempt_count
          end,
          claim_token = null,
          claimed_at = null,
          lease_expires_at = null,
          completed_at = null,
          last_error_code = 'rollout_off',
          updated_at = now()
      where status in ('pending', 'claimed');
    end if;

    v_result := jsonb_build_object(
      'rollout_mode', v_status,
      'rollout_percentage', v_rollout_percentage,
      'action', v_action
    );
  end if;

  insert into public.admin_audit_logs (
    admin_user_id,
    admin_email,
    action,
    target_type,
    target_id,
    metadata
  )
  values (
    p_actor_user_id,
    v_admin_email,
    'notifications.' || v_action,
    case
      when v_action like '%rule%' then 'notification_rule'
      when v_action like '%campaign%' then 'notification_campaign'
      when v_action in ('create_template', 'update_template')
        then 'notification_template'
      else 'notification_automation'
    end,
    coalesce(
      v_result->>'id',
      v_result->>'enabled',
      'global'
    ),
    jsonb_build_object(
      'action', v_action,
      'status', v_result->>'status',
      'version', v_result->>'version'
    )
  );

  return v_result;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'invalid_notification_payload'
      using errcode = '22023';
end;
$$;

revoke all on function public.admin_notification_mutation_v1(
  uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.admin_notification_mutation_v1(
  uuid, text, jsonb
) to service_role;

-- ---------------------------------------------------------------------------
-- Initial templates/rules and disabled rollout flag
-- ---------------------------------------------------------------------------

insert into public.app_feature_flags (key, value)
values (
  'engagement_notification_automation',
  jsonb_build_object(
    'rollout_mode', 'off',
    'enabled_user_hashes', jsonb_build_array(),
    'rollout_percentage', 0,
    'kill_switch', false
  )
)
on conflict (key) do nothing;

do $$
declare
  v_first_template_id uuid;
  v_inactivity_template_id uuid;
  v_first_rule_id uuid;
  v_inactivity_rule_id uuid;
  v_version_id uuid;
begin
  insert into private.notification_templates (
    key,
    name,
    title,
    body,
    destination,
    status
  )
  values (
    'first_analysis_reminder_v1',
    'İlk analiz hatırlatması',
    'İlk analizin seni bekliyor',
    'Saha fotoğrafını ekle, riskleri birkaç dakika içinde birlikte değerlendirelim.',
    'new_analysis',
    'active'
  )
  on conflict (key) do nothing;

  select id into v_first_template_id
  from private.notification_templates
  where key = 'first_analysis_reminder_v1';

  insert into private.notification_templates (
    key,
    name,
    title,
    body,
    destination,
    status
  )
  values (
    'inactivity_reminder_v1',
    'Beş günlük aktivite hatırlatması',
    'Sahadaki riskleri erteleme',
    'Yeni bir saha fotoğrafıyla risk analizini güncelle ve önlemlerini gözden geçir.',
    'new_analysis',
    'active'
  )
  on conflict (key) do nothing;

  select id into v_inactivity_template_id
  from private.notification_templates
  where key = 'inactivity_reminder_v1';

  insert into private.notification_rules (
    key,
    name,
    rule_type,
    status,
    template_id,
    priority
  )
  values (
    'first_analysis_after_24h',
    'Onboarding sonrası ilk analiz',
    'first_analysis',
    'shadow',
    v_first_template_id,
    100
  )
  on conflict (key) do nothing;

  select id, current_version_id
  into v_first_rule_id, v_version_id
  from private.notification_rules
  where key = 'first_analysis_after_24h';

  if v_version_id is null then
    insert into private.notification_rule_versions (
      rule_id,
      version,
      conditions,
      template_snapshot
    )
    values (
      v_first_rule_id,
      1,
      '{"min_hours":24,"max_hours":72}'::jsonb,
      jsonb_build_object(
        'template_id', v_first_template_id,
        'title', 'İlk analizin seni bekliyor',
        'body', 'Saha fotoğrafını ekle, riskleri birkaç dakika içinde birlikte değerlendirelim.',
        'destination', 'new_analysis'
      )
    )
    returning id into v_version_id;

    update private.notification_rules
    set current_version_id = v_version_id
    where id = v_first_rule_id;
  end if;

  v_version_id := null;

  insert into private.notification_rules (
    key,
    name,
    rule_type,
    status,
    template_id,
    priority
  )
  values (
    'inactivity_after_5d',
    'Beş günlük uygulama aktivitesizliği',
    'inactivity',
    'shadow',
    v_inactivity_template_id,
    200
  )
  on conflict (key) do nothing;

  select id, current_version_id
  into v_inactivity_rule_id, v_version_id
  from private.notification_rules
  where key = 'inactivity_after_5d';

  if v_version_id is null then
    insert into private.notification_rule_versions (
      rule_id,
      version,
      conditions,
      template_snapshot
    )
    values (
      v_inactivity_rule_id,
      1,
      '{"inactivity_days":5}'::jsonb,
      jsonb_build_object(
        'template_id', v_inactivity_template_id,
        'title', 'Sahadaki riskleri erteleme',
        'body', 'Yeni bir saha fotoğrafıyla risk analizini güncelle ve önlemlerini gözden geçir.',
        'destination', 'new_analysis'
      )
    )
    returning id into v_version_id;

    update private.notification_rules
    set current_version_id = v_version_id
    where id = v_inactivity_rule_id;
  end if;
end
$$;

-- Cron is installed only when both Vault secrets already exist. This prevents
-- a half-configured deployment from producing failing network requests.
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'riskdetected-notification-automation-15m'
  ) then
    perform cron.unschedule('riskdetected-notification-automation-15m');
  end if;

  if exists (
    select 1
    from vault.decrypted_secrets
    where name = 'project_url'
      and nullif(decrypted_secret, '') is not null
  )
  and exists (
    select 1
    from vault.decrypted_secrets
    where name = 'notification_automation_secret'
      and nullif(decrypted_secret, '') is not null
  ) then
    perform cron.schedule(
      'riskdetected-notification-automation-15m',
      '*/15 * * * *',
      $cron$
      select net.http_post(
        url := (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'project_url'
        ) || '/functions/v1/process-notification-automation',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-notification-automation-secret', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'notification_automation_secret'
          )
        ),
        body := jsonb_build_object(
          'source', 'pg_cron',
          'limit', 100,
          'scheduled_at', now()
        ),
        timeout_milliseconds := 120000
      ) as request_id;
      $cron$
    );
  else
    raise notice
      'notification automation cron not scheduled: Vault secrets are missing';
  end if;
end
$$;

select pg_notify('pgrst', 'reload schema');
