-- Firm-wide records must remain visible in lists after writing them.
BEGIN;
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
 'private_isg.directory_mutate(uuid,text,uuid,uuid,uuid,bigint,jsonb)'::regprocedure,
 $old$PERFORM 1 FROM private_isg.workplaces WHERE id=workplace AND company_id=p_company AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;$old$,
 $new$IF NOT private_isg.company_workplace_scope(p_company,workplace,NULL,
    p_id IS NOT NULL AND EXISTS(SELECT 1 FROM private_isg.contractor_engagements e
      WHERE e.id=p_id AND e.company_id=p_company AND e.workplace_id IS NULL)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_REQUIRED';END IF;$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.directory_mutate(uuid,text,uuid,uuid,uuid,bigint,jsonb)'::regprocedure,
 $old$organization_id=organization AND workplace_id=workplace AND starts_on=from_date FOR UPDATE;$old$,
 $new$organization_id=organization AND workplace_id IS NOT DISTINCT FROM workplace AND starts_on=from_date FOR UPDATE;$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.read_personnel(uuid,text,text,boolean,uuid,uuid)'::regprocedure,
 $old$private_isg.departments d JOIN private_isg.workplaces w ON w.company_id=d.company_id AND w.id=d.workplace_id
      WHERE d.company_id=p_company AND NOT d.is_archived AND NOT w.is_archived$old$,
 $new$private_isg.departments d LEFT JOIN private_isg.workplaces w ON w.company_id=d.company_id AND w.id=d.workplace_id
      WHERE d.company_id=p_company AND NOT d.is_archived AND (d.workplace_id IS NULL OR NOT w.is_archived)$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.workspace_personnel_advanced_read(uuid,uuid,text,uuid,integer)'::regprocedure,
 $old$JOIN private_isg.workplaces w ON w.workspace_id=e.workspace_id AND w.company_id=e.company_id AND w.id=e.workplace_id$old$,
 $new$LEFT JOIN private_isg.workplaces w ON w.workspace_id=e.workspace_id AND w.company_id=e.company_id AND w.id=e.workplace_id$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.workspace_training_advanced_read(uuid,uuid,text,uuid,integer)'::regprocedure,
 $old$JOIN private_isg.workplaces w ON w.workspace_id=p.workspace_id AND w.company_id=p.company_id AND w.id=p.workplace_id$old$,
 $new$LEFT JOIN private_isg.workplaces w ON w.workspace_id=p.workspace_id AND w.company_id=p.company_id AND w.id=p.workplace_id$new$);

DROP FUNCTION private_isg.migration_replace_once(regprocedure,text,text);
COMMIT;
