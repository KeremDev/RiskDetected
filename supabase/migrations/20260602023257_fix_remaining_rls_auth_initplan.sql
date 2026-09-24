-- Complete the RLS initPlan cleanup for the remaining active subscription policy.

alter policy "Users read own subscription"
  on public.user_subscriptions
  using ((select auth.uid()) = user_id);
