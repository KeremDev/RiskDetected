
-- Profiles tablosu — auth.users'ı genişletir
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  initials text,
  title text,                 -- "İSG Uzmanı · A Sınıfı"
  certificate_number text,    -- "A-12384"
  company_name text,
  company_logo_url text,
  phone text,
  tier subscription_tier not null default 'free',
  subscription_period subscription_period,
  subscription_renewal_at timestamptz,
  daily_quota_used int not null default 0,
  daily_quota_reset_at date not null default current_date,
  preferred_method risk_method not null default 'fine_kinney',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- updated_at trigger
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.tg_set_updated_at();

-- Otomatik profile oluştur (auth.users insert sonrası)
create or replace function public.tg_create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(coalesce(new.email,''), '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.tg_create_profile_for_new_user();
;
