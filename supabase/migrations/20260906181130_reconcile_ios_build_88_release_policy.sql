-- App Store still serves iOS 2.0.0 (build 88). The release policy was advanced to build 89
-- before that build became publicly available, so build 88 clients were incorrectly offered a
-- soft update with nowhere to update to. Reconcile the advertised build without weakening the
-- existing build-88 minimum/hard-update policy.
do $migration$
declare
  v_policy jsonb;
  v_latest_build integer;
  v_engine_flag jsonb;
  v_hub_flag jsonb;
begin
  select value into v_policy
  from public.app_feature_flags
  where key = 'ios_release_policy'
  for update;

  if v_policy is null then
    raise exception 'ios_release_policy feature flag is missing';
  end if;

  v_latest_build := case
    when v_policy->>'latest_build' ~ '^[0-9]+$' then (v_policy->>'latest_build')::integer
    else 0
  end;

  if v_latest_build > 89
  then
    raise exception 'Refusing to roll ios_release_policy back from build % to 88', v_latest_build;
  end if;

  if v_latest_build = 89
    and (
      v_policy->>'minimum_supported_build' <> '88'
      or v_policy->>'hard_update_enabled' <> 'true'
      or v_policy->>'soft_update_enabled' <> 'true'
      or v_policy->>'policy_version' <> 'build-88-appstore-general-release'
    )
  then
    raise exception 'Refusing to reconcile unexpected iOS build-89 policy state: %', v_policy;
  end if;

  select value into v_engine_flag
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  select value into v_hub_flag
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  if not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '88')
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '88')
  then
    raise exception 'iOS build 88 release gates are not ready';
  end if;

  update public.app_feature_flags
  set value = v_policy || jsonb_build_object(
        'minimum_supported_build', 88,
        'latest_build', 88,
        'hard_update_enabled', true,
        'soft_update_enabled', true,
        'app_store_url', 'https://apps.apple.com/tr/app/riskdetected-i-%C5%9F-g%C3%BCvenli%C4%9Fi-i-sg/id6769498181',
        'policy_version', 'build-88-appstore-general-release-reconciled'
      ),
      updated_at = now()
  where key = 'ios_release_policy';
end;
$migration$;

do $verification$
declare
  v_policy jsonb;
begin
  select value into v_policy
  from public.app_feature_flags
  where key = 'ios_release_policy';

  if v_policy->>'minimum_supported_build' <> '88'
    or v_policy->>'latest_build' <> '88'
    or v_policy->>'hard_update_enabled' <> 'true'
    or v_policy->>'soft_update_enabled' <> 'true'
    or v_policy->>'policy_version' <> 'build-88-appstore-general-release-reconciled'
  then
    raise exception 'iOS build 88 release policy reconciliation verification failed';
  end if;
end;
$verification$;
