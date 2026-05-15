
-- Reports (PDF/Excel üretildiğinde kayıt)
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  document_no text not null,                  -- RD-RA-2026-0001
  format text not null,                        -- 'pdf' | 'xlsx'
  storage_path text not null,
  size_bytes int,
  page_count int,
  method risk_method not null,
  signed_url_expires_at timestamptz,
  created_at timestamptz not null default now()
);

create index reports_user_id_idx on public.reports(user_id, created_at desc);
create unique index reports_document_no_idx on public.reports(document_no);

-- Sıralı doküman no üretici (her kullanıcı için yıllık sequence)
create table public.report_counters (
  user_id uuid not null references public.profiles(id) on delete cascade,
  year int not null,
  last_no int not null default 0,
  primary key (user_id, year)
);

create or replace function public.next_document_no(p_user_id uuid)
returns text language plpgsql security definer as $$
declare
  y int := extract(year from now())::int;
  n int;
begin
  insert into public.report_counters(user_id, year, last_no)
  values (p_user_id, y, 1)
  on conflict (user_id, year) do update
    set last_no = public.report_counters.last_no + 1
  returning last_no into n;
  return 'RD-RA-' || y::text || '-' || lpad(n::text, 4, '0');
end $$;

-- Audit log (önemli aksiyonlar)
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  action text not null,                        -- 'analysis.created', 'finding.resolved', vs.
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_user_id_idx on public.audit_logs(user_id, created_at desc);
;
