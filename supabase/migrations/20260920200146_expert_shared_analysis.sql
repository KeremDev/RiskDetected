-- Shared expert analysis data adapter; no alternate expert presentation.
SET LOCAL lock_timeout='2s';
ALTER TABLE private_isg.checklist_templates ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
CREATE OR REPLACE FUNCTION private_isg.checklist_template_code(p_owner uuid, p_title text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  SELECT 'c'||left(md5(coalesce(private_isg.expert_workspace()::text||':','')||p_owner::text||':'||btrim(lower(p_title))),20)
$function$
;
CREATE OR REPLACE FUNCTION private_isg.draft_checklist_template(p_owner uuid, p_title text, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE code text; entry private_isg.checklist_templates; next_version integer; existing integer;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_owner IS NULL OR p_title IS NULL OR btrim(p_title)='' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  code:=private_isg.checklist_template_code(p_owner,p_title);
  SELECT * INTO entry FROM private_isg.checklist_templates WHERE template_code=code FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO private_isg.checklist_templates(template_code,title,owner_id,workspace_id,created_at)
      VALUES(code,private_isg.text_value(p_title,200),p_owner,private_isg.expert_workspace(),p_now);
  ELSIF entry.owner_id IS DISTINCT FROM p_owner OR entry.workspace_id IS DISTINCT FROM private_isg.expert_workspace() THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  -- One draft at a time: a second call returns the draft that is already open.
  SELECT version INTO existing FROM private_isg.checklist_template_versions
    WHERE template_code=code AND status='draft' FOR UPDATE;
  IF existing IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'template_code',code,'version',existing,
      'status','draft','replayed',true); END IF;
  SELECT coalesce(max(version),0)+1 INTO next_version FROM private_isg.checklist_template_versions
    WHERE template_code=code;
  INSERT INTO private_isg.checklist_template_versions(template_code,version,status,created_at)
    VALUES(code,next_version,'draft',p_now);
  -- A new version starts from what is published, so a small change is a small
  -- edit rather than retyping the whole list.
  INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,allows_not_applicable,position)
    SELECT i.template_code,next_version,i.item_code,i.prompt,i.allows_not_applicable,i.position
    FROM private_isg.checklist_template_items i
    JOIN private_isg.checklist_template_versions v
      ON v.template_code=i.template_code AND v.version=i.version AND v.status='published'
    WHERE i.template_code=code;
  RETURN jsonb_build_object('schema_version',1,'template_code',code,'version',next_version,
    'status','draft','replayed',false);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.require_checklist_template(p_code text, p_actor uuid, p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE entry private_isg.checklist_templates;
BEGIN
  SELECT * INTO entry FROM private_isg.checklist_templates WHERE template_code=p_code;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.workspace_id IS DISTINCT FROM private_isg.expert_workspace() AND NOT (entry.owner_id IS NULL AND entry.workspace_id IS NULL AND NOT p_write) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  -- Reading a product template is allowed; editing one is not, because it is
  -- not the expert's to change.
  IF p_write THEN
    IF entry.owner_id IS DISTINCT FROM p_actor THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF entry.owner_id IS NOT NULL AND entry.owner_id<>p_actor THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.module_gate(p_module text, p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM private_isg.module_registry WHERE module=p_module) THEN RAISE EXCEPTION 'MODULE_UNAVAILABLE'; END IF;
  PERFORM private_isg.workspace_domain_gate(CASE WHEN p_module IN ('appointment','drill','emergency_plan','ppe') THEN 'emergency_ppe' WHEN p_module='equipment' THEN 'equipment' ELSE 'operations' END,p_write);
  RETURN;
 END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='modules' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  PERFORM 1 FROM private_isg.module_registry WHERE module=p_module AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MODULE_UNAVAILABLE'; END IF;
END $function$
;
SET LOCAL statement_timeout='60s';
-- A company must have the same default workplace before the first personnel,
-- education or nonconformity form is opened.
CREATE FUNCTION private_isg.expert_company_default_workplace() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM private_isg.workspaces WHERE id=NEW.workspace_id AND kind='osgb') THEN
  PERFORM private_isg.ensure_default(NEW.id);
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.expert_company_default_workplace() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER expert_company_default_workplace AFTER INSERT ON public.companies
 FOR EACH ROW EXECUTE FUNCTION private_isg.expert_company_default_workplace();
SELECT private_isg.ensure_default(c.id) FROM public.companies c JOIN private_isg.workspaces w ON w.id=c.workspace_id
 WHERE w.kind='osgb' AND NOT EXISTS(SELECT 1 FROM private_isg.workplaces p WHERE p.company_id=c.id AND NOT p.is_archived);

ALTER TABLE private_isg.notice_marks ADD COLUMN context_key text NOT NULL DEFAULT 'personal';
ALTER TABLE private_isg.notice_marks DROP CONSTRAINT notice_marks_pkey;
ALTER TABLE private_isg.notice_marks ADD PRIMARY KEY(owner_id,context_key,notice_key);
CREATE OR REPLACE FUNCTION private_isg.mark_notices(p_action text, p_keys text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); touched integer:=0;
        current_keys text[]; valid text[];
BEGIN
  IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,true)
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_action IS NULL OR p_action NOT IN ('read','dismiss','restore','read_all','dismiss_all')
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_action IN ('read','dismiss','restore') THEN
    IF p_keys IS NULL OR cardinality(p_keys)=0 OR cardinality(p_keys)>200
      THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  ELSIF p_keys IS NOT NULL THEN
    -- The bulk actions take no list; a payload here would be a second meaning.
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED';
  END IF;

  SELECT coalesce(array_agg(k.notice_key),'{}') INTO current_keys
    FROM private_isg.notice_keys(actor) k;
  IF p_keys IS NULL THEN valid:=current_keys;
  ELSE
    SELECT coalesce(array_agg(DISTINCT x),'{}') INTO valid
      FROM unnest(p_keys) x WHERE x=ANY(current_keys);
    IF cardinality(valid)<>cardinality(ARRAY(SELECT DISTINCT unnest(p_keys)))
      THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='NOTICE_NOT_FOUND'; END IF;
  END IF;

  IF p_action='restore' THEN
    -- Undoing a dismissal restores the notice; a row that carried nothing else
    -- is removed rather than left violating its own rule.
    UPDATE private_isg.notice_marks m SET dismissed_at=NULL,updated_at=now()
     WHERE m.owner_id=actor AND m.context_key=coalesce(private_isg.expert_workspace()::text,'personal') AND m.notice_key=ANY(valid)
       AND m.dismissed_at IS NOT NULL AND m.read_at IS NOT NULL;
    GET DIAGNOSTICS touched=ROW_COUNT;
    DELETE FROM private_isg.notice_marks m
     WHERE m.owner_id=actor AND m.context_key=coalesce(private_isg.expert_workspace()::text,'personal') AND m.notice_key=ANY(valid) AND m.read_at IS NULL;
  ELSE
    INSERT INTO private_isg.notice_marks AS t(owner_id,context_key,notice_key,read_at,dismissed_at)
    SELECT actor,coalesce(private_isg.expert_workspace()::text,'personal'),k,now(),CASE WHEN p_action IN ('dismiss','dismiss_all') THEN now() END
      FROM unnest(valid) k
    ON CONFLICT(owner_id,context_key,notice_key) DO UPDATE
      SET read_at=coalesce(t.read_at,excluded.read_at),
          dismissed_at=coalesce(excluded.dismissed_at,t.dismissed_at),
          updated_at=now();
    GET DIAGNOSTICS touched=ROW_COUNT;
  END IF;

  -- A situation that no longer exists keeps no mark.
  DELETE FROM private_isg.notice_marks m
   WHERE m.owner_id=actor AND m.context_key=coalesce(private_isg.expert_workspace()::text,'personal') AND NOT (m.notice_key=ANY(current_keys));

  RETURN jsonb_build_object('action',p_action,'marked',touched,
    'generated_at',clock_timestamp(),
    'push_delivery_claimed',false,'dismiss_is_permanent',false,'records_changed',false);
END $function$
;

CREATE FUNCTION private_isg.expert_asset_meter() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member uuid;
BEGIN
 IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
 SELECT id INTO member FROM private_isg.workspace_memberships WHERE workspace_id=NEW.workspace_id AND user_id=NEW.uploaded_by_user_id ORDER BY created_at LIMIT 1;
 IF member IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 INSERT INTO private_isg.workspace_file_assets(id,workspace_id,company_id,uploaded_by_membership_id,source_kind,
  bucket,object_path,object_version,byte_size,sha256,lifecycle,finalized_at,media_type,extension)
 VALUES(NEW.asset_id,NEW.workspace_id,NEW.company_id,member,'upload',NEW.bucket,NEW.immutable_path,encode(NEW.sha256,'hex'),
 NEW.bytes,NEW.sha256,'active',clock_timestamp(),NEW.detected_type,NEW.extension);
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.expert_asset_meter() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER expert_asset_meter AFTER INSERT ON private_isg.file_assets FOR EACH ROW EXECUTE FUNCTION private_isg.expert_asset_meter();

CREATE TABLE private_isg.expert_analysis_inputs (
 job_id uuid PRIMARY KEY REFERENCES private_isg.workspace_ai_jobs(id),
 asset_ids uuid[] NOT NULL CHECK(cardinality(asset_ids) BETWEEN 1 AND 20),
 focus_ids text[] NOT NULL,
 sector text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.expert_analysis_feedback (
 workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id),
 analysis_id uuid NOT NULL REFERENCES private_isg.workspace_analyses(id),
 item_id uuid NOT NULL, actor_id uuid NOT NULL REFERENCES auth.users(id),
 reaction text NOT NULL CHECK(reaction IN ('none','like','dislike')),
 PRIMARY KEY(workspace_id,analysis_id,item_id,actor_id)
);
ALTER TABLE private_isg.expert_analysis_inputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.expert_analysis_feedback ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.expert_analysis_inputs,private_isg.expert_analysis_feedback FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.expert_analysis(p_action text,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE w uuid:=private_isg.expert_workspace(); actor uuid:=private_isg.active_actor();
 analysis_record private_isg.workspace_analyses; finding_record private_isg.workspace_analysis_findings; target_analysis uuid:=(p_payload->>'analysis_id')::uuid;
 item uuid:=(p_payload->>'item_id')::uuid; result jsonb; rows jsonb; sources jsonb; company uuid;
 lim integer:=least(greatest(coalesce((p_payload->>'limit')::integer,50),1),100);
 off_ integer:=greatest(coalesce((p_payload->>'offset')::integer,0),0);
 assets uuid[]; focuses text[]; job uuid; receipt jsonb; score numeric; score5 integer;
BEGIN
 IF w IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>65536 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 PERFORM private_isg.workspace_require_member(w,ARRAY['owner','admin','expert'],false);
 PERFORM private_isg.workspace_domain_gate('analysis_exports',p_action IN ('submit','edit','remove','react','assign','file','export'));
 IF p_action='list' THEN
  SELECT coalesce(jsonb_agg(x.row ORDER BY x.created_at DESC,x.id),'[]') INTO rows FROM (
   SELECT a.created_at,a.id,to_jsonb(a)||jsonb_build_object('company_name',c.name,
    'finding_count',(SELECT count(*) FROM private_isg.workspace_analysis_findings f WHERE f.analysis_id=a.id),
    'highest_band_fk',(SELECT f.fk_band FROM private_isg.workspace_analysis_findings f WHERE f.analysis_id=a.id AND f.is_scored ORDER BY f.fk_score DESC NULLS LAST LIMIT 1),
    'highest_band_m5',(SELECT f.m5_band FROM private_isg.workspace_analysis_findings f WHERE f.analysis_id=a.id AND f.is_scored ORDER BY f.m5_score DESC NULLS LAST LIMIT 1)) row
   FROM private_isg.workspace_analyses a JOIN public.companies c ON c.id=a.company_id
   WHERE a.workspace_id=w AND a.status='ready' AND private_isg.expert_company_visible(c.user_id,c.id,actor)
   ORDER BY a.created_at DESC,a.id LIMIT lim+1 OFFSET off_) x;
  RETURN jsonb_build_object('rows',coalesce((SELECT jsonb_agg(value) FROM jsonb_array_elements(rows) WITH ORDINALITY x(value,n) WHERE n<=lim),'[]'),'has_more',jsonb_array_length(rows)>lim);
 ELSIF p_action='reports' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO rows FROM (
   SELECT e.id,e.analysis_id,a.title,c.name company_name,e.format,e.created_at,
    fa.byte_size file_size,'İSG Raporu.'||e.format file_name
   FROM private_isg.workspace_export_jobs e JOIN private_isg.workspace_analyses a ON a.id=e.analysis_id
   JOIN public.companies c ON c.id=e.company_id JOIN private_isg.workspace_file_assets fa ON fa.id=e.output_asset_id
   WHERE e.workspace_id=w AND e.status='succeeded' AND private_isg.expert_company_visible(c.user_id,c.id,actor)
   ORDER BY e.created_at DESC LIMIT lim) x;
  RETURN jsonb_build_object('rows',rows);
 ELSIF p_action='submit' THEN
  company:=(p_payload->>'company_id')::uuid;
  PERFORM private_isg.workspace_require_company(w,company,true);
  SELECT array_agg(value::uuid) INTO assets FROM jsonb_array_elements_text(p_payload->'asset_ids');
  SELECT array_agg(value) INTO focuses FROM jsonb_array_elements_text(p_payload->'focus_ids');
  IF cardinality(assets) NOT BETWEEN 1 AND 20 OR cardinality(assets) IS NULL OR cardinality(focuses) IS NULL
   OR cardinality(focuses) NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF EXISTS(SELECT 1 FROM unnest(assets) x WHERE NOT EXISTS(SELECT 1 FROM private_isg.workspace_file_assets fa
    WHERE fa.id=x AND fa.workspace_id=w AND fa.company_id=company AND fa.lifecycle='active' AND fa.media_type LIKE 'image/%')) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  receipt:=private_isg.workspace_photo_analysis_submit(w,company,(p_payload->>'mutation_id')::uuid,assets[1]);
  job:=(receipt->>'job_id')::uuid;
  IF job IS NULL THEN job:=(receipt->>'id')::uuid; END IF;
  INSERT INTO private_isg.expert_analysis_inputs(job_id,asset_ids,focus_ids,sector) VALUES(job,assets,focuses,p_payload->>'sector')
   ON CONFLICT(job_id) DO NOTHING;
  IF NOT EXISTS(SELECT 1 FROM private_isg.expert_analysis_inputs i WHERE i.job_id=job AND i.asset_ids=assets
   AND i.focus_ids=focuses AND i.sector IS NOT DISTINCT FROM p_payload->>'sector') THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  RETURN receipt||jsonb_build_object('id',job);
 ELSIF p_action='source' THEN
  SELECT s.source_analysis_id INTO target_analysis FROM private_isg.workspace_analysis_filed_sources s
   WHERE s.workspace_id=w AND s.nonconformity_id=(p_payload->>'record_id')::uuid;
  IF target_analysis IS NULL THEN RAISE EXCEPTION 'SOURCE_NOT_FOUND'; END IF;
 END IF;
 SELECT * INTO analysis_record FROM private_isg.workspace_analyses WHERE workspace_id=w AND workspace_analyses.id=target_analysis;
 IF analysis_record.id IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 PERFORM private_isg.workspace_require_company(w,analysis_record.company_id,p_action IN ('edit','remove','react','assign','file','export'));
 IF p_action IN ('detail','source') THEN
  result:=private_isg.workspace_analysis_read(w,analysis_record.company_id,analysis_record.id);
  SELECT coalesce(jsonb_agg(jsonb_build_object('asset_id',fa.id,'bucket',fa.bucket,'path',fa.object_path,'name','photo.'||coalesce(fa.extension,'jpg')) ORDER BY x.ordinal),'[]')
   INTO sources FROM private_isg.workspace_ai_jobs j
   LEFT JOIN private_isg.expert_analysis_inputs i ON i.job_id=j.id
   CROSS JOIN LATERAL unnest(coalesce(i.asset_ids,ARRAY[CASE WHEN j.source_reference ~ '^[0-9a-f-]{36}$' THEN j.source_reference::uuid END])) WITH ORDINALITY x(asset,ordinal)
   JOIN private_isg.workspace_file_assets fa ON fa.id=x.asset AND fa.workspace_id=w AND fa.company_id=analysis_record.company_id AND fa.lifecycle='active'
   WHERE j.id=analysis_record.ai_job_id;
  RETURN result||jsonb_build_object('company_name',(SELECT name FROM public.companies WHERE public.companies.id=analysis_record.company_id),
   'photos',sources,'feedback',coalesce((SELECT jsonb_object_agg(item_id::text,reaction) FROM private_isg.expert_analysis_feedback WHERE analysis_id=analysis_record.id AND actor_id=actor),'{}'));
 ELSIF p_action='assign' THEN
  company:=(p_payload->>'company_id')::uuid;
  PERFORM private_isg.workspace_require_company(w,company,true);
  IF company<>analysis_record.company_id THEN RAISE EXCEPTION 'ANALYSIS_COMPANY_FIXED'; END IF;
  RETURN jsonb_build_object('id',analysis_record.id);
 ELSIF p_action='export' THEN
  IF coalesce(p_payload->>'method',analysis_record.primary_method) NOT IN ('fine_kinney','matrix_5x5') THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  receipt:=private_isg.workspace_export_create((p_payload->>'mutation_id')::uuid,w,analysis_record.company_id,analysis_record.id,p_payload->>'format',jsonb_build_object('finding_ids','[]'::jsonb,'expert_item_ids','[]'::jsonb,'training_item_ids','[]'::jsonb));
  job:=(receipt#>>'{row,id}')::uuid;
  SELECT source_snapshot INTO sources FROM private_isg.workspace_export_jobs WHERE workspace_export_jobs.id=job FOR UPDATE;
  IF sources ? '_shared_request' AND sources->'_shared_request' IS DISTINCT FROM p_payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  IF NOT sources ? '_shared_request' THEN
   UPDATE private_isg.workspace_export_jobs SET source_snapshot=jsonb_set(sources,'{analysis,primary_method}',to_jsonb(coalesce(p_payload->>'method',analysis_record.primary_method)))||jsonb_build_object('_shared_request',p_payload)
    WHERE workspace_export_jobs.id=job;
  END IF;
  RETURN receipt;
 ELSIF p_action='file' THEN
  IF coalesce(p_payload->>'record_kind','nonconformity') NOT IN ('nonconformity','improvement') THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  receipt:=private_isg.workspace_analysis_file((p_payload->>'mutation_id')::uuid,w,analysis_record.company_id,(p_payload->>'workplace_id')::uuid,
   'workspace',analysis_record.id,p_payload->>'item_kind',item,p_payload->>'severity',current_date,NULL);
  IF coalesce((receipt->>'created')::boolean,false) THEN
   UPDATE private_isg.nonconformities SET record_kind=coalesce(p_payload->>'record_kind','nonconformity')
    WHERE nonconformity_id=(receipt->>'nonconformity_id')::uuid;
   SELECT s.snapshot INTO sources FROM private_isg.workspace_analysis_filed_sources s WHERE s.nonconformity_id=(receipt->>'nonconformity_id')::uuid;
   PERFORM private_isg.set_nonconformity_detail((receipt->>'nonconformity_id')::uuid,sources->>'description',sources->>'recommended_action',
    sources->>'references_text',sources->>'responsible',NULL,NULL,NULL,NULL,NULL,NULL,clock_timestamp());
  END IF;
  RETURN receipt;
 ELSIF p_action IN ('edit','remove','react') THEN
  IF NOT EXISTS(SELECT 1 FROM private_isg.workspace_analysis_findings WHERE analysis_id=analysis_record.id AND workspace_analysis_findings.id=item)
    AND NOT EXISTS(SELECT 1 FROM private_isg.workspace_analysis_expert_items WHERE analysis_id=analysis_record.id AND workspace_analysis_expert_items.id=item)
    AND NOT EXISTS(SELECT 1 FROM private_isg.workspace_analysis_training_items WHERE analysis_id=analysis_record.id AND workspace_analysis_training_items.id=item)
   THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  IF p_action='react' THEN
   INSERT INTO private_isg.expert_analysis_feedback VALUES(w,analysis_record.id,item,actor,p_payload->>'reaction')
   ON CONFLICT(workspace_id,analysis_id,item_id,actor_id) DO UPDATE SET reaction=excluded.reaction;
  ELSIF p_action='remove' THEN
   DELETE FROM private_isg.workspace_analysis_findings WHERE analysis_id=analysis_record.id AND workspace_analysis_findings.id=item;
   DELETE FROM private_isg.workspace_analysis_expert_items WHERE analysis_id=analysis_record.id AND workspace_analysis_expert_items.id=item;
   DELETE FROM private_isg.workspace_analysis_training_items WHERE analysis_id=analysis_record.id AND workspace_analysis_training_items.id=item;
  ELSE
   SELECT * INTO finding_record FROM private_isg.workspace_analysis_findings WHERE analysis_id=analysis_record.id AND workspace_analysis_findings.id=item FOR UPDATE;
   IF finding_record.id IS NOT NULL THEN
    UPDATE private_isg.workspace_analysis_findings SET title=coalesce(p_payload->>'title',title),
     category=coalesce(p_payload->>'category',category),description=coalesce(p_payload->>'body',description),
     recommended_action=coalesce(p_payload->>'measure',recommended_action),references_text=coalesce(p_payload->>'references',references_text),
     fk_probability=coalesce((p_payload->>'fk_probability')::numeric,fk_probability),
     fk_frequency=coalesce((p_payload->>'fk_frequency')::numeric,fk_frequency),
     fk_severity=coalesce((p_payload->>'fk_severity')::numeric,fk_severity),
     m5_probability=coalesce((p_payload->>'m5_probability')::integer,m5_probability),
     m5_severity=coalesce((p_payload->>'m5_severity')::integer,m5_severity),version=version+1
     WHERE workspace_analysis_findings.id=item RETURNING * INTO finding_record;
    IF finding_record.is_scored THEN
     IF finding_record.fk_probability<>ALL(ARRAY[0.2,0.5,1,3,6,10]::numeric[]) OR finding_record.fk_frequency<>ALL(ARRAY[0.5,1,2,3,6,10]::numeric[])
      OR finding_record.fk_severity<>ALL(ARRAY[1,3,7,15,40,100]::numeric[]) OR finding_record.m5_probability NOT BETWEEN 1 AND 5 OR finding_record.m5_severity NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
     score:=finding_record.fk_probability*finding_record.fk_frequency*finding_record.fk_severity; score5:=finding_record.m5_probability*finding_record.m5_severity;
     UPDATE private_isg.workspace_analysis_findings SET fk_score=score,m5_score=score5,
      fk_band=CASE WHEN score>=400 THEN 'critical' WHEN score>=200 THEN 'high' WHEN score>=70 THEN 'medium' ELSE 'low' END,
      m5_band=CASE WHEN score5>=20 THEN 'critical' WHEN score5>=15 THEN 'high' WHEN score5>=6 THEN 'medium' ELSE 'low' END
      WHERE workspace_analysis_findings.id=item;
    END IF;
   ELSE
    UPDATE private_isg.workspace_analysis_expert_items SET title=coalesce(p_payload->>'title',title),body=coalesce(p_payload->>'body',body),
     recommendation=coalesce(p_payload->>'measure',recommendation),references_text=coalesce(p_payload->>'references',references_text),version=version+1 WHERE analysis_id=analysis_record.id AND workspace_analysis_expert_items.id=item;
    UPDATE private_isg.workspace_analysis_training_items SET title=coalesce(p_payload->>'title',title),body=coalesce(p_payload->>'body',body),version=version+1 WHERE analysis_id=analysis_record.id AND workspace_analysis_training_items.id=item;
   END IF;
  END IF;
  UPDATE private_isg.workspace_analyses SET result_version=result_version+1,updated_at=clock_timestamp() WHERE workspace_analyses.id=analysis_record.id;
  RETURN jsonb_build_object('id',analysis_record.id,'item_id',item);
 END IF;
 RAISE EXCEPTION 'VALIDATION_ERROR';
END $$;
REVOKE ALL ON FUNCTION private_isg.expert_analysis(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private_isg.workspace_worker_ai_claim(p_limit integer, p_now timestamp with time zone, p_lease_seconds integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE job private_isg.workspace_ai_jobs; started jsonb; rows jsonb:='[]'; token uuid;
  asset private_isg.workspace_file_assets; provider_hash bytea;
BEGIN
  IF p_limit NOT BETWEEN 1 AND 20 OR p_now IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 600 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR job IN SELECT * FROM private_isg.workspace_ai_jobs j
      WHERE ((j.status='queued' AND j.worker_attempt_count<20) OR
             (j.status='running' AND j.worker_lease_until<=p_now AND j.worker_attempt_count<20))
      ORDER BY j.created_at,j.id FOR UPDATE SKIP LOCKED LIMIT p_limit LOOP
    asset:=NULL;
    IF job.source_kind IN ('photo','document') THEN
      IF job.source_reference ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
        SELECT * INTO asset FROM private_isg.workspace_file_assets
          WHERE id=job.source_reference::uuid AND workspace_id=job.workspace_id
            AND (job.company_id IS NULL OR company_id=job.company_id) AND lifecycle='active';
      END IF;
      IF asset.id IS NULL THEN
        IF job.status='queued' THEN
          PERFORM private_isg.workspace_ai_fail(job.id,'SOURCE_NOT_FOUND',false,p_now);
        ELSE
          PERFORM private_isg.workspace_ai_fail(job.id,'SOURCE_NOT_FOUND',true,p_now);
        END IF;
        CONTINUE;
      END IF;
    END IF;
    provider_hash:=sha256(convert_to('isg-worker:'||job.id::text||':'||job.source_version::text,'UTF8'));
    IF job.status='queued' THEN
      started:=private_isg.workspace_ai_start(job.id,provider_hash,p_now);
      IF started->>'status'<>'running' THEN CONTINUE; END IF;
    END IF;
    token:=gen_random_uuid();
    UPDATE private_isg.workspace_ai_jobs SET worker_token=token,
      worker_lease_until=p_now+make_interval(secs=>p_lease_seconds),
      worker_attempt_count=worker_attempt_count+1,updated_at=clock_timestamp()
      WHERE id=job.id RETURNING * INTO job;
    rows:=rows||jsonb_build_array(jsonb_build_object(
      'job_id',job.id,'worker_token',token,'workspace_id',job.workspace_id,'company_id',job.company_id,
      'feature',job.feature,'model_code',job.model_code,'pricing_version',job.pricing_version,
      'reserve_units',(SELECT p.reserve_units FROM private_isg.workspace_ai_pricing p
        WHERE p.feature=job.feature AND p.model_code=job.model_code AND p.pricing_version=job.pricing_version),
      'source_kind',job.source_kind,'source_reference',job.source_reference,'source_version',job.source_version,
      'source_bucket',asset.bucket,'source_path',asset.object_path,'source_media_type',asset.media_type,
      'source_byte_size',asset.byte_size,'attempt_count',job.worker_attempt_count,
      'source_assets',(SELECT jsonb_agg(jsonb_build_object('bucket',fa.bucket,'path',fa.object_path,'mime',fa.media_type,'bytes',fa.byte_size) ORDER BY x.ordinal)
        FROM private_isg.expert_analysis_inputs i CROSS JOIN LATERAL unnest(i.asset_ids) WITH ORDINALITY x(id,ordinal)
        JOIN private_isg.workspace_file_assets fa ON fa.id=x.id AND fa.workspace_id=job.workspace_id AND fa.company_id=job.company_id AND fa.lifecycle='active' WHERE i.job_id=job.id),
      'expected_source_count',(SELECT cardinality(i.asset_ids) FROM private_isg.expert_analysis_inputs i WHERE i.job_id=job.id),
      'focus_ids',(SELECT to_jsonb(i.focus_ids) FROM private_isg.expert_analysis_inputs i WHERE i.job_id=job.id),
      'sector',(SELECT i.sector FROM private_isg.expert_analysis_inputs i WHERE i.job_id=job.id)));
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'jobs',rows,'claimed',jsonb_array_length(rows));
END $function$
;
ALTER TABLE private_isg.workspace_analysis_filed_sources DROP CONSTRAINT workspace_analysis_filed_sources_source_item_kind_check;
ALTER TABLE private_isg.workspace_analysis_filed_sources ADD CHECK(source_item_kind IN ('finding','expert_item','training_item'));
CREATE OR REPLACE FUNCTION private_isg.workspace_analysis_file(p_mutation uuid, p_workspace uuid, p_company uuid, p_workplace uuid, p_source_scope text, p_analysis uuid, p_item_kind text, p_item uuid, p_severity text, p_opened_on date, p_due_on date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); fingerprint bytea; replay jsonb; snapshot jsonb; target uuid;
  title text; source_version bigint; band text; v_source_ref text; v_source_kind text; created boolean:=false;
  row_json jsonb; result jsonb; method text;
BEGIN
  PERFORM private_isg.workspace_domain_gate('analysis_exports',true);
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_source_scope NOT IN ('workspace','personal') OR p_item_kind NOT IN ('finding','expert_item','training_item') OR
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
  ELSIF p_source_scope='workspace' AND p_item_kind='training_item' THEN
    SELECT jsonb_build_object('title',t.title,'description',t.body,'is_scored',false,'audience',t.audience,'duration_minutes',t.duration_minutes),
      t.title,t.version,'training',NULL INTO snapshot,title,source_version,method,band
      FROM private_isg.workspace_analysis_training_items t WHERE t.workspace_id=p_workspace AND t.company_id=p_company AND t.analysis_id=p_analysis AND t.id=p_item;
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
END $function$
;
