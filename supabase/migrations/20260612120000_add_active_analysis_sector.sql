alter table public.analyses
add column if not exists analysis_sector text,
add column if not exists analysis_sector_source text,
add column if not exists analysis_sector_prompt_version text;

comment on column public.analyses.analysis_sector is
  'Canonical active sector selected by the user for this specific analysis. Nullable for legacy clients/old analyses.';

comment on column public.analyses.analysis_sector_source is
  'Source of active analysis sector: user_selected, legacy_missing, system_migrated, etc.';

comment on column public.analyses.analysis_sector_prompt_version is
  'Prompt/guidance version used for active sector context.';

create index if not exists analyses_user_sector_created_idx
on public.analyses (user_id, analysis_sector, created_at desc);
