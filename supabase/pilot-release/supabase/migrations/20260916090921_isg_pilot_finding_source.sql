SET LOCAL lock_timeout='1s';
-- Immutable source evidence is separate from the editable corrective-action record.
CREATE TABLE private_isg.pilot_finding_sources(
 nonconformity_id uuid PRIMARY KEY REFERENCES private_isg.nonconformities(nonconformity_id),
 company_id uuid NOT NULL,owner_id uuid NOT NULL,analysis_id uuid NOT NULL,finding_id uuid NOT NULL,
 finding_version integer,snapshot jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE private_isg.pilot_finding_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.pilot_finding_sources FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.isg_pilot_finding_file_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; source public.findings; result jsonb; outcome jsonb; fingerprint bytea;
 prior private_isg.nonconformity_receipts; target uuid; method text; score_method text; severity text;
 stamp timestamptz:=clock_timestamp(); source_id uuid;
BEGIN
 actor:=private_isg.require_nonconformity_company(p_company,true);
 IF NOT private_isg.p05_pilot_account_enabled(actor,true) OR NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF p_action IS DISTINCT FROM 'open_from_finding' OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('finding_id','workplace_id','title','severity','risk_band','risk_method','due_on')) THEN RAISE EXCEPTION 'PAYLOAD_NOT_ALLOWED'; END IF;
 fingerprint:=sha256(convert_to(jsonb_build_array('pilot_verified_finding',p_company,p_action,p_operation,p_payload)::text,'UTF8'));
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-nonconformity:'||p_mutation::text,0));
 SELECT * INTO prior FROM private_isg.nonconformity_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
 IF FOUND THEN
  IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  RETURN prior.response||jsonb_build_object('replayed',true);
 END IF;
 source_id:=(p_payload->>'finding_id')::uuid;
 SELECT f.* INTO source FROM public.findings f JOIN public.analyses a ON a.id=f.analysis_id
  WHERE f.id=source_id AND f.user_id=actor AND a.user_id=actor AND NOT coalesce(f.is_user_deleted,false)
    FOR SHARE OF f,a;
 IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company AND id=(p_payload->>'workplace_id')::uuid AND owner_id=actor AND NOT is_archived;
 IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 method:=coalesce(p_payload->>'risk_method','fine_kinney');
 IF method NOT IN ('fine_kinney','matrix_5x5') THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 severity:=coalesce(p_payload->>'severity',private_isg.severity_for_risk_band(CASE method WHEN 'fine_kinney' THEN source.fk_band::text ELSE source.m5_band::text END));
 -- Serialize different clicks on the same company/source, not only network retries.
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':file-finding:'||p_company::text||':'||source_id::text,0));
 outcome:=private_isg.open_nonconformity_record(p_company,(p_payload->>'workplace_id')::uuid,'legacy_finding',source_id::text,
  left(source.title,300),severity,'nonconformity',(stamp AT TIME ZONE 'Europe/Istanbul')::date,(p_payload->>'due_on')::date,NULL,stamp);
 target:=(outcome->>'nonconformity_id')::uuid;
 IF NOT coalesce((outcome->>'replayed')::boolean,false) THEN
  IF method='fine_kinney' AND source.fk_probability IN (0.2,0.5,1,3,6,10) AND source.fk_frequency IN (0.5,1,2,3,6,10) AND source.fk_severity IN (1,3,7,15,40,100) THEN score_method:=method;
  ELSIF method='matrix_5x5' AND source.m5_probability BETWEEN 1 AND 5 AND source.m5_severity BETWEEN 1 AND 5 THEN score_method:=method; END IF;
  PERFORM private_isg.set_nonconformity_detail(target,left(source.description,2000),left(source.recommended_action,2000),left(source.references_text,500),left(source.responsible,200),score_method,
   CASE WHEN score_method='fine_kinney' THEN source.fk_probability END,CASE WHEN score_method='fine_kinney' THEN source.fk_frequency END,CASE WHEN score_method='fine_kinney' THEN source.fk_severity END,
   CASE WHEN score_method='matrix_5x5' THEN source.m5_probability END,CASE WHEN score_method='matrix_5x5' THEN source.m5_severity END,stamp);
  INSERT INTO private_isg.pilot_finding_sources(nonconformity_id,company_id,owner_id,analysis_id,finding_id,finding_version,snapshot)
   VALUES(target,p_company,actor,source.analysis_id,source.id,source.finding_version,
    jsonb_build_object('title',source.title,'description',source.description,'recommended_action',source.recommended_action,'references_text',source.references_text,'responsible',source.responsible,
     'method',method,'fk_probability',source.fk_probability,'fk_frequency',source.fk_frequency,'fk_severity',source.fk_severity,'fk_score',source.fk_score,'fk_band',source.fk_band,
     'm5_probability',source.m5_probability,'m5_severity',source.m5_severity,'m5_score',source.m5_score,'m5_band',source.m5_band,'photo_id',source.photo_id));
 END IF;
 result:=jsonb_build_object('schema_version',1,'action',p_action,'operation_id',p_operation,'row',private_isg.nonconformity_row(p_company,target),'outcome',outcome,'legacy_finding_written',false);
 INSERT INTO private_isg.nonconformity_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response) VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
 RETURN result||jsonb_build_object('replayed',false);
END $$;
REVOKE ALL ON FUNCTION public.isg_pilot_finding_file_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.isg_pilot_finding_file_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
