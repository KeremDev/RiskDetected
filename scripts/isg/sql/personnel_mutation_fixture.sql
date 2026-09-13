-- Private synthetic transaction candidate; NOT a production RPC or Auth adapter.
BEGIN;
SET LOCAL ROLE isg_workplace_owner;
ALTER TABLE isg_workplace_fixture.employees ADD COLUMN assignment_version bigint NOT NULL DEFAULT 0 CHECK (assignment_version BETWEEN 0 AND 9007199254740991);
CREATE TABLE isg_workplace_fixture.personnel_write_access(actor_id uuid PRIMARY KEY, enabled boolean NOT NULL);
CREATE TABLE isg_workplace_fixture.personnel_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, payload jsonb NOT NULL, response jsonb NOT NULL,
  PRIMARY KEY(actor_id,mutation_id)
);
CREATE TABLE isg_workplace_fixture.personnel_audit (
  company_id uuid NOT NULL, employee_id uuid NOT NULL, version bigint NOT NULL,
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, assignment_id uuid NOT NULL REFERENCES isg_workplace_fixture.employee_assignments(id),
  PRIMARY KEY(company_id,employee_id,version),
  FOREIGN KEY(company_id,employee_id) REFERENCES isg_workplace_fixture.employees(company_id,id)
);
CREATE TABLE isg_workplace_fixture.personnel_outbox (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, employee_id uuid NOT NULL,
  version bigint NOT NULL, event_type text NOT NULL CHECK(event_type='employee.assignment.changed'),
  schema_version integer NOT NULL CHECK(schema_version=1), assignment_id uuid NOT NULL REFERENCES isg_workplace_fixture.employee_assignments(id),
  UNIQUE(company_id,employee_id,version),
  FOREIGN KEY(company_id,employee_id) REFERENCES isg_workplace_fixture.employees(company_id,id)
);
ALTER TABLE isg_workplace_fixture.personnel_write_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.personnel_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.personnel_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.personnel_outbox ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION isg_workplace_fixture.move_primary(p_operation uuid,p_mutation uuid,p_company uuid,p_employee uuid,p_expected bigint,
  p_previous uuid,p_workplace uuid,p_department uuid,p_job uuid,p_on date) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid; employee isg_workplace_fixture.employees; previous isg_workplace_fixture.employee_assignments;
  receipt isg_workplace_fixture.personnel_receipts; payload jsonb; result jsonb; new_id uuid; end_before date;
BEGIN
  -- This GUC + access table are synthetic verified-actor/capability stand-ins.
  actor := nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
  PERFORM 1 FROM isg_workplace_fixture.personnel_write_access WHERE actor_id=actor AND enabled FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM 1 FROM isg_workplace_fixture.legacy_companies WHERE id=p_company AND owner_id=actor AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_operation IS NULL OR p_mutation IS NULL OR p_employee IS NULL OR p_expected IS NULL OR p_expected<0 OR p_expected>=9007199254740991 OR
     p_workplace IS NULL OR p_department IS NULL OR p_job IS NULL OR p_on IS NULL OR NOT isfinite(p_on) OR p_on NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  payload := jsonb_build_object('schema_version',1,'operation_id',p_operation,'company_id',p_company,'employee_id',p_employee,'expected_version',p_expected,
    'previous_assignment_id',p_previous,'workplace_id',p_workplace,'department_id',p_department,'job_role_id',p_job,'starts_on',p_on);
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_mutation::text,0));
  SELECT * INTO employee FROM isg_workplace_fixture.employees WHERE company_id=p_company AND id=p_employee AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO receipt FROM isg_workplace_fixture.personnel_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF receipt.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN receipt.response;
  END IF;
  IF employee.assignment_version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  end_before:=employee.employment_ends_before;
  IF p_previous IS NOT NULL THEN
    SELECT * INTO previous FROM isg_workplace_fixture.employee_assignments WHERE company_id=p_company AND employee_id=p_employee AND id=p_previous FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_SCOPE_INVALID'; END IF;
    IF p_on<=previous.starts_on OR (previous.ends_before IS NOT NULL AND p_on>=previous.ends_before) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
    END IF;
    end_before:=previous.ends_before;
    UPDATE isg_workplace_fixture.employee_assignments SET ends_before=p_on WHERE id=p_previous;
  END IF;
  INSERT INTO isg_workplace_fixture.employee_assignments(company_id,owner_id,employee_id,workplace_id,department_id,job_role_id,starts_on,ends_before)
    VALUES(p_company,actor,p_employee,p_workplace,p_department,p_job,p_on,end_before) RETURNING id INTO new_id;
  UPDATE isg_workplace_fixture.employees SET assignment_version=assignment_version+1 WHERE id=p_employee RETURNING * INTO employee;
  result:=jsonb_build_object('schema_version',1,'operation_id',p_operation,'employee_id',p_employee,'assignment_id',new_id,'version',employee.assignment_version);
  INSERT INTO isg_workplace_fixture.personnel_audit VALUES(p_company,p_employee,employee.assignment_version,actor,p_mutation,new_id);
  INSERT INTO isg_workplace_fixture.personnel_outbox(company_id,employee_id,version,event_type,schema_version,assignment_id)
    VALUES(p_company,p_employee,employee.assignment_version,'employee.assignment.changed',1,new_id);
  INSERT INTO isg_workplace_fixture.personnel_receipts VALUES(actor,p_mutation,payload,result);
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION isg_workplace_fixture.move_primary(uuid,uuid,uuid,uuid,bigint,uuid,uuid,uuid,uuid,date) FROM PUBLIC;
CREATE TRIGGER personnel_audit_fault BEFORE INSERT ON isg_workplace_fixture.personnel_audit FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
CREATE TRIGGER personnel_outbox_fault BEFORE INSERT ON isg_workplace_fixture.personnel_outbox FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
CREATE TRIGGER personnel_receipts_fault BEFORE INSERT ON isg_workplace_fixture.personnel_receipts FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
COMMIT;
