-- Complete the verified checklist catalogue runtime: item search, composed
-- templates, managed assignments and optimistic concurrency for field runs.
-- Additive and staging-first; the catalogue remains pending domain review.
BEGIN;
SET LOCAL lock_timeout='5s';

-- OSGB companies are workspace-owned and intentionally have no personal
-- companies.user_id. Assignment authority is checked by the RPC and stored
-- workspace_id; owner_id remains populated for personal companies only.
ALTER TABLE private_isg.checklist_template_assignments
  ALTER COLUMN owner_id DROP NOT NULL;

ALTER TABLE private_isg.checklist_template_items
  ADD COLUMN IF NOT EXISTS section_title text,
  ADD COLUMN IF NOT EXISTS scope_key text;

ALTER TABLE private_isg.checklist_runs
  ADD COLUMN IF NOT EXISTS edit_revision bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS revises_run_id uuid,
  ADD COLUMN IF NOT EXISTS area_label text,
  ADD COLUMN IF NOT EXISTS equipment_label text,
  ADD COLUMN IF NOT EXISTS document_number text;

DO $$ BEGIN
  ALTER TABLE private_isg.checklist_runs
    ADD CONSTRAINT checklist_runs_revises_fk FOREIGN KEY(revises_run_id)
      REFERENCES private_isg.checklist_runs(run_id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS checklist_runs_revision_idx
  ON private_isg.checklist_runs(revises_run_id) WHERE revises_run_id IS NOT NULL;

-- Reordering a complete draft is one statement and is validated at commit.
DO $$ BEGIN
  ALTER TABLE private_isg.checklist_template_items
    DROP CONSTRAINT checklist_template_items_template_code_version_position_key;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE private_isg.checklist_template_items
    ADD CONSTRAINT checklist_template_items_template_code_version_position_key
      UNIQUE(template_code,version,position) DEFERRABLE INITIALLY DEFERRED;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION private_isg.checklist_run_row(p_run uuid,p_items boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs; template private_isg.checklist_templates;
  expected integer; answered integer; failing integer; conforming integer; skipped integer; opened integer;
BEGIN
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO template FROM private_isg.checklist_templates WHERE template_code=run.template_code;
  SELECT count(*) INTO expected FROM private_isg.checklist_template_items
    WHERE template_code=run.template_code AND version=run.template_version;
  SELECT count(*),count(*) FILTER (WHERE result='nonconform'),
         count(*) FILTER (WHERE result='conform'),
         count(*) FILTER (WHERE result='not_applicable'),
         count(*) FILTER (WHERE nonconformity_id IS NOT NULL)
    INTO answered,failing,conforming,skipped,opened
    FROM private_isg.checklist_run_items WHERE run_id=p_run;
  RETURN jsonb_build_object(
    'id',run.run_id,'company_id',run.company_id,'workplace_id',run.workplace_id,
    'template_code',run.template_code,'catalog_template_code',template.catalog_template_code,
    'template_title',template.title,'template_version',run.template_version,
    'catalog_version',template.catalog_version,'sector_code',template.sector_code,
    'template_kind',template.template_kind,'scope_note',template.scope_note,
    'professional_review_status',template.professional_review_status,
    'source_ids',template.source_ids,'revision',run.edit_revision,
    'revises_run_id',run.revises_run_id,'area_label',run.area_label,
    'equipment_label',run.equipment_label,'document_number',run.document_number,
    'state',run.state,'started_on',run.started_on,'submitted_at',run.submitted_at,
    'expected',expected,'answered',answered,'remaining',greatest(expected-answered,0),
    'conform',conforming,'nonconform',failing,'not_applicable',skipped,
    'progress_percent',CASE WHEN expected=0 THEN 0 ELSE round(answered*100.0/expected,1) END,
    'coverage_percent',CASE WHEN expected=0 THEN 0 ELSE round(answered*100.0/expected,1) END,
    'applicable_coverage_percent',CASE WHEN expected-skipped<=0 THEN NULL
      ELSE round((conforming+failing)*100.0/(expected-skipped),1) END,
    'score_percent',CASE WHEN conforming+failing>0
      THEN round(conforming*100.0/(conforming+failing),1) END,
    'nonconformities_opened',opened,'auto_nonconformity',false,
    'items',CASE WHEN p_items THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object(
          'item_code',t.item_code,'catalog_item_code',t.catalog_item_code,
          'atomic_item_code',t.atomic_item_code,'prompt',t.prompt,
          'position',t.position,'section_title',t.section_title,'scope_key',t.scope_key,
          'allows_not_applicable',t.allows_not_applicable,
          'verification_method',t.verification_method,'help_text',t.help_text,'tags',t.tags,
          'risk_topic',t.risk_topic,'source_ids',t.source_ids,
          'na_reason_required',t.na_reason_required,'evidence_recommended',t.evidence_recommended,
          'photo_required',t.photo_required,'result',r.result,
          'answer',CASE r.result WHEN 'conform' THEN 'compliant'
            WHEN 'nonconform' THEN 'non_compliant' WHEN 'not_applicable' THEN 'not_applicable' END,
          'note',r.note,'evidence_asset_id',r.evidence_asset_id,
          'nonconformity_id',r.nonconformity_id,'recorded_at',r.recorded_at)
          ORDER BY t.position),'[]'::jsonb)
       FROM private_isg.checklist_template_items t
       LEFT JOIN private_isg.checklist_run_items r ON r.run_id=p_run AND r.item_code=t.item_code
       WHERE t.template_code=run.template_code AND t.version=run.template_version) END,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE OR REPLACE FUNCTION private_isg.read_checklists(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_template text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date; page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer; catalog text;
BEGIN
  actor:=private_isg.require_checklist_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','library','template_detail','templates','assignments','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
  SELECT catalog_version INTO catalog FROM private_isg.checklist_catalogs ORDER BY generated_on DESC LIMIT 1;
  page_limit:=least(greatest(coalesce(p_limit,20),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(private_isg.checklist_search_fold(btrim(coalesce(p_query,''))),'');

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',3,'kind','catalog','catalog_version',catalog,
      'publication_status',(SELECT publication_status FROM private_isg.checklist_catalogs WHERE catalog_version=catalog),
      'professional_review_status',(SELECT professional_review_status FROM private_isg.checklist_catalogs WHERE catalog_version=catalog),
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w WHERE p_company IS NOT NULL AND w.company_id=p_company
          AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived),
      'templates',(SELECT coalesce(jsonb_agg(jsonb_build_object(
          'template_code',t.template_code,'catalog_template_code',t.catalog_template_code,
          'title',t.title,'version',v.version,'items',(SELECT count(*)
            FROM private_isg.checklist_template_items i WHERE i.template_code=t.template_code AND i.version=v.version),
          'is_product',t.owner_id IS NULL,'sector_code',t.sector_code,'kind',t.template_kind,
          'scope_note',t.scope_note,'professional_review_status',t.professional_review_status)
          ORDER BY (t.owner_id IS NOT NULL),t.title),'[]'::jsonb)
        FROM private_isg.checklist_templates t JOIN private_isg.checklist_template_versions v
          ON v.template_code=t.template_code AND v.status='published'
        WHERE NOT t.is_archived AND ((t.owner_id IS NULL AND t.workspace_id IS NULL)
          OR (t.owner_id=actor AND t.workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace()))),
      'product_templates_offered',true,'product_template_count',
        (SELECT count(*) FROM private_isg.checklist_catalog_templates WHERE catalog_version=catalog),
      'auto_nonconformity',false,'health_records_tracked',false);
  END IF;

  IF p_kind='library' THEN
    RETURN jsonb_build_object('schema_version',3,'kind','library','catalog_version',catalog,
      'publication_status',(SELECT publication_status FROM private_isg.checklist_catalogs WHERE catalog_version=catalog),
      'professional_review_status',(SELECT professional_review_status FROM private_isg.checklist_catalogs WHERE catalog_version=catalog),
      'sectors',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.sector_code,'name',s.name,'count',
          (SELECT count(*) FROM private_isg.checklist_catalog_templates t WHERE t.catalog_version=catalog
            AND t.sector_code=s.sector_code)) ORDER BY s.name),'[]'::jsonb)
        FROM private_isg.checklist_catalog_sectors s WHERE s.catalog_version=catalog),
      'rows',(SELECT coalesce(jsonb_agg(row_data ORDER BY title),'[]'::jsonb) FROM (
        SELECT t.title,jsonb_build_object('template_code',t.runtime_template_code,
          'catalog_template_code',t.template_code,'title',t.title,'sector_code',t.sector_code,
          'sector_name',t.sector_name,'kind',t.kind,'aliases',t.aliases,'scope_note',t.scope_note,
          'professional_review_status',t.professional_review_status,'items',t.item_count,
          'source_ids',t.source_ids) AS row_data
        FROM private_isg.checklist_catalog_templates t WHERE t.catalog_version=catalog
          AND (p_template IS NULL OR t.sector_code=p_template) AND (p_state IS NULL OR t.kind=p_state)
          AND (needle IS NULL OR t.search_document LIKE '%'||needle||'%'
            OR EXISTS(SELECT 1 FROM private_isg.checklist_catalog_items i
              WHERE i.catalog_version=t.catalog_version AND i.template_code=t.template_code
                AND i.search_document LIKE '%'||needle||'%'))
        ORDER BY t.title LIMIT page_limit OFFSET page_offset) page),
      'matched_items',CASE WHEN needle IS NULL THEN '[]'::jsonb ELSE
        (SELECT coalesce(jsonb_agg(item_row ORDER BY prompt),'[]'::jsonb) FROM (
          SELECT min(i.prompt) AS prompt,jsonb_build_object('atomic_item_code',i.atomic_item_code,
            'prompt',min(i.prompt),'verification_method',min(i.verification_method),
            'risk_topic',min(i.risk_topic),'tags',coalesce(jsonb_agg(DISTINCT tag.value)
              FILTER (WHERE tag.value IS NOT NULL),'[]'::jsonb),
            'source_ids',(SELECT coalesce(jsonb_agg(DISTINCT source.value),'[]'::jsonb)
              FROM private_isg.checklist_catalog_items si
              CROSS JOIN LATERAL jsonb_array_elements_text(si.source_ids) source(value)
              WHERE si.catalog_version=catalog AND si.atomic_item_code=i.atomic_item_code),
            'contexts',jsonb_agg(DISTINCT jsonb_build_object('template_code',t.runtime_template_code,
              'catalog_template_code',t.template_code,'title',t.title,'sector_code',t.sector_code,
              'sector_name',t.sector_name,'item_code',i.item_code))) AS item_row
          FROM private_isg.checklist_catalog_items i
          JOIN private_isg.checklist_catalog_templates t ON t.catalog_version=i.catalog_version
            AND t.template_code=i.template_code
          LEFT JOIN LATERAL jsonb_array_elements_text(i.tags) tag(value) ON true
          WHERE i.catalog_version=catalog AND i.search_document LIKE '%'||needle||'%'
            AND (p_template IS NULL OR t.sector_code=p_template) AND (p_state IS NULL OR t.kind=p_state)
          GROUP BY i.atomic_item_code ORDER BY min(i.prompt) LIMIT 50) matches) END,
      'total',(SELECT count(*) FROM private_isg.checklist_catalog_templates t
        WHERE t.catalog_version=catalog AND (p_template IS NULL OR t.sector_code=p_template)
          AND (p_state IS NULL OR t.kind=p_state)
          AND (needle IS NULL OR t.search_document LIKE '%'||needle||'%'
            OR EXISTS(SELECT 1 FROM private_isg.checklist_catalog_items i
              WHERE i.catalog_version=t.catalog_version AND i.template_code=t.template_code
                AND i.search_document LIKE '%'||needle||'%'))),
      'limit',page_limit,'offset',page_offset);
  END IF;

  IF p_kind='template_detail' THEN
    IF p_template IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM private_isg.require_checklist_template(p_template,actor,false);
    RETURN jsonb_build_object('schema_version',3,'kind','template_detail','row',(
      SELECT jsonb_build_object('template_code',t.template_code,'catalog_template_code',t.catalog_template_code,
        'catalog_version',t.catalog_version,'title',t.title,'sector_code',t.sector_code,
        'kind',t.template_kind,'aliases',t.aliases,'scope_note',t.scope_note,'source_ids',t.source_ids,
        'is_product',t.owner_id IS NULL,'professional_review_status',t.professional_review_status,
        'version',v.version,'items',(SELECT coalesce(jsonb_agg(jsonb_build_object(
          'item_code',i.item_code,'catalog_item_code',i.catalog_item_code,
          'atomic_item_code',i.atomic_item_code,'prompt',i.prompt,'position',i.position,
          'section_title',i.section_title,'scope_key',i.scope_key,
          'allows_not_applicable',i.allows_not_applicable,'verification_method',i.verification_method,
          'help_text',i.help_text,'tags',i.tags,'risk_topic',i.risk_topic,'source_ids',i.source_ids,
          'na_reason_required',i.na_reason_required,'evidence_recommended',i.evidence_recommended,
          'photo_required',i.photo_required) ORDER BY i.position),'[]'::jsonb)
          FROM private_isg.checklist_template_items i
          WHERE i.template_code=t.template_code AND i.version=v.version))
      FROM private_isg.checklist_templates t JOIN private_isg.checklist_template_versions v
        ON v.template_code=t.template_code AND v.status='published' WHERE t.template_code=p_template));
  END IF;

  IF p_kind='templates' THEN
    RETURN jsonb_build_object('schema_version',3,'kind','templates','rows',(
      SELECT coalesce(jsonb_agg(jsonb_build_object('template_code',t.template_code,'title',t.title,
        'is_product',false,'is_archived',t.is_archived,'catalog_version',t.catalog_version,
        'catalog_template_code',t.catalog_template_code,'versions',(SELECT coalesce(jsonb_agg(
          jsonb_build_object('version',v.version,'status',v.status,'published_at',v.published_at,
            'approval_note',v.approval_note,'items',(SELECT coalesce(jsonb_agg(jsonb_build_object(
              'item_code',i.item_code,'atomic_item_code',i.atomic_item_code,'prompt',i.prompt,
              'position',i.position,'section_title',i.section_title,'scope_key',i.scope_key,
              'allows_not_applicable',i.allows_not_applicable,'verification_method',i.verification_method,
              'help_text',i.help_text,'tags',i.tags,'risk_topic',i.risk_topic,
              'source_ids',i.source_ids,'na_reason_required',i.na_reason_required,
              'evidence_recommended',i.evidence_recommended,'photo_required',i.photo_required)
              ORDER BY i.position),'[]'::jsonb) FROM private_isg.checklist_template_items i
              WHERE i.template_code=v.template_code AND i.version=v.version))
          ORDER BY v.version DESC),'[]'::jsonb) FROM private_isg.checklist_template_versions v
          WHERE v.template_code=t.template_code)) ORDER BY t.title),'[]'::jsonb)
      FROM private_isg.checklist_templates t WHERE t.owner_id=actor
        AND t.workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace()),
      'approval_is_self_declared',true,'product_templates_offered',true);
  END IF;

  IF p_kind='assignments' THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    RETURN jsonb_build_object('schema_version',3,'kind','assignments','rows',(
      SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.assignment_id,'company_id',a.company_id,
        'workplace_id',a.workplace_id,'workplace_name',w.name,'template_code',a.template_code,
        'template_title',t.title,'template_version',a.template_version,'assigned_at',a.assigned_at)
        ORDER BY a.assigned_at DESC),'[]'::jsonb)
      FROM private_isg.checklist_template_assignments a
      JOIN private_isg.checklist_templates t ON t.template_code=a.template_code
      LEFT JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.workplace_id
      WHERE a.company_id=p_company AND a.is_active));
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.checklist_runs r JOIN public.companies c
      ON c.id=r.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor)
      WHERE r.run_id=p_id AND (p_company IS NULL OR r.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',3,'kind','detail','today',today,
      'row',private_isg.checklist_run_row(p_id,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('open','submitted','cancelled') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor)
      AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), page AS (
    SELECT r.run_id,r.company_id,s.name AS company_name,r.workplace_id,w.name AS workplace_name,
      r.template_code,t.title AS template_title,r.state AS entry_state,r.started_on,
      row_number() OVER (ORDER BY CASE r.state WHEN 'open' THEN 0 WHEN 'submitted' THEN 1 ELSE 2 END,
        r.started_on DESC,s.name,w.name,r.run_id) AS ordinal
    FROM private_isg.checklist_runs r JOIN scope s ON s.id=r.company_id
    JOIN private_isg.workplaces w ON w.company_id=r.company_id AND w.id=r.workplace_id
    JOIN private_isg.checklist_templates t ON t.template_code=r.template_code
    WHERE private_isg.expert_company_visible(r.owner_id,r.company_id,actor)
  ), filtered AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
      AND (p_workplace IS NULL OR workplace_id=p_workplace)
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
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]') FROM (
      SELECT picked.ordinal AS sort,private_isg.checklist_run_row(picked.run_id,false)
        ||jsonb_build_object('company_name',picked.company_name,'workplace_name',picked.workplace_name) AS entry
      FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;
  RETURN jsonb_build_object('schema_version',3,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,'total',matching_rows,
    'returned',jsonb_array_length(tally_rows),'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'compliance_verdict',NULL,
    'auto_nonconformity',false,'health_records_tracked',false);
END $$;

CREATE OR REPLACE FUNCTION private_isg.mutate_checklists(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.checklist_receipts;
  result jsonb; answer jsonb; run uuid; entry private_isg.checklist_runs;
  source_template private_isg.checklist_templates; source_version integer; copied_code text;
  copied_title text; company_owner uuid; assignment uuid; picked jsonb; picked_row record;
  target_version integer; next_position integer; generated_code text; duplicate_count integer;
  expected_revision bigint; revised uuid; ordered_count integer;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_checklist_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>65536 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;
  allowed:=CASE p_action
    WHEN 'draft_template' THEN ARRAY['title']
    WHEN 'copy_template' THEN ARRAY['template_code','title']
    WHEN 'copy_items' THEN ARRAY['template_code','version','items']
    WHEN 'reorder_items' THEN ARRAY['template_code','version','item_codes']
    WHEN 'assign_template' THEN ARRAY['template_code','workplace_id']
    WHEN 'deactivate_assignment' THEN ARRAY['assignment_id']
    WHEN 'set_item' THEN ARRAY['template_code','version','item_code','prompt','allows_not_applicable','position','section_title','scope_key']
    WHEN 'remove_item' THEN ARRAY['template_code','version','item_code']
    WHEN 'publish_template' THEN ARRAY['template_code','version','approval_note']
    WHEN 'start_run' THEN ARRAY['workplace_id','template_code','started_on','area_label','equipment_label','document_number']
    WHEN 'revise_run' THEN ARRAY['run_id','started_on']
    WHEN 'record_item' THEN ARRAY['run_id','item_code','result','note','evidence_asset_id',
      'open_nonconformity','severity','due_on','expected_revision']
    WHEN 'submit_run' THEN ARRAY['run_id','expected_revision']
    WHEN 'cancel_run' THEN ARRAY['run_id','expected_revision']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-checklist:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.checklist_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='draft_template' THEN
    IF p_payload->>'title' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.draft_checklist_template(actor,p_payload->>'title',stamp);
  ELSIF p_action='copy_template' THEN
    IF p_payload->>'template_code' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO source_template FROM private_isg.checklist_templates
      WHERE template_code=p_payload->>'template_code' AND owner_id IS NULL AND workspace_id IS NULL FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    SELECT version INTO source_version FROM private_isg.checklist_template_versions
      WHERE template_code=source_template.template_code AND status='published' FOR SHARE;
    copied_title:=private_isg.text_value(coalesce(nullif(btrim(p_payload->>'title'),''),source_template.title),200);
    copied_code:=private_isg.checklist_template_code(actor,copied_title||':'||source_template.template_code);
    INSERT INTO private_isg.checklist_templates(template_code,title,owner_id,is_archived,workspace_id,
      catalog_version,catalog_template_code,sector_code,template_kind,aliases,scope_note,
      professional_review_status,source_ids,created_at)
    VALUES(copied_code,copied_title,actor,false,private_isg.expert_workspace(),source_template.catalog_version,
      source_template.catalog_template_code,source_template.sector_code,source_template.template_kind,
      source_template.aliases,source_template.scope_note,source_template.professional_review_status,
      source_template.source_ids,stamp) ON CONFLICT(template_code) DO NOTHING;
    IF NOT EXISTS(SELECT 1 FROM private_isg.checklist_template_versions
        WHERE template_code=copied_code AND status='draft') THEN
      INSERT INTO private_isg.checklist_template_versions(template_code,version,status,created_at)
      VALUES(copied_code,1,'draft',stamp);
      INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,
        allows_not_applicable,position,atomic_item_code,verification_method,help_text,tags,risk_topic,
        source_ids,na_reason_required,evidence_recommended,photo_required,catalog_item_code,section_title,scope_key)
      SELECT copied_code,1,item_code,prompt,allows_not_applicable,position,atomic_item_code,
        verification_method,help_text,tags,risk_topic,source_ids,na_reason_required,
        evidence_recommended,photo_required,catalog_item_code,section_title,scope_key
      FROM private_isg.checklist_template_items
      WHERE template_code=source_template.template_code AND version=source_version;
    END IF;
    answer:=jsonb_build_object('schema_version',3,'template_code',copied_code,'version',1,
      'source_template_code',source_template.template_code,'status','draft');
  ELSIF p_action='copy_items' THEN
    IF p_payload->>'template_code' IS NULL OR p_payload->>'version' IS NULL OR
       jsonb_typeof(p_payload->'items')<>'array' OR jsonb_array_length(p_payload->'items') NOT BETWEEN 1 AND 100 THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    target_version:=(p_payload->>'version')::integer;
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,true);
    PERFORM 1 FROM private_isg.checklist_template_versions WHERE template_code=p_payload->>'template_code'
      AND version=target_version AND status='draft' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_PUBLISHED'; END IF;
    SELECT coalesce(max(position),0) INTO next_position FROM private_isg.checklist_template_items
      WHERE template_code=p_payload->>'template_code' AND version=target_version;
    FOR picked IN SELECT value FROM jsonb_array_elements(p_payload->'items') LOOP
      IF picked->>'source_template_code' IS NULL OR picked->>'source_item_code' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT i.*,t.owner_id INTO picked_row FROM private_isg.checklist_template_items i
        JOIN private_isg.checklist_templates t ON t.template_code=i.template_code
        JOIN private_isg.checklist_template_versions v ON v.template_code=i.template_code AND v.version=i.version
        WHERE i.template_code=picked->>'source_template_code' AND i.item_code=picked->>'source_item_code'
          AND v.status='published' AND (t.owner_id IS NULL OR t.owner_id=actor) FOR SHARE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      SELECT count(*) INTO duplicate_count FROM private_isg.checklist_template_items i
        WHERE i.template_code=p_payload->>'template_code' AND i.version=target_version
          AND i.atomic_item_code IS NOT DISTINCT FROM picked_row.atomic_item_code
          AND coalesce(i.scope_key,'')=coalesce(nullif(btrim(picked->>'scope_key'),''),'');
      IF duplicate_count>0 AND NOT coalesce((picked->>'allow_duplicate')::boolean,false) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUPLICATE_CHECKLIST_ITEM'; END IF;
      next_position:=next_position+1;
      generated_code:=left('i'||md5(picked_row.atomic_item_code||':'||coalesce(picked->>'scope_key','')||':'||next_position::text),40);
      INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,
        allows_not_applicable,position,atomic_item_code,verification_method,help_text,tags,risk_topic,
        source_ids,na_reason_required,evidence_recommended,photo_required,catalog_item_code,section_title,scope_key)
      VALUES(p_payload->>'template_code',target_version,generated_code,picked_row.prompt,
        picked_row.allows_not_applicable,next_position,picked_row.atomic_item_code,picked_row.verification_method,
        picked_row.help_text,picked_row.tags,picked_row.risk_topic,picked_row.source_ids,
        picked_row.na_reason_required,picked_row.evidence_recommended,picked_row.photo_required,
        picked_row.catalog_item_code,nullif(btrim(picked->>'section_title'),''),nullif(btrim(picked->>'scope_key'),''));
    END LOOP;
    answer:=jsonb_build_object('schema_version',3,'template_code',p_payload->>'template_code',
      'version',target_version,'items_added',jsonb_array_length(p_payload->'items'));
  ELSIF p_action='reorder_items' THEN
    IF p_payload->>'template_code' IS NULL OR p_payload->>'version' IS NULL OR
       jsonb_typeof(p_payload->'item_codes')<>'array' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    target_version:=(p_payload->>'version')::integer;
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,true);
    PERFORM 1 FROM private_isg.checklist_template_versions WHERE template_code=p_payload->>'template_code'
      AND version=target_version AND status='draft' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_PUBLISHED'; END IF;
    SELECT count(*) INTO ordered_count FROM private_isg.checklist_template_items
      WHERE template_code=p_payload->>'template_code' AND version=target_version;
    IF ordered_count<>jsonb_array_length(p_payload->'item_codes') OR
       ordered_count<>(SELECT count(DISTINCT value) FROM jsonb_array_elements_text(p_payload->'item_codes')) OR
       EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_payload->'item_codes') x(value)
         WHERE NOT EXISTS(SELECT 1 FROM private_isg.checklist_template_items i
           WHERE i.template_code=p_payload->>'template_code' AND i.version=target_version AND i.item_code=x.value)) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    UPDATE private_isg.checklist_template_items i SET position=o.position
      FROM (SELECT value,row_number() OVER()::integer AS position
        FROM jsonb_array_elements_text(p_payload->'item_codes')) o
      WHERE i.template_code=p_payload->>'template_code' AND i.version=target_version AND i.item_code=o.value;
    answer:=jsonb_build_object('schema_version',3,'template_code',p_payload->>'template_code',
      'version',target_version,'items_reordered',ordered_count);
  ELSIF p_action='assign_template' THEN
    IF p_payload->>'template_code' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,false);
    SELECT version INTO source_version FROM private_isg.checklist_template_versions
      WHERE template_code=p_payload->>'template_code' AND status='published' FOR SHARE;
    IF source_version IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF p_payload->>'workplace_id' IS NOT NULL THEN
      PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
        AND id=(p_payload->>'workplace_id')::uuid
        AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    END IF;
    SELECT user_id INTO company_owner FROM public.companies WHERE id=p_company FOR SHARE;
    INSERT INTO private_isg.checklist_template_assignments(company_id,owner_id,workspace_id,workplace_id,
      template_code,template_version,assigned_by,assigned_at)
    VALUES(p_company,company_owner,private_isg.expert_workspace(),(p_payload->>'workplace_id')::uuid,
      p_payload->>'template_code',source_version,actor,stamp)
    ON CONFLICT(company_id,workplace_key,template_code,template_version) WHERE is_active
    DO UPDATE SET assigned_by=excluded.assigned_by,assigned_at=excluded.assigned_at
    RETURNING assignment_id INTO assignment;
    answer:=jsonb_build_object('schema_version',3,'assignment_id',assignment,
      'template_code',p_payload->>'template_code','template_version',source_version);
  ELSIF p_action='deactivate_assignment' THEN
    UPDATE private_isg.checklist_template_assignments SET is_active=false
      WHERE assignment_id=(p_payload->>'assignment_id')::uuid AND company_id=p_company AND is_active
      RETURNING assignment_id INTO assignment;
    IF assignment IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    answer:=jsonb_build_object('schema_version',3,'assignment_id',assignment,'is_active',false);
  ELSIF p_action IN ('set_item','remove_item','publish_template') THEN
    IF p_payload->>'template_code' IS NULL OR p_payload->>'version' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,true);
    IF p_action='set_item' THEN
      IF p_payload->>'item_code' IS NULL OR p_payload->>'prompt' IS NULL OR p_payload->>'position' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.set_checklist_item(p_payload->>'template_code',(p_payload->>'version')::integer,
        p_payload->>'item_code',p_payload->>'prompt',coalesce((p_payload->>'allows_not_applicable')::boolean,true),
        (p_payload->>'position')::integer,stamp);
      UPDATE private_isg.checklist_template_items SET
        section_title=nullif(btrim(p_payload->>'section_title'),''),scope_key=nullif(btrim(p_payload->>'scope_key'),'')
        WHERE template_code=p_payload->>'template_code' AND version=(p_payload->>'version')::integer
          AND item_code=p_payload->>'item_code';
    ELSIF p_action='remove_item' THEN
      answer:=private_isg.remove_checklist_item(p_payload->>'template_code',
        (p_payload->>'version')::integer,p_payload->>'item_code');
    ELSE
      IF btrim(coalesce(p_payload->>'approval_note',''))='' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.publish_checklist_version(p_payload->>'template_code',
        (p_payload->>'version')::integer,actor,p_payload->>'approval_note',stamp);
    END IF;
  ELSIF p_action='start_run' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'template_code' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid
      AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,false);
    answer:=private_isg.start_checklist_run(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'template_code',coalesce((p_payload->>'started_on')::date,today),stamp);
    run:=(answer->>'run_id')::uuid;
    UPDATE private_isg.checklist_runs SET area_label=nullif(btrim(p_payload->>'area_label'),''),
      equipment_label=nullif(btrim(p_payload->>'equipment_label'),''),
      document_number=nullif(btrim(p_payload->>'document_number'),'') WHERE run_id=run;
  ELSIF p_action='revise_run' THEN
    run:=(p_payload->>'run_id')::uuid;
    SELECT * INTO entry FROM private_isg.checklist_runs WHERE run_id=run AND company_id=p_company
      AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF entry.state<>'submitted' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    INSERT INTO private_isg.checklist_runs(company_id,owner_id,workplace_id,template_code,template_version,
      started_on,created_at,revises_run_id,area_label,equipment_label,document_number)
    VALUES(entry.company_id,entry.owner_id,entry.workplace_id,entry.template_code,entry.template_version,
      coalesce((p_payload->>'started_on')::date,today),stamp,entry.run_id,entry.area_label,
      entry.equipment_label,entry.document_number) RETURNING run_id INTO revised;
    INSERT INTO private_isg.checklist_run_items(run_id,item_code,result,note,evidence_asset_id,recorded_at)
      SELECT revised,item_code,result,note,evidence_asset_id,stamp FROM private_isg.checklist_run_items
      WHERE run_id=entry.run_id;
    run:=revised;
    answer:=jsonb_build_object('schema_version',3,'run_id',run,'revises_run_id',entry.run_id,'state','open');
  ELSE
    run:=(p_payload->>'run_id')::uuid;
    SELECT * INTO entry FROM private_isg.checklist_runs WHERE run_id=run AND company_id=p_company
      AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_payload->>'expected_revision' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    expected_revision:=(p_payload->>'expected_revision')::bigint;
    IF entry.edit_revision<>expected_revision THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHECKLIST_CONFLICT'; END IF;
    IF p_action='record_item' THEN
      IF p_payload->>'item_code' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.record_run_item(run,p_payload->>'item_code',p_payload->>'result',
        nullif(btrim(coalesce(p_payload->>'note','')),''),(p_payload->>'evidence_asset_id')::uuid,
        coalesce((p_payload->>'open_nonconformity')::boolean,false),
        nullif(btrim(coalesce(p_payload->>'severity','')),''),(p_payload->>'due_on')::date,stamp);
    ELSIF p_action='submit_run' THEN answer:=private_isg.submit_checklist_run(run,stamp);
    ELSE answer:=private_isg.cancel_checklist_run(run,stamp); END IF;
    UPDATE private_isg.checklist_runs SET edit_revision=edit_revision+1 WHERE run_id=run;
  END IF;

  result:=jsonb_build_object('schema_version',3,'action',p_action,'answer',answer,'run_id',run,
    'row',CASE WHEN run IS NOT NULL THEN private_isg.checklist_run_row(run,true) END,
    'auto_nonconformity',false);
  INSERT INTO private_isg.checklist_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

REVOKE ALL ON FUNCTION private_isg.checklist_run_row(uuid,boolean),
  private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
