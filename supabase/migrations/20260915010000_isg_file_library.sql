-- P04 second slice / P11 third: the client surface behind "Diğer Dosyalar".
-- Additive. The rollout row is NOT opened here: switching a feature on stays a
-- separate, human decision, exactly as it is for every slice before this one.
--
-- The first slice (20260913130000_isg_file_core.sql) built the quarantine state
-- machine and said in its own header that it creates "no bucket, storage
-- policy, scanner or client surface". This migration adds exactly those four
-- and nothing else: the library is a naming and filing layer over assets that
-- the state machine already refuses to produce without a verdict.
--
-- Four things are made structurally impossible rather than merely discouraged:
--   1. A file the expert can open is always a promoted asset. The download path
--      comes from the asset row, which the state machine refuses to create
--      without a verdict over the very bytes being promoted; there is no column
--      that could carry a path for a file still sitting in quarantine.
--   2. The client cannot read, replace or delete anything in quarantine. The
--      only policy on that bucket is INSERT under the caller's own prefix, so a
--      scanned object can not be swapped for another one afterwards.
--   3. A verdict cannot be asserted by the account that uploaded the file. The
--      inspection entry is granted to service_role alone and takes no actor
--      argument: it reads the owner from the intent row it was handed.
--   4. The product never claims a file was scanned for malware. What cleared a
--      file is looked up in a scanner registry, and a scanner nobody registered
--      counts as not detecting malware. Unknown is not yes.
--
-- The format inspector shipped with this slice checks real type, size, hash and
-- active content. That is a genuine layer and it is not antivirus, so the read
-- says so on every row and the general wide-format release gate in the plan
-- (§31.6) is not satisfied by this migration.
BEGIN;
SET LOCAL lock_timeout='5s';

ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports','notifications','personal_notes','billing_lifecycle',
    'campaigns','observability','score','document_tracking','file_library'));
INSERT INTO private_isg.rollout(feature) VALUES('file_library');

-- ---------------------------------------------------------------------------
-- Buckets. Both private. The quarantine bucket is write-only for the client and
-- the final bucket is read-only for the client: promotion is the server's job.
-- The legacy photos/reports/logos buckets and their policies are untouched.
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets(id,name,public,file_size_limit)
VALUES('isg-quarantine','isg-quarantine',false,52428800),
      ('isg-documents','isg-documents',false,52428800)
ON CONFLICT(id) DO NOTHING;
-- allowed_mime_types is deliberately left NULL: the declared type of an upload
-- is not evidence. private_isg.file_acceptance and the inspector decide.

-- quarantine/{owner}/{intent} -> foldername() = {quarantine, owner}
CREATE POLICY isg_quarantine_insert_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK(bucket_id='isg-quarantine' AND (storage.foldername(name))[1]='quarantine'
    AND (storage.foldername(name))[2]=auth.uid()::text);
-- assets/{owner}/{sha256} and derivatives/{owner}/{kind}/{sha256}
CREATE POLICY isg_documents_select_own ON storage.objects
  FOR SELECT TO authenticated
  USING(bucket_id='isg-documents'
    AND (storage.foldername(name))[1] IN ('assets','derivatives')
    AND (storage.foldername(name))[2]=auth.uid()::text);

-- ---------------------------------------------------------------------------
-- What cleared a file. A scanner that nobody registered detects no malware, so
-- an unrecognised name can never be reported as a malware scan.
-- ---------------------------------------------------------------------------
CREATE TABLE private_isg.file_scanners (
  scanner text PRIMARY KEY CHECK(btrim(scanner)<>'' AND length(scanner)<=60),
  assurance text NOT NULL CHECK(assurance IN ('format_inspection','malware_scan')),
  detects_malware boolean NOT NULL,
  note text NOT NULL CHECK(btrim(note)<>''),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(detects_malware=(assurance='malware_scan'))
);
INSERT INTO private_isg.file_scanners(scanner,assurance,detects_malware,note) VALUES
  ('isg_format_inspector','format_inspection',false,
   'Real type, size, hash and active-content inspection. Not an antivirus.');

-- ---------------------------------------------------------------------------
-- The filing categories, and the company heading each one belongs under, so the
-- company page and the library can never disagree about where a file lives.
-- The section names are the client's NovaCompanySection cases.
-- ---------------------------------------------------------------------------
CREATE TABLE private_isg.file_library_categories (
  category text PRIMARY KEY CHECK(category IN ('risk_assessment','emergency_plan','training_material',
    'inspection_report','measurement_report','accident_record','board_document','handover_form',
    'personnel_document','contract','permit_form','contractor_document','other')),
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 999),
  section text NOT NULL CHECK(section IN ('logo','personnel','representative','support','risk','emergency',
    'inspections','accidents','board','training','files','handover')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(ordinal)
);
INSERT INTO private_isg.file_library_categories(category,ordinal,section) VALUES
  ('risk_assessment',1,'risk'),('emergency_plan',2,'emergency'),('training_material',3,'training'),
  ('inspection_report',4,'inspections'),('measurement_report',5,'inspections'),
  ('accident_record',6,'accidents'),('board_document',7,'board'),('handover_form',8,'handover'),
  ('personnel_document',9,'personnel'),('contract',10,'files'),('permit_form',11,'files'),
  ('contractor_document',12,'files'),('other',13,'files');

-- ---------------------------------------------------------------------------
-- One filed document. The entry is created together with its upload intent, so
-- a row exists from the moment the expert picks a file and always shows what
-- really happened to it. No state is stored here: the intent owns that, and the
-- read reports it. asset_id stays NULL until a clean upload is promoted.
-- ---------------------------------------------------------------------------
CREATE TABLE private_isg.file_library_entries (
  entry_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL,
  intent_id uuid NOT NULL UNIQUE REFERENCES private_isg.upload_intents(intent_id) ON DELETE CASCADE,
  -- Deliberately not unique: promotion is content addressed, so the same
  -- document filed under two headings is two entries over one object.
  asset_id uuid REFERENCES private_isg.file_assets(asset_id) ON DELETE RESTRICT,
  category text NOT NULL REFERENCES private_isg.file_library_categories(category),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=160),
  -- The name the file had on the expert's device. Kept for recognition only; it
  -- never decides the real type and never becomes a storage path.
  file_name text NOT NULL CHECK(btrim(file_name)<>'' AND length(file_name)<=200),
  note text CHECK(note IS NULL OR length(note)<=500),
  is_archived boolean NOT NULL DEFAULT false,
  version bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX file_library_entry_company_idx ON private_isg.file_library_entries(company_id,owner_id);
CREATE INDEX file_library_entry_category_idx ON private_isg.file_library_entries(category);
CREATE INDEX file_library_entry_intent_idx ON private_isg.file_library_entries(intent_id);
CREATE INDEX file_library_entry_asset_idx ON private_isg.file_library_entries(asset_id);
-- Promotion is content addressed, so the same bytes always reach the same path.
-- This index is what lets a second filing of the same document find the asset
-- that is already there instead of colliding with it.
CREATE INDEX file_asset_owner_digest_idx ON private_isg.file_assets(owner_id,sha256);

CREATE TABLE private_isg.file_library_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX file_library_receipt_company_idx ON private_isg.file_library_receipts(company_id,actor_id);

ALTER TABLE private_isg.file_scanners ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.file_library_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.file_library_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.file_library_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- The switch on its own, in the same shape as every other slice's gate.
CREATE FUNCTION private_isg.file_library_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='file_library' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;

-- A NULL company is the whole account, and only for reads: every write names
-- the company it writes into.
CREATE FUNCTION private_isg.require_file_library_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.file_library_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $$;

-- The purpose is decided from the extension by the server, never sent by the
-- client: a caller cannot file a spreadsheet under the photo limits.
CREATE FUNCTION private_isg.file_library_purpose(p_extension text) RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT p.purpose FROM private_isg.file_purposes p
  WHERE p.purpose IN ('company_document','evidence_photo')
    AND lower(btrim(p_extension))=ANY(p.extensions)
  ORDER BY p.purpose LIMIT 1
$$;

-- One entry with the state its upload really reached. Nothing here is stored as
-- a status: it is read from the intent every time.
CREATE FUNCTION private_isg.file_library_entry_row(p_entry uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.file_library_entries; intent private_isg.upload_intents;
  asset private_isg.file_assets; scan private_isg.file_scan_results; registry private_isg.file_scanners;
  shown_state text;
BEGIN
  SELECT * INTO entry FROM private_isg.file_library_entries WHERE entry_id=p_entry;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO intent FROM private_isg.upload_intents WHERE intent_id=entry.intent_id;
  IF entry.asset_id IS NOT NULL THEN
    SELECT * INTO asset FROM private_isg.file_assets WHERE asset_id=entry.asset_id; END IF;
  SELECT * INTO scan FROM private_isg.file_scan_results WHERE intent_id=entry.intent_id;
  IF scan.scanner IS NOT NULL THEN
    SELECT * INTO registry FROM private_isg.file_scanners WHERE scanner=scan.scanner; END IF;
  -- The asset row is the proof that cleared bytes reached the final bucket. The
  -- intent's own state is bookkeeping, and it stays behind when a second filing
  -- of the same document links to the asset that was already promoted.
  shown_state:=CASE WHEN entry.asset_id IS NOT NULL THEN 'promoted' ELSE intent.state END;
  RETURN jsonb_build_object(
    'id',entry.entry_id,'company_id',entry.company_id,'category',entry.category,
    'section',(SELECT c.section FROM private_isg.file_library_categories c WHERE c.category=entry.category),
    'title',entry.title,'file_name',entry.file_name,'note',entry.note,
    'is_archived',entry.is_archived,'version',entry.version,
    'created_at',entry.created_at,'updated_at',entry.updated_at,
    'state',shown_state,'state_authority','computed_at_read',
    'intent_id',entry.intent_id,'intent_state',intent.state,
    'rejection_code',intent.rejection_code,
    'extension',intent.declared_extension,'purpose',intent.purpose,
    'declared_bytes',intent.declared_bytes,'received_bytes',intent.received_bytes,
    'detected_type',coalesce(asset.detected_type,intent.detected_type),
    'expires_at',intent.expires_at,
    -- Write-only for the client; it is here so the app knows where to PUT.
    'upload_bucket',CASE WHEN intent.state='pending' THEN 'isg-quarantine' END,
    'upload_path',CASE WHEN intent.state='pending' THEN intent.quarantine_path END,
    -- A path is emitted only when an asset exists, which the state machine
    -- refuses to create without a verdict over the very bytes being promoted.
    'download_bucket',asset.bucket,'download_path',asset.immutable_path,
    'scanner',scan.scanner,'scan_finding',scan.finding_code,
    'assurance',registry.assurance,
    -- An unregistered scanner is not evidence of a malware scan.
    'malware_scanned',coalesce(registry.detects_malware,false),
    'preview_status',coalesce(asset.preview_status,'none'));
END $$;

-- ---------------------------------------------------------------------------
-- Read. One aggregate answers the page, the tally, the per-company summary and
-- the per-category tally, so a count can never disagree with the list it counts.
-- ---------------------------------------------------------------------------
CREATE FUNCTION private_isg.read_file_library(p_company uuid,p_kind text,p_query text,p_category text,
  p_state text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; page_limit integer; page_offset integer;
  -- Prefixed so a local can never collide with an aggregate alias below.
  tally_all jsonb; tally_companies jsonb; tally_categories jsonb; tally_rows jsonb; matching_rows integer;
  catalog_rows jsonb; accept_rows jsonb;
BEGIN
  actor:=private_isg.require_file_library_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;

  IF p_kind='catalog' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('code',c.category,'ordinal',c.ordinal,'section',c.section)
      ORDER BY c.ordinal),'[]'::jsonb) INTO catalog_rows FROM private_isg.file_library_categories c;
    -- What the server will accept at all, declared at runtime: an OS picker
    -- offering a type is a convenience, this is the authority.
    SELECT coalesce(jsonb_agg(jsonb_build_object('purpose',p.purpose,'extensions',to_jsonb(p.extensions),
      'max_bytes',p.max_bytes,'limit_approved',p.limit_approved) ORDER BY p.purpose),'[]'::jsonb)
      INTO accept_rows FROM private_isg.file_purposes p WHERE p.purpose IN ('company_document','evidence_photo');
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','categories',catalog_rows,
      'accepts',accept_rows,
      'scanners',(SELECT coalesce(jsonb_agg(jsonb_build_object('scanner',s.scanner,'assurance',s.assurance,
        'detects_malware',s.detects_malware) ORDER BY s.scanner),'[]'::jsonb) FROM private_isg.file_scanners s),
      -- The plan's wide-format release gate needs a malware scanner. None is
      -- registered, so the module says so rather than implying one ran.
      'malware_scanning_available',
        (SELECT coalesce(bool_or(s.detects_malware),false) FROM private_isg.file_scanners s));
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.file_library_entries
      WHERE entry_id=p_id AND owner_id=actor AND (p_company IS NULL OR company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail',
      'row',private_isg.file_library_entry_row(p_id));
  END IF;

  -- Either one exact state, or one of the four groups the page counts under,
  -- so tapping a counter filters exactly the rows that counter counted.
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
    SELECT e.entry_id,e.company_id,s.name AS company_name,e.category,e.title,
      CASE WHEN e.asset_id IS NOT NULL THEN 'promoted' ELSE i.state END AS entry_state,
      row_number() OVER (ORDER BY
        -- What needs the expert's attention first: a refusal, then an upload
        -- that never finished, then the archive itself, newest first.
        CASE WHEN e.asset_id IS NOT NULL THEN 4
          WHEN i.state='rejected' THEN 0 WHEN i.state='scan_failed' THEN 1
          WHEN i.state='expired' THEN 2 ELSE 3 END,
        e.created_at DESC,e.entry_id) AS ordinal
    FROM private_isg.file_library_entries e
    JOIN scope s ON s.id=e.company_id
    JOIN private_isg.upload_intents i ON i.intent_id=e.intent_id
    WHERE e.owner_id=actor AND NOT e.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_category IS NULL OR category=p_category)
      AND (p_state IS NULL OR entry_state=p_state
        OR (p_state='filed' AND entry_state='promoted')
        OR (p_state='working' AND entry_state IN ('pending','uploaded','scanning','clean'))
        OR (p_state='unchecked' AND entry_state IN ('scan_failed','expired')))
      AND (needle IS NULL OR title ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
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
    -- A tally of filed documents. Never a statement that a company is compliant.
    'compliance_verdict',NULL,
    'malware_scanning_available',
      (SELECT coalesce(bool_or(s.detects_malware),false) FROM private_isg.file_scanners s));
END $$;

-- ---------------------------------------------------------------------------
-- Write. The expert opens an upload, names it and files it. Nothing here can
-- move an upload forward through the quarantine machine: that belongs to the
-- inspector below.
-- ---------------------------------------------------------------------------
CREATE FUNCTION private_isg.mutate_file_library(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.file_library_receipts;
  result jsonb; target uuid; expected bigint; entry private_isg.file_library_entries;
  purpose text; extension text; intent jsonb; stamp timestamptz:=clock_timestamp();
BEGIN
  actor:=private_isg.require_file_library_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  allowed:=CASE p_action
    WHEN 'open_upload' THEN ARRAY['title','category','file_name','note','extension','bytes','sha256']
    WHEN 'rename_entry' THEN ARRAY['entry_id','expected_version','title','category','note']
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
    -- An extension no purpose accepts is refused here, before an intent exists.
    IF purpose IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UNSUPPORTED_FORMAT'; END IF;
    intent:=private_isg.open_upload_intent(actor,p_company,purpose,extension,
      (p_payload->>'bytes')::bigint,decode(p_payload->>'sha256','hex'),p_operation,p_mutation,
      NULL,true,3600,stamp);
    INSERT INTO private_isg.file_library_entries(company_id,owner_id,intent_id,category,title,file_name,note)
      VALUES(p_company,actor,(intent->>'intent_id')::uuid,p_payload->>'category',
        btrim(p_payload->>'title'),btrim(p_payload->>'file_name'),
        nullif(btrim(coalesce(p_payload->>'note','')),''))
      RETURNING entry_id INTO target;
  ELSE
    target:=(p_payload->>'entry_id')::uuid;
    expected:=(p_payload->>'expected_version')::bigint;
    SELECT * INTO entry FROM private_isg.file_library_entries
      WHERE entry_id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;
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
        version=version+1,updated_at=stamp WHERE entry_id=target;
    ELSIF p_action='archive_entry' THEN
      UPDATE private_isg.file_library_entries SET is_archived=true,version=version+1,updated_at=stamp
        WHERE entry_id=target;
    ELSE
      -- Cancelling only abandons an upload that never became a file. A promoted
      -- asset is not deleted by a cancel; archiving is the way to put it away.
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
END $$;

-- ---------------------------------------------------------------------------
-- The inspector's only entry. Granted to service_role alone, because a verdict
-- must not be assertable by the account that uploaded the file. It takes no
-- actor argument: the owner is read from the intent row, so holding this grant
-- confers no ability to act as a user.
-- ---------------------------------------------------------------------------
CREATE FUNCTION private_isg.inspect_file_upload(p_intent uuid,p_stage text,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE intent private_isg.upload_intents; answer jsonb; stamp timestamptz:=clock_timestamp();
  registered boolean; existing uuid;
BEGIN
  PERFORM private_isg.file_library_gate(true);
  IF p_intent IS NULL OR p_stage IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR
     octet_length(p_payload::text)>4096 OR
     p_stage NOT IN ('claim','received','scanned','promoted') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent FROM private_isg.upload_intents WHERE intent_id=p_intent;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Only an upload this module opened is inspected here.
  PERFORM 1 FROM private_isg.file_library_entries WHERE intent_id=p_intent;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

  IF p_stage='claim' THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state',intent.state,
      'owner_id',intent.owner_id,'purpose',intent.purpose,'extension',intent.declared_extension,
      'declared_bytes',intent.declared_bytes,'declared_sha256',encode(intent.declared_sha256,'hex'),
      'quarantine_path',intent.quarantine_path,'expires_at',intent.expires_at);
  ELSIF p_stage='received' THEN
    answer:=private_isg.mark_upload_received(p_intent,(p_payload->>'bytes')::bigint,
      decode(p_payload->>'sha256','hex'),p_payload->>'detected_type',stamp);
  ELSIF p_stage='scanned' THEN
    -- A scanner the registry does not know can still record a verdict, but it
    -- will never be reported as a malware scan by the read.
    SELECT EXISTS(SELECT 1 FROM private_isg.file_scanners WHERE scanner=p_payload->>'scanner') INTO registered;
    answer:=private_isg.record_scan_result(p_intent,p_payload->>'scanner',p_payload->>'scan_version',
      p_payload->>'verdict',nullif(p_payload->>'finding_code',''),decode(p_payload->>'sha256','hex'),
      coalesce(p_payload->'evidence','{}'::jsonb)||jsonb_build_object('scanner_registered',registered),stamp);
  ELSE
    -- The final path is the owner plus the digest, so filing the same document a
    -- second time cannot create a second object. The entry is linked to the
    -- asset that is already there rather than overwriting anything.
    SELECT asset_id INTO existing FROM private_isg.file_assets
      WHERE owner_id=intent.owner_id AND sha256=decode(p_payload->>'sha256','hex');
    IF existing IS NOT NULL THEN
      UPDATE private_isg.file_library_entries SET asset_id=existing,version=version+1,updated_at=stamp
        WHERE intent_id=p_intent AND asset_id IS NULL;
      answer:=jsonb_build_object('asset_id',existing,'duplicate_of_existing_asset',true);
    ELSE
      answer:=private_isg.promote_clean_upload(p_intent,'isg-documents',
        decode(p_payload->>'sha256','hex'),(p_payload->>'bytes')::bigint,stamp);
      IF answer->>'asset_id' IS NOT NULL THEN
        UPDATE private_isg.file_library_entries SET asset_id=(answer->>'asset_id')::uuid,
          version=version+1,updated_at=stamp WHERE intent_id=p_intent AND asset_id IS NULL;
      END IF;
    END IF;
  END IF;
  RETURN answer||jsonb_build_object('schema_version',1,'intent_id',p_intent,
    'row',(SELECT private_isg.file_library_entry_row(e.entry_id)
      FROM private_isg.file_library_entries e WHERE e.intent_id=p_intent));
END $$;

CREATE FUNCTION public.isg_file_library_read_v1(p_company uuid,p_kind text,p_query text,p_category text,
  p_state text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_file_library(p_company,p_kind,p_query,p_category,p_state,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_file_library_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_file_library(p_company,p_action,p_operation,p_mutation,p_payload)
$$;
CREATE FUNCTION public.isg_file_inspection_v1(p_intent uuid,p_stage text,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.inspect_file_upload(p_intent,p_stage,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.file_library_gate(boolean),
  private_isg.require_file_library_company(uuid,boolean),
  private_isg.file_library_purpose(text),
  private_isg.file_library_entry_row(uuid),
  private_isg.read_file_library(uuid,text,text,text,text,uuid,integer,integer),
  private_isg.mutate_file_library(uuid,text,uuid,uuid,jsonb),
  private_isg.inspect_file_upload(uuid,text,jsonb),
  public.isg_file_library_read_v1(uuid,text,text,text,text,uuid,integer,integer),
  public.isg_file_library_mutate_v1(uuid,text,uuid,uuid,jsonb),
  public.isg_file_inspection_v1(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_file_library(uuid,text,text,text,text,uuid,integer,integer),
  private_isg.mutate_file_library(uuid,text,uuid,uuid,jsonb),
  public.isg_file_library_read_v1(uuid,text,text,text,text,uuid,integer,integer),
  public.isg_file_library_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
-- The inspector, and only the inspector, is reachable by the worker identity.
GRANT EXECUTE ON FUNCTION private_isg.inspect_file_upload(uuid,text,jsonb),
  public.isg_file_inspection_v1(uuid,text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
