-- Local candidate only. No real account is seeded and no rollout is opened.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE TABLE private_isg.p05_pilot_accounts (
  actor_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  read_enabled boolean NOT NULL DEFAULT false,
  write_enabled boolean NOT NULL DEFAULT false,
  approved_reference text NOT NULL CHECK(approved_reference ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{2,119}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK(NOT write_enabled OR read_enabled),
  CHECK(isfinite(created_at) AND isfinite(expires_at) AND expires_at>created_at AND expires_at<=created_at+interval '30 days')
);
-- Receipt/provenance survives company deletion: a retry must not recreate it.
-- Account deletion removes these opaque IDs/hashes, not another user's data.
CREATE TABLE private_isg.p05_pilot_company_origins (
  company_id uuid PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mutation_id uuid NOT NULL,
  request_sha256 bytea NOT NULL CHECK(octet_length(request_sha256)=32),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,mutation_id)
);
ALTER TABLE private_isg.p05_pilot_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.p05_pilot_company_origins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.p05_pilot_accounts,private_isg.p05_pilot_company_origins FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.p05_pilot_account_enabled(p_actor uuid,p_write boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_actor IS NULL OR p_write IS NULL THEN RETURN false; END IF;
  PERFORM 1 FROM private_isg.p05_pilot_accounts a JOIN private_isg.rollout r ON r.feature='personnel'
    WHERE a.actor_id=p_actor AND a.read_enabled AND r.read_enabled
      AND (NOT p_write OR (a.write_enabled AND r.write_enabled))
      AND a.revoked_at IS NULL AND a.created_at<=clock_timestamp() AND a.expires_at>clock_timestamp()
    FOR SHARE OF a,r;
  RETURN FOUND;
END $$;
CREATE OR REPLACE FUNCTION private_isg.p05_pilot_can_read(p_actor uuid,p_company uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF NOT private_isg.p05_pilot_account_enabled(p_actor,false) THEN RETURN false; END IF;
  IF p_company IS NULL THEN RETURN true; END IF; -- Account can reach an empty company list.
  PERFORM 1 FROM private_isg.p05_pilot_grants g
    JOIN private_isg.p05_pilot_company_origins o ON o.company_id=g.company_id AND o.actor_id=g.actor_id
    JOIN public.companies c ON c.id=g.company_id AND c.user_id=g.actor_id
    WHERE g.actor_id=p_actor AND g.company_id=p_company AND g.revoked_at IS NULL
      AND g.created_at<=clock_timestamp() AND g.expires_at>clock_timestamp()
    FOR SHARE OF g,o;
  RETURN FOUND;
END $$;
CREATE OR REPLACE FUNCTION private_isg.require_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF p_company IS NULL OR p_write IS NULL OR NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_write THEN
    IF NOT private_isg.p05_pilot_account_enabled(actor,true) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro')
      AND status IN ('active','trialing','grace_period')
      AND (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $$;

-- Checked private DEFINER follows existing P05 API architecture. The caller
-- never supplies an owner or an existing company ID. Legacy plan/limit helper
-- and company write trigger remain unchanged; no paid/quota override exists.
CREATE FUNCTION private_isg.p05_pilot_create_company(p_mutation uuid,p_name text,p_hazard_class text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();account private_isg.p05_pilot_accounts;
  prior private_isg.p05_pilot_company_origins;company public.companies;fingerprint bytea;name text;
BEGIN
  IF p_mutation IS NULL OR p_name IS NULL OR p_hazard_class IS NULL OR p_hazard_class NOT IN ('low','medium','high') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  name:=private_isg.text_value(p_name,200);
  -- One lock order for every creation, including retry, before grant SHARE locks.
  SELECT * INTO account FROM private_isg.p05_pilot_accounts WHERE actor_id=actor FOR UPDATE;
  IF NOT FOUND OR NOT private_isg.p05_pilot_account_enabled(actor,true) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(name,p_hazard_class)::text,'UTF8'));
  SELECT * INTO prior FROM private_isg.p05_pilot_company_origins WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_sha256<>fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    PERFORM private_isg.require_company(prior.company_id,true);
    SELECT * INTO STRICT company FROM public.companies WHERE id=prior.company_id AND user_id=actor;
    RETURN jsonb_build_object('schema_version',1,'company',to_jsonb(company),'replayed',true);
  END IF;
  PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro')
    AND status IN ('active','trialing','grace_period')
    AND (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
  IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
  IF (SELECT count(*) FROM public.companies WHERE user_id=actor AND NOT is_archived)>=coalesce(private.company_limit_for_user(actor),0) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='company_limit_exceeded'; END IF;
  INSERT INTO public.companies(user_id,name,hazard_class) VALUES(actor,name,p_hazard_class) RETURNING * INTO company;
  INSERT INTO private_isg.p05_pilot_company_origins(company_id,actor_id,mutation_id,request_sha256)
    VALUES(company.id,actor,p_mutation,fingerprint);
  INSERT INTO private_isg.p05_pilot_grants(actor_id,company_id,approved_reference,expires_at)
    VALUES(actor,company.id,account.approved_reference,account.expires_at);
  PERFORM private_isg.ensure_default(company.id);
  RETURN jsonb_build_object('schema_version',1,'company',to_jsonb(company),'replayed',false);
END $$;
CREATE FUNCTION public.isg_pilot_company_create_v1(p_mutation uuid,p_name text,p_hazard_class text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.p05_pilot_create_company(p_mutation,p_name,p_hazard_class)
$$;

CREATE OR REPLACE FUNCTION private_isg.workspace_availability(p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();can_read boolean;can_write boolean:=false;company public.companies;
BEGIN
  can_read:=private_isg.p05_pilot_can_read(actor,p_company);
  IF can_read AND p_company IS NOT NULL THEN
    BEGIN
      PERFORM private_isg.require_company(p_company,true);can_write:=true;
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM NOT IN ('FEATURE_UNAVAILABLE','PAID_PLAN_REQUIRED','ACCESS_DENIED') THEN RAISE; END IF;
    END;
    PERFORM private_isg.require_company(p_company,false);
    SELECT * INTO STRICT company FROM public.companies WHERE id=p_company AND user_id=actor;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,
    'company_name',company.name,'is_archived',company.is_archived,'can_read',can_read,'can_write',can_write);
END $$;

-- Remove the NEW ISG global hook, not any legacy trigger. Explicit pilot RPC
-- initializes only its newly created company. Historical bootstrap is unchanged.
DROP TRIGGER companies_isg_default ON public.companies;
REVOKE ALL ON FUNCTION private_isg.p05_pilot_account_enabled(uuid,boolean),
  private_isg.p05_pilot_create_company(uuid,text,text),public.isg_pilot_company_create_v1(uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.p05_pilot_create_company(uuid,text,text),
  public.isg_pilot_company_create_v1(uuid,text,text) TO authenticated;
UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='personnel';
NOTIFY pgrst,'reload schema';
COMMIT;
