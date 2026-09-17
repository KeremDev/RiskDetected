-- D8 workspace analysis result, verified filing and export jobs.
-- NOT DEPLOYED; `analysis_exports` remains OFF by default.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='35s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check CHECK(entity_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit',
   'notebook_archive','file_entry','file_reference','analysis','export'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check CHECK(aggregate_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit',
   'notebook_archive','file_entry','file_reference','analysis','export'));

ALTER TABLE private_isg.nonconformities DROP CONSTRAINT nonconformities_source_kind_check;
ALTER TABLE private_isg.nonconformities ADD CONSTRAINT nonconformities_source_kind_check
  CHECK(source_kind IN ('checklist','risk_version','legacy_finding','manual','analysis_finding','analysis_expert_item'));

CREATE TABLE private_isg.workspace_analyses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  ai_job_id uuid NOT NULL UNIQUE REFERENCES private_isg.workspace_ai_jobs(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 300),
  kind text NOT NULL CHECK(kind IN ('photo','document','record_set')),
  status text NOT NULL DEFAULT 'ready' CHECK(status IN ('ready','archived')),
  primary_method text NOT NULL CHECK(primary_method IN ('fine_kinney','matrix_5x5')),
  output_asset_id uuid NOT NULL,
  result_hash bytea NOT NULL CHECK(octet_length(result_hash)=32),
  result_version bigint NOT NULL DEFAULT 1 CHECK(result_version BETWEEN 1 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,output_asset_id) REFERENCES private_isg.workspace_file_assets(workspace_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_analysis_findings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  analysis_id uuid NOT NULL,
  source_key text NOT NULL CHECK(octet_length(source_key) BETWEEN 1 AND 120),
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 10000),
  display_order integer NOT NULL CHECK(display_order BETWEEN 1 AND 10000),
  item_class text NOT NULL CHECK(item_class IN ('observed_finding','assurance_requirement','verification_request')),
  is_scored boolean NOT NULL,
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 300),
  category text CHECK(category IS NULL OR octet_length(category)<=160),
  description text CHECK(description IS NULL OR octet_length(description)<=6000),
  recommended_action text CHECK(recommended_action IS NULL OR octet_length(recommended_action)<=6000),
  references_text text CHECK(references_text IS NULL OR octet_length(references_text)<=2000),
  responsible text CHECK(responsible IS NULL OR octet_length(responsible)<=200),
  fk_probability numeric,
  fk_frequency numeric,
  fk_severity numeric,
  fk_score numeric,
  fk_band text NOT NULL DEFAULT 'unknown' CHECK(fk_band IN ('critical','high','medium','low','unknown')),
  m5_probability integer,
  m5_severity integer,
  m5_score integer,
  m5_band text NOT NULL DEFAULT 'unknown' CHECK(m5_band IN ('critical','high','medium','low','unknown')),
  source_photo_indices integer[] NOT NULL DEFAULT '{}',
  version bigint NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(analysis_id,source_key),
  UNIQUE(analysis_id,ordinal),
  UNIQUE(workspace_id,company_id,analysis_id,id),
  FOREIGN KEY(workspace_id,company_id,analysis_id)
    REFERENCES private_isg.workspace_analyses(workspace_id,company_id,id) ON DELETE RESTRICT,
  CHECK((is_scored AND item_class='observed_finding' AND fk_probability IS NOT NULL AND
         fk_frequency IS NOT NULL AND fk_severity IS NOT NULL AND m5_probability IS NOT NULL AND m5_severity IS NOT NULL)
    OR (NOT is_scored AND item_class IN ('assurance_requirement','verification_request') AND
        fk_probability IS NULL AND fk_frequency IS NULL AND fk_severity IS NULL AND
        m5_probability IS NULL AND m5_severity IS NULL AND fk_band='unknown' AND m5_band='unknown'))
);

CREATE TABLE private_isg.workspace_analysis_expert_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  analysis_id uuid NOT NULL,
  source_key text NOT NULL CHECK(octet_length(source_key) BETWEEN 1 AND 120),
  display_order integer NOT NULL CHECK(display_order BETWEEN 1 AND 10000),
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 300),
  body text NOT NULL CHECK(octet_length(body) BETWEEN 1 AND 6000),
  recommendation text CHECK(recommendation IS NULL OR octet_length(recommendation)<=6000),
  references_text text CHECK(references_text IS NULL OR octet_length(references_text)<=2000),
  source_finding_keys text[] NOT NULL DEFAULT '{}',
  version bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(analysis_id,source_key),
  UNIQUE(workspace_id,company_id,analysis_id,id),
  FOREIGN KEY(workspace_id,company_id,analysis_id)
    REFERENCES private_isg.workspace_analyses(workspace_id,company_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_analysis_training_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  analysis_id uuid NOT NULL,
  source_key text NOT NULL CHECK(octet_length(source_key) BETWEEN 1 AND 120),
  catalog_code text CHECK(catalog_code IS NULL OR octet_length(catalog_code)<=100),
  display_order integer NOT NULL CHECK(display_order BETWEEN 1 AND 10000),
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 300),
  audience text CHECK(audience IS NULL OR octet_length(audience)<=300),
  body text CHECK(body IS NULL OR octet_length(body)<=6000),
  duration_minutes integer CHECK(duration_minutes IS NULL OR duration_minutes BETWEEN 1 AND 100000),
  source_finding_keys text[] NOT NULL DEFAULT '{}',
  version bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(analysis_id,source_key),
  UNIQUE(workspace_id,company_id,analysis_id,id),
  FOREIGN KEY(workspace_id,company_id,analysis_id)
    REFERENCES private_isg.workspace_analyses(workspace_id,company_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_analysis_filed_sources (
  nonconformity_id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  source_scope text NOT NULL CHECK(source_scope IN ('workspace','personal')),
  source_analysis_id uuid NOT NULL,
  source_item_kind text NOT NULL CHECK(source_item_kind IN ('finding','expert_item')),
  source_item_id uuid NOT NULL,
  source_version bigint NOT NULL CHECK(source_version>0),
  snapshot jsonb NOT NULL,
  filed_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,source_scope,source_item_kind,source_item_id),
  FOREIGN KEY(workspace_id,company_id,nonconformity_id)
    REFERENCES private_isg.nonconformities(workspace_id,company_id,nonconformity_id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_export_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  analysis_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  permission_revision bigint NOT NULL CHECK(permission_revision>=0),
  format text NOT NULL CHECK(format IN ('pdf','xlsx')),
  selection jsonb NOT NULL,
  source_snapshot jsonb NOT NULL,
  request_hash bytea NOT NULL CHECK(octet_length(request_hash)=32),
  status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','running','succeeded','failed','cancelled')),
  output_asset_id uuid,
  error_code text CHECK(error_code IS NULL OR error_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,id),
  FOREIGN KEY(workspace_id,company_id,analysis_id)
    REFERENCES private_isg.workspace_analyses(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,output_asset_id)
    REFERENCES private_isg.workspace_file_assets(workspace_id,id) ON DELETE RESTRICT,
  CHECK(status<>'succeeded' OR (output_asset_id IS NOT NULL AND completed_at IS NOT NULL)),
  CHECK(status<>'failed' OR (error_code IS NOT NULL AND completed_at IS NOT NULL))
);

CREATE INDEX workspace_analysis_timeline ON private_isg.workspace_analyses(workspace_id,company_id,created_at DESC,id);
CREATE INDEX workspace_analysis_findings_order ON private_isg.workspace_analysis_findings(analysis_id,is_scored DESC,display_order,id);
CREATE INDEX workspace_export_queue ON private_isg.workspace_export_jobs(status,created_at,id) WHERE status IN ('queued','running');

ALTER TABLE private_isg.workspace_analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_analysis_findings ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_analysis_expert_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_analysis_training_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_analysis_filed_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_export_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_analyses,private_isg.workspace_analysis_findings,
  private_isg.workspace_analysis_expert_items,private_isg.workspace_analysis_training_items,
  private_isg.workspace_analysis_filed_sources,private_isg.workspace_export_jobs
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_analysis_commit(p_job uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs; prior private_isg.workspace_analyses; analysis private_isg.workspace_analyses;
  item jsonb; result_hash bytea; source_keys text[]; result jsonb;
BEGIN
  IF p_job IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>524288 OR
     EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
       ('title','kind','primary_method','findings','expert_items','training_items')) OR
     jsonb_typeof(p_payload->'findings')<>'array' OR jsonb_typeof(p_payload->'expert_items')<>'array' OR
     jsonb_typeof(p_payload->'training_items')<>'array' OR jsonb_array_length(p_payload->'findings')>200 OR
     jsonb_array_length(p_payload->'expert_items')>100 OR jsonb_array_length(p_payload->'training_items')>100 OR
     coalesce(p_payload->>'kind','') NOT IN ('photo','document','record_set') OR
     coalesce(p_payload->>'primary_method','') NOT IN ('fine_kinney','matrix_5x5') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.workspace_ai_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL OR job.status<>'succeeded' OR job.company_id IS NULL OR job.output_asset_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_STATE_CONFLICT'; END IF;
  result_hash:=sha256(convert_to(p_payload::text,'UTF8'));
  SELECT * INTO prior FROM private_isg.workspace_analyses WHERE ai_job_id=p_job;
  IF prior.id IS NOT NULL THEN
    IF prior.result_hash IS DISTINCT FROM result_hash THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RESULT_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'analysis_id',prior.id,'workspace_id',prior.workspace_id,
      'company_id',prior.company_id,'replayed',true); END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'findings') f WHERE
      jsonb_typeof(f)<>'object' OR coalesce(f->>'source_key','')='' OR coalesce(f->>'title','')='' OR
      coalesce(f->>'item_class','') NOT IN ('observed_finding','assurance_requirement','verification_request') OR
      NOT (f ? 'is_scored')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVALID_FINDING'; END IF;
  INSERT INTO private_isg.workspace_analyses(workspace_id,company_id,ai_job_id,title,kind,primary_method,
    output_asset_id,result_hash,created_by_user_id)
  VALUES(job.workspace_id,job.company_id,job.id,private_isg.workspace_text(p_payload->>'title',300),
    p_payload->>'kind',p_payload->>'primary_method',job.output_asset_id,result_hash,job.actor_user_id)
  RETURNING * INTO analysis;
  FOR item IN SELECT value FROM jsonb_array_elements(p_payload->'findings') LOOP
    IF ((item->>'is_scored')::boolean AND (item->>'item_class'<>'observed_finding' OR
        NOT (item ?& ARRAY['fk_probability','fk_frequency','fk_severity','m5_probability','m5_severity']) OR
        coalesce(item->>'fk_band','') NOT IN ('critical','high','medium','low') OR
        coalesce(item->>'m5_band','') NOT IN ('critical','high','medium','low'))) OR
       (NOT (item->>'is_scored')::boolean AND item->>'item_class' NOT IN ('assurance_requirement','verification_request')) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVALID_FINDING'; END IF;
    INSERT INTO private_isg.workspace_analysis_findings(workspace_id,company_id,analysis_id,source_key,ordinal,
      display_order,item_class,is_scored,title,category,description,recommended_action,references_text,responsible,
      fk_probability,fk_frequency,fk_severity,fk_score,fk_band,m5_probability,m5_severity,m5_score,m5_band,
      source_photo_indices)
    VALUES(analysis.workspace_id,analysis.company_id,analysis.id,private_isg.workspace_text(item->>'source_key',120),
      (item->>'ordinal')::integer,coalesce((item->>'display_order')::integer,(item->>'ordinal')::integer),
      item->>'item_class',(item->>'is_scored')::boolean,private_isg.workspace_text(item->>'title',300),
      nullif(btrim(coalesce(item->>'category','')),''),nullif(btrim(coalesce(item->>'description','')),''),
      nullif(btrim(coalesce(item->>'recommended_action','')),''),nullif(btrim(coalesce(item->>'references_text','')),''),
      nullif(btrim(coalesce(item->>'responsible','')),''),
      CASE WHEN (item->>'is_scored')::boolean THEN (item->>'fk_probability')::numeric END,
      CASE WHEN (item->>'is_scored')::boolean THEN (item->>'fk_frequency')::numeric END,
      CASE WHEN (item->>'is_scored')::boolean THEN (item->>'fk_severity')::numeric END,
      CASE WHEN (item->>'is_scored')::boolean THEN (item->>'fk_probability')::numeric*(item->>'fk_frequency')::numeric*(item->>'fk_severity')::numeric END,
      CASE WHEN (item->>'is_scored')::boolean THEN item->>'fk_band' ELSE 'unknown' END,
      CASE WHEN (item->>'is_scored')::boolean THEN (item->>'m5_probability')::integer END,
      CASE WHEN (item->>'is_scored')::boolean THEN (item->>'m5_severity')::integer END,
      CASE WHEN (item->>'is_scored')::boolean THEN (item->>'m5_probability')::integer*(item->>'m5_severity')::integer END,
      CASE WHEN (item->>'is_scored')::boolean THEN item->>'m5_band' ELSE 'unknown' END,
      ARRAY(SELECT value::integer FROM jsonb_array_elements_text(coalesce(item->'source_photo_indices','[]'))));
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(p_payload->'expert_items') LOOP
    IF jsonb_typeof(item)<>'object' OR coalesce(item->>'source_key','')='' OR coalesce(item->>'title','')='' OR coalesce(item->>'body','')='' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVALID_EXPERT_ITEM'; END IF;
    source_keys:=ARRAY(SELECT value FROM jsonb_array_elements_text(coalesce(item->'source_finding_keys','[]')));
    INSERT INTO private_isg.workspace_analysis_expert_items(workspace_id,company_id,analysis_id,source_key,
      display_order,title,body,recommendation,references_text,source_finding_keys)
    VALUES(analysis.workspace_id,analysis.company_id,analysis.id,private_isg.workspace_text(item->>'source_key',120),
      coalesce((item->>'display_order')::integer,1),private_isg.workspace_text(item->>'title',300),
      private_isg.workspace_text(item->>'body',6000),nullif(btrim(coalesce(item->>'recommendation','')),''),
      nullif(btrim(coalesce(item->>'references_text','')),''),source_keys);
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(p_payload->'training_items') LOOP
    IF jsonb_typeof(item)<>'object' OR coalesce(item->>'source_key','')='' OR coalesce(item->>'title','')='' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVALID_TRAINING_ITEM'; END IF;
    source_keys:=ARRAY(SELECT value FROM jsonb_array_elements_text(coalesce(item->'source_finding_keys','[]')));
    INSERT INTO private_isg.workspace_analysis_training_items(workspace_id,company_id,analysis_id,source_key,
      catalog_code,display_order,title,audience,body,duration_minutes,source_finding_keys)
    VALUES(analysis.workspace_id,analysis.company_id,analysis.id,private_isg.workspace_text(item->>'source_key',120),
      nullif(btrim(coalesce(item->>'catalog_code','')),''),coalesce((item->>'display_order')::integer,1),
      private_isg.workspace_text(item->>'title',300),nullif(btrim(coalesce(item->>'audience','')),''),
      nullif(btrim(coalesce(item->>'body','')),''),(item->>'duration_minutes')::integer,source_keys);
  END LOOP;
  IF EXISTS(SELECT 1 FROM (
      SELECT unnest(source_finding_keys) source_key FROM private_isg.workspace_analysis_expert_items WHERE analysis_id=analysis.id
      UNION ALL SELECT unnest(source_finding_keys) FROM private_isg.workspace_analysis_training_items WHERE analysis_id=analysis.id) x
      WHERE NOT EXISTS(SELECT 1 FROM private_isg.workspace_analysis_findings f WHERE f.analysis_id=analysis.id AND f.source_key=x.source_key)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SOURCE_FINDING_NOT_FOUND'; END IF;
  result:=jsonb_build_object('schema_version',1,'analysis_id',analysis.id,'workspace_id',analysis.workspace_id,
    'company_id',analysis.company_id,'finding_count',jsonb_array_length(p_payload->'findings'),
    'expert_count',(SELECT count(*) FROM private_isg.workspace_analysis_expert_items WHERE analysis_id=analysis.id)+
      (SELECT count(*) FROM private_isg.workspace_analysis_findings WHERE analysis_id=analysis.id AND NOT is_scored),
    'training_count',jsonb_array_length(p_payload->'training_items'),'replayed',false);
  INSERT INTO private_isg.workspace_audit(workspace_id,actor_user_id,action,entity_type,entity_id,after_state,correlation_id)
    VALUES(analysis.workspace_id,job.actor_user_id,'analysis.commit','analysis',analysis.id,result,job.id);
  INSERT INTO private_isg.workspace_outbox(workspace_id,event_type,aggregate_type,aggregate_id,aggregate_version,payload,correlation_id)
    VALUES(analysis.workspace_id,'workspace.analysis.ready.v1','analysis',analysis.id,analysis.result_version,result,job.id);
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_analysis_list(p_workspace uuid,p_company uuid,p_offset integer,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; more boolean;
BEGIN
  PERFORM private_isg.workspace_domain_gate('analysis_exports',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_offset IS NULL OR p_offset<0 OR p_offset>100000 OR p_limit IS NULL OR p_limit<1 OR p_limit>100 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]') INTO rows FROM (
    SELECT a.id,a.title,a.kind,a.status,a.primary_method,a.created_at,a.result_version AS version,
      (SELECT count(*)::integer FROM private_isg.workspace_analysis_findings f
        WHERE f.analysis_id=a.id AND f.is_scored) AS finding_count,
      (SELECT f.fk_band FROM private_isg.workspace_analysis_findings f
        WHERE f.analysis_id=a.id AND f.is_scored
        ORDER BY CASE f.fk_band WHEN 'critical' THEN 4 WHEN 'high' THEN 3 WHEN 'medium' THEN 2 WHEN 'low' THEN 1 ELSE 0 END DESC,
          f.fk_score DESC NULLS LAST,f.id LIMIT 1) AS highest_band
      FROM private_isg.workspace_analyses a
      WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND a.status='ready'
      ORDER BY a.created_at DESC,a.id DESC OFFSET p_offset LIMIT p_limit
  ) x;
  SELECT EXISTS(SELECT 1 FROM private_isg.workspace_analyses a
    WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND a.status='ready'
    ORDER BY a.created_at DESC,a.id DESC OFFSET (p_offset+p_limit) LIMIT 1) INTO more;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'offset',p_offset,'returned',jsonb_array_length(rows),'has_more',more,'rows',rows);
END $$;

CREATE FUNCTION private_isg.workspace_analysis_read(p_workspace uuid,p_company uuid,p_analysis uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE analysis private_isg.workspace_analyses; findings jsonb; expert jsonb; training jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('analysis_exports',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT * INTO analysis FROM private_isg.workspace_analyses WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_analysis;
  IF analysis.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(f)-'workspace_id'-'company_id'-'analysis_id' ORDER BY f.display_order,f.id),'[]') INTO findings
    FROM private_isg.workspace_analysis_findings f WHERE f.analysis_id=analysis.id AND f.is_scored;
  SELECT coalesce(jsonb_agg(x.item ORDER BY x.display_order,x.sort_key),'[]') INTO expert FROM (
    SELECT f.display_order,f.id::text sort_key,jsonb_build_object('id',f.id,'source_key',f.source_key,
      'kind','unscored_finding','item_class',f.item_class,'title',f.title,'body',f.description,
      'recommendation',f.recommended_action,'references_text',f.references_text,'version',f.version) item
      FROM private_isg.workspace_analysis_findings f WHERE f.analysis_id=analysis.id AND NOT f.is_scored
    UNION ALL
    SELECT e.display_order,e.id::text,jsonb_build_object('id',e.id,'source_key',e.source_key,
      'kind','expert_recommendation','title',e.title,'body',e.body,'recommendation',e.recommendation,
      'references_text',e.references_text,'source_finding_keys',e.source_finding_keys,'version',e.version)
      FROM private_isg.workspace_analysis_expert_items e WHERE e.analysis_id=analysis.id) x;
  SELECT coalesce(jsonb_agg(to_jsonb(t)-'workspace_id'-'company_id'-'analysis_id' ORDER BY t.display_order,t.id),'[]') INTO training
    FROM private_isg.workspace_analysis_training_items t WHERE t.analysis_id=analysis.id;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'analysis',jsonb_build_object('id',analysis.id,'title',analysis.title,'kind',analysis.kind,'status',analysis.status,
      'primary_method',analysis.primary_method,'output_asset_id',analysis.output_asset_id,'version',analysis.result_version,
      'created_at',analysis.created_at),'risk_findings',findings,'expert_items',expert,'training_items',training,
    'counts',jsonb_build_object('risk',jsonb_array_length(findings),'expert',jsonb_array_length(expert),
      'training',jsonb_array_length(training)));
END $$;

CREATE FUNCTION private_isg.workspace_analysis_severity(p_band text,p_explicit text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_band IN ('critical','high','medium','low') THEN RETURN p_band; END IF;
  IF p_explicit IN ('critical','high','medium','low') THEN RETURN p_explicit; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SEVERITY_REQUIRED';
END $$;

CREATE FUNCTION private_isg.workspace_analysis_file(p_mutation uuid,p_workspace uuid,p_company uuid,p_workplace uuid,
  p_source_scope text,p_analysis uuid,p_item_kind text,p_item uuid,p_severity text,p_opened_on date,p_due_on date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); fingerprint bytea; replay jsonb; snapshot jsonb; target uuid;
  title text; source_version bigint; band text; v_source_ref text; v_source_kind text; created boolean:=false;
  row_json jsonb; result jsonb; method text;
BEGIN
  PERFORM private_isg.workspace_domain_gate('analysis_exports',true);
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_source_scope NOT IN ('workspace','personal') OR p_item_kind NOT IN ('finding','expert_item') OR
     p_analysis IS NULL OR p_item IS NULL OR p_workplace IS NULL OR p_opened_on IS NULL OR NOT isfinite(p_opened_on) OR
     (p_due_on IS NOT NULL AND p_due_on<p_opened_on) OR
     NOT EXISTS(SELECT 1 FROM private_isg.workplaces WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_workplace AND NOT is_archived) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_workplace,p_source_scope,p_analysis,
    p_item_kind,p_item,p_severity,p_opened_on,p_due_on)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'analysis.file',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  IF p_source_scope='workspace' AND p_item_kind='finding' THEN
    SELECT jsonb_build_object('title',f.title,'category',f.category,'description',f.description,
      'recommended_action',f.recommended_action,'references_text',f.references_text,'responsible',f.responsible,
      'is_scored',f.is_scored,'item_class',f.item_class,'fk_probability',f.fk_probability,
      'fk_frequency',f.fk_frequency,'fk_severity',f.fk_severity,'fk_score',f.fk_score,'fk_band',f.fk_band,
      'm5_probability',f.m5_probability,'m5_severity',f.m5_severity,'m5_score',f.m5_score,'m5_band',f.m5_band,
      'source_photo_indices',f.source_photo_indices),f.title,f.version,a.primary_method,
      CASE a.primary_method WHEN 'fine_kinney' THEN f.fk_band ELSE f.m5_band END
      INTO snapshot,title,source_version,method,band
      FROM private_isg.workspace_analysis_findings f JOIN private_isg.workspace_analyses a ON a.id=f.analysis_id
      WHERE f.workspace_id=p_workspace AND f.company_id=p_company AND f.analysis_id=p_analysis AND f.id=p_item;
  ELSIF p_source_scope='workspace' AND p_item_kind='expert_item' THEN
    SELECT jsonb_build_object('title',e.title,'description',e.body,'recommended_action',e.recommendation,
      'references_text',e.references_text,'source_finding_keys',e.source_finding_keys,'is_scored',false),
      e.title,e.version,'expert',NULL INTO snapshot,title,source_version,method,band
      FROM private_isg.workspace_analysis_expert_items e
      WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND e.analysis_id=p_analysis AND e.id=p_item;
  ELSIF p_source_scope='personal' AND p_item_kind='finding' THEN
    SELECT jsonb_build_object('title',f.title,'category',f.category,'description',f.description,
      'recommended_action',f.recommended_action,'references_text',f.references_text,'responsible',f.responsible,
      'is_scored',f.is_scored,'item_class',f.item_class,'fk_probability',f.fk_probability,
      'fk_frequency',f.fk_frequency,'fk_severity',f.fk_severity,'fk_score',f.fk_score,'fk_band',f.fk_band,
      'm5_probability',f.m5_probability,'m5_severity',f.m5_severity,'m5_score',f.m5_score,'m5_band',f.m5_band,
      'source_photo_indices',f.source_photo_indices),f.title,f.finding_version::bigint,a.primary_method,
      CASE a.primary_method WHEN 'fine_kinney' THEN f.fk_band::text ELSE f.m5_band::text END
      INTO snapshot,title,source_version,method,band
      FROM public.findings f JOIN public.analyses a ON a.id=f.analysis_id
      WHERE f.id=p_item AND f.analysis_id=p_analysis AND f.user_id=actor AND a.user_id=actor
        AND NOT coalesce(f.is_user_deleted,false) FOR SHARE OF f,a;
  ELSE
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  IF snapshot IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  v_source_ref:=p_source_scope||':'||p_item_kind||':'||p_item::text;
  v_source_kind:=CASE p_item_kind WHEN 'finding' THEN 'analysis_finding' ELSE 'analysis_expert_item' END;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_workspace::text||':'||p_company::text||':'||v_source_ref,0));
  SELECT n.nonconformity_id INTO target FROM private_isg.nonconformities n
    WHERE n.workspace_id=p_workspace AND n.company_id=p_company AND n.source_kind=v_source_kind
      AND n.source_ref=v_source_ref FOR UPDATE;
  IF target IS NULL THEN
    INSERT INTO private_isg.nonconformities(workspace_id,company_id,owner_id,workplace_id,source_kind,source_ref,
      title,severity,opened_on,due_on,state,version,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,p_workplace,v_source_kind,v_source_ref,private_isg.workspace_text(title,300),
      private_isg.workspace_analysis_severity(band,p_severity),p_opened_on,p_due_on,'open',1,actor,actor)
    RETURNING nonconformity_id INTO target;
    INSERT INTO private_isg.nonconformity_transitions(workspace_id,company_id,nonconformity_id,version,
      from_state,to_state,actor_id,occurred_at)
    VALUES(p_workspace,p_company,target,1,'draft','open',actor,clock_timestamp());
    INSERT INTO private_isg.workspace_analysis_filed_sources(nonconformity_id,workspace_id,company_id,
      source_scope,source_analysis_id,source_item_kind,source_item_id,source_version,snapshot,filed_by_user_id)
    VALUES(target,p_workspace,p_company,p_source_scope,p_analysis,p_item_kind,p_item,source_version,
      snapshot||jsonb_build_object('primary_method',method),actor);
    created:=true;
  END IF;
  row_json:=private_isg.workspace_nonconformity_row(p_workspace,p_company,target);
  IF row_json IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMMIT_VISIBILITY_FAILED'; END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'nonconformity_id',target,'row',row_json,'created',created,'commit_state','committed_and_visible',
    'success_message_key',CASE WHEN created THEN 'analysis_finding_filed' ELSE 'analysis_finding_already_filed' END);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'analysis.file',fingerprint,p_workspace,
    'nonconformity',target,(row_json->>'version')::bigint,NULL,row_json,NULL,result);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_nonconformity_row(p_workspace uuid,p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('nonconformity_id',n.nonconformity_id,'company_id',n.company_id,
    'workplace_id',n.workplace_id,'source_kind',n.source_kind,'source_ref',n.source_ref,
    'title',n.title,'severity',n.severity,'opened_on',n.opened_on,'due_on',n.due_on,
    'assignee_contact',n.assignee_contact,'state',n.state,'version',n.version,'closed_on',n.closed_on,
    'created_by_user_id',n.created_by_user_id,
    'source_snapshot',(SELECT s.snapshot||jsonb_build_object('source_scope',s.source_scope,
      'source_analysis_id',s.source_analysis_id,'source_item_kind',s.source_item_kind,'source_item_id',s.source_item_id,
      'source_version',s.source_version) FROM private_isg.workspace_analysis_filed_sources s
      WHERE s.nonconformity_id=n.nonconformity_id),
    'actions',coalesce((SELECT jsonb_agg(jsonb_build_object('action_id',a.action_id,
      'description',a.description,'assignee_contact',a.assignee_contact,'due_on',a.due_on,'state',a.state)
      ORDER BY a.created_at,a.action_id) FROM private_isg.nonconformity_actions a
      WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND a.nonconformity_id=n.nonconformity_id),'[]'::jsonb),
    'transitions',coalesce((SELECT jsonb_agg(jsonb_build_object('from',t.from_state,'to',t.to_state,
      'reason',t.reason,'actor_id',t.actor_id,'occurred_at',t.occurred_at) ORDER BY t.version)
      FROM private_isg.nonconformity_transitions t WHERE t.workspace_id=p_workspace
        AND t.company_id=p_company AND t.nonconformity_id=n.nonconformity_id),'[]'::jsonb))
  FROM private_isg.nonconformities n
  WHERE n.workspace_id=p_workspace AND n.company_id=p_company AND n.nonconformity_id=p_id
$$;

CREATE FUNCTION private_isg.workspace_export_row(p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('id',e.id,'workspace_id',e.workspace_id,'company_id',e.company_id,
    'analysis_id',e.analysis_id,'format',e.format,'selection',e.selection,'status',e.status,
    'output_asset_id',e.output_asset_id,'error_code',e.error_code,'version',e.version,
    'created_at',e.created_at,'started_at',e.started_at,'completed_at',e.completed_at)
  FROM private_isg.workspace_export_jobs e WHERE e.id=p_id
$$;

CREATE FUNCTION private_isg.workspace_export_create(p_mutation uuid,p_workspace uuid,p_company uuid,p_analysis uuid,
  p_format text,p_selection jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships; fingerprint bytea;
  replay jsonb; snapshot jsonb; job private_isg.workspace_export_jobs; result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('analysis_exports',true);
  member:=private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_format NOT IN ('pdf','xlsx') OR p_selection IS NULL OR
     jsonb_typeof(p_selection)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_selection) k
       WHERE k NOT IN ('finding_ids','expert_item_ids','training_item_ids')) OR
     EXISTS(SELECT 1 FROM jsonb_each(p_selection) e WHERE jsonb_typeof(e.value)<>'array') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  snapshot:=private_isg.workspace_analysis_read(p_workspace,p_company,p_analysis);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(p_selection->'finding_ids','[]')) x
      WHERE NOT EXISTS(SELECT 1 FROM private_isg.workspace_analysis_findings f WHERE f.analysis_id=p_analysis AND f.id=x::uuid)) OR
     EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(p_selection->'expert_item_ids','[]')) x
      WHERE NOT EXISTS(SELECT 1 FROM private_isg.workspace_analysis_expert_items e WHERE e.analysis_id=p_analysis AND e.id=x::uuid)) OR
     EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(p_selection->'training_item_ids','[]')) x
      WHERE NOT EXISTS(SELECT 1 FROM private_isg.workspace_analysis_training_items t WHERE t.analysis_id=p_analysis AND t.id=x::uuid)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SELECTION_SCOPE_CONFLICT'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_analysis,p_format,p_selection)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'export.create',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  INSERT INTO private_isg.workspace_export_jobs(workspace_id,company_id,analysis_id,actor_user_id,membership_id,
    permission_revision,format,selection,source_snapshot,request_hash)
  VALUES(p_workspace,p_company,p_analysis,actor,member.id,member.permission_revision,p_format,p_selection,snapshot,fingerprint)
  RETURNING * INTO job;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'row',private_isg.workspace_export_row(job.id));
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'export.create',fingerprint,p_workspace,
    'export',job.id,job.version,NULL,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_export_start(p_job uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_export_jobs; member private_isg.workspace_memberships;
BEGIN
  IF p_job IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.workspace_export_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_NOT_FOUND'; END IF;
  IF job.status='running' THEN RETURN private_isg.workspace_export_row(job.id)||jsonb_build_object('replayed',true); END IF;
  IF job.status<>'queued' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_STATE_CONFLICT'; END IF;
  SELECT * INTO member FROM private_isg.workspace_memberships WHERE workspace_id=job.workspace_id AND id=job.membership_id;
  IF member.id IS NULL OR member.user_id<>job.actor_user_id OR member.status<>'active' OR
     member.permission_revision<>job.permission_revision THEN
    UPDATE private_isg.workspace_export_jobs SET status='failed',error_code='AUTHORITY_REVOKED',completed_at=p_now,
      version=version+1,updated_at=clock_timestamp() WHERE id=job.id;
    RETURN private_isg.workspace_export_row(job.id); END IF;
  IF member.role='expert' AND NOT EXISTS(SELECT 1 FROM private_isg.company_assignments a
      WHERE a.workspace_id=job.workspace_id AND a.company_id=job.company_id AND a.membership_id=member.id
        AND a.starts_at<=p_now AND (a.ends_at IS NULL OR a.ends_at>p_now)) THEN
    UPDATE private_isg.workspace_export_jobs SET status='failed',error_code='ASSIGNMENT_REVOKED',completed_at=p_now,
      version=version+1,updated_at=clock_timestamp() WHERE id=job.id;
    RETURN private_isg.workspace_export_row(job.id); END IF;
  UPDATE private_isg.workspace_export_jobs SET status='running',started_at=p_now,version=version+1,
    updated_at=clock_timestamp() WHERE id=job.id;
  RETURN private_isg.workspace_export_row(job.id)||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_export_complete(p_job uuid,p_asset uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_export_jobs; asset private_isg.workspace_file_assets; result jsonb;
BEGIN
  IF p_job IS NULL OR p_asset IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.workspace_export_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_NOT_FOUND'; END IF;
  IF job.status='succeeded' AND job.output_asset_id=p_asset THEN RETURN private_isg.workspace_export_row(job.id)||jsonb_build_object('replayed',true); END IF;
  IF job.status<>'running' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_STATE_CONFLICT'; END IF;
  SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=p_asset AND workspace_id=job.workspace_id
    AND company_id=job.company_id AND lifecycle='active' AND source_kind IN ('generated','derivative');
  IF asset.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_SCOPE_CONFLICT'; END IF;
  UPDATE private_isg.workspace_export_jobs SET status='succeeded',output_asset_id=p_asset,completed_at=p_now,
    version=version+1,updated_at=clock_timestamp() WHERE id=job.id RETURNING * INTO job;
  result:=private_isg.workspace_export_row(job.id);
  INSERT INTO private_isg.workspace_outbox(workspace_id,event_type,aggregate_type,aggregate_id,aggregate_version,payload,correlation_id)
    VALUES(job.workspace_id,'workspace.export.succeeded.v1','export',job.id,job.version,result,job.id);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_export_fail(p_job uuid,p_error text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_export_jobs;
BEGIN
  IF p_job IS NULL OR p_error !~ '^[A-Z][A-Z0-9_]{2,49}$' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.workspace_export_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_NOT_FOUND'; END IF;
  IF job.status='failed' THEN RETURN private_isg.workspace_export_row(job.id)||jsonb_build_object('replayed',true); END IF;
  IF job.status NOT IN ('queued','running') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_STATE_CONFLICT'; END IF;
  UPDATE private_isg.workspace_export_jobs SET status='failed',error_code=p_error,completed_at=p_now,
    version=version+1,updated_at=clock_timestamp() WHERE id=job.id;
  RETURN private_isg.workspace_export_row(job.id)||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_export_get(p_workspace uuid,p_company uuid,p_job uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_export_jobs;
BEGIN
  PERFORM private_isg.workspace_domain_gate('analysis_exports',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT * INTO job FROM private_isg.workspace_export_jobs WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_job;
  IF job.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'row',private_isg.workspace_export_row(job.id));
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_asset_reference_count(p_workspace uuid,p_asset uuid) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT
    (SELECT count(*) FROM private_isg.workspace_file_versions v WHERE v.workspace_id=p_workspace AND v.asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.equipment_inspections v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.katip_contracts v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.board_meetings v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.work_permit_forms v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.site_visit_observations v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.notebook_archive_entries v WHERE v.workspace_id=p_workspace AND v.workspace_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.workspace_ai_jobs v WHERE v.workspace_id=p_workspace AND v.output_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.workspace_analyses v WHERE v.workspace_id=p_workspace AND v.output_asset_id=p_asset)+
    (SELECT count(*) FROM private_isg.workspace_export_jobs v WHERE v.workspace_id=p_workspace AND v.output_asset_id=p_asset)
$$;

CREATE FUNCTION public.isg_workspace_analysis_read_v1(p_workspace uuid,p_company uuid,p_analysis uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_analysis_read(p_workspace,p_company,p_analysis) $$;
CREATE FUNCTION public.isg_workspace_analysis_list_v1(p_workspace uuid,p_company uuid,p_offset integer,p_limit integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_analysis_list(p_workspace,p_company,p_offset,p_limit) $$;
CREATE FUNCTION public.isg_workspace_analysis_file_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_workplace uuid,
  p_source_scope text,p_analysis uuid,p_item_kind text,p_item uuid,p_severity text,p_opened_on date,p_due_on date) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_analysis_file(p_mutation,p_workspace,p_company,
  p_workplace,p_source_scope,p_analysis,p_item_kind,p_item,p_severity,p_opened_on,p_due_on) $$;
CREATE FUNCTION public.isg_workspace_export_create_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_analysis uuid,
  p_format text,p_selection jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_export_create(p_mutation,p_workspace,p_company,p_analysis,p_format,p_selection) $$;
CREATE FUNCTION public.isg_workspace_export_get_v1(p_workspace uuid,p_company uuid,p_job uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_export_get(p_workspace,p_company,p_job) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_analysis_commit(uuid,jsonb),
  private_isg.workspace_analysis_list(uuid,uuid,integer,integer),private_isg.workspace_analysis_read(uuid,uuid,uuid),private_isg.workspace_analysis_severity(text,text),
  private_isg.workspace_analysis_file(uuid,uuid,uuid,uuid,text,uuid,text,uuid,text,date,date),
  private_isg.workspace_nonconformity_row(uuid,uuid,uuid),private_isg.workspace_export_row(uuid),
  private_isg.workspace_export_create(uuid,uuid,uuid,uuid,text,jsonb),private_isg.workspace_export_start(uuid,timestamptz),
  private_isg.workspace_export_complete(uuid,uuid,timestamptz),private_isg.workspace_export_fail(uuid,text,timestamptz),
  private_isg.workspace_export_get(uuid,uuid,uuid),private_isg.workspace_asset_reference_count(uuid,uuid),
  public.isg_workspace_analysis_list_v1(uuid,uuid,integer,integer),public.isg_workspace_analysis_read_v1(uuid,uuid,uuid),
  public.isg_workspace_analysis_file_v1(uuid,uuid,uuid,uuid,text,uuid,text,uuid,text,date,date),
  public.isg_workspace_export_create_v1(uuid,uuid,uuid,uuid,text,jsonb),public.isg_workspace_export_get_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_analysis_list(uuid,uuid,integer,integer),private_isg.workspace_analysis_read(uuid,uuid,uuid),
  private_isg.workspace_analysis_file(uuid,uuid,uuid,uuid,text,uuid,text,uuid,text,date,date),
  private_isg.workspace_export_create(uuid,uuid,uuid,uuid,text,jsonb),private_isg.workspace_export_get(uuid,uuid,uuid),
  public.isg_workspace_analysis_list_v1(uuid,uuid,integer,integer),public.isg_workspace_analysis_read_v1(uuid,uuid,uuid),
  public.isg_workspace_analysis_file_v1(uuid,uuid,uuid,uuid,text,uuid,text,uuid,text,date,date),
  public.isg_workspace_export_create_v1(uuid,uuid,uuid,uuid,text,jsonb),public.isg_workspace_export_get_v1(uuid,uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION private_isg.workspace_analysis_commit(uuid,jsonb),
  private_isg.workspace_export_start(uuid,timestamptz),private_isg.workspace_export_complete(uuid,uuid,timestamptz),
  private_isg.workspace_export_fail(uuid,text,timestamptz) TO service_role;
NOTIFY pgrst,'reload schema';
