-- Professional Progress module: MDP, title progression, badges and
-- competency-level risk accounting. This module is intentionally isolated under
-- the professional_progress_* prefix so it can be disabled without changing the
-- core analysis/report flows.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.professional_progress_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  total_mdp integer not null default 0 check (total_mdp >= 0),
  current_title_key text not null default 'candidate',
  total_analyses integer not null default 0 check (total_analyses >= 0),
  total_reports integer not null default 0 check (total_reports >= 0),
  total_findings integer not null default 0 check (total_findings >= 0),
  critical_findings integer not null default 0 check (critical_findings >= 0),
  high_findings integer not null default 0 check (high_findings >= 0),
  medium_findings integer not null default 0 check (medium_findings >= 0),
  low_findings integer not null default 0 check (low_findings >= 0),
  unknown_findings integer not null default 0 check (unknown_findings >= 0),
  active_days integer not null default 0 check (active_days >= 0),
  last_event_at timestamptz,
  last_title_change_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint professional_progress_profiles_title_check check (
    current_title_key in (
      'candidate',
      'field_observer',
      'risk_hunter',
      'hazard_analyst',
      'senior_risk_specialist',
      'safety_strategist',
      'master_hse_specialist'
    )
  )
);

create table if not exists public.professional_progress_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_key text not null,
  event_type text not null,
  mdp_delta integer not null default 0 check (mdp_delta >= 0),
  analysis_id uuid references public.analyses(id) on delete set null,
  report_id uuid references public.reports(id) on delete set null,
  competency_key text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint professional_progress_events_type_check check (
    event_type in (
      'analysis_completed',
      'report_created',
      'first_competency_used',
      'weekly_report_bonus',
      'badge_unlocked',
      'title_changed',
      'onboarding_competency_seeded',
      'backfill_seed'
    )
  ),
  constraint professional_progress_events_metadata_object_check
    check (jsonb_typeof(metadata) = 'object'),
  unique (user_id, event_key)
);

create table if not exists public.professional_progress_finding_classifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  finding_id uuid not null references public.findings(id) on delete cascade,
  competency_key text not null,
  risk_level text not null,
  source_category_text text,
  matched_by text not null,
  confidence numeric not null default 0 check (confidence >= 0 and confidence <= 1),
  classifier_version text not null default 'v1_keyword_2026_05_26',
  created_at timestamptz not null default now(),
  constraint professional_progress_finding_competency_check check (
    competency_key in (
      'fire',
      'chemical',
      'electrical',
      'mechanical',
      'ergonomics',
      'psychosocial',
      'working_at_height',
      'ppe',
      'mining',
      'construction',
      'factory',
      'unclassified'
    )
  ),
  constraint professional_progress_finding_risk_check check (
    risk_level in ('critical', 'high', 'medium', 'low', 'unknown')
  ),
  unique (finding_id)
);

create table if not exists public.professional_progress_competency_stats (
  user_id uuid not null references auth.users(id) on delete cascade,
  competency_key text not null,
  analysis_count integer not null default 0 check (analysis_count >= 0),
  report_count integer not null default 0 check (report_count >= 0),
  finding_count integer not null default 0 check (finding_count >= 0),
  critical_count integer not null default 0 check (critical_count >= 0),
  high_count integer not null default 0 check (high_count >= 0),
  medium_count integer not null default 0 check (medium_count >= 0),
  low_count integer not null default 0 check (low_count >= 0),
  unknown_count integer not null default 0 check (unknown_count >= 0),
  onboarding_seed boolean not null default false,
  last_detected_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, competency_key),
  constraint professional_progress_competency_stats_key_check check (
    competency_key in (
      'fire',
      'chemical',
      'electrical',
      'mechanical',
      'ergonomics',
      'psychosocial',
      'working_at_height',
      'ppe',
      'mining',
      'construction',
      'factory'
    )
  )
);

create table if not exists public.professional_progress_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_key text not null,
  badge_type text not null,
  title text not null,
  subtitle text not null,
  icon_name text not null,
  unlocked_at timestamptz not null default now(),
  seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  constraint professional_progress_badges_type_check check (
    badge_type in (
      'report_count',
      'competency_diversity',
      'risk',
      'report_kind',
      'onboarding_area',
      'active_days',
      'title'
    )
  ),
  constraint professional_progress_badges_metadata_object_check
    check (jsonb_typeof(metadata) = 'object'),
  unique (user_id, badge_key)
);

create table if not exists public.professional_progress_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message_type text not null,
  title text not null,
  body text not null,
  related_analysis_id uuid references public.analyses(id) on delete set null,
  related_report_id uuid references public.reports(id) on delete set null,
  competency_key text,
  risk_level text,
  seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint professional_progress_messages_type_check check (
    message_type in ('instant', 'weekly_summary', 'monthly_summary', 'milestone', 'title_change')
  ),
  constraint professional_progress_messages_metadata_object_check
    check (jsonb_typeof(metadata) = 'object')
);

create table if not exists public.professional_progress_weekly_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null,
  reports_count integer not null default 0 check (reports_count >= 0),
  analyses_count integer not null default 0 check (analyses_count >= 0),
  findings_count integer not null default 0 check (findings_count >= 0),
  top_competency_key text,
  message_title text,
  message_body text,
  push_sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, week_start)
);

alter table public.notification_preferences
  add column if not exists progress_weekly_summary boolean not null default true,
  add column if not exists progress_monthly_summary boolean not null default true,
  add column if not exists progress_milestones boolean not null default true;

create index if not exists professional_progress_events_user_created_idx
  on public.professional_progress_events (user_id, created_at desc);
create index if not exists professional_progress_events_analysis_idx
  on public.professional_progress_events (analysis_id);
create index if not exists professional_progress_events_report_idx
  on public.professional_progress_events (report_id);
create index if not exists professional_progress_finding_user_competency_idx
  on public.professional_progress_finding_classifications (user_id, competency_key, risk_level);
create index if not exists professional_progress_messages_user_created_idx
  on public.professional_progress_messages (user_id, created_at desc);
create index if not exists professional_progress_badges_user_unlocked_idx
  on public.professional_progress_badges (user_id, unlocked_at desc);

alter table public.professional_progress_profiles enable row level security;
alter table public.professional_progress_events enable row level security;
alter table public.professional_progress_finding_classifications enable row level security;
alter table public.professional_progress_competency_stats enable row level security;
alter table public.professional_progress_badges enable row level security;
alter table public.professional_progress_messages enable row level security;
alter table public.professional_progress_weekly_summaries enable row level security;

drop policy if exists professional_progress_profiles_select_own on public.professional_progress_profiles;
create policy professional_progress_profiles_select_own
  on public.professional_progress_profiles for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists professional_progress_events_select_own on public.professional_progress_events;
create policy professional_progress_events_select_own
  on public.professional_progress_events for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists professional_progress_classifications_select_own on public.professional_progress_finding_classifications;
create policy professional_progress_classifications_select_own
  on public.professional_progress_finding_classifications for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists professional_progress_competency_select_own on public.professional_progress_competency_stats;
create policy professional_progress_competency_select_own
  on public.professional_progress_competency_stats for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists professional_progress_badges_select_own on public.professional_progress_badges;
create policy professional_progress_badges_select_own
  on public.professional_progress_badges for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists professional_progress_badges_seen_own on public.professional_progress_badges;
create policy professional_progress_badges_seen_own
  on public.professional_progress_badges for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists professional_progress_messages_select_own on public.professional_progress_messages;
create policy professional_progress_messages_select_own
  on public.professional_progress_messages for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists professional_progress_messages_seen_own on public.professional_progress_messages;
create policy professional_progress_messages_seen_own
  on public.professional_progress_messages for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists professional_progress_weekly_select_own on public.professional_progress_weekly_summaries;
create policy professional_progress_weekly_select_own
  on public.professional_progress_weekly_summaries for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.professional_progress_profiles from anon, public;
revoke all on public.professional_progress_events from anon, public;
revoke all on public.professional_progress_finding_classifications from anon, public;
revoke all on public.professional_progress_competency_stats from anon, public;
revoke all on public.professional_progress_badges from anon, public;
revoke all on public.professional_progress_messages from anon, public;
revoke all on public.professional_progress_weekly_summaries from anon, public;

grant select on public.professional_progress_profiles to authenticated;
grant select on public.professional_progress_events to authenticated;
grant select on public.professional_progress_finding_classifications to authenticated;
grant select on public.professional_progress_competency_stats to authenticated;
grant select on public.professional_progress_badges to authenticated;
grant update (seen_at) on public.professional_progress_badges to authenticated;
grant select on public.professional_progress_messages to authenticated;
grant update (seen_at) on public.professional_progress_messages to authenticated;
grant select on public.professional_progress_weekly_summaries to authenticated;

create or replace function private.pp_title_key_for_mdp(p_mdp integer)
returns text
language sql
immutable
as $$
  select case
    when coalesce(p_mdp, 0) >= 30000 then 'master_hse_specialist'
    when coalesce(p_mdp, 0) >= 15000 then 'safety_strategist'
    when coalesce(p_mdp, 0) >= 8000 then 'senior_risk_specialist'
    when coalesce(p_mdp, 0) >= 4000 then 'hazard_analyst'
    when coalesce(p_mdp, 0) >= 1500 then 'risk_hunter'
    when coalesce(p_mdp, 0) >= 500 then 'field_observer'
    else 'candidate'
  end;
$$;
revoke all on function private.pp_title_key_for_mdp(integer) from public, anon, authenticated;

create or replace function private.pp_title_label(p_key text)
returns text
language sql
immutable
as $$
  select case p_key
    when 'field_observer' then 'Saha Gözlemcisi'
    when 'risk_hunter' then 'Risk Avcısı'
    when 'hazard_analyst' then 'Tehlike Analisti'
    when 'senior_risk_specialist' then 'Kıdemli Risk Uzmanı'
    when 'safety_strategist' then 'Güvenlik Stratejisti'
    when 'master_hse_specialist' then 'Usta İSG Uzmanı'
    else 'Aday Uzman'
  end;
$$;
revoke all on function private.pp_title_label(text) from public, anon, authenticated;

create or replace function private.pp_competency_label(p_key text)
returns text
language sql
immutable
as $$
  select case p_key
    when 'fire' then 'Yangın'
    when 'chemical' then 'Kimyasal'
    when 'electrical' then 'Elektrik'
    when 'mechanical' then 'Mekanik'
    when 'ergonomics' then 'Ergonomi'
    when 'psychosocial' then 'Psikososyal'
    when 'working_at_height' then 'Yüksekte Çalışma'
    when 'ppe' then 'KKD'
    when 'mining' then 'Maden'
    when 'construction' then 'İnşaat'
    when 'factory' then 'Fabrika'
    else 'Genel'
  end;
$$;
revoke all on function private.pp_competency_label(text) from public, anon, authenticated;

create or replace function private.pp_risk_rank(p_level text)
returns integer
language sql
immutable
as $$
  select case p_level
    when 'critical' then 4
    when 'high' then 3
    when 'medium' then 2
    when 'low' then 1
    else 0
  end;
$$;
revoke all on function private.pp_risk_rank(text) from public, anon, authenticated;

create or replace function private.pp_highest_risk_level(p_fk text, p_m5 text)
returns text
language sql
immutable
as $$
  select case
    when greatest(private.pp_risk_rank(p_fk), private.pp_risk_rank(p_m5)) = 4 then 'critical'
    when greatest(private.pp_risk_rank(p_fk), private.pp_risk_rank(p_m5)) = 3 then 'high'
    when greatest(private.pp_risk_rank(p_fk), private.pp_risk_rank(p_m5)) = 2 then 'medium'
    when greatest(private.pp_risk_rank(p_fk), private.pp_risk_rank(p_m5)) = 1 then 'low'
    else 'unknown'
  end;
$$;
revoke all on function private.pp_highest_risk_level(text, text) from public, anon, authenticated;

create or replace function private.pp_contains_any(p_text text, p_terms text[])
returns boolean
language sql
immutable
as $$
  select exists (
    select 1
    from unnest(p_terms) as term(value)
    where position(term.value in coalesce(p_text, '')) > 0
  );
$$;
revoke all on function private.pp_contains_any(text, text[]) from public, anon, authenticated;

create or replace function private.pp_competency_for_finding(
  p_category text,
  p_title text,
  p_description text,
  p_action text,
  p_canvas text,
  p_sectors text[] default '{}'::text[]
)
returns table (
  competency_key text,
  matched_by text,
  confidence numeric,
  source_text text
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  v_category text := lower(coalesce(p_category, ''));
  v_text text := lower(
    coalesce(p_category, '') || ' ' ||
    coalesce(p_title, '') || ' ' ||
    coalesce(p_description, '') || ' ' ||
    coalesce(p_action, '')
  );
  v_canvas text := coalesce(p_canvas, '');
  v_sectors text[] := coalesce(p_sectors, '{}'::text[]);
begin
  if private.pp_contains_any(v_category, array['yangın','yangin','söndürücü','sondurucu','tahliye','acil çıkış','acil cikis','yanıcı','yanici','parlayıcı','parlayici','alev','duman','yangın dolabı','yangin dolabi']) then
    return query select 'fire', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['kimyasal','sds','msds','solvent','asit','baz','dökülme','dokulme','sızıntı','sizinti','gaz','buhar','maruziyet','toz','etiketsiz kap']) then
    return query select 'chemical', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['elektrik','pano','kablo','kaçak akım','kacak akim','topraklama','izolasyon','sigorta','gerilim','priz']) then
    return query select 'electrical', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['makine','mekanik','koruyucu','sıkışma','sikisma','ezilme','kesilme','forklift','vinç','vinc','transpalet','hareketli ekipman','döner parça','doner parca']) then
    return query select 'mechanical', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['ergonomi','duruş','durus','manuel taşıma','manuel tasima','tekrarlı','tekrarli','oturuş','oturus']) then
    return query select 'ergonomics', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['psikososyal','stres','mobbing','vardiya','tükenmişlik','tukenmislik','iş yükü','is yuku']) then
    return query select 'psychosocial', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['yüksekte','yuksekte','iskele','ankraj','yaşam hattı','yasam hatti','emniyet kemeri','korkuluk','düşme','dusme','merdiven']) then
    return query select 'working_at_height', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['kkd','baret','gözlük','gozluk','eldiven','maske','kulaklık','kulaklik','emniyet ayakkabısı','emniyet ayakkabisi','reflektif','yelek','kişisel koruyucu','kisisel koruyucu']) then
    return query select 'ppe', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['maden','ocak','galeri','tünel','tunel','göçük','gocuk','taşocağı','tasocagi','havalandırma','havalandirma']) then
    return query select 'mining', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['inşaat','insaat','şantiye','santiye','hafriyat','kalıp','kalip','beton','yapı','yapi']) then
    return query select 'construction', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_category, array['fabrika','üretim','uretim','atölye','atolye','pres','konveyör','konveyor','üretim hattı','uretim hatti']) then
    return query select 'factory', 'finding_category', 0.96::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['maden','ocak','galeri','tünel','tunel','göçük','gocuk','taşocağı','tasocagi','havalandırma','havalandirma']) then
    return query select 'mining', 'finding_text', 0.92::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['inşaat','insaat','şantiye','santiye','hafriyat','kalıp','kalip','beton','yapı','yapi']) then
    return query select 'construction', 'finding_text', 0.9::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['fabrika','üretim','uretim','atölye','atolye','pres','konveyör','konveyor','üretim hattı','uretim hatti']) then
    return query select 'factory', 'finding_text', 0.9::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['yangın','yangin','söndürücü','sondurucu','tahliye','acil çıkış','acil cikis','yanıcı','yanici','parlayıcı','parlayici','alev','duman','yangın dolabı','yangin dolabi']) then
    return query select 'fire', 'finding_text', 0.9::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['kimyasal','sds','msds','solvent','asit','baz','dökülme','dokulme','sızıntı','sizinti','gaz','buhar','maruziyet','toz','etiketsiz kap']) then
    return query select 'chemical', 'finding_text', 0.88::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['elektrik','pano','kablo','kaçak akım','kacak akim','topraklama','izolasyon','sigorta','gerilim','priz']) then
    return query select 'electrical', 'finding_text', 0.88::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['yüksekte','yuksekte','iskele','ankraj','yaşam hattı','yasam hatti','emniyet kemeri','korkuluk','düşme','dusme','merdiven']) then
    return query select 'working_at_height', 'finding_text', 0.88::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['kkd','baret','gözlük','gozluk','eldiven','maske','kulaklık','kulaklik','emniyet ayakkabısı','emniyet ayakkabisi','reflektif','yelek','kişisel koruyucu','kisisel koruyucu']) then
    return query select 'ppe', 'finding_text', 0.88::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['makine','koruyucu','sıkışma','sikisma','ezilme','kesilme','forklift','vinç','vinc','transpalet','hareketli ekipman','döner parça','doner parca']) then
    return query select 'mechanical', 'finding_text', 0.82::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['ergonomi','duruş','durus','manuel taşıma','manuel tasima','tekrarlı','tekrarli','oturuş','oturus']) then
    return query select 'ergonomics', 'finding_text', 0.82::numeric, p_category;
    return;
  end if;

  if private.pp_contains_any(v_text, array['psikososyal','stres','mobbing','vardiya','tükenmişlik','tukenmislik','iş yükü','is yuku']) then
    return query select 'psychosocial', 'finding_text', 0.82::numeric, p_category;
    return;
  end if;

  case v_canvas
    when 'fire' then
      return query select 'fire', 'canvas_fallback', 0.62::numeric, p_category;
      return;
    when 'explosion' then
      return query select 'fire', 'canvas_fallback', 0.58::numeric, p_category;
      return;
    when 'electrical' then
      return query select 'electrical', 'canvas_fallback', 0.62::numeric, p_category;
      return;
    when 'ppe' then
      return query select 'ppe', 'canvas_fallback', 0.62::numeric, p_category;
      return;
    when 'working_at_height' then
      return query select 'working_at_height', 'canvas_fallback', 0.62::numeric, p_category;
      return;
    when 'machine', 'mobile_equipment', 'construction_machinery' then
      return query select 'mechanical', 'canvas_fallback', 0.58::numeric, p_category;
      return;
    when 'ergonomics' then
      return query select 'ergonomics', 'canvas_fallback', 0.58::numeric, p_category;
      return;
    when 'sector' then
      if 'mining' = any(v_sectors) then
        return query select 'mining', 'onboarding_context', 0.45::numeric, p_category;
        return;
      elsif 'construction' = any(v_sectors) then
        return query select 'construction', 'onboarding_context', 0.45::numeric, p_category;
        return;
      elsif 'manufacturing' = any(v_sectors) then
        return query select 'factory', 'onboarding_context', 0.45::numeric, p_category;
        return;
      end if;
    else
      null;
  end case;

  return;
end;
$$;
revoke all on function private.pp_competency_for_finding(text, text, text, text, text, text[]) from public, anon, authenticated;

create or replace function private.pp_ensure_profile(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  insert into public.professional_progress_profiles (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;
end;
$$;
revoke all on function private.pp_ensure_profile(uuid) from public, anon, authenticated;

create or replace function private.pp_insert_message(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_analysis_id uuid default null,
  p_report_id uuid default null,
  p_competency_key text default null,
  p_risk_level text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  insert into public.professional_progress_messages (
    user_id,
    message_type,
    title,
    body,
    related_analysis_id,
    related_report_id,
    competency_key,
    risk_level,
    metadata
  )
  values (
    p_user_id,
    p_type,
    p_title,
    p_body,
    p_analysis_id,
    p_report_id,
    p_competency_key,
    p_risk_level,
    coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;
revoke all on function private.pp_insert_message(uuid, text, text, text, uuid, uuid, text, text, jsonb) from public, anon, authenticated;

create or replace function private.pp_record_event(
  p_user_id uuid,
  p_event_key text,
  p_event_type text,
  p_mdp integer default 0,
  p_analysis_id uuid default null,
  p_report_id uuid default null,
  p_competency_key text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_occurred_at timestamptz default now()
)
returns boolean
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_inserted integer := 0;
  v_old_title text;
  v_new_title text;
  v_new_total integer;
begin
  perform private.pp_ensure_profile(p_user_id);

  insert into public.professional_progress_events (
    user_id,
    event_key,
    event_type,
    mdp_delta,
    analysis_id,
    report_id,
    competency_key,
    metadata,
    occurred_at
  )
  values (
    p_user_id,
    p_event_key,
    p_event_type,
    greatest(coalesce(p_mdp, 0), 0),
    p_analysis_id,
    p_report_id,
    p_competency_key,
    coalesce(p_metadata, '{}'::jsonb),
    coalesce(p_occurred_at, now())
  )
  on conflict (user_id, event_key) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return false;
  end if;

  select current_title_key
    into v_old_title
  from public.professional_progress_profiles
  where user_id = p_user_id;

  update public.professional_progress_profiles
  set
    total_mdp = total_mdp + greatest(coalesce(p_mdp, 0), 0),
    last_event_at = greatest(coalesce(last_event_at, p_occurred_at), p_occurred_at),
    updated_at = now()
  where user_id = p_user_id
  returning total_mdp into v_new_total;

  v_new_title := private.pp_title_key_for_mdp(v_new_total);
  if v_new_title is distinct from v_old_title then
    update public.professional_progress_profiles
    set current_title_key = v_new_title,
        last_title_change_at = now(),
        updated_at = now()
    where user_id = p_user_id;

    insert into public.professional_progress_events (
      user_id,
      event_key,
      event_type,
      mdp_delta,
      metadata,
      occurred_at
    )
    values (
      p_user_id,
      'title_changed:' || v_new_title,
      'title_changed',
      0,
      jsonb_build_object(
        'title_key', v_new_title,
        'title_label', private.pp_title_label(v_new_title),
        'total_mdp', v_new_total
      ),
      now()
    )
    on conflict (user_id, event_key) do nothing;

    insert into public.professional_progress_badges (
      user_id,
      badge_key,
      badge_type,
      title,
      subtitle,
      icon_name,
      metadata
    )
    values (
      p_user_id,
      'title:' || v_new_title,
      'title',
      private.pp_title_label(v_new_title),
      'RiskDetected içi mesleki birikim ünvanı kazanıldı.',
      'checkmark.seal.fill',
      jsonb_build_object('title_key', v_new_title, 'total_mdp', v_new_total)
    )
    on conflict (user_id, badge_key) do nothing;

    perform private.pp_insert_message(
      p_user_id,
      'title_change',
      'Yeni ünvan',
      'Tebrikler. ' || private.pp_title_label(v_new_title) || ' ünvanına ulaştınız. Bu, ' || v_new_total::text || ' MDP''lik mesleki birikim demek.',
      null,
      null,
      null,
      null,
      jsonb_build_object('title_key', v_new_title, 'total_mdp', v_new_total)
    );
  end if;

  return true;
end;
$$;
revoke all on function private.pp_record_event(uuid, text, text, integer, uuid, uuid, text, jsonb, timestamptz) from public, anon, authenticated;

create or replace function private.pp_unlock_badge(
  p_user_id uuid,
  p_badge_key text,
  p_badge_type text,
  p_title text,
  p_subtitle text,
  p_icon_name text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_inserted integer := 0;
begin
  insert into public.professional_progress_badges (
    user_id,
    badge_key,
    badge_type,
    title,
    subtitle,
    icon_name,
    metadata
  )
  values (
    p_user_id,
    p_badge_key,
    p_badge_type,
    p_title,
    p_subtitle,
    p_icon_name,
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (user_id, badge_key) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted > 0 then
    perform private.pp_insert_message(
      p_user_id,
      'milestone',
      p_title,
      p_subtitle,
      null,
      null,
      null,
      null,
      jsonb_build_object('badge_key', p_badge_key, 'badge_type', p_badge_type)
    );
  end if;
end;
$$;
revoke all on function private.pp_unlock_badge(uuid, text, text, text, text, text, jsonb) from public, anon, authenticated;

create or replace function private.pp_refresh_active_days(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_count integer;
begin
  select count(distinct (occurred_at at time zone 'Europe/Istanbul')::date)
    into v_count
  from public.professional_progress_events
  where user_id = p_user_id
    and event_type in ('analysis_completed', 'report_created');

  update public.professional_progress_profiles
  set active_days = coalesce(v_count, 0),
      updated_at = now()
  where user_id = p_user_id;
end;
$$;
revoke all on function private.pp_refresh_active_days(uuid) from public, anon, authenticated;

create or replace function private.pp_refresh_weekly_summary(
  p_user_id uuid,
  p_reference_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_week_start date;
  v_week_end date;
  v_reports integer := 0;
  v_analyses integer := 0;
  v_findings integer := 0;
  v_top_competency text;
  v_title text := 'Haftalık mesleki özet';
  v_body text;
begin
  v_week_start := (date_trunc('week', coalesce(p_reference_at, now()) at time zone 'Europe/Istanbul'))::date;
  v_week_end := v_week_start + 7;

  select count(*)::int
    into v_reports
  from public.reports
  where user_id = p_user_id
    and (created_at at time zone 'Europe/Istanbul')::date >= v_week_start
    and (created_at at time zone 'Europe/Istanbul')::date < v_week_end;

  select count(*)::int
    into v_analyses
  from public.analyses
  where user_id = p_user_id
    and status = 'completed'
    and (coalesce(completed_at, created_at) at time zone 'Europe/Istanbul')::date >= v_week_start
    and (coalesce(completed_at, created_at) at time zone 'Europe/Istanbul')::date < v_week_end;

  select count(*)::int
    into v_findings
  from public.professional_progress_finding_classifications c
  join public.analyses a on a.id = c.analysis_id
  where c.user_id = p_user_id
    and (coalesce(a.completed_at, a.created_at) at time zone 'Europe/Istanbul')::date >= v_week_start
    and (coalesce(a.completed_at, a.created_at) at time zone 'Europe/Istanbul')::date < v_week_end;

  select c.competency_key
    into v_top_competency
  from public.professional_progress_finding_classifications c
  join public.analyses a on a.id = c.analysis_id
  where c.user_id = p_user_id
    and c.competency_key <> 'unclassified'
    and (coalesce(a.completed_at, a.created_at) at time zone 'Europe/Istanbul')::date >= v_week_start
    and (coalesce(a.completed_at, a.created_at) at time zone 'Europe/Istanbul')::date < v_week_end
  group by c.competency_key
  order by count(*) desc, c.competency_key
  limit 1;

  v_body := 'Bu hafta ' || coalesce(v_reports, 0)::text || ' rapor, ' ||
    coalesce(v_analyses, 0)::text || ' analiz ve ' ||
    coalesce(v_findings, 0)::text || ' risk kaydı oluştu.';

  if v_top_competency is not null then
    v_body := v_body || ' En yoğun alan: ' || private.pp_competency_label(v_top_competency) || '.';
  end if;

  insert into public.professional_progress_weekly_summaries (
    user_id,
    week_start,
    reports_count,
    analyses_count,
    findings_count,
    top_competency_key,
    message_title,
    message_body
  )
  values (
    p_user_id,
    v_week_start,
    coalesce(v_reports, 0),
    coalesce(v_analyses, 0),
    coalesce(v_findings, 0),
    v_top_competency,
    v_title,
    v_body
  )
  on conflict (user_id, week_start) do update
  set reports_count = excluded.reports_count,
      analyses_count = excluded.analyses_count,
      findings_count = excluded.findings_count,
      top_competency_key = excluded.top_competency_key,
      message_title = excluded.message_title,
      message_body = excluded.message_body;
end;
$$;
revoke all on function private.pp_refresh_weekly_summary(uuid, timestamptz) from public, anon, authenticated;

create or replace function private.pp_unlock_badges_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_profile public.professional_progress_profiles%rowtype;
  v_diversity integer;
  v_onboarding record;
begin
  select * into v_profile
  from public.professional_progress_profiles
  where user_id = p_user_id;
  if not found then
    return;
  end if;

  if v_profile.total_reports >= 1 then
    perform private.pp_unlock_badge(p_user_id, 'reports:1', 'report_count', 'İlk Adım', 'İlk raporunu oluşturdun. Mesleki takip izin başladı.', 'rosette');
  end if;
  if v_profile.total_reports >= 10 then
    perform private.pp_unlock_badge(p_user_id, 'reports:10', 'report_count', 'Kararlı Başlangıç', '10 rapora ulaştın. Raporlama disiplinin güçleniyor.', 'medal.fill');
  end if;
  if v_profile.total_reports >= 25 then
    perform private.pp_unlock_badge(p_user_id, 'reports:25', 'report_count', 'İstikrarlı Uzman', '25 raporla düzenli takip alışkanlığı oluşturdun.', 'medal.fill');
  end if;
  if v_profile.total_reports >= 50 then
    perform private.pp_unlock_badge(p_user_id, 'reports:50', 'report_count', 'Deneyimli Gözlemci', '50 rapor, güçlü bir saha gözlemi birikimi demek.', 'trophy.fill');
  end if;
  if v_profile.total_reports >= 100 then
    perform private.pp_unlock_badge(p_user_id, 'reports:100', 'report_count', 'Yüz Rapor Kulübü', '100. raporun. Bu, mesleki anlamda ciddi bir kilometre taşı.', 'trophy.fill');
  end if;
  if v_profile.total_reports >= 250 then
    perform private.pp_unlock_badge(p_user_id, 'reports:250', 'report_count', 'Saha Veterani', '250 rapora ulaştın. Takip izin derinleşiyor.', 'trophy.fill');
  end if;
  if v_profile.total_reports >= 500 then
    perform private.pp_unlock_badge(p_user_id, 'reports:500', 'report_count', 'Kıdemli Saha Lideri', '500 rapor, uzun soluklu bir saha disiplini gösterir.', 'trophy.fill');
  end if;
  if v_profile.total_reports >= 1000 then
    perform private.pp_unlock_badge(p_user_id, 'reports:1000', 'report_count', 'Bin Rapor Ustası', '1.000 rapora ulaştın. Bu büyük bir mesleki arşiv.', 'trophy.fill');
  end if;

  select count(*)
    into v_diversity
  from public.professional_progress_competency_stats
  where user_id = p_user_id
    and (finding_count > 0 or report_count > 0);

  if v_diversity >= 3 then
    perform private.pp_unlock_badge(p_user_id, 'competency:3', 'competency_diversity', 'Çok Yönlü Bakış', '3 farklı yetkinlik alanında risk dokümante ettin.', 'square.grid.2x2.fill');
  end if;
  if v_diversity >= 5 then
    perform private.pp_unlock_badge(p_user_id, 'competency:5', 'competency_diversity', 'Geniş Spektrum Uzmanı', '5 farklı yetkinlik alanında birikim oluşturdun.', 'square.grid.3x2.fill');
  end if;
  if v_diversity >= 8 then
    perform private.pp_unlock_badge(p_user_id, 'competency:8', 'competency_diversity', 'Tam Kapsamlı Analist', '8 farklı yetkinlik alanını görünür kıldın.', 'square.grid.3x3.fill');
  end if;
  if v_diversity >= 11 then
    perform private.pp_unlock_badge(p_user_id, 'competency:11', 'competency_diversity', 'Tam Spektrum Analisti', '11 yetkinlik alanının tamamında iz bıraktın.', 'sparkles');
  end if;

  if v_profile.critical_findings + v_profile.high_findings >= 1 then
    perform private.pp_unlock_badge(p_user_id, 'risk:first_high', 'risk', 'Cesur Karar', 'İlk yüksek/kritik riskli analizini tamamladın. Zor olanı görünür kıldın.', 'exclamationmark.triangle.fill');
  end if;

  if exists (
    select 1
    from public.professional_progress_events
    where user_id = p_user_id
      and event_type = 'report_created'
      and coalesce(metadata->>'risk_report', 'false') = 'true'
  ) then
    perform private.pp_unlock_badge(p_user_id, 'report_kind:first_risk_analysis', 'report_kind', 'Risk Analizi Raporu', 'İlk detaylı risk analizi raporunu arşivledin.', 'doc.richtext.fill');
  end if;

  if v_profile.active_days >= 30 then
    perform private.pp_unlock_badge(p_user_id, 'active_days:30', 'active_days', 'Bir Aylık Yolculuk', '30 farklı aktif günde analiz veya rapor ürettin.', 'calendar.badge.checkmark');
  end if;
  if v_profile.active_days >= 90 then
    perform private.pp_unlock_badge(p_user_id, 'active_days:90', 'active_days', 'Üç Aylık Süreklilik', '90 aktif güne yayılan mesleki takip izi oluşturdun.', 'calendar.badge.checkmark');
  end if;
  if v_profile.active_days >= 365 then
    perform private.pp_unlock_badge(p_user_id, 'active_days:365', 'active_days', 'Yıllık Birikim', 'Bir yıla yayılan aktif RiskDetected birikimi oluşturdun.', 'calendar.badge.checkmark');
  end if;

  for v_onboarding in
    select competency_key
    from public.professional_progress_competency_stats
    where user_id = p_user_id
      and onboarding_seed = true
      and report_count > 0
  loop
    perform private.pp_unlock_badge(
      p_user_id,
      'onboarding_area:first_report:' || v_onboarding.competency_key,
      'onboarding_area',
      'Beyan Edilen Alanda İlk Rapor',
      'Onboardingde belirttiğin çalışma alanında ilk gerçek raporunu oluşturdun.',
      'checkmark.seal.fill',
      jsonb_build_object('competency_key', v_onboarding.competency_key)
    );
  end loop;
end;
$$;
revoke all on function private.pp_unlock_badges_for_user(uuid) from public, anon, authenticated;

create or replace function private.pp_seed_competency(p_user_id uuid, p_competency_key text)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if p_competency_key is null then
    return;
  end if;

  insert into public.professional_progress_competency_stats (
    user_id,
    competency_key,
    onboarding_seed,
    updated_at
  )
  values (
    p_user_id,
    p_competency_key,
    true,
    now()
  )
  on conflict (user_id, competency_key) do update
  set onboarding_seed = true,
      updated_at = now();

  perform private.pp_record_event(
    p_user_id,
    'onboarding_competency_seeded:' || p_competency_key,
    'onboarding_competency_seeded',
    0,
    null,
    null,
    p_competency_key,
    jsonb_build_object('competency_key', p_competency_key),
    now()
  );
end;
$$;
revoke all on function private.pp_seed_competency(uuid, text) from public, anon, authenticated;

create or replace function private.pp_seed_onboarding_competencies()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  perform private.pp_ensure_profile(new.user_id);

  if 'mining' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'mining');
  end if;
  if 'construction' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'construction');
  end if;
  if 'manufacturing' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'factory');
  end if;
  if 'energy' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'chemical');
    perform private.pp_seed_competency(new.user_id, 'electrical');
    perform private.pp_seed_competency(new.user_id, 'fire');
  end if;
  if 'office' = any(new.sectors) then
    perform private.pp_seed_competency(new.user_id, 'ergonomics');
    perform private.pp_seed_competency(new.user_id, 'psychosocial');
  end if;

  return new;
exception when others then
  raise warning 'professional_progress onboarding seed failed for user %: %', new.user_id, sqlerrm;
  return new;
end;
$$;
revoke all on function private.pp_seed_onboarding_competencies() from public, anon, authenticated;

drop trigger if exists professional_progress_seed_onboarding on public.user_onboarding_answers;
create trigger professional_progress_seed_onboarding
  after insert or update of sectors on public.user_onboarding_answers
  for each row execute function private.pp_seed_onboarding_competencies();

create or replace function private.pp_process_analysis_completed()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_inserted boolean;
  v_analysis_mdp integer := 0;
  v_highest_risk text;
  v_onboarding_sectors text[] := '{}'::text[];
  v_finding record;
  v_class record;
  v_competency text;
  v_risk text;
  v_distinct_competencies text[] := '{}'::text[];
  v_total_findings integer := 0;
  v_critical integer := 0;
  v_high integer := 0;
  v_medium integer := 0;
  v_low integer := 0;
  v_unknown integer := 0;
begin
  if new.status <> 'completed' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'completed' then
    return new;
  end if;

  select private.pp_highest_risk_level(new.highest_band_fk::text, new.highest_band_m5::text)
    into v_highest_risk;

  if coalesce(new.analysis_mode, 'standard') <> 'standard' then
    v_analysis_mdp := v_analysis_mdp + 150;
  end if;
  if v_highest_risk in ('critical', 'high') then
    v_analysis_mdp := v_analysis_mdp + 200;
  end if;

  v_inserted := private.pp_record_event(
    new.user_id,
    'analysis_completed:' || new.id::text,
    'analysis_completed',
    v_analysis_mdp,
    new.id,
    null,
    null,
    jsonb_build_object(
      'analysis_mode', coalesce(new.analysis_mode, 'standard'),
      'highest_risk', v_highest_risk
    ),
    coalesce(new.completed_at, now())
  );
  if not v_inserted then
    return new;
  end if;

  select coalesce(uoa.sectors, '{}'::text[])
    into v_onboarding_sectors
  from public.user_onboarding_answers uoa
  where uoa.user_id = new.user_id;

  for v_finding in
    select *
    from public.findings f
    where f.analysis_id = new.id
      and f.user_id = new.user_id
  loop
    v_total_findings := v_total_findings + 1;
    v_risk := private.pp_highest_risk_level(v_finding.fk_band::text, v_finding.m5_band::text);
    if v_risk = 'critical' then
      v_critical := v_critical + 1;
    elsif v_risk = 'high' then
      v_high := v_high + 1;
    elsif v_risk = 'medium' then
      v_medium := v_medium + 1;
    elsif v_risk = 'low' then
      v_low := v_low + 1;
    else
      v_unknown := v_unknown + 1;
    end if;

    select *
      into v_class
    from private.pp_competency_for_finding(
      v_finding.category,
      v_finding.title,
      v_finding.description,
      v_finding.recommended_action,
      new.canvas::text,
      coalesce(v_onboarding_sectors, '{}'::text[])
    )
    limit 1;

    insert into public.professional_progress_finding_classifications (
      user_id,
      analysis_id,
      finding_id,
      competency_key,
      risk_level,
      source_category_text,
      matched_by,
      confidence
    )
    values (
      new.user_id,
      new.id,
      v_finding.id,
      case
        when v_class.competency_key is not null and coalesce(v_class.confidence, 0) >= 0.45
          then v_class.competency_key
        else 'unclassified'
      end,
      v_risk,
      coalesce(v_class.source_text, v_finding.category),
      case
        when v_class.competency_key is not null and coalesce(v_class.confidence, 0) >= 0.45
          then v_class.matched_by
        else 'unclassified'
      end,
      case
        when v_class.competency_key is not null and coalesce(v_class.confidence, 0) >= 0.45
          then v_class.confidence
        else 0
      end
    )
    on conflict (finding_id) do nothing;

    if v_class.competency_key is not null and coalesce(v_class.confidence, 0) >= 0.45 then
      insert into public.professional_progress_competency_stats (
        user_id,
        competency_key,
        finding_count,
        critical_count,
        high_count,
        medium_count,
        low_count,
        unknown_count,
        last_detected_at,
        updated_at
      )
      values (
        new.user_id,
        v_class.competency_key,
        1,
        case when v_risk = 'critical' then 1 else 0 end,
        case when v_risk = 'high' then 1 else 0 end,
        case when v_risk = 'medium' then 1 else 0 end,
        case when v_risk = 'low' then 1 else 0 end,
        case when v_risk = 'unknown' then 1 else 0 end,
        coalesce(new.completed_at, now()),
        now()
      )
      on conflict (user_id, competency_key) do update
      set finding_count = professional_progress_competency_stats.finding_count + 1,
          critical_count = professional_progress_competency_stats.critical_count + excluded.critical_count,
          high_count = professional_progress_competency_stats.high_count + excluded.high_count,
          medium_count = professional_progress_competency_stats.medium_count + excluded.medium_count,
          low_count = professional_progress_competency_stats.low_count + excluded.low_count,
          unknown_count = professional_progress_competency_stats.unknown_count + excluded.unknown_count,
          last_detected_at = greatest(coalesce(professional_progress_competency_stats.last_detected_at, excluded.last_detected_at), excluded.last_detected_at),
          updated_at = now();

      if not (v_class.competency_key = any(v_distinct_competencies)) then
        v_distinct_competencies := array_append(v_distinct_competencies, v_class.competency_key);
      end if;

      perform private.pp_record_event(
        new.user_id,
        'first_competency_used:' || v_class.competency_key,
        'first_competency_used',
        50,
        new.id,
        null,
        v_class.competency_key,
        jsonb_build_object('competency_key', v_class.competency_key),
        coalesce(new.completed_at, now())
      );
    end if;
  end loop;

  foreach v_competency in array v_distinct_competencies loop
    update public.professional_progress_competency_stats
    set analysis_count = analysis_count + 1,
        updated_at = now()
    where user_id = new.user_id
      and competency_key = v_competency;
  end loop;

  update public.professional_progress_profiles
  set total_analyses = total_analyses + 1,
      total_findings = total_findings + v_total_findings,
      critical_findings = critical_findings + v_critical,
      high_findings = high_findings + v_high,
      medium_findings = medium_findings + v_medium,
      low_findings = low_findings + v_low,
      unknown_findings = unknown_findings + v_unknown,
      updated_at = now()
  where user_id = new.user_id;

  perform private.pp_refresh_active_days(new.user_id);
  perform private.pp_refresh_weekly_summary(new.user_id, coalesce(new.completed_at, now()));
  perform private.pp_unlock_badges_for_user(new.user_id);

  return new;
exception when others then
  raise warning 'professional_progress analysis processing failed for analysis %: %', new.id, sqlerrm;
  return new;
end;
$$;
revoke all on function private.pp_process_analysis_completed() from public, anon, authenticated;

drop trigger if exists professional_progress_analysis_completed on public.analyses;
create trigger professional_progress_analysis_completed
  after insert or update of status on public.analyses
  for each row execute function private.pp_process_analysis_completed();

create or replace function private.pp_process_report_created()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_mdp integer := 100;
  v_is_risk_report boolean := false;
  v_inserted boolean;
  v_week_start date;
  v_week_reports integer;
  v_month_findings integer;
  v_best record;
  v_competency text;
begin
  v_is_risk_report := coalesce(new.kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(new.format, '') = 'xlsx';
  if v_is_risk_report then
    v_mdp := v_mdp + 150;
  end if;

  v_inserted := private.pp_record_event(
    new.user_id,
    'report_created:' || new.id::text,
    'report_created',
    v_mdp,
    new.analysis_id,
    new.id,
    null,
    jsonb_build_object(
      'format', new.format,
      'kind', new.kind,
      'risk_report', v_is_risk_report
    ),
    new.created_at
  );
  if not v_inserted then
    return new;
  end if;

  update public.professional_progress_profiles
  set total_reports = total_reports + 1,
      updated_at = now()
  where user_id = new.user_id;

  for v_competency in
    select distinct competency_key
    from public.professional_progress_finding_classifications
    where user_id = new.user_id
      and analysis_id = new.analysis_id
      and competency_key <> 'unclassified'
  loop
    update public.professional_progress_competency_stats
    set report_count = report_count + 1,
        updated_at = now()
    where user_id = new.user_id
      and competency_key = v_competency;
  end loop;

  v_week_start := (date_trunc('week', new.created_at at time zone 'Europe/Istanbul'))::date;
  perform private.pp_record_event(
    new.user_id,
    'weekly_bonus:' || v_week_start::text,
    'weekly_report_bonus',
    75,
    null,
    new.id,
    null,
    jsonb_build_object('week_start', v_week_start),
    new.created_at
  );

  select count(*)
    into v_week_reports
  from public.reports r
  where r.user_id = new.user_id
    and (r.created_at at time zone 'Europe/Istanbul')::date >= v_week_start
    and (r.created_at at time zone 'Europe/Istanbul')::date < v_week_start + 7;

  select coalesce(sum(finding_count), 0)
    into v_month_findings
  from public.professional_progress_competency_stats
  where user_id = new.user_id;

  select c.competency_key, c.risk_level, count(*)::int as count
    into v_best
  from public.professional_progress_finding_classifications c
  where c.user_id = new.user_id
    and c.analysis_id = new.analysis_id
    and c.competency_key <> 'unclassified'
  group by c.competency_key, c.risk_level
  order by private.pp_risk_rank(c.risk_level) desc, count(*) desc
  limit 1;

  if v_best.competency_key is not null then
    perform private.pp_insert_message(
      new.user_id,
      'instant',
      'Rapor arşivlendi',
      case
        when v_best.risk_level in ('critical', 'high') then
          'Bu raporda ' || private.pp_competency_label(v_best.competency_key) || ' alanında yüksek/kritik riskleri görünür kıldın.'
        else
          'Bu hafta ' || coalesce(v_week_reports, 1)::text || '. raporun. İstikrarlı ilerliyorsun.'
      end,
      new.analysis_id,
      new.id,
      v_best.competency_key,
      v_best.risk_level,
      jsonb_build_object('week_reports', v_week_reports, 'total_documented_risks', v_month_findings)
    );
  else
    perform private.pp_insert_message(
      new.user_id,
      'instant',
      'Rapor arşivlendi',
      'Bu hafta ' || coalesce(v_week_reports, 1)::text || '. raporun. İstikrarlı ilerliyorsun.',
      new.analysis_id,
      new.id,
      null,
      null,
      jsonb_build_object('week_reports', v_week_reports, 'total_documented_risks', v_month_findings)
    );
  end if;

  perform private.pp_refresh_active_days(new.user_id);
  perform private.pp_refresh_weekly_summary(new.user_id, new.created_at);
  perform private.pp_unlock_badges_for_user(new.user_id);

  return new;
exception when others then
  raise warning 'professional_progress report processing failed for report %: %', new.id, sqlerrm;
  return new;
end;
$$;
revoke all on function private.pp_process_report_created() from public, anon, authenticated;

drop trigger if exists professional_progress_report_created on public.reports;
create trigger professional_progress_report_created
  after insert on public.reports
  for each row execute function private.pp_process_report_created();

-- Initial backfill is summary-only and idempotent. It deliberately does not
-- generate one event per historical report/analysis.
insert into public.professional_progress_profiles (
  user_id,
  total_analyses,
  total_reports,
  total_findings,
  critical_findings,
  high_findings,
  medium_findings,
  low_findings,
  unknown_findings,
  active_days,
  current_title_key,
  created_at,
  updated_at
)
select
  p.id,
  coalesce(a.analysis_count, 0),
  coalesce(r.report_count, 0),
  coalesce(f.finding_count, 0),
  coalesce(f.critical_count, 0),
  coalesce(f.high_count, 0),
  coalesce(f.medium_count, 0),
  coalesce(f.low_count, 0),
  coalesce(f.unknown_count, 0),
  coalesce(ad.active_days, 0),
  'candidate',
  now(),
  now()
from public.profiles p
left join (
  select user_id, count(*)::int as analysis_count
  from public.analyses
  where status = 'completed'
  group by user_id
) a on a.user_id = p.id
left join (
  select user_id, count(*)::int as report_count
  from public.reports
  group by user_id
) r on r.user_id = p.id
left join (
  select
    user_id,
    count(*)::int as finding_count,
    count(*) filter (where private.pp_highest_risk_level(fk_band::text, m5_band::text) = 'critical')::int as critical_count,
    count(*) filter (where private.pp_highest_risk_level(fk_band::text, m5_band::text) = 'high')::int as high_count,
    count(*) filter (where private.pp_highest_risk_level(fk_band::text, m5_band::text) = 'medium')::int as medium_count,
    count(*) filter (where private.pp_highest_risk_level(fk_band::text, m5_band::text) = 'low')::int as low_count,
    count(*) filter (where private.pp_highest_risk_level(fk_band::text, m5_band::text) = 'unknown')::int as unknown_count
  from public.findings
  group by user_id
) f on f.user_id = p.id
left join (
  select user_id, count(distinct active_day)::int as active_days
  from (
    select user_id, (created_at at time zone 'Europe/Istanbul')::date as active_day
    from public.analyses
    where status = 'completed'
    union
    select user_id, (created_at at time zone 'Europe/Istanbul')::date as active_day
    from public.reports
  ) days
  group by user_id
) ad on ad.user_id = p.id
on conflict (user_id) do nothing;

insert into public.professional_progress_competency_stats (
  user_id,
  competency_key,
  onboarding_seed,
  updated_at
)
select user_id, competency_key, true, now()
from (
  select user_id, 'mining'::text as competency_key
  from public.user_onboarding_answers
  where 'mining' = any(sectors)
  union all
  select user_id, 'construction'::text
  from public.user_onboarding_answers
  where 'construction' = any(sectors)
  union all
  select user_id, 'factory'::text
  from public.user_onboarding_answers
  where 'manufacturing' = any(sectors)
  union all
  select user_id, 'chemical'::text
  from public.user_onboarding_answers
  where 'energy' = any(sectors)
  union all
  select user_id, 'electrical'::text
  from public.user_onboarding_answers
  where 'energy' = any(sectors)
  union all
  select user_id, 'fire'::text
  from public.user_onboarding_answers
  where 'energy' = any(sectors)
  union all
  select user_id, 'ergonomics'::text
  from public.user_onboarding_answers
  where 'office' = any(sectors)
  union all
  select user_id, 'psychosocial'::text
  from public.user_onboarding_answers
  where 'office' = any(sectors)
) seeds
on conflict (user_id, competency_key) do update
set onboarding_seed = true,
    updated_at = now();

insert into public.professional_progress_finding_classifications (
  user_id,
  analysis_id,
  finding_id,
  competency_key,
  risk_level,
  source_category_text,
  matched_by,
  confidence
)
select
  f.user_id,
  f.analysis_id,
  f.id,
  case
    when c.competency_key is not null and coalesce(c.confidence, 0) >= 0.45
      then c.competency_key
    else 'unclassified'
  end,
  private.pp_highest_risk_level(f.fk_band::text, f.m5_band::text),
  coalesce(c.source_text, f.category),
  case
    when c.competency_key is not null and coalesce(c.confidence, 0) >= 0.45
      then c.matched_by
    else 'unclassified'
  end,
  case
    when c.competency_key is not null and coalesce(c.confidence, 0) >= 0.45
      then c.confidence
    else 0
  end
from public.findings f
join public.analyses a on a.id = f.analysis_id
left join public.user_onboarding_answers uoa on uoa.user_id = f.user_id
left join lateral private.pp_competency_for_finding(
  f.category,
  f.title,
  f.description,
  f.recommended_action,
  a.canvas::text,
  coalesce(uoa.sectors, '{}'::text[])
) c on true
on conflict (finding_id) do nothing;

insert into public.professional_progress_competency_stats (
  user_id,
  competency_key,
  analysis_count,
  finding_count,
  critical_count,
  high_count,
  medium_count,
  low_count,
  unknown_count,
  last_detected_at,
  updated_at
)
select
  c.user_id,
  c.competency_key,
  count(distinct c.analysis_id)::int,
  count(*)::int,
  count(*) filter (where c.risk_level = 'critical')::int,
  count(*) filter (where c.risk_level = 'high')::int,
  count(*) filter (where c.risk_level = 'medium')::int,
  count(*) filter (where c.risk_level = 'low')::int,
  count(*) filter (where c.risk_level = 'unknown')::int,
  max(a.completed_at),
  now()
from public.professional_progress_finding_classifications c
join public.analyses a on a.id = c.analysis_id
where c.competency_key <> 'unclassified'
group by c.user_id, c.competency_key
on conflict (user_id, competency_key) do update
set analysis_count = excluded.analysis_count,
    finding_count = excluded.finding_count,
    critical_count = excluded.critical_count,
    high_count = excluded.high_count,
    medium_count = excluded.medium_count,
    low_count = excluded.low_count,
    unknown_count = excluded.unknown_count,
    last_detected_at = excluded.last_detected_at,
    onboarding_seed = professional_progress_competency_stats.onboarding_seed or excluded.onboarding_seed,
    updated_at = now();

insert into public.professional_progress_competency_stats (
  user_id,
  competency_key,
  report_count,
  updated_at
)
select
  r.user_id,
  c.competency_key,
  count(distinct r.id)::int,
  now()
from public.reports r
join public.professional_progress_finding_classifications c
  on c.analysis_id = r.analysis_id
 and c.user_id = r.user_id
 and c.competency_key <> 'unclassified'
group by r.user_id, c.competency_key
on conflict (user_id, competency_key) do update
set report_count = excluded.report_count,
    updated_at = now();

with mdp_calc as (
  select
    p.id as user_id,
    (
      coalesce(r.report_count, 0) * 100 +
      coalesce(r.risk_report_count, 0) * 150 +
      coalesce(a.detailed_count, 0) * 150 +
      coalesce(a.high_risk_count, 0) * 200 +
      coalesce(c.competency_count, 0) * 50 +
      coalesce(w.report_weeks, 0) * 75
    )::int as total_mdp
  from public.profiles p
  left join (
    select
      user_id,
      count(*)::int as report_count,
      count(*) filter (
        where kind in ('riskAnalysis', 'risk_analysis') or format = 'xlsx'
      )::int as risk_report_count
    from public.reports
    group by user_id
  ) r on r.user_id = p.id
  left join (
    select
      user_id,
      count(*) filter (where coalesce(analysis_mode, 'standard') <> 'standard')::int as detailed_count,
      count(*) filter (
        where private.pp_highest_risk_level(highest_band_fk::text, highest_band_m5::text) in ('critical', 'high')
      )::int as high_risk_count
    from public.analyses
    where status = 'completed'
    group by user_id
  ) a on a.user_id = p.id
  left join (
    select user_id, count(*)::int as competency_count
    from public.professional_progress_competency_stats
    where finding_count > 0 or report_count > 0
    group by user_id
  ) c on c.user_id = p.id
  left join (
    select
      user_id,
      count(distinct date_trunc('week', created_at at time zone 'Europe/Istanbul')::date)::int as report_weeks
    from public.reports
    group by user_id
  ) w on w.user_id = p.id
)
update public.professional_progress_profiles pp
set total_mdp = mdp_calc.total_mdp,
    current_title_key = private.pp_title_key_for_mdp(mdp_calc.total_mdp),
    updated_at = now()
from mdp_calc
where pp.user_id = mdp_calc.user_id;

insert into public.professional_progress_events (
  user_id,
  event_key,
  event_type,
  mdp_delta,
  metadata
)
select
  user_id,
  'backfill_seed:2026-05-26',
  'backfill_seed',
  0,
  jsonb_build_object(
    'total_analyses', total_analyses,
    'total_reports', total_reports,
    'total_findings', total_findings
  )
from public.professional_progress_profiles
on conflict (user_id, event_key) do nothing;

select pg_notify('pgrst', 'reload schema');
