-- Preparation only. Empty roster + rollout OFF. Not a deployment authorization.
-- Requires the four P05 candidates through 20260913092642.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

CREATE TABLE private_isg.p05_pilot_grants (
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  approved_reference text NOT NULL CHECK(approved_reference ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{2,119}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  PRIMARY KEY(actor_id,company_id),
  CHECK(isfinite(created_at) AND isfinite(expires_at) AND expires_at>created_at
    AND expires_at<=created_at+interval '30 days')
);
CREATE INDEX p05_pilot_company_idx ON private_isg.p05_pilot_grants(company_id);
ALTER TABLE private_isg.p05_pilot_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.p05_pilot_grants FROM PUBLIC,anon,authenticated,service_role;

-- No client-settable claim, build string, GUC, metadata or wildcard grants.
-- Read locks serialize grant/flag revocation against an already authorized read.
CREATE FUNCTION private_isg.p05_pilot_can_read(p_actor uuid,p_company uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout AS r
    JOIN private_isg.p05_pilot_grants AS g ON g.actor_id=p_actor
    JOIN public.companies AS c ON c.id=g.company_id AND c.user_id=p_actor
    WHERE r.feature='personnel' AND r.read_enabled
      AND g.revoked_at IS NULL AND g.expires_at>clock_timestamp()
      AND (p_company IS NULL OR g.company_id=p_company)
    FOR SHARE OF r,g,c;
  RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION private_isg.p05_pilot_can_read(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- All existing personnel/directory/context reads and mutations enter here.
-- Pilot v1 is strictly read-only, even if someone sets the generic write flag.
CREATE OR REPLACE FUNCTION private_isg.require_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF p_company IS NULL OR p_write IS NULL OR
     NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_write THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  RETURN actor;
END $$;

-- Keep the established wrapper and result contract. A global read is discovery
-- only, not company authorization; it never exposes the roster or grants writes.
CREATE OR REPLACE FUNCTION private_isg.workspace_availability(p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();can_read boolean;company public.companies;
BEGIN
  can_read:=private_isg.p05_pilot_can_read(actor,p_company);
  IF can_read AND p_company IS NOT NULL THEN
    PERFORM private_isg.require_company(p_company,false);
    SELECT * INTO STRICT company FROM public.companies WHERE id=p_company AND user_id=actor;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,
    'company_name',company.name,'is_archived',company.is_archived,'can_read',can_read,'can_write',false);
END $$;
-- CREATE OR REPLACE preserves the previous restricted grants; state them again.
REVOKE ALL ON FUNCTION private_isg.require_company(uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private_isg.workspace_availability(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_availability(uuid) TO authenticated;
UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='personnel';
NOTIFY pgrst,'reload schema';
COMMIT;
