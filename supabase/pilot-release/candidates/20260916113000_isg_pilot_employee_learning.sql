-- Cumulative instruction read model; never creates attendance, exams or certificates.
SET LOCAL lock_timeout='1s';
CREATE FUNCTION private_isg.pilot_learning_totals(p_scopes jsonb,p_package jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE b record; s jsonb; t jsonb; preset jsonb; topics jsonb; missing jsonb; rows_ jsonb:='[]';
 total_ int; g4_ int; common_ int; required_ int; g4required_ int; commonrequired_ int; n int; excluded_ int; code_ text; dates_ jsonb; due_ date; context_missing boolean;
BEGIN
 FOR b IN SELECT value->>'workplace_id' workplace,value->>'group_name' group_name,value->>'cycle' cycle,value->>'preset_code' preset_code,value->>'workplace_name' workplace_name,
 jsonb_agg(value ORDER BY value->>'held_on',value->>'id') scopes FROM jsonb_array_elements(p_scopes)
 WHERE value->>'cycle' IN ('initial','periodic_repeat')
 GROUP BY value->>'workplace_id',value->>'group_name',value->>'cycle',value->>'preset_code',value->>'workplace_name' LOOP
  SELECT x INTO preset FROM jsonb_array_elements(p_package->'presets') x WHERE x->>'code'=b.preset_code;
  IF preset IS NULL THEN CONTINUE; END IF;
  total_:=0;g4_:=0;common_:=0;excluded_:=0;topics:='{}';dates_:='[]';due_:=NULL;context_missing:=false;
  required_:=(preset->>'default_instruction_minutes')::int;
  g4required_:=(preset->'group4'->>'budget_instruction_minutes')::int;
  commonrequired_:=CASE WHEN b.cycle='initial' THEN (preset->'common_groups_review_guard'->>'reference_instruction_minutes')::int ELSE 0 END;
  FOR s IN SELECT value FROM jsonb_array_elements(b.scopes) LOOP
   -- An inconsistent schedule is retained in education but never credited here.
   IF coalesce(s->'issues','[]') ?| ARRAY['LESSON_TOPIC_MISMATCH','LESSON_BREAK_INVALID'] THEN excluded_:=excluded_+1; CONTINUE; END IF;
   dates_:=dates_||jsonb_build_array(jsonb_build_object('session_id',s->>'_session_id','title',s->>'_title','held_on',s->>'held_on','instruction_minutes',s->'instruction_minutes'));
   due_:=greatest(due_,(s->>'valid_until')::date);
   FOR t IN SELECT value FROM jsonb_array_elements(s->'topics') LOOP
    n:=(t->>'instruction_minutes')::int;
    IF t->>'group'='G4' AND (length(btrim(coalesce(s->>'context_note','')))=0 OR (preset->>'hazard_class'<>'low' AND t->>'method'<>'face_to_face')) THEN
     context_missing:=true; CONTINUE;
    END IF;
    code_:=coalesce(nullif(t->>'parent_code',''),t->>'code');
    topics:=jsonb_set(topics,ARRAY[code_],to_jsonb(coalesce((topics->>code_)::int,0)+n));
    total_:=total_+n;
    IF t->>'group'='G4' THEN g4_:=g4_+n; ELSE common_:=common_+n; END IF;
   END LOOP;
  END LOOP;
  SELECT coalesce(jsonb_agg(jsonb_build_object('code',x->>'code','title',x->>'legal_label') ORDER BY (x->>'sort_order')::int),'[]') INTO missing FROM jsonb_array_elements(p_package->'topics') x WHERE coalesce((topics->>(x->>'code'))::int,0)=0;
  rows_:=rows_||jsonb_build_array(jsonb_build_object('id',b.workplace||':'||b.group_name||':'||b.preset_code,'workplace_name',b.workplace_name,'group_name',b.group_name,'cycle',b.cycle,'profile',preset->>'label',
   'required_minutes',required_,'received_minutes',total_,'remaining_minutes',greatest(0,required_-total_),
   'group4_remaining_minutes',greatest(0,g4required_-g4_),'common_remaining_minutes',greatest(0,commonrequired_-common_),
   'missing_topics',missing,'sessions',dates_,'excluded_sessions',excluded_,'context_missing',context_missing,'valid_until',due_,
   'complete',total_>=required_ AND g4_>=g4required_ AND common_>=commonrequired_ AND jsonb_array_length(missing)=0));
 END LOOP;
 RETURN rows_;
END $$;
REVOKE ALL ON FUNCTION private_isg.pilot_learning_totals(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_isg.pilot_employee_learning(p_company uuid,p_employee uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.process_guard('personnel_certificate',p_company,false); scopes_ jsonb; package_ jsonb; expired_ int; legacy_ int; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
 IF p_company IS NULL OR NOT EXISTS(SELECT 1 FROM private_isg.employees WHERE id=p_employee AND company_id=p_company AND owner_id=actor) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF NOT coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='training'),false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 SELECT content_package INTO package_ FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1;
 IF package_ IS NULL THEN RAISE EXCEPTION 'PROFILE_UNAVAILABLE'; END IF;
 SELECT coalesce(jsonb_agg(s||jsonb_build_object('_session_id',t.id,'_title',t.title)) FILTER(WHERE (s->>'valid_until')::date>=today),'[]'),
 count(*) FILTER(WHERE (s->>'valid_until')::date<today) INTO scopes_,expired_
 FROM private_isg.pilot_training_sessions t CROSS JOIN LATERAL jsonb_array_elements(t.education->'scopes') s
 WHERE t.owner_id=actor AND t.deleted_at IS NULL AND (s->>'company_id')::uuid=p_company
 AND s->>'cycle' IN ('initial','periodic_repeat') AND EXISTS(SELECT 1 FROM jsonb_array_elements(s->'participants') p WHERE (p->>'id')::uuid=p_employee);
 -- Legacy rows have no reliable topic breakdown; do not invent credit from them.
 SELECT count(*) INTO legacy_ FROM private_isg.pilot_training_records r WHERE r.company_id=p_company AND r.owner_id=actor AND r.state='completed' AND r.session_id IS NULL;
 RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'employee_id',p_employee,
 'groups',private_isg.pilot_learning_totals(scopes_,package_),'expired_scopes',expired_,
 'legacy_company_records',legacy_,'source','expert_record','certificate_issued',false);
END $$;
CREATE FUNCTION public.isg_pilot_employee_learning_v1(p_company uuid,p_employee uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.pilot_employee_learning(p_company,p_employee) $$;
REVOKE ALL ON FUNCTION private_isg.pilot_employee_learning(uuid,uuid),public.isg_pilot_employee_learning_v1(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.pilot_employee_learning(uuid,uuid),public.isg_pilot_employee_learning_v1(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
