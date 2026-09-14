CREATE FUNCTION private_isg.process_references(p_kind text,p_company uuid,p_id uuid,p_query text,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); rows_ jsonb; row_ jsonb; from_ text; id_ text; title_ text; date_ text; state_ text; company_ text; predicate text; BEGIN
 IF p_company IS NULL OR p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) OR NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF p_kind NOT IN ('training_record','equipment_inspection','nonconformity') THEN
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
 WHEN 'nonconformity' THEN
  PERFORM private_isg.require_nonconformity_company(p_company,false);
  from_:='private_isg.nonconformities t';id_:='t.nonconformity_id';title_:='t.title';date_:='t.opened_on';state_:='t.state';company_:='t.company_id';predicate:='t.state<>''cancelled'' AND t.owner_id=$1';
 END CASE;
 EXECUTE format('SELECT coalesce(jsonb_agg(r),''[]''::jsonb) FROM (SELECT jsonb_build_object(''id'',%s,''company_id'',%s,''company_name'',c.name,''title'',%s,''date'',%s,''expected'','''',''values'',jsonb_build_object(''state'',%s)) r FROM %s JOIN public.companies c ON c.id=%s WHERE %s AND %s=$2 AND ($3 IS NULL OR %s=$3) AND ($4 IS NULL OR %s ILIKE ''%%''||$4||''%%'') ORDER BY %s DESC,%s DESC OFFSET $5 LIMIT 21) q',id_,company_,title_,date_,state_,from_,company_,predicate,company_,id_,title_,date_,id_) INTO rows_ USING actor,p_company,p_id,nullif(btrim(p_query),''),p_offset;
 IF p_id IS NOT NULL AND jsonb_array_length(rows_)=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 RETURN jsonb_build_object('rows',(SELECT coalesce(jsonb_agg(value ORDER BY ord),'[]') FROM jsonb_array_elements(rows_) WITH ORDINALITY x(value,ord) WHERE ord<=20),'has_more',jsonb_array_length(rows_)>20,'workplaces','[]'::jsonb,'employees','[]'::jsonb,'documents','[]'::jsonb,'organizations','[]'::jsonb);
END $$;
CREATE FUNCTION public.isg_pilot_process_references_v1(p_kind text,p_company uuid,p_id uuid,p_query text,p_offset integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.process_references(p_kind,p_company,p_id,p_query,p_offset) $$;
REVOKE ALL ON FUNCTION private_isg.process_references(text,uuid,uuid,text,integer),public.isg_pilot_process_references_v1(text,uuid,uuid,text,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.process_references(text,uuid,uuid,text,integer),public.isg_pilot_process_references_v1(text,uuid,uuid,text,integer) TO authenticated;
CREATE OR REPLACE FUNCTION private_isg.process_mutate(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
END $$;

NOTIFY pgrst,'reload schema';
