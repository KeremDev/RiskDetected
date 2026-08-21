insert into public.app_feature_flags (key, value)
values
  (
    'ai_output_certainty_policy_v2',
    jsonb_build_object(
      'policy_version', 2,
      'rollout_mode', 'on',
      'kill_switch', false,
      'enabled_user_hashes', jsonb_build_array()
    )
  ),
  (
    'ai_output_deterministic_fallback_v1',
    jsonb_build_object(
      'policy_version', 1,
      'rollout_mode', 'on',
      'kill_switch', false,
      'enabled_user_hashes', jsonb_build_array()
    )
  )
on conflict (key) do nothing;
