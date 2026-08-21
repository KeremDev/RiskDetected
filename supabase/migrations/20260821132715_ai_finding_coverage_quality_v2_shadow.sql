insert into public.app_feature_flags (key, value)
values (
  'ai_finding_coverage_quality_v2',
  jsonb_build_object(
    'policy_version', 2,
    'rollout_mode', 'shadow',
    'kill_switch', false,
    'enabled_user_hashes', jsonb_build_array()
  )
)
on conflict (key) do nothing;
