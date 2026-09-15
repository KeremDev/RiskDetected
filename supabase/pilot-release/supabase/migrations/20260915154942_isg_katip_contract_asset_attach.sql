-- İSG-KATİP Sözleşmeleri: katip_contracts.asset_id already existed
-- (unused — never in process_spec's field whitelist, so process_mutate could
-- never write it and process_row never exposed it). Wires it the same way the
-- emergency plan's own asset_id got wired, and drops the free-text
-- "Sözleşme konumu / referansı" placeholder it stood in for. Table has zero
-- live rows in this pilot, so the column drop carries no data loss.
ALTER TABLE private_isg.katip_contracts DROP COLUMN contract_location;

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
 WHEN 'board' THEN '{"table":"board_meetings","id":"meeting_id","module":"board","title":"agenda","date":"planned_on","fields":["workplace_id","applicability","planned_on","held_on","agenda","attendance","state","cancelled_reason"]}'::jsonb
 WHEN 'board_decision' THEN '{"table":"board_decisions","id":"decision_id","module":"board","parent":"meeting_id","parent_kind":"board","title":"decision_text","date":"due_on","fields":["meeting_id","decision_no","decision_text","responsible_contact","due_on","state"]}'::jsonb
 WHEN 'site_visit' THEN '{"table":"site_visits","id":"visit_id","module":"site_visit","title":"expert_note","date":"visited_on","fields":["workplace_id","visited_on","location_note","expert_note","responsible_contact"]}'::jsonb
 WHEN 'site_observation' THEN '{"table":"site_visit_observations","id":"observation_id","module":"site_visit","parent":"visit_id","parent_kind":"site_visit","title":"note","date":"created_at","fields":["visit_id","note","external_ref"]}'::jsonb
 WHEN 'work_permit' THEN '{"table":"work_permit_forms","id":"permit_id","module":"work_permit","title":"job_description","date":"planned_on","fields":["workplace_id","template_code","job_description","parties","planned_on","work_location","starts_at","ends_at","risk_precautions"]}'::jsonb
 WHEN 'contractor' THEN '{"table":"contractor_organizations","id":"id","module":"contractor","title":"name","date":"code","fields":["code","name","relationship","contact","identifiers","notes"]}'::jsonb
 WHEN 'contractor_engagement' THEN '{"table":"contractor_engagements","id":"id","module":"contractor","title":"description","date":"starts_on","fields":["organization_id","workplace_id","starts_on","ends_before","description"]}'::jsonb
 ELSE NULL END;
END $function$;

CREATE OR REPLACE FUNCTION private_isg.process_row(p_kind text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ DECLARE spec jsonb:=private_isg.process_spec(p_kind); row_ jsonb; parent jsonb; company uuid; BEGIN
IF spec IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
EXECUTE format('SELECT to_jsonb(t) FROM private_isg.%I t WHERE %I=$1',spec->>'table',spec->>'id') INTO row_ USING p_id;
IF row_ IS NULL OR coalesce((row_->>'is_deleted')::boolean,false) OR coalesce((row_->>'is_archived')::boolean,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF spec ? 'parent' THEN parent:=private_isg.process_row(spec->>'parent_kind',(row_->>(spec->>'parent'))::uuid);company:=(parent->>'company_id')::uuid;
ELSE company:=(row_->>'company_id')::uuid; END IF;
PERFORM private_isg.process_guard(p_kind,company,false);
RETURN jsonb_build_object('child_summary',CASE p_kind
 WHEN 'annual_work_plan' THEN (SELECT jsonb_build_object('total',count(*),'open',count(*) FILTER(WHERE state='planned'),'overdue',count(*) FILTER(WHERE state='planned' AND planned_on<(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date)) FROM private_isg.annual_work_plan_items WHERE plan_id=p_id AND NOT is_deleted)
 WHEN 'board' THEN (SELECT jsonb_build_object('total',count(*),'open',count(*) FILTER(WHERE state='open'),'overdue',count(*) FILTER(WHERE state='open' AND due_on<(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date)) FROM private_isg.board_decisions WHERE meeting_id=p_id AND NOT is_deleted)
 ELSE NULL END,'id',p_id,'company_id',company,'company_name',(SELECT name FROM public.companies WHERE id=company),'title',coalesce(row_->>(spec->>'title'),p_kind),'date',coalesce(row_->>(spec->>'date'),''),'values',row_,'workplace_name',(SELECT name FROM private_isg.workplaces WHERE id=(row_->>'workplace_id')::uuid AND company_id=company),
 -- A resolved download location, the same shape the emergency plan row
 -- already exposes, only when this kind's table carries an asset_id.
 'asset_download',CASE WHEN row_ ? 'asset_id' AND row_->>'asset_id' IS NOT NULL THEN
   (SELECT jsonb_build_object('bucket',bucket,'path',immutable_path) FROM private_isg.file_assets WHERE asset_id=(row_->>'asset_id')::uuid) ELSE NULL END,
 'expected',md5((row_||coalesce((SELECT jsonb_build_object('document_id',m.document_id,'related_kind',m.related_kind,'related_id',m.related_id) FROM private_isg.process_record_meta m WHERE m.kind=p_kind AND m.record_id=p_id),jsonb_build_object('document_id',NULL,'related_kind',NULL,'related_id',NULL)))::text),'document_id',(SELECT document_id FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id),'related_kind',(SELECT related_kind FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id),'related_id',(SELECT related_id FROM private_isg.process_record_meta WHERE kind=p_kind AND record_id=p_id));
END $function$;

CREATE OR REPLACE FUNCTION private_isg.process_mutate(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE kind text:=p_payload->>'kind'; spec jsonb:=private_isg.process_spec(kind); actor uuid; id_ uuid; row_ jsonb; vals jsonb:=p_payload->'values'; old_ jsonb; result jsonb; parent jsonb; cols text; expr text; key_ text; hash_ bytea; receipt private_isg.module_edit_receipts; doc uuid; other jsonb; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date; document_ private_isg.documents; stored_ private_isg.document_versions; template_ text; serial_ bigint; version_ integer; source_hash_ text; child_kind_ text; child_spec_ jsonb; child_id_ uuid; children_ jsonb:='[]';
BEGIN
actor:=private_isg.process_guard(kind,p_company,true);
IF p_operation IS NULL OR p_mutation IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>32768 OR p_action IS NULL OR p_action NOT IN ('save','delete','export') OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('kind','id','expected','values','document_id','related_kind','related_id')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
hash_:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':process:'||p_mutation::text,0));
SELECT * INTO receipt FROM private_isg.module_edit_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
IF FOUND THEN IF receipt.request_hash<>hash_ THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF; RETURN receipt.response; END IF;
id_:=(p_payload->>'id')::uuid;
IF id_ IS NOT NULL THEN
 EXECUTE format('SELECT to_jsonb(t) FROM private_isg.%I t WHERE %I=$1 FOR UPDATE',spec->>'table',spec->>'id') INTO old_ USING id_;
 row_:=private_isg.process_row(kind,id_);
 IF (row_->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF row_->>'expected' IS DISTINCT FROM p_payload->>'expected' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
ELSE IF p_action<>'save' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF; END IF;
IF p_action='delete' THEN
 IF kind='annual_work_plan' AND EXISTS(SELECT 1 FROM private_isg.annual_work_plan_items WHERE plan_id=id_ AND NOT is_deleted) OR kind='board' AND EXISTS(SELECT 1 FROM private_isg.board_decisions WHERE meeting_id=id_ AND NOT is_deleted) OR kind='site_visit' AND EXISTS(SELECT 1 FROM private_isg.site_visit_observations WHERE visit_id=id_ AND NOT is_deleted) OR kind='contractor' AND (EXISTS(SELECT 1 FROM private_isg.contractor_engagements WHERE organization_id=id_ AND NOT is_deleted) OR EXISTS(SELECT 1 FROM private_isg.employees WHERE employer_org_id=id_ AND NOT is_archived)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPENDENT_RECORDS'; END IF;
 EXECUTE format('UPDATE private_isg.%I SET %I=true WHERE %I=$1',spec->>'table',CASE WHEN kind='contractor' THEN 'is_archived' ELSE 'is_deleted' END,spec->>'id') USING id_;
 result:=jsonb_build_object('deleted',true);
ELSIF p_action='export' THEN
 child_kind_:=CASE kind WHEN 'annual_work_plan' THEN 'annual_work_item' WHEN 'board' THEN 'board_decision' WHEN 'site_visit' THEN 'site_observation' END;
 IF child_kind_ IS NOT NULL THEN
  child_spec_:=private_isg.process_spec(child_kind_);
  FOR child_id_ IN EXECUTE format('SELECT %I FROM private_isg.%I WHERE %I=$1 AND NOT is_deleted ORDER BY %I FOR SHARE',child_spec_->>'id',child_spec_->>'table',child_spec_->>'parent',child_spec_->>'id') USING id_ LOOP
   children_:=children_||jsonb_build_array(private_isg.process_row(child_kind_,child_id_));
  END LOOP;
 END IF;
 result:=row_||jsonb_build_object('children',children_,'child_kind',child_kind_,'source','expert_record');
 source_hash_:=md5(result::text); template_:='process_'||kind;
 INSERT INTO private_isg.document_templates(template_code,source_domain,title) VALUES(template_,'module',kind) ON CONFLICT DO NOTHING;
 INSERT INTO private_isg.document_template_versions(template_code,version,status,approved_by,approval_note,published_at) VALUES(template_,1,'published',actor,'Expert-requested record export; blank signatures, no regulatory approval claim',now()) ON CONFLICT DO NOTHING;
 INSERT INTO private_isg.documents(company_id,owner_id,workplace_id,source_domain,source_ref,template_code) VALUES(p_company,actor,(row_->'values'->>'workplace_id')::uuid,'module',kind||':'||id_::text,template_) ON CONFLICT(company_id,source_domain,source_ref,template_code) DO NOTHING;
 SELECT * INTO document_ FROM private_isg.documents WHERE company_id=p_company AND source_domain='module' AND source_ref=kind||':'||id_::text AND template_code=template_ FOR UPDATE;
 SELECT * INTO stored_ FROM private_isg.document_versions WHERE document_id=document_.document_id AND version=document_.current_version;
 IF FOUND AND stored_.snapshot->>'source_hash'=source_hash_ THEN result:=stored_.snapshot;
 ELSE
  INSERT INTO private_isg.education_document_counters(scope,year,next_value) VALUES('MOD',extract(year FROM today)::int,1) ON CONFLICT DO NOTHING;
  UPDATE private_isg.education_document_counters SET next_value=next_value+1 WHERE scope='MOD' AND year=extract(year FROM today)::int RETURNING next_value-1 INTO serial_;
  version_:=document_.current_version+1;
  result:=result||jsonb_build_object('document_id',document_.document_id,'number','MOD-'||extract(year FROM today)::int||'-'||serial_,'revision',version_,'source_hash',source_hash_,'exported_on',today);
  INSERT INTO private_isg.document_versions(document_id,version,template_version,document_no,source_kind,snapshot,snapshot_sha256,finalized_by,finalized_at,mutation_id) VALUES(document_.document_id,version_,1,result->>'number','structured',result,sha256(convert_to(result::text,'UTF8')),actor,now(),p_mutation);
  UPDATE private_isg.documents SET current_version=version_ WHERE document_id=document_.document_id;
 END IF;

ELSE
 IF jsonb_typeof(vals) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(vals) k WHERE NOT (spec->'fields' ? k)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
 IF spec ? 'parent' THEN
  parent:=private_isg.process_row(spec->>'parent_kind',(vals->>(spec->>'parent'))::uuid);
  IF (parent->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF vals ? 'workplace_id' THEN
  PERFORM 1 FROM private_isg.workplaces WHERE id=(vals->>'workplace_id')::uuid AND company_id=p_company AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF kind='annual_work_item' THEN
  IF extract(year FROM (vals->>'planned_on')::date)<>(parent->'values'->>'plan_year')::integer THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_YEAR_MISMATCH'; END IF;
  IF parent->'values'->>'state'<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_CLOSED'; END IF;
  IF (vals->>'performed_on')::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
 END IF;
 IF kind='board' THEN
  vals:=vals||jsonb_build_object('counts_towards_legal_score',vals->>'applicability'='mandatory');
  IF (vals->>'held_on')::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
  IF jsonb_typeof(vals->'agenda')<>'array' OR jsonb_array_length(vals->'agenda')=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 END IF;
 IF kind='site_visit' AND (vals->>'visited_on')::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
 IF kind='work_permit' THEN
  IF vals->>'template_code' NOT IN ('general','hot_work','work_at_height','confined_space','electrical') OR (vals->>'ends_at')::timestamptz<=(vals->>'starts_at')::timestamptz THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  vals:=vals||'{"template_version":1}'::jsonb;
 END IF;
 IF kind IN ('board','work_permit') THEN
  key_:=CASE WHEN kind='board' THEN 'attendance' ELSE 'parties' END;
  IF vals->key_ IS NOT NULL AND vals->key_<>'null'::jsonb THEN
   IF jsonb_typeof(vals->key_)<>'array' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(vals->key_) person WHERE NOT EXISTS(SELECT 1 FROM private_isg.employees e WHERE e.id=(person->>'id')::uuid AND e.company_id=p_company AND NOT e.is_archived)) OR (SELECT count(*)<>count(DISTINCT person->>'id') FROM jsonb_array_elements(vals->key_) person) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
   vals:=jsonb_set(vals,ARRAY[key_],(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'name',e.full_name) ORDER BY ord),'[]') FROM jsonb_array_elements(vals->key_) WITH ORDINALITY x(person,ord) JOIN private_isg.employees e ON e.id=(person->>'id')::uuid));
  END IF;
 END IF;
 IF kind='contractor_engagement' THEN
  PERFORM 1 FROM private_isg.contractor_organizations WHERE id=(vals->>'organization_id')::uuid AND company_id=p_company AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 -- Only a clean, owned asset may be attached — the same rule the emergency
 -- plan enforces on its own asset_id.
 IF vals ? 'asset_id' AND vals->>'asset_id' IS NOT NULL THEN
  PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
    WHERE fa.asset_id=(vals->>'asset_id')::uuid AND fa.scan_status='clean' AND fle.company_id=p_company AND fle.owner_id=actor;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 doc:=(p_payload->>'document_id')::uuid;
 IF doc IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.document_obligations WHERE obligation_id=doc AND company_id=p_company AND owner_id=actor AND NOT is_archived) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF p_payload->>'related_id' IS NOT NULL THEN
  other:=private_isg.process_references(p_payload->>'related_kind',p_company,(p_payload->>'related_id')::uuid,NULL,0)->'rows'->0;
  IF (other->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF id_ IS NULL THEN
  id_:=gen_random_uuid();vals:=vals||jsonb_build_object(spec->>'id',id_);
  IF NOT (spec ? 'parent') THEN vals:=vals||jsonb_build_object('company_id',p_company,'owner_id',actor); END IF;
  SELECT string_agg(format('%I',k),',' ORDER BY k),string_agg(format('r.%I',k),',' ORDER BY k) INTO cols,expr FROM jsonb_object_keys(vals) k;
  EXECUTE format('INSERT INTO private_isg.%I(%s) SELECT %s FROM jsonb_populate_record(NULL::private_isg.%I,$1) r',spec->>'table',cols,expr,spec->>'table') USING vals;
 ELSE
  SELECT string_agg(format('%I=r.%I',k,k),',' ORDER BY k) INTO cols FROM jsonb_object_keys(vals) k;
  IF kind IN ('contractor','contractor_engagement') THEN cols:=cols||',version=t.version+1'; END IF;
  EXECUTE format('UPDATE private_isg.%I t SET %s FROM jsonb_populate_record(NULL::private_isg.%I,$1) r WHERE t.%I=$2',spec->>'table',cols,spec->>'table',spec->>'id') USING vals,id_;
 END IF;
 INSERT INTO private_isg.process_record_meta(kind,record_id,company_id,document_id,related_kind,related_id) VALUES(kind,id_,p_company,doc,p_payload->>'related_kind',(p_payload->>'related_id')::uuid) ON CONFLICT ON CONSTRAINT process_record_meta_pkey DO UPDATE SET document_id=EXCLUDED.document_id,related_kind=EXCLUDED.related_kind,related_id=EXCLUDED.related_id;
 result:=private_isg.process_row(kind,id_);
END IF;
IF old_ IS NOT NULL THEN INSERT INTO private_isg.process_record_history(kind,record_id,company_id,actor_id,before_snapshot) VALUES(kind,id_,p_company,actor,old_); END IF;
INSERT INTO private_isg.module_edit_receipts VALUES(actor,p_mutation,hash_,result);
RETURN result;
END $function$;
