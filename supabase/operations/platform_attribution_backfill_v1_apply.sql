-- Run platform_attribution_backfill_v1.sql and approve its aggregate first.
-- This apply is idempotent, writes only NULL signup_platform rows, and locks at
-- most 500 profiles per batch. It emits aggregate counts only (no user IDs).
begin;

create temporary table platform_attribution_candidates on commit drop as
with observations as (
  select a.user_id, a.client_platform as platform, a.created_at as observed_at
  from public.analyses a
  where a.client_platform in ('ios', 'android')
  union all
  select d.user_id, d.platform, d.created_at
  from public.push_device_tokens d
  where d.platform in ('ios', 'android')
)
select distinct on (user_id) user_id, platform, observed_at
from observations
order by user_id, observed_at asc, platform asc;

do $backfill$
declare
  v_updated integer;
begin
  loop
    with batch as (
      select p.id, c.platform, c.observed_at
      from public.profiles p
      join platform_attribution_candidates c on c.user_id = p.id
      where p.signup_platform is null
      order by p.id
      for update of p skip locked
      limit 500
    )
    update public.profiles p
    set signup_platform = b.platform,
        signup_platform_source = 'inferred_activity',
        signup_platform_recorded_at = b.observed_at
    from batch b
    where p.id = b.id and p.signup_platform is null;

    get diagnostics v_updated = row_count;
    exit when v_updated = 0;
  end loop;
end
$backfill$;

select
  coalesce(signup_platform, 'unknown') as signup_platform,
  signup_platform_source,
  count(*) as profiles
from public.profiles
group by coalesce(signup_platform, 'unknown'), signup_platform_source
order by signup_platform, signup_platform_source;

commit;
