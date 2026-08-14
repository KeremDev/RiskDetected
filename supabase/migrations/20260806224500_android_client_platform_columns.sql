-- E8 (review doc): `analyze` already parses client_platform (parseClientReleaseContext) but
-- never persists it — telemetry/dashboards can't break down by platform once Android exists.
-- Additive only; both columns nullable, no backfill (historical iOS rows stay NULL — this repo's
-- pattern elsewhere, e.g. app_language/client_build in 20260731103000, does the same: NULL means
-- "predates this column", not "unknown platform").

alter table public.analyses
  add column if not exists client_platform text;
do $analyses_client_platform_constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_client_platform_check'
  ) then
    alter table public.analyses
      add constraint analyses_client_platform_check
        check (client_platform is null or client_platform in ('ios', 'android'))
        not valid;
  end if;
end
$analyses_client_platform_constraint$;

alter table public.ai_usage_logs
  add column if not exists client_platform text;
do $ai_usage_logs_client_platform_constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_client_platform_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_client_platform_check
        check (client_platform is null or client_platform in ('ios', 'android'))
        not valid;
  end if;
end
$ai_usage_logs_client_platform_constraint$;

comment on column public.analyses.client_platform is
  'ios | android | NULL (predates this column). Parsed from client_platform in the analyze request body; NOT the same as source, which is an ingestion path elsewhere in this schema (see F11).';
comment on column public.ai_usage_logs.client_platform is
  'Same convention as public.analyses.client_platform.';
