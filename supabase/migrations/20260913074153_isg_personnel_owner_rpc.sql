-- P05 first production-schema slice. Additive; rollout defaults OFF.
-- No changes to legacy company quotas, subscription products, or mobile identities.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE SCHEMA private_isg;
REVOKE ALL ON SCHEMA private_isg FROM PUBLIC, anon, authenticated, service_role;
ALTER TABLE public.companies ADD CONSTRAINT companies_id_user_isg_unique UNIQUE(id,user_id);

CREATE TABLE private_isg.rollout (
  feature text PRIMARY KEY CHECK(feature='personnel'),
  read_enabled boolean NOT NULL DEFAULT false,
  write_enabled boolean NOT NULL DEFAULT false,
  CHECK(NOT write_enabled OR read_enabled)
);
INSERT INTO private_isg.rollout(feature) VALUES('personnel');
CREATE TABLE private_isg.workplaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL,
  name text NOT NULL CHECK(btrim(name)<>''),
  address text, hazard_class text CHECK(hazard_class IN ('low','medium','high')),
  jurisdiction text, timezone text, needs_review boolean NOT NULL DEFAULT true,
  is_archived boolean NOT NULL DEFAULT false, legacy_company_id uuid UNIQUE,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  UNIQUE(company_id,id),
  CHECK(legacy_company_id IS NULL OR legacy_company_id=company_id),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL, code text NOT NULL CHECK(btrim(code)<>''),
  name text NOT NULL CHECK(btrim(name)<>''), is_archived boolean NOT NULL DEFAULT false,
  UNIQUE(company_id,id), UNIQUE(company_id,workplace_id,code),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, owner_id uuid NOT NULL,
  employee_code text NOT NULL CHECK(btrim(employee_code)<>''),
  full_name text NOT NULL CHECK(btrim(full_name)<>''),
  intake_department_id uuid, hired_on date CHECK(isfinite(hired_on)),
  employment_ends_before date CHECK(isfinite(employment_ends_before)),
  registered_at timestamptz NOT NULL DEFAULT now(),
  record_version bigint NOT NULL DEFAULT 0 CHECK(record_version BETWEEN 0 AND 9007199254740991),
  is_archived boolean NOT NULL DEFAULT false,
  CHECK(hired_on IS NULL OR employment_ends_before IS NULL OR hired_on<employment_ends_before),
  UNIQUE(company_id,id), UNIQUE(company_id,employee_code),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,intake_department_id) REFERENCES private_isg.departments(company_id,id)
);
CREATE TABLE private_isg.personnel_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.personnel_audit (
  event_id uuid PRIMARY KEY, company_id uuid NOT NULL, actor_id uuid NOT NULL,
  employee_id uuid NOT NULL, version bigint NOT NULL, operation_id uuid NOT NULL,
  action text NOT NULL CHECK(action IN ('create','edit','archive')),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(employee_id,version),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.personnel_outbox (
  event_id uuid PRIMARY KEY REFERENCES private_isg.personnel_audit(event_id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK(event_type IN ('employee.created','employee.updated','employee.archived')),
  schema_version integer NOT NULL DEFAULT 1 CHECK(schema_version=1),
  -- No worker consumes this new producer until the P01/P06 consumer is implemented.
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_isg.workplace_initializations (
  workplace_id uuid PRIMARY KEY REFERENCES private_isg.workplaces(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX isg_employee_directory ON private_isg.employees(company_id,is_archived,id);
CREATE INDEX isg_workplace_owner ON private_isg.workplaces(company_id,owner_id);
CREATE INDEX isg_department_owner ON private_isg.departments(company_id,owner_id);
CREATE INDEX isg_employee_owner ON private_isg.employees(company_id,owner_id);
CREATE INDEX isg_department_directory ON private_isg.departments(company_id,is_archived,id);
CREATE INDEX isg_department_workplace ON private_isg.departments(company_id,workplace_id);
CREATE INDEX isg_employee_department ON private_isg.employees(company_id,intake_department_id);
CREATE INDEX isg_personnel_receipt_company ON private_isg.personnel_receipts(company_id,actor_id);
CREATE INDEX isg_personnel_audit_company ON private_isg.personnel_audit(company_id,actor_id);
CREATE INDEX isg_personnel_audit_employee ON private_isg.personnel_audit(company_id,employee_id);
ALTER TABLE private_isg.rollout ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workplaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.personnel_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.personnel_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.personnel_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workplace_initializations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.text_value(value text, max_bytes integer) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE result text;
BEGIN
  result:=normalize(regexp_replace(btrim(value,E' \t\r\n'),E'[ \t\r\n]+',' ','g'),NFC);
  IF value IS NULL OR octet_length(value)>4096 OR octet_length(result)>max_bytes OR
     result ~ '[[:cntrl:]]' OR result ~ U&'[\200B\FEFF]' OR
     btrim(result,U&'\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')='' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  RETURN result;
END $$;
CREATE FUNCTION private_isg.name_key(value text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT translate(normalize(regexp_replace(btrim(value,E' \t\r\n'),E'[ \t\r\n]+',' ','g'),NFC),
    'ABCDEFGHIJKLMNOPQRSTUVWXYZÇĞİÖŞÜ','abcdefghıjklmnopqrstuvwxyzçğiöşü')
$$;
CREATE FUNCTION private_isg.active_actor() RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE claims jsonb:=auth.jwt(); actor uuid; session uuid;
BEGIN
  IF claims IS NULL OR jsonb_typeof(claims)<>'object' OR claims->>'role' IS DISTINCT FROM 'authenticated' OR
    jsonb_typeof(claims->'sub') IS DISTINCT FROM 'string' OR jsonb_typeof(claims->'session_id') IS DISTINCT FROM 'string' OR
    (claims->>'sub') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' OR
    (claims->>'session_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' OR
    jsonb_typeof(claims->'exp') IS DISTINCT FROM 'number' OR (claims->>'exp') !~ '^[0-9]{1,15}$' THEN
    RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='AUTH_REQUIRED'; END IF;
  actor:=(claims->>'sub')::uuid; session:=(claims->>'session_id')::uuid;
  -- auth.uid may use a legacy claim GUC. Require agreement, never trust it alone.
  IF auth.uid() IS DISTINCT FROM actor OR (claims->>'exp')::numeric<=extract(epoch FROM clock_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='AUTH_REQUIRED'; END IF;
  PERFORM 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id WHERE
    s.id=session AND s.user_id=actor AND (s.not_after IS NULL OR s.not_after>clock_timestamp()) AND
    u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp()) AND u.is_anonymous IS FALSE
    FOR SHARE OF s,u;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='28000',MESSAGE='AUTH_REQUIRED'; END IF;
  RETURN actor;
END $$;
CREATE FUNCTION private_isg.require_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='personnel' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_write THEN
    -- Existing effective subscription rules; user/profile metadata cannot grant this.
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $$;
CREATE FUNCTION private_isg.ensure_default(p_company uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE company public.companies; result uuid;
BEGIN
  SELECT * INTO STRICT company FROM public.companies WHERE id=p_company FOR UPDATE;
  SELECT id INTO result FROM private_isg.workplaces WHERE legacy_company_id=p_company;
  IF FOUND THEN RETURN result; END IF;
  INSERT INTO private_isg.workplaces(company_id,owner_id,name,address,hazard_class,is_archived,legacy_company_id)
    VALUES(company.id,company.user_id,company.name,to_jsonb(company)->>'address',company.hazard_class,company.is_archived,company.id) RETURNING id INTO result;
  INSERT INTO private_isg.workplace_initializations(workplace_id) VALUES(result);
  RETURN result;
END $$;
CREATE FUNCTION private_isg.company_default_after_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  -- Not an API grant; trigger follows a successful, legacy-authorized company INSERT.
  PERFORM private_isg.ensure_default(NEW.id); RETURN NEW;
END $$;
CREATE TRIGGER companies_isg_default AFTER INSERT ON public.companies
  FOR EACH ROW EXECUTE FUNCTION private_isg.company_default_after_insert();
-- Catch-up and initial backfill share one locked initializer. No invented timezone/jurisdiction.
SELECT private_isg.ensure_default(id) FROM public.companies ORDER BY id;

CREATE FUNCTION private_isg.employee_row(p_company uuid,p_employee uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('id',e.id,'owner_id',e.owner_id,'company_id',e.company_id,'name',e.full_name,
    'department_id',e.intake_department_id,'department_name',d.name,'version',e.record_version,'is_archived',e.is_archived)
  FROM private_isg.employees e LEFT JOIN private_isg.departments d ON d.company_id=e.company_id AND d.id=e.intake_department_id
  WHERE e.company_id=p_company AND e.id=p_employee
$$;
CREATE FUNCTION private_isg.read_personnel(p_company uuid,p_kind text,p_query text,p_archived boolean,p_after uuid,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; rows jsonb; cursor uuid; needle text;
BEGIN
  PERFORM private_isg.require_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('employees','departments','detail') OR p_query IS NULL OR octet_length(p_query)>200 OR p_archived IS NULL OR
    (p_kind='detail' AND (p_id IS NULL OR p_query<>'' OR p_after IS NOT NULL OR p_archived)) OR
    (p_kind<>'detail' AND p_id IS NOT NULL) OR (p_kind='departments' AND p_archived) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='detail' THEN
    result:=private_isg.employee_row(p_company,p_id);
    IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN result;
  END IF;
  needle:=private_isg.name_key(p_query);
  IF p_kind='employees' THEN
    WITH matches AS MATERIALIZED(SELECT e.id FROM private_isg.employees e WHERE e.company_id=p_company AND (p_archived OR NOT e.is_archived)
      AND (p_after IS NULL OR e.id>p_after) AND strpos(private_isg.name_key(e.full_name),needle)>0 ORDER BY e.id LIMIT 51),
      page AS(SELECT id FROM matches ORDER BY id LIMIT 50)
    SELECT coalesce(jsonb_agg(private_isg.employee_row(p_company,id) ORDER BY id),'[]'::jsonb),
      CASE WHEN(SELECT count(*) FROM matches)>50 THEN max(id::text)::uuid END INTO rows,cursor FROM page;
  ELSE
    WITH matches AS MATERIALIZED(SELECT d.* FROM private_isg.departments d JOIN private_isg.workplaces w ON w.company_id=d.company_id AND w.id=d.workplace_id
      WHERE d.company_id=p_company AND NOT d.is_archived AND NOT w.is_archived AND
      (p_after IS NULL OR d.id>p_after) AND strpos(private_isg.name_key(d.name),needle)>0 ORDER BY d.id LIMIT 51),
      page AS(SELECT * FROM matches ORDER BY id LIMIT 50)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'owner_id',owner_id,'company_id',company_id,'name',name) ORDER BY id),'[]'::jsonb),
      CASE WHEN(SELECT count(*) FROM matches)>50 THEN max(id::text)::uuid END INTO rows,cursor FROM page;
  END IF;
  RETURN jsonb_build_object('rows',rows,'next',cursor);
END $$;
CREATE FUNCTION private_isg.mutate_personnel(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,
  p_employee uuid,p_expected bigint,p_name text,p_change_department boolean,p_department uuid,p_department_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; person private_isg.employees; receipt private_isg.personnel_receipts;
  fullname text; depname text; depkey text; department uuid; workplace uuid; matches integer;
  fingerprint bytea; result jsonb; employee uuid; version bigint; event uuid:=gen_random_uuid();
BEGIN
  actor:=private_isg.require_company(p_company,true);
  IF p_operation IS NULL OR p_mutation IS NULL OR p_action IS NULL OR p_action NOT IN ('create','edit','archive') OR
    p_expected IS NULL OR p_expected<0 OR p_expected>=9007199254740991 OR p_change_department IS NULL OR
    (p_action='create' AND (p_employee IS NOT NULL OR p_expected<>0 OR NOT p_change_department)) OR
    (p_action<>'create' AND p_employee IS NULL) OR
    (p_action='archive' AND (p_name IS NOT NULL OR p_change_department)) OR
    (NOT p_change_department AND (p_department IS NOT NULL OR p_department_name IS NOT NULL)) OR
    (p_department IS NOT NULL AND p_department_name IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_action<>'archive' THEN fullname:=private_isg.text_value(p_name,200); END IF;
  IF p_department_name IS NOT NULL THEN depname:=private_isg.text_value(p_department_name,120);depkey:=private_isg.name_key(depname); END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_employee,p_expected,fullname,p_change_department,p_department,depkey)::text,'UTF8'));
  -- Actor-wide mutation key: changing action/company cannot recycle a previous key.
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-personnel:'||p_mutation::text,0));
  SELECT * INTO receipt FROM private_isg.personnel_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF receipt.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    PERFORM 1 FROM private_isg.employees WHERE id=(receipt.response->>'employee_id')::uuid AND company_id=p_company AND (p_action='archive' OR NOT is_archived) FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN receipt.response;
  END IF;
  IF p_action<>'create' THEN
    SELECT * INTO person FROM private_isg.employees WHERE company_id=p_company AND id=p_employee AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF person.record_version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  END IF;
  department:=person.intake_department_id;
  IF p_change_department THEN
    department:=p_department;
    IF depname IS NOT NULL THEN
      SELECT count(*),min(d.id::text)::uuid INTO matches,department FROM private_isg.departments d
        WHERE d.company_id=p_company AND NOT d.is_archived AND private_isg.name_key(d.name)=depkey;
      IF matches>1 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SELECTION_REQUIRED'; END IF;
      IF matches=0 THEN
        workplace:=private_isg.ensure_default(p_company);
        PERFORM 1 FROM private_isg.workplaces WHERE id=workplace AND NOT is_archived FOR SHARE;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID'; END IF;
        department:=gen_random_uuid();
        INSERT INTO private_isg.departments(id,company_id,owner_id,workplace_id,code,name) VALUES(department,p_company,actor,workplace,'D-'||department::text,depname);
      END IF;
    END IF;
    IF department IS NOT NULL THEN
      PERFORM 1 FROM private_isg.departments d JOIN private_isg.workplaces w ON w.id=d.workplace_id AND w.company_id=d.company_id
        WHERE d.id=department AND d.company_id=p_company AND NOT d.is_archived AND NOT w.is_archived FOR SHARE OF d,w;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID'; END IF;
    END IF;
  END IF;
  IF p_action='create' THEN
    employee:=gen_random_uuid();version:=0;
    INSERT INTO private_isg.employees(id,company_id,owner_id,employee_code,full_name,intake_department_id)
      VALUES(employee,p_company,actor,'P-'||employee::text,fullname,department);
  ELSE
    employee:=p_employee;version:=p_expected+1;
    UPDATE private_isg.employees SET full_name=CASE WHEN p_action='archive' THEN full_name ELSE fullname END,
      intake_department_id=department,record_version=version,is_archived=(p_action='archive') WHERE id=employee;
  END IF;
  result:=jsonb_build_object('schema_version',1,'operation_id',p_operation,'employee_id',employee,'owner_id',actor,'company_id',p_company,'version',version,'is_archived',p_action='archive');
  INSERT INTO private_isg.personnel_audit(event_id,company_id,actor_id,employee_id,version,operation_id,action)
    VALUES(event,p_company,actor,employee,version,p_operation,p_action);
  INSERT INTO private_isg.personnel_outbox(event_id,event_type)
    VALUES(event,CASE p_action WHEN 'create' THEN 'employee.created' WHEN 'edit' THEN 'employee.updated' ELSE 'employee.archived' END);
  INSERT INTO private_isg.personnel_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result;
END $$;

-- Exposed wrappers remain INVOKER. Only two checked entry points have a grant.
CREATE FUNCTION public.isg_personnel_read_v1(p_company uuid,p_kind text,p_query text,p_archived boolean,p_after uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_personnel(p_company,p_kind,p_query,p_archived,p_after,p_id)
$$;
CREATE FUNCTION public.isg_personnel_mutate_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,
  p_employee uuid,p_expected bigint,p_name text,p_change_department boolean,p_department uuid,p_department_name text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_personnel(p_company,p_action,p_operation,p_mutation,p_employee,p_expected,p_name,p_change_department,p_department,p_department_name)
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.isg_personnel_read_v1(uuid,text,text,boolean,uuid,uuid),
  public.isg_personnel_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,text,boolean,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA private_isg TO authenticated;
GRANT EXECUTE ON FUNCTION private_isg.read_personnel(uuid,text,text,boolean,uuid,uuid),
  private_isg.mutate_personnel(uuid,text,uuid,uuid,uuid,bigint,text,boolean,uuid,text),
  public.isg_personnel_read_v1(uuid,text,text,boolean,uuid,uuid),
  public.isg_personnel_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,text,boolean,uuid,text) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
