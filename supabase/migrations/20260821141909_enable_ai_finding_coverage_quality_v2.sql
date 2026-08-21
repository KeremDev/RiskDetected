do $coverage_quality_v2_on$
declare
  current_value jsonb;
begin
  select value
  into current_value
  from public.app_feature_flags
  where key = 'ai_finding_coverage_quality_v2'
  for update;

  if current_value is null then
    raise exception 'ai_finding_coverage_quality_v2 flag is missing';
  end if;

  if (current_value ->> 'policy_version')::integer is distinct from 2 then
    raise exception 'ai_finding_coverage_quality_v2 policy_version must be 2';
  end if;

  if coalesce((current_value ->> 'kill_switch')::boolean, true) then
    raise exception 'ai_finding_coverage_quality_v2 kill_switch must be false';
  end if;

  if coalesce(current_value ->> 'rollout_mode', 'off') not in ('shadow', 'allowlist', 'on') then
    raise exception 'ai_finding_coverage_quality_v2 rollout_mode is invalid';
  end if;

  update public.app_feature_flags
  set
    value = current_value || jsonb_build_object(
      'rollout_mode', 'on',
      'live_rollout_stage', 'general',
      'live_rollout_started_at', now()
    ),
    updated_at = now()
  where key = 'ai_finding_coverage_quality_v2';

  if not exists (
    select 1
    from public.app_feature_flags
    where key = 'ai_finding_coverage_quality_v2'
      and value ->> 'rollout_mode' = 'on'
      and (value ->> 'policy_version')::integer = 2
      and (value ->> 'kill_switch')::boolean is false
  ) then
    raise exception 'ai_finding_coverage_quality_v2 activation verification failed';
  end if;
end;
$coverage_quality_v2_on$;
