-- Older clients may still call this endpoint when a company is created.
-- Keep authorization and response shape, but never create an invisible workplace.
BEGIN;
CREATE OR REPLACE FUNCTION private_isg.workspace_personnel_initialize(p_workspace uuid,p_company uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  workplace private_isg.workplaces;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',true);
  member:=private_isg.workspace_require_company(p_workspace,p_company,true);
  IF member.role='expert' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO workplace FROM private_isg.workplaces
    WHERE workspace_id=p_workspace AND company_id=p_company AND NOT is_archived
    ORDER BY created_at,id LIMIT 1;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'workplace_id',workplace.id,'name',workplace.name,'code',workplace.code,'version',workplace.version);
END $function$;
COMMIT;
