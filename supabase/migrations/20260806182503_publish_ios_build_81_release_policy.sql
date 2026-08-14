do $$
declare
  current_policy jsonb;
  current_latest_build integer;
begin
  select value
    into current_policy
  from public.app_feature_flags
  where key = 'ios_release_policy'
  for update;

  if current_policy is null then
    raise exception 'ios_release_policy feature flag is missing';
  end if;

  current_latest_build :=
    case
      when current_policy ->> 'latest_build' ~ '^[0-9]+$'
        then (current_policy ->> 'latest_build')::integer
      else 0
    end;

  if current_latest_build > 81 then
    raise exception
      'Refusing to roll ios_release_policy back from build % to 81',
      current_latest_build;
  end if;

  update public.app_feature_flags
  set
    value = current_policy || jsonb_build_object(
      'latest_build', 81,
      'policy_version', 'build-81-appstore',
      'soft_update_enabled', true,
      'hard_update_enabled', false,
      'app_store_url',
        'https://apps.apple.com/tr/app/riskdetected-i-%C5%9F-g%C3%BCvenli%C4%9Fi-i-sg/id6769498181'
    ),
    updated_at = now()
  where key = 'ios_release_policy';
end;
$$;
