-- Give Free users one lifetime Risk Analysis Table trial while keeping
-- monthly report quotas enforced from the same atomic trigger.

create or replace function public.enforce_report_plan_limits()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  tier text;
  monthly_limit integer;
  month_start timestamptz;
  month_end timestamptz;
  used_count integer;
  risk_trial_used integer;
  is_risk_analysis_report boolean;
begin
  tier := coalesce(private.user_plan_tier(new.user_id), 'free');
  monthly_limit := private.report_monthly_limit(tier);
  is_risk_analysis_report :=
    coalesce(new.kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(new.format, '') = 'xlsx';

  month_start := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  month_end := month_start + interval '1 month';

  perform pg_advisory_xact_lock(hashtext(new.user_id::text || ':report_quota:' || month_start::text));

  if tier = 'free' and is_risk_analysis_report then
    select count(*)
      into risk_trial_used
    from public.reports r
    where r.user_id = new.user_id
      and (
        coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
        or coalesce(r.format, '') = 'xlsx'
      );

    if risk_trial_used >= 1 then
      raise exception 'free_risk_analysis_trial_exhausted:1/1'
        using errcode = 'P0001',
              hint = 'Free users can create one risk analysis table as a trial.';
    end if;
  end if;

  if monthly_limit is null then
    return new;
  end if;

  select count(*)
    into used_count
  from public.reports r
  where r.user_id = new.user_id
    and r.created_at >= month_start
    and r.created_at < month_end;

  if used_count >= monthly_limit then
    raise exception 'report_quota_exceeded:%/%', monthly_limit, monthly_limit
      using errcode = 'P0001',
            hint = 'Upgrade plan or wait until the next monthly quota period.';
  end if;

  return new;
end;
$$;

select pg_notify('pgrst', 'reload schema');
