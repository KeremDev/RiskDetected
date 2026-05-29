-- Track the user's product entitlement separately from AI quality/routing.
-- This lets Free users receive a paid-backed first-value analysis without
-- changing their quota, feature gates, or real subscription tier.

alter table public.ai_usage_logs
  add column if not exists quality_tier text
    check (quality_tier in ('free', 'plus', 'pro')),
  add column if not exists ai_execution_route text
    check (ai_execution_route in ('free_legacy', 'free_paid_trial', 'paid_plan'));

create index if not exists ai_usage_logs_ai_execution_route_created_idx
  on public.ai_usage_logs (ai_execution_route, created_at desc)
  where ai_execution_route is not null;

create index if not exists ai_usage_logs_quality_tier_created_idx
  on public.ai_usage_logs (quality_tier, created_at desc)
  where quality_tier is not null;
