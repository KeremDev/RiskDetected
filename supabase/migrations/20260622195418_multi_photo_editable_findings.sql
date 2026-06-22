-- Multi-photo analysis, editable findings, and report snapshots.
-- All changes are additive/backward-compatible for existing app builds.

create table if not exists public.plan_capability_rules (
  plan text primary key check (plan in ('free', 'plus', 'pro')),
  max_photos_per_analysis integer not null check (max_photos_per_analysis >= 1),
  visible_photo_slots_in_ui integer not null default 5 check (visible_photo_slots_in_ui >= 1),
  max_findings_per_photo integer not null default 12 check (max_findings_per_photo >= 1),
  max_findings_per_analysis integer not null check (max_findings_per_analysis >= 1),
  can_use_multi_photo_analysis boolean not null default false,
  can_edit_ai_findings boolean not null default true,
  can_add_manual_findings boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.plan_capability_rules enable row level security;

drop policy if exists plan_capability_rules_select_authenticated on public.plan_capability_rules;
create policy plan_capability_rules_select_authenticated
  on public.plan_capability_rules
  for select
  to authenticated
  using (true);

insert into public.plan_capability_rules (
  plan,
  max_photos_per_analysis,
  visible_photo_slots_in_ui,
  max_findings_per_photo,
  max_findings_per_analysis,
  can_use_multi_photo_analysis,
  can_edit_ai_findings,
  can_add_manual_findings
) values
  ('free', 1, 5, 12, 12, false, true, false),
  ('plus', 5, 5, 12, 60, true, true, false),
  ('pro', 5, 5, 12, 60, true, true, false)
on conflict (plan) do update set
  max_photos_per_analysis = excluded.max_photos_per_analysis,
  visible_photo_slots_in_ui = excluded.visible_photo_slots_in_ui,
  max_findings_per_photo = excluded.max_findings_per_photo,
  max_findings_per_analysis = excluded.max_findings_per_analysis,
  can_use_multi_photo_analysis = excluded.can_use_multi_photo_analysis,
  can_edit_ai_findings = excluded.can_edit_ai_findings,
  can_add_manual_findings = excluded.can_add_manual_findings,
  updated_at = now();

create table if not exists public.app_feature_flags (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.app_feature_flags enable row level security;

drop policy if exists app_feature_flags_select_authenticated on public.app_feature_flags;
create policy app_feature_flags_select_authenticated
  on public.app_feature_flags
  for select
  to authenticated
  using (true);

insert into public.app_feature_flags (key, value) values
  ('multi_photo_analysis', jsonb_build_object(
    'enable_multi_photo_analysis', false,
    'enable_photo_limit_locked_slots_for_free', false,
    'enable_plus_pro_5_photo_limit', false,
    'enable_editable_findings', false,
    'enable_manual_finding_add', false,
    'enable_report_snapshot_v2', false,
    'max_photo_count_free', 1,
    'max_photo_count_plus', 5,
    'max_photo_count_pro', 5,
    'max_findings_per_photo', 12
  ))
on conflict (key) do update set
  value = excluded.value,
  updated_at = now();

alter table public.analyses
  add column if not exists input_payload_version text not null default 'analysis-v1',
  add column if not exists photo_count integer not null default 0 check (photo_count >= 0),
  add column if not exists max_photos_allowed_at_creation integer,
  add column if not exists max_findings_per_photo integer not null default 12,
  add column if not exists max_findings_total integer,
  add column if not exists generated_findings_count integer not null default 0,
  add column if not exists visible_findings_count integer not null default 0,
  add column if not exists hidden_or_rejected_findings_count integer not null default 0,
  add column if not exists has_user_edits boolean not null default false,
  add column if not exists user_edit_count integer not null default 0,
  add column if not exists analysis_edit_version integer not null default 0,
  add column if not exists finalized_for_report_at timestamptz,
  add column if not exists plan_at_creation text,
  add column if not exists capability_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists rollout_snapshot jsonb not null default '{}'::jsonb;

alter table public.photos
  add column if not exists sequence_index integer,
  add column if not exists client_photo_id text,
  add column if not exists is_primary boolean not null default false,
  add column if not exists original_filename text,
  add column if not exists byte_size integer,
  add column if not exists sha256 text,
  add column if not exists thumbnail_storage_path text,
  add column if not exists annotation_storage_path text,
  add column if not exists user_caption text,
  add column if not exists upload_payload_version text not null default 'photo-single-v1',
  add column if not exists compression_metadata jsonb not null default '{}'::jsonb,
  add column if not exists ai_scene_summary text;

update public.photos
set byte_size = coalesce(byte_size, size_bytes)
where byte_size is null;

create unique index if not exists photos_analysis_sequence_unique
  on public.photos(analysis_id, sequence_index)
  where sequence_index is not null;

create index if not exists photos_analysis_order_idx
  on public.photos(analysis_id, sequence_index);

create index if not exists photos_analysis_sha256_idx
  on public.photos(analysis_id, sha256)
  where sha256 is not null;

alter table public.findings
  add column if not exists origin text not null default 'ai'
    check (origin in ('ai', 'user')),
  add column if not exists ai_original_snapshot jsonb,
  add column if not exists source_photo_indices integer[] not null default '{}',
  add column if not exists source_photo_observations jsonb,
  add column if not exists finding_budget_policy jsonb,
  add column if not exists ai_confidence numeric,
  add column if not exists is_user_deleted boolean not null default false,
  add column if not exists user_deleted_at timestamptz,
  add column if not exists user_deleted_by uuid references auth.users(id),
  add column if not exists last_user_edit_at timestamptz,
  add column if not exists last_user_edit_by uuid references auth.users(id),
  add column if not exists user_edit_count integer not null default 0,
  add column if not exists finding_version integer not null default 1,
  add column if not exists report_visibility text not null default 'visible'
    check (report_visibility in ('visible', 'hidden')),
  add column if not exists display_group text,
  add column if not exists display_order integer;

create index if not exists findings_analysis_visible_idx
  on public.findings(analysis_id, ordinal)
  where is_user_deleted = false;

create index if not exists findings_source_photo_indices_gin_idx
  on public.findings using gin(source_photo_indices);

create index if not exists findings_analysis_display_order_idx
  on public.findings(analysis_id, display_order);

create table if not exists public.analysis_photo_summaries (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  photo_id uuid references public.photos(id) on delete set null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  photo_sequence_index integer not null,
  scene_summary text,
  candidate_findings_count integer not null default 0,
  generated_findings_count integer not null default 0,
  highest_risk_level text,
  ai_confidence numeric,
  raw_summary jsonb,
  created_at timestamptz not null default now(),
  unique (analysis_id, photo_sequence_index)
);

alter table public.analysis_photo_summaries enable row level security;

drop policy if exists analysis_photo_summaries_select_own on public.analysis_photo_summaries;
create policy analysis_photo_summaries_select_own
  on public.analysis_photo_summaries
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create index if not exists analysis_photo_summaries_user_created_idx
  on public.analysis_photo_summaries(user_id, created_at desc);

create table if not exists public.finding_edit_events (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  finding_id uuid references public.findings(id) on delete set null,
  actor_user_id uuid not null references auth.users(id),
  event_type text not null check (event_type in ('update', 'hard_delete')),
  before_snapshot jsonb,
  after_snapshot jsonb,
  changed_fields text[] not null default '{}',
  finding_version_before integer,
  finding_version_after integer,
  client_app_version text,
  request_id text,
  support_id text,
  created_at timestamptz not null default now()
);

alter table public.finding_edit_events enable row level security;
revoke all on table public.finding_edit_events from anon, authenticated;
grant select, insert on table public.finding_edit_events to service_role;

create index if not exists finding_edit_events_analysis_created_idx
  on public.finding_edit_events(analysis_id, created_at desc);

create index if not exists finding_edit_events_actor_created_idx
  on public.finding_edit_events(actor_user_id, created_at desc);

alter table public.reports
  add column if not exists findings_snapshot_json jsonb,
  add column if not exists photos_snapshot_json jsonb,
  add column if not exists analysis_edit_version integer not null default 0,
  add column if not exists generated_from_user_edited_findings boolean not null default false,
  add column if not exists source_photo_count integer,
  add column if not exists visible_findings_count integer,
  add column if not exists report_page_count integer;

create or replace function public.recalc_analysis_rollup(p_analysis_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid;
  v_count integer;
  v_total_fk numeric;
  v_total_m5 integer;
  v_highest_fk text;
  v_highest_m5 text;
begin
  if p_analysis_id is null then
    return;
  end if;

  select user_id into v_user_id
  from public.analyses
  where id = p_analysis_id;

  if v_user_id is null then
    return;
  end if;

  select
    count(*)::integer,
    coalesce(sum(fk_score), 0),
    coalesce(sum(m5_score), 0)::integer,
    coalesce((
      array_agg(fk_band::text order by
        case fk_band::text
          when 'critical' then 4
          when 'high' then 3
          when 'medium' then 2
          when 'low' then 1
          else 0
        end desc
      )
    )[1], 'unknown'),
    coalesce((
      array_agg(m5_band::text order by
        case m5_band::text
          when 'critical' then 4
          when 'high' then 3
          when 'medium' then 2
          when 'low' then 1
          else 0
        end desc
      )
    )[1], 'unknown')
  into v_count, v_total_fk, v_total_m5, v_highest_fk, v_highest_m5
  from public.findings
  where analysis_id = p_analysis_id
    and coalesce(is_user_deleted, false) = false
    and coalesce(report_visibility, 'visible') = 'visible';

  update public.analyses
  set finding_count = v_count,
      generated_findings_count = greatest(generated_findings_count, v_count),
      visible_findings_count = v_count,
      total_score_fk = v_total_fk,
      total_score_m5 = v_total_m5,
      highest_band_fk = nullif(v_highest_fk, 'unknown')::risk_level,
      highest_band_m5 = nullif(v_highest_m5, 'unknown')::risk_level,
      updated_at = now()
  where id = p_analysis_id;
end
$function$;

revoke all on function public.recalc_analysis_rollup(uuid) from public, anon, authenticated;
grant execute on function public.recalc_analysis_rollup(uuid) to service_role;

create or replace function public.tg_recalc_finding_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.recalc_analysis_rollup(coalesce(new.analysis_id, old.analysis_id));
  return null;
end
$function$;

drop trigger if exists findings_after_change on public.findings;
create trigger findings_after_change
  after insert or delete on public.findings
  for each row execute function public.tg_recalc_finding_count();

grant select on public.plan_capability_rules to authenticated;
grant select on public.app_feature_flags to authenticated;
grant select on public.analysis_photo_summaries to authenticated;
