-- Close the remaining direct-record boundaries for company-level findings and
-- checklists. Historical company records remain editable after a workplace is
-- later registered.
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
 'private_isg.workspace_nonconformity_mutate(uuid,uuid,uuid,jsonb)'::regprocedure,
 $old$OR workplace IS NULL OR opened IS NULL$old$,
 $new$OR opened IS NULL$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.start_checklist_run(uuid,uuid,text,date,timestamptz)'::regprocedure,
 $old$p_company IS NULL OR p_workplace IS NULL OR p_code IS NULL$old$,
 $new$p_company IS NULL OR p_code IS NULL$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.start_checklist_run(uuid,uuid,text,date,timestamptz)'::regprocedure,
 $old$SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$PERFORM private_isg.require_company_workplace(p_company,p_workplace,private_isg.active_actor());
  IF p_workplace IS NULL THEN
    SELECT c.user_id INTO workplace.owner_id FROM public.companies c WHERE c.id=p_company FOR SHARE;
  ELSE
    SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  END IF;$new$);

SELECT private_isg.migration_replace_once(
 'private_isg.mutate_checklists_company_v3(uuid,text,uuid,uuid,jsonb)'::regprocedure,
 $old$IF p_payload->>'workplace_id' IS NULL OR p_payload->>'template_code' IS NULL THEN$old$,
 $new$IF p_payload->>'template_code' IS NULL THEN$new$);
SELECT private_isg.migration_replace_once(
 'private_isg.mutate_checklists_company_v3(uuid,text,uuid,uuid,jsonb)'::regprocedure,
 $old$PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid
      AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$PERFORM private_isg.require_company_workplace(p_company,(p_payload->>'workplace_id')::uuid,actor);$new$);

DROP FUNCTION private_isg.migration_replace_once(regprocedure,text,text);
COMMIT;
