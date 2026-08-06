create table if not exists public.model_pricing_catalog (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  model text not null,
  effective_from date not null default current_date,
  input_price_per_million numeric(12, 6) not null,
  output_price_per_million numeric(12, 6) not null,
  cached_price_per_million numeric(12, 6),
  thoughts_price_per_million numeric(12, 6),
  currency text not null default 'USD',
  notes text,
  created_at timestamptz not null default now(),

  constraint model_pricing_catalog_unique
    unique (provider, model, effective_from)
);

create index if not exists model_pricing_catalog_lookup_idx
  on public.model_pricing_catalog (provider, model, effective_from desc);

alter table public.model_pricing_catalog enable row level security;

revoke all on table public.model_pricing_catalog from anon;
revoke all on table public.model_pricing_catalog from authenticated;

grant select on table public.model_pricing_catalog to service_role;

insert into public.model_pricing_catalog (
  provider,
  model,
  effective_from,
  input_price_per_million,
  output_price_per_million,
  cached_price_per_million,
  thoughts_price_per_million,
  notes
)
values
  ('gemini', 'gemini-2.5-flash', '2026-01-01', 0.15, 0.60, 0.0375, 0.60, 'Tahmini Google Gemini 2.5 Flash fiyatı (admin katalog)'),
  ('gemini', 'gemini-2.5-pro', '2026-01-01', 1.25, 10.00, 0.3125, 10.00, 'Tahmini Google Gemini 2.5 Pro fiyatı (admin katalog)'),
  ('gemini', 'gemini-3.1-flash-lite', '2026-01-01', 0.075, 0.30, 0.01875, 0.30, 'Tahmini Gemini 3.1 Flash Lite fiyatı (admin katalog)'),
  ('groq', 'meta-llama/llama-4-scout-17b-16e-instruct', '2026-01-01', 0.11, 0.34, null, null, 'Tahmini Groq Llama 4 Scout fiyatı (admin katalog)')
on conflict (provider, model, effective_from) do nothing;;
