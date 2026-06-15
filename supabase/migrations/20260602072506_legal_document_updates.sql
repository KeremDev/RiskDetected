-- Remote legal document manifest/audit support.
-- Storage keeps markdown text public-readable; audit rows remain user-private.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'legal-documents',
  'legal-documents',
  true,
  262144,
  array['application/json', 'text/markdown', 'text/plain']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public read legal documents" on storage.objects;
create policy "Public read legal documents"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'legal-documents');

create table if not exists public.legal_document_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_kind text not null check (document_kind in ('terms', 'privacy', 'kvkk', 'consent')),
  version text not null,
  change_type text not null check (change_type in ('info', 'material_terms', 'explicit_consent')),
  seen_at timestamptz,
  continued_use_accepted_at timestamptz,
  explicitly_accepted_at timestamptz,
  source text not null default 'legal_update_notice',
  app_version text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, document_kind, version)
);

alter table public.legal_document_acknowledgements enable row level security;

drop policy if exists "Users read own legal acknowledgements" on public.legal_document_acknowledgements;
create policy "Users read own legal acknowledgements"
  on public.legal_document_acknowledgements for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own legal acknowledgements" on public.legal_document_acknowledgements;
create policy "Users insert own legal acknowledgements"
  on public.legal_document_acknowledgements for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own legal acknowledgements" on public.legal_document_acknowledgements;
create policy "Users update own legal acknowledgements"
  on public.legal_document_acknowledgements for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop trigger if exists legal_document_acknowledgements_set_updated_at
  on public.legal_document_acknowledgements;
create trigger legal_document_acknowledgements_set_updated_at
  before update on public.legal_document_acknowledgements
  for each row execute function public.tg_set_updated_at();

revoke all on public.legal_document_acknowledgements from anon;
revoke all on public.legal_document_acknowledgements from authenticated;
grant select, insert, update on public.legal_document_acknowledgements to authenticated;

create index if not exists legal_document_ack_user_version
  on public.legal_document_acknowledgements (user_id, document_kind, version);

create index if not exists legal_document_ack_user_seen
  on public.legal_document_acknowledgements (user_id, seen_at desc);

select pg_notify('pgrst', 'reload schema');
