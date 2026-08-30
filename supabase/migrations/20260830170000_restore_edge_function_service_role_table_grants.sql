-- Restore the Data API privileges required by server-side Edge Functions.
--
-- These tables are created by the `postgres` migration role. This project's
-- postgres default ACL intentionally does not grant Data API DML privileges,
-- so every server-accessed table must be opted in explicitly. `service_role`
-- still bypasses RLS as designed; anon/authenticated grants and policies are
-- deliberately unchanged.

grant select, insert, update, delete on table
  public.account_deletion_requests,
  public.ai_usage_logs,
  public.analyses,
  public.analysis_photo_summaries,
  public.app_feature_flags,
  public.companies,
  public.findings,
  public.notification_events,
  public.notification_preferences,
  public.paywall_events,
  public.photos,
  public.plan_capability_rules,
  public.profiles,
  public.push_device_tokens,
  public.reports,
  public.subscription_conversion_attributions,
  public.subscription_events,
  public.subscription_test_overrides,
  public.support_requests,
  public.usage_events,
  public.user_ad_attribution,
  public.user_onboarding_answers,
  public.user_subscriptions
to service_role;

do $verification$
declare
  v_table regclass;
begin
  foreach v_table in array array[
    'public.analyses'::regclass,
    'public.photos'::regclass,
    'public.findings'::regclass,
    'public.profiles'::regclass
  ]
  loop
    if not has_table_privilege('service_role', v_table, 'select')
      or not has_table_privilege('service_role', v_table, 'insert')
      or not has_table_privilege('service_role', v_table, 'update')
      or not has_table_privilege('service_role', v_table, 'delete')
    then
      raise exception 'service_role Data API privileges missing for %', v_table;
    end if;
  end loop;
end;
$verification$;
