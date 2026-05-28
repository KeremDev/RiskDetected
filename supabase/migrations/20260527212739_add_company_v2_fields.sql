-- Company V2 metadata.
-- Nullable by design: existing companies and report flows keep working if these are empty.

alter table public.companies
  add column if not exists address text,
  add column if not exists contact_person text,
  add column if not exists department text,
  add column if not exists default_responsible text,
  add column if not exists default_due_days integer;

alter table public.companies
  drop constraint if exists companies_default_due_days_check,
  add constraint companies_default_due_days_check
    check (default_due_days is null or default_due_days between 1 and 365);

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
  new.address := nullif(btrim(coalesce(new.address, '')), '');
  new.contact_person := nullif(btrim(coalesce(new.contact_person, '')), '');
  new.department := nullif(btrim(coalesce(new.department, '')), '');
  new.default_responsible := nullif(btrim(coalesce(new.default_responsible, '')), '');

  if new.name = '' then
    raise exception 'company_name_required';
  end if;

  if new.default_due_days is not null and (new.default_due_days < 1 or new.default_due_days > 365) then
    raise exception 'company_default_due_days_invalid';
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
