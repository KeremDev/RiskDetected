-- Checklist execution references and current parent workload summaries. No automatic completion.
CREATE OR REPLACE FUNCTION private_isg.process_references(p_kind text,p_company uuid,p_id uuid,p_query text,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); rows_ jsonb; row_ jsonb; from_ text; id_ text; title_ text; date_ text; state_ text; company_ text; predicate text; BEGIN
 IF p_company IS NULL OR p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) OR NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF p_kind NOT IN ('training_record','equipment_inspection','nonconformity','checklist_run') THEN
  IF p_id IS NULL THEN RETURN private_isg.process_read(p_kind,p_company,NULL,NULL,p_query,p_offset); END IF;
  row_:=private_isg.process_row(p_kind,p_id);
  IF (row_->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('rows',jsonb_build_array(row_),'has_more',false,'workplaces','[]'::jsonb,'employees','[]'::jsonb,'documents','[]'::jsonb,'organizations','[]'::jsonb);
 END IF;
 CASE p_kind
 WHEN 'training_record' THEN
  from_:='private_isg.pilot_training_records t';id_:='t.id';title_:='t.title';date_:='t.starts_at';state_:='t.state';company_:='t.company_id';predicate:='t.state=''completed'' AND t.owner_id=$1';
 WHEN 'equipment_inspection' THEN
  PERFORM private_isg.require_equipment_company(p_company,false);
  from_:='private_isg.equipment_inspections t JOIN private_isg.equipment_items e ON e.equipment_id=t.equipment_id';id_:='t.inspection_id';title_:='e.serial_tag';date_:='t.performed_on';state_:='t.result';company_:='e.company_id';predicate:='NOT e.is_archived AND e.owner_id=$1';
 WHEN 'checklist_run' THEN
  PERFORM private_isg.require_checklist_company(p_company,false);
  from_:='private_isg.checklist_runs t JOIN private_isg.checklist_templates ct ON ct.template_code=t.template_code';id_:='t.run_id';title_:='ct.title';date_:='t.started_on';state_:='t.state';company_:='t.company_id';predicate:='t.state=''submitted''';
 WHEN 'nonconformity' THEN
  PERFORM private_isg.require_nonconformity_company(p_company,false);
  from_:='private_isg.nonconformities t';id_:='t.nonconformity_id';title_:='t.title';date_:='t.opened_on';state_:='t.state';company_:='t.company_id';predicate:='t.state<>''cancelled'' AND t.owner_id=$1';
 END CASE;
 EXECUTE format('SELECT coalesce(jsonb_agg(r),''[]''::jsonb) FROM (SELECT jsonb_build_object(''id'',%s,''company_id'',%s,''company_name'',c.name,''title'',%s,''date'',%s,''expected'','''',''values'',jsonb_build_object(''state'',%s)) r FROM %s JOIN public.companies c ON c.id=%s WHERE %s AND %s=$2 AND ($3 IS NULL OR %s=$3) AND ($4 IS NULL OR %s ILIKE ''%%''||$4||''%%'') ORDER BY %s DESC,%s DESC OFFSET $5 LIMIT 21) q',id_,company_,title_,date_,state_,from_,company_,predicate,company_,id_,title_,date_,id_) INTO rows_ USING actor,p_company,p_id,nullif(btrim(p_query),''),p_offset;
 IF p_id IS NOT NULL AND jsonb_array_length(rows_)=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 RETURN jsonb_build_object('rows',(SELECT coalesce(jsonb_agg(value ORDER BY ord),'[]') FROM jsonb_array_elements(rows_) WITH ORDINALITY x(value,ord) WHERE ord<=20),'has_more',jsonb_array_length(rows_)>20,'workplaces','[]'::jsonb,'employees','[]'::jsonb,'documents','[]'::jsonb,'organizations','[]'::jsonb);
END $$;
CREATE OR REPLACE FUNCTION private_isg.process_row(p_kind text,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$ DECLARE spec jsonb:=private_isg.process_spec(p_kind); row_ jsonb; parent jsonb; company uuid; BEGIN
IF spec IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
EXECUTE format('SELECT to_jsonb(t) FROM private_isg.%I t WHERE %I=$1',spec->>'table',spec->>'id') INTO row_ USING p_id;
IF row_ IS NULL OR coalesce((row_->>'is_deleted')::boolean,false) OR coalesce((row_->>'is_archived')::boolean,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF spec ? 'parent' THEN parent:=private_isg.process_row(spec->>'parent_kind',(row_->>(spec->>'parent'))::uuid);company:=(parent->>'company_id')::uuid;
ELSE company:=(row_->>'company_id')::uuid; END IF;
PERFORM private_isg.process_guard(p_kind,company,false);
RETURN jsonb_build_object('child_summary',CASE p_kind
 WHEN 'annual_work_plan' THEN (SELECT jsonb_build_object('total',count(*),'open',count(*) FILTER(WHERE state='planned'),'overdue',count(*) FILTER(WHERE state='planned' AND planned_on<(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date)) FROM private_isg.annual_work_plan_items WHERE plan_id=p_id AND NOT is_deleted)
 WHEN 'board' THEN (SELECT jsonb_build_object('total',count(*),'open',count(*) FILTER(WHERE state='open'),'overdue',count(*) FILTER(WHERE state='open' AND due_on<(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date)) FROM private_isg.board_decisions WHERE meeting_id=p_id AND NOT is_deleted)
 ELSE NULL END,'id',p_id,'company_id',company,'company_name',(SELECT name FROM public.companies WHERE id=company),'title',coalesce(row_->>(spec->>'title'),p_kind),'date',coalesce(row_->>(spec->>'date'),''),'values',row_,'workplace_name',(SELECT name FROM private_isg.workplaces WHERE id=(row_->>'workplace_id')::uuid AND company_id=company),'expected',md5((row_||coalesce((SELECT jsonb_build_object('document_id',m.document_id,'related_kind',m.related_kind,'related_id',m.related_id) FROM private_isg.process_record_meta m WHERE m.kind=p_kind AND m.record_id=p_id),jsonb_build_object('document_id',NULL,'related_kind',NULL,'related_id',NULL)))::text),'document_id',(SELECT document_id FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id),'related_kind',(SELECT related_kind FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id),'related_id',(SELECT related_id FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id));
END $$;
CREATE OR REPLACE FUNCTION public.isg_pilot_module_tracking_v1(p_company uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); answer jsonb; today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_company IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies c WHERE c.id=p_company AND c.user_id=actor AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
WITH scoped AS MATERIALIZED (SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived AND (p_company IS NULL OR c.id=p_company) AND private_isg.p05_pilot_can_read(actor,c.id)),
kinds(kind,module) AS (VALUES ('katip_contract','katip_contract'),('annual_work_plan','annual_work_plan'),('annual_work_item','annual_work_plan'),('board','board'),('board_decision','board'),('site_visit','site_visit'),('work_permit','work_permit'),('contractor','contractor'),('emergency_plan','emergency_plan'),('drill','drill'),('appointment','appointment'),('ppe','ppe'),('checklist_run','checklist')),
records AS (SELECT t.company_id, 'checklist_run'::text kind, t.state='open' pending, NULL::date due_on, false review FROM private_isg.checklist_runs t JOIN scoped c ON c.id=t.company_id WHERE t.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'katip_contract'::text kind, (false) pending, (t.ends_before-1) due_on, (t.ends_before IS NULL) review FROM private_isg.katip_contracts t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'annual_work_plan'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.annual_work_plans t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'annual_work_item'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.annual_work_plan_items t JOIN private_isg.annual_work_plans p ON p.plan_id=t.plan_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted UNION ALL SELECT t.company_id company_id, 'board'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.board_meetings t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'board_decision'::text kind, (t.state='open') pending, (CASE WHEN t.state='open' THEN t.due_on END) due_on, (false) review FROM private_isg.board_decisions t JOIN private_isg.board_meetings p ON p.meeting_id=t.meeting_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted AND p.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'site_visit'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.site_visits t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'work_permit'::text kind, (t.state='draft') pending, (NULL::date) due_on, (false) review FROM private_isg.work_permit_forms t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'contractor'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.contractor_organizations t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_archived UNION ALL SELECT t.company_id company_id, 'emergency_plan'::text kind, (false) pending, (t.valid_until) due_on, (t.valid_until IS NULL) review FROM private_isg.emergency_plan_versions t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'drill'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.drill_records t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'appointment'::text kind, (false) pending, (t.ends_before-1) due_on, (false) review FROM private_isg.appointments t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'ppe'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.ppe_handovers t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted),
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
END $$;
NOTIFY pgrst,'reload schema';
