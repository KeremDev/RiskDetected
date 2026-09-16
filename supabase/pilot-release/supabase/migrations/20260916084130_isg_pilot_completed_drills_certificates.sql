-- Pilot-owned performed drills and employee certificates. No planning workflow.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';
ALTER TABLE private_isg.module_registry DROP CONSTRAINT module_registry_module_check;
ALTER TABLE private_isg.module_registry ADD CONSTRAINT module_registry_module_check CHECK(module IN ('emergency_plan','drill','equipment','ppe','appointment','katip_contract','annual_work_plan','board','work_permit','site_visit','contractor','approved_notebook','personnel_certificate'));
INSERT INTO private_isg.module_registry(module,read_enabled,write_enabled) VALUES('personnel_certificate',true,true);
CREATE TABLE private_isg.pilot_completed_drills (
 record_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL,owner_id uuid NOT NULL,
 workplace_id uuid NOT NULL, held_on date NOT NULL CHECK(isfinite(held_on)),
 drill_type text NOT NULL CHECK(drill_type IN ('emergency','fire')),
 announcement text NOT NULL CHECK(announcement IN ('announced','unannounced')),
 bekra boolean NOT NULL DEFAULT false, duration_minutes integer CHECK(duration_minutes BETWEEN 1 AND 1440),
 scenario text NOT NULL CHECK(length(btrim(scenario)) BETWEEN 1 AND 8000),note text CHECK(length(note)<=8000),
 photo_ids uuid[] NOT NULL DEFAULT '{}',asset_id uuid REFERENCES private_isg.file_assets(asset_id),
 calculated_due date NOT NULL,valid_until date NOT NULL CHECK(isfinite(valid_until) AND valid_until>held_on),
 due_override boolean NOT NULL DEFAULT false,hazard_snapshot text,period_months integer NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),is_deleted boolean NOT NULL DEFAULT false,
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id),
 FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id),
 CHECK(cardinality(photo_ids)<=10)
);
CREATE TABLE private_isg.pilot_personnel_certificates (
 record_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
 employee_id uuid NOT NULL REFERENCES private_isg.employees(id),
 certificate_kind text NOT NULL CHECK(certificate_kind IN ('first_aid','myk','custom')),
 title text NOT NULL CHECK(length(btrim(title)) BETWEEN 1 AND 200),
 issued_on date NOT NULL CHECK(isfinite(issued_on)),valid_until date NOT NULL CHECK(isfinite(valid_until) AND valid_until>issued_on),
 calculated_due date,due_override boolean NOT NULL DEFAULT false,
 asset_id uuid REFERENCES private_isg.file_assets(asset_id),note text CHECK(length(note)<=4000),
 created_at timestamptz NOT NULL DEFAULT now(),is_deleted boolean NOT NULL DEFAULT false,
 FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id)
);
CREATE INDEX pilot_completed_drills_company ON private_isg.pilot_completed_drills(company_id,held_on DESC) WHERE NOT is_deleted;
CREATE INDEX pilot_personnel_certificates_person ON private_isg.pilot_personnel_certificates(company_id,employee_id,valid_until) WHERE NOT is_deleted;
ALTER TABLE private_isg.pilot_completed_drills ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.pilot_personnel_certificates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.pilot_completed_drills,private_isg.pilot_personnel_certificates FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_isg.pilot_record_validate() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE actor uuid; asset uuid; wp jsonb; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
 actor:=private_isg.process_guard(CASE TG_TABLE_NAME WHEN 'pilot_completed_drills' THEN 'completed_drill' ELSE 'personnel_certificate' END,NEW.company_id,true);
 IF NEW.owner_id<>actor THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF TG_OP='UPDATE' AND (NEW.company_id<>OLD.company_id OR NEW.owner_id<>OLD.owner_id) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 -- Deleting retains its historical snapshots, including archived attachments/persons.
 IF TG_OP='UPDATE' AND NEW.is_deleted THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME='pilot_completed_drills' THEN
  IF NEW.held_on>today THEN RAISE EXCEPTION 'FUTURE_DATE'; END IF;
  SELECT to_jsonb(w) INTO wp FROM private_isg.workplaces w WHERE w.id=NEW.workplace_id AND w.company_id=NEW.company_id AND NOT w.is_archived;
  IF wp IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  -- Drill interval is annual, mining six-monthly; hazard class governs the plan,
  -- not this interval. BEKRA is recorded separately, never extends this deadline.
  NEW.period_months:=CASE WHEN coalesce(wp->>'nace_code','') ~ '^0[5-9]' THEN 6 ELSE 12 END;
  NEW.hazard_snapshot:=wp->>'hazard_class';
  NEW.calculated_due:=(NEW.held_on+make_interval(months=>NEW.period_months))::date;
  IF NOT NEW.due_override OR NEW.valid_until IS NULL THEN NEW.valid_until:=NEW.calculated_due;NEW.due_override:=false; END IF;
  IF NEW.photo_ids IS NULL OR cardinality(NEW.photo_ids)>10 OR cardinality(NEW.photo_ids)<>(SELECT count(DISTINCT x) FROM unnest(NEW.photo_ids) x) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  FOREACH asset IN ARRAY NEW.photo_ids LOOP
   IF NOT EXISTS(SELECT 1 FROM private_isg.file_assets a JOIN private_isg.file_library_entries f ON f.asset_id=a.asset_id WHERE a.asset_id=asset AND a.owner_id=actor AND a.company_id=NEW.company_id AND a.scan_status='clean' AND a.detected_type LIKE 'image/%' AND f.owner_id=actor AND f.company_id=NEW.company_id AND NOT f.is_archived) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  END LOOP;
 ELSE
  IF NEW.issued_on>today THEN RAISE EXCEPTION 'FUTURE_DATE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM private_isg.employees WHERE id=NEW.employee_id AND company_id=NEW.company_id AND NOT is_archived) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  NEW.calculated_due:=CASE WHEN NEW.certificate_kind='first_aid' THEN (NEW.issued_on+interval '3 years')::date END;
  IF NEW.calculated_due IS NOT NULL AND (NOT NEW.due_override OR NEW.valid_until IS NULL) THEN NEW.valid_until:=NEW.calculated_due;NEW.due_override:=false; END IF;
 END IF;
 IF NEW.asset_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.file_assets a JOIN private_isg.file_library_entries f ON f.asset_id=a.asset_id WHERE a.asset_id=NEW.asset_id AND a.owner_id=actor AND a.company_id=NEW.company_id AND a.scan_status='clean' AND (TG_TABLE_NAME<>'pilot_completed_drills' OR a.detected_type='application/pdf') AND f.owner_id=actor AND f.company_id=NEW.company_id AND NOT f.is_archived) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.pilot_record_validate() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER pilot_completed_drills_validate BEFORE INSERT OR UPDATE ON private_isg.pilot_completed_drills FOR EACH ROW EXECUTE FUNCTION private_isg.pilot_record_validate();
CREATE TRIGGER pilot_personnel_certificates_validate BEFORE INSERT OR UPDATE ON private_isg.pilot_personnel_certificates FOR EACH ROW EXECUTE FUNCTION private_isg.pilot_record_validate();
CREATE OR REPLACE FUNCTION private_isg.process_spec(p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$ BEGIN
RETURN CASE p_kind
 WHEN 'katip_contract' THEN '{"table":"katip_contracts","id":"contract_id","module":"katip_contract","title":"counterparty","date":"starts_on","fields":["workplace_id","counterparty","expert_contact","scope","starts_on","ends_before","declared_monthly_minutes","declared_note","asset_id"]}'::jsonb
 WHEN 'annual_work_plan' THEN '{"table":"annual_work_plans","id":"plan_id","module":"annual_work_plan","title":"plan_year","date":"created_at","fields":["workplace_id","plan_year"]}'::jsonb
 WHEN 'annual_work_item' THEN '{"table":"annual_work_plan_items","id":"item_id","module":"annual_work_plan","parent":"plan_id","parent_kind":"annual_work_plan","title":"activity","date":"planned_on","fields":["plan_id","activity","responsible_contact","planned_on","performed_on","state","carry_over_reason"]}'::jsonb
 WHEN 'board' THEN '{"table":"board_meetings","id":"meeting_id","module":"board","title":"agenda","date":"planned_on","fields":["workplace_id","applicability","planned_on","held_on","agenda","attendance","state","cancelled_reason","minutes_asset_id"]}'::jsonb
 WHEN 'board_decision' THEN '{"table":"board_decisions","id":"decision_id","module":"board","parent":"meeting_id","parent_kind":"board","title":"decision_text","date":"due_on","fields":["meeting_id","decision_no","decision_text","responsible_contact","due_on","state"]}'::jsonb
 WHEN 'completed_drill' THEN '{"table":"pilot_completed_drills","id":"record_id","module":"drill","title":"scenario","date":"held_on","fields":["workplace_id","held_on","drill_type","announcement","bekra","duration_minutes","scenario","note","photo_ids","asset_id","valid_until","due_override"]}'::jsonb
 WHEN 'personnel_certificate' THEN '{"table":"pilot_personnel_certificates","id":"record_id","module":"personnel_certificate","title":"title","date":"issued_on","fields":["employee_id","certificate_kind","title","issued_on","valid_until","due_override","asset_id","note"]}'::jsonb
 WHEN 'approved_notebook'  THEN '{"table":"pilot_notebook_images","id":"record_id","module":"approved_notebook","title":"title","date":"created_at","fields":["title","note","asset_id"]}'::jsonb
 WHEN 'site_visit' THEN '{"table":"site_visits","id":"visit_id","module":"site_visit","title":"expert_note","date":"visited_on","fields":["workplace_id","visited_on","location_note","expert_note","responsible_contact","duration_minutes","visit_asset_id"]}'::jsonb
 WHEN 'site_observation' THEN '{"table":"site_visit_observations","id":"observation_id","module":"site_visit","parent":"visit_id","parent_kind":"site_visit","title":"note","date":"created_at","fields":["visit_id","note","external_ref"]}'::jsonb
 WHEN 'work_permit' THEN '{"table":"work_permit_forms","id":"permit_id","module":"work_permit","title":"job_description","date":"planned_on","fields":["workplace_id","template_code","job_description","parties","planned_on","work_location","starts_at","ends_at","risk_precautions"]}'::jsonb
 WHEN 'contractor' THEN '{"table":"contractor_organizations","id":"id","module":"contractor","title":"name","date":"code","fields":["code","name","relationship","contact","identifiers","notes"]}'::jsonb
 WHEN 'contractor_engagement' THEN '{"table":"contractor_engagements","id":"id","module":"contractor","title":"description","date":"starts_on","fields":["organization_id","workplace_id","starts_on","ends_before","description"]}'::jsonb
 ELSE NULL END;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.process_read(p_kind text, p_company uuid, p_id uuid, p_parent uuid, p_query text, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ DECLARE actor uuid; spec jsonb:=private_isg.process_spec(p_kind); ids uuid[]; rows_ jsonb:='[]'; id_ uuid; join_ text:=''; where_ text; parent_spec jsonb; BEGIN
actor:=private_isg.process_guard(p_kind,p_company,false);
IF p_id IS NOT NULL THEN RETURN private_isg.process_row(p_kind,p_id); END IF;
IF p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
IF spec ? 'parent' THEN
 parent_spec:=private_isg.process_spec(spec->>'parent_kind');
 join_:=format(' JOIN private_isg.%I p ON p.%I=t.%I ',parent_spec->>'table',parent_spec->>'id',spec->>'parent');
 where_:='p.company_id';
ELSE where_:='t.company_id'; END IF;
EXECUTE format('SELECT array_agg(id) FROM (SELECT t.%I id FROM private_isg.%I t %s JOIN public.companies c ON c.id=%s WHERE c.user_id=$1 AND private_isg.p05_pilot_can_read($1,c.id) AND ($2 IS NULL OR c.id=$2) AND NOT coalesce((to_jsonb(t)->>''is_deleted'')::boolean,false) AND NOT coalesce((to_jsonb(t)->>''is_archived'')::boolean,false) %s AND ($3 IS NULL OR to_jsonb(t)->>%L ILIKE ''%%''||$3||''%%'') %s ORDER BY t.%I DESC OFFSET $4 LIMIT 21) q',spec->>'id',spec->>'table',join_,where_,CASE WHEN spec ? 'parent' THEN 'AND NOT p.is_deleted' ELSE '' END,spec->>'title',CASE WHEN spec ? 'parent' THEN format('AND ($5 IS NULL OR t.%I=$5)',spec->>'parent') WHEN p_kind='personnel_certificate' THEN 'AND ($5 IS NULL OR t.employee_id=$5)' WHEN p_kind='contractor_engagement' THEN 'AND ($5 IS NULL OR t.organization_id=$5)' ELSE '' END,spec->>'id') INTO ids USING actor,p_company,nullif(btrim(p_query),''),p_offset,p_parent;
FOREACH id_ IN ARRAY coalesce(ids[1:20],ARRAY[]::uuid[]) LOOP rows_:=rows_||jsonb_build_array(private_isg.process_row(p_kind,id_)); END LOOP;
RETURN jsonb_build_object('rows',rows_,'has_more',coalesce(cardinality(ids)>20,false),
 'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]') FROM private_isg.workplaces WHERE company_id=p_company AND NOT is_archived),
 'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) ORDER BY full_name),'[]') FROM private_isg.employees WHERE company_id=p_company AND NOT is_archived),
 'documents',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',obligation_id,'name',title) ORDER BY title),'[]') FROM private_isg.document_obligations WHERE company_id=p_company AND NOT is_archived),
 'organizations',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]') FROM private_isg.contractor_organizations WHERE company_id=p_company AND NOT is_archived));
END $function$
;
NOTIFY pgrst,'reload schema';

CREATE OR REPLACE FUNCTION private_isg.pilot_process_attachment(p_kind text,p_record uuid,p_field text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); row_ jsonb; entry_ uuid; asset_ uuid;
BEGIN
 IF p_kind='completed_drill' AND p_field LIKE 'photo_ids:%' THEN
  row_:=private_isg.process_row(p_kind,p_record);
  asset_:=split_part(p_field,':',2)::uuid;
  IF NOT (row_->'values'->'photo_ids' ? asset_::text) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 ELSE
 IF p_field IS NULL OR p_field NOT IN ('asset_id','minutes_asset_id','visit_asset_id') OR NOT (private_isg.process_spec(p_kind)->'fields' ? p_field) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 row_:=private_isg.process_row(p_kind,p_record);
 asset_:=(row_->'values'->>p_field)::uuid;
 END IF;
 SELECT fle.entry_id INTO entry_ FROM private_isg.file_library_entries fle JOIN private_isg.file_assets fa ON fa.asset_id=fle.asset_id
 WHERE fle.asset_id=asset_ AND fle.owner_id=actor AND fle.company_id=(row_->>'company_id')::uuid
   AND NOT fle.is_archived AND fa.owner_id=actor AND fa.company_id=fle.company_id AND fa.scan_status='clean'
 ORDER BY fle.created_at DESC,fle.entry_id LIMIT 1;
 IF entry_ IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 RETURN jsonb_build_object('entry_id',entry_);
END $$;
