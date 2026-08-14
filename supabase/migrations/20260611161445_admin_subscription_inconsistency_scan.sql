create or replace function public.admin_subscription_inconsistency_scan()
returns table (
  user_id uuid,
  email text,
  full_name text,
  profile_tier text,
  subscription_tier text,
  subscription_status text,
  current_period_ends_at timestamptz,
  subscription_updated_at timestamptz,
  issue_type text,
  severity text,
  description text
)
language sql
stable
security definer
set search_path = public
as $$
  with joined as (
    select
      p.id as user_id,
      p.email,
      p.full_name,
      coalesce(p.tier::text, 'free') as profile_tier,
      us.tier as subscription_tier,
      us.status as subscription_status,
      us.current_period_ends_at,
      us.updated_at as subscription_updated_at
    from public.profiles p
    left join public.user_subscriptions us on us.user_id = p.id
  ),
  classified as (
    select
      j.*,
      case
        when j.subscription_tier is null and j.profile_tier in ('plus', 'pro')
          then 'missing_subscription'
        when j.subscription_tier is not null and j.profile_tier is distinct from j.subscription_tier
          then 'tier_mismatch'
        when j.profile_tier = 'free'
          and j.subscription_tier in ('plus', 'pro')
          and j.subscription_status in ('active', 'trialing', 'grace_period')
          then 'active_sub_profile_free'
        when j.profile_tier in ('plus', 'pro')
          and (
            j.subscription_tier is null
            or j.subscription_status is null
            or j.subscription_status not in ('active', 'trialing', 'grace_period')
          )
          then 'profile_paid_inactive_sub'
        else null
      end as issue_type
    from joined j
  )
  select
    c.user_id,
    c.email,
    c.full_name,
    c.profile_tier,
    coalesce(c.subscription_tier, '—') as subscription_tier,
    coalesce(c.subscription_status, 'missing') as subscription_status,
    c.current_period_ends_at,
    c.subscription_updated_at,
    c.issue_type,
    case
      when c.issue_type in ('missing_subscription', 'tier_mismatch', 'active_sub_profile_free')
        then 'high'
      else 'medium'
    end as severity,
    case c.issue_type
      when 'missing_subscription'
        then 'Profil ücretli plan gösteriyor ancak abonelik kaydı yok'
      when 'tier_mismatch'
        then 'Profil planı ile RevenueCat abonelik planı uyuşmuyor'
      when 'active_sub_profile_free'
        then 'Aktif ücretli abonelik var ancak profil Free görünüyor'
      when 'profile_paid_inactive_sub'
        then 'Profil ücretli plan gösteriyor ancak abonelik aktif değil'
      else 'Bilinmeyen tutarsızlık'
    end as description
  from classified c
  where c.issue_type is not null
  order by
    case c.issue_type
      when 'missing_subscription' then 1
      when 'active_sub_profile_free' then 2
      when 'tier_mismatch' then 3
      else 4
    end,
    c.subscription_updated_at desc nulls last;
$$;

revoke all on function public.admin_subscription_inconsistency_scan() from public;
grant execute on function public.admin_subscription_inconsistency_scan() to service_role;;
