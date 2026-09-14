-- Approved P05 scoped pilot; activation is a separate DML transaction.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';
DO $preflight$ BEGIN
  IF to_regnamespace('private_isg') IS NOT NULL OR
    (SELECT max(version) FROM supabase_migrations.schema_migrations) IS DISTINCT FROM '20260908134026' THEN
    RAISE EXCEPTION 'PILOT_RELEASE_BASELINE_CHANGED'; END IF;
  IF md5(pg_get_functiondef('private.user_plan_tier(uuid)'::regprocedure)||pg_get_functiondef('private.company_limit_for_user(uuid)'::regprocedure)||pg_get_functiondef('private.enforce_company_write_rules()'::regprocedure)) <> 'e61b8d817d8917fdb99d2f44364b8414' THEN
    RAISE EXCEPTION 'PILOT_RELEASE_LEGACY_HELPER_CHANGED'; END IF;
END $preflight$;
-- REVIEW CANDIDATE. No deployment authorization. All accounts/flags remain closed.

-- Source: supabase/migrations/20260913074153_isg_personnel_owner_rpc.sql
-- P05 first production-schema slice. Additive; rollout defaults OFF.
-- No changes to legacy company quotas, subscription products, or mobile identities.

SET LOCAL lock_timeout='1s';
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
-- Pilot package: do not bootstrap any existing company.

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


-- Source: supabase/migrations/20260913081536_isg_workplace_context_assignments.sql
-- P05 domain expansion. Additive and gated by private_isg.rollout; no live activation.

SET LOCAL lock_timeout='1s';
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;
SET LOCAL search_path=private_isg,extensions,pg_catalog;
ALTER TABLE private_isg.workplaces ADD COLUMN code text;
UPDATE private_isg.workplaces SET code='W-'||id::text;
ALTER TABLE private_isg.workplaces ALTER COLUMN code SET NOT NULL;
ALTER TABLE private_isg.workplaces ADD CONSTRAINT workplace_code_unique UNIQUE(company_id,code);
ALTER TABLE private_isg.workplaces ADD COLUMN context_version bigint NOT NULL DEFAULT 0 CHECK(context_version BETWEEN 0 AND 9007199254740991);
ALTER TABLE private_isg.departments ADD COLUMN parent_id uuid;
ALTER TABLE private_isg.departments ADD COLUMN version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991);
ALTER TABLE private_isg.departments ADD CONSTRAINT department_workplace_identity UNIQUE(company_id,workplace_id,id);
ALTER TABLE private_isg.departments ADD CONSTRAINT department_parent_scope FOREIGN KEY(company_id,workplace_id,parent_id) REFERENCES private_isg.departments(company_id,workplace_id,id);
CREATE INDEX department_parent_scope_idx ON private_isg.departments(company_id,workplace_id,parent_id);

CREATE TABLE private_isg.job_roles (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
 code text NOT NULL CHECK(btrim(code)<>''),title text NOT NULL CHECK(btrim(title)<>''),description text NOT NULL DEFAULT '',
 is_archived boolean NOT NULL DEFAULT false,version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
 UNIQUE(company_id,id),UNIQUE(company_id,code),
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.contractor_organizations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
 code text NOT NULL CHECK(btrim(code)<>''),name text NOT NULL CHECK(btrim(name)<>''),
 relationship text NOT NULL CHECK(relationship IN('subcontractor','contractor','supplier','other')),
 is_archived boolean NOT NULL DEFAULT false,version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
 UNIQUE(company_id,id),UNIQUE(company_id,code),
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.contractor_engagements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
 organization_id uuid NOT NULL,workplace_id uuid NOT NULL,starts_on date NOT NULL CHECK(isfinite(starts_on)),
 ends_before date CHECK(isfinite(ends_before) AND ends_before>starts_on),
 effective_dates daterange GENERATED ALWAYS AS(daterange(starts_on,ends_before,'[)')) STORED,
 description text NOT NULL DEFAULT '',version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
 UNIQUE(company_id,id),
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
 FOREIGN KEY(company_id,organization_id) REFERENCES private_isg.contractor_organizations(company_id,id),
 FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id),
 EXCLUDE USING gist(company_id WITH =,organization_id WITH =,workplace_id WITH =,effective_dates WITH &&)
);
ALTER TABLE private_isg.employees ADD COLUMN employer_org_id uuid;
ALTER TABLE private_isg.employees ADD COLUMN employer_version bigint NOT NULL DEFAULT 0 CHECK(employer_version BETWEEN 0 AND 9007199254740991);
ALTER TABLE private_isg.employees ADD COLUMN assignment_version bigint NOT NULL DEFAULT 0 CHECK(assignment_version BETWEEN 0 AND 9007199254740991);
ALTER TABLE private_isg.employees ADD CONSTRAINT employee_employer_scope FOREIGN KEY(company_id,employer_org_id) REFERENCES private_isg.contractor_organizations(company_id,id);
CREATE INDEX employee_employer_scope_idx ON private_isg.employees(company_id,employer_org_id);
CREATE TABLE private_isg.workplace_context_versions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,workplace_id uuid NOT NULL,
 starts_on date NOT NULL CHECK(isfinite(starts_on)),ends_before date CHECK(isfinite(ends_before) AND ends_before>starts_on),
 effective_dates daterange GENERATED ALWAYS AS(daterange(starts_on,ends_before,'[)')) STORED,
 timezone text NOT NULL,jurisdiction text NOT NULL CHECK(btrim(jurisdiction)<>''),
 hazard_class text NOT NULL CHECK(hazard_class IN('low','medium','high')),industry_code text,evidence_note text NOT NULL CHECK(btrim(evidence_note)<>''),
 UNIQUE(company_id,id),
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
 FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id),
 EXCLUDE USING gist(company_id WITH =,workplace_id WITH =,effective_dates WITH &&)
);
CREATE TABLE private_isg.employee_assignments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,employee_id uuid NOT NULL,
 workplace_id uuid NOT NULL,department_id uuid NOT NULL,job_role_id uuid NOT NULL,
 kind text NOT NULL DEFAULT 'primary' CHECK(kind='primary'),starts_on date NOT NULL CHECK(isfinite(starts_on)),
 ends_before date CHECK(isfinite(ends_before) AND ends_before>starts_on),
 effective_dates daterange GENERATED ALWAYS AS(daterange(starts_on,ends_before,'[)')) STORED,
 department_name_snapshot text NOT NULL,job_title_snapshot text NOT NULL,employer_org_id_snapshot uuid,employer_name_snapshot text,
 reason text NOT NULL DEFAULT '',
 UNIQUE(company_id,id),
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
 FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE,
 FOREIGN KEY(company_id,workplace_id,department_id) REFERENCES private_isg.departments(company_id,workplace_id,id),
 FOREIGN KEY(company_id,job_role_id) REFERENCES private_isg.job_roles(company_id,id),
 FOREIGN KEY(company_id,employer_org_id_snapshot) REFERENCES private_isg.contractor_organizations(company_id,id),
 EXCLUDE USING gist(company_id WITH =,employee_id WITH =,effective_dates WITH &&)
);
CREATE TABLE private_isg.directory_events (
 event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
 operation_id uuid NOT NULL,entity_kind text NOT NULL,entity_id uuid NOT NULL,version bigint NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(company_id,entity_kind,entity_id,version),
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.directory_outbox (
 event_id uuid PRIMARY KEY REFERENCES private_isg.directory_events(event_id) ON DELETE CASCADE,
 schema_version integer NOT NULL DEFAULT 1 CHECK(schema_version=1)
);
CREATE INDEX job_owner_idx ON private_isg.job_roles(company_id,owner_id);
CREATE INDEX contractor_owner_idx ON private_isg.contractor_organizations(company_id,owner_id);
CREATE INDEX engagement_owner_idx ON private_isg.contractor_engagements(company_id,owner_id);
CREATE INDEX engagement_organization_idx ON private_isg.contractor_engagements(company_id,organization_id);
CREATE INDEX engagement_workplace_idx ON private_isg.contractor_engagements(company_id,workplace_id);
CREATE INDEX context_owner_idx ON private_isg.workplace_context_versions(company_id,owner_id);
CREATE INDEX context_workplace_idx ON private_isg.workplace_context_versions(company_id,workplace_id);
CREATE INDEX assignment_owner_idx ON private_isg.employee_assignments(company_id,owner_id);
CREATE INDEX assignment_employee_idx ON private_isg.employee_assignments(company_id,employee_id);
CREATE INDEX assignment_department_idx ON private_isg.employee_assignments(company_id,workplace_id,department_id);
CREATE INDEX assignment_job_idx ON private_isg.employee_assignments(company_id,job_role_id);
CREATE INDEX assignment_employer_idx ON private_isg.employee_assignments(company_id,employer_org_id_snapshot);
CREATE INDEX directory_event_owner_idx ON private_isg.directory_events(company_id,owner_id);
ALTER TABLE private_isg.job_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.contractor_organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.contractor_engagements ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workplace_context_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.employee_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.directory_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.directory_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- Catch-up still works for old binary inserts after the code column is introduced.
CREATE FUNCTION private_isg.workplace_code_default() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN IF NEW.code IS NULL THEN NEW.code:='W-'||NEW.id::text;END IF;RETURN NEW;END $$;
CREATE TRIGGER workplace_code_default BEFORE INSERT ON private_isg.workplaces FOR EACH ROW EXECUTE FUNCTION private_isg.workplace_code_default();
CREATE FUNCTION private_isg.department_hierarchy_guard() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND ROW(NEW.company_id,NEW.owner_id,NEW.workplace_id) IS DISTINCT FROM ROW(OLD.company_id,OLD.owner_id,OLD.workplace_id) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE';END IF;
 PERFORM 1 FROM public.companies WHERE id=NEW.company_id FOR UPDATE;
 IF NEW.parent_id IS NOT NULL AND EXISTS(WITH RECURSIVE ancestors AS(
   SELECT id,parent_id,ARRAY[id] path FROM private_isg.departments WHERE id=NEW.parent_id AND company_id=NEW.company_id
   UNION ALL SELECT d.id,d.parent_id,a.path||d.id FROM private_isg.departments d JOIN ancestors a ON d.id=a.parent_id WHERE NOT d.id=ANY(a.path)
 ) SELECT 1 FROM ancestors WHERE id=NEW.id) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='HIERARCHY_CYCLE';END IF;
 IF NEW.parent_id=NEW.id THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='HIERARCHY_CYCLE';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER department_hierarchy_guard BEFORE INSERT OR UPDATE ON private_isg.departments FOR EACH ROW EXECUTE FUNCTION private_isg.department_hierarchy_guard();
CREATE FUNCTION private_isg.assignment_guard() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE person private_isg.employees;dep private_isg.departments;job private_isg.job_roles;
BEGIN
 IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'ends_before'-'effective_dates') IS DISTINCT FROM (to_jsonb(OLD)-'ends_before'-'effective_dates') THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_IMMUTABLE';END IF;
 IF TG_OP='UPDATE' AND OLD.ends_before IS NOT NULL AND(NEW.ends_before IS NULL OR NEW.ends_before>OLD.ends_before) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_EXTENSION_REQUIRES_REVIEW';END IF;
 SELECT * INTO STRICT person FROM private_isg.employees WHERE company_id=NEW.company_id AND id=NEW.employee_id FOR UPDATE;
 IF (person.hired_on IS NOT NULL AND NEW.starts_on<person.hired_on) OR(person.employment_ends_before IS NOT NULL AND(NEW.ends_before IS NULL OR NEW.ends_before>person.employment_ends_before)) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYMENT_INTERVAL_INVALID';END IF;
 IF TG_OP='INSERT' THEN
  IF person.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;
  PERFORM 1 FROM private_isg.workplaces WHERE id=NEW.workplace_id AND company_id=NEW.company_id AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_SCOPE_INVALID';END IF;
  SELECT * INTO dep FROM private_isg.departments WHERE id=NEW.department_id AND company_id=NEW.company_id AND workplace_id=NEW.workplace_id AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_SCOPE_INVALID';END IF;
  SELECT * INTO job FROM private_isg.job_roles WHERE id=NEW.job_role_id AND company_id=NEW.company_id AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_SCOPE_INVALID';END IF;
  NEW.department_name_snapshot:=dep.name;NEW.job_title_snapshot:=job.title;NEW.employer_org_id_snapshot:=person.employer_org_id;
  SELECT name INTO NEW.employer_name_snapshot FROM private_isg.contractor_organizations WHERE id=person.employer_org_id AND company_id=NEW.company_id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER assignment_guard BEFORE INSERT OR UPDATE ON private_isg.employee_assignments FOR EACH ROW EXECUTE FUNCTION private_isg.assignment_guard();
CREATE FUNCTION private_isg.personnel_history_guard() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF NEW.intake_department_id IS DISTINCT FROM OLD.intake_department_id AND EXISTS(SELECT 1 FROM private_isg.employee_assignments WHERE employee_id=OLD.id AND company_id=OLD.company_id) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_CHANGE_REQUIRED';END IF;
 IF EXISTS(SELECT 1 FROM private_isg.employee_assignments WHERE employee_id=OLD.id AND company_id=OLD.company_id AND
  ((NEW.hired_on IS NOT NULL AND starts_on<NEW.hired_on) OR(NEW.employment_ends_before IS NOT NULL AND(ends_before IS NULL OR ends_before>NEW.employment_ends_before)))) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYMENT_INTERVAL_INVALID';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER personnel_history_guard BEFORE UPDATE OF intake_department_id,hired_on,employment_ends_before ON private_isg.employees FOR EACH ROW EXECUTE FUNCTION private_isg.personnel_history_guard();
CREATE FUNCTION private_isg.context_history_guard() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF(to_jsonb(NEW)-'ends_before'-'effective_dates') IS DISTINCT FROM(to_jsonb(OLD)-'ends_before'-'effective_dates') OR
  (OLD.ends_before IS NOT NULL AND(NEW.ends_before IS NULL OR NEW.ends_before>OLD.ends_before)) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CONTEXT_IMMUTABLE';END IF;RETURN NEW;
END $$;
CREATE TRIGGER context_history_guard BEFORE UPDATE ON private_isg.workplace_context_versions FOR EACH ROW EXECUTE FUNCTION private_isg.context_history_guard();

CREATE FUNCTION private_isg.require_json_keys(body jsonb,keys text[]) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry record;day date;
BEGIN IF body IS NULL OR jsonb_typeof(body)<>'object' OR(SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(body) k) IS DISTINCT FROM(SELECT array_agg(k ORDER BY k) FROM unnest(keys) k) THEN
 RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
 FOR entry IN SELECT key,value FROM jsonb_each(body) LOOP
  IF entry.key='is_archived' THEN
   IF jsonb_typeof(entry.value)<>'boolean' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
  ELSIF jsonb_typeof(entry.value) NOT IN('string','null') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
  IF entry.key IN('starts_on','ends_before') AND entry.value<>'null'::jsonb THEN
   IF (entry.value#>>'{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
   day:=(entry.value#>>'{}')::date;
   IF day NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
  END IF;
 END LOOP;
END $$;
CREATE FUNCTION private_isg.directory_read(p_company uuid,p_kind text,p_parent uuid,p_after uuid,p_archived boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb;cursor uuid;parent_version bigint;
BEGIN
 PERFORM private_isg.require_company(p_company,false);
 IF p_kind IS NULL OR p_archived IS NULL OR p_kind NOT IN('workplaces','departments','jobs','contractors','engagements','contexts','assignments','employers') THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
 WITH candidates AS NOT MATERIALIZED(
  SELECT id,to_jsonb(w) data FROM private_isg.workplaces w WHERE p_kind='workplaces' AND company_id=p_company AND(p_archived OR NOT is_archived)
  UNION ALL SELECT id,to_jsonb(d) FROM private_isg.departments d WHERE p_kind='departments' AND company_id=p_company AND(p_parent IS NULL OR workplace_id=p_parent) AND(p_archived OR NOT is_archived)
  UNION ALL SELECT id,to_jsonb(j) FROM private_isg.job_roles j WHERE p_kind='jobs' AND company_id=p_company AND(p_archived OR NOT is_archived)
  UNION ALL SELECT id,to_jsonb(c) FROM private_isg.contractor_organizations c WHERE p_kind='contractors' AND company_id=p_company AND(p_archived OR NOT is_archived)
  UNION ALL SELECT id,to_jsonb(e)-'effective_dates' FROM private_isg.contractor_engagements e WHERE p_kind='engagements' AND company_id=p_company AND(p_parent IS NULL OR organization_id=p_parent)
  UNION ALL SELECT id,to_jsonb(c)-'effective_dates' FROM private_isg.workplace_context_versions c WHERE p_kind='contexts' AND company_id=p_company AND workplace_id=p_parent
  UNION ALL SELECT id,to_jsonb(a)-'effective_dates' FROM private_isg.employee_assignments a WHERE p_kind='assignments' AND company_id=p_company AND employee_id=p_parent
  UNION ALL SELECT id,jsonb_build_object('id',id,'company_id',company_id,'owner_id',owner_id,'employer_org_id',employer_org_id,'version',employer_version) FROM private_isg.employees WHERE p_kind='employers' AND company_id=p_company AND id=p_parent
 ),matches AS(SELECT * FROM candidates WHERE p_after IS NULL OR id>p_after ORDER BY id LIMIT 51),page AS(SELECT * FROM matches ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(data ORDER BY id),'[]'::jsonb),CASE WHEN(SELECT count(*) FROM matches)>50 THEN max(id::text)::uuid END INTO rows,cursor FROM page;
 IF p_kind='assignments' THEN SELECT assignment_version INTO parent_version FROM private_isg.employees WHERE id=p_parent AND company_id=p_company;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;
 ELSIF p_kind='contexts' THEN SELECT context_version INTO parent_version FROM private_isg.workplaces WHERE id=p_parent AND company_id=p_company;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;END IF;
 RETURN jsonb_build_object('rows',rows,'next',cursor,'parent_version',parent_version);
END $$;

CREATE FUNCTION private_isg.directory_mutate(p_company uuid,p_kind text,p_operation uuid,p_mutation uuid,p_id uuid,p_expected bigint,p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
<<directory_mutate>>
DECLARE actor uuid;entity uuid:=coalesce(p_id,gen_random_uuid());v bigint;fingerprint bytea;receipt private_isg.personnel_receipts;result jsonb;event uuid;
 name text;code text;description text;archived boolean;workplace uuid;parent uuid;organization uuid;from_date date;to_date date;previous uuid;
 person private_isg.employees;prior_assignment private_isg.employee_assignments;prior_context private_isg.workplace_context_versions;
BEGIN
 actor:=private_isg.require_company(p_company,true);
 IF p_operation IS NULL OR p_mutation IS NULL OR p_kind IS NULL OR p_expected IS NULL OR p_expected<0 OR p_expected>=9007199254740991 OR octet_length(p_body::text)>8192 THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
 fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_kind,p_operation,p_id,p_expected,p_body)::text,'UTF8'));
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-personnel:'||p_mutation::text,0));
 SELECT * INTO receipt FROM private_isg.personnel_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
 IF FOUND THEN IF receipt.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT';END IF;RETURN receipt.response;END IF;
 IF p_kind IN('workplaces','departments','jobs','contractors') THEN
  IF p_kind='workplaces' THEN PERFORM private_isg.require_json_keys(p_body,ARRAY['name','code','address','is_archived']);
  ELSIF p_kind='departments' THEN PERFORM private_isg.require_json_keys(p_body,ARRAY['name','code','workplace_id','parent_id','is_archived']);
  ELSIF p_kind='jobs' THEN PERFORM private_isg.require_json_keys(p_body,ARRAY['name','code','description','is_archived']);
  ELSE PERFORM private_isg.require_json_keys(p_body,ARRAY['name','code','relationship','is_archived']);END IF;
  name:=private_isg.text_value(p_body->>'name',200);code:=private_isg.text_value(p_body->>'code',80);
  IF jsonb_typeof(p_body->'is_archived')<>'boolean' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
  archived:=(p_body->>'is_archived')::boolean;
  IF p_id IS NULL THEN IF p_expected<>0 OR archived THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;v:=0;
  ELSE
   CASE p_kind WHEN 'workplaces' THEN SELECT version INTO v FROM private_isg.workplaces WHERE id=p_id AND company_id=p_company FOR UPDATE;
   WHEN 'departments' THEN SELECT version INTO v FROM private_isg.departments WHERE id=p_id AND company_id=p_company FOR UPDATE;
   WHEN 'jobs' THEN SELECT version INTO v FROM private_isg.job_roles WHERE id=p_id AND company_id=p_company FOR UPDATE;
   WHEN 'contractors' THEN SELECT version INTO v FROM private_isg.contractor_organizations WHERE id=p_id AND company_id=p_company FOR UPDATE;END CASE;
   IF v IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;
   IF v<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';END IF;v:=v+1;
  END IF;
  CASE p_kind
  WHEN 'workplaces' THEN
   description:=nullif(p_body->>'address','');IF description IS NOT NULL THEN description:=private_isg.text_value(description,1000);END IF;
   IF p_id IS NULL THEN INSERT INTO private_isg.workplaces(id,company_id,owner_id,code,name,address) VALUES(entity,p_company,actor,code,name,description);
   ELSE UPDATE private_isg.workplaces SET name=directory_mutate.name,code=directory_mutate.code,address=description,is_archived=archived,version=v WHERE id=entity;END IF;
  WHEN 'departments' THEN
   workplace:=(p_body->>'workplace_id')::uuid;parent:=(p_body->>'parent_id')::uuid;
   PERFORM 1 FROM private_isg.workplaces WHERE id=workplace AND company_id=p_company AND NOT is_archived FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID';END IF;
   IF parent IS NOT NULL THEN PERFORM 1 FROM private_isg.departments WHERE id=parent AND company_id=p_company AND workplace_id=workplace AND NOT is_archived FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID';END IF;END IF;
   IF p_id IS NULL THEN INSERT INTO private_isg.departments(id,company_id,owner_id,workplace_id,parent_id,code,name) VALUES(entity,p_company,actor,workplace,parent,code,name);
   ELSE UPDATE private_isg.departments SET name=directory_mutate.name,code=directory_mutate.code,parent_id=parent,workplace_id=workplace,is_archived=archived,version=v WHERE id=entity;END IF;
  WHEN 'jobs' THEN
   description:=coalesce(p_body->>'description','');IF description<>'' THEN description:=private_isg.text_value(description,2000);END IF;
   IF p_id IS NULL THEN INSERT INTO private_isg.job_roles(id,company_id,owner_id,code,title,description) VALUES(entity,p_company,actor,code,name,description);
   ELSE UPDATE private_isg.job_roles SET title=name,code=directory_mutate.code,description=directory_mutate.description,is_archived=archived,version=v WHERE id=entity;END IF;
  WHEN 'contractors' THEN
   IF p_body->>'relationship' NOT IN('subcontractor','contractor','supplier','other') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
   IF p_id IS NULL THEN INSERT INTO private_isg.contractor_organizations(id,company_id,owner_id,code,name,relationship) VALUES(entity,p_company,actor,code,name,p_body->>'relationship');
   ELSE UPDATE private_isg.contractor_organizations SET name=directory_mutate.name,code=directory_mutate.code,relationship=p_body->>'relationship',is_archived=archived,version=v WHERE id=entity;END IF;
  END CASE;
 ELSIF p_kind='employers' THEN
  PERFORM private_isg.require_json_keys(p_body,ARRAY['organization_id']);organization:=(p_body->>'organization_id')::uuid;
  SELECT * INTO person FROM private_isg.employees WHERE id=p_id AND company_id=p_company AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;
  IF person.employer_version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';END IF;
  IF organization IS NOT NULL THEN PERFORM 1 FROM private_isg.contractor_organizations WHERE id=organization AND company_id=p_company AND NOT is_archived FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYER_SCOPE_INVALID';END IF;END IF;
  v:=p_expected+1;UPDATE private_isg.employees SET employer_org_id=organization,employer_version=v WHERE id=p_id;
 ELSIF p_kind='assignments' THEN
  PERFORM private_isg.require_json_keys(p_body,ARRAY['employee_id','previous_id','workplace_id','department_id','job_role_id','starts_on','reason']);
  IF p_id IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_IMMUTABLE';END IF;
  SELECT * INTO person FROM private_isg.employees WHERE id=(p_body->>'employee_id')::uuid AND company_id=p_company AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;
  IF person.assignment_version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';END IF;
  previous:=(p_body->>'previous_id')::uuid;from_date:=(p_body->>'starts_on')::date;to_date:=person.employment_ends_before;
  IF from_date IS NULL OR NOT isfinite(from_date) OR from_date NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
  IF previous IS NOT NULL THEN SELECT * INTO prior_assignment FROM private_isg.employee_assignments WHERE id=previous AND company_id=p_company AND employee_id=person.id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_SCOPE_INVALID';END IF;
   IF from_date<=prior_assignment.starts_on OR(prior_assignment.ends_before IS NOT NULL AND from_date>=prior_assignment.ends_before) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
   to_date:=prior_assignment.ends_before;UPDATE private_isg.employee_assignments SET ends_before=from_date WHERE id=previous;END IF;
  description:=coalesce(p_body->>'reason','');IF description<>'' THEN description:=private_isg.text_value(description,500);END IF;
  INSERT INTO private_isg.employee_assignments(id,company_id,owner_id,employee_id,workplace_id,department_id,job_role_id,starts_on,ends_before,department_name_snapshot,job_title_snapshot,reason)
   VALUES(entity,p_company,actor,person.id,(p_body->>'workplace_id')::uuid,(p_body->>'department_id')::uuid,(p_body->>'job_role_id')::uuid,from_date,to_date,'','',description);
  v:=p_expected+1;UPDATE private_isg.employees SET assignment_version=v WHERE id=person.id;
 ELSIF p_kind='contexts' THEN
  PERFORM private_isg.require_json_keys(p_body,ARRAY['workplace_id','previous_id','starts_on','timezone','jurisdiction','hazard_class','industry_code','evidence_note']);
  IF p_id IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CONTEXT_IMMUTABLE';END IF;
  workplace:=(p_body->>'workplace_id')::uuid;
  SELECT context_version INTO v FROM private_isg.workplaces WHERE id=workplace AND company_id=p_company AND NOT is_archived FOR UPDATE;
  IF v IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;
  IF v<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';END IF;
  PERFORM 1 FROM pg_timezone_names tz WHERE tz.name=p_body->>'timezone';IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TIMEZONE_INVALID';END IF;
  from_date:=(p_body->>'starts_on')::date;previous:=(p_body->>'previous_id')::uuid;
  IF from_date IS NULL OR NOT isfinite(from_date) OR from_date NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
  IF previous IS NOT NULL THEN SELECT * INTO prior_context FROM private_isg.workplace_context_versions WHERE id=previous AND company_id=p_company AND workplace_id=workplace FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CONTEXT_SCOPE_INVALID';END IF;
   IF from_date<=prior_context.starts_on OR(prior_context.ends_before IS NOT NULL AND from_date>=prior_context.ends_before) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
   to_date:=prior_context.ends_before;UPDATE private_isg.workplace_context_versions SET ends_before=from_date WHERE id=previous;END IF;
  INSERT INTO private_isg.workplace_context_versions(id,company_id,owner_id,workplace_id,starts_on,ends_before,timezone,jurisdiction,hazard_class,industry_code,evidence_note)
   VALUES(entity,p_company,actor,workplace,from_date,to_date,p_body->>'timezone',private_isg.text_value(p_body->>'jurisdiction',80),p_body->>'hazard_class',nullif(p_body->>'industry_code',''),private_isg.text_value(p_body->>'evidence_note',1000));
  v:=p_expected+1;UPDATE private_isg.workplaces SET context_version=v WHERE id=workplace;
 ELSIF p_kind='engagements' THEN
  PERFORM private_isg.require_json_keys(p_body,ARRAY['organization_id','workplace_id','starts_on','ends_before','description']);
  organization:=(p_body->>'organization_id')::uuid;workplace:=(p_body->>'workplace_id')::uuid;
  from_date:=(p_body->>'starts_on')::date;to_date:=(p_body->>'ends_before')::date;
  PERFORM 1 FROM private_isg.contractor_organizations WHERE id=organization AND company_id=p_company AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYER_SCOPE_INVALID';END IF;
  PERFORM 1 FROM private_isg.workplaces WHERE id=workplace AND company_id=p_company AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;
  description:=coalesce(p_body->>'description','');IF description<>'' THEN description:=private_isg.text_value(description,1000);END IF;
  IF p_id IS NULL THEN
   IF p_expected<>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';END IF;v:=0;
   INSERT INTO private_isg.contractor_engagements(id,company_id,owner_id,organization_id,workplace_id,starts_on,ends_before,description) VALUES(entity,p_company,actor,organization,workplace,from_date,to_date,description);
  ELSE
   SELECT version INTO v FROM private_isg.contractor_engagements WHERE id=p_id AND company_id=p_company AND organization_id=organization AND workplace_id=workplace AND starts_on=from_date FOR UPDATE;
   IF v IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE';END IF;
   IF v<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';END IF;
   v:=v+1;UPDATE private_isg.contractor_engagements SET ends_before=to_date,description=directory_mutate.description,version=v WHERE id=entity;
  END IF;
 ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
 result:=jsonb_build_object('schema_version',1,'operation_id',p_operation,'entity_id',entity,'owner_id',actor,'company_id',p_company,'kind',p_kind,'version',v);
 INSERT INTO private_isg.directory_events(company_id,owner_id,operation_id,entity_kind,entity_id,version) VALUES(p_company,actor,p_operation,p_kind,entity,v) RETURNING event_id INTO event;
 INSERT INTO private_isg.directory_outbox(event_id) VALUES(event);
 INSERT INTO private_isg.personnel_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response) VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
 RETURN result;
END $$;

-- Callers must resolve a stated effective date. Legacy defaults and future contexts
-- are never substituted for an absent historical period.
CREATE FUNCTION private_isg.context_at(p_company uuid,p_workplace uuid,p_on date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE context private_isg.workplace_context_versions;
BEGIN
 PERFORM private_isg.require_company(p_company,false);
 IF p_on IS NULL OR NOT isfinite(p_on) OR p_on NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END IF;
 PERFORM 1 FROM private_isg.workplaces WHERE id=p_workplace AND company_id=p_company;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';END IF;
 SELECT * INTO context FROM private_isg.workplace_context_versions WHERE company_id=p_company AND workplace_id=p_workplace AND effective_dates @> p_on;
 IF NOT FOUND THEN RETURN jsonb_build_object('schema_version',1,'status','needs_review','effective_on',p_on,'context',NULL);END IF;
 RETURN jsonb_build_object('schema_version',1,'status','resolved','effective_on',p_on,'context',to_jsonb(context)-'effective_dates');
END $$;
CREATE FUNCTION public.isg_context_at_v1(p_company uuid,p_workplace uuid,p_on date) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.context_at(p_company,p_workplace,p_on) $$;
CREATE FUNCTION public.isg_directory_read_v1(p_company uuid,p_kind text,p_parent uuid,p_after uuid,p_archived boolean) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.directory_read(p_company,p_kind,p_parent,p_after,p_archived) $$;
CREATE FUNCTION public.isg_directory_mutate_v1(p_company uuid,p_kind text,p_operation uuid,p_mutation uuid,p_id uuid,p_expected bigint,p_body jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.directory_mutate(p_company,p_kind,p_operation,p_mutation,p_id,p_expected,p_body) $$;
REVOKE ALL ON FUNCTION private_isg.context_at(uuid,uuid,date),public.isg_context_at_v1(uuid,uuid,date),private_isg.workplace_code_default(),private_isg.department_hierarchy_guard(),private_isg.assignment_guard(),private_isg.personnel_history_guard(),private_isg.context_history_guard(),private_isg.require_json_keys(jsonb,text[]),
 private_isg.directory_read(uuid,text,uuid,uuid,boolean),private_isg.directory_mutate(uuid,text,uuid,uuid,uuid,bigint,jsonb),
 public.isg_directory_read_v1(uuid,text,uuid,uuid,boolean),public.isg_directory_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.context_at(uuid,uuid,date),public.isg_context_at_v1(uuid,uuid,date),private_isg.directory_read(uuid,text,uuid,uuid,boolean),private_isg.directory_mutate(uuid,text,uuid,uuid,uuid,bigint,jsonb),
 public.isg_directory_read_v1(uuid,text,uuid,uuid,boolean),public.isg_directory_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';


-- Source: supabase/migrations/20260913084736_isg_workspace_availability.sql
-- Presentation availability only. Every read/mutation still verifies its own authority.

SET LOCAL lock_timeout='1s';
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


-- Source: supabase/migrations/20260913092642_isg_personnel_reactivation.sql
-- Explicit reactivation preserves IDs, dates, assignments and historical snapshots.

SET LOCAL lock_timeout='1s';
ALTER TABLE private_isg.personnel_audit DROP CONSTRAINT personnel_audit_action_check;
ALTER TABLE private_isg.personnel_audit ADD CONSTRAINT personnel_audit_action_check CHECK(action IN ('create','edit','archive','restore'));
ALTER TABLE private_isg.personnel_outbox DROP CONSTRAINT personnel_outbox_event_type_check;
ALTER TABLE private_isg.personnel_outbox ADD CONSTRAINT personnel_outbox_event_type_check CHECK(event_type IN ('employee.created','employee.updated','employee.archived','employee.restored'));
CREATE OR REPLACE FUNCTION private_isg.mutate_personnel(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,
  p_employee uuid,p_expected bigint,p_name text,p_change_department boolean,p_department uuid,p_department_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; person private_isg.employees; receipt private_isg.personnel_receipts;
  fullname text; depname text; depkey text; department uuid; workplace uuid; matches integer;
  fingerprint bytea; result jsonb; employee uuid; version bigint; event uuid:=gen_random_uuid();
BEGIN
  actor:=private_isg.require_company(p_company,true);
  IF p_operation IS NULL OR p_mutation IS NULL OR p_action IS NULL OR p_action NOT IN ('create','edit','archive','restore') OR
    p_expected IS NULL OR p_expected<0 OR p_expected>=9007199254740991 OR p_change_department IS NULL OR
    (p_action='create' AND (p_employee IS NOT NULL OR p_expected<>0 OR NOT p_change_department)) OR
    (p_action<>'create' AND p_employee IS NULL) OR
    (p_action IN ('archive','restore') AND (p_name IS NOT NULL OR p_change_department)) OR
    (NOT p_change_department AND (p_department IS NOT NULL OR p_department_name IS NOT NULL)) OR
    (p_department IS NOT NULL AND p_department_name IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_action NOT IN ('archive','restore') THEN fullname:=private_isg.text_value(p_name,200); END IF;
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
    SELECT * INTO person FROM private_isg.employees WHERE company_id=p_company AND id=p_employee AND (CASE WHEN p_action='restore' THEN is_archived ELSE NOT is_archived END) FOR UPDATE;
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
    UPDATE private_isg.employees SET full_name=CASE WHEN p_action IN ('archive','restore') THEN full_name ELSE fullname END,
      intake_department_id=department,record_version=version,is_archived=(p_action='archive') WHERE id=employee;
  END IF;
  result:=jsonb_build_object('schema_version',1,'operation_id',p_operation,'employee_id',employee,'owner_id',actor,'company_id',p_company,'version',version,'is_archived',p_action='archive');
  INSERT INTO private_isg.personnel_audit(event_id,company_id,actor_id,employee_id,version,operation_id,action)
    VALUES(event,p_company,actor,employee,version,p_operation,p_action);
  INSERT INTO private_isg.personnel_outbox(event_id,event_type)
    VALUES(event,CASE p_action WHEN 'create' THEN 'employee.created' WHEN 'edit' THEN 'employee.updated' WHEN 'restore' THEN 'employee.restored' ELSE 'employee.archived' END);
  INSERT INTO private_isg.personnel_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result;
END $$;
NOTIFY pgrst,'reload schema';


-- Source: supabase/migrations/20260913191226_isg_p05_readonly_pilot.sql
-- Preparation only. Empty roster + rollout OFF. Not a deployment authorization.
-- Requires the four P05 candidates through 20260913092642.

SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';

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


-- Source: supabase/migrations/20260913193231_isg_p05_account_pilot_creation.sql
-- Local candidate only. No real account is seeded and no rollout is opened.

SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';
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




SET LOCAL search_path=pg_catalog,public;
DO $postflight$ BEGIN
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND rowsecurity) <> 18 OR
     (SELECT count(*) FROM pg_tables WHERE schemaname='private_isg') <> 18 OR
     EXISTS(SELECT 1 FROM private_isg.p05_pilot_accounts) OR
     EXISTS(SELECT 1 FROM private_isg.p05_pilot_grants) OR
     EXISTS(SELECT 1 FROM private_isg.p05_pilot_company_origins) OR
     EXISTS(SELECT 1 FROM private_isg.workplaces) OR
     EXISTS(SELECT 1 FROM private_isg.rollout WHERE read_enabled OR write_enabled) OR
     EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.companies'::regclass AND tgname='companies_isg_default') OR
     NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.companies'::regclass AND tgname='companies_enforce_write_rules' AND tgenabled='O') OR
     EXISTS(SELECT 1 FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('PUBLIC','anon','authenticated','service_role')) THEN
     RAISE EXCEPTION 'PILOT_RELEASE_POSTFLIGHT_FAILED'; END IF;
  IF md5(pg_get_functiondef('private.user_plan_tier(uuid)'::regprocedure)||pg_get_functiondef('private.company_limit_for_user(uuid)'::regprocedure)||pg_get_functiondef('private.enforce_company_write_rules()'::regprocedure)) <> 'e61b8d817d8917fdb99d2f44364b8414' THEN
    RAISE EXCEPTION 'PILOT_RELEASE_LEGACY_HELPER_CHANGED'; END IF;
END $postflight$;
NOTIFY pgrst,'reload schema';
