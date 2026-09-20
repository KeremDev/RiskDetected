-- OSGB product parity for the personal pilot's operational summary cards.
-- Additive response keys only: existing clients keep every previously exposed
-- metric while newer clients can select domain-specific four-card summaries.

CREATE OR REPLACE FUNCTION private_isg.workspace_safety_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE today date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('emergency_ppe',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'plans',jsonb_build_object(
      'active',(SELECT count(*) FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company AND state='active'),
      'expired',(SELECT count(*) FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company AND state='active' AND valid_until<today),
      'untracked',(SELECT count(*) FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company AND state='active' AND valid_until IS NULL),
      'due_soon',(SELECT count(*) FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company AND state='active' AND valid_until BETWEEN today AND today+60),
      'valid',(SELECT count(*) FROM private_isg.emergency_plan_versions WHERE workspace_id=p_workspace AND company_id=p_company AND state='active' AND valid_until>today+60)),
    'drills',jsonb_build_object(
      'planned',(SELECT count(*) FROM private_isg.drill_records WHERE workspace_id=p_workspace AND company_id=p_company AND state='planned'),
      'performed',(SELECT count(*) FROM private_isg.drill_records WHERE workspace_id=p_workspace AND company_id=p_company AND state='performed')),
    'appointments',jsonb_build_object(
      'total',(SELECT count(*) FROM private_isg.appointments WHERE workspace_id=p_workspace AND company_id=p_company),
      'active',(SELECT count(*) FROM private_isg.appointments WHERE workspace_id=p_workspace AND company_id=p_company AND starts_on<=today AND (ends_before IS NULL OR ends_before>today)),
      'upcoming',(SELECT count(*) FROM private_isg.appointments WHERE workspace_id=p_workspace AND company_id=p_company AND starts_on>today),
      'ended',(SELECT count(*) FROM private_isg.appointments WHERE workspace_id=p_workspace AND company_id=p_company AND ends_before<=today)),
    'ppe',jsonb_build_object(
      'handovers',(SELECT count(*) FROM private_isg.ppe_handovers WHERE workspace_id=p_workspace AND company_id=p_company),
      'outstanding_quantity',(SELECT coalesce(sum(h.quantity-coalesce((SELECT sum(r.quantity) FROM private_isg.ppe_returns r
        WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.handover_id=h.handover_id),0)),0)
        FROM private_isg.ppe_handovers h WHERE h.workspace_id=p_workspace AND h.company_id=p_company))) INTO result;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_assurance_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; today date:=(clock_timestamp() AT TIME ZONE 'UTC')::date;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'risk',jsonb_build_object(
      'total',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company),
      'untracked',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND current_version=0),
      'expired',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND current_version>0 AND valid_until<today),
      'due_soon',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND current_version>0 AND valid_until BETWEEN today AND today+60),
      'valid',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND current_version>0 AND valid_until>today+60)),
    'nonconformity',jsonb_build_object(
      'total',(SELECT count(*) FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company),
      'open',(SELECT count(*) FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND state NOT IN ('closed','cancelled')),
      'overdue',(SELECT count(*) FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND state NOT IN ('closed','cancelled') AND due_on<today),
      'closed',(SELECT count(*) FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND state='closed')),
    'checklists',jsonb_build_object(
      'open',(SELECT count(*) FROM private_isg.checklist_runs WHERE workspace_id=p_workspace AND company_id=p_company AND state='open'),
      'submitted',(SELECT count(*) FROM private_isg.checklist_runs WHERE workspace_id=p_workspace AND company_id=p_company AND state='submitted'))) INTO result;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_operations_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.workspace_domain_gate('operations',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'katip_active',(SELECT count(*) FROM private_isg.katip_contracts WHERE workspace_id=p_workspace AND company_id=p_company AND state='active' AND NOT is_deleted),
    'annual_open_items',(SELECT count(*) FROM private_isg.annual_work_plan_items WHERE workspace_id=p_workspace AND company_id=p_company AND state='planned' AND NOT is_deleted),
    'board_open_decisions',(SELECT count(*) FROM private_isg.board_decisions WHERE workspace_id=p_workspace AND company_id=p_company AND state='open' AND NOT is_deleted),
    'board',jsonb_build_object(
      'planned',(SELECT count(*) FROM private_isg.board_meetings WHERE workspace_id=p_workspace AND company_id=p_company AND state='planned' AND NOT is_deleted),
      'held',(SELECT count(*) FROM private_isg.board_meetings WHERE workspace_id=p_workspace AND company_id=p_company AND state='held' AND NOT is_deleted),
      'cancelled',(SELECT count(*) FROM private_isg.board_meetings WHERE workspace_id=p_workspace AND company_id=p_company AND state='cancelled' AND NOT is_deleted),
      'open_decisions',(SELECT count(*) FROM private_isg.board_decisions WHERE workspace_id=p_workspace AND company_id=p_company AND state='open' AND NOT is_deleted)),
    'work_permits',(SELECT count(*) FROM private_isg.work_permit_forms WHERE workspace_id=p_workspace AND company_id=p_company AND NOT is_deleted),
    'site_visits',(SELECT count(*) FROM private_isg.site_visits WHERE workspace_id=p_workspace AND company_id=p_company AND NOT is_deleted),
    'notebook_archives',(SELECT count(*) FROM private_isg.notebook_archive_entries WHERE workspace_id=p_workspace AND company_id=p_company));
END $$;

COMMENT ON FUNCTION private_isg.workspace_safety_metrics(uuid,uuid) IS
  'Tenant-scoped safety metrics with product-parity plan and appointment status groups.';
COMMENT ON FUNCTION private_isg.workspace_assurance_metrics(uuid,uuid) IS
  'Tenant-scoped assurance metrics with mutually meaningful risk status groups.';
COMMENT ON FUNCTION private_isg.workspace_operations_metrics(uuid,uuid) IS
  'Tenant-scoped operations metrics including board meeting lifecycle and open decisions.';

NOTIFY pgrst,'reload schema';
