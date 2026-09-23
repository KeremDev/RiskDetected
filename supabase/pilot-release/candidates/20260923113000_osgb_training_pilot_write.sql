-- Staging OSGB pilot: an active pilot writer may record training for their
-- granted companies even when the staging account has no paid subscription.
-- Keep the general personnel/other-module paid entitlement unchanged.
BEGIN;

CREATE OR REPLACE FUNCTION private_isg.training_require_company(p_company uuid, p_write boolean)
RETURNS uuid
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE actor uuid := private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    RETURN private_isg.expert_require_company(p_company, p_write, 'personnel');
  END IF;
  IF p_company IS NULL OR p_write IS NULL
     OR NOT private_isg.p05_pilot_can_read(actor, p_company) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FEATURE_UNAVAILABLE';
  END IF;
  IF p_write THEN
    IF NOT private_isg.p05_pilot_account_enabled(actor, true) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FEATURE_UNAVAILABLE';
    END IF;
    PERFORM 1 FROM public.companies
      WHERE id = p_company AND user_id = actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.companies
      WHERE id = p_company AND user_id = actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED';
  END IF;
  RETURN actor;
END $function$;

REVOKE ALL ON FUNCTION private_isg.training_require_company(uuid, boolean)
  FROM PUBLIC, anon, authenticated;

-- All five routines are confined to the training domain. Check the number of
-- existing call sites so a later schema change cannot silently bypass a gate.
DO $migration$
DECLARE
  routine regprocedure;
  source text;
  expected integer;
  actual integer;
  needle constant text := 'private_isg.require_company(';
BEGIN
  FOR routine, expected IN
    SELECT sig, calls FROM (VALUES
      ('private_isg.pilot_training_sessions_read(uuid,uuid)'::regprocedure, 2),
      ('private_isg.education_save(uuid,jsonb)'::regprocedure, 2),
      ('private_isg.education_scope(jsonb,jsonb,jsonb,boolean)'::regprocedure, 1),
      ('private_isg.education_certificate(jsonb)'::regprocedure, 2),
      ('private_isg.pilot_training_sessions_save_legacy_v2(uuid,jsonb)'::regprocedure, 2)
    ) AS targets(sig, calls)
  LOOP
    source := pg_get_functiondef(routine);
    actual := (length(source) - length(replace(source, needle, ''))) / length(needle);
    IF actual <> expected THEN
      RAISE EXCEPTION 'Unexpected training authorization calls in %: %', routine, actual;
    END IF;
    EXECUTE replace(source, needle, 'private_isg.training_require_company(');
  END LOOP;
END $migration$;

NOTIFY pgrst, 'reload schema';
COMMIT;
