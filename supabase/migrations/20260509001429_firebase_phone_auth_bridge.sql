-- Firebase Phone Auth bridge mapping.
--
-- This table is intentionally service-role only. The iOS app verifies a phone
-- number through Firebase, then the Edge Function validates the Firebase ID
-- token and maps it to a real Supabase Auth user. App clients never write this
-- table directly.

create table if not exists public.firebase_phone_auth_links (
  id uuid primary key default gen_random_uuid(),
  firebase_project_id text not null,
  firebase_uid text not null,
  supabase_user_id uuid not null references auth.users(id) on delete cascade,
  phone text not null,
  provider text not null default 'firebase_phone',
  last_sign_in_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (firebase_project_id, firebase_uid),
  unique (supabase_user_id),
  unique (phone)
);

alter table public.firebase_phone_auth_links enable row level security;

revoke all on public.firebase_phone_auth_links from anon;
revoke all on public.firebase_phone_auth_links from authenticated;

create index if not exists firebase_phone_auth_links_phone_idx
  on public.firebase_phone_auth_links (phone);

create index if not exists firebase_phone_auth_links_user_idx
  on public.firebase_phone_auth_links (supabase_user_id);

select pg_notify('pgrst', 'reload schema');
