-- Weekly tracking messages for Professional Progress.
-- Keeps the app-facing weekly summary useful even when the user has no current
-- week activity, without adding pressure or legal-sounding claims.

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
  v_title text := 'Haftalık Takip';
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

  if coalesce(v_reports, 0) = 0 and coalesce(v_analyses, 0) = 0 then
    v_body := 'Bu hafta ilk analizini başlat. 😔';
  elsif coalesce(v_reports, 0) = 0 then
    v_body := coalesce(v_analyses, 0)::text ||
      ' analiz tamamladın. Şimdi rapora dönüştür.';
  elsif coalesce(v_reports, 0) = 1 then
    v_body := 'İlk rapor tamam. Devam et.';
  else
    v_body := 'Bu hafta ' || coalesce(v_reports, 0)::text ||
      ' rapor tamamladın. 💪';
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

create or replace function private.pp_refresh_weekly_summaries_for_week(
  p_reference_at timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_profile record;
  v_count integer := 0;
begin
  for v_profile in
    select user_id
    from public.professional_progress_profiles
  loop
    perform private.pp_refresh_weekly_summary(v_profile.user_id, p_reference_at);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;
revoke all on function private.pp_refresh_weekly_summaries_for_week(timestamptz) from public, anon, authenticated;

create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'riskdetected-professional-progress-weekly-tracking'
  ) then
    perform cron.unschedule('riskdetected-professional-progress-weekly-tracking');
  end if;
end $$;

select cron.schedule(
  'riskdetected-professional-progress-weekly-tracking',
  '30 6 * * 1',
  $$
  select private.pp_refresh_weekly_summaries_for_week(now());
  $$
);

select private.pp_refresh_weekly_summaries_for_week(now());

select pg_notify('pgrst', 'reload schema');
