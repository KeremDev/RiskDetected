-- Reject exhausted report quotas before Edge Functions download and buffer the
-- uploaded report object. The existing BEFORE INSERT trigger remains the final
-- atomic authority and closes races after this inexpensive preflight check.

create or replace function public.check_report_quota_eligibility(
  p_user_id uuid,
  p_kind text,
  p_format text default 'pdf'
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  tier text;
  monthly_limit integer;
  period_start timestamptz;
  period_end timestamptz;
  used_count integer := 0;
  quota_feature text;
  is_risk_analysis_report boolean;
begin
  if p_user_id is null then
    raise exception 'report_quota_user_required' using errcode = '22023';
  end if;

  tier := coalesce(private.user_plan_tier(p_user_id), 'free');
  monthly_limit := private.report_monthly_limit(tier);
  is_risk_analysis_report :=
    coalesce(p_kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(p_format, '') = 'xlsx';

  if tier = 'free' and is_risk_analysis_report then
    quota_feature := 'report_risk_analysis_trial';

    select count(*) into used_count
    from public.usage_events ue
    where ue.user_id = p_user_id
      and ue.feature = quota_feature
      and ue.event_type = 'completed';

    select used_count + count(*) into used_count
    from public.reports r
    where r.user_id = p_user_id
      and (
        coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
        or coalesce(r.format, '') = 'xlsx'
      )
      and not exists (
        select 1
        from public.usage_events ue
        where ue.user_id = r.user_id
          and ue.source_id = r.id
          and ue.feature = quota_feature
      );

    return jsonb_build_object(
      'allowed', used_count < 1,
      'error_code', case when used_count >= 1 then 'free_risk_analysis_trial_exhausted' else null end,
      'limit', 1,
      'used', used_count,
      'period', 'lifetime'
    );
  end if;

  if tier = 'free' then
    quota_feature := 'report_standard';
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
    period_end := period_start + interval '1 day';
    monthly_limit := 1;
  elsif monthly_limit is not null then
    quota_feature := 'report_standard';
    period_start := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
    period_end := period_start + interval '1 month';
  else
    return jsonb_build_object(
      'allowed', true,
      'error_code', null,
      'limit', null,
      'used', 0,
      'period', 'unlimited'
    );
  end if;

  select count(*) into used_count
  from public.usage_events ue
  where ue.user_id = p_user_id
    and ue.feature = quota_feature
    and ue.event_type = 'completed'
    and ue.created_at >= period_start
    and ue.created_at < period_end;

  select used_count + count(*) into used_count
  from public.reports r
  where r.user_id = p_user_id
    and r.created_at >= period_start
    and r.created_at < period_end
    and (tier <> 'free' or not (
      coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
      or coalesce(r.format, '') = 'xlsx'
    ))
    and not exists (
      select 1
      from public.usage_events ue
      where ue.user_id = r.user_id
        and ue.source_id = r.id
        and ue.feature = quota_feature
    );

  return jsonb_build_object(
    'allowed', used_count < monthly_limit,
    'error_code', case when used_count >= monthly_limit then 'report_quota_exceeded' else null end,
    'limit', monthly_limit,
    'used', used_count,
    'period', case when tier = 'free' then 'daily' else 'monthly' end
  );
end;
$$;

revoke all on function public.check_report_quota_eligibility(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.check_report_quota_eligibility(uuid, text, text)
  to service_role;
