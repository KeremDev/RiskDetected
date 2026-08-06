-- Admin dashboard "Son aktivite" should reflect app usage, not only auth.last_sign_in_at.
-- Users with a valid session can analyze without triggering a new sign-in event.

drop function if exists public.admin_recent_sign_ins(integer);

create function public.admin_recent_sign_ins(p_limit integer default 5)
returns table (
  user_id uuid,
  email text,
  last_sign_in_at timestamptz,
  last_activity_at timestamptz
)
language sql
stable
security definer
set search_path = auth, public
as $$
  with per_user as (
    select
      u.id as user_id,
      u.email::text as email,
      u.last_sign_in_at,
      greatest(
        coalesce(u.last_sign_in_at, '-infinity'::timestamptz),
        coalesce(
          (select max(a.created_at) from public.analyses a where a.user_id = u.id),
          '-infinity'::timestamptz
        ),
        coalesce(
          (select max(r.created_at) from public.reports r where r.user_id = u.id),
          '-infinity'::timestamptz
        ),
        coalesce(
          (select max(e.created_at) from public.usage_events e where e.user_id = u.id),
          '-infinity'::timestamptz
        )
      ) as last_activity_at
    from auth.users u
  )
  select
    user_id,
    email,
    last_sign_in_at,
    last_activity_at
  from per_user
  where last_activity_at > '-infinity'::timestamptz
  order by last_activity_at desc
  limit greatest(1, least(coalesce(p_limit, 5), 20));
$$;

revoke all on function public.admin_recent_sign_ins(integer) from public;
grant execute on function public.admin_recent_sign_ins(integer) to service_role;
