-- Google Play reports Android 2.0.1 (versionCode 13) live at 100%.
-- Reconcile the public release policy without forcing or suggesting an update.
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

  if v_latest_build not in (12, 13) then
    raise exception 'Refusing to publish Android build 13 from unexpected latest build %', v_latest_build;
  end if;

  if v_latest_build = 12
    and (
      v_policy->>'policy_version' <> 'production-2.0.0-vc12'
      or coalesce((v_policy->>'soft_update_enabled')::boolean, true)
      or coalesce((v_policy->>'hard_update_enabled')::boolean, true)
    )
  then
    raise exception 'Unexpected Android build 12 policy state: %', v_policy;
  end if;

  if v_latest_build = 13
    and (
      v_policy->>'policy_version' <> 'production-2.0.1-vc13'
      or coalesce((v_policy->>'soft_update_enabled')::boolean, true)
      or coalesce((v_policy->>'hard_update_enabled')::boolean, true)
    )
  then
    raise exception 'Unexpected Android build 13 policy state: %', v_policy;
  end if;

  foreach v_key in array array['analysis_engine_v4', 'analysis_result_hub_v1'] loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key;

    if v_value is null
      or v_value->>'rollout_mode' <> 'build_allowlist'
      or coalesce((v_value->>'kill_switch')::boolean, true)
      or not (coalesce(v_value->'enabled_android_builds', '[]'::jsonb) ?& array['7','8','9','10','11','12','13'])
    then
      raise exception 'Android build 13 release reconciliation failed for %', v_key;
    end if;
  end loop;

  foreach v_key in array v_runtime_keys loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key;

    if v_value is null
      or v_value->>'rollout_mode' not in ('min_version', 'min_build')
      or coalesce((v_value->>'kill_switch')::boolean, true)
      or coalesce((v_value->>'min_android_version_code')::integer, 2147483647) > 13
    then
      raise exception 'Android build 13 runtime reconciliation failed for %', v_key;
    end if;
  end loop;

  update public.app_feature_flags
  set value = v_policy || jsonb_build_object(
        'latest_build', 13,
        'soft_update_enabled', false,
        'hard_update_enabled', false,
        'app_store_url', 'https://play.google.com/store/apps/details?id=com.riskdetectedan.app',
        'policy_version', 'production-2.0.1-vc13'
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

  if (v_policy->>'latest_build')::integer <> 13
    or coalesce((v_policy->>'soft_update_enabled')::boolean, true)
    or coalesce((v_policy->>'hard_update_enabled')::boolean, true)
    or v_policy->>'app_store_url' <> 'https://play.google.com/store/apps/details?id=com.riskdetectedan.app'
    or v_policy->>'policy_version' <> 'production-2.0.1-vc13'
  then
    raise exception 'Android build 13 release policy verification failed';
  end if;
end;
$verification$;
