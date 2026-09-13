-- Explicit reactivation preserves IDs, dates, assignments and historical snapshots.
BEGIN;
SET LOCAL lock_timeout='5s';
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
COMMIT;
