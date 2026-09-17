-- D4 emergency plans, drills, employee appointments and PPE. NOT DEPLOYED; default OFF.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='25s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check
  CHECK(entity_type IN ('workspace','membership','invitation','company','assignment','seat','subscription',
    'wallet','asset','handover','workplace','department','employee','domain','training','risk',
    'nonconformity','checklist','emergency_plan','drill','appointment','ppe'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check
  CHECK(aggregate_type IN ('workspace','membership','invitation','company','assignment','seat','subscription',
    'wallet','asset','handover','workplace','department','employee','domain','training','risk',
    'nonconformity','checklist','emergency_plan','drill','appointment','ppe'));

ALTER TABLE private_isg.emergency_plan_versions ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.emergency_plan_versions ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.emergency_plan_versions ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.emergency_plan_versions ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.emergency_plan_versions ADD CONSTRAINT emergency_plans_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.emergency_plan_versions ADD CONSTRAINT emergency_plans_workspace_workplace_fk
  FOREIGN KEY(workspace_id,company_id,workplace_id)
  REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.emergency_plan_versions ADD CONSTRAINT emergency_plans_workspace_identity_unique
  UNIQUE(workspace_id,company_id,plan_id,version);

ALTER TABLE private_isg.drill_records ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.drill_records ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.drill_records ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.drill_records ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.drill_records ADD CONSTRAINT drills_workspace_plan_fk
  FOREIGN KEY(workspace_id,company_id,plan_id,plan_version)
  REFERENCES private_isg.emergency_plan_versions(workspace_id,company_id,plan_id,version) ON DELETE RESTRICT;
ALTER TABLE private_isg.drill_records ADD CONSTRAINT drills_workspace_workplace_fk
  FOREIGN KEY(workspace_id,company_id,workplace_id)
  REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.drill_records ADD CONSTRAINT drills_workspace_identity_unique
  UNIQUE(workspace_id,company_id,drill_id);

ALTER TABLE private_isg.appointments ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.appointments ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.appointments ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.appointments ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.appointments ADD CONSTRAINT appointments_workspace_employee_fk
  FOREIGN KEY(workspace_id,company_id,employee_id)
  REFERENCES private_isg.employees(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.appointments ADD CONSTRAINT appointments_workspace_workplace_fk
  FOREIGN KEY(workspace_id,company_id,scope_workplace_id)
  REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.appointments ADD CONSTRAINT appointments_workspace_identity_unique
  UNIQUE(workspace_id,company_id,appointment_id);

ALTER TABLE private_isg.ppe_handovers ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.ppe_handovers ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.ppe_handovers ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.ppe_handovers ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.ppe_handovers ADD CONSTRAINT ppe_handovers_workspace_employee_fk
  FOREIGN KEY(workspace_id,company_id,employee_id)
  REFERENCES private_isg.employees(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.ppe_handovers ADD CONSTRAINT ppe_handovers_workspace_identity_unique
  UNIQUE(workspace_id,company_id,handover_id);
ALTER TABLE private_isg.ppe_returns ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.ppe_returns ADD COLUMN company_id uuid;
ALTER TABLE private_isg.ppe_returns ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.ppe_returns ADD CONSTRAINT ppe_returns_workspace_parent_fk
  FOREIGN KEY(workspace_id,company_id,handover_id)
  REFERENCES private_isg.ppe_handovers(workspace_id,company_id,handover_id) ON DELETE CASCADE;

UPDATE private_isg.emergency_plan_versions p SET workspace_id=c.workspace_id,
  created_by_user_id=p.owner_id,updated_by_user_id=p.owner_id
FROM public.companies c WHERE c.id=p.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.drill_records d SET workspace_id=p.workspace_id,
  created_by_user_id=p.created_by_user_id,updated_by_user_id=p.updated_by_user_id
FROM private_isg.emergency_plan_versions p WHERE p.company_id=d.company_id AND p.plan_id=d.plan_id
  AND p.version=d.plan_version AND p.workspace_id IS NOT NULL;
UPDATE private_isg.appointments a SET workspace_id=e.workspace_id,
  created_by_user_id=e.created_by_user_id,updated_by_user_id=e.updated_by_user_id
FROM private_isg.employees e WHERE e.company_id=a.company_id AND e.id=a.employee_id AND e.workspace_id IS NOT NULL;
UPDATE private_isg.ppe_handovers h SET workspace_id=e.workspace_id,
  created_by_user_id=e.created_by_user_id,updated_by_user_id=e.updated_by_user_id
FROM private_isg.employees e WHERE e.company_id=h.company_id AND e.id=h.employee_id AND e.workspace_id IS NOT NULL;
UPDATE private_isg.ppe_returns r SET workspace_id=h.workspace_id,company_id=h.company_id,
  created_by_user_id=h.created_by_user_id FROM private_isg.ppe_handovers h
WHERE h.handover_id=r.handover_id AND h.workspace_id IS NOT NULL;

CREATE INDEX emergency_plans_workspace_page ON private_isg.emergency_plan_versions(workspace_id,company_id,state,valid_until,plan_id,version);
CREATE INDEX drills_workspace_page ON private_isg.drill_records(workspace_id,company_id,state,planned_on,drill_id);
CREATE INDEX appointments_workspace_page ON private_isg.appointments(workspace_id,company_id,kind,starts_on,appointment_id);
CREATE INDEX ppe_workspace_page ON private_isg.ppe_handovers(workspace_id,company_id,employee_id,handed_on,handover_id);

CREATE FUNCTION private_isg.workspace_emergency_plan_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company public.companies; workspace private_isg.workspaces;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF company.id IS NULL OR NEW.workspace_id IS DISTINCT FROM company.workspace_id OR NOT EXISTS(
    SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id
      AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_SCOPE_CONFLICT'; END IF;
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.kind='osgb' AND NEW.owner_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_FORBIDDEN'; END IF;
  IF workspace.kind='personal' AND NEW.owner_id IS DISTINCT FROM company.user_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_MISMATCH'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.owner_id,NEW.plan_id,NEW.version,
      NEW.workplace_id,NEW.created_by_user_id) IS DISTINCT FROM
    ROW(OLD.workspace_id,OLD.company_id,OLD.owner_id,OLD.plan_id,OLD.version,
      OLD.workplace_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER emergency_plans_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.emergency_plan_versions
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_emergency_plan_invariant();

CREATE FUNCTION private_isg.workspace_drill_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE plan private_isg.emergency_plan_versions;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO plan FROM private_isg.emergency_plan_versions
    WHERE company_id=NEW.company_id AND plan_id=NEW.plan_id AND version=NEW.plan_version FOR SHARE;
  IF plan.plan_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='PLAN_NOT_FOUND'; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=plan.workspace_id; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id,NEW.workplace_id) IS DISTINCT FROM
     ROW(plan.workspace_id,plan.company_id,plan.workplace_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DRILL_SCOPE_CONFLICT'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.plan_id,NEW.plan_version,
      NEW.workplace_id,NEW.created_by_user_id) IS DISTINCT FROM
    ROW(OLD.workspace_id,OLD.company_id,OLD.plan_id,OLD.plan_version,
      OLD.workplace_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER drills_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.drill_records
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_drill_invariant();

CREATE FUNCTION private_isg.workspace_appointment_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE employee private_isg.employees;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO employee FROM private_isg.employees WHERE company_id=NEW.company_id AND id=NEW.employee_id FOR SHARE;
  IF employee.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='EMPLOYEE_NOT_FOUND'; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=employee.workspace_id; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id) IS DISTINCT FROM ROW(employee.workspace_id,employee.company_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYEE_SCOPE_CONFLICT'; END IF;
  IF NOT EXISTS(SELECT 1 FROM private_isg.workplaces w
      WHERE w.workspace_id=NEW.workspace_id AND w.company_id=NEW.company_id AND w.id=NEW.scope_workplace_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_SCOPE_CONFLICT'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.employee_id,NEW.created_by_user_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.employee_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER appointments_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.appointments
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_appointment_invariant();

CREATE FUNCTION private_isg.workspace_ppe_handover_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE employee private_isg.employees;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO employee FROM private_isg.employees WHERE company_id=NEW.company_id AND id=NEW.employee_id FOR SHARE;
  IF employee.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='EMPLOYEE_NOT_FOUND'; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=employee.workspace_id; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id) IS DISTINCT FROM ROW(employee.workspace_id,employee.company_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYEE_SCOPE_CONFLICT'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.employee_id,NEW.created_by_user_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.employee_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ppe_handovers_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.ppe_handovers
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_ppe_handover_invariant();

CREATE FUNCTION private_isg.workspace_ppe_return_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE parent private_isg.ppe_handovers; returned numeric;
BEGIN
  SELECT * INTO parent FROM private_isg.ppe_handovers WHERE handover_id=NEW.handover_id FOR SHARE;
  IF parent.handover_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='PPE_HANDOVER_NOT_FOUND'; END IF;
  IF private_isg.workspace_is_legacy_company_write(parent.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=parent.workspace_id; END IF;
  IF NEW.company_id IS NULL THEN NEW.company_id:=parent.company_id; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id) IS DISTINCT FROM ROW(parent.workspace_id,parent.company_id)
    OR NEW.returned_on<parent.handed_on THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PPE_RETURN_CONFLICT'; END IF;
  SELECT coalesce(sum(r.quantity),0) INTO returned FROM private_isg.ppe_returns r
    WHERE r.handover_id=NEW.handover_id AND r.return_id<>NEW.return_id;
  IF returned+NEW.quantity>parent.quantity THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PPE_RETURN_EXCEEDS_HANDOVER'; END IF;
  IF NEW.created_by_user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_RECORD'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ppe_returns_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.ppe_returns
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_ppe_return_invariant();

CREATE FUNCTION private_isg.workspace_safety_read(p_workspace uuid,p_company uuid,p_kind text,p_id uuid,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('emergency_ppe',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_kind NOT IN ('plans','drills','appointments','ppe') OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='plans' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('plan_id',plan_id,'version',version,'workplace_id',workplace_id,
      'scope',scope,'prepared_on',prepared_on,'valid_until',valid_until,'team',team_snapshot,
      'state',state,'needs_review',needs_review,'created_by_user_id',created_by_user_id)
      ORDER BY created_at DESC,plan_id,version DESC),'[]'::jsonb) INTO rows
    FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company
      AND (p_id IS NULL OR plan_id=p_id) AND (p_id IS NOT NULL OR state='active');
  ELSIF p_kind='drills' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('drill_id',drill_id,'workplace_id',workplace_id,
      'plan_id',plan_id,'plan_version',plan_version,'planned_on',planned_on,'performed_on',performed_on,
      'state',state,'participants',participants,'observation',observation,'improvement',improvement,'version',version)
      ORDER BY planned_on DESC,drill_id),'[]'::jsonb) INTO rows
    FROM private_isg.drill_records WHERE workspace_id=p_workspace AND company_id=p_company
      AND (p_id IS NULL OR drill_id=p_id);
  ELSIF p_kind='appointments' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('appointment_id',appointment_id,'employee_id',employee_id,
      'kind',kind,'workplace_id',scope_workplace_id,'starts_on',starts_on,'ends_before',ends_before,'version',version)
      ORDER BY starts_on DESC,appointment_id),'[]'::jsonb) INTO rows
    FROM private_isg.appointments WHERE workspace_id=p_workspace AND company_id=p_company
      AND (p_id IS NULL OR appointment_id=p_id);
  ELSE
    SELECT coalesce(jsonb_agg(jsonb_build_object('handover_id',h.handover_id,'employee_id',h.employee_id,
      'item',h.item,'quantity',h.quantity,'unit',h.unit,'handed_on',h.handed_on,'signed_copy',h.signed_copy,
      'version',h.version,'returned_quantity',coalesce((SELECT sum(r.quantity) FROM private_isg.ppe_returns r
        WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.handover_id=h.handover_id),0))
      ORDER BY h.handed_on DESC,h.handover_id),'[]'::jsonb) INTO rows
    FROM private_isg.ppe_handovers h WHERE h.workspace_id=p_workspace AND h.company_id=p_company
      AND (p_id IS NULL OR h.handover_id=p_id);
  END IF;
  IF p_id IS NOT NULL AND jsonb_array_length(rows)=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'kind',p_kind,
    'rows',(SELECT coalesce(jsonb_agg(value),'[]'::jsonb) FROM (SELECT value FROM jsonb_array_elements(rows) LIMIT p_limit) q));
END $$;

CREATE FUNCTION private_isg.workspace_safety_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); entity text; action text; fingerprint bytea; replay jsonb;
  target uuid; expected bigint; plan private_isg.emergency_plan_versions; drill private_isg.drill_records;
  appointment private_isg.appointments; handover private_isg.ppe_handovers; returned private_isg.ppe_returns;
  next_version integer; result jsonb; before_state jsonb; aggregate_version bigint:=0;
  team_snapshot jsonb; participants_snapshot jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('emergency_ppe',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>65536
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
      ('entity','action','id','expected_version','workplace_id','plan_id','plan_version','scope','prepared_on',
       'valid_until','team','review_note','planned_on','performed_on','participants','observation','improvement',
       'reason','employee_id','kind','starts_on','ends_before','item','quantity','unit','handed_on',
       'signed_copy','external_ref','returned_on','condition','note')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  entity:=p_payload->>'entity'; action:=p_payload->>'action'; target:=(p_payload->>'id')::uuid;
  IF (entity='plan' AND action='publish') OR (entity='drill' AND action IN ('create','perform','cancel'))
    OR (entity='appointment' AND action IN ('create','end')) OR (entity='ppe' AND action IN ('handover','return')) THEN NULL;
  ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'safety.'||entity||'.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  IF entity='plan' THEN
    target:=coalesce((p_payload->>'plan_id')::uuid,gen_random_uuid());
    SELECT coalesce(max(version),0)+1 INTO next_version FROM private_isg.emergency_plan_versions
      WHERE workspace_id=p_workspace AND company_id=p_company AND plan_id=target;
    IF jsonb_typeof(p_payload->'team') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'team') NOT BETWEEN 1 AND 200
      OR (p_payload->>'prepared_on')::date IS NULL OR
      ((p_payload->>'valid_until')::date IS NOT NULL AND (p_payload->>'valid_until')::date<=(p_payload->>'prepared_on')::date) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'team') AS source(member)
      WHERE jsonb_typeof(member)<>'object'
        OR EXISTS(SELECT 1 FROM jsonb_object_keys(member) key WHERE key NOT IN ('employee_id','role','contact'))
        OR coalesce(member->>'employee_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        OR coalesce(member->>'role','') NOT IN ('coordinator','fire','first_aid','evacuation','other')
        OR length(coalesce(member->>'contact',''))>200) OR
       (SELECT count(*) FROM jsonb_array_elements(p_payload->'team')) IS DISTINCT FROM
       (SELECT count(DISTINCT member->>'employee_id') FROM jsonb_array_elements(p_payload->'team') AS source(member)) OR
       EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'team') AS source(member)
         WHERE NOT EXISTS(SELECT 1 FROM private_isg.employees e
           WHERE e.workspace_id=p_workspace AND e.company_id=p_company
             AND e.id=(member->>'employee_id')::uuid AND NOT e.is_archived)) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEAM_MEMBER_INVALID'; END IF;
    SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('employee_id',e.id,'full_name',e.full_name,
      'role',member->>'role','contact',nullif(btrim(coalesce(member->>'contact','')),''))) ORDER BY ordinal)
      INTO team_snapshot
    FROM jsonb_array_elements(p_payload->'team') WITH ORDINALITY AS source(member,ordinal)
    JOIN private_isg.employees e ON e.workspace_id=p_workspace AND e.company_id=p_company
      AND e.id=(member->>'employee_id')::uuid;
    UPDATE private_isg.emergency_plan_versions SET state='superseded',updated_by_user_id=actor
      WHERE workspace_id=p_workspace AND company_id=p_company AND plan_id=target AND state='active';
    INSERT INTO private_isg.emergency_plan_versions(workspace_id,plan_id,version,company_id,owner_id,workplace_id,
      scope,prepared_on,valid_until,team_snapshot,state,needs_review,review_note,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,target,next_version,p_company,NULL,(p_payload->>'workplace_id')::uuid,
      private_isg.workspace_text(p_payload->>'scope',300),(p_payload->>'prepared_on')::date,
      (p_payload->>'valid_until')::date,team_snapshot,'active',
      (p_payload->>'valid_until') IS NULL,nullif(btrim(coalesce(p_payload->>'review_note','')),''),actor,actor)
    RETURNING * INTO plan;
    aggregate_version:=plan.version;
    result:=jsonb_build_object('plan_id',plan.plan_id,'version',plan.version,'state',plan.state);
  ELSIF entity='drill' THEN
    IF action='create' THEN
      INSERT INTO private_isg.drill_records(workspace_id,company_id,workplace_id,plan_id,plan_version,
        planned_on,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,(p_payload->>'workplace_id')::uuid,(p_payload->>'plan_id')::uuid,
        (p_payload->>'plan_version')::integer,(p_payload->>'planned_on')::date,actor,actor) RETURNING * INTO drill;
    ELSE
      expected:=(p_payload->>'expected_version')::bigint;
      SELECT * INTO drill FROM private_isg.drill_records WHERE workspace_id=p_workspace
        AND company_id=p_company AND drill_id=target FOR UPDATE;
      IF drill.drill_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF drill.version<>expected OR drill.state<>'planned' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      before_state:=to_jsonb(drill);
      IF action='perform' THEN
        IF jsonb_typeof(p_payload->'participants') IS DISTINCT FROM 'array' OR
          jsonb_array_length(p_payload->'participants') NOT BETWEEN 1 AND 1000 OR
          (p_payload->>'performed_on')::date>(clock_timestamp() AT TIME ZONE 'UTC')::date THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
        IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_payload->'participants') AS source(participant)
          WHERE participant !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') OR
           (SELECT count(*) FROM jsonb_array_elements_text(p_payload->'participants')) IS DISTINCT FROM
           (SELECT count(DISTINCT participant) FROM jsonb_array_elements_text(p_payload->'participants') AS source(participant)) OR
           EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_payload->'participants') AS source(participant)
             WHERE NOT EXISTS(SELECT 1 FROM private_isg.employees e
               WHERE e.workspace_id=p_workspace AND e.company_id=p_company
                 AND e.id=participant::uuid AND NOT e.is_archived)) THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_INVALID'; END IF;
        SELECT jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name) ORDER BY ordinal)
          INTO participants_snapshot
        FROM jsonb_array_elements_text(p_payload->'participants') WITH ORDINALITY AS source(participant,ordinal)
        JOIN private_isg.employees e ON e.workspace_id=p_workspace AND e.company_id=p_company
          AND e.id=participant::uuid;
        UPDATE private_isg.drill_records SET state='performed',performed_on=(p_payload->>'performed_on')::date,
          participants=participants_snapshot,observation=nullif(btrim(coalesce(p_payload->>'observation','')),''),
          improvement=nullif(btrim(coalesce(p_payload->>'improvement','')),''),version=version+1,
          updated_by_user_id=actor,updated_at=clock_timestamp() WHERE drill_id=target RETURNING * INTO drill;
      ELSE
        UPDATE private_isg.drill_records SET state='cancelled',cancelled_reason=private_isg.workspace_text(p_payload->>'reason',1000),
          version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp()
          WHERE drill_id=target RETURNING * INTO drill;
      END IF;
    END IF;
    target:=drill.drill_id; aggregate_version:=drill.version;
    result:=jsonb_build_object('drill_id',target,'state',drill.state,'version',drill.version);
  ELSIF entity='appointment' THEN
    IF action='create' THEN
      IF (p_payload->>'starts_on')::date IS NULL OR
         ((p_payload->>'ends_before')::date IS NOT NULL AND
          (p_payload->>'ends_before')::date<=(p_payload->>'starts_on')::date) OR EXISTS(
        SELECT 1 FROM private_isg.appointments a
        WHERE a.workspace_id=p_workspace AND a.company_id=p_company
          AND a.employee_id=(p_payload->>'employee_id')::uuid
          AND a.kind=p_payload->>'kind' AND a.scope_workplace_id=(p_payload->>'workplace_id')::uuid
          AND daterange(a.starts_on,a.ends_before,'[)') &&
              daterange((p_payload->>'starts_on')::date,(p_payload->>'ends_before')::date,'[)')) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='APPOINTMENT_OVERLAP'; END IF;
      INSERT INTO private_isg.appointments(workspace_id,company_id,employee_id,kind,scope_workplace_id,
        starts_on,ends_before,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,(p_payload->>'employee_id')::uuid,p_payload->>'kind',
        (p_payload->>'workplace_id')::uuid,(p_payload->>'starts_on')::date,(p_payload->>'ends_before')::date,actor,actor)
      RETURNING * INTO appointment;
    ELSE
      expected:=(p_payload->>'expected_version')::bigint;
      SELECT * INTO appointment FROM private_isg.appointments WHERE workspace_id=p_workspace
        AND company_id=p_company AND appointment_id=target FOR UPDATE;
      IF appointment.appointment_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF appointment.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      IF (p_payload->>'ends_before')::date IS NULL OR
         (p_payload->>'ends_before')::date<=appointment.starts_on THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      before_state:=to_jsonb(appointment);
      UPDATE private_isg.appointments SET ends_before=(p_payload->>'ends_before')::date,version=version+1,
        updated_by_user_id=actor,updated_at=clock_timestamp() WHERE appointment_id=target RETURNING * INTO appointment;
    END IF;
    target:=appointment.appointment_id; aggregate_version:=appointment.version;
    result:=jsonb_build_object('appointment_id',target,'version',appointment.version,'ends_before',appointment.ends_before);
  ELSE
    IF action='handover' THEN
      -- D7 will bind signed evidence to a workspace asset. Until that bridge is
      -- installed this endpoint must never claim a signed form was stored.
      IF coalesce((p_payload->>'signed_copy')::boolean,false) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SIGNED_EVIDENCE_REQUIRED'; END IF;
      INSERT INTO private_isg.ppe_handovers(workspace_id,company_id,employee_id,item,quantity,unit,handed_on,
        signed_copy,external_ref,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,(p_payload->>'employee_id')::uuid,private_isg.workspace_text(p_payload->>'item',200),
        (p_payload->>'quantity')::numeric,p_payload->>'unit',(p_payload->>'handed_on')::date,
        coalesce((p_payload->>'signed_copy')::boolean,false),nullif(btrim(coalesce(p_payload->>'external_ref','')),''),actor,actor)
      RETURNING * INTO handover;
      target:=handover.handover_id; aggregate_version:=handover.version;
      result:=jsonb_build_object('handover_id',target,'version',handover.version,'returned_quantity',0);
    ELSE
      SELECT * INTO handover FROM private_isg.ppe_handovers WHERE workspace_id=p_workspace
        AND company_id=p_company AND handover_id=target FOR UPDATE;
      IF handover.handover_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      before_state:=to_jsonb(handover);
      INSERT INTO private_isg.ppe_returns(workspace_id,company_id,handover_id,quantity,returned_on,condition,note,created_by_user_id)
      VALUES(p_workspace,p_company,target,(p_payload->>'quantity')::numeric,(p_payload->>'returned_on')::date,
        p_payload->>'condition',nullif(btrim(coalesce(p_payload->>'note','')),''),actor) RETURNING * INTO returned;
      UPDATE private_isg.ppe_handovers SET version=version+1,updated_by_user_id=actor
        WHERE handover_id=target RETURNING * INTO handover;
      aggregate_version:=handover.version;
      result:=jsonb_build_object('handover_id',target,'return_id',returned.return_id,'version',handover.version);
    END IF;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'entity',entity,'action',action,'row',result);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'safety.'||entity||'.'||action,fingerprint,p_workspace,
    CASE entity WHEN 'plan' THEN 'emergency_plan' ELSE entity END,target,aggregate_version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_safety_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE today date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('emergency_ppe',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'plans',jsonb_build_object(
      'active',(SELECT count(*) FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company AND state='active'),
      'expired',(SELECT count(*) FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company AND state='active' AND valid_until<today)),
    'drills',jsonb_build_object(
      'planned',(SELECT count(*) FROM private_isg.drill_records WHERE workspace_id=p_workspace AND company_id=p_company AND state='planned'),
      'performed',(SELECT count(*) FROM private_isg.drill_records WHERE workspace_id=p_workspace AND company_id=p_company AND state='performed')),
    'appointments',jsonb_build_object(
      'active',(SELECT count(*) FROM private_isg.appointments WHERE workspace_id=p_workspace AND company_id=p_company AND starts_on<=today AND (ends_before IS NULL OR ends_before>today))),
    'ppe',jsonb_build_object(
      'handovers',(SELECT count(*) FROM private_isg.ppe_handovers WHERE workspace_id=p_workspace AND company_id=p_company),
      'outstanding_quantity',(SELECT coalesce(sum(h.quantity-coalesce((SELECT sum(r.quantity) FROM private_isg.ppe_returns r
        WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.handover_id=h.handover_id),0)),0)
        FROM private_isg.ppe_handovers h WHERE h.workspace_id=p_workspace AND h.company_id=p_company))) INTO result;
  RETURN result;
END $$;

CREATE FUNCTION public.isg_workspace_safety_read_v1(p_workspace uuid,p_company uuid,p_kind text,
  p_id uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_safety_read(p_workspace,p_company,p_kind,p_id,p_limit) $$;
CREATE FUNCTION public.isg_workspace_safety_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_safety_mutate(p_mutation,p_workspace,p_company,p_payload) $$;
CREATE FUNCTION public.isg_workspace_safety_metrics_v1(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_safety_metrics(p_workspace,p_company) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_emergency_plan_invariant(),private_isg.workspace_drill_invariant(),
  private_isg.workspace_appointment_invariant(),private_isg.workspace_ppe_handover_invariant(),
  private_isg.workspace_ppe_return_invariant(),
  private_isg.workspace_safety_read(uuid,uuid,text,uuid,integer),private_isg.workspace_safety_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_safety_metrics(uuid,uuid),public.isg_workspace_safety_read_v1(uuid,uuid,text,uuid,integer),
  public.isg_workspace_safety_mutate_v1(uuid,uuid,uuid,jsonb),public.isg_workspace_safety_metrics_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_safety_read(uuid,uuid,text,uuid,integer),
  private_isg.workspace_safety_mutate(uuid,uuid,uuid,jsonb),private_isg.workspace_safety_metrics(uuid,uuid),
  public.isg_workspace_safety_read_v1(uuid,uuid,text,uuid,integer),
  public.isg_workspace_safety_mutate_v1(uuid,uuid,uuid,jsonb),public.isg_workspace_safety_metrics_v1(uuid,uuid)
  TO authenticated;
NOTIFY pgrst,'reload schema';
