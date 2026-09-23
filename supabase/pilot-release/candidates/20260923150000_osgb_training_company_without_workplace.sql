-- Staging pilot: a training scope may target the company directly when it has
-- no active workplace. Existing workplace-scoped records keep their contract.
BEGIN;

DO $patch$
DECLARE
  source text := pg_get_functiondef('private_isg.education_scope(jsonb,jsonb,jsonb,boolean)'::regprocedure);
  anchor constant text := $old$ SELECT * INTO wp FROM private_isg.workplaces WHERE id=workplace AND company_id=company AND private_isg.expert_company_visible(owner_id,company_id,actor);
 IF NOT FOUND THEN RAISE EXCEPTION 'WORKPLACE_REQUIRED'; END IF;$old$;
  replacement constant text := $new$ IF workplace IS NULL THEN
   -- A company-only record is legal only while no active workplace exists.
   -- Keep curriculum versions workplace-scoped until that workflow is revised.
   IF p_curriculum OR EXISTS(
     SELECT 1 FROM private_isg.workplaces w
     WHERE w.company_id=company AND NOT w.is_archived
       AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor)
   ) THEN RAISE EXCEPTION 'WORKPLACE_REQUIRED'; END IF;
 ELSE
   SELECT * INTO wp FROM private_isg.workplaces
   WHERE id=workplace AND company_id=company AND NOT is_archived
     AND private_isg.expert_company_visible(owner_id,company_id,actor);
   IF NOT FOUND THEN RAISE EXCEPTION 'WORKPLACE_REQUIRED'; END IF;
 END IF;$new$;
BEGIN
  IF (length(source) - length(replace(source, anchor, ''))) / length(anchor) <> 1 THEN
    RAISE EXCEPTION 'Unexpected education_scope workplace guard';
  END IF;
  EXECUTE replace(source, anchor, replacement);
END $patch$;

NOTIFY pgrst, 'reload schema';
COMMIT;
