-- Trigger-only security-definer functions must not be callable through PostgREST roles.
revoke all on function public.reconcile_paywall_conversion_from_client_event()
  from public, anon, authenticated;
