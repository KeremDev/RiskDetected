-- Company is the record scope when it has no active workplaces. A real
-- workplace must be chosen when one exists. Existing company records remain
-- editable if a workplace is created later.
BEGIN;

CREATE OR REPLACE FUNCTION private_isg.company_workplace_scope(
  p_company uuid, p_workplace uuid, p_workspace uuid, p_existing boolean DEFAULT false)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO '' AS $scope$
  SELECT CASE WHEN p_workplace IS NULL THEN p_existing OR NOT EXISTS (
    SELECT 1 FROM private_isg.workplaces w WHERE w.company_id=p_company AND NOT w.is_archived
  ) ELSE EXISTS (
    SELECT 1 FROM private_isg.workplaces w WHERE w.company_id=p_company
      AND w.id=p_workplace AND NOT w.is_archived
      AND (p_workspace IS NULL OR w.workspace_id=p_workspace OR w.workspace_id IS NULL)
  ) END;
$scope$;

CREATE OR REPLACE FUNCTION private_isg.require_company_workplace(
  p_company uuid, p_workplace uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SET search_path TO '' AS $scope$
BEGIN
  IF p_workplace IS NULL THEN
    IF EXISTS (SELECT 1 FROM private_isg.workplaces WHERE company_id=p_company AND NOT is_archived) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_REQUIRED'; END IF;
  ELSE
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace
      AND private_isg.expert_company_visible(owner_id,company_id,p_actor) AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
END $scope$;
REVOKE ALL ON FUNCTION private_isg.company_workplace_scope(uuid,uuid,uuid,boolean),
  private_isg.require_company_workplace(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE private_isg.appointments ALTER COLUMN scope_workplace_id DROP NOT NULL;
ALTER TABLE private_isg.risk_assessments ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.nonconformities ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.emergency_plan_versions ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.katip_contracts ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.annual_work_plans ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.board_meetings ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.work_permit_forms ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.site_visits ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.notebook_archive_entries ALTER COLUMN workplace_id DROP NOT NULL;
ALTER TABLE private_isg.drill_records ALTER COLUMN workplace_id DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS risk_assessments_company_general_unique
  ON private_isg.risk_assessments(company_id) WHERE workplace_id IS NULL;
ALTER TABLE private_isg.appointments ADD CONSTRAINT appointment_company_general_overlap
  EXCLUDE USING gist (company_id WITH =,employee_id WITH =,kind WITH =,effective_dates WITH &&)
  WHERE (scope_workplace_id IS NULL AND NOT is_deleted);

-- Fail closed if upstream functions changed. Each replacement must match once.
CREATE FUNCTION private_isg.migration_replace_function_once(
  p_signature regprocedure,p_old text,p_new text) RETURNS void
LANGUAGE plpgsql SET search_path TO '' AS $patch$
DECLARE definition text; matches integer;
BEGIN
  definition:=pg_get_functiondef(p_signature);
  matches:=(length(definition)-length(replace(definition,p_old,'')))/length(p_old);
  IF matches<>1 THEN
    RAISE EXCEPTION 'MIGRATION_SOURCE_DRIFT: % expected one match, found %',p_signature,matches;
  END IF;
  EXECUTE replace(definition,p_old,p_new);
END $patch$;

SELECT private_isg.migration_replace_function_once(
 'private_isg.workspace_assurance_root_invariant()'::regprocedure,
 $old$IF NOT EXISTS(SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id
      AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN$old$,
 $new$IF NOT private_isg.company_workplace_scope(NEW.company_id,NEW.workplace_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workplace_id IS NULL ELSE false END) THEN$new$);

SELECT private_isg.migration_replace_function_once(
 'private_isg.workspace_emergency_plan_invariant()'::regprocedure,
 $old$OR NOT EXISTS(
    SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id
      AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN$old$,
 $new$OR NOT private_isg.company_workplace_scope(NEW.company_id,NEW.workplace_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workplace_id IS NULL ELSE false END) THEN$new$);

SELECT private_isg.migration_replace_function_once(
 'private_isg.workspace_operation_root_invariant()'::regprocedure,
 $old$OR NOT EXISTS(
    SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN$old$,
 $new$OR NOT private_isg.company_workplace_scope(NEW.company_id,NEW.workplace_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workplace_id IS NULL ELSE false END) THEN$new$);

SELECT private_isg.migration_replace_function_once(
 'private_isg.workspace_appointment_invariant()'::regprocedure,
 $old$IF NOT EXISTS(SELECT 1 FROM private_isg.workplaces w
      WHERE w.workspace_id=NEW.workspace_id AND w.company_id=NEW.company_id AND w.id=NEW.scope_workplace_id) THEN$old$,
 $new$IF NOT private_isg.company_workplace_scope(NEW.company_id,NEW.scope_workplace_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.scope_workplace_id IS NULL ELSE false END) THEN$new$);

-- Legacy RPC boundaries: an omitted workplace is legal only for a company
-- with no workplace. Authorization remains in require_*_company.
SELECT private_isg.migration_replace_function_once(
 'private_isg.mutate_appointments(uuid,text,uuid,uuid,jsonb)'::regprocedure,
 $old$p_payload->>'workplace_id' IS NULL OR p_payload->>'starts_on' IS NULL$old$,
 $new$p_payload->>'starts_on' IS NULL$new$);
SELECT private_isg.migration_replace_function_once(
 'private_isg.mutate_appointments(uuid,text,uuid,uuid,jsonb)'::regprocedure,
 $old$PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$PERFORM private_isg.require_company_workplace(p_company,(p_payload->>'workplace_id')::uuid,actor);$new$);

SELECT private_isg.migration_replace_function_once(
 'private_isg.mutate_emergency_plans(uuid,text,uuid,uuid,jsonb)'::regprocedure,
 $old$p_payload->>'workplace_id' IS NULL OR p_payload->>'scope' IS NULL$old$,
 $new$p_payload->>'scope' IS NULL$new$);
SELECT private_isg.migration_replace_function_once(
 'private_isg.mutate_emergency_plans(uuid,text,uuid,uuid,jsonb)'::regprocedure,
 $old$PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
    AND id=(p_payload->>'workplace_id')::uuid AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$PERFORM private_isg.require_company_workplace(p_company,(p_payload->>'workplace_id')::uuid,actor);$new$);

SELECT private_isg.migration_replace_function_once(
 'private_isg.mutate_risk_versions(uuid,text,uuid,uuid,jsonb)'::regprocedure,
 $old$IF p_payload->>'workplace_id' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;$old$,
 $new$-- Workplace scope is checked by require_company_workplace below.$new$);
SELECT private_isg.migration_replace_function_once(
 'private_isg.mutate_risk_versions(uuid,text,uuid,uuid,jsonb)'::regprocedure,
 $old$PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$PERFORM private_isg.require_company_workplace(p_company,(p_payload->>'workplace_id')::uuid,actor);$new$);

-- The domain writers below predate nullable workplace scopes.
SELECT private_isg.migration_replace_function_once(
 'private_isg.open_risk_assessment(uuid,uuid,timestamptz)'::regprocedure,
 $old$IF p_company IS NULL OR p_workplace IS NULL OR p_now IS NULL$old$,
 $new$IF p_company IS NULL OR p_now IS NULL$new$);
SELECT private_isg.migration_replace_function_once(
 'private_isg.open_risk_assessment(uuid,uuid,timestamptz)'::regprocedure,
 $old$SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$PERFORM private_isg.require_company_workplace(p_company,p_workplace,private_isg.active_actor());
  IF p_workplace IS NULL THEN
    SELECT c.user_id INTO workplace.owner_id FROM public.companies c WHERE c.id=p_company FOR SHARE;
  ELSE
    SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  END IF;$new$);
SELECT private_isg.migration_replace_function_once(
 'private_isg.open_risk_assessment(uuid,uuid,timestamptz)'::regprocedure,
 $old$WHERE company_id=p_company AND workplace_id=p_workplace;$old$,
 $new$WHERE company_id=p_company AND workplace_id IS NOT DISTINCT FROM p_workplace;$new$);

SELECT private_isg.migration_replace_function_once(
 'private_isg.open_nonconformity_record(uuid,uuid,text,text,text,text,text,date,date,text,timestamptz)'::regprocedure,
 $old$p_company IS NULL OR p_workplace IS NULL OR p_source_kind IS NULL$old$,
 $new$p_company IS NULL OR p_source_kind IS NULL$new$);
SELECT private_isg.migration_replace_function_once(
 'private_isg.open_nonconformity_record(uuid,uuid,text,text,text,text,text,date,date,text,timestamptz)'::regprocedure,
 $old$SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;$old$,
 $new$PERFORM private_isg.require_company_workplace(p_company,p_workplace,private_isg.active_actor());
  IF p_workplace IS NULL THEN
    SELECT c.user_id INTO workplace.owner_id FROM public.companies c WHERE c.id=p_company FOR SHARE;
  ELSE
    SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  END IF;$new$);

DROP FUNCTION private_isg.migration_replace_function_once(regprocedure,text,text);
COMMIT;
