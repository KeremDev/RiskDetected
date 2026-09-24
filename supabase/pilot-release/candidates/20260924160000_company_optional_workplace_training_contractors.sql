-- Firm-wide contractor engagements and training plans retain their own scope
-- when the company has no registered workplace.
BEGIN;
ALTER TABLE private_isg.workspace_contractor_engagements ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.workspace_annual_training_plans ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.company_curriculum_versions ALTER COLUMN workplace_id DROP NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS annual_training_plan_company_general_unique
 ON private_isg.workspace_annual_training_plans(workspace_id,company_id,plan_year)
 WHERE workplace_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS company_curriculum_general_unique
 ON private_isg.company_curriculum_versions(company_id,catalog_code,version)
 WHERE workplace_id IS NULL;

CREATE FUNCTION private_isg.migration_replace_once(
  p_signature regprocedure,p_old text,p_new text) RETURNS void
LANGUAGE plpgsql SET search_path TO '' AS $patch$
DECLARE definition text; matches integer;
BEGIN
  definition:=pg_get_functiondef(p_signature);
  matches:=(length(definition)-length(replace(definition,p_old,'')))/length(p_old);
  IF matches<>1 THEN RAISE EXCEPTION 'MIGRATION_SOURCE_DRIFT: % found %',p_signature,matches; END IF;
  EXECUTE replace(definition,p_old,p_new);
END $patch$;

SELECT private_isg.migration_replace_once(
 'private_isg.workspace_personnel_advanced_mutate(uuid,uuid,uuid,jsonb)'::regprocedure,
 $old$OR NOT EXISTS(SELECT 1 FROM private_isg.workplaces WHERE workspace_id=p_workspace
          AND company_id=p_company AND id=v_workplace_id AND NOT is_archived) THEN$old$,
 $new$OR NOT private_isg.company_workplace_scope(p_company,v_workplace_id,p_workspace,false) THEN$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.workspace_training_advanced_mutate(uuid,uuid,uuid,jsonb)'::regprocedure,
 $old$OR NOT EXISTS(SELECT 1 FROM private_isg.workplaces w
        WHERE w.workspace_id=p_workspace AND w.company_id=p_company AND w.id=v_workplace_id AND NOT w.is_archived) THEN$old$,
 $new$OR NOT private_isg.company_workplace_scope(p_company,v_workplace_id,p_workspace,false) THEN$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.education_scope(jsonb,jsonb,jsonb,boolean)'::regprocedure,
 $old$IF p_curriculum OR EXISTS($old$,
 $new$IF EXISTS($new$);

DROP FUNCTION private_isg.migration_replace_once(regprocedure,text,text);
COMMIT;
