-- P01 candidate on a disposable Auth restore ONLY. Not a production migration.
-- Signature/issuer/audience verification belongs to the trusted gateway before
-- these claims are set. A SQL client who can set GUCs is NOT a trusted gateway.
-- This helper gives identity freshness, not company ownership, billing, MFA,
-- account-deletion workflow authorization or permission to mutate a domain.
CREATE SCHEMA isg_session_fixture AUTHORIZATION supabase_admin;
REVOKE ALL ON SCHEMA isg_session_fixture FROM PUBLIC, anon, service_role;
GRANT USAGE ON SCHEMA isg_session_fixture TO authenticated;

CREATE FUNCTION isg_session_fixture.require_active_session()
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog
AS $fn$
DECLARE
  claims jsonb := auth.jwt();
  actor_id uuid;
  session_id uuid;
  permitted_actor uuid;
  uuid_pattern constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$';
BEGIN
  IF claims IS NULL OR jsonb_typeof(claims) <> 'object'
    OR claims->>'role' IS DISTINCT FROM 'authenticated'
    OR jsonb_typeof(claims->'sub') IS DISTINCT FROM 'string'
    OR jsonb_typeof(claims->'session_id') IS DISTINCT FROM 'string'
    OR (claims->>'sub') !~ uuid_pattern
    OR (claims->>'session_id') !~ uuid_pattern
    OR jsonb_typeof(claims->'exp') IS DISTINCT FROM 'number'
    OR (claims->>'exp') !~ '^[0-9]{1,15}$'
  THEN RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='AUTH_REQUIRED'; END IF;
  IF (claims->>'exp')::numeric <= extract(epoch from clock_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='AUTH_REQUIRED';
  END IF;
  actor_id := (claims->>'sub')::uuid;
  session_id := (claims->>'session_id')::uuid;
  -- The locks live until the outer mutation transaction commits. Logout/delete
  -- that completed first is rejected; one arriving after this guard waits for
  -- that already-authorized transaction. Keep transactions short and bounded.
  SELECT u.id INTO permitted_actor
  FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
  WHERE s.id=session_id AND s.user_id=actor_id
    AND (s.not_after IS NULL OR s.not_after > clock_timestamp())
    AND u.deleted_at IS NULL
    AND (u.banned_until IS NULL OR u.banned_until <= clock_timestamp())
    AND u.is_anonymous IS FALSE
  FOR SHARE OF s,u;
  IF permitted_actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='AUTH_REQUIRED';
  END IF;
  RETURN permitted_actor;
END;
$fn$;
REVOKE ALL ON FUNCTION isg_session_fixture.require_active_session() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION isg_session_fixture.require_active_session() TO authenticated;

-- Trusted-test-only wrapper catches a controlled result without exposing IDs,
-- JWT, Auth records or diagnostic strings to the evidence log. Not client API.
CREATE FUNCTION isg_session_fixture.observe_guard()
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog
AS $fn$
BEGIN
  PERFORM isg_session_fixture.require_active_session();
  RETURN 'ALLOW';
EXCEPTION WHEN SQLSTATE '28000' THEN RETURN 'DENY';
END;
$fn$;
REVOKE ALL ON FUNCTION isg_session_fixture.observe_guard() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION isg_session_fixture.observe_guard() TO authenticated;
