-- Mandatory read-only dry run. This file never mutates production data.
begin;
set local transaction read only;

with observations as (
  select a.user_id, a.client_platform as platform, a.created_at as observed_at
  from public.analyses a
  where a.client_platform in ('ios', 'android')
  union all
  select d.user_id, d.platform, d.created_at
  from public.push_device_tokens d
  where d.platform in ('ios', 'android')
), earliest as (
  select distinct on (user_id) user_id, platform, observed_at
  from observations
  order by user_id, observed_at asc, platform asc
), preview as (
  select
    count(*) filter (where p.signup_platform is null and e.platform = 'ios') as will_set_ios,
    count(*) filter (where p.signup_platform is null and e.platform = 'android') as will_set_android,
    count(*) filter (where p.signup_platform is null and e.platform is null) as will_remain_unknown,
    count(*) filter (where p.signup_platform is not null) as already_attributed
  from public.profiles p
  left join earliest e on e.user_id = p.id
)
select * from preview;
rollback;
