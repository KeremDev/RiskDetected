-- Synthetic composition only. Real local GoTrue session, private P05 candidate.
-- The trusted harness verifies the token signature before setting JWT claims.
BEGIN;
GRANT USAGE ON SCHEMA isg_session_fixture TO isg_workplace_owner;
GRANT EXECUTE ON FUNCTION isg_session_fixture.require_active_session() TO isg_workplace_owner;
SET LOCAL ROLE isg_workplace_owner;
CREATE FUNCTION isg_workplace_fixture.personnel_verified(p_kind text, p_args jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid; previous_sub text; result jsonb;
BEGIN
  actor:=isg_session_fixture.require_active_session();
  IF p_kind IS NULL OR p_kind NOT IN ('read','create','edit') OR jsonb_typeof(p_args) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  previous_sub:=current_setting('request.jwt.claim.sub',true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  IF p_kind='read' THEN
    result:=isg_workplace_fixture.read_personnel((p_args->>'p_company')::uuid,p_args->>'p_kind',p_args->>'p_query',
      (p_args->>'p_archived')::boolean,(p_args->>'p_after')::uuid,(p_args->>'p_id')::uuid);
  ELSIF p_kind='create' THEN
    result:=isg_workplace_fixture.create_employee((p_args->>'p_operation')::uuid,(p_args->>'p_mutation')::uuid,
      (p_args->>'p_company')::uuid,p_args->>'p_name',(p_args->>'p_department')::uuid,p_args->>'p_department_name');
  ELSE
    result:=isg_workplace_fixture.edit_employee((p_args->>'p_operation')::uuid,(p_args->>'p_mutation')::uuid,
      (p_args->>'p_company')::uuid,(p_args->>'p_employee')::uuid,(p_args->>'p_expected')::bigint,p_args->>'p_action',
      p_args->>'p_name',(p_args->>'p_change_department')::boolean,(p_args->>'p_department')::uuid,p_args->>'p_department_name');
  END IF;
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION isg_workplace_fixture.personnel_verified(text,jsonb) FROM PUBLIC,anon,service_role;
GRANT USAGE ON SCHEMA isg_workplace_fixture TO authenticated;
GRANT EXECUTE ON FUNCTION isg_workplace_fixture.personnel_verified(text,jsonb) TO authenticated;
-- Test observer rolls back the entire failed domain call before reporting its code.
CREATE FUNCTION isg_workplace_fixture.observe_personnel(p_kind text,p_args jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE code text;
BEGIN
  RETURN jsonb_build_object('result',isg_workplace_fixture.personnel_verified(p_kind,p_args));
EXCEPTION
  WHEN SQLSTATE '28000' THEN RETURN jsonb_build_object('error','AUTH_REQUIRED');
  WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;
    IF code NOT IN ('ACCESS_DENIED','VALIDATION_ERROR','VERSION_CONFLICT','IDEMPOTENCY_CONFLICT','DEPARTMENT_SCOPE_INVALID','DEPARTMENT_SELECTION_REQUIRED','ASSIGNMENT_CHANGE_REQUIRED','INJECTED_FAILURE') THEN RAISE; END IF;
    RETURN jsonb_build_object('error',code);
END $$;
REVOKE ALL ON FUNCTION isg_workplace_fixture.observe_personnel(text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION isg_workplace_fixture.observe_personnel(text,jsonb) TO authenticated;
COMMIT;
