-- Personnel and departments can belong directly to a company. Creating a
-- department by name must never manufacture a hidden default workplace.
BEGIN;
ALTER TABLE private_isg.departments ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.employee_assignments ALTER COLUMN workplace_id DROP NOT NULL;

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
 'private_isg.mutate_personnel(uuid,text,uuid,uuid,uuid,bigint,text,boolean,uuid,text)'::regprocedure,
 $old$workplace:=private_isg.ensure_default(p_company);
        PERFORM 1 FROM private_isg.workplaces WHERE id=workplace AND NOT is_archived FOR SHARE;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID'; END IF;$old$,
 $new$IF EXISTS(SELECT 1 FROM private_isg.workplaces WHERE company_id=p_company AND NOT is_archived) THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SELECTION_REQUIRED'; END IF;
        workplace:=NULL;$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.mutate_personnel(uuid,text,uuid,uuid,uuid,bigint,text,boolean,uuid,text)'::regprocedure,
 $old$PERFORM 1 FROM private_isg.departments d JOIN private_isg.workplaces w ON w.id=d.workplace_id AND w.company_id=d.company_id
        WHERE d.id=department AND d.company_id=p_company AND NOT d.is_archived AND NOT w.is_archived FOR SHARE OF d,w;$old$,
 $new$PERFORM 1 FROM private_isg.departments d LEFT JOIN private_isg.workplaces w ON w.id=d.workplace_id AND w.company_id=d.company_id
        WHERE d.id=department AND d.company_id=p_company AND NOT d.is_archived
          AND (d.workplace_id IS NULL OR NOT w.is_archived) FOR SHARE OF d;$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.directory_mutate(uuid,text,uuid,uuid,uuid,bigint,jsonb)'::regprocedure,
 $old$PERFORM 1 FROM private_isg.workplaces WHERE id=workplace AND company_id=p_company AND NOT is_archived FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID';END IF;$old$,
 $new$IF NOT private_isg.company_workplace_scope(p_company,workplace,NULL,
      p_id IS NOT NULL AND EXISTS(SELECT 1 FROM private_isg.departments d
        WHERE d.id=p_id AND d.company_id=p_company AND d.workplace_id IS NULL)) THEN
     RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID';END IF;$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.directory_mutate(uuid,text,uuid,uuid,uuid,bigint,jsonb)'::regprocedure,
 $old$company_id=p_company AND workplace_id=workplace AND NOT is_archived FOR SHARE;$old$,
 $new$company_id=p_company AND workplace_id IS NOT DISTINCT FROM workplace AND NOT is_archived FOR SHARE;$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.assignment_guard()'::regprocedure,
 $old$PERFORM 1 FROM private_isg.workplaces WHERE id=NEW.workplace_id AND company_id=NEW.company_id AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_SCOPE_INVALID';END IF;$old$,
 $new$IF NOT private_isg.company_workplace_scope(NEW.company_id,NEW.workplace_id,NULL,false) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_SCOPE_INVALID';END IF;$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.assignment_guard()'::regprocedure,
 $old$company_id=NEW.company_id AND workplace_id=NEW.workplace_id AND NOT is_archived FOR SHARE;$old$,
 $new$company_id=NEW.company_id AND workplace_id IS NOT DISTINCT FROM NEW.workplace_id AND NOT is_archived FOR SHARE;$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.workspace_directory_mutate(uuid,uuid,uuid,text,text,uuid,bigint,uuid,text,text)'::regprocedure,
 $old$IF NOT EXISTS(SELECT 1 FROM private_isg.workplaces WHERE workspace_id=p_workspace AND company_id=p_company
        AND id=p_workplace AND NOT is_archived) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$IF NOT private_isg.company_workplace_scope(p_company,p_workplace,p_workspace,false) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_REQUIRED'; END IF;$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.workspace_directory_mutate(uuid,uuid,uuid,text,text,uuid,bigint,uuid,text,text)'::regprocedure,
 $old$IF p_action='edit' AND (p_workplace IS NULL OR NOT EXISTS(SELECT 1 FROM private_isg.workplaces
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_workplace AND NOT is_archived)) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$IF p_action='edit' AND NOT private_isg.company_workplace_scope(p_company,p_workplace,p_workspace,
        before_state->>'workplace_id' IS NULL) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_REQUIRED'; END IF;$new$);

DROP FUNCTION private_isg.migration_replace_once(regprocedure,text,text);
COMMIT;
