-- D1 workspace personnel/workplace/department slice. NOT DEPLOYED and default OFF.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE TABLE private_isg.workspace_domain_rollout(
  domain text PRIMARY KEY CHECK(domain IN ('personnel','training','risk_nonconformity','emergency_ppe',
    'equipment','operations','files','analysis_exports','tracking_notifications')),
  read_enabled boolean NOT NULL DEFAULT false,
  write_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(NOT write_enabled OR read_enabled)
);
INSERT INTO private_isg.workspace_domain_rollout(domain) VALUES
  ('personnel'),('training'),('risk_nonconformity'),('emergency_ppe'),('equipment'),
  ('operations'),('files'),('analysis_exports'),('tracking_notifications');
ALTER TABLE private_isg.workspace_domain_rollout ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_domain_rollout FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE private_isg.workplaces ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.workplaces ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.workplaces ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.workplaces ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.workplaces ADD CONSTRAINT workplaces_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.workplaces ADD CONSTRAINT workplaces_workspace_identity_unique
  UNIQUE(workspace_id,company_id,id);

ALTER TABLE private_isg.departments ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.departments ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.departments ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.departments ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.departments ADD CONSTRAINT departments_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.departments ADD CONSTRAINT departments_workspace_workplace_fk
  FOREIGN KEY(workspace_id,company_id,workplace_id)
  REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.departments ADD CONSTRAINT departments_workspace_identity_unique
  UNIQUE(workspace_id,company_id,id);

ALTER TABLE private_isg.employees ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.employees ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.employees ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.employees ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.employees ADD CONSTRAINT employees_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.employees ADD CONSTRAINT employees_workspace_department_fk
  FOREIGN KEY(workspace_id,company_id,intake_department_id)
  REFERENCES private_isg.departments(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.employees ADD CONSTRAINT employees_workspace_identity_unique
  UNIQUE(workspace_id,company_id,id);

UPDATE private_isg.workplaces w SET workspace_id=c.workspace_id
  FROM public.companies c WHERE c.id=w.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.departments d SET workspace_id=c.workspace_id
  FROM public.companies c WHERE c.id=d.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.employees e SET workspace_id=c.workspace_id
  FROM public.companies c WHERE c.id=e.company_id AND c.workspace_id IS NOT NULL;

CREATE INDEX workplaces_workspace_page ON private_isg.workplaces(workspace_id,company_id,is_archived,id);
CREATE INDEX departments_workspace_page ON private_isg.departments(workspace_id,company_id,is_archived,id);
CREATE INDEX employees_workspace_page ON private_isg.employees(workspace_id,company_id,is_archived,id);

CREATE FUNCTION private_isg.workspace_domain_gate(p_domain text,p_write boolean) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF p_domain IS NULL OR p_write IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.workspace_domain_rollout
    WHERE domain=p_domain AND read_enabled AND (NOT p_write OR write_enabled);
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;

-- Existing personal commands keep their original RLS/FK/validation contract.
-- Never let this compatibility path accept an OSGB company or move an OSGB row.
CREATE FUNCTION private_isg.workspace_is_legacy_company_write(p_company uuid,p_new_workspace uuid,p_old_workspace uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS(SELECT 1 FROM public.companies c WHERE c.id=p_company AND c.user_id IS NOT NULL
    AND (p_new_workspace IS NULL OR p_new_workspace=c.workspace_id)
    AND (p_old_workspace IS NULL OR p_old_workspace=c.workspace_id))
$$;
REVOKE ALL ON FUNCTION private_isg.workspace_is_legacy_company_write(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_personnel_scope_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company public.companies; workspace private_isg.workspaces;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='COMPANY_NOT_FOUND'; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF NEW.workspace_id IS DISTINCT FROM company.workspace_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_SCOPE_CONFLICT'; END IF;
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.kind='osgb' AND NEW.owner_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_FORBIDDEN'; END IF;
  IF workspace.kind='personal' AND NEW.owner_id IS DISTINCT FROM company.user_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_MISMATCH'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.owner_id,NEW.created_by_user_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.owner_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workplaces_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.workplaces
  FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_personnel_scope_invariant();
CREATE TRIGGER departments_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.departments
  FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_personnel_scope_invariant();
CREATE TRIGGER employees_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.employees
  FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_personnel_scope_invariant();

CREATE FUNCTION private_isg.workspace_personnel_initialize(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  company private_isg.workspace_companies; workplace private_isg.workplaces;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',true);
  member:=private_isg.workspace_require_company(p_workspace,p_company,true);
  IF member.role='expert' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO company FROM private_isg.workspace_companies
    WHERE workspace_id=p_workspace AND id=p_company AND status='active' FOR SHARE;
  SELECT * INTO workplace FROM private_isg.workplaces
    WHERE workspace_id=p_workspace AND company_id=p_company AND legacy_company_id=p_company FOR UPDATE;
  IF workplace.id IS NULL THEN
    INSERT INTO private_isg.workplaces(workspace_id,company_id,owner_id,name,hazard_class,needs_review,
      is_archived,legacy_company_id,code,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,NULL,company.name,company.hazard_class,false,false,p_company,'MERKEZ',actor,actor)
      RETURNING * INTO workplace;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'workplace_id',workplace.id,'name',workplace.name,'code',workplace.code,'version',workplace.version);
END $$;

CREATE FUNCTION private_isg.workspace_personnel_read(p_workspace uuid,p_company uuid,p_kind text,
  p_query text,p_archived boolean,p_after uuid,p_id uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; rows jsonb; next_id uuid; needle text;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',false);
  member:=private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_kind NOT IN ('workplaces','departments','employees','employee_detail') OR p_query IS NULL OR
     octet_length(p_query)>200 OR p_archived IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR
     (p_kind='employee_detail')<>(p_id IS NOT NULL) OR
     (p_kind='employee_detail' AND (p_query<>'' OR p_after IS NOT NULL OR p_archived)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  needle:=lower(btrim(p_query));
  IF p_kind='employee_detail' THEN
    SELECT jsonb_build_object('employee_id',e.id,'company_id',e.company_id,'code',e.employee_code,
      'name',e.full_name,'department_id',e.intake_department_id,'hired_on',e.hired_on,
      'employment_ends_before',e.employment_ends_before,'is_archived',e.is_archived,
      'version',e.record_version) INTO rows
      FROM private_isg.employees e WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND e.id=p_id;
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'row',rows);
  ELSIF p_kind='employees' THEN
    WITH visible AS (SELECT e.* FROM private_isg.employees e WHERE e.workspace_id=p_workspace AND e.company_id=p_company
      AND (p_archived OR NOT e.is_archived) AND (p_after IS NULL OR e.id>p_after)
      AND strpos(lower(e.full_name),needle)>0 ORDER BY e.id LIMIT p_limit+1),
    page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('employee_id',id,'code',employee_code,'name',full_name,
      'department_id',intake_department_id,'is_archived',is_archived,'version',record_version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSIF p_kind='departments' THEN
    WITH visible AS (SELECT d.* FROM private_isg.departments d WHERE d.workspace_id=p_workspace AND d.company_id=p_company
      AND (p_archived OR NOT d.is_archived) AND (p_after IS NULL OR d.id>p_after)
      AND strpos(lower(d.name),needle)>0 ORDER BY d.id LIMIT p_limit+1),
    page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('department_id',id,'workplace_id',workplace_id,'code',code,
      'name',name,'is_archived',is_archived,'version',version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSE
    WITH visible AS (SELECT w.* FROM private_isg.workplaces w WHERE w.workspace_id=p_workspace AND w.company_id=p_company
      AND (p_archived OR NOT w.is_archived) AND (p_after IS NULL OR w.id>p_after)
      AND strpos(lower(w.name),needle)>0 ORDER BY w.id LIMIT p_limit+1),
    page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('workplace_id',id,'code',code,'name',name,
      'hazard_class',hazard_class,'is_archived',is_archived,'version',version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'kind',p_kind,'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_directory_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_entity text,p_action text,p_id uuid,p_expected bigint,p_workplace uuid,p_code text,p_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships; clean_code text; clean_name text;
  fingerprint bytea; replay jsonb; before_state jsonb; result jsonb; entity_id uuid; version_ bigint;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',true);
  member:=private_isg.workspace_require_company(p_workspace,p_company,true);
  IF member.role='expert' OR p_entity NOT IN ('workplace','department') OR p_action NOT IN ('create','edit','archive') OR
     p_expected IS NULL OR p_expected<0 OR (p_action='create')<>(p_id IS NULL) OR
     (p_action='create' AND p_expected<>0) OR (p_entity='workplace' AND p_workplace IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_action<>'archive' THEN clean_code:=private_isg.workspace_text(p_code,40); clean_name:=private_isg.workspace_text(p_name,200); END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_entity,p_action,p_id,p_expected,
    p_workplace,clean_code,clean_name)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,p_entity||'.'||p_action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  IF p_entity='workplace' THEN
    IF p_action='create' THEN
      INSERT INTO private_isg.workplaces(workspace_id,company_id,owner_id,name,hazard_class,needs_review,
        is_archived,code,created_by_user_id,updated_by_user_id)
        SELECT p_workspace,p_company,NULL,clean_name,c.hazard_class,false,false,clean_code,actor,actor
        FROM private_isg.workspace_companies c WHERE c.workspace_id=p_workspace AND c.id=p_company
        RETURNING id,version INTO entity_id,version_;
    ELSE
      SELECT jsonb_build_object('name',name,'code',code,'version',version) INTO before_state
        FROM private_isg.workplaces WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_id FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF (before_state->>'version')::bigint<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      UPDATE private_isg.workplaces SET name=CASE WHEN p_action='edit' THEN clean_name ELSE name END,
        code=CASE WHEN p_action='edit' THEN clean_code ELSE code END,is_archived=(p_action='archive'),
        version=version+1,updated_by_user_id=actor WHERE id=p_id RETURNING id,version INTO entity_id,version_;
    END IF;
  ELSE
    IF p_action='create' THEN
      IF NOT EXISTS(SELECT 1 FROM private_isg.workplaces WHERE workspace_id=p_workspace AND company_id=p_company
        AND id=p_workplace AND NOT is_archived) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      INSERT INTO private_isg.departments(workspace_id,company_id,owner_id,workplace_id,code,name,
        created_by_user_id,updated_by_user_id)
        VALUES(p_workspace,p_company,NULL,p_workplace,clean_code,clean_name,actor,actor)
        RETURNING id,version INTO entity_id,version_;
    ELSE
      SELECT jsonb_build_object('name',name,'code',code,'workplace_id',workplace_id,'version',version) INTO before_state
        FROM private_isg.departments WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_id FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF (before_state->>'version')::bigint<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      IF p_action='edit' AND (p_workplace IS NULL OR NOT EXISTS(SELECT 1 FROM private_isg.workplaces
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_workplace AND NOT is_archived)) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      UPDATE private_isg.departments SET workplace_id=CASE WHEN p_action='edit' THEN p_workplace ELSE workplace_id END,
        name=CASE WHEN p_action='edit' THEN clean_name ELSE name END,code=CASE WHEN p_action='edit' THEN clean_code ELSE code END,
        is_archived=(p_action='archive'),version=version+1,updated_by_user_id=actor
        WHERE id=p_id RETURNING id,version INTO entity_id,version_;
    END IF;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'entity',p_entity,'entity_id',entity_id,'version',version_,'action',p_action);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,p_entity||'.'||p_action,fingerprint,p_workspace,
    p_entity,entity_id,version_,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_employee_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_action text,p_employee uuid,p_expected bigint,p_code text,p_name text,p_department uuid,
  p_hired_on date,p_ends_before date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships; clean_code text; clean_name text;
  fingerprint bytea; replay jsonb; employee private_isg.employees; before_state jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',true);
  member:=private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_action NOT IN ('create','edit','archive') OR p_expected IS NULL OR p_expected<0 OR
     (p_action='create')<>(p_employee IS NULL) OR (p_action='create' AND p_expected<>0) OR
     (p_hired_on IS NOT NULL AND p_ends_before IS NOT NULL AND p_hired_on>=p_ends_before) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_action<>'archive' THEN clean_code:=private_isg.workspace_text(p_code,80); clean_name:=private_isg.workspace_text(p_name,200); END IF;
  IF p_action<>'archive' AND p_department IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.departments
    WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_department AND NOT is_archived) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_action,p_employee,p_expected,
    clean_code,clean_name,p_department,p_hired_on,p_ends_before)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'employee.'||p_action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  IF p_action='create' THEN
    INSERT INTO private_isg.employees(workspace_id,company_id,owner_id,employee_code,full_name,
      intake_department_id,hired_on,employment_ends_before,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,NULL,clean_code,clean_name,p_department,p_hired_on,p_ends_before,actor,actor)
      RETURNING * INTO employee;
  ELSE
    SELECT * INTO employee FROM private_isg.employees
      WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_employee FOR UPDATE;
    IF employee.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF employee.record_version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    before_state:=jsonb_build_object('code',employee.employee_code,'name',employee.full_name,
      'department_id',employee.intake_department_id,'is_archived',employee.is_archived,'version',employee.record_version);
    UPDATE private_isg.employees SET employee_code=CASE WHEN p_action='edit' THEN clean_code ELSE employee_code END,
      full_name=CASE WHEN p_action='edit' THEN clean_name ELSE full_name END,
      intake_department_id=CASE WHEN p_action='edit' THEN p_department ELSE intake_department_id END,
      hired_on=CASE WHEN p_action='edit' THEN p_hired_on ELSE hired_on END,
      employment_ends_before=CASE WHEN p_action='edit' THEN p_ends_before ELSE employment_ends_before END,
      is_archived=(p_action='archive'),record_version=record_version+1,updated_by_user_id=actor
      WHERE id=employee.id RETURNING * INTO employee;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'employee_id',employee.id,'code',employee.employee_code,'name',employee.full_name,
    'department_id',employee.intake_department_id,'is_archived',employee.is_archived,'version',employee.record_version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'employee.'||p_action,fingerprint,p_workspace,
    'employee',employee.id,employee.record_version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_personnel_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',false);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  IF p_company IS NOT NULL THEN PERFORM private_isg.workspace_require_company(p_workspace,p_company,false); END IF;
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'measured',true,
    'workplaces',jsonb_build_object('active',count(DISTINCT w.id) FILTER(WHERE NOT w.is_archived),
      'archived',count(DISTINCT w.id) FILTER(WHERE w.is_archived)),
    'departments',jsonb_build_object('active',count(DISTINCT d.id) FILTER(WHERE NOT d.is_archived),
      'archived',count(DISTINCT d.id) FILTER(WHERE d.is_archived)),
    'employees',jsonb_build_object('active',count(DISTINCT e.id) FILTER(WHERE NOT e.is_archived),
      'archived',count(DISTINCT e.id) FILTER(WHERE e.is_archived))) INTO result
  FROM private_isg.workspace_companies c
  LEFT JOIN private_isg.workplaces w ON w.workspace_id=c.workspace_id AND w.company_id=c.id
  LEFT JOIN private_isg.departments d ON d.workspace_id=c.workspace_id AND d.company_id=c.id
  LEFT JOIN private_isg.employees e ON e.workspace_id=c.workspace_id AND e.company_id=c.id
  WHERE c.workspace_id=p_workspace AND c.status='active' AND (p_company IS NULL OR c.id=p_company)
    AND (member.role IN ('owner','admin') OR EXISTS(SELECT 1 FROM private_isg.company_assignments a
      WHERE a.workspace_id=p_workspace AND a.company_id=c.id AND a.membership_id=member.id
        AND a.starts_at<=clock_timestamp() AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp())));
  RETURN result;
END $$;

CREATE FUNCTION public.isg_workspace_personnel_initialize_v1(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_personnel_initialize(p_workspace,p_company) $$;
CREATE FUNCTION public.isg_workspace_personnel_read_v1(p_workspace uuid,p_company uuid,p_kind text,
  p_query text,p_archived boolean,p_after uuid,p_id uuid,p_limit integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_personnel_read(
  p_workspace,p_company,p_kind,p_query,p_archived,p_after,p_id,p_limit) $$;
CREATE FUNCTION public.isg_workspace_directory_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_entity text,p_action text,p_id uuid,p_expected bigint,p_workplace uuid,p_code text,p_name text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_directory_mutate(
  p_mutation,p_workspace,p_company,p_entity,p_action,p_id,p_expected,p_workplace,p_code,p_name) $$;
CREATE FUNCTION public.isg_workspace_employee_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_action text,p_employee uuid,p_expected bigint,p_code text,p_name text,p_department uuid,
  p_hired_on date,p_ends_before date) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_employee_mutate(
  p_mutation,p_workspace,p_company,p_action,p_employee,p_expected,p_code,p_name,p_department,p_hired_on,p_ends_before) $$;
CREATE FUNCTION public.isg_workspace_personnel_metrics_v1(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_personnel_metrics(p_workspace,p_company) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_domain_gate(text,boolean),
  private_isg.workspace_personnel_scope_invariant(),private_isg.workspace_personnel_initialize(uuid,uuid),
  private_isg.workspace_personnel_read(uuid,uuid,text,text,boolean,uuid,uuid,integer),
  private_isg.workspace_directory_mutate(uuid,uuid,uuid,text,text,uuid,bigint,uuid,text,text),
  private_isg.workspace_employee_mutate(uuid,uuid,uuid,text,uuid,bigint,text,text,uuid,date,date),
  private_isg.workspace_personnel_metrics(uuid,uuid),
  public.isg_workspace_personnel_initialize_v1(uuid,uuid),
  public.isg_workspace_personnel_read_v1(uuid,uuid,text,text,boolean,uuid,uuid,integer),
  public.isg_workspace_directory_mutate_v1(uuid,uuid,uuid,text,text,uuid,bigint,uuid,text,text),
  public.isg_workspace_employee_mutate_v1(uuid,uuid,uuid,text,uuid,bigint,text,text,uuid,date,date),
  public.isg_workspace_personnel_metrics_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_personnel_initialize(uuid,uuid),
  private_isg.workspace_personnel_read(uuid,uuid,text,text,boolean,uuid,uuid,integer),
  private_isg.workspace_directory_mutate(uuid,uuid,uuid,text,text,uuid,bigint,uuid,text,text),
  private_isg.workspace_employee_mutate(uuid,uuid,uuid,text,uuid,bigint,text,text,uuid,date,date),
  private_isg.workspace_personnel_metrics(uuid,uuid),
  public.isg_workspace_personnel_initialize_v1(uuid,uuid),
  public.isg_workspace_personnel_read_v1(uuid,uuid,text,text,boolean,uuid,uuid,integer),
  public.isg_workspace_directory_mutate_v1(uuid,uuid,uuid,text,text,uuid,bigint,uuid,text,text),
  public.isg_workspace_employee_mutate_v1(uuid,uuid,uuid,text,uuid,bigint,text,text,uuid,date,date),
  public.isg_workspace_personnel_metrics_v1(uuid,uuid)
  TO authenticated;
NOTIFY pgrst,'reload schema';
