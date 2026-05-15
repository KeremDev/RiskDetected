
-- Analyses (her tarama bir kayıt)
create table public.analyses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default 'Adsız analiz',
  kind analysis_kind not null,                 -- photo | text
  canvas canvas_id not null default 'general',
  text_input text,                              -- text-mode için input
  status analysis_status not null default 'pending',
  status_message text,                          -- hata mesajı vs.
  started_at timestamptz,
  completed_at timestamptz,
  ai_models_used text[],                        -- ["claude-sonnet-4", "gpt-4o-vision"]
  primary_method risk_method not null default 'fine_kinney',
  ai_summary text,                              -- "5 bulgu tespit edildi..."
  total_score_fk numeric,                       -- toplam Fine-Kinney skoru
  total_score_m5 int,                           -- toplam 5x5 skoru
  highest_band_fk risk_level,
  highest_band_m5 risk_level,
  finding_count int not null default 0,
  review_status analysis_review_status not null default 'open',
  location text,                                -- "3. Kat şantiye girişi"
  raw_ai_response jsonb,                        -- ham AI yanıtı (debug & audit)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index analyses_user_id_idx on public.analyses(user_id, created_at desc);
create index analyses_status_idx on public.analyses(status) where status != 'completed';

create trigger analyses_set_updated_at
  before update on public.analyses
  for each row execute function public.tg_set_updated_at();

-- Photos (analysis başına 0..N foto)
create table public.photos (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null,                   -- "user_id/analysis_id/photo_1.jpg"
  width int,
  height int,
  size_bytes int,
  mime_type text not null default 'image/jpeg',
  annotations jsonb,                            -- shape annotations + pen drawing
  exif jsonb,
  created_at timestamptz not null default now()
);

create index photos_analysis_id_idx on public.photos(analysis_id);
;
