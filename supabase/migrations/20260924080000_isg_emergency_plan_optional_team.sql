-- An emergency plan may be published before its team is chosen. The apps
-- already let the expert skip the team step; the server still demanded one
-- to two hundred members, so publishing without a team failed with
-- VALIDATION_ERROR. The lower bound drops to zero; the upper bound and every
-- per-member check stay as they are.
--
-- Only the bound is rewritten, in place, so each function keeps the rest of
-- its current body, its settings and its grants. workspace_safety_mutate is
-- not defined by this repository's migrations, so it is only rewritten where
-- it exists.
DO $migration$
DECLARE
  target record;
  definition text;
BEGIN
  FOR target IN
    SELECT * FROM (VALUES
      ('private_isg.publish_emergency_plan(uuid,uuid,uuid,text,date,date,jsonb,uuid,text,timestamptz)',
       'jsonb_array_length(p_team) NOT BETWEEN 1 AND 200',
       'jsonb_array_length(p_team) NOT BETWEEN 0 AND 200', true),
      ('private_isg.emergency_team_snapshot(jsonb)',
       'jsonb_array_length(p_team) NOT BETWEEN 1 AND 200',
       'jsonb_array_length(p_team) NOT BETWEEN 0 AND 200', true),
      ('private_isg.workspace_safety_mutate(uuid,uuid,uuid,jsonb)',
       'jsonb_array_length(p_payload->''team'') NOT BETWEEN 1 AND 200',
       'jsonb_array_length(p_payload->''team'') NOT BETWEEN 0 AND 200', false)
    ) AS rules(signature, old_rule, new_rule, required)
  LOOP
    IF to_regprocedure(target.signature) IS NULL THEN
      IF target.required THEN
        RAISE EXCEPTION 'missing function %', target.signature;
      END IF;
      CONTINUE;
    END IF;
    definition := pg_get_functiondef(to_regprocedure(target.signature));
    IF position(target.new_rule IN definition) > 0 THEN
      CONTINUE;
    END IF;
    IF (length(definition) - length(replace(definition, target.old_rule, ''))) / length(target.old_rule) <> 1 THEN
      RAISE EXCEPTION 'unexpected team rule in %', target.signature;
    END IF;
    EXECUTE replace(definition, target.old_rule, target.new_rule);
  END LOOP;
END
$migration$;
