-- Core transactional notifications are presented as always active whenever the
-- notification master switch is on. Users can still manage app reminders and
-- professional progress categories independently.

create or replace function public.set_notification_master_preference_v1(
  p_enabled boolean
)
returns public.notification_preferences
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.notification_preferences;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  insert into public.notification_preferences as preferences (
    user_id,
    enabled,
    analysis_complete,
    report_ready,
    account_updates,
    marketing,
    trial_reminder,
    progress_weekly_summary,
    progress_monthly_summary,
    progress_milestones,
    app_reminders
  )
  values (
    v_user_id,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled,
    false,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled,
    p_enabled
  )
  on conflict (user_id) do update set
    enabled = excluded.enabled,
    analysis_complete = case
      when excluded.enabled then true
      else preferences.analysis_complete
    end,
    report_ready = case
      when excluded.enabled then true
      else preferences.report_ready
    end,
    account_updates = case
      when excluded.enabled then true
      else preferences.account_updates
    end
  returning * into v_row;

  update public.push_device_tokens
  set notifications_enabled = p_enabled
  where user_id = v_user_id
    and notifications_enabled is distinct from p_enabled;

  return v_row;
end;
$$;

revoke all on function public.set_notification_master_preference_v1(boolean)
  from public, anon;
grant execute on function public.set_notification_master_preference_v1(boolean)
  to authenticated, service_role;

-- Repair users whose master preference is already enabled but whose core
-- transactional categories were left disabled by the legacy all-or-nothing
-- preference writer.
update public.notification_preferences
set analysis_complete = true,
    report_ready = true,
    account_updates = true
where enabled
  and (
    not analysis_complete
    or not report_ready
    or not account_updates
  );
