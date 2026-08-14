-- Persist the platform already recorded in raw_ai_response._input_audit.
--
-- The Android client sends client_platform in the analyze request and the Edge Function copies
-- it into the input audit. Pipeline-v2 finalization writes raw_ai_response through the existing
-- localization telemetry trigger, but the trigger predates analyses.client_platform and therefore
-- left that additive column NULL. Keep the client unable to write this server-owned telemetry
-- directly; derive it from the same audited server result as app_language/client_build instead.

begin;

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

  v_text := v_audit ->> 'client_platform';
  if v_text in ('ios', 'android') then
    new.client_platform := v_text;
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

-- Re-run the trigger for already completed rows that contain a valid audited platform. The
-- assignment is intentionally idempotent and only targets NULL telemetry.
update public.analyses
set raw_ai_response = raw_ai_response
where client_platform is null
  and raw_ai_response -> '_input_audit' ->> 'client_platform' in ('ios', 'android');

commit;
