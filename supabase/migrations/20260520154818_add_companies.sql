-- Multi-company support for Plus/Pro users.

create schema if not exists private;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  hazard_class text not null,
  logo_path text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint companies_name_not_blank check (length(btrim(name)) > 0),
  constraint companies_hazard_class_check check (hazard_class in ('low', 'medium', 'high'))
);

create unique index if not exists companies_user_active_name_idx
  on public.companies (user_id, lower(btrim(name)))
  where is_archived = false;

create index if not exists companies_user_active_created_idx
  on public.companies (user_id, is_archived, created_at desc);

alter table public.companies enable row level security;

create or replace function private.company_limit_for_user(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, private
as $$
  select case coalesce(private.user_plan_tier(p_user_id), p.tier::text)
    when 'plus' then 5
    when 'pro' then 25
    else 0
  end
  from public.profiles p
  where p.id = p_user_id
$$;

revoke all on function private.company_limit_for_user(uuid) from public, anon, authenticated;

create or replace function private.enforce_company_write_rules()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_limit integer;
  v_active_count integer;
begin
  new.name := btrim(new.name);
  new.logo_path := nullif(btrim(coalesce(new.logo_path, '')), '');

  if new.name = '' then
    raise exception 'company_name_required';
  end if;

  v_limit := coalesce(private.company_limit_for_user(new.user_id), 0);
  if v_limit <= 0 then
    raise exception 'company_feature_requires_paid_plan';
  end if;

  if new.is_archived = false then
    select count(*)
      into v_active_count
    from public.companies c
    where c.user_id = new.user_id
      and c.is_archived = false
      and (tg_op <> 'UPDATE' or c.id <> new.id);

    if v_active_count >= v_limit then
      raise exception 'company_limit_exceeded';
    end if;
  end if;

  new.updated_at := now();
  return new;
end $$;

revoke all on function private.enforce_company_write_rules() from public, anon, authenticated;

-- Backfill existing profile company fields as the user's first company.
-- This runs before the write trigger so legacy Free users keep their data for a future upgrade.
insert into public.companies (user_id, name, hazard_class, logo_path)
select
  p.id,
  btrim(p.company_name),
  'medium',
  nullif(btrim(coalesce(p.company_logo_url, '')), '')
from public.profiles p
where nullif(btrim(coalesce(p.company_name, '')), '') is not null
on conflict do nothing;

drop trigger if exists companies_enforce_write_rules on public.companies;
create trigger companies_enforce_write_rules
  before insert or update on public.companies
  for each row execute function private.enforce_company_write_rules();

drop policy if exists companies_select_paid_own on public.companies;
create policy companies_select_paid_own
  on public.companies for select to authenticated
  using (
    auth.uid() = user_id
    and coalesce(private.company_limit_for_user(auth.uid()), 0) > 0
  );

drop policy if exists companies_insert_paid_own on public.companies;
create policy companies_insert_paid_own
  on public.companies for insert to authenticated
  with check (
    auth.uid() = user_id
    and coalesce(private.company_limit_for_user(auth.uid()), 0) > 0
  );

drop policy if exists companies_update_paid_own on public.companies;
create policy companies_update_paid_own
  on public.companies for update to authenticated
  using (
    auth.uid() = user_id
    and coalesce(private.company_limit_for_user(auth.uid()), 0) > 0
  )
  with check (
    auth.uid() = user_id
    and coalesce(private.company_limit_for_user(auth.uid()), 0) > 0
  );

grant select, insert, update on public.companies to authenticated;

alter table public.analyses
  add column if not exists company_id uuid references public.companies(id) on delete set null;

alter table public.reports
  add column if not exists company_id uuid references public.companies(id) on delete set null,
  add column if not exists company_snapshot jsonb;

create or replace function private.enforce_analysis_company_owner()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if new.company_id is not null and not exists (
    select 1
    from public.companies c
    where c.id = new.company_id
      and c.user_id = new.user_id
  ) then
    raise exception 'company_not_owned';
  end if;

  return new;
end $$;

revoke all on function private.enforce_analysis_company_owner() from public, anon, authenticated;

drop trigger if exists analyses_enforce_company_owner on public.analyses;
create trigger analyses_enforce_company_owner
  before insert or update of user_id, company_id on public.analyses
  for each row execute function private.enforce_analysis_company_owner();

create or replace function private.enforce_report_company_owner()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if new.company_id is not null and not exists (
    select 1
    from public.companies c
    where c.id = new.company_id
      and c.user_id = new.user_id
  ) then
    raise exception 'company_not_owned';
  end if;

  return new;
end $$;

revoke all on function private.enforce_report_company_owner() from public, anon, authenticated;

drop trigger if exists reports_enforce_company_owner on public.reports;
create trigger reports_enforce_company_owner
  before insert or update of user_id, company_id on public.reports
  for each row execute function private.enforce_report_company_owner();

create index if not exists analyses_user_company_created_idx
  on public.analyses (user_id, company_id, created_at desc);

create index if not exists reports_user_company_created_idx
  on public.reports (user_id, company_id, created_at desc);

grant update (company_id) on public.analyses to authenticated;

-- Ensure report metadata writes can include the new company columns.
grant update (company_id, company_snapshot) on public.reports to authenticated;
