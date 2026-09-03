-- Publish Android 2.0.0 (versionCode 10) only after Google Play confirms the
-- Production release is live. The build-specific V4 and result-hub allowlists
-- were opened by 20260903084834; this migration advertises the live build while
-- deliberately keeping both update prompts disabled for the first release.

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
  select value
    into v_policy
  from public.app_feature_flags
  where key = 'android_release_policy'
  for update;

  if v_policy is null then
    raise exception 'android_release_policy feature flag is missing';
  end if;

  v_latest_build :=
    case
      when v_policy->>'latest_build' ~ '^[0-9]+$'
        then (v_policy->>'latest_build')::integer
      else 0
    end;

  if v_latest_build > 10 then
    raise exception
      'Refusing to roll android_release_policy back from build % to 10',
      v_latest_build;
  end if;

  foreach v_key in array array['analysis_engine_v4', 'analysis_result_hub_v1'] loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key;

    if v_value is null
      or v_value->>'rollout_mode' <> 'build_allowlist'
      or coalesce((v_value->>'kill_switch')::boolean, true)
      or not (coalesce(v_value->'enabled_android_builds', '[]'::jsonb) ?& array['7','8','9','10'])
      or not (coalesce(v_value->'enabled_ios_builds', '[]'::jsonb) ?& array['87','88'])
    then
      raise exception 'Android build 10 release preflight failed for %', v_key;
    end if;
  end loop;

  foreach v_key in array v_runtime_keys loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key;

    if v_value is null
      or v_value->>'rollout_mode' not in ('min_version', 'min_build')
      or coalesce((v_value->>'kill_switch')::boolean, true)
      or coalesce((v_value->>'min_android_version_code')::integer, 2147483647) > 10
    then
      raise exception 'Android build 10 runtime preflight failed for %', v_key;
    end if;
  end loop;

  update public.app_feature_flags
  set value = v_policy || jsonb_build_object(
        'latest_build', 10,
        'soft_update_enabled', false,
        'hard_update_enabled', false,
        'app_store_url', 'https://play.google.com/store/apps/details?id=com.riskdetectedan.app',
        'policy_version', 'production-2.0.0-vc10'
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

  if (v_policy->>'latest_build')::integer <> 10
    or coalesce((v_policy->>'soft_update_enabled')::boolean, true)
    or coalesce((v_policy->>'hard_update_enabled')::boolean, true)
    or v_policy->>'app_store_url' <> 'https://play.google.com/store/apps/details?id=com.riskdetectedan.app'
    or v_policy->>'policy_version' <> 'production-2.0.0-vc10'
  then
    raise exception 'Android build 10 release policy verification failed';
  end if;
end;
$verification$;
