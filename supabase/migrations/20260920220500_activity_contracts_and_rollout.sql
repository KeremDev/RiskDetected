-- Explicit mutation/log contract. New mutation RPCs must be classified by the coverage test.
CREATE TABLE private_isg.business_activity_rpc_contracts (
 rpc_name text PRIMARY KEY, source text NOT NULL, exclusion_reason text
);
ALTER TABLE private_isg.business_activity_rpc_contracts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.business_activity_rpc_contracts FROM PUBLIC,anon,authenticated;
INSERT INTO private_isg.business_activity_rpc_contracts(rpc_name,source)
SELECT unnest(ARRAY[
'isg_appointments_mutate_v1','isg_checklists_mutate_v1','isg_directory_mutate_v1','isg_document_tracking_mutate_v1',
'isg_drills_mutate_v1','isg_emergency_plans_mutate_v1','isg_equipment_checks_mutate_v1','isg_file_library_mutate_v1',
'isg_nonconformity_mutate_v1','isg_personnel_mutate_v1','isg_pilot_company_create_v1','isg_pilot_company_create_v2',
'isg_pilot_company_create_v3','isg_pilot_file_library_mutate_v2','isg_pilot_finding_file_v1','isg_pilot_module_mutate_v1',
'isg_pilot_process_mutate_v1','isg_pilot_training_certificate_v1','isg_pilot_training_record_v2',
'isg_pilot_training_record_v3','isg_pilot_training_save_v1','isg_ppe_mutate_v1','isg_risk_versions_mutate_v1'
]),'canonical_rows_and_receipts';
INSERT INTO private_isg.business_activity_rpc_contracts(rpc_name,source)
SELECT unnest(ARRAY[
'isg_osgb_workspace_create_v1','isg_workspace_archive_v1','isg_workspace_asset_delete_v1',
'isg_workspace_assignment_mutate_v1','isg_workspace_checklist_mutate_v1','isg_workspace_company_archive_v1',
'isg_workspace_company_create_v1','isg_workspace_company_profile_mutate_v1','isg_workspace_company_update_v1',
'isg_workspace_directory_mutate_v1','isg_workspace_employee_mutate_v1','isg_workspace_equipment_mutate_v1',
'isg_workspace_file_create_receipt_v1','isg_workspace_file_mutate_v1','isg_workspace_handover_cancel_v1',
'isg_workspace_handover_compensate_v1','isg_workspace_handover_execute_v1','isg_workspace_invitation_accept_v1',
'isg_workspace_invitation_mutate_v1','isg_workspace_invitation_resend_v1','isg_workspace_invite_v1',
'isg_workspace_member_mutate_v1','isg_workspace_member_quota_set_v1','isg_workspace_nonconformity_mutate_v1',
'isg_workspace_operations_mutate_v1','isg_workspace_personnel_advanced_mutate_v1','isg_workspace_ppe_signed_handover_v1',
'isg_workspace_risk_mutate_v1','isg_workspace_safety_mutate_v1','isg_workspace_settings_update_v1',
'isg_workspace_training_advanced_mutate_v1','isg_workspace_training_mutate_v1','isg_workspace_analysis_file_v1',
'isg_workspace_upload_finalize_worker_v1'
]),'workspace_audit';
INSERT INTO private_isg.business_activity_rpc_contracts(rpc_name,source)
SELECT unnest(ARRAY['isg_workspace_ai_submit_v1','isg_workspace_photo_analysis_submit_v1',
'isg_workspace_export_create_v1','isg_workspace_worker_export_complete_v1','isg_workspace_worker_export_fail_v1'
]),'async_lifecycle';
INSERT INTO private_isg.business_activity_rpc_contracts(rpc_name,source)
SELECT unnest(ARRAY['isg_notebook_mutate_v1','isg_notebook_organize_v1']),'private_note_receipt';
INSERT INTO private_isg.business_activity_rpc_contracts VALUES
('isg_personal_workspace_ensure_v1','excluded','Idempotent technical workspace bootstrap'),
('isg_workspace_export_get_v1','excluded','Read only'),
('isg_workspace_handover_preview_v1','excluded','Preview only'),
('isg_workspace_worker_export_claim_v1','excluded','Internal worker lease'),
('isg_workspace_purchase_record_revenuecat_v1','excluded','Billing provider receipt, not expert business activity'),
('isg_notebook_reminder_mutate_v1','excluded','Private reminder metadata, never shared with managers');
INSERT INTO private_isg.business_activity_sources VALUES ('private_isg','pilot_personnel_certificates','certificate','record_id');
CREATE TRIGGER business_activity_row AFTER INSERT OR UPDATE OR DELETE ON private_isg.pilot_personnel_certificates
FOR EACH ROW EXECUTE FUNCTION private_isg.activity_business_row('certificate','record_id');

-- Facets use the whole authorized/date-scoped history, not just the visible page.
CREATE OR REPLACE FUNCTION private_isg.activity_page(p_user uuid,p_workspace uuid,p_after bigint,p_from timestamptz,p_to timestamptz,p_action text,p_company uuid,p_manager boolean)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH scoped AS MATERIALIZED (
 SELECT e.id,e.action,e.entity_type,e.entity_id,e.company_id,e.correlation_id,e.created_at,
 CASE WHEN e.workspace_id IS NOT NULL THEN
  (SELECT c.name FROM private_isg.workspace_companies c WHERE c.workspace_id=e.workspace_id AND (c.id=e.company_id OR c.legacy_company_id=e.company_id) LIMIT 1)
 ELSE (SELECT c.name FROM public.companies c WHERE c.id=e.company_id AND c.user_id=p_user) END company_name
 FROM private_isg.business_activity_events e WHERE e.actor_user_id=p_user
 AND (NOT p_manager OR (e.workspace_id=p_workspace AND e.entity_type<>'personal_note'))
 AND e.created_at>=p_from AND e.created_at<=p_to
 ), page AS (
 SELECT * FROM scoped WHERE (p_after IS NULL OR id<p_after)
 AND (p_action IS NULL OR action=p_action) AND (p_company IS NULL OR company_id=p_company)
 ORDER BY id DESC LIMIT 31
 ), shown AS (SELECT * FROM page ORDER BY id DESC LIMIT 30)
 SELECT jsonb_build_object('items',coalesce((SELECT jsonb_agg(to_jsonb(shown) ORDER BY id DESC) FROM shown),'[]'),
 'actions',coalesce((SELECT jsonb_agg(action ORDER BY action) FROM (SELECT DISTINCT action FROM scoped) x),'[]'),
 'companies',coalesce((SELECT jsonb_agg(jsonb_build_object('id',company_id,'name',coalesce(company_name,'Arşivlenmiş firma')) ORDER BY company_name)
 FROM (SELECT DISTINCT company_id,company_name FROM scoped WHERE company_id IS NOT NULL) x),'[]'),
 'next_cursor',CASE WHEN (SELECT count(*) FROM page)>30 THEN (SELECT min(id) FROM shown) ELSE NULL END);
$$;

CREATE OR REPLACE FUNCTION public.isg_activity_event_detail_v1(p_event bigint,p_workspace uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); e private_isg.business_activity_events; link_company uuid; link_workspace uuid;
BEGIN
 SELECT * INTO e FROM private_isg.business_activity_events WHERE id=p_event;
 IF e.id IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF e.actor_user_id IS DISTINCT FROM actor OR p_workspace IS NOT NULL THEN
   IF p_workspace IS NULL OR e.workspace_id IS DISTINCT FROM p_workspace OR e.entity_type='personal_note' THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
   PERFORM private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
   IF e.actor_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.workspace_memberships m WHERE m.workspace_id=p_workspace AND m.user_id=e.actor_user_id
     AND e.created_at>=m.joined_at AND e.created_at<=coalesce(m.ended_at,m.suspended_at,'infinity')) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 END IF;
 -- Historical log access does not grant present-day record access.
 IF e.workspace_id IS NULL THEN
   SELECT id INTO link_company FROM public.companies WHERE id=e.company_id AND user_id=actor;
 ELSE
   IF EXISTS(SELECT 1 FROM private_isg.workspace_memberships WHERE workspace_id=e.workspace_id AND user_id=actor AND status='active') THEN
     SELECT coalesce(legacy_company_id,id),workspace_id INTO link_company,link_workspace
       FROM private_isg.workspace_companies WHERE workspace_id=e.workspace_id AND (id=e.company_id OR legacy_company_id=e.company_id) LIMIT 1;
   END IF;
 END IF;
 RETURN jsonb_build_object('id',e.id,'action',e.action,'entity_type',e.entity_type,'entity_id',e.entity_id,
 'company_id',e.company_id,'correlation_id',e.correlation_id,'created_at',e.created_at,'changes',e.changes,'stages',e.stages,
 'link_company_id',link_company,'link_workspace_id',link_workspace);
END $$;

-- Fresh installations become visible only after all forward RPCs and the worker exist.
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='personal_notes';
