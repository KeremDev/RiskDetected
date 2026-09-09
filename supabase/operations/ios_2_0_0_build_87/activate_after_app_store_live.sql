-- Run only after iOS 2.0.0 build 87 is publicly available in the App Store.
begin;

update public.app_feature_flags
set value = coalesce(value, '{}'::jsonb) || jsonb_build_object(
      'latest_build', 87,
      'minimum_supported_build', 87,
      'soft_update_enabled', true,
      'hard_update_enabled', true,
      'policy_version', 'build-87-appstore'
    ),
    updated_at = now()
where key = 'ios_release_policy';

do $verification$
declare
  v_policy jsonb;
begin
  select value into v_policy
  from public.app_feature_flags
  where key = 'ios_release_policy';

  if (v_policy->>'latest_build')::integer <> 87
    or (v_policy->>'minimum_supported_build')::integer <> 87
    or v_policy->>'hard_update_enabled' <> 'true'
    or v_policy->>'policy_version' <> 'build-87-appstore'
  then
    raise exception 'build 87 App Store policy did not activate cleanly';
  end if;
end
$verification$;

commit;
