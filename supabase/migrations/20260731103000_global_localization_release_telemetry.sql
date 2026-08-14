-- Phase 6: additive localization rollout and bounded release telemetry.
--
-- This migration does not enable the English product. Every new flag starts
-- off, existing rollout_mode values are preserved, and current iOS builds
-- continue to resolve to the Turkish legacy contract.

alter table public.analyses
  add column if not exists app_language text,
  add column if not exists client_build text,
  add column if not exists language_contract_repair_used boolean,
  add column if not exists forbidden_claim_validation_status text;

alter table public.ai_usage_logs
  add column if not exists app_language text,
  add column if not exists safety_profile_version integer,
  add column if not exists prompt_profile_version text,
  add column if not exists client_build text,
  add column if not exists language_contract_repair_used boolean,
  add column if not exists forbidden_claim_validation_status text;

do $constraints$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_app_language_check'
  ) then
    alter table public.analyses
      add constraint analyses_app_language_check
      check (app_language is null or app_language in ('tr', 'en'))
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_client_build_check'
  ) then
    alter table public.analyses
      add constraint analyses_client_build_check
      check (
        client_build is null
        or (
          char_length(client_build) between 1 and 40
          and client_build ~ '^[1-9][0-9]{0,8}$'
        )
      )
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_forbidden_claim_validation_status_check'
  ) then
    alter table public.analyses
      add constraint analyses_forbidden_claim_validation_status_check
      check (
        forbidden_claim_validation_status is null
        or forbidden_claim_validation_status in (
          'not_evaluated', 'passed', 'repaired', 'failed'
        )
      )
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_app_language_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_app_language_check
      check (app_language is null or app_language in ('tr', 'en'))
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_safety_profile_version_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_safety_profile_version_check
      check (safety_profile_version is null or safety_profile_version > 0)
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_client_build_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_client_build_check
      check (
        client_build is null
        or (
          char_length(client_build) between 1 and 40
          and client_build ~ '^[1-9][0-9]{0,8}$'
        )
      )
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_forbidden_claim_validation_status_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_forbidden_claim_validation_status_check
      check (
        forbidden_claim_validation_status is null
        or forbidden_claim_validation_status in (
          'not_evaluated', 'passed', 'repaired', 'failed'
        )
      )
      not valid;
  end if;
end
$constraints$;

create or replace function private.tg_sync_analysis_localization_telemetry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_audit jsonb;
  v_text text;
begin
  v_audit := new.raw_ai_response -> '_input_audit';
  if jsonb_typeof(v_audit) is distinct from 'object' then
    return new;
  end if;

  v_text := v_audit ->> 'app_language';
  if v_text in ('tr', 'en') then
    new.app_language := v_text;
  end if;

  v_text := v_audit ->> 'client_build';
  if v_text ~ '^[1-9][0-9]{0,8}$' then
    new.client_build := v_text;
  end if;

  if jsonb_typeof(v_audit -> 'language_contract_repair_used') = 'boolean' then
    new.language_contract_repair_used :=
      (v_audit ->> 'language_contract_repair_used')::boolean;
  end if;

  v_text := v_audit ->> 'forbidden_claim_validation_status';
  if v_text in ('not_evaluated', 'passed', 'repaired', 'failed') then
    new.forbidden_claim_validation_status := v_text;
  end if;

  return new;
end
$function$;

drop trigger if exists analyses_sync_localization_telemetry
  on public.analyses;
create trigger analyses_sync_localization_telemetry
  before insert or update of raw_ai_response
  on public.analyses
  for each row
  execute function private.tg_sync_analysis_localization_telemetry();

revoke all on function private.tg_sync_analysis_localization_telemetry()
  from public, anon, authenticated;
grant execute on function private.tg_sync_analysis_localization_telemetry()
  to service_role;

do $backfill_analysis_telemetry$
declare
  v_rows integer;
begin
  loop
    with batch as (
      select ctid
      from public.analyses
      where raw_ai_response is not null
        and jsonb_typeof(raw_ai_response -> '_input_audit') = 'object'
        and (
          (
            app_language is null
            and raw_ai_response -> '_input_audit' ->> 'app_language'
              in ('tr', 'en')
          )
          or (
            client_build is null
            and raw_ai_response -> '_input_audit' ->> 'client_build'
              ~ '^[1-9][0-9]{0,8}$'
          )
          or (
            language_contract_repair_used is null
            and jsonb_typeof(
              raw_ai_response
                -> '_input_audit'
                -> 'language_contract_repair_used'
            ) = 'boolean'
          )
          or (
            forbidden_claim_validation_status is null
            and raw_ai_response
              -> '_input_audit'
              ->> 'forbidden_claim_validation_status'
              in ('not_evaluated', 'passed', 'repaired', 'failed')
          )
        )
      limit 500
      for update skip locked
    )
    update public.analyses a
    set raw_ai_response = a.raw_ai_response
    from batch
    where a.ctid = batch.ctid;

    get diagnostics v_rows = row_count;
    exit when v_rows = 0;
  end loop;
end
$backfill_analysis_telemetry$;

create index if not exists analyses_localization_release_metrics_idx
  on public.analyses (
    output_language,
    safety_profile_id,
    client_build,
    created_at desc
  );

create index if not exists ai_usage_logs_localization_release_metrics_idx
  on public.ai_usage_logs (
    output_language,
    safety_profile_id,
    client_build,
    created_at desc
  );

insert into public.app_feature_flags (key, value)
values
  (
    'localization_v2',
    '{"rollout_mode":"off","enabled_user_hashes":[],"enabled_ios_builds":[],"min_ios_build":null,"kill_switch":false,"contract_version":1}'::jsonb
  ),
  (
    'english_product_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[],"enabled_ios_builds":[],"min_ios_build":null,"kill_switch":false,"contract_version":1}'::jsonb
  )
on conflict (key) do nothing;

update public.app_feature_flags
set value =
  '{"enabled_user_hashes":[],"enabled_ios_builds":[],"min_ios_build":null,"kill_switch":false}'::jsonb
  || value
where key in (
  'localization_v2',
  'english_product_enabled',
  'global_localization_wave1',
  'safety_profile_en_intl_enabled',
  'safety_profile_en_gb_enabled',
  'safety_profile_en_us_enabled',
  'safety_profile_en_au_enabled',
  'safety_profile_en_ca_enabled',
  'localization_queue_payload_v1',
  'ai_language_guard_enabled',
  'ai_country_term_guard_enabled',
  'english_report_enabled',
  'english_notifications_enabled'
);

comment on column public.analyses.language_contract_repair_used is
  'Aggregate-safe boolean; no prompt, photo or user-authored text.';
comment on column public.analyses.forbidden_claim_validation_status is
  'Bounded validator outcome; no generated or user-authored text.';
comment on column public.ai_usage_logs.language_contract_repair_used is
  'Whether one same-provider language-contract repair request was used.';
comment on column public.ai_usage_logs.forbidden_claim_validation_status is
  'Bounded forbidden-claim validator outcome.';

select pg_notify('pgrst', 'reload schema');
