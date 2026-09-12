-- SYNTHETIC COMPOSITION ONLY: requires auth_session_fixture.sql and the unchanged
-- transaction_fixture.sql. No public schema, migration or production endpoint.
BEGIN;
GRANT USAGE ON SCHEMA isg_session_fixture TO isg_fixture_owner;
GRANT EXECUTE ON FUNCTION isg_session_fixture.require_active_session() TO isg_fixture_owner;
SET LOCAL ROLE isg_fixture_owner;
CREATE TABLE isg_fixture.write_capabilities (
  actor_id uuid PRIMARY KEY REFERENCES isg_fixture.actors,
  can_mutate boolean NOT NULL
);
ALTER TABLE isg_fixture.write_capabilities ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION isg_fixture.mutate_verified(p_mutation uuid, p_company uuid, p_entity uuid, p_expected bigint, p_delta integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $fn$
DECLARE actor uuid; result jsonb; previous_sub text;
BEGIN
  -- The trusted harness verifies the real local JWT before setting claims.
  -- The identity comes from the session guard, never a caller-supplied owner.
  actor := isg_session_fixture.require_active_session();
  -- Synthetic permission switch only: NOT a billing/quota/entitlement model.
  -- Hold through commit so a revoke that wins first denies new writes/replays.
  PERFORM 1 FROM isg_fixture.write_capabilities WHERE actor_id=actor AND can_mutate FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ACCESS_DENIED'; END IF;
  previous_sub := current_setting('request.jwt.claim.sub',true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  -- Reuse the reviewed owner/version/idempotency/audit/outbox implementation.
  -- This legacy prototype function is NOT granted to authenticated callers.
  result := isg_fixture.mutate(p_mutation,p_company,p_entity,p_expected,p_delta);
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  RETURN result;
END;
$fn$;
REVOKE ALL ON FUNCTION isg_fixture.mutate_verified(uuid,uuid,uuid,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT USAGE ON SCHEMA isg_fixture TO authenticated;
GRANT EXECUTE ON FUNCTION isg_fixture.mutate_verified(uuid,uuid,uuid,bigint,integer) TO authenticated;

-- Test-only observer. Security invoker, only controlled errors are returned;
-- the exception subtransaction rolls back all failed mutation side effects.
CREATE FUNCTION isg_fixture.observe_mutation(p_mutation uuid, p_company uuid, p_entity uuid, p_expected bigint, p_delta integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog
AS $fn$
DECLARE error_message text;
BEGIN
  RETURN jsonb_build_object('result',isg_fixture.mutate_verified(p_mutation,p_company,p_entity,p_expected,p_delta));
EXCEPTION
  WHEN SQLSTATE '28000' THEN RETURN jsonb_build_object('error','AUTH_REQUIRED');
  WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS error_message=MESSAGE_TEXT;
    IF error_message NOT IN ('AUTH_REQUIRED','ACCESS_DENIED','VALIDATION_ERROR','VERSION_CONFLICT','IDEMPOTENCY_CONFLICT','INJECTED_FAILURE') THEN RAISE; END IF;
    RETURN jsonb_build_object('error',error_message);
END;
$fn$;
REVOKE ALL ON FUNCTION isg_fixture.observe_mutation(uuid,uuid,uuid,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION isg_fixture.observe_mutation(uuid,uuid,uuid,bigint,integer) TO authenticated;
COMMIT;
