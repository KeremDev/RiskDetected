-- Generic process forms, photo analysis filing, risk revisions and completed
-- drills must use the same company/workplace rule as the direct module RPCs.
BEGIN;

ALTER TABLE private_isg.contractor_engagements ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.pilot_completed_drills ALTER COLUMN workplace_id DROP NOT NULL;

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
  'private_isg.process_mutate(uuid,text,uuid,uuid,jsonb)'::regprocedure,
  $old$IF vals ? 'workplace_id' THEN
  PERFORM 1 FROM private_isg.workplaces WHERE id=(vals->>'workplace_id')::uuid AND company_id=p_company AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;$old$,
  $new$IF vals ? 'workplace_id' AND NOT private_isg.company_workplace_scope(
    p_company,(vals->>'workplace_id')::uuid,NULL,
    id_ IS NOT NULL AND old_->>'workplace_id' IS NULL) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_REQUIRED';
 END IF;$new$);

SELECT private_isg.migration_replace_once(
  'private_isg.workspace_risk_mutate(uuid,uuid,uuid,jsonb)'::regprocedure,
  $old$IF workplace IS NULL OR kind NOT IN$old$,
  $new$IF kind NOT IN$new$);
SELECT private_isg.migration_replace_once(
  'private_isg.workspace_risk_mutate(uuid,uuid,uuid,jsonb)'::regprocedure,
  $old$AND company_id=p_company AND workplace_id=workplace FOR UPDATE$old$,
  $new$AND company_id=p_company AND workplace_id IS NOT DISTINCT FROM workplace FOR UPDATE$new$);

SELECT private_isg.migration_replace_once(
  'private_isg.workspace_analysis_file(uuid,uuid,uuid,uuid,text,uuid,text,uuid,text,date,date)'::regprocedure,
  $old$p_analysis IS NULL OR p_item IS NULL OR p_workplace IS NULL OR p_opened_on IS NULL$old$,
  $new$p_analysis IS NULL OR p_item IS NULL OR p_opened_on IS NULL$new$);
SELECT private_isg.migration_replace_once(
  'private_isg.workspace_analysis_file(uuid,uuid,uuid,uuid,text,uuid,text,uuid,text,date,date)'::regprocedure,
  $old$NOT EXISTS(SELECT 1 FROM private_isg.workplaces WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_workplace AND NOT is_archived)$old$,
  $new$NOT private_isg.company_workplace_scope(p_company,p_workplace,p_workspace,false)$new$);

SELECT private_isg.migration_replace_once(
  'private_isg.pilot_record_validate()'::regprocedure,
  $old$SELECT to_jsonb(w) INTO wp FROM private_isg.workplaces w WHERE w.id=NEW.workplace_id AND w.company_id=NEW.company_id AND NOT w.is_archived;
  IF wp IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;$old$,
  $new$IF NEW.workplace_id IS NULL THEN
    IF NOT private_isg.company_workplace_scope(NEW.company_id,NULL,NULL,
      TG_OP='UPDATE' AND OLD.workplace_id IS NULL) THEN RAISE EXCEPTION 'WORKPLACE_REQUIRED'; END IF;
    SELECT to_jsonb(c) INTO wp FROM public.companies c WHERE c.id=NEW.company_id AND NOT c.is_archived;
  ELSE
    SELECT to_jsonb(w) INTO wp FROM private_isg.workplaces w WHERE w.id=NEW.workplace_id AND w.company_id=NEW.company_id AND NOT w.is_archived;
  END IF;
  IF wp IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;$new$);

DROP FUNCTION private_isg.migration_replace_once(regprocedure,text,text);
COMMIT;
