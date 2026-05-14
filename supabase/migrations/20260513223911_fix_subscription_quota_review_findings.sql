-- Make report quota checks atomic and keep paid access through a cancelled
-- subscription's already-paid period.

create or replace function private.user_plan_tier(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce((
    select us.tier
    from public.user_subscriptions us
    where us.user_id = p_user_id
      and us.tier in ('plus', 'pro')
      and us.status in ('active', 'trialing', 'grace_period')
      and (us.current_period_ends_at is null or us.current_period_ends_at > now())
    order by case us.tier when 'pro' then 2 when 'plus' then 1 else 0 end desc,
             us.updated_at desc
    limit 1
  ), 'free');
$$;

revoke all on function private.user_plan_tier(uuid) from public, anon, authenticated;

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
begin
  tier := coalesce(private.user_plan_tier(new.user_id), 'free');
  monthly_limit := private.report_monthly_limit(tier);

  if monthly_limit is null then
    return new;
  end if;

  month_start := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  month_end := month_start + interval '1 month';

  perform pg_advisory_xact_lock(hashtext(new.user_id::text || ':report_quota:' || month_start::text));

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

drop trigger if exists reports_enforce_plan_limits on public.reports;
create trigger reports_enforce_plan_limits
  before insert on public.reports
  for each row
  execute function public.enforce_report_plan_limits();

select pg_notify('pgrst', 'reload schema');
