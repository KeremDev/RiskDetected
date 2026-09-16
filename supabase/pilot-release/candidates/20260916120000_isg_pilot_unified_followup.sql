SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';
CREATE OR REPLACE FUNCTION private_isg.notice_rows(p_actor uuid, p_company uuid)
 RETURNS TABLE(kind text, destination text, company_id uuid, company_name text, record_id uuid, title text, due_on date, window_days integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
WITH scoped AS MATERIALIZED (
  SELECT c.id,c.name FROM public.companies c
  WHERE c.user_id=p_actor AND NOT c.is_archived
    AND (p_company IS NULL OR c.id=p_company)
    AND private_isg.p05_pilot_can_read(p_actor,c.id)),
raw AS (
  SELECT 'katip_contract'::text kind,'katipContracts'::text destination,c.id company_id,c.name company_name,
         t.contract_id record_id,t.counterparty title,(t.ends_before-1) due_on
    FROM private_isg.katip_contracts t JOIN scoped c ON c.id=t.company_id
   WHERE NOT t.is_deleted AND t.state='active' AND t.ends_before IS NOT NULL
  UNION ALL
  SELECT 'appointment','appointments',c.id,c.name,t.appointment_id,e.full_name,(t.ends_before-1)
    FROM private_isg.appointments t JOIN scoped c ON c.id=t.company_id
    JOIN private_isg.employees e ON e.id=t.employee_id
   WHERE NOT t.is_deleted AND t.ends_before IS NOT NULL
  UNION ALL
  SELECT 'emergency_plan','emergencyPlans',c.id,c.name,t.plan_id,w.name,t.valid_until
    FROM private_isg.emergency_plan_versions t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE NOT t.is_deleted AND t.state='active' AND t.valid_until IS NOT NULL
  UNION ALL
  SELECT 'drill','drills',c.id,c.name,t.record_id,t.scenario,t.valid_until
    FROM private_isg.pilot_completed_drills t JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted
  UNION ALL
  SELECT 'personnel_certificate','documentChecklist',c.id,c.name,t.record_id,e.full_name||' · '||t.title,t.valid_until
    FROM private_isg.pilot_personnel_certificates t JOIN scoped c ON c.id=t.company_id JOIN private_isg.employees e ON e.id=t.employee_id
    WHERE NOT t.is_deleted AND NOT e.is_archived
  UNION ALL
  SELECT 'training','training',c.id,c.name,(s->>'id')::uuid,t.title||' · '||coalesce(s->>'group_name',''),(s->>'valid_until')::date
    FROM private_isg.pilot_training_sessions t CROSS JOIN LATERAL jsonb_array_elements(t.education->'scopes') s JOIN scoped c ON c.id=(s->>'company_id')::uuid
    WHERE t.owner_id=p_actor AND t.deleted_at IS NULL AND s->>'valid_until' IS NOT NULL
  UNION ALL
  SELECT 'annual_work_item','annualWorkPlans',c.id,c.name,t.item_id,t.activity,t.planned_on
    FROM private_isg.annual_work_plan_items t
    JOIN private_isg.annual_work_plans p ON p.plan_id=t.plan_id
    JOIN scoped c ON c.id=p.company_id
   WHERE NOT t.is_deleted AND NOT p.is_deleted AND t.state='planned' AND t.planned_on IS NOT NULL
  UNION ALL
  SELECT 'board','boardMeetings',c.id,c.name,t.meeting_id,w.name,t.planned_on
    FROM private_isg.board_meetings t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE NOT t.is_deleted AND t.state='planned' AND t.planned_on IS NOT NULL
  UNION ALL
  SELECT 'board_decision','boardMeetings',c.id,c.name,t.decision_id,t.decision_no::text,t.due_on
    FROM private_isg.board_decisions t
    JOIN private_isg.board_meetings p ON p.meeting_id=t.meeting_id
    JOIN scoped c ON c.id=p.company_id
   WHERE NOT t.is_deleted AND NOT p.is_deleted AND p.state<>'cancelled'
     AND t.state='open' AND t.due_on IS NOT NULL
  UNION ALL
  SELECT 'risk_assessment','riskAssessments',c.id,c.name,t.assessment_id,w.name,t.valid_until
    FROM private_isg.risk_assessments t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE t.valid_until IS NOT NULL
  UNION ALL
  SELECT 'equipment','periodicChecks',c.id,c.name,t.equipment_id,t.serial_tag,i.next_due_on
    FROM private_isg.equipment_items t JOIN scoped c ON c.id=t.company_id
    JOIN LATERAL (SELECT x.next_due_on FROM private_isg.equipment_inspections x
                   WHERE x.equipment_id=t.equipment_id
                   ORDER BY x.performed_on DESC,x.inspection_id DESC LIMIT 1) i ON true
   WHERE NOT t.is_archived AND i.next_due_on IS NOT NULL)
SELECT r.kind,r.destination,r.company_id,r.company_name,r.record_id,
       coalesce(nullif(btrim(r.title),''),'—'),r.due_on,private_isg.notice_window(r.kind)
  FROM raw r WHERE private_isg.notice_kind_available(r.kind)
UNION ALL
-- Evrak carries its own window, and only the newest recorded copy counts.
SELECT 'document','documentChecklist',c.id,c.name,o.obligation_id,o.title,d.valid_until,o.notice_days
  FROM private_isg.document_obligations o JOIN scoped c ON c.id=o.company_id
  JOIN LATERAL (SELECT x.valid_until FROM private_isg.document_obligation_records x
                 WHERE x.obligation_id=o.obligation_id
                 ORDER BY x.issued_on DESC,x.record_id DESC LIMIT 1) d ON true
 WHERE NOT o.is_archived AND d.valid_until IS NOT NULL
   AND private_isg.notice_kind_available('document')
$function$
;
CREATE OR REPLACE FUNCTION private_isg.notice_kind_available(p_kind text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN p_kind='training' THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='training'),false)
    WHEN p_kind='risk_assessment'
      THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='risk'),false)
    WHEN p_kind='document'
      THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='document_tracking'),false)
    ELSE coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='modules'),false)
     AND coalesce((SELECT m.read_enabled FROM private_isg.module_registry m WHERE m.module=CASE p_kind
       WHEN 'annual_work_item' THEN 'annual_work_plan'
       WHEN 'board_decision' THEN 'board'
       ELSE p_kind END),false)
  END
$function$
;
CREATE OR REPLACE FUNCTION private_isg.notice_window(p_kind text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT CASE p_kind
    WHEN 'training' THEN 30
    WHEN 'personnel_certificate' THEN 30
    WHEN 'risk_assessment' THEN private_isg.risk_notice_days()
    WHEN 'emergency_plan' THEN private_isg.emergency_notice_days()
    WHEN 'drill' THEN private_isg.drill_notice_days()
    WHEN 'equipment' THEN private_isg.equipment_notice_days()
    WHEN 'katip_contract' THEN 30
    WHEN 'appointment' THEN 30
    WHEN 'annual_work_item' THEN 14
    WHEN 'board' THEN 14
    WHEN 'board_decision' THEN 7
  END
$function$
;
CREATE OR REPLACE FUNCTION public.isg_pilot_module_tracking_v2(p_company uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); answer jsonb; today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_company IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies c WHERE c.id=p_company AND c.user_id=actor AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
WITH scoped AS MATERIALIZED (SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived AND (p_company IS NULL OR c.id=p_company) AND private_isg.p05_pilot_can_read(actor,c.id)),
kinds(kind,module) AS (VALUES ('katip_contract','katip_contract'),('annual_work_plan','annual_work_plan'),('annual_work_item','annual_work_plan'),('board','board'),('board_decision','board'),('site_visit','site_visit'),('work_permit','work_permit'),('contractor','contractor'),('emergency_plan','emergency_plan'),('drill','drill'),('appointment','appointment'),('ppe','ppe'),('checklist_run','checklist'),('personnel_certificate','personnel_certificate')),
records AS (SELECT t.company_id, 'drill'::text kind, false pending,t.valid_until due_on,false review FROM private_isg.pilot_completed_drills t JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted
 UNION ALL SELECT t.company_id,'personnel_certificate',false,t.valid_until,false FROM private_isg.pilot_personnel_certificates t JOIN scoped c ON c.id=t.company_id JOIN private_isg.employees e ON e.id=t.employee_id WHERE NOT t.is_deleted AND NOT e.is_archived
 UNION ALL SELECT t.company_id, 'checklist_run'::text kind, t.state='open' pending, NULL::date due_on, false review FROM private_isg.checklist_runs t JOIN scoped c ON c.id=t.company_id WHERE t.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'katip_contract'::text kind, (false) pending, (t.ends_before-1) due_on, (t.ends_before IS NULL) review FROM private_isg.katip_contracts t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'annual_work_plan'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.annual_work_plans t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'annual_work_item'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.annual_work_plan_items t JOIN private_isg.annual_work_plans p ON p.plan_id=t.plan_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted UNION ALL SELECT t.company_id company_id, 'board'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.board_meetings t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'board_decision'::text kind, (t.state='open') pending, (CASE WHEN t.state='open' THEN t.due_on END) due_on, (false) review FROM private_isg.board_decisions t JOIN private_isg.board_meetings p ON p.meeting_id=t.meeting_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted AND p.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'site_visit'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.site_visits t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'work_permit'::text kind, (t.state='draft') pending, (NULL::date) due_on, (false) review FROM private_isg.work_permit_forms t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'contractor'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.contractor_organizations t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_archived UNION ALL SELECT t.company_id company_id, 'emergency_plan'::text kind, (false) pending, (t.valid_until) due_on, (t.valid_until IS NULL) review FROM private_isg.emergency_plan_versions t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'drill'::text kind, false pending, NULL::date due_on, (false) review FROM private_isg.drill_records t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'appointment'::text kind, (false) pending, (t.ends_before-1) due_on, (false) review FROM private_isg.appointments t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'ppe'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.ppe_handovers t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted),
summary AS (
 SELECT c.id company_id,c.name company_name,k.kind,
 CASE WHEN k.kind='checklist_run' THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='nonconformity'),false) ELSE coalesce(m.read_enabled,false) AND coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='modules'),false) END available,
 count(r.kind) total,count(r.kind) FILTER(WHERE r.pending) pending,
 count(r.kind) FILTER(WHERE r.due_on<today) overdue,
 count(r.kind) FILTER(WHERE r.due_on BETWEEN today AND today+30) upcoming,
 count(r.kind) FILTER(WHERE r.review) review,
 min(r.due_on) FILTER(WHERE r.due_on>=today) next_on
 FROM scoped c CROSS JOIN kinds k LEFT JOIN private_isg.module_registry m ON m.module=k.module
 LEFT JOIN records r ON r.company_id=c.id AND r.kind=k.kind
 GROUP BY c.id,c.name,k.kind,m.read_enabled)
SELECT jsonb_build_object('today',today,'generated_at',clock_timestamp(),'company_id',p_company,'rows',coalesce(jsonb_agg(jsonb_build_object(
 'company_id',company_id,'company_name',company_name,'kind',kind,'available',available,
 'total',CASE WHEN available THEN total END,'pending',CASE WHEN available THEN pending END,
 'overdue',CASE WHEN available THEN overdue END,'upcoming',CASE WHEN available THEN upcoming END,
 'review',CASE WHEN available THEN review END,'next_on',CASE WHEN available THEN next_on END)
 ORDER BY company_name,company_id,kind),'[]'::jsonb)) INTO answer FROM summary;
RETURN answer;
END $function$
;
REVOKE ALL ON FUNCTION public.isg_pilot_module_tracking_v2(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.isg_pilot_module_tracking_v2(uuid) TO authenticated;
CREATE FUNCTION private_isg.pilot_followup_rows(p_actor uuid,p_company uuid)
RETURNS TABLE(kind text,company_id uuid,company_name text,record_id uuid,title text,due_on date,window_days int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE r.kind WHEN 'drill' THEN 'completed_drill' ELSE r.kind END,r.company_id,r.company_name,r.record_id,r.title,r.due_on,r.window_days
 FROM private_isg.notice_rows(p_actor,p_company) r WHERE r.kind NOT IN ('annual_work_item','board','board_decision')
 UNION ALL
 SELECT 'file',f.company_id,c.name,f.entry_id,f.title,NULL::date,NULL::int
 FROM private_isg.file_library_entries f JOIN public.companies c ON c.id=f.company_id AND c.user_id=f.owner_id
 WHERE f.owner_id=p_actor AND NOT c.is_archived AND NOT f.is_archived AND f.asset_id IS NOT NULL AND private_isg.p05_pilot_can_read(p_actor,c.id)
 AND (p_company IS NULL OR f.company_id=p_company)
 AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_personnel_certificates x WHERE x.asset_id=f.asset_id AND NOT x.is_deleted)
 AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_completed_drills x WHERE (x.asset_id=f.asset_id OR f.asset_id=ANY(x.photo_ids)) AND NOT x.is_deleted)
$$;
REVOKE ALL ON FUNCTION private_isg.pilot_followup_rows(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.isg_pilot_followup_v1(p_company uuid DEFAULT NULL,p_status text DEFAULT NULL,p_query text DEFAULT '',p_offset int DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); answer jsonb; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
 IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF p_company IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived AND private_isg.p05_pilot_can_read(actor,id)) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 OR length(p_query)>200 OR (p_status IS NOT NULL AND p_status NOT IN ('current','soon','expired','undated')) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 WITH raw AS MATERIALIZED (SELECT r.*,CASE WHEN due_on IS NULL THEN 'undated' WHEN due_on<today THEN 'expired' WHEN due_on<=today+coalesce(window_days,30) THEN 'soon' ELSE 'current' END status FROM private_isg.pilot_followup_rows(actor,p_company) r),
 filtered AS (SELECT * FROM raw WHERE (p_status IS NULL OR status=p_status) AND (coalesce(p_query,'')='' OR title ILIKE '%'||p_query||'%' OR company_name ILIKE '%'||p_query||'%'))
 SELECT jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'today',today,
 'current',(SELECT count(*) FROM raw WHERE status='current'),'soon',(SELECT count(*) FROM raw WHERE status='soon'),'expired',(SELECT count(*) FROM raw WHERE status='expired'),'undated',(SELECT count(*) FROM raw WHERE status='undated'),
 'has_more',(SELECT count(*) FROM filtered)>p_offset+30,
 'rows',coalesce((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object('source_id',CASE WHEN t.kind='training' THEN (SELECT x.id FROM private_isg.pilot_training_sessions x WHERE x.owner_id=actor AND x.deleted_at IS NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(x.education->'scopes') sc WHERE sc->>'id'=t.record_id::text) LIMIT 1) ELSE t.record_id END) ORDER BY t.due_on NULLS LAST,t.company_name,t.kind,t.record_id) FROM (SELECT * FROM filtered ORDER BY due_on NULLS LAST,company_name,kind,record_id OFFSET p_offset LIMIT 30) t),'[]')) INTO answer;
 RETURN answer;
END $$;
REVOKE ALL ON FUNCTION public.isg_pilot_followup_v1(uuid,text,text,int) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.isg_pilot_followup_v1(uuid,text,text,int) TO authenticated;
NOTIFY pgrst,'reload schema';
