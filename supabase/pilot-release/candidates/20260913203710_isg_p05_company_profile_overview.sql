-- Additive pilot-only extension. V1, legacy company rows, quotas and rollout remain unchanged.
-- The migration transport owns the transaction (no BEGIN/COMMIT here).
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';
CREATE TABLE private_isg.p05_company_profiles (
  company_id uuid PRIMARY KEY,
  owner_id uuid NOT NULL,
  sector text NOT NULL CHECK(octet_length(sector) BETWEEN 1 AND 120),
  email text CHECK(email IS NULL OR (octet_length(email)<=254 AND email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$')),
  declared_employee_count integer CHECK(declared_employee_count BETWEEN 0 AND 10000000),
  responsible_employee_id uuid,
  create_hash bytea NOT NULL CHECK(octet_length(create_hash)=32),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,responsible_employee_id) REFERENCES private_isg.employees(company_id,id)
);
CREATE INDEX p05_company_profile_responsible ON private_isg.p05_company_profiles(company_id,responsible_employee_id);
CREATE INDEX p05_company_profile_owner ON private_isg.p05_company_profiles(company_id,owner_id);
ALTER TABLE private_isg.p05_company_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.p05_company_profiles FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.p05_company_create_v2(p_mutation uuid,p_name text,p_hazard_class text,
  p_sector text,p_email text,p_employee_count integer,p_responsible_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); result jsonb; company uuid; fingerprint bytea;
  sector text; email text; responsible text; person uuid; profile private_isg.p05_company_profiles;
BEGIN
  -- Same normalization and limits on both sides; optional values are absent, never invented.
  sector:=private_isg.text_value(p_sector,120);
  IF p_email IS NOT NULL THEN
    email:=private_isg.text_value(p_email,254);
    IF email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  END IF;
  IF p_employee_count IS NOT NULL AND (p_employee_count<0 OR p_employee_count>10000000) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_responsible_name IS NOT NULL THEN responsible:=private_isg.text_value(p_responsible_name,200); END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(sector,email,p_employee_count,responsible)::text,'UTF8'));
  -- V1 locks the actor, checks paid/quota/expiry and creates company+grant+workplace atomically.
  result:=private_isg.p05_pilot_create_company(p_mutation,p_name,p_hazard_class);
  company:=(result->'company'->>'id')::uuid;
  SELECT * INTO profile FROM private_isg.p05_company_profiles WHERE company_id=company AND owner_id=actor;
  IF FOUND THEN
    IF profile.create_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
  ELSE
    -- A V1 mutation cannot be reused to attach a different V2 intent to an existing company.
    IF (result->>'replayed')::boolean THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    IF responsible IS NOT NULL THEN
      person:=(private_isg.mutate_personnel(company,'create',gen_random_uuid(),gen_random_uuid(),NULL,0,
        responsible,true,NULL,NULL)->>'employee_id')::uuid;
    END IF;
    INSERT INTO private_isg.p05_company_profiles(company_id,owner_id,sector,email,declared_employee_count,responsible_employee_id,create_hash)
      VALUES(company,actor,sector,email,p_employee_count,person,fingerprint);
  END IF;
  RETURN result || jsonb_build_object('schema_version',2);
END $$;
CREATE FUNCTION public.isg_pilot_company_create_v2(p_mutation uuid,p_name text,p_hazard_class text,
  p_sector text,p_email text,p_employee_count integer,p_responsible_name text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.p05_company_create_v2(p_mutation,p_name,p_hazard_class,p_sector,p_email,p_employee_count,p_responsible_name)
$$;

CREATE FUNCTION private_isg.p05_company_overview(p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); company public.companies; profile private_isg.p05_company_profiles;
  rows jsonb:='[]';
BEGIN
  IF NOT private_isg.p05_pilot_can_read(actor,NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL THEN PERFORM private_isg.require_company(p_company,false); END IF;
  FOR company IN SELECT c.* FROM public.companies c
    JOIN private_isg.p05_pilot_company_origins o ON o.company_id=c.id AND o.actor_id=c.user_id
    WHERE c.user_id=actor AND (p_company IS NULL OR c.id=p_company) ORDER BY c.id LOOP
    IF NOT private_isg.p05_pilot_can_read(actor,company.id) THEN CONTINUE; END IF;
    PERFORM private_isg.require_company(company.id,false);
    SELECT * INTO profile FROM private_isg.p05_company_profiles WHERE company_id=company.id AND owner_id=actor;
    rows:=rows || jsonb_build_array(jsonb_build_object(
      'id',company.id,'owner_id',actor,'name',company.name,'hazard_class',company.hazard_class,'is_archived',company.is_archived,
      'sector',profile.sector,'email',profile.email,'declared_employee_count',profile.declared_employee_count,
      'responsible_employee_id',profile.responsible_employee_id,
      'personnel_count',(SELECT count(*) FROM private_isg.employees WHERE company_id=company.id AND owner_id=actor AND NOT is_archived),
      'workplace_count',(SELECT count(*) FROM private_isg.workplaces WHERE company_id=company.id AND owner_id=actor AND NOT is_archived),
      'department_count',(SELECT count(*) FROM private_isg.departments WHERE company_id=company.id AND owner_id=actor AND NOT is_archived),
      'finding_count',NULL,'document_count',NULL,'completion_score',NULL));
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'companies',rows);
END $$;
CREATE FUNCTION public.isg_pilot_overview_v1(p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.p05_company_overview(p_company) $$;

REVOKE ALL ON FUNCTION private_isg.p05_company_create_v2(uuid,text,text,text,text,integer,text),
  public.isg_pilot_company_create_v2(uuid,text,text,text,text,integer,text),
  private_isg.p05_company_overview(uuid),public.isg_pilot_overview_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.p05_company_create_v2(uuid,text,text,text,text,integer,text),
  public.isg_pilot_company_create_v2(uuid,text,text,text,text,integer,text),
  private_isg.p05_company_overview(uuid),public.isg_pilot_overview_v1(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
