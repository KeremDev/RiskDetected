-- Presentation availability only. Every read/mutation still verifies its own authority.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE FUNCTION private_isg.workspace_availability(p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();can_read boolean;can_write boolean:=false;company public.companies;
BEGIN
 SELECT read_enabled INTO can_read FROM private_isg.rollout WHERE feature='personnel' FOR SHARE;
 can_read:=coalesce(can_read,false);
 IF can_read AND p_company IS NOT NULL THEN
  -- Take the write lock first; never upgrade two concurrent company SHARE locks.
  BEGIN
   PERFORM private_isg.require_company(p_company,true);can_write:=true;
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
   IF SQLERRM NOT IN('PAID_PLAN_REQUIRED','FEATURE_UNAVAILABLE','ACCESS_DENIED') THEN RAISE;END IF;
  END;
  PERFORM private_isg.require_company(p_company,false);
  SELECT * INTO STRICT company FROM public.companies WHERE id=p_company AND user_id=actor;
 END IF;
 RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,
  'company_name',company.name,'is_archived',company.is_archived,'can_read',can_read,'can_write',can_write);
END $$;
CREATE FUNCTION public.isg_workspace_availability_v1(p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_availability(p_company) $$;
REVOKE ALL ON FUNCTION private_isg.workspace_availability(uuid),public.isg_workspace_availability_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_availability(uuid),public.isg_workspace_availability_v1(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
