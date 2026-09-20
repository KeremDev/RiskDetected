-- Product-level company profile for OSGB workspaces. NOT DEPLOYED TO PRODUCTION.
-- Existing company rows remain valid because the profile is optional and joined
-- with LEFT JOIN. The mutation is rollout-gated by workspace_companies.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE TABLE private_isg.workspace_company_profiles (
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  sector text NOT NULL CHECK(octet_length(sector) BETWEEN 1 AND 160),
  email text CHECK(email IS NULL OR octet_length(email)<=320),
  declared_employee_count integer CHECK(declared_employee_count IS NULL OR declared_employee_count BETWEEN 0 AND 10000000),
  address text CHECK(address IS NULL OR octet_length(address)<=1000),
  responsible_name text CHECK(responsible_name IS NULL OR octet_length(responsible_name)<=160),
  responsible_phone text CHECK(responsible_phone IS NULL OR octet_length(responsible_phone)<=80),
  responsible_email text CHECK(responsible_email IS NULL OR octet_length(responsible_email)<=320),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(workspace_id,company_id),
  FOREIGN KEY(workspace_id,company_id)
    REFERENCES private_isg.workspace_companies(workspace_id,id) ON DELETE RESTRICT,
  CHECK((responsible_name IS NULL AND responsible_phone IS NULL AND responsible_email IS NULL) OR
        (responsible_name IS NOT NULL AND responsible_phone IS NOT NULL AND responsible_email IS NOT NULL))
);
ALTER TABLE private_isg.workspace_company_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_company_profiles FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_company_profile_mutate(
  p_mutation uuid,p_workspace uuid,p_company uuid,p_expected bigint,p_sector text,p_email text,
  p_employee_count integer,p_address text,p_responsible_name text,p_responsible_phone text,p_responsible_email text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  current private_isg.workspace_company_profiles; saved private_isg.workspace_company_profiles;
  has_current boolean; clean_sector text; clean_email text; clean_address text;
  clean_name text; clean_phone text; clean_responsible_email text;
  fingerprint bytea; replay jsonb; before_state jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  clean_sector:=private_isg.workspace_text(p_sector,160);
  clean_email:=nullif(btrim(coalesce(p_email,'')),'');
  clean_address:=nullif(btrim(coalesce(p_address,'')),'');
  clean_name:=nullif(btrim(coalesce(p_responsible_name,'')),'');
  clean_phone:=nullif(btrim(coalesce(p_responsible_phone,'')),'');
  clean_responsible_email:=nullif(btrim(coalesce(p_responsible_email,'')),'');
  IF p_mutation IS NULL OR p_expected IS NULL OR p_expected<0 OR
     p_employee_count IS NOT NULL AND p_employee_count NOT BETWEEN 0 AND 10000000 OR
     clean_email IS NOT NULL AND (octet_length(clean_email)>320 OR clean_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') OR
     clean_address IS NOT NULL AND octet_length(clean_address)>1000 OR
     clean_name IS NOT NULL AND octet_length(clean_name)>160 OR
     clean_phone IS NOT NULL AND octet_length(clean_phone)>80 OR
     clean_responsible_email IS NOT NULL AND (octet_length(clean_responsible_email)>320 OR clean_responsible_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') OR
     ((clean_name IS NULL OR clean_phone IS NULL OR clean_responsible_email IS NULL) AND
      (clean_name IS NOT NULL OR clean_phone IS NOT NULL OR clean_responsible_email IS NOT NULL)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_expected,clean_sector,clean_email,
    p_employee_count,clean_address,clean_name,clean_phone,clean_responsible_email)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'company.profile',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO current FROM private_isg.workspace_company_profiles
    WHERE workspace_id=p_workspace AND company_id=p_company FOR UPDATE;
  has_current:=FOUND;
  IF has_current AND current.version<>p_expected THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';
  ELSIF NOT has_current AND p_expected<>0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';
  END IF;
  before_state:=CASE WHEN has_current THEN to_jsonb(current)-ARRAY['created_by_user_id','updated_by_user_id'] ELSE NULL END;
  INSERT INTO private_isg.workspace_company_profiles(workspace_id,company_id,sector,email,declared_employee_count,
    address,responsible_name,responsible_phone,responsible_email,created_by_user_id,updated_by_user_id)
  VALUES(p_workspace,p_company,clean_sector,clean_email,p_employee_count,clean_address,clean_name,clean_phone,
    clean_responsible_email,actor,actor)
  ON CONFLICT(workspace_id,company_id) DO UPDATE SET sector=EXCLUDED.sector,email=EXCLUDED.email,
    declared_employee_count=EXCLUDED.declared_employee_count,address=EXCLUDED.address,
    responsible_name=EXCLUDED.responsible_name,responsible_phone=EXCLUDED.responsible_phone,
    responsible_email=EXCLUDED.responsible_email,version=private_isg.workspace_company_profiles.version+1,
    updated_by_user_id=actor,updated_at=clock_timestamp()
  RETURNING * INTO saved;
  UPDATE public.companies SET address=clean_address,contact_person=clean_name,default_responsible=clean_name
    WHERE id=p_company AND workspace_id=p_workspace;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_CANONICAL_MISSING'; END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'sector',saved.sector,'email',saved.email,'declared_employee_count',saved.declared_employee_count,
    'address',saved.address,'responsible_name',saved.responsible_name,'responsible_phone',saved.responsible_phone,
    'responsible_email',saved.responsible_email,'profile_version',saved.version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'company.profile',fingerprint,p_workspace,
    'company',p_company,saved.version,before_state,result,NULL,result);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_company_list(p_workspace uuid,p_after uuid,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships; rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',false);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  WITH visible AS (
    SELECT c.*,p.sector,p.email,p.declared_employee_count,p.address,p.responsible_name,p.responsible_phone,
      p.responsible_email,p.version profile_version
    FROM private_isg.workspace_companies c
    LEFT JOIN private_isg.workspace_company_profiles p ON p.workspace_id=c.workspace_id AND p.company_id=c.id
    WHERE c.workspace_id=p_workspace AND c.status='active' AND (p_after IS NULL OR c.id>p_after)
      AND (member.role IN ('owner','admin') OR EXISTS(SELECT 1 FROM private_isg.company_assignments a
        WHERE a.workspace_id=p_workspace AND a.company_id=c.id AND a.membership_id=member.id
          AND a.starts_at<=clock_timestamp() AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp())))
    ORDER BY c.id LIMIT p_limit+1
  ), page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
  SELECT coalesce(jsonb_agg(jsonb_build_object('company_id',id,'name',name,'hazard_class',hazard_class,
      'status',status,'version',version,'sector',sector,'email',email,'declared_employee_count',declared_employee_count,
      'address',address,'responsible_name',responsible_name,'responsible_phone',responsible_phone,
      'responsible_email',responsible_email,'profile_version',profile_version) ORDER BY id),'[]'::jsonb),
    CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
    INTO rows,next_id FROM page;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION public.isg_workspace_company_profile_mutate_v1(
  p_mutation uuid,p_workspace uuid,p_company uuid,p_expected bigint,p_sector text,p_email text,
  p_employee_count integer,p_address text,p_responsible_name text,p_responsible_phone text,p_responsible_email text
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_company_profile_mutate(p_mutation,p_workspace,p_company,p_expected,p_sector,p_email,
    p_employee_count,p_address,p_responsible_name,p_responsible_phone,p_responsible_email)
$$;

REVOKE ALL ON FUNCTION private_isg.workspace_company_profile_mutate(uuid,uuid,uuid,bigint,text,text,integer,text,text,text,text),
  public.isg_workspace_company_profile_mutate_v1(uuid,uuid,uuid,bigint,text,text,integer,text,text,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_company_profile_mutate(uuid,uuid,uuid,bigint,text,text,integer,text,text,text,text),
  public.isg_workspace_company_profile_mutate_v1(uuid,uuid,uuid,bigint,text,text,integer,text,text,text,text)
  TO authenticated;
