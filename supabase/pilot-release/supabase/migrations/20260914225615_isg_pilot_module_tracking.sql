-- Current module tracking, derived at read time; no score or automatic completion writes.
CREATE FUNCTION public.isg_pilot_module_tracking_v1(p_company uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); answer jsonb; today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_company IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies c WHERE c.id=p_company AND c.user_id=actor AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
WITH scoped AS MATERIALIZED (SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived AND (p_company IS NULL OR c.id=p_company) AND private_isg.p05_pilot_can_read(actor,c.id)),
kinds(kind,module) AS (VALUES ('katip_contract','katip_contract'),('annual_work_plan','annual_work_plan'),('annual_work_item','annual_work_plan'),('board','board'),('board_decision','board'),('site_visit','site_visit'),('work_permit','work_permit'),('contractor','contractor'),('emergency_plan','emergency_plan'),('drill','drill'),('appointment','appointment'),('ppe','ppe')),
records AS (SELECT t.company_id company_id, 'katip_contract'::text kind, (false) pending, (t.ends_before-1) due_on, (t.ends_before IS NULL) review FROM private_isg.katip_contracts t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'annual_work_plan'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.annual_work_plans t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'annual_work_item'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.annual_work_plan_items t JOIN private_isg.annual_work_plans p ON p.plan_id=t.plan_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted UNION ALL SELECT t.company_id company_id, 'board'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.board_meetings t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'board_decision'::text kind, (t.state='open') pending, (CASE WHEN t.state='open' THEN t.due_on END) due_on, (false) review FROM private_isg.board_decisions t JOIN private_isg.board_meetings p ON p.meeting_id=t.meeting_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted AND p.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'site_visit'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.site_visits t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'work_permit'::text kind, (t.state='draft') pending, (NULL::date) due_on, (false) review FROM private_isg.work_permit_forms t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'contractor'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.contractor_organizations t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_archived UNION ALL SELECT t.company_id company_id, 'emergency_plan'::text kind, (false) pending, (t.valid_until) due_on, (t.valid_until IS NULL) review FROM private_isg.emergency_plan_versions t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'drill'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.drill_records t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'appointment'::text kind, (false) pending, (t.ends_before-1) due_on, (false) review FROM private_isg.appointments t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'ppe'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.ppe_handovers t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted),
summary AS (
 SELECT c.id company_id,c.name company_name,k.kind,
 coalesce(m.read_enabled,false) AND coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='modules'),false) available,
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
END $$;
REVOKE ALL ON FUNCTION public.isg_pilot_module_tracking_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.isg_pilot_module_tracking_v1(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
