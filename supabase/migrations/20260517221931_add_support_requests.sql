-- Stores in-app support requests so messages are not lost when email delivery
-- is unavailable or the mail provider is not configured.

create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  support_id text not null unique,
  subject text not null,
  message text not null,
  sender_name text,
  sender_email text,
  sender_phone text,
  tier text,
  company_name text,
  title text,
  attachment_count integer not null default 0,
  attachments jsonb not null default '[]'::jsonb,
  delivery_status text not null default 'stored',
  delivery_error text,
  created_at timestamptz not null default now(),
  constraint support_requests_delivery_status_check
    check (delivery_status in ('sent', 'stored', 'email_failed'))
);

create index if not exists support_requests_user_created_at
  on public.support_requests (user_id, created_at desc);

create index if not exists support_requests_support_id
  on public.support_requests (support_id);

alter table public.support_requests enable row level security;
