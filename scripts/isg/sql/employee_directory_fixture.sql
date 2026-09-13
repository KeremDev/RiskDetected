-- P05 scoped directory/edit/archive candidate, after employee_intake_fixture.sql.
BEGIN;
SET LOCAL ROLE isg_workplace_owner;
ALTER TABLE isg_workplace_fixture.employees ADD COLUMN record_version bigint NOT NULL DEFAULT 0 CHECK(record_version BETWEEN 0 AND 9007199254740991);
CREATE INDEX employee_directory_page ON isg_workplace_fixture.employees(company_id,is_archived,id);
CREATE INDEX department_directory_page ON isg_workplace_fixture.departments(company_id,is_archived,id);
CREATE TABLE isg_workplace_fixture.employee_edit_receipts(actor_id uuid NOT NULL,mutation_id uuid NOT NULL,payload jsonb NOT NULL,response jsonb NOT NULL,PRIMARY KEY(actor_id,mutation_id));
CREATE TABLE isg_workplace_fixture.employee_edit_audit(employee_id uuid NOT NULL REFERENCES isg_workplace_fixture.employees(id),version bigint NOT NULL,actor_id uuid NOT NULL,mutation_id uuid NOT NULL,action text NOT NULL CHECK(action IN ('edit','archive')),PRIMARY KEY(employee_id,version));
CREATE TABLE isg_workplace_fixture.employee_edit_outbox(employee_id uuid NOT NULL REFERENCES isg_workplace_fixture.employees(id),version bigint NOT NULL,event_type text NOT NULL CHECK(event_type IN ('employee.updated','employee.archived')),PRIMARY KEY(employee_id,version));
ALTER TABLE isg_workplace_fixture.employee_edit_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.employee_edit_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.employee_edit_outbox ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION isg_workplace_fixture.require_personnel_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid;
BEGIN
  actor:=nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
  IF p_write THEN
    PERFORM 1 FROM isg_workplace_fixture.personnel_write_access WHERE actor_id=actor AND enabled FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    PERFORM 1 FROM isg_workplace_fixture.legacy_companies WHERE id=p_company AND owner_id=actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM isg_workplace_fixture.legacy_companies WHERE id=p_company AND owner_id=actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $$;

-- The historical assignment active on p_on wins over the optional intake preference.
-- A future assignment cannot prematurely change today's department label.
CREATE FUNCTION isg_workplace_fixture.employee_row(p_company uuid,p_employee uuid,p_on date) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('id',e.id,'owner_id',e.owner_id,'company_id',e.company_id,'name',e.full_name,
    'department_id',CASE WHEN a.id IS NOT NULL THEN a.department_id ELSE e.intake_department_id END,
    'department_name',CASE WHEN a.id IS NOT NULL THEN a.department_name_snapshot ELSE d.name END,
    'version',e.record_version,'is_archived',e.is_archived)
  FROM isg_workplace_fixture.employees e
  LEFT JOIN LATERAL (SELECT x.id,x.department_id,x.department_name_snapshot FROM isg_workplace_fixture.employee_assignments x
    WHERE x.company_id=e.company_id AND x.employee_id=e.id AND x.effective_dates @> p_on LIMIT 1) a ON true
  LEFT JOIN isg_workplace_fixture.departments d ON d.company_id=e.company_id AND d.id=e.intake_department_id
  WHERE e.company_id=p_company AND e.id=p_employee
$$;
CREATE FUNCTION isg_workplace_fixture.read_personnel(p_company uuid,p_kind text,p_query text,p_archived boolean,p_after uuid,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE result jsonb; rows jsonb; cursor uuid; today date := (transaction_timestamp() AT TIME ZONE 'Europe/Istanbul')::date; needle text;
BEGIN
  PERFORM isg_workplace_fixture.require_personnel_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('employees','departments','detail') OR p_query IS NULL OR octet_length(p_query)>200 OR p_archived IS NULL OR
     (p_kind='detail' AND (p_id IS NULL OR p_after IS NOT NULL OR p_query<>'' OR p_archived)) OR (p_kind<>'detail' AND p_id IS NOT NULL) OR (p_kind='departments' AND p_archived) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  IF p_kind='detail' THEN
    result:=isg_workplace_fixture.employee_row(p_company,p_id,today);
    IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN result;
  END IF;
  needle:=isg_workplace_fixture.department_name_key(p_query);
  IF p_kind='employees' THEN
    WITH matches AS MATERIALIZED (
      SELECT e.id FROM isg_workplace_fixture.employees e WHERE e.company_id=p_company AND (p_archived OR NOT e.is_archived)
        AND (p_after IS NULL OR e.id>p_after) AND strpos(isg_workplace_fixture.department_name_key(e.full_name),needle)>0 ORDER BY e.id LIMIT 51
    ), page AS (SELECT id FROM matches ORDER BY id LIMIT 50)
    SELECT coalesce(jsonb_agg(isg_workplace_fixture.employee_row(p_company,id,today) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM matches)>50 THEN max(id::text)::uuid END INTO rows,cursor FROM page;
  ELSE
    WITH matches AS MATERIALIZED (
      SELECT d.* FROM isg_workplace_fixture.departments d JOIN isg_workplace_fixture.workplaces w ON w.company_id=d.company_id AND w.id=d.workplace_id
      WHERE d.company_id=p_company AND NOT d.is_archived AND NOT w.is_archived AND (p_after IS NULL OR d.id>p_after)
        AND strpos(isg_workplace_fixture.department_name_key(d.name),needle)>0 ORDER BY d.id LIMIT 51
    ), page AS (SELECT * FROM matches ORDER BY id LIMIT 50)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'owner_id',owner_id,'company_id',company_id,'name',name) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM matches)>50 THEN max(id::text)::uuid END INTO rows,cursor FROM page;
  END IF;
  RETURN jsonb_build_object('rows',rows,'next',cursor);
END $$;

CREATE FUNCTION isg_workplace_fixture.edit_employee(p_operation uuid,p_mutation uuid,p_company uuid,p_employee uuid,p_expected bigint,p_action text,p_name text,p_change_department boolean,p_department uuid,p_department_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid; employee isg_workplace_fixture.employees; receipt isg_workplace_fixture.employee_edit_receipts;
  payload jsonb; result jsonb; department uuid; name text; depname text; namekey text; matches integer; workplace uuid;
BEGIN
  actor:=isg_workplace_fixture.require_personnel_company(p_company,true);
  IF p_operation IS NULL OR p_mutation IS NULL OR p_employee IS NULL OR p_expected IS NULL OR p_expected<0 OR p_expected>=9007199254740991 OR p_change_department IS NULL OR p_action IS NULL OR p_action NOT IN ('edit','archive') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  name:=isg_workplace_fixture.intake_text(p_name);depname:=isg_workplace_fixture.intake_text(p_department_name);
  IF p_action='edit' AND (btrim(name,U&'\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')='' OR
    btrim(depname,U&'\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')='') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_action='edit' AND (name IS NULL OR name='' OR octet_length(name)>200 OR octet_length(p_name)>4096 OR name ~ '[[:cntrl:]]' OR name ~ U&'[\200B\FEFF]' OR
    (p_department IS NOT NULL AND p_department_name IS NOT NULL) OR
    (p_department_name IS NOT NULL AND (depname='' OR octet_length(depname)>120 OR octet_length(p_department_name)>4096 OR depname ~ '[[:cntrl:]]' OR depname ~ U&'[\200B\FEFF]'))) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF (p_action='archive' AND (p_name IS NOT NULL OR p_change_department)) OR (NOT p_change_department AND (p_department IS NOT NULL OR p_department_name IS NOT NULL)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  namekey:=isg_workplace_fixture.department_name_key(depname);
  payload:=jsonb_build_object('operation_id',p_operation,'company_id',p_company,'employee_id',p_employee,'expected_version',p_expected,'action',p_action,'name',name,'change_department',p_change_department,'department_id',p_department,'department_name_key',namekey);
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':employee-edit:'||p_mutation::text,0));
  SELECT * INTO employee FROM isg_workplace_fixture.employees WHERE company_id=p_company AND id=p_employee FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO receipt FROM isg_workplace_fixture.employee_edit_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF receipt.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    IF employee.is_archived AND p_action<>'archive' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN receipt.response;
  END IF;
  IF employee.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF employee.record_version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  IF p_action='edit' THEN
    -- Intake preference edits must not silently rewrite a dated assignment.
    IF p_change_department AND EXISTS(SELECT 1 FROM isg_workplace_fixture.employee_assignments WHERE company_id=p_company AND employee_id=p_employee) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_CHANGE_REQUIRED'; END IF;
    department:=employee.intake_department_id;
    IF p_change_department THEN
    department:=p_department;
    IF p_department_name IS NOT NULL THEN
      SELECT count(*),min(d.id::text)::uuid INTO matches,department FROM isg_workplace_fixture.departments d WHERE d.company_id=p_company AND NOT d.is_archived AND isg_workplace_fixture.department_name_key(d.name)=namekey;
      IF matches>1 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SELECTION_REQUIRED'; END IF;
      IF matches=0 THEN
        workplace:=isg_workplace_fixture.ensure_default(p_company);
        department:=gen_random_uuid();
        INSERT INTO isg_workplace_fixture.departments(id,company_id,owner_id,workplace_id,code,name) VALUES(department,p_company,actor,workplace,'D-'||department::text,depname);
      END IF;
    END IF;
    IF department IS NOT NULL THEN
      SELECT workplace_id INTO workplace FROM isg_workplace_fixture.departments WHERE id=department AND company_id=p_company AND NOT is_archived FOR SHARE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID'; END IF;
      PERFORM 1 FROM isg_workplace_fixture.workplaces WHERE id=workplace AND company_id=p_company AND NOT is_archived FOR SHARE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID'; END IF;
    END IF;
    END IF;
    UPDATE isg_workplace_fixture.employees SET full_name=name,intake_department_id=department,record_version=record_version+1 WHERE id=p_employee;
  ELSE
    UPDATE isg_workplace_fixture.employees SET is_archived=true,record_version=record_version+1 WHERE id=p_employee;
  END IF;
  result:=jsonb_build_object('operation_id',p_operation,'employee_id',p_employee,'version',p_expected+1);
  INSERT INTO isg_workplace_fixture.employee_edit_audit VALUES(p_employee,p_expected+1,actor,p_mutation,p_action);
  INSERT INTO isg_workplace_fixture.employee_edit_outbox VALUES(p_employee,p_expected+1,CASE WHEN p_action='archive' THEN 'employee.archived' ELSE 'employee.updated' END);
  INSERT INTO isg_workplace_fixture.employee_edit_receipts VALUES(actor,p_mutation,payload,result);
  RETURN result;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA isg_workplace_fixture FROM PUBLIC;
CREATE TRIGGER employee_edit_audit_fault BEFORE INSERT ON isg_workplace_fixture.employee_edit_audit FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
CREATE TRIGGER employee_edit_outbox_fault BEFORE INSERT ON isg_workplace_fixture.employee_edit_outbox FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
CREATE TRIGGER employee_edit_receipts_fault BEFORE INSERT ON isg_workplace_fixture.employee_edit_receipts FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
COMMIT;
