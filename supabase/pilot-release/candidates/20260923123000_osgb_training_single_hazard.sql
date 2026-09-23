-- A shared training record has one curriculum and one lesson schedule. Enforce
-- the hazard class after each workplace's class is resolved for the training
-- date, so a historical class change cannot evade the mobile picker rule.
BEGIN;

DO $migration$
DECLARE
  source text := pg_get_functiondef('private_isg.education_save(uuid,jsonb)'::regprocedure);
  anchor constant text := 'scopes:=scopes||jsonb_build_array(scope);';
BEGIN
  IF (length(source) - length(replace(source, anchor, ''))) / length(anchor) <> 1 THEN
    RAISE EXCEPTION 'Unexpected education_save scope loop';
  END IF;
  IF position('TRAINING_HAZARD_MISMATCH' IN source) > 0 THEN
    RAISE EXCEPTION 'Single-hazard guard already installed';
  END IF;
  EXECUTE replace(source, anchor,
    'IF jsonb_array_length(scopes)>0 AND (scope->>''hazard_class'') IS DISTINCT FROM (scopes->0->>''hazard_class'') THEN
       RAISE EXCEPTION USING ERRCODE=''P0001'',MESSAGE=''TRAINING_HAZARD_MISMATCH'';
     END IF;
     ' || anchor);
END $migration$;

NOTIFY pgrst, 'reload schema';
COMMIT;
