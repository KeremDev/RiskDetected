-- Professional Progress economy v2.
-- Slows title progression, reduces per-action MDP, and caps one
-- analysis/report workflow at 400 MDP so heavy report exports cannot jump ranks.

create or replace function private.pp_title_key_for_mdp(p_mdp integer)
returns text
language sql
immutable
as $$
  select case
    when coalesce(p_mdp, 0) >= 180000 then 'master_hse_specialist'
    when coalesce(p_mdp, 0) >= 90000 then 'safety_strategist'
    when coalesce(p_mdp, 0) >= 40000 then 'senior_risk_specialist'
    when coalesce(p_mdp, 0) >= 15000 then 'hazard_analyst'
    when coalesce(p_mdp, 0) >= 5000 then 'risk_hunter'
    when coalesce(p_mdp, 0) >= 1000 then 'field_observer'
    else 'candidate'
  end;
$$;
revoke all on function private.pp_title_key_for_mdp(integer) from public, anon, authenticated;

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
    v_analysis_mdp := v_analysis_mdp + 70;
  end if;
  if v_highest_risk in ('critical', 'high') then
    v_analysis_mdp := v_analysis_mdp + 120;
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
      'highest_risk', v_highest_risk,
      'economy_version', 'v2_2026_05_26'
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
        20,
        new.id,
        null,
        v_class.competency_key,
        jsonb_build_object(
          'competency_key', v_class.competency_key,
          'economy_version', 'v2_2026_05_26'
        ),
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

create or replace function private.pp_process_report_created()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_mdp integer := 60;
  v_uncapped_mdp integer := 60;
  v_is_risk_report boolean := false;
  v_workflow_existing_mdp integer := 0;
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
    v_uncapped_mdp := v_uncapped_mdp + 90;
  end if;

  v_mdp := v_uncapped_mdp;

  if new.analysis_id is not null then
    select coalesce(sum(mdp_delta), 0)::int
      into v_workflow_existing_mdp
    from public.professional_progress_events
    where user_id = new.user_id
      and analysis_id = new.analysis_id
      and event_type in ('analysis_completed', 'first_competency_used', 'report_created');

    v_mdp := least(v_uncapped_mdp, greatest(400 - coalesce(v_workflow_existing_mdp, 0), 0));
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
      'risk_report', v_is_risk_report,
      'uncapped_mdp', v_uncapped_mdp,
      'workflow_cap_mdp', 400,
      'workflow_existing_mdp', v_workflow_existing_mdp,
      'economy_version', 'v2_2026_05_26'
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
    25,
    null,
    new.id,
    null,
    jsonb_build_object(
      'week_start', v_week_start,
      'economy_version', 'v2_2026_05_26'
    ),
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

-- Reprice any existing event ledger rows so event-based totals stay consistent.
update public.professional_progress_events e
set mdp_delta =
      (case when coalesce(a.analysis_mode, 'standard') <> 'standard' then 70 else 0 end)
    + (case when private.pp_highest_risk_level(a.highest_band_fk::text, a.highest_band_m5::text) in ('critical', 'high') then 120 else 0 end),
    metadata = coalesce(e.metadata, '{}'::jsonb) || jsonb_build_object('economy_version', 'v2_2026_05_26')
from public.analyses a
where e.event_type = 'analysis_completed'
  and e.analysis_id = a.id;

update public.professional_progress_events
set mdp_delta = 20,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('economy_version', 'v2_2026_05_26')
where event_type = 'first_competency_used';

update public.professional_progress_events
set mdp_delta = 25,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('economy_version', 'v2_2026_05_26')
where event_type = 'weekly_report_bonus';

with report_base as (
  select
    e.id as event_id,
    e.user_id,
    e.analysis_id,
    e.occurred_at,
    case
      when coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
        or coalesce(r.format, '') = 'xlsx'
        or coalesce(e.metadata->>'risk_report', 'false') = 'true'
        then 150::bigint
      else 60::bigint
    end as base_mdp
  from public.professional_progress_events e
  left join public.reports r on r.id = e.report_id
  where e.event_type = 'report_created'
),
workflow_mdp as (
  select
    user_id,
    analysis_id,
    sum(mdp_delta)::bigint as mdp
  from public.professional_progress_events
  where event_type in ('analysis_completed', 'first_competency_used')
    and analysis_id is not null
  group by user_id, analysis_id
),
report_scored as (
  select
    rb.event_id,
    rb.base_mdp,
    case
      when rb.analysis_id is null then rb.base_mdp
      else least(
        rb.base_mdp,
        greatest(
          400::bigint
          - coalesce(wm.mdp, 0)
          - coalesce(sum(rb.base_mdp) over (
              partition by rb.user_id, rb.analysis_id
              order by rb.occurred_at, rb.event_id
              rows between unbounded preceding and 1 preceding
            ), 0),
          0
        )
      )
    end as capped_mdp
  from report_base rb
  left join workflow_mdp wm
    on wm.user_id = rb.user_id
   and wm.analysis_id = rb.analysis_id
)
update public.professional_progress_events e
set mdp_delta = report_scored.capped_mdp::int,
    metadata = coalesce(e.metadata, '{}'::jsonb) || jsonb_build_object(
      'economy_version', 'v2_2026_05_26',
      'uncapped_mdp', report_scored.base_mdp,
      'workflow_cap_mdp', 400
    )
from report_scored
where e.id = report_scored.event_id;

-- Recalculate profile totals from source tables. This also fixes databases that
-- were backfilled before individual historical events existed.
insert into public.professional_progress_profiles (user_id)
select p.id
from public.profiles p
on conflict (user_id) do nothing;

with analysis_scores as (
  select
    a.user_id,
    a.id as analysis_id,
    (
      case when coalesce(a.analysis_mode, 'standard') <> 'standard' then 70 else 0 end
      + case when private.pp_highest_risk_level(a.highest_band_fk::text, a.highest_band_m5::text) in ('critical', 'high') then 120 else 0 end
    )::bigint as mdp
  from public.analyses a
  where a.status = 'completed'
),
first_competency as (
  select user_id, analysis_id, count(*)::bigint * 20 as mdp
  from (
    select distinct on (user_id, competency_key)
      user_id,
      competency_key,
      analysis_id,
      created_at
    from public.professional_progress_finding_classifications
    where competency_key <> 'unclassified'
    order by user_id, competency_key, created_at, analysis_id
  ) firsts
  group by user_id, analysis_id
),
report_base as (
  select
    r.user_id,
    r.id as report_id,
    r.analysis_id,
    r.created_at,
    case
      when coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
        or coalesce(r.format, '') = 'xlsx'
        then 150::bigint
      else 60::bigint
    end as base_mdp
  from public.reports r
),
report_scored as (
  select
    rb.user_id,
    rb.report_id,
    case
      when rb.analysis_id is null then rb.base_mdp
      else least(
        rb.base_mdp,
        greatest(
          400::bigint
          - coalesce(a.mdp, 0)
          - coalesce(fc.mdp, 0)
          - coalesce(sum(rb.base_mdp) over (
              partition by rb.user_id, rb.analysis_id
              order by rb.created_at, rb.report_id
              rows between unbounded preceding and 1 preceding
            ), 0),
          0
        )
      )
    end as mdp
  from report_base rb
  left join analysis_scores a
    on a.user_id = rb.user_id
   and a.analysis_id = rb.analysis_id
  left join first_competency fc
    on fc.user_id = rb.user_id
   and fc.analysis_id = rb.analysis_id
),
analysis_totals as (
  select user_id, sum(mdp)::bigint as mdp
  from analysis_scores
  group by user_id
),
first_competency_totals as (
  select user_id, sum(mdp)::bigint as mdp
  from first_competency
  group by user_id
),
report_totals as (
  select user_id, sum(mdp)::bigint as mdp
  from report_scored
  group by user_id
),
weekly_totals as (
  select
    user_id,
    count(distinct date_trunc('week', created_at at time zone 'Europe/Istanbul')::date)::bigint * 25 as mdp
  from public.reports
  group by user_id
),
source_mdp as (
  select
    pp.user_id,
    (
      coalesce(a.mdp, 0)
      + coalesce(fc.mdp, 0)
      + coalesce(r.mdp, 0)
      + coalesce(w.mdp, 0)
    )::int as total_mdp
  from public.professional_progress_profiles pp
  left join analysis_totals a on a.user_id = pp.user_id
  left join first_competency_totals fc on fc.user_id = pp.user_id
  left join report_totals r on r.user_id = pp.user_id
  left join weekly_totals w on w.user_id = pp.user_id
)
update public.professional_progress_profiles pp
set total_mdp = source_mdp.total_mdp,
    current_title_key = private.pp_title_key_for_mdp(source_mdp.total_mdp),
    updated_at = now()
from source_mdp
where pp.user_id = source_mdp.user_id;

select pg_notify('pgrst', 'reload schema');
