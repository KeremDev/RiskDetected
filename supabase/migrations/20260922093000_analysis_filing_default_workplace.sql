-- A legacy personal company may have been created before the default-workplace
-- invariant. Repair that one missing dependency at the moment the expert asks
-- to file an analysis finding; never accept a company outside the actor's
-- writable scope and never expose the private initializer directly.
BEGIN;
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE FUNCTION private_isg.analysis_filing_workplace(p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  actor uuid;
  workplace uuid;
  row_ private_isg.workplaces;
BEGIN
  IF p_company IS NULL OR private_isg.expert_workspace() IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  actor:=private_isg.require_company(p_company,true);
  PERFORM private_isg.nonconformity_gate(true);
  workplace:=private_isg.ensure_default(p_company);
  SELECT * INTO row_ FROM private_isg.workplaces
    WHERE id=workplace AND company_id=p_company AND owner_id=actor AND workspace_id IS NULL AND NOT is_archived
    FOR SHARE;
  IF row_.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  RETURN jsonb_build_object('schema_version',1,'company_id',p_company,
    'workplace_id',row_.id,'name',row_.name);
END $$;

CREATE FUNCTION public.isg_analysis_filing_workplace_v1(p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.analysis_filing_workplace(p_company)
$$;

REVOKE ALL ON FUNCTION private_isg.analysis_filing_workplace(uuid),
  public.isg_analysis_filing_workplace_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.isg_analysis_filing_workplace_v1(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
