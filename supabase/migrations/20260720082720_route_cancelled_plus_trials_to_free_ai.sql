-- Route cancelled, still-active Plus yearly trials through the free AI
-- provider pool while preserving their Plus product capabilities.
--
-- Expand-only and rollback-safe:
-- - the feature flag starts off;
-- - the new telemetry value is accepted before the function can emit it;
-- - disabling the flag restores the previous routing without a schema revert.

alter table public.ai_usage_logs
  drop constraint if exists ai_usage_logs_ai_execution_route_check;

alter table public.ai_usage_logs
  add constraint ai_usage_logs_ai_execution_route_check
  check (
    ai_execution_route in (
      'free_legacy',
      'free_paid_trial',
      'paid_plan',
      'cancelled_plus_trial_free'
    )
  );

insert into public.app_feature_flags (key, value)
values (
  'cancelled_plus_trial_free_routing',
  jsonb_build_object(
    'mode', 'off',
    'user_hashes', jsonb_build_array()
  )
)
on conflict (key) do nothing;
