-- Android analysis creation idempotency.
--
-- Nullable/additive by design: shipping iOS requests keep their existing insert shape. Android
-- persists a UUID before the first create attempt and reuses it after response loss/process death.

begin;

alter table public.analyses
  add column if not exists client_submission_id uuid;

create unique index if not exists analyses_user_client_submission_unique
  on public.analyses (user_id, client_submission_id);

grant insert (client_submission_id)
  on table public.analyses
  to authenticated;

commit;
