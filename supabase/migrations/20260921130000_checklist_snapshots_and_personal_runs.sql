-- Immutable checklist question snapshots, optimistic template editing and
-- company-free expert runs. Additive, staging-first; catalogue content is
-- still pending professional review and is not published to production.
BEGIN;
SET LOCAL lock_timeout='5s';

ALTER TABLE private_isg.checklist_template_versions
  ADD COLUMN IF NOT EXISTS edit_revision bigint NOT NULL DEFAULT 0;

ALTER TABLE private_isg.checklist_runs
  ALTER COLUMN company_id DROP NOT NULL,
  ALTER COLUMN workplace_id DROP NOT NULL;

ALTER TABLE private_isg.checklist_receipts
  ALTER COLUMN company_id DROP NOT NULL;

DO $$ BEGIN
  ALTER TABLE private_isg.checklist_runs
    ADD CONSTRAINT checklist_runs_scope_shape_check CHECK(
      (company_id IS NOT NULL AND workplace_id IS NOT NULL) OR
      (company_id IS NULL AND workplace_id IS NULL AND owner_id IS NOT NULL)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE private_isg.checklist_run_questions (
  run_id uuid NOT NULL REFERENCES private_isg.checklist_runs(run_id) ON DELETE CASCADE,
  item_code text NOT NULL,
  catalog_item_code text,
  atomic_item_code text,
  prompt text NOT NULL CHECK(btrim(prompt)<>'' AND length(prompt)<=500),
  position integer NOT NULL CHECK(position BETWEEN 1 AND 500),
  section_title text,
  scope_key text,
  allows_not_applicable boolean NOT NULL,
  verification_method text,
  help_text text,
  tags jsonb NOT NULL DEFAULT '[]'::jsonb,
  risk_topic text,
  source_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  na_reason_required boolean NOT NULL DEFAULT false,
  evidence_recommended boolean NOT NULL DEFAULT false,
  photo_required boolean NOT NULL DEFAULT false,
  PRIMARY KEY(run_id,item_code),
  UNIQUE(run_id,position)
);
ALTER TABLE private_isg.checklist_run_questions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.checklist_run_questions FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO private_isg.checklist_run_questions(
  run_id,item_code,catalog_item_code,atomic_item_code,prompt,position,section_title,scope_key,
  allows_not_applicable,verification_method,help_text,tags,risk_topic,source_ids,
  na_reason_required,evidence_recommended,photo_required)
SELECT r.run_id,i.item_code,i.catalog_item_code,i.atomic_item_code,i.prompt,i.position,
  i.section_title,i.scope_key,i.allows_not_applicable,i.verification_method,i.help_text,
  i.tags,i.risk_topic,i.source_ids,i.na_reason_required,i.evidence_recommended,i.photo_required
FROM private_isg.checklist_runs r
JOIN private_isg.checklist_template_items i
  ON i.template_code=r.template_code AND i.version=r.template_version
ON CONFLICT(run_id,item_code) DO NOTHING;

CREATE OR REPLACE FUNCTION private_isg.snapshot_checklist_run() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.revises_run_id IS NOT NULL THEN
    INSERT INTO private_isg.checklist_run_questions(
      run_id,item_code,catalog_item_code,atomic_item_code,prompt,position,section_title,scope_key,
      allows_not_applicable,verification_method,help_text,tags,risk_topic,source_ids,
      na_reason_required,evidence_recommended,photo_required)
    SELECT NEW.run_id,item_code,catalog_item_code,atomic_item_code,prompt,position,section_title,scope_key,
      allows_not_applicable,verification_method,help_text,tags,risk_topic,source_ids,
      na_reason_required,evidence_recommended,photo_required
    FROM private_isg.checklist_run_questions WHERE run_id=NEW.revises_run_id;
  ELSE
    INSERT INTO private_isg.checklist_run_questions(
      run_id,item_code,catalog_item_code,atomic_item_code,prompt,position,section_title,scope_key,
      allows_not_applicable,verification_method,help_text,tags,risk_topic,source_ids,
      na_reason_required,evidence_recommended,photo_required)
    SELECT NEW.run_id,item_code,catalog_item_code,atomic_item_code,prompt,position,section_title,scope_key,
      allows_not_applicable,verification_method,help_text,tags,risk_topic,source_ids,
      na_reason_required,evidence_recommended,photo_required
    FROM private_isg.checklist_template_items
    WHERE template_code=NEW.template_code AND version=NEW.template_version;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM private_isg.checklist_run_questions WHERE run_id=NEW.run_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHECKLIST_SNAPSHOT_EMPTY';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS checklist_run_snapshot_after_insert ON private_isg.checklist_runs;
CREATE TRIGGER checklist_run_snapshot_after_insert
AFTER INSERT ON private_isg.checklist_runs
FOR EACH ROW EXECUTE FUNCTION private_isg.snapshot_checklist_run();

CREATE OR REPLACE FUNCTION private_isg.require_checklist_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); workspace uuid:=private_isg.expert_workspace();
BEGIN
  IF p_write IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF workspace IS NOT NULL THEN
    IF p_company IS NULL THEN
      PERFORM private_isg.checklist_gate(p_write);
      RETURN actor;
    END IF;
    RETURN private_isg.expert_require_company(p_company,p_write,'risk_nonconformity');
  END IF;
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.checklist_gate(p_write);
  IF p_write THEN
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro')
      AND status IN ('active','trialing','grace_period')
      AND (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
  END IF;
  IF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor
      AND (NOT p_write OR NOT is_archived) FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  RETURN actor;
END $$;

CREATE OR REPLACE FUNCTION private_isg.checklist_run_row(p_run uuid,p_items boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs; template private_isg.checklist_templates;
  expected integer; answered integer; failing integer; conforming integer; skipped integer; opened integer;
BEGIN
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO template FROM private_isg.checklist_templates WHERE template_code=run.template_code;
  SELECT count(*) INTO expected FROM private_isg.checklist_run_questions WHERE run_id=p_run;
  SELECT count(*),count(*) FILTER (WHERE result='nonconform'),
         count(*) FILTER (WHERE result='conform'),count(*) FILTER (WHERE result='not_applicable'),
         count(*) FILTER (WHERE nonconformity_id IS NOT NULL)
    INTO answered,failing,conforming,skipped,opened
    FROM private_isg.checklist_run_items WHERE run_id=p_run;
  RETURN jsonb_build_object(
    'id',run.run_id,'company_id',run.company_id,'workplace_id',run.workplace_id,
    'template_code',run.template_code,'catalog_template_code',template.catalog_template_code,
    'template_title',template.title,'template_version',run.template_version,
    'catalog_version',template.catalog_version,'sector_code',template.sector_code,
    'template_kind',template.template_kind,'scope_note',template.scope_note,
    'professional_review_status',template.professional_review_status,'source_ids',template.source_ids,
    'revision',run.edit_revision,'revises_run_id',run.revises_run_id,
    'area_label',run.area_label,'equipment_label',run.equipment_label,
    'document_number',run.document_number,'is_personal',run.company_id IS NULL,
    'state',run.state,'started_on',run.started_on,'submitted_at',run.submitted_at,
    'expected',expected,'answered',answered,'remaining',greatest(expected-answered,0),
    'conform',conforming,'nonconform',failing,'not_applicable',skipped,
    'progress_percent',CASE WHEN expected=0 THEN 0 ELSE round(answered*100.0/expected,1) END,
    'coverage_percent',CASE WHEN expected=0 THEN 0 ELSE round(answered*100.0/expected,1) END,
    'applicable_coverage_percent',CASE WHEN expected-skipped<=0 THEN NULL
      ELSE round((conforming+failing)*100.0/(expected-skipped),1) END,
    'score_percent',CASE WHEN conforming+failing>0 THEN round(conforming*100.0/(conforming+failing),1) END,
    'nonconformities_opened',opened,'auto_nonconformity',false,
    'items',CASE WHEN p_items THEN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'item_code',q.item_code,'catalog_item_code',q.catalog_item_code,'atomic_item_code',q.atomic_item_code,
      'prompt',q.prompt,'position',q.position,'section_title',q.section_title,'scope_key',q.scope_key,
      'allows_not_applicable',q.allows_not_applicable,'verification_method',q.verification_method,
      'help_text',q.help_text,'tags',q.tags,'risk_topic',q.risk_topic,'source_ids',q.source_ids,
      'na_reason_required',q.na_reason_required,'evidence_recommended',q.evidence_recommended,
      'photo_required',q.photo_required,'result',a.result,
      'answer',CASE a.result WHEN 'conform' THEN 'compliant' WHEN 'nonconform' THEN 'non_compliant'
        WHEN 'not_applicable' THEN 'not_applicable' END,
      'note',a.note,'evidence_asset_id',a.evidence_asset_id,'nonconformity_id',a.nonconformity_id,
      'recorded_at',a.recorded_at) ORDER BY q.position),'[]'::jsonb)
      FROM private_isg.checklist_run_questions q LEFT JOIN private_isg.checklist_run_items a
        ON a.run_id=q.run_id AND a.item_code=q.item_code WHERE q.run_id=p_run) END,
    'snapshot_count',expected,'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE OR REPLACE FUNCTION private_isg.record_run_item(p_run uuid,p_item text,p_result text,p_note text,p_asset uuid,
  p_open_nonconformity boolean,p_severity text,p_due_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); run private_isg.checklist_runs;
  item private_isg.checklist_run_questions; existing private_isg.checklist_run_items;
  finding jsonb; record_id uuid; normalized text;
BEGIN
  PERFORM private_isg.checklist_gate(true);
  normalized:=CASE p_result WHEN 'compliant' THEN 'conform' WHEN 'non_compliant' THEN 'nonconform' ELSE p_result END;
  IF p_run IS NULL OR p_item IS NULL OR normalized IS NULL OR p_now IS NULL OR p_open_nonconformity IS NULL OR
     normalized NOT IN ('conform','nonconform','not_applicable') OR
     (p_open_nonconformity AND (normalized<>'nonconform' OR p_severity IS NULL)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF run.state<>'open' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RUN_SUBMITTED'; END IF;
  SELECT * INTO item FROM private_isg.checklist_run_questions WHERE run_id=p_run AND item_code=p_item;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF normalized='not_applicable' AND NOT item.allows_not_applicable THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF normalized IN ('nonconform','not_applicable') AND btrim(coalesce(p_note,''))='' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EXPLANATION_REQUIRED'; END IF;
  IF run.company_id IS NULL AND (p_asset IS NOT NULL OR p_open_nonconformity) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_REQUIRED_FOR_NONCONFORMITY'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets a WHERE a.asset_id=p_asset AND a.company_id=run.company_id
      AND a.scan_status='clean' AND private_isg.expert_company_visible(a.owner_id,a.company_id,actor) FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  SELECT * INTO existing FROM private_isg.checklist_run_items WHERE run_id=p_run AND item_code=p_item;
  record_id:=existing.nonconformity_id;
  IF p_open_nonconformity AND record_id IS NULL THEN
    finding:=private_isg.open_nonconformity(run.company_id,run.workplace_id,'checklist',p_run::text||':'||p_item,
      item.prompt,p_severity,run.started_on,p_due_on,p_now);
    record_id:=(finding->>'nonconformity_id')::uuid;
    UPDATE private_isg.nonconformities SET source_run_id=p_run,source_item_code=p_item
      WHERE nonconformity_id=record_id;
  END IF;
  INSERT INTO private_isg.checklist_run_items(
      run_id,item_code,result,note,evidence_asset_id,nonconformity_id,recorded_at)
    VALUES(p_run,p_item,normalized,nullif(btrim(coalesce(p_note,'')),''),p_asset,record_id,p_now)
  ON CONFLICT(run_id,item_code) DO UPDATE SET result=excluded.result,note=excluded.note,
    evidence_asset_id=excluded.evidence_asset_id,
    nonconformity_id=coalesce(checklist_run_items.nonconformity_id,excluded.nonconformity_id),
    recorded_at=excluded.recorded_at;
  RETURN jsonb_build_object('schema_version',4,'run_id',p_run,'item_code',p_item,'result',normalized,
    'answer',CASE normalized WHEN 'conform' THEN 'compliant' WHEN 'nonconform' THEN 'non_compliant'
      ELSE 'not_applicable' END,'evidence_asset_id',p_asset,'nonconformity_id',record_id,
    'replayed',existing.result IS NOT DISTINCT FROM normalized AND
      existing.note IS NOT DISTINCT FROM nullif(btrim(coalesce(p_note,'')),''));
END $$;

CREATE OR REPLACE FUNCTION private_isg.submit_checklist_run(p_run uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs; expected integer; answered integer;
BEGIN
  PERFORM private_isg.checklist_gate(true);
  IF p_run IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF run.state='submitted' THEN RETURN jsonb_build_object('schema_version',4,'run_id',p_run,'state','submitted','replayed',true); END IF;
  SELECT count(*) INTO expected FROM private_isg.checklist_run_questions WHERE run_id=p_run;
  SELECT count(*) INTO answered FROM private_isg.checklist_run_items WHERE run_id=p_run;
  IF answered<expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RUN_INCOMPLETE'; END IF;
  UPDATE private_isg.checklist_runs SET state='submitted',submitted_at=p_now WHERE run_id=p_run;
  RETURN jsonb_build_object('schema_version',4,'run_id',p_run,'state','submitted','items',answered,'replayed',false);
END $$;

-- Keep the complete company implementation intact and put the personal-run
-- branch in front of it. The public wrapper is rebound to this new function.
ALTER FUNCTION private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer)
  RENAME TO read_checklists_company_v3;
ALTER FUNCTION private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb)
  RENAME TO mutate_checklists_company_v3;

CREATE FUNCTION private_isg.read_checklists(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_template text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.require_checklist_company(p_company,false); today date;
  page_limit integer; page_offset integer; needle text; tally_all jsonb; tally_companies jsonb;
  tally_rows jsonb; matching_rows integer;
BEGIN
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
  IF p_kind='templates' THEN
    RETURN jsonb_build_object('schema_version',4,'kind','templates','rows',(
      SELECT coalesce(jsonb_agg(jsonb_build_object('template_code',t.template_code,'title',t.title,
        'is_product',false,'is_archived',t.is_archived,'catalog_version',t.catalog_version,
        'catalog_template_code',t.catalog_template_code,'versions',(SELECT coalesce(jsonb_agg(
          jsonb_build_object('version',v.version,'revision',v.edit_revision,'status',v.status,
            'published_at',v.published_at,'approval_note',v.approval_note,
            'items',(SELECT coalesce(jsonb_agg(jsonb_build_object(
              'item_code',i.item_code,'atomic_item_code',i.atomic_item_code,'prompt',i.prompt,
              'position',i.position,'section_title',i.section_title,'scope_key',i.scope_key,
              'allows_not_applicable',i.allows_not_applicable,'verification_method',i.verification_method,
              'help_text',i.help_text,'tags',i.tags,'risk_topic',i.risk_topic,'source_ids',i.source_ids,
              'na_reason_required',i.na_reason_required,'evidence_recommended',i.evidence_recommended,
              'photo_required',i.photo_required) ORDER BY i.position),'[]'::jsonb)
              FROM private_isg.checklist_template_items i
              WHERE i.template_code=v.template_code AND i.version=v.version))
          ORDER BY v.version DESC),'[]'::jsonb) FROM private_isg.checklist_template_versions v
          WHERE v.template_code=t.template_code)) ORDER BY t.title),'[]'::jsonb)
      FROM private_isg.checklist_templates t WHERE t.owner_id=actor
        AND t.workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace()),
      'approval_is_self_declared',true,'product_templates_offered',true);
  END IF;
  IF p_kind='detail' AND p_id IS NOT NULL AND EXISTS(
      SELECT 1 FROM private_isg.checklist_runs r WHERE r.run_id=p_id AND r.company_id IS NULL
        AND r.owner_id=actor AND r.workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace()) THEN
    RETURN jsonb_build_object('schema_version',4,'kind','detail','today',today,
      'row',private_isg.checklist_run_row(p_id,true));
  END IF;
  IF p_kind<>'list' OR p_company IS NOT NULL THEN
    RETURN private_isg.read_checklists_company_v3(p_company,p_kind,p_query,p_state,p_workplace,
      p_template,p_id,p_limit,p_offset);
  END IF;
  IF p_state IS NOT NULL AND p_state NOT IN ('open','submitted','cancelled') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(private_isg.checklist_search_fold(p_query),'');
  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor)
      AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), base AS (
    SELECT r.run_id,r.company_id,s.name AS company_name,r.workplace_id,w.name AS workplace_name,
      r.template_code,t.title AS template_title,r.state AS entry_state,r.started_on
    FROM private_isg.checklist_runs r JOIN scope s ON s.id=r.company_id
    JOIN private_isg.workplaces w ON w.company_id=r.company_id AND w.id=r.workplace_id
    JOIN private_isg.checklist_templates t ON t.template_code=r.template_code
    WHERE private_isg.expert_company_visible(r.owner_id,r.company_id,actor)
    UNION ALL
    SELECT r.run_id,NULL::uuid,NULL::text,NULL::uuid,NULL::text,r.template_code,t.title,r.state,r.started_on
    FROM private_isg.checklist_runs r JOIN private_isg.checklist_templates t ON t.template_code=r.template_code
    WHERE r.company_id IS NULL AND r.owner_id=actor
      AND r.workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace()
  ), page AS (
    SELECT b.*,row_number() OVER(ORDER BY CASE entry_state WHEN 'open' THEN 0 WHEN 'submitted' THEN 1 ELSE 2 END,
      started_on DESC,coalesce(company_name,''),coalesce(workplace_name,''),run_id) AS ordinal FROM base b
  ), filtered AS (
    SELECT * FROM page WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_template IS NULL OR template_code=p_template) AND (p_state IS NULL OR entry_state=p_state)
      AND (needle IS NULL OR private_isg.checklist_search_fold(template_title) LIKE '%'||needle||'%'
        OR private_isg.checklist_search_fold(workplace_name) LIKE '%'||needle||'%'
        OR private_isg.checklist_search_fold(company_name) LIKE '%'||needle||'%')
  )
  SELECT (SELECT coalesce(jsonb_object_agg(state,total),'{}') FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
      ORDER BY name),'[]') FROM (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          WHERE company_id IS NOT NULL GROUP BY company_id,company_name,entry_state) b
        GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]') FROM (
      SELECT picked.ordinal AS sort,private_isg.checklist_run_row(picked.run_id,false)
        ||jsonb_build_object('company_name',picked.company_name,'workplace_name',picked.workplace_name) AS entry
      FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;
  RETURN jsonb_build_object('schema_version',4,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,'total',matching_rows,
    'returned',jsonb_array_length(tally_rows),'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'compliance_verdict',NULL,
    'auto_nonconformity',false,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.mutate_checklists(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.require_checklist_company(p_company,true);
  prior private_isg.checklist_receipts; fingerprint bytea; result jsonb; answer jsonb;
  entry private_isg.checklist_runs; run uuid; revised uuid; template_version integer;
  expected_revision bigint; stamp timestamptz:=clock_timestamp(); today date;
  template_action boolean:=p_action=ANY(ARRAY['copy_items','reorder_items','set_item','remove_item','publish_template']);
  clean_payload jsonb;
BEGIN
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>65536 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;

  IF template_action THEN
    clean_payload:=p_payload-'expected_revision';
    SELECT * INTO prior FROM private_isg.checklist_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
    IF FOUND THEN
      RETURN private_isg.mutate_checklists_company_v3(p_company,p_action,p_operation,p_mutation,clean_payload);
    END IF;
    IF p_payload->>'expected_revision' IS NULL OR p_payload->>'template_code' IS NULL OR
       p_payload->>'version' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    expected_revision:=(p_payload->>'expected_revision')::bigint;
    PERFORM 1 FROM private_isg.checklist_template_versions v
      JOIN private_isg.checklist_templates t ON t.template_code=v.template_code
      WHERE v.template_code=p_payload->>'template_code' AND v.version=(p_payload->>'version')::integer
        AND v.edit_revision=expected_revision AND t.owner_id=actor
        AND t.workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace() FOR UPDATE OF v;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHECKLIST_CONFLICT'; END IF;
    result:=private_isg.mutate_checklists_company_v3(p_company,p_action,p_operation,p_mutation,clean_payload);
    UPDATE private_isg.checklist_template_versions SET edit_revision=edit_revision+1
      WHERE template_code=p_payload->>'template_code' AND version=(p_payload->>'version')::integer;
    RETURN result||jsonb_build_object('template_revision',expected_revision+1);
  END IF;

  IF p_action='revise_run' OR (p_company IS NULL AND p_action=ANY(ARRAY[
      'start_run','record_item','submit_run','cancel_run'])) THEN
    fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
    PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-checklist:'||p_mutation::text,0));
    SELECT * INTO prior FROM private_isg.checklist_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
    IF FOUND THEN
      IF prior.request_hash IS DISTINCT FROM fingerprint THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
      RETURN prior.response||jsonb_build_object('replayed',true);
    END IF;
    IF p_action='start_run' THEN
      IF p_company IS NOT NULL OR p_payload->>'template_code' IS NULL OR p_payload->>'workplace_id' IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,false);
      SELECT version INTO template_version FROM private_isg.checklist_template_versions
        WHERE template_code=p_payload->>'template_code' AND status='published' FOR SHARE;
      IF template_version IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      INSERT INTO private_isg.checklist_runs(company_id,owner_id,workspace_id,workplace_id,
        template_code,template_version,started_on,created_at,created_by_user_id,updated_by_user_id,
        area_label,equipment_label,document_number)
      VALUES(NULL,actor,private_isg.expert_workspace(),NULL,p_payload->>'template_code',template_version,
        coalesce((p_payload->>'started_on')::date,today),stamp,actor,actor,
        nullif(btrim(p_payload->>'area_label'),''),nullif(btrim(p_payload->>'equipment_label'),''),
        nullif(btrim(p_payload->>'document_number'),'')) RETURNING run_id INTO run;
      answer:=jsonb_build_object('schema_version',4,'run_id',run,'template_code',p_payload->>'template_code',
        'template_version',template_version,'state','open','personal',true);
    ELSE
      run:=(p_payload->>'run_id')::uuid;
      SELECT * INTO entry FROM private_isg.checklist_runs WHERE run_id=run
        AND ((company_id IS NULL AND owner_id=actor
          AND workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace()) OR
          (company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor))) FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF p_payload->>'expected_revision' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      expected_revision:=(p_payload->>'expected_revision')::bigint;
      IF entry.edit_revision<>expected_revision THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHECKLIST_CONFLICT'; END IF;
      IF p_action='revise_run' THEN
        IF entry.state<>'submitted' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
        INSERT INTO private_isg.checklist_runs(company_id,owner_id,workspace_id,workplace_id,
          template_code,template_version,started_on,created_at,created_by_user_id,updated_by_user_id,
          revises_run_id,area_label,equipment_label,document_number)
        VALUES(entry.company_id,entry.owner_id,entry.workspace_id,entry.workplace_id,
          entry.template_code,entry.template_version,coalesce((p_payload->>'started_on')::date,today),
          stamp,actor,actor,entry.run_id,entry.area_label,entry.equipment_label,entry.document_number)
        RETURNING run_id INTO revised;
        INSERT INTO private_isg.checklist_run_items(run_id,item_code,result,note,evidence_asset_id,recorded_at)
          SELECT revised,item_code,result,note,evidence_asset_id,stamp FROM private_isg.checklist_run_items
          WHERE run_id=entry.run_id;
        run:=revised;
        answer:=jsonb_build_object('schema_version',4,'run_id',run,'revises_run_id',entry.run_id,'state','open');
      ELSIF p_action='record_item' THEN
        IF p_payload->>'item_code' IS NULL OR p_payload->>'result' IS NULL THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
        answer:=private_isg.record_run_item(run,p_payload->>'item_code',p_payload->>'result',
          nullif(btrim(coalesce(p_payload->>'note','')),''),(p_payload->>'evidence_asset_id')::uuid,
          coalesce((p_payload->>'open_nonconformity')::boolean,false),
          nullif(btrim(coalesce(p_payload->>'severity','')),''),(p_payload->>'due_on')::date,stamp);
        UPDATE private_isg.checklist_runs SET edit_revision=edit_revision+1,updated_by_user_id=actor,
          updated_at=stamp WHERE run_id=run;
      ELSIF p_action='submit_run' THEN
        answer:=private_isg.submit_checklist_run(run,stamp);
        UPDATE private_isg.checklist_runs SET edit_revision=edit_revision+1,updated_by_user_id=actor,
          updated_at=stamp WHERE run_id=run;
      ELSIF p_action='cancel_run' THEN
        answer:=private_isg.cancel_checklist_run(run,stamp);
        UPDATE private_isg.checklist_runs SET edit_revision=edit_revision+1,updated_by_user_id=actor,
          updated_at=stamp WHERE run_id=run;
      ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    END IF;
    result:=jsonb_build_object('schema_version',4,'action',p_action,'answer',answer,'run_id',run,
      'row',private_isg.checklist_run_row(run,true),'auto_nonconformity',false);
    INSERT INTO private_isg.checklist_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
      VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
    RETURN result||jsonb_build_object('replayed',false);
  END IF;

  RETURN private_isg.mutate_checklists_company_v3(p_company,p_action,p_operation,p_mutation,p_payload);
END $$;

CREATE OR REPLACE FUNCTION public.isg_checklists_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_template text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_checklists(p_company,p_kind,p_query,p_state,p_workplace,p_template,p_id,p_limit,p_offset)
$$;
CREATE OR REPLACE FUNCTION public.isg_checklists_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_checklists(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.snapshot_checklist_run(),
  private_isg.require_checklist_company(uuid,boolean),private_isg.checklist_run_row(uuid,boolean),
  private_isg.record_run_item(uuid,text,text,text,uuid,boolean,text,date,timestamptz),
  private_isg.submit_checklist_run(uuid,timestamptz),
  private_isg.read_checklists_company_v3(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists_company_v3(uuid,text,uuid,uuid,jsonb),
  private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb),
  public.isg_checklists_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_checklists_mutate_v1(uuid,text,uuid,uuid,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb),
  public.isg_checklists_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_checklists_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
