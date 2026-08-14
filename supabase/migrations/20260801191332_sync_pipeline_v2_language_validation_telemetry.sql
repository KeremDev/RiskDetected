-- Pipeline v2 finalization persists the complete localization audit inside
-- analyses.raw_ai_response._input_audit. Keep the indexed aggregate columns
-- synchronized from that authoritative audit in the same row update.

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

  v_text := v_audit ->> 'language_validation_status';
  if v_text in ('not_evaluated', 'passed', 'repaired', 'failed') then
    new.language_validation_status := v_text;
  end if;

  v_text := v_audit ->> 'language_validation_attempts';
  if v_text ~ '^[0-2]$' then
    new.language_validation_attempts := v_text::integer;
  end if;

  if v_audit ? 'language_validation_code' then
    v_text := v_audit ->> 'language_validation_code';
    if v_text is null or v_text ~ '^[A-Z0-9_]{1,160}$' then
      new.language_validation_code := v_text;
    end if;
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

revoke all on function private.tg_sync_analysis_localization_telemetry()
  from public, anon, authenticated;
grant execute on function private.tg_sync_analysis_localization_telemetry()
  to service_role;

do $backfill_pipeline_v2_language_telemetry$
declare
  v_rows integer;
begin
  loop
    with batch as (
      select ctid
      from public.analyses
      where status::text = 'completed'
        and raw_ai_response is not null
        and jsonb_typeof(raw_ai_response -> '_input_audit') = 'object'
        and raw_ai_response
          -> '_input_audit'
          ->> 'language_validation_status'
          in ('passed', 'repaired', 'failed')
        and (
          language_validation_status is null
          or language_validation_status = 'not_evaluated'
          or language_validation_attempts is null
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
$backfill_pipeline_v2_language_telemetry$;

comment on function private.tg_sync_analysis_localization_telemetry() is
  'Synchronizes bounded localization and language-validation aggregate telemetry from the immutable AI input audit.';
