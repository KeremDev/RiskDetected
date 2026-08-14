-- Skip quota tombstone inserts while an auth user deletion is cascading.
-- When the account itself is deleted, usage_events rows are deleted too; trying
-- to insert new usage_events at that point violates the auth.users FK.

create or replace function public.ensure_analysis_usage_event_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  quota_feature text;
begin
  if old.user_id is null or old.status <> 'completed' then
    return old;
  end if;

  if not exists (
    select 1
    from auth.users u
    where u.id = old.user_id
  ) then
    return old;
  end if;

  quota_feature := case
    when old.analysis_mode = 'detailed' then 'analysis_detailed'
    else 'analysis_standard'
  end;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata,
    created_at
  ) values (
    old.user_id,
    quota_feature,
    'completed',
    old.id,
    jsonb_build_object(
      'source', 'analysis_delete_tombstone',
      'analysis_mode', coalesce(old.analysis_mode, 'standard'),
      'status', old.status
    ),
    coalesce(old.completed_at, old.created_at)
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('analysis_standard', 'analysis_detailed')
  do nothing;

  return old;
end;
$$;

create or replace function public.ensure_report_usage_event_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  tier text;
  is_risk_analysis_report boolean;
  quota_feature text;
begin
  if old.user_id is null then
    return old;
  end if;

  if not exists (
    select 1
    from auth.users u
    where u.id = old.user_id
  ) then
    return old;
  end if;

  tier := coalesce(private.user_plan_tier(old.user_id), 'free');
  is_risk_analysis_report :=
    coalesce(old.kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(old.format, '') = 'xlsx';
  quota_feature := case
    when tier = 'free' and is_risk_analysis_report
      then 'report_risk_analysis_trial'
    else 'report_standard'
  end;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata,
    created_at
  ) values (
    old.user_id,
    quota_feature,
    'completed',
    old.id,
    jsonb_build_object(
      'source', 'report_delete_tombstone',
      'format', old.format,
      'kind', old.kind,
      'method', old.method
    ),
    old.created_at
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('report_standard', 'report_risk_analysis_trial')
  do nothing;

  return old;
end;
$$;

revoke execute on function public.ensure_analysis_usage_event_on_delete()
  from public, anon, authenticated;
revoke execute on function public.ensure_report_usage_event_on_delete()
  from public, anon, authenticated;
grant execute on function public.ensure_analysis_usage_event_on_delete()
  to service_role;
grant execute on function public.ensure_report_usage_event_on_delete()
  to service_role;

select pg_notify('pgrst', 'reload schema');
