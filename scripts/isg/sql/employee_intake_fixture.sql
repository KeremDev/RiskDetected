-- User simplification: name-only company employee intake. Private synthetic candidate.
BEGIN;
SET LOCAL ROLE isg_workplace_owner;
ALTER TABLE isg_workplace_fixture.employees ALTER COLUMN hired_on DROP NOT NULL;
ALTER TABLE isg_workplace_fixture.departments ADD UNIQUE(company_id,id);
ALTER TABLE isg_workplace_fixture.employees ADD COLUMN intake_department_id uuid,
  ADD FOREIGN KEY(company_id,intake_department_id) REFERENCES isg_workplace_fixture.departments(company_id,id);
-- Do not backdate unknown legacy registration timestamps or invent employment dates.
ALTER TABLE isg_workplace_fixture.employees ADD COLUMN registered_at timestamptz;
CREATE TABLE isg_workplace_fixture.employee_create_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, payload jsonb NOT NULL, response jsonb NOT NULL,
  PRIMARY KEY(actor_id,mutation_id)
);
CREATE TABLE isg_workplace_fixture.employee_create_audit (
  employee_id uuid PRIMARY KEY REFERENCES isg_workplace_fixture.employees(id), actor_id uuid NOT NULL,
  mutation_id uuid NOT NULL, department_created_id uuid REFERENCES isg_workplace_fixture.departments(id)
);
CREATE TABLE isg_workplace_fixture.employee_create_outbox (
  employee_id uuid PRIMARY KEY REFERENCES isg_workplace_fixture.employees(id),
  event_type text NOT NULL CHECK(event_type='employee.created'), schema_version integer NOT NULL CHECK(schema_version=1)
);
ALTER TABLE isg_workplace_fixture.employee_create_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.employee_create_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.employee_create_outbox ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION isg_workplace_fixture.intake_text(value text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT normalize(regexp_replace(btrim(value,E' \t\r\n'),E'[ \t\r\n]+',' ','g'),NFC)
$$;
CREATE FUNCTION isg_workplace_fixture.department_name_key(value text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT translate(isg_workplace_fixture.intake_text(value),'ABCDEFGHIJKLMNOPQRSTUVWXYZÇĞİÖŞÜ','abcdefghıjklmnopqrstuvwxyzçğiöşü')
$$;
CREATE FUNCTION isg_workplace_fixture.create_employee(p_operation uuid,p_mutation uuid,p_company uuid,
  p_name text,p_department uuid,p_department_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid; full_name text; department_name text; name_key text; department uuid;
  created_department uuid; workplace uuid; matches integer; employee uuid; payload jsonb; result jsonb;
  receipt isg_workplace_fixture.employee_create_receipts;
BEGIN
  actor:=nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
  PERFORM 1 FROM isg_workplace_fixture.personnel_write_access WHERE actor_id=actor AND enabled FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Serializes inline name resolution/creation within this company, including retries.
  PERFORM 1 FROM isg_workplace_fixture.legacy_companies WHERE id=p_company AND owner_id=actor AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  full_name:=isg_workplace_fixture.intake_text(p_name);
  department_name:=isg_workplace_fixture.intake_text(p_department_name);
  IF p_operation IS NULL OR p_mutation IS NULL OR full_name IS NULL OR full_name='' OR octet_length(p_name)>4096 OR octet_length(full_name)>200 OR full_name ~ '[[:cntrl:]]' OR
     (p_department IS NOT NULL AND p_department_name IS NOT NULL) OR
     (p_department_name IS NOT NULL AND (department_name='' OR octet_length(p_department_name)>4096 OR octet_length(department_name)>120 OR department_name ~ '[[:cntrl:]]')) OR
     full_name ~ U&'[\200B\FEFF]' OR department_name ~ U&'[\200B\FEFF]' OR full_name ~ '^[[:space:]]*$' OR department_name ~ '^[[:space:]]*$' OR
     btrim(full_name,U&'\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')='' OR
     btrim(department_name,U&'\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')='' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  name_key:=isg_workplace_fixture.department_name_key(department_name);
  payload:=jsonb_build_object('operation_id',p_operation,'company_id',p_company,'full_name',full_name,'department_id',p_department,'department_name_key',name_key);
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':employee-create:'||p_mutation::text,0));
  SELECT * INTO receipt FROM isg_workplace_fixture.employee_create_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF receipt.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    PERFORM 1 FROM isg_workplace_fixture.employees WHERE id=(receipt.response->>'employee_id')::uuid AND company_id=p_company AND NOT is_archived FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN receipt.response;
  END IF;
  department:=p_department;
  IF p_department_name IS NOT NULL THEN
    SELECT count(*),min(id::text)::uuid INTO matches,department FROM isg_workplace_fixture.departments
      WHERE company_id=p_company AND NOT is_archived AND isg_workplace_fixture.department_name_key(name)=name_key;
    IF matches>1 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SELECTION_REQUIRED'; END IF;
    IF matches=0 THEN
      workplace:=isg_workplace_fixture.ensure_default(p_company);
      PERFORM 1 FROM isg_workplace_fixture.workplaces WHERE id=workplace AND NOT is_archived FOR SHARE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID'; END IF;
      created_department:=gen_random_uuid();
      INSERT INTO isg_workplace_fixture.departments(id,company_id,owner_id,workplace_id,code,name)
        VALUES(created_department,p_company,actor,workplace,'D-'||created_department::text,department_name);
      department:=created_department;
    END IF;
  END IF;
  IF department IS NOT NULL THEN
    SELECT workplace_id INTO workplace FROM isg_workplace_fixture.departments
      WHERE id=department AND company_id=p_company AND NOT is_archived FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID'; END IF;
    PERFORM 1 FROM isg_workplace_fixture.workplaces WHERE id=workplace AND company_id=p_company AND NOT is_archived FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPARTMENT_SCOPE_INVALID'; END IF;
  END IF;
  employee:=gen_random_uuid();
  INSERT INTO isg_workplace_fixture.employees(id,company_id,owner_id,employee_code,full_name,intake_department_id,registered_at)
    VALUES(employee,p_company,actor,'P-'||employee::text,full_name,department,transaction_timestamp());
  result:=jsonb_build_object('schema_version',1,'operation_id',p_operation,'employee_id',employee,'department_id',department,'department_created',created_department IS NOT NULL,'version',0);
  INSERT INTO isg_workplace_fixture.employee_create_audit VALUES(employee,actor,p_mutation,created_department);
  INSERT INTO isg_workplace_fixture.employee_create_outbox VALUES(employee,'employee.created',1);
  INSERT INTO isg_workplace_fixture.employee_create_receipts VALUES(actor,p_mutation,payload,result);
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION isg_workplace_fixture.intake_text(text),isg_workplace_fixture.department_name_key(text),
  isg_workplace_fixture.create_employee(uuid,uuid,uuid,text,uuid,text) FROM PUBLIC;
CREATE TRIGGER employee_create_audit_fault BEFORE INSERT ON isg_workplace_fixture.employee_create_audit FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
CREATE TRIGGER employee_create_outbox_fault BEFORE INSERT ON isg_workplace_fixture.employee_create_outbox FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
CREATE TRIGGER employee_create_receipts_fault BEFORE INSERT ON isg_workplace_fixture.employee_create_receipts FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
COMMIT;
