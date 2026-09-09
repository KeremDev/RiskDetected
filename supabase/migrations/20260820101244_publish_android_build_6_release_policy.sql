-- Canonical timestamp aligned with the production migration history.
-- Records versionCode 6 (1.6.0) as the latest Android closed-test build, mirroring
-- the pattern already used for ios_release_policy publishes (see e.g.
-- 20260806182503_publish_ios_build_81_release_policy.sql). This build carries only
-- the min_version runtime-gate migration (20260819235131) and formatting/test
-- fixes; no forced or soft update is being asked of testers, so both update flags
-- stay off.

do $$
declare
  current_policy jsonb;
  current_latest_build integer;
begin
  select value
    into current_policy
  from public.app_feature_flags
  where key = 'android_release_policy'
  for update;

  if current_policy is null then
    raise exception 'android_release_policy feature flag is missing';
  end if;

  current_latest_build :=
    case
      when current_policy ->> 'latest_build' ~ '^[0-9]+$'
        then (current_policy ->> 'latest_build')::integer
      else 0
    end;

  if current_latest_build > 6 then
    raise exception
      'Refusing to roll android_release_policy back from build % to 6',
      current_latest_build;
  end if;

  update public.app_feature_flags
  set
    value = current_policy || jsonb_build_object(
      'latest_build', 6,
      'policy_version', 'closed-test-1.6.0-vc6'
    ),
    updated_at = now()
  where key = 'android_release_policy';
end;
$$;
