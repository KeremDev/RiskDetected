update public.app_feature_flags
set value = value || jsonb_build_object(
  'policy_version', 1,
  'rollout_mode', 'on',
  'kill_switch', false,
  'live_rollout_stage', 'general',
  'live_rollout_started_at', now()
),
updated_at = now()
where key = 'ai_expert_depth_v1';

do $$
begin
  if not exists (
    select 1
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
      and value->>'rollout_mode' = 'on'
      and coalesce((value->>'kill_switch')::boolean, true) = false
      and coalesce((value->>'policy_version')::integer, 0) = 1
  ) then
    raise exception 'ai_expert_depth_v1 activation failed';
  end if;
end
$$;
