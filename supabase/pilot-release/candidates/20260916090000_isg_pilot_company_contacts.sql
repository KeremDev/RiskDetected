-- Additive pilot API; V1/V2 requests and ordinary company writes retain their contract.
-- Execute in one transaction. No enrollment, rollout changes or business-data backfill.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';
ALTER TABLE private_isg.p05_company_profiles
  ADD COLUMN responsible_phone text CHECK(responsible_phone IS NULL OR responsible_phone ~ '^[+]?[0-9]{7,15}$'),
  ADD COLUMN responsible_email text CHECK(responsible_email IS NULL OR (octet_length(responsible_email)<=254 AND responsible_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$')),
  ADD COLUMN contact_create_hash bytea CHECK(contact_create_hash IS NULL OR octet_length(contact_create_hash)=32),
  ADD CONSTRAINT p05_responsible_contact_pair CHECK(
    (responsible_phone IS NULL AND responsible_email IS NULL) OR
    (responsible_employee_id IS NOT NULL AND responsible_phone IS NOT NULL AND responsible_email IS NOT NULL));

CREATE FUNCTION private_isg.p05_company_create_v3(p_mutation uuid,p_name text,p_hazard_class text,
  p_sector text,p_email text,p_employee_count integer,p_responsible_name text,
  p_responsible_phone text,p_responsible_email text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); result jsonb; company uuid;
  phone text; contact_mail text; fingerprint bytea; saved_hash bytea;
BEGIN
  -- V2 retains the actor lock and current pilot, paid-plan and quota checks even on replay.
  IF p_responsible_name IS NOT NULL THEN
    phone:=regexp_replace(private_isg.text_value(p_responsible_phone,64),'[ ()-]','','g');
    contact_mail:=private_isg.text_value(p_responsible_email,254);
    IF phone !~ '^[+]?[0-9]{7,15}$' OR contact_mail !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  ELSIF p_responsible_phone IS NOT NULL OR p_responsible_email IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(phone,contact_mail)::text,'UTF8'));
  result:=private_isg.p05_company_create_v2(p_mutation,p_name,p_hazard_class,p_sector,p_email,p_employee_count,p_responsible_name);
  company:=(result->'company'->>'id')::uuid;
  SELECT contact_create_hash INTO saved_hash FROM private_isg.p05_company_profiles
    WHERE company_id=company AND owner_id=actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF saved_hash IS NOT NULL THEN
    IF saved_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
  ELSE
    -- An earlier V1/V2 mutation cannot acquire a new contact intent on retry.
    IF (result->>'replayed')::boolean THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    UPDATE private_isg.p05_company_profiles SET responsible_phone=phone,responsible_email=contact_mail,contact_create_hash=fingerprint
      WHERE company_id=company AND owner_id=actor;
  END IF;
  RETURN result || jsonb_build_object('schema_version',3);
END $$;
CREATE FUNCTION public.isg_pilot_company_create_v3(p_mutation uuid,p_name text,p_hazard_class text,
  p_sector text,p_email text,p_employee_count integer,p_responsible_name text,
  p_responsible_phone text,p_responsible_email text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.p05_company_create_v3(p_mutation,p_name,p_hazard_class,p_sector,p_email,p_employee_count,p_responsible_name,p_responsible_phone,p_responsible_email)
$$;
CREATE FUNCTION private_isg.p05_company_overview_v2(p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; rows jsonb;
BEGIN
  -- Only enrich rows already authorized by the existing pilot/owner checks.
  result:=private_isg.p05_company_overview(p_company);
  SELECT coalesce(jsonb_agg(entry || jsonb_build_object('responsible_name',e.full_name,
    'responsible_phone',p.responsible_phone,'responsible_email',p.responsible_email) ORDER BY ordinal),'[]'::jsonb)
    INTO rows FROM jsonb_array_elements(result->'companies') WITH ORDINALITY AS r(entry,ordinal)
    LEFT JOIN private_isg.p05_company_profiles p ON p.company_id=(entry->>'id')::uuid AND p.owner_id=(result->>'owner_id')::uuid
    LEFT JOIN private_isg.employees e ON e.company_id=p.company_id AND e.owner_id=p.owner_id AND e.id=p.responsible_employee_id;
  RETURN result || jsonb_build_object('schema_version',2,'companies',rows);
END $$;
CREATE FUNCTION public.isg_pilot_overview_v2(p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.p05_company_overview_v2(p_company) $$;
REVOKE ALL ON FUNCTION private_isg.p05_company_create_v3(uuid,text,text,text,text,integer,text,text,text),
 public.isg_pilot_company_create_v3(uuid,text,text,text,text,integer,text,text,text),
 private_isg.p05_company_overview_v2(uuid), public.isg_pilot_overview_v2(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.p05_company_create_v3(uuid,text,text,text,text,integer,text,text,text),
 public.isg_pilot_company_create_v3(uuid,text,text,text,text,integer,text,text,text),
 private_isg.p05_company_overview_v2(uuid), public.isg_pilot_overview_v2(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
