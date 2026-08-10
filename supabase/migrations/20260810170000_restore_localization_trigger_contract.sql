-- Restore the complete localization telemetry contract after the additive Android platform
-- migration extended this trigger. CREATE OR REPLACE owns the whole function body, so the
-- platform-only extension must retain the language-validation fields introduced earlier.

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

comment on function private.tg_sync_analysis_localization_telemetry() is
  'Synchronizes bounded localization, platform and language-validation aggregate telemetry from the immutable AI input audit.';

commit;
