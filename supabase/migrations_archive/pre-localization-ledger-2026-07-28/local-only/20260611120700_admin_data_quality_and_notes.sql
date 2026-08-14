-- V1.5: Admin notes + data quality scan for operasyon merkezi

create table if not exists public.admin_notes (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null,
  target_id text not null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint admin_notes_target_type_check
    check (target_type in ('user', 'analysis', 'support', 'deletion')),
  constraint admin_notes_body_check
    check (char_length(trim(body)) > 0 and char_length(body) <= 2000)
);

create index if not exists admin_notes_target_idx
  on public.admin_notes(target_type, target_id);

create index if not exists admin_notes_created_at_idx
  on public.admin_notes(created_at desc);

alter table public.admin_notes enable row level security;

revoke all on table public.admin_notes from anon;
revoke all on table public.admin_notes from authenticated;

grant select, insert, update, delete on table public.admin_notes to service_role;

create or replace function public.admin_data_quality_scan()
returns table (
  check_key text,
  category text,
  severity text,
  issue_count bigint,
  description text,
  sample_ids text[]
)
language sql
stable
security definer
set search_path = public
as $$
  with stale_cutoff as (
    select now() - interval '15 minutes' as ts
  ),
  last7d as (
    select now() - interval '7 days' as ts
  ),
  checks as (
    select
      'subscription_inconsistency'::text as check_key,
      'subscriptions'::text as category,
      case
        when count(*) filter (where s.severity = 'high') > 0 then 'high'
        when count(*) > 0 then 'medium'
        else 'low'
      end as severity,
      count(*)::bigint as issue_count,
      'Profil planı ile RevenueCat abonelik kaydı uyuşmuyor'::text as description,
      coalesce(
        (
          select array_agg(s.user_id::text order by s.user_id)
          from (
            select user_id
            from public.admin_subscription_inconsistency_scan()
            limit 5
          ) s
        ),
        '{}'::text[]
      ) as sample_ids
    from public.admin_subscription_inconsistency_scan() s

    union all

    select
      'orphan_analyses',
      'analyses',
      'high',
      count(*)::bigint,
      'Profil kaydı olmayan kullanıcıya bağlı analizler',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select a.id
            from public.analyses a
            left join public.profiles p on p.id = a.user_id
            where p.id is null
            order by a.created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses a
    left join public.profiles p on p.id = a.user_id
    where p.id is null

    union all

    select
      'completed_no_findings',
      'analyses',
      'low',
      count(*)::bigint,
      'Tamamlanmış ancak bulgu sayısı sıfır analizler (30g)',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.analyses
            where status = 'completed'
              and coalesce(finding_count, 0) = 0
              and created_at >= now() - interval '30 days'
            order by created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses
    where status = 'completed'
      and coalesce(finding_count, 0) = 0
      and created_at >= now() - interval '30 days'

    union all

    select
      'stale_queue',
      'system',
      'high',
      count(*)::bigint,
      '15 dakikadan uzun süredir queued durumunda analizler',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.analyses, stale_cutoff sc
            where status = 'queued'
              and queued_at is not null
              and queued_at < sc.ts
            order by queued_at asc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses, stale_cutoff sc
    where status = 'queued'
      and queued_at is not null
      and queued_at < sc.ts

    union all

    select
      'profiles_missing_email',
      'profiles',
      'medium',
      count(*)::bigint,
      'E-posta alanı boş profiller',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.profiles
            where email is null or btrim(email) = ''
            order by created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.profiles
    where email is null or btrim(email) = ''

    union all

    select
      'pending_deletion_backlog',
      'operations',
      'medium',
      count(*)::bigint,
      'Bekleyen veya işlenmekte olan hesap silme talepleri',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.account_deletion_requests
            where status in ('pending', 'processing')
            order by created_at asc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.account_deletion_requests
    where status in ('pending', 'processing')

    union all

    select
      'ai_errors_7d',
      'ai',
      case
        when count(*) >= 50 then 'high'
        when count(*) >= 10 then 'medium'
        when count(*) > 0 then 'low'
        else 'low'
      end,
      count(*)::bigint,
      'Son 7 günde hata ile sonuçlanan AI çağrıları',
      '{}'::text[]
    from public.ai_usage_logs, last7d l
    where created_at >= l.ts
      and error is not null

    union all

    select
      'completion_push_backlog',
      'notifications',
      'low',
      count(*)::bigint,
      'Tamamlanmış analizlerde gönderilmemiş completion push (7g)',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select id
            from public.analyses, last7d l
            where status = 'completed'
              and completion_push_sent_at is null
              and completed_at >= l.ts
            order by completed_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.analyses, last7d l
    where status = 'completed'
      and completion_push_sent_at is null
      and completed_at >= l.ts

    union all

    select
      'paid_without_onboarding',
      'onboarding',
      'low',
      count(*)::bigint,
      'Plus/Pro profil ancak onboarding cevabı yok',
      coalesce(
        (
          select array_agg(x.id::text)
          from (
            select p.id
            from public.profiles p
            left join public.user_onboarding_answers o on o.user_id = p.id
            where p.tier in ('plus', 'pro')
              and o.user_id is null
            order by p.created_at desc
            limit 5
          ) x
        ),
        '{}'::text[]
      )
    from public.profiles p
    left join public.user_onboarding_answers o on o.user_id = p.id
    where p.tier in ('plus', 'pro')
      and o.user_id is null
  )
  select
    c.check_key,
    c.category,
    c.severity,
    c.issue_count,
    c.description,
    c.sample_ids
  from checks c
  where c.issue_count > 0
  order by
    case c.severity
      when 'high' then 1
      when 'medium' then 2
      else 3
    end,
    c.issue_count desc,
    c.check_key;
$$;

revoke all on function public.admin_data_quality_scan() from public;
grant execute on function public.admin_data_quality_scan() to service_role;
