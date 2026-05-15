-- Reports: generated PDF metadata + Storage access.
-- Files live in the private `reports` bucket under:
--   {user_id}/{analysis_id}/{filename}.pdf

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reports', 'reports', false, 20971520, array['application/pdf'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  analysis_id  uuid references public.analyses(id) on delete cascade,
  kind         text not null default 'standard',
  method       text not null default 'fine_kinney',
  title        text not null,
  storage_path text not null,
  file_name    text not null,
  mime_type    text not null default 'application/pdf',
  file_size    integer,
  created_at   timestamptz not null default now(),
  unique (user_id, storage_path)
);

alter table public.reports
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists analysis_id uuid references public.analyses(id) on delete cascade,
  add column if not exists document_no text,
  add column if not exists format text,
  add column if not exists kind text not null default 'standard',
  add column if not exists method text not null default 'fine_kinney',
  add column if not exists title text not null default 'RiskDetected Report',
  add column if not exists storage_path text,
  add column if not exists file_name text,
  add column if not exists mime_type text not null default 'application/pdf',
  add column if not exists file_size integer,
  add column if not exists size_bytes integer,
  add column if not exists page_count integer,
  add column if not exists created_at timestamptz not null default now();

update public.reports
set document_no = coalesce(document_no, upper(left(analysis_id::text, 8))),
    format = coalesce(format, 'pdf'),
    file_name = coalesce(file_name, split_part(storage_path, '/', array_length(string_to_array(storage_path, '/'), 1))),
    mime_type = coalesce(mime_type, 'application/pdf'),
    file_size = coalesce(file_size, size_bytes),
    size_bytes = coalesce(size_bytes, file_size)
where document_no is null
   or format is null
   or file_name is null
   or mime_type is null
   or file_size is null
   or size_bytes is null;

alter table public.reports
  alter column storage_path set not null,
  alter column file_name set not null,
  alter column document_no set not null,
  alter column format set not null,
  alter column format set default 'pdf';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'reports_user_storage_path_key'
      and conrelid = 'public.reports'::regclass
  ) then
    alter table public.reports
      add constraint reports_user_storage_path_key unique (user_id, storage_path);
  end if;
end $$;

alter table public.reports enable row level security;

drop policy if exists "Users read own reports" on public.reports;
drop policy if exists "reports_select_own" on public.reports;
create policy "Users read own reports"
  on public.reports for select
  using (auth.uid() = user_id);

drop policy if exists "Users insert own reports" on public.reports;
drop policy if exists "reports_insert_own" on public.reports;
create policy "Users insert own reports"
  on public.reports for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users update own reports" on public.reports;
create policy "Users update own reports"
  on public.reports for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users delete own reports" on public.reports;
drop policy if exists "reports_delete_own" on public.reports;
create policy "Users delete own reports"
  on public.reports for delete
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.reports to authenticated;

create index if not exists reports_user_created
  on public.reports (user_id, created_at desc);

create index if not exists reports_analysis_created
  on public.reports (analysis_id, created_at desc);

drop policy if exists "Users read own report files" on storage.objects;
create policy "Users read own report files"
  on storage.objects for select
  using (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users insert own report files" on storage.objects;
create policy "Users insert own report files"
  on storage.objects for insert
  with check (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users update own report files" on storage.objects;
create policy "Users update own report files"
  on storage.objects for update
  using (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  )
  with check (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users delete own report files" on storage.objects;
create policy "Users delete own report files"
  on storage.objects for delete
  using (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );
