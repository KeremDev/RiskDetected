-- The table is intentionally service-role-only. An explicit deny policy documents that contract
-- for authenticated clients while service_role continues to bypass RLS for the webhook.
drop policy if exists subscription_conversion_service_only
  on public.subscription_conversion_attributions;
create policy subscription_conversion_service_only
  on public.subscription_conversion_attributions
  for all
  to authenticated
  using (false)
  with check (false);

-- Cover the FK used when a referenced paywall event is removed.
create index if not exists subscription_conversion_entry_event_idx
  on public.subscription_conversion_attributions (entry_event_id)
  where entry_event_id is not null;
