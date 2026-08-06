-- V16: PGMQ analysis_jobs queue depth for admin operasyon merkezi

create or replace function public.admin_pgmq_queue_metrics()
returns table (
  queue_name text,
  depth bigint,
  archive_depth bigint,
  oldest_enqueued_at timestamptz,
  oldest_age_seconds bigint,
  max_read_count integer,
  stuck_messages bigint,
  visibility_expired bigint
)
language sql
stable
security definer
set search_path = public, pgmq
as $$
  select
    'analysis_jobs'::text as queue_name,
    (select count(*)::bigint from pgmq.q_analysis_jobs) as depth,
    (select count(*)::bigint from pgmq.a_analysis_jobs) as archive_depth,
    (select min(enqueued_at) from pgmq.q_analysis_jobs) as oldest_enqueued_at,
    (
      select extract(epoch from (now() - min(enqueued_at)))::bigint
      from pgmq.q_analysis_jobs
    ) as oldest_age_seconds,
    (select coalesce(max(read_ct), 0) from pgmq.q_analysis_jobs) as max_read_count,
    (
      select count(*)::bigint
      from pgmq.q_analysis_jobs
      where read_ct >= 3
    ) as stuck_messages,
    (
      select count(*)::bigint
      from pgmq.q_analysis_jobs
      where vt <= now()
    ) as visibility_expired;
$$;

create or replace function public.admin_pgmq_queue_messages(p_limit integer default 20)
returns table (
  msg_id bigint,
  enqueued_at timestamptz,
  read_ct integer,
  vt timestamptz,
  analysis_id uuid,
  is_stuck boolean,
  is_visibility_expired boolean
)
language sql
stable
security definer
set search_path = public, pgmq
as $$
  select
    m.msg_id,
    m.enqueued_at,
    m.read_ct,
    m.vt,
    nullif(m.message ->> 'analysis_id', '')::uuid as analysis_id,
    (m.read_ct >= 3) as is_stuck,
    (m.vt <= now()) as is_visibility_expired
  from pgmq.q_analysis_jobs m
  order by m.enqueued_at asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

revoke all on function public.admin_pgmq_queue_metrics() from public;
revoke all on function public.admin_pgmq_queue_messages(integer) from public;

grant execute on function public.admin_pgmq_queue_metrics() to service_role;
grant execute on function public.admin_pgmq_queue_messages(integer) to service_role;

insert into public.admin_alert_rules (
  rule_key, name, description, metric_key, operator, threshold, severity, cooldown_minutes
)
values (
  'pgmq_depth',
  'PGMQ kuyruk derinliği',
  'analysis_jobs PGMQ kuyruğunda biriken mesaj sayısı yükseldi',
  'pgmq_depth',
  'gte',
  5,
  'warning',
  60
)
on conflict (rule_key) do nothing;;
