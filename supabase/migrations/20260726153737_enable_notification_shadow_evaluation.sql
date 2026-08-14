do $$
declare
  current_flag jsonb;
begin
  select value
    into current_flag
  from public.app_feature_flags
  where key = 'engagement_notification_automation'
  for update;

  if current_flag is null then
    raise exception 'engagement_notification_automation feature flag is missing';
  end if;

  if (select count(*) from private.notification_rules) <> 2
     or exists (
       select 1
       from private.notification_rules
       where key not in (
         'first_analysis_after_24h',
         'inactivity_after_5d'
       )
         or status <> 'shadow'
     ) then
    raise exception
      'Notification rules must contain exactly the two expected shadow rules';
  end if;

  if exists (
    select 1
    from private.notification_campaigns
    where status in ('scheduled', 'running')
  ) then
    raise exception
      'Scheduled or running campaigns prevent safe shadow rollout';
  end if;

  if exists (
    select 1
    from private.notification_jobs
    where status in ('pending', 'claimed')
  ) then
    raise exception
      'Pending or claimed notification jobs prevent safe shadow rollout';
  end if;

  update public.app_feature_flags
  set
    value = current_flag || jsonb_build_object(
      'rollout_mode', 'on',
      'rollout_percentage', 100,
      'enabled_user_hashes', jsonb_build_array(),
      'kill_switch', false,
      'shadow_observation_started_at', now()
    ),
    updated_at = now()
  where key = 'engagement_notification_automation';
end;
$$;
