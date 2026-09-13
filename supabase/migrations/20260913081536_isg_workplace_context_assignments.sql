-- P05 domain expansion. Additive and gated by private_isg.rollout; no live activation.
BEGIN;
SET LOCAL lock_timeout='5s';
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
COMMIT;
