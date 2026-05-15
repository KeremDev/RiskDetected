
-- Findings (analiz başına N bulgu)
create table public.findings (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  ordinal int not null,                          -- 1, 2, 3...
  title text not null,
  category text,                                  -- "Düşme riski", "KKD uyumsuzluğu"
  description text,
  recommended_action text,
  references_text text,                           -- "6331/4857 · ÇSGB"
  confidence numeric not null default 0,          -- 0..1

  -- Fine-Kinney
  fk_probability numeric not null,                -- 0.2..10
  fk_frequency   numeric not null,                -- 0.5..10
  fk_severity    numeric not null,                -- 1..100
  fk_score       numeric generated always as (fk_probability * fk_frequency * fk_severity) stored,
  fk_band        risk_level not null,

  -- 5x5
  m5_probability int not null,                    -- 1..5
  m5_severity    int not null,                    -- 1..5
  m5_score       int generated always as (m5_probability * m5_severity) stored,
  m5_band        risk_level not null,

  -- Önerilen Kalıntı (önlem sonrası) skor — opsiyonel
  residual_fk_probability numeric,
  residual_fk_frequency numeric,
  residual_fk_severity numeric,
  residual_fk_score numeric generated always as (
    coalesce(residual_fk_probability * residual_fk_frequency * residual_fk_severity, null)
  ) stored,
  residual_m5_probability int,
  residual_m5_severity int,
  residual_m5_score int generated always as (
    coalesce(residual_m5_probability * residual_m5_severity, null)
  ) stored,

  -- Aksiyon takibi
  responsible text,                               -- "İşveren", "İSG Uzmanı"
  deadline text,                                  -- "Acil", "1 hafta", "Sürekli"
  is_resolved boolean not null default false,
  resolved_at timestamptz,

  -- Reference to specific photo (varsa hangi fotonun hangi bölgesi)
  photo_id uuid references public.photos(id) on delete set null,
  bounding_box jsonb,                             -- {x, y, w, h} 0..1 oranında

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (analysis_id, ordinal),
  check (fk_probability in (0.2, 0.5, 1, 3, 6, 10)),
  check (fk_frequency in (0.5, 1, 2, 3, 6, 10)),
  check (fk_severity in (1, 3, 7, 15, 40, 100)),
  check (m5_probability between 1 and 5),
  check (m5_severity between 1 and 5)
);

create index findings_analysis_id_idx on public.findings(analysis_id, ordinal);
create index findings_user_id_idx on public.findings(user_id, created_at desc);
create index findings_unresolved_idx on public.findings(user_id) where is_resolved = false;

create trigger findings_set_updated_at
  before update on public.findings
  for each row execute function public.tg_set_updated_at();

-- Bulgu sayısını analyses tablosuna senkronize et
create or replace function public.tg_recalc_finding_count()
returns trigger language plpgsql as $$
begin
  update public.analyses
  set finding_count = (select count(*) from public.findings where analysis_id =
    coalesce(new.analysis_id, old.analysis_id))
  where id = coalesce(new.analysis_id, old.analysis_id);
  return null;
end $$;

create trigger findings_after_change
  after insert or delete on public.findings
  for each row execute function public.tg_recalc_finding_count();
;
