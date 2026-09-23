-- Staging OSGB pilot: personnel records use the same company assignment and
-- active pilot account gate as training. Other modules keep their own gates.
BEGIN;

CREATE OR REPLACE FUNCTION private_isg.personnel_require_company(p_company uuid, p_write boolean)
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

REVOKE ALL ON FUNCTION private_isg.personnel_require_company(uuid, boolean)
  FROM PUBLIC, anon, authenticated;

DO $migration$
DECLARE routine regprocedure; source text; actual integer;
  needle constant text := 'private_isg.require_company(';
BEGIN
  FOREACH routine IN ARRAY ARRAY[
    'private_isg.read_personnel(uuid,text,text,boolean,uuid,uuid)'::regprocedure,
    'private_isg.mutate_personnel(uuid,text,uuid,uuid,uuid,bigint,text,boolean,uuid,text)'::regprocedure
  ] LOOP
    source := pg_get_functiondef(routine);
    actual := (length(source) - length(replace(source, needle, ''))) / length(needle);
    IF actual <> 1 THEN RAISE EXCEPTION 'Unexpected personnel gate count in %: %', routine, actual; END IF;
    EXECUTE replace(source, needle, 'private_isg.personnel_require_company(');
  END LOOP;
END $migration$;

NOTIFY pgrst, 'reload schema';
COMMIT;
