-- Keep the legacy v2 record endpoint consistent with the guided v3 editor.
BEGIN;

DO $migration$
DECLARE
  source text := pg_get_functiondef('private_isg.pilot_training_sessions_save_legacy_v2(uuid,jsonb)'::regprocedure);
  anchor constant text := 'rule:=cat.rules->hazard;';
BEGIN
  IF (length(source) - length(replace(source, anchor, ''))) / length(anchor) <> 1 THEN
    RAISE EXCEPTION 'Unexpected legacy training company loop';
  END IF;
  IF position('TRAINING_HAZARD_MISMATCH' IN source) > 0 THEN
    RAISE EXCEPTION 'Legacy single-hazard guard already installed';
  END IF;
  EXECUTE replace(source, anchor,
    'IF EXISTS(SELECT 1 FROM public.companies previous
       WHERE previous.id=ANY(companies) AND previous.hazard_class IS DISTINCT FROM hazard) THEN
       RAISE EXCEPTION USING ERRCODE=''P0001'',MESSAGE=''TRAINING_HAZARD_MISMATCH'';
     END IF;
     ' || anchor);
END $migration$;

NOTIFY pgrst, 'reload schema';
COMMIT;
