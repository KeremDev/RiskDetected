-- Complete the shared writer stamps for process roots and child observations.
CREATE OR REPLACE FUNCTION private_isg.expert_write_scope() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace uuid:=private_isg.expert_workspace(); actor uuid; data jsonb:=to_jsonb(NEW);
 company uuid:=(data->>'company_id')::uuid; prior jsonb; patch jsonb;
BEGIN
 IF workspace IS NULL THEN RETURN NEW; END IF;
 actor:=private_isg.active_actor();
 IF company IS NULL THEN
  CASE TG_TABLE_NAME
   WHEN 'risk_assessment_versions','risk_source_links','risk_impacts' THEN SELECT company_id INTO company FROM private_isg.risk_assessments WHERE assessment_id=(data->>'assessment_id')::uuid;
   WHEN 'checklist_run_items' THEN SELECT company_id INTO company FROM private_isg.checklist_runs WHERE run_id=(data->>'run_id')::uuid;
   WHEN 'equipment_inspections' THEN SELECT company_id INTO company FROM private_isg.equipment_items WHERE equipment_id=(data->>'equipment_id')::uuid;
   WHEN 'annual_work_plan_items' THEN SELECT company_id INTO company FROM private_isg.annual_work_plans WHERE plan_id=(data->>'plan_id')::uuid;
   WHEN 'site_visit_observations' THEN SELECT company_id INTO company FROM private_isg.site_visits WHERE visit_id=(data->>'visit_id')::uuid;
   WHEN 'board_decisions' THEN SELECT company_id INTO company FROM private_isg.board_meetings WHERE meeting_id=(data->>'meeting_id')::uuid;
   WHEN 'document_versions' THEN SELECT company_id INTO company FROM private_isg.documents WHERE document_id=(data->>'document_id')::uuid;
   WHEN 'ppe_returns' THEN SELECT company_id INTO company FROM private_isg.ppe_handovers WHERE handover_id=(data->>'handover_id')::uuid;
   WHEN 'pilot_training_sessions','pilot_training_session_revisions' THEN
    PERFORM private_isg.workspace_require_member(workspace,ARRAY['owner','admin','expert'],true);
   ELSE RAISE EXCEPTION 'COMPANY_SCOPE_REQUIRED';
  END CASE;
 END IF;
 IF company IS NOT NULL THEN PERFORM private_isg.workspace_require_company(workspace,company,true); END IF;
 IF TG_OP='UPDATE' THEN
  prior:=to_jsonb(OLD);
  IF (prior->>'workspace_id')::uuid IS DISTINCT FROM workspace
    OR prior->>'company_id' IS DISTINCT FROM data->>'company_id'
    OR prior->>'owner_id' IS DISTINCT FROM data->>'owner_id' THEN RAISE EXCEPTION 'IMMUTABLE_SCOPE'; END IF;
 END IF;
 IF data->>'workspace_id' IS NOT NULL AND (data->>'workspace_id')::uuid<>workspace THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 patch:=jsonb_build_object('workspace_id',workspace);
 IF data ? 'company_id' THEN patch:=patch||jsonb_build_object('company_id',company); END IF;
 IF data ? 'owner_id' THEN patch:=patch||jsonb_build_object('owner_id',NULL); END IF;
 IF data ? 'created_by_user_id' THEN patch:=patch||jsonb_build_object('created_by_user_id',
  CASE WHEN TG_OP='UPDATE' THEN (prior->>'created_by_user_id')::uuid ELSE actor END); END IF;
 IF data ? 'updated_by_user_id' THEN patch:=patch||jsonb_build_object('updated_by_user_id',actor); END IF;
 IF data ? 'recorded_by_user_id' THEN patch:=patch||jsonb_build_object('recorded_by_user_id',actor); END IF;
 NEW:=jsonb_populate_record(NEW,patch);
 RETURN NEW;
END $$;

CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.work_permit_forms FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.site_visit_observations FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
