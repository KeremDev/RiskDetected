-- Google Play already reports Android 2.0.0 (versionCode 12) live at 100%, while the backend
-- still advertises build 11. Reconcile that drift without forcing or suggesting an update.
do $migration$
declare
  v_policy jsonb;
  v_latest_build integer;
  v_key text;
  v_value jsonb;
  v_runtime_keys constant text[] := array[
    'android_client_enabled',
    'android_auth_enabled',
    'android_analysis_submit_enabled',
    'android_payments_enabled',
    'android_notifications_enabled',
    'android_pdf_reports_enabled'
  ];
begin
  select value into v_policy
  from public.app_feature_flags
  where key = 'android_release_policy'
  for update;

  if v_policy is null then
    raise exception 'android_release_policy feature flag is missing';
  end if;

  v_latest_build := case
    when v_policy->>'latest_build' ~ '^[0-9]+$' then (v_policy->>'latest_build')::integer
    else 0
  end;

  if v_latest_build > 12 then
    raise exception 'Refusing to roll android_release_policy back from build % to 12', v_latest_build;
  end if;

  foreach v_key in array array['analysis_engine_v4', 'analysis_result_hub_v1'] loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key;

    if v_value is null
      or v_value->>'rollout_mode' <> 'build_allowlist'
      or coalesce((v_value->>'kill_switch')::boolean, true)
      or not (coalesce(v_value->'enabled_android_builds', '[]'::jsonb) ?& array['7','8','9','10','11','12'])
      or not (coalesce(v_value->'enabled_ios_builds', '[]'::jsonb) ?& array['87','88','89'])
    then
      raise exception 'Android build 12 release reconciliation failed for %', v_key;
    end if;
  end loop;

  foreach v_key in array v_runtime_keys loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key;

    if v_value is null
      or v_value->>'rollout_mode' not in ('min_version', 'min_build')
      or coalesce((v_value->>'kill_switch')::boolean, true)
      or coalesce((v_value->>'min_android_version_code')::integer, 2147483647) > 12
    then
      raise exception 'Android build 12 runtime reconciliation failed for %', v_key;
    end if;
  end loop;

  update public.app_feature_flags
  set value = v_policy || jsonb_build_object(
        'latest_build', 12,
        'soft_update_enabled', false,
        'hard_update_enabled', false,
        'app_store_url', 'https://play.google.com/store/apps/details?id=com.riskdetectedan.app',
        'policy_version', 'production-2.0.0-vc12'
      ),
      updated_at = now()
  where key = 'android_release_policy';
end;
$migration$;

do $verification$
declare
  v_policy jsonb;
begin
  select value into v_policy
  from public.app_feature_flags
  where key = 'android_release_policy';

  if (v_policy->>'latest_build')::integer <> 12
    or coalesce((v_policy->>'soft_update_enabled')::boolean, true)
    or coalesce((v_policy->>'hard_update_enabled')::boolean, true)
    or v_policy->>'app_store_url' <> 'https://play.google.com/store/apps/details?id=com.riskdetectedan.app'
    or v_policy->>'policy_version' <> 'production-2.0.0-vc12'
  then
    raise exception 'Android build 12 release policy reconciliation verification failed';
  end if;
end;
$verification$;
