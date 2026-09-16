SET LOCAL lock_timeout='1s';
-- Only new pilot APIs accept a NULL company. Ordinary v1 write still requires one.
ALTER TABLE private_isg.file_library_entries ALTER COLUMN company_id DROP NOT NULL;
ALTER TABLE private_isg.file_library_receipts ALTER COLUMN company_id DROP NOT NULL;
CREATE FUNCTION private_isg.pilot_file_owner(p_company uuid,p_write bool) RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 PERFORM private_isg.file_library_gate(p_write);
 IF p_company IS NOT NULL THEN
  IF NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  RETURN private_isg.require_file_library_company(p_company,p_write);
 END IF;
 IF p_write AND (private.user_plan_tier(actor) NOT IN ('plus','pro') OR NOT EXISTS(SELECT 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND status IN ('active','trialing','grace_period') AND (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()))) THEN RAISE EXCEPTION 'PAID_PLAN_REQUIRED'; END IF;
 RETURN actor;
END $$;
REVOKE ALL ON FUNCTION private_isg.pilot_file_owner(uuid,bool) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private_isg.pilot_mutate_file_library(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.file_library_receipts;
  result jsonb; target uuid; expected bigint; entry private_isg.file_library_entries;
  purpose text; extension text; intent jsonb; stamp timestamptz:=clock_timestamp();
BEGIN
  actor:=private_isg.pilot_file_owner(p_company,true);
  IF NOT private_isg.p05_pilot_account_enabled(actor,true) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  IF p_payload ? 'tags' AND (jsonb_typeof(p_payload->'tags') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'tags')>12) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF p_payload ? 'tags' AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'tags') x WHERE jsonb_typeof(x)<>'string' OR length(btrim(x#>>'{}')) NOT BETWEEN 1 AND 40) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  allowed:=CASE p_action
    WHEN 'open_upload' THEN ARRAY['title','category','file_name','note','tags','extension','bytes','sha256']
    WHEN 'rename_entry' THEN ARRAY['entry_id','expected_version','title','category','note','tags']
    WHEN 'archive_entry' THEN ARRAY['entry_id','expected_version']
    WHEN 'cancel_upload' THEN ARRAY['entry_id','expected_version']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-file-library:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.file_library_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='open_upload' THEN
    IF p_payload->>'title' IS NULL OR p_payload->>'category' IS NULL OR p_payload->>'file_name' IS NULL OR
       p_payload->>'extension' IS NULL OR p_payload->>'bytes' IS NULL OR p_payload->>'sha256' IS NULL OR
       (p_payload->>'sha256') !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF NOT EXISTS(SELECT 1 FROM private_isg.file_library_categories
        WHERE category=p_payload->>'category') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    extension:=lower(btrim(p_payload->>'extension'));
    purpose:=private_isg.file_library_purpose(extension);
    IF purpose IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UNSUPPORTED_FORMAT'; END IF;
    intent:=private_isg.open_upload_intent(actor,p_company,purpose,extension,
      (p_payload->>'bytes')::bigint,decode(p_payload->>'sha256','hex'),p_operation,p_mutation,
      NULL,true,3600,stamp);
    INSERT INTO private_isg.file_library_entries(company_id,owner_id,intent_id,category,title,file_name,note,tags)
      VALUES(p_company,actor,(intent->>'intent_id')::uuid,p_payload->>'category',
        btrim(p_payload->>'title'),btrim(p_payload->>'file_name'),
        nullif(btrim(coalesce(p_payload->>'note','')),''),ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(coalesce(p_payload->'tags','[]')) x ORDER BY btrim(x)))
      RETURNING entry_id INTO target;
  ELSE
    target:=(p_payload->>'entry_id')::uuid;
    expected:=(p_payload->>'expected_version')::bigint;
    SELECT * INTO entry FROM private_isg.file_library_entries
      WHERE entry_id=target AND company_id IS NOT DISTINCT FROM p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF expected IS NULL OR entry.version<>expected THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF p_action='rename_entry' THEN
      IF p_payload->>'title' IS NOT NULL AND btrim(p_payload->>'title')='' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF p_payload->>'category' IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM private_isg.file_library_categories WHERE category=p_payload->>'category') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      UPDATE private_isg.file_library_entries SET
        title=coalesce(nullif(btrim(coalesce(p_payload->>'title','')),''),title),
        category=coalesce(p_payload->>'category',category),
        note=CASE WHEN p_payload ? 'note' THEN nullif(btrim(coalesce(p_payload->>'note','')),'') ELSE note END,
        tags=CASE WHEN p_payload ? 'tags' THEN ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(p_payload->'tags') x ORDER BY btrim(x)) ELSE tags END,
        version=version+1,updated_at=stamp WHERE entry_id=target;
    ELSIF p_action='archive_entry' THEN
      UPDATE private_isg.file_library_entries SET is_archived=true,version=version+1,updated_at=stamp
        WHERE entry_id=target;
    ELSE
      PERFORM 1 FROM private_isg.upload_intents
        WHERE intent_id=entry.intent_id AND state IN ('pending','uploaded','scanning','clean');
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_NOT_CANCELLABLE'; END IF;
      PERFORM private_isg.reject_upload_intent(entry.intent_id,'EXPIRED',stamp);
      UPDATE private_isg.file_library_entries SET is_archived=true,version=version+1,updated_at=stamp
        WHERE entry_id=target;
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'entry_id',target,
    'row',private_isg.file_library_entry_row(target));
  INSERT INTO private_isg.file_library_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.pilot_read_file_library(p_company uuid, p_kind text, p_query text, p_category text, p_state text, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_categories jsonb; tally_rows jsonb; matching_rows integer;
  catalog_rows jsonb; accept_rows jsonb;
BEGIN
  actor:=private_isg.pilot_file_owner(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;

  IF p_kind='catalog' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('code',c.category,'ordinal',c.ordinal,'section',c.section)
      ORDER BY c.ordinal),'[]'::jsonb) INTO catalog_rows FROM private_isg.file_library_categories c;
    SELECT coalesce(jsonb_agg(jsonb_build_object('purpose',p.purpose,'extensions',to_jsonb(p.extensions),
      'max_bytes',p.max_bytes,'limit_approved',p.limit_approved) ORDER BY p.purpose),'[]'::jsonb)
      INTO accept_rows FROM private_isg.file_purposes p WHERE p.purpose IN ('company_document','evidence_photo');
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','categories',catalog_rows,
      'accepts',accept_rows,
      'scanners',(SELECT coalesce(jsonb_agg(jsonb_build_object('scanner',s.scanner,'assurance',s.assurance,
        'detects_malware',s.detects_malware) ORDER BY s.scanner),'[]'::jsonb) FROM private_isg.file_scanners s),
      'malware_scanning_available',
        (SELECT coalesce(bool_or(s.detects_malware),false) FROM private_isg.file_scanners s));
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.file_library_entries
      WHERE entry_id=p_id AND owner_id=actor AND (p_company IS NULL OR company_id=p_company)
        AND (company_id IS NULL OR private_isg.p05_pilot_can_read(actor,company_id));
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail',
      'row',private_isg.file_library_entry_row(p_id));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('pending','uploaded','scanning','clean','rejected',
    'scan_failed','promoted','expired','filed','working','unchecked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_category IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM private_isg.file_library_categories WHERE category=p_category) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), page AS (
    SELECT e.entry_id,e.company_id,coalesce(s.name,'Kişisel Dosyalar') AS company_name,e.category,e.title,e.note,e.tags,
      CASE WHEN e.asset_id IS NOT NULL THEN 'promoted' ELSE i.state END AS entry_state,
      row_number() OVER (ORDER BY
        CASE WHEN e.asset_id IS NOT NULL THEN 4
          WHEN i.state='rejected' THEN 0 WHEN i.state='scan_failed' THEN 1
          WHEN i.state='expired' THEN 2 ELSE 3 END,
        e.created_at DESC,e.entry_id) AS ordinal
    FROM private_isg.file_library_entries e
    LEFT JOIN scope s ON s.id=e.company_id
    JOIN private_isg.upload_intents i ON i.intent_id=e.intent_id
    WHERE e.owner_id=actor AND NOT e.is_archived AND (e.company_id IS NULL OR (s.id IS NOT NULL AND private_isg.p05_pilot_can_read(actor,e.company_id)))
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_category IS NULL OR category=p_category)
      AND (p_state IS NULL OR entry_state=p_state
        OR (p_state='filed' AND entry_state='promoted')
        OR (p_state='working' AND entry_state IN ('pending','uploaded','scanning','clean'))
        OR (p_state='unchecked' AND entry_state IN ('scan_failed','expired')))
      AND (needle IS NULL OR title ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%' OR note ILIKE '%'||needle||'%' OR array_to_string(tags,' ') ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,sum(state_total) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page WHERE company_id IS NOT NULL
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT coalesce(jsonb_object_agg(category,states),'{}'::jsonb) FROM
      (SELECT category,jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT category,entry_state,count(*) AS state_total FROM scoped
          GROUP BY category,entry_state) d GROUP BY category) e),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.file_library_entry_row(picked.entry_id)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,tally_categories,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,
    'counts',tally_all,'companies',tally_companies,'category_counts',tally_categories,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    'compliance_verdict',NULL,
    'malware_scanning_available',
      (SELECT coalesce(bool_or(s.detects_malware),false) FROM private_isg.file_scanners s));
END $function$
;
CREATE FUNCTION public.isg_pilot_file_library_read_v2(p_company uuid,p_kind text,p_query text,p_category text,p_state text,p_id uuid,p_limit int,p_offset int) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.pilot_read_file_library(p_company,p_kind,p_query,p_category,p_state,p_id,p_limit,p_offset) $$;
REVOKE ALL ON FUNCTION private_isg.pilot_read_file_library(uuid,text,text,text,text,uuid,int,int),public.isg_pilot_file_library_read_v2(uuid,text,text,text,text,uuid,int,int) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.pilot_read_file_library(uuid,text,text,text,text,uuid,int,int),public.isg_pilot_file_library_read_v2(uuid,text,text,text,text,uuid,int,int) TO authenticated;
DO $$ DECLARE d text; old_clause text; BEGIN
 d:=pg_get_functiondef('public.isg_pilot_file_sources_v1(uuid)'::regprocedure);
 old_clause:='IF NOT FOUND OR NOT private_isg.p05_pilot_can_read(actor,f.company_id) THEN RAISE EXCEPTION ''ACCESS_DENIED''; END IF;';
 IF strpos(d,old_clause)=0 THEN RAISE EXCEPTION 'SOURCE_BASELINE_CHANGED'; END IF;
 EXECUTE replace(d,old_clause,'IF NOT FOUND THEN RAISE EXCEPTION ''ACCESS_DENIED''; END IF; IF f.company_id IS NULL THEN RETURN ''[]''::jsonb; END IF; IF NOT private_isg.p05_pilot_can_read(actor,f.company_id) THEN RAISE EXCEPTION ''ACCESS_DENIED''; END IF;');
END $$;
NOTIFY pgrst,'reload schema';
