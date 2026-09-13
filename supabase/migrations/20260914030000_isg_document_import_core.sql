-- P11 first slice: document numbering and immutable snapshots with PDF/XLSX
-- parity, plus an import pipeline with preview, commit and compensation.
-- Additive; rollout OFF; no client grant. No renderer or parser binary is
-- created here: this is the ledger and the rule surface they will obey.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports'));
INSERT INTO private_isg.rollout(feature) VALUES('documents'),('imports');

CREATE TABLE private_isg.document_templates (
  template_code text PRIMARY KEY CHECK(template_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  source_domain text NOT NULL CHECK(source_domain IN ('training','risk','nonconformity','module','personnel')),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_isg.document_template_versions (
  template_code text NOT NULL REFERENCES private_isg.document_templates(template_code) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','superseded')),
  approved_by uuid REFERENCES public.profiles(id), approval_note text, published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(template_code,version),
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))
);
CREATE UNIQUE INDEX document_template_published_idx ON private_isg.document_template_versions(template_code) WHERE status='published';
CREATE TABLE private_isg.documents (
  document_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid,
  source_domain text NOT NULL CHECK(source_domain IN ('training','risk','nonconformity','module','personnel')),
  source_ref text NOT NULL CHECK(btrim(source_ref)<>'' AND length(source_ref)<=200),
  template_code text NOT NULL REFERENCES private_isg.document_templates(template_code),
  current_version integer NOT NULL DEFAULT 0 CHECK(current_version BETWEEN 0 AND 10000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,source_domain,source_ref,template_code),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
-- Concurrency safe numbering per company, scope and year.
CREATE TABLE private_isg.document_number_sequences (
  company_id uuid NOT NULL, scope text NOT NULL CHECK(scope ~ '^[a-z][a-z0-9_]{1,19}$'),
  year integer NOT NULL CHECK(year BETWEEN 2000 AND 2100),
  next_value bigint NOT NULL DEFAULT 1 CHECK(next_value>=1),
  PRIMARY KEY(company_id,scope,year)
);
-- A finalised version is immutable: the company name, the employee's role, the
-- dates and the template version are snapshotted at that moment.
CREATE TABLE private_isg.document_versions (
  document_id uuid NOT NULL REFERENCES private_isg.documents(document_id) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 10000),
  template_version integer NOT NULL,
  document_no text NOT NULL CHECK(document_no ~ '^[A-Z0-9_]{2,20}-[0-9]{4}-[0-9]{1,9}$'),
  source_kind text NOT NULL CHECK(source_kind IN ('structured','scanned')),
  snapshot jsonb NOT NULL, snapshot_sha256 bytea NOT NULL CHECK(octet_length(snapshot_sha256)=32),
  finalized_by uuid NOT NULL REFERENCES public.profiles(id), finalized_at timestamptz NOT NULL,
  mutation_id uuid NOT NULL,
  PRIMARY KEY(document_id,version),
  UNIQUE(document_id,mutation_id)
);
CREATE UNIQUE INDEX document_no_idx ON private_isg.document_versions(document_no);
CREATE TABLE private_isg.export_jobs (
  job_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL, version integer NOT NULL,
  format text NOT NULL CHECK(format IN ('pdf','xlsx')),
  content_kind text NOT NULL CHECK(content_kind IN ('structured','metadata_index')),
  state text NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','rendering','ready','failed')),
  asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  error_code text CHECK(error_code IS NULL OR error_code ~ '^[A-Z][A-Z0-9_]{2,39}$'),
  snapshot_sha256 bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(document_id,version,format),
  CHECK((state='ready')=(asset_id IS NOT NULL)),
  CHECK((state='failed')=(error_code IS NOT NULL)),
  FOREIGN KEY(document_id,version) REFERENCES private_isg.document_versions(document_id,version) ON DELETE CASCADE
);
-- Import: idempotent per company and mutation, fingerprinted over the file hash
-- and the mapping version so the same file for a different purpose is explicit.
CREATE TABLE private_isg.import_batches (
  batch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL,
  target_kind text NOT NULL CHECK(target_kind IN ('employee','equipment')),
  asset_id uuid NOT NULL REFERENCES private_isg.file_assets(asset_id),
  file_sha256 bytea NOT NULL CHECK(octet_length(file_sha256)=32),
  mapping_version integer NOT NULL CHECK(mapping_version BETWEEN 1 AND 1000),
  mutation_id uuid NOT NULL, request_hash bytea NOT NULL,
  date_system text NOT NULL DEFAULT '1900' CHECK(date_system IN ('1900','1904')),
  decimal_separator text NOT NULL DEFAULT ',' CHECK(decimal_separator IN (',','.')),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','previewed','committed','cancelled')),
  preview_sha256 bytea, committed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,mutation_id),
  CHECK((state='committed')=(committed_at IS NOT NULL)),
  CHECK(state='draft' OR preview_sha256 IS NOT NULL),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.import_rows (
  batch_id uuid NOT NULL REFERENCES private_isg.import_batches(batch_id) ON DELETE CASCADE,
  row_no integer NOT NULL CHECK(row_no BETWEEN 1 AND 10000),
  raw jsonb NOT NULL, normalised jsonb,
  status text NOT NULL CHECK(status IN ('ok','error','duplicate','review')),
  -- Codes may carry a digit: EXCEL_1900_LEAP_BUG is one of them.
  error_code text CHECK(error_code IS NULL OR error_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  target_ref uuid, target_version bigint,
  committed boolean NOT NULL DEFAULT false,
  PRIMARY KEY(batch_id,row_no),
  CHECK((status='ok')=(error_code IS NULL)),
  CHECK(NOT committed OR target_ref IS NOT NULL)
);
CREATE TABLE private_isg.import_checkpoints (
  batch_id uuid NOT NULL REFERENCES private_isg.import_batches(batch_id) ON DELETE CASCADE,
  last_row_no integer NOT NULL CHECK(last_row_no>=0),
  committed_rows integer NOT NULL CHECK(committed_rows>=0),
  created_at timestamptz NOT NULL,
  PRIMARY KEY(batch_id,last_row_no)
);
CREATE INDEX document_scope_idx ON private_isg.documents(company_id,source_domain);
CREATE INDEX document_owner_idx ON private_isg.documents(company_id,owner_id);
CREATE INDEX document_template_idx ON private_isg.documents(template_code);
CREATE INDEX document_version_finalizer_idx ON private_isg.document_versions(finalized_by);
CREATE INDEX export_state_idx ON private_isg.export_jobs(state,created_at);
CREATE INDEX export_asset_idx ON private_isg.export_jobs(asset_id);
CREATE INDEX import_owner_idx ON private_isg.import_batches(company_id,owner_id);
CREATE INDEX import_asset_idx ON private_isg.import_batches(asset_id);
CREATE INDEX import_row_status_idx ON private_isg.import_rows(batch_id,status);
CREATE INDEX document_template_approver_idx ON private_isg.document_template_versions(approved_by);
ALTER TABLE private_isg.document_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.document_template_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.document_number_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.import_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.import_checkpoints ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.document_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='documents' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
CREATE FUNCTION private_isg.import_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='imports' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- A spreadsheet cell is data, never a formula. A leading =, +, - or @ is
-- neutralised and reported instead of being handed on as a live expression.
CREATE FUNCTION private_isg.sanitise_cell(p_value text) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE trimmed text;
BEGIN
  IF p_value IS NULL THEN RETURN jsonb_build_object('value',NULL,'sanitised',false); END IF;
  trimmed:=btrim(p_value,E' \t\r\n');
  IF trimmed ~ '^[=+@-]' THEN
    RETURN jsonb_build_object('value',right(trimmed,length(trimmed)-1),'sanitised',true,
      'reason','FORMULA_PREFIX_REMOVED','original_prefix',left(trimmed,1));
  END IF;
  RETURN jsonb_build_object('value',trimmed,'sanitised',false);
END $$;
CREATE FUNCTION private_isg.import_column_allowed(p_column text) RETURNS boolean
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  -- Health and clinical columns are out of scope and are refused at the door,
  -- not quietly stored inside a raw JSON blob.
  SELECT p_column IS NOT NULL AND lower(p_column) !~
    '(health|saglik|sağlık|medical|muayene|diagnos|teshis|teşhis|vaccin|asi|aşı|blood|kan_grubu|rapor_saglik)'
$$;
CREATE FUNCTION private_isg.import_cell_value(p_kind text,p_raw text,p_date_system text,p_decimal text) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE clean jsonb; value text; serial integer; epoch date;
BEGIN
  IF p_kind IS NULL OR p_kind NOT IN ('text','code','number','date') OR
     p_date_system IS NULL OR p_date_system NOT IN ('1900','1904') OR
     p_decimal IS NULL OR p_decimal NOT IN (',','.') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  clean:=private_isg.sanitise_cell(p_raw);
  value:=clean->>'value';
  IF value IS NULL OR value='' THEN
    RETURN jsonb_build_object('state','empty','value',NULL,'sanitised',clean->'sanitised'); END IF;
  IF p_kind='text' THEN
    RETURN jsonb_build_object('state','ok','value',value,'sanitised',clean->'sanitised'); END IF;
  IF p_kind='code' THEN
    -- A code keeps its leading zeros: it is text, never a number.
    IF value !~ '^[0-9A-Za-z._/-]{1,64}$' THEN
      RETURN jsonb_build_object('state','error','reason','CODE_FORMAT_INVALID'); END IF;
    RETURN jsonb_build_object('state','ok','value',value,'sanitised',clean->'sanitised'); END IF;
  IF p_kind='number' THEN
    IF p_decimal=',' THEN
      IF value ~ '^-?[0-9]{1,3}(\.[0-9]{3})+,[0-9]+$' OR value ~ '^-?[0-9]+,[0-9]+$' THEN
        RETURN jsonb_build_object('state','ok','value',(replace(replace(value,'.',''),',','.'))::numeric); END IF;
      IF value ~ '^-?[0-9]+$' THEN RETURN jsonb_build_object('state','ok','value',value::numeric); END IF;
      -- "1.234" is 1234 in one locale and 1.234 in another: ask, do not guess.
      IF value ~ '^-?[0-9]{1,3}(\.[0-9]{3})+$' OR value ~ '^-?[0-9]+\.[0-9]+$' THEN
        RETURN jsonb_build_object('state','review','reason','AMBIGUOUS_DECIMAL','value',NULL); END IF;
      RETURN jsonb_build_object('state','error','reason','NUMBER_FORMAT_INVALID');
    END IF;
    IF value ~ '^-?[0-9]{1,3}(,[0-9]{3})+\.[0-9]+$' OR value ~ '^-?[0-9]+\.[0-9]+$' OR value ~ '^-?[0-9]+$' THEN
      RETURN jsonb_build_object('state','ok','value',(replace(value,',',''))::numeric); END IF;
    RETURN jsonb_build_object('state','error','reason','NUMBER_FORMAT_INVALID');
  END IF;
  IF value ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    BEGIN RETURN jsonb_build_object('state','ok','value',value::date);
    EXCEPTION WHEN others THEN RETURN jsonb_build_object('state','error','reason','DATE_INVALID'); END;
  END IF;
  IF value ~ '^[0-9]{1,6}$' THEN
    serial:=value::integer;
    IF p_date_system='1900' THEN
      -- Serial 60 is Excel's non-existent 29 February 1900; it is refused.
      IF serial=60 THEN RETURN jsonb_build_object('state','error','reason','EXCEL_1900_LEAP_BUG'); END IF;
      IF serial<1 OR serial>2958465 THEN RETURN jsonb_build_object('state','error','reason','DATE_OUT_OF_RANGE'); END IF;
      epoch:=DATE '1899-12-30';
      IF serial<60 THEN epoch:=DATE '1899-12-31'; END IF;
      RETURN jsonb_build_object('state','ok','value',epoch+serial,'system','1900');
    END IF;
    IF serial<0 OR serial>2957003 THEN RETURN jsonb_build_object('state','error','reason','DATE_OUT_OF_RANGE'); END IF;
    RETURN jsonb_build_object('state','ok','value',DATE '1904-01-01'+serial,'system','1904');
  END IF;
  RETURN jsonb_build_object('state','error','reason','DATE_INVALID');
END $$;
CREATE FUNCTION private_isg.allocate_document_number(p_company uuid,p_scope text,p_year integer) RETURNS text
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE value bigint;
BEGIN
  IF p_company IS NULL OR p_scope IS NULL OR p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2100 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- One locked row per company, scope and year: twenty concurrent exports get
  -- twenty different numbers and never the same one twice.
  INSERT INTO private_isg.document_number_sequences(company_id,scope,year) VALUES(p_company,p_scope,p_year)
    ON CONFLICT(company_id,scope,year) DO NOTHING;
  UPDATE private_isg.document_number_sequences SET next_value=next_value+1
    WHERE company_id=p_company AND scope=p_scope AND year=p_year RETURNING next_value-1 INTO value;
  RETURN upper(p_scope)||'-'||p_year::text||'-'||value::text;
END $$;
CREATE FUNCTION private_isg.register_document(p_company uuid,p_workplace uuid,p_domain text,p_source_ref text,
  p_template text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; document uuid; existing private_isg.documents; reference text;
BEGIN
  PERFORM private_isg.document_gate(true);
  IF p_company IS NULL OR p_domain IS NULL OR p_source_ref IS NULL OR p_template IS NULL OR p_now IS NULL OR
     p_domain NOT IN ('training','risk','nonconformity','module','personnel') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT user_id INTO owner FROM public.companies WHERE id=p_company FOR SHARE;
  IF owner IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM 1 FROM private_isg.document_template_versions v JOIN private_isg.document_templates t USING(template_code)
    WHERE v.template_code=p_template AND v.status='published' AND t.source_domain=p_domain FOR SHARE OF v,t;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_NOT_PUBLISHED'; END IF;
  reference:=private_isg.text_value(p_source_ref,200);
  SELECT * INTO existing FROM private_isg.documents WHERE company_id=p_company AND source_domain=p_domain
    AND source_ref=reference AND template_code=p_template;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'document_id',existing.document_id,
    'current_version',existing.current_version,'replayed',true); END IF;
  INSERT INTO private_isg.documents(company_id,owner_id,workplace_id,source_domain,source_ref,template_code,created_at)
    VALUES(p_company,owner,p_workplace,p_domain,reference,p_template,p_now) RETURNING document_id INTO document;
  RETURN jsonb_build_object('schema_version',1,'document_id',document,'current_version',0,'replayed',false);
END $$;
-- Finalising snapshots everything the document shows and allocates its number
-- in the same transaction. A retry returns the same logical document.
CREATE FUNCTION private_isg.finalize_document_version(p_document uuid,p_mutation uuid,p_snapshot jsonb,
  p_source_kind text,p_scope text,p_year integer,p_finalized_by uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.documents; template private_isg.document_template_versions;
  existing private_isg.document_versions; next_version integer; number text; digest bytea;
BEGIN
  PERFORM private_isg.document_gate(true);
  IF p_document IS NULL OR p_mutation IS NULL OR p_snapshot IS NULL OR jsonb_typeof(p_snapshot)<>'object' OR
     p_source_kind IS NULL OR p_source_kind NOT IN ('structured','scanned') OR p_scope IS NULL OR
     p_finalized_by IS NULL OR p_now IS NULL OR octet_length(p_snapshot::text)>200000 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.documents WHERE document_id=p_document FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO existing FROM private_isg.document_versions WHERE document_id=p_document AND mutation_id=p_mutation;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'document_id',p_document,'version',existing.version,
    'document_no',existing.document_no,'snapshot_sha256',encode(existing.snapshot_sha256,'hex'),'replayed',true); END IF;
  SELECT * INTO template FROM private_isg.document_template_versions
    WHERE template_code=entry.template_code AND status='published' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_NOT_PUBLISHED'; END IF;
  next_version:=entry.current_version+1;
  number:=private_isg.allocate_document_number(entry.company_id,p_scope,p_year);
  digest:=sha256(convert_to(p_snapshot::text,'UTF8'));
  INSERT INTO private_isg.document_versions(document_id,version,template_version,document_no,source_kind,snapshot,
      snapshot_sha256,finalized_by,finalized_at,mutation_id)
    VALUES(p_document,next_version,template.version,number,p_source_kind,p_snapshot,digest,p_finalized_by,p_now,p_mutation);
  UPDATE private_isg.documents SET current_version=next_version WHERE document_id=p_document;
  RETURN jsonb_build_object('schema_version',1,'document_id',p_document,'version',next_version,'document_no',number,
    'template_version',template.version,'snapshot_sha256',encode(digest,'hex'),'replayed',false);
END $$;
-- Both formats render the same snapshot. A scanned original never becomes a
-- structured spreadsheet: its XLSX can only be a metadata index.
CREATE FUNCTION private_isg.request_export(p_document uuid,p_version integer,p_format text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE revision private_isg.document_versions; existing private_isg.export_jobs; job uuid; content text;
BEGIN
  PERFORM private_isg.document_gate(true);
  IF p_document IS NULL OR p_version IS NULL OR p_format IS NULL OR p_format NOT IN ('pdf','xlsx') OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO revision FROM private_isg.document_versions AS v
    WHERE v.document_id=p_document AND v.version=p_version FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO existing FROM private_isg.export_jobs AS j
    WHERE j.document_id=p_document AND j.version=p_version AND j.format=p_format;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'job_id',existing.job_id,'format',p_format,
    'content_kind',existing.content_kind,'state',existing.state,'replayed',true); END IF;
  content:=CASE WHEN p_format='xlsx' AND revision.source_kind='scanned' THEN 'metadata_index' ELSE 'structured' END;
  INSERT INTO private_isg.export_jobs(document_id,version,format,content_kind,snapshot_sha256,created_at,updated_at)
    VALUES(p_document,p_version,p_format,content,revision.snapshot_sha256,p_now,p_now) RETURNING job_id INTO job;
  RETURN jsonb_build_object('schema_version',1,'job_id',job,'format',p_format,'content_kind',content,'state','queued',
    'snapshot_sha256',encode(revision.snapshot_sha256,'hex'),'replayed',false);
END $$;
CREATE FUNCTION private_isg.settle_export(p_job uuid,p_state text,p_asset uuid,p_error text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.export_jobs;
BEGIN
  PERFORM private_isg.document_gate(true);
  IF p_job IS NULL OR p_state IS NULL OR p_now IS NULL OR p_state NOT IN ('rendering','ready','failed') OR
     (p_state='ready')<>(p_asset IS NOT NULL) OR (p_state='failed')<>(p_error IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.export_jobs WHERE job_id=p_job FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state=p_state THEN RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state',p_state,'replayed',true); END IF;
  IF entry.state='ready' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  UPDATE private_isg.export_jobs SET state=p_state,asset_id=p_asset,error_code=p_error,updated_at=p_now WHERE job_id=p_job;
  RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state',p_state,'error_code',p_error,'replayed',false);
END $$;
CREATE FUNCTION private_isg.open_import_batch(p_company uuid,p_target text,p_asset uuid,p_file_sha256 bytea,
  p_mapping_version integer,p_mutation uuid,p_date_system text,p_decimal text,p_columns jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; batch uuid; prior private_isg.import_batches; fingerprint bytea; column_name text;
BEGIN
  PERFORM private_isg.import_gate(true);
  IF p_company IS NULL OR p_target IS NULL OR p_asset IS NULL OR p_file_sha256 IS NULL OR
     octet_length(p_file_sha256)<>32 OR p_mapping_version IS NULL OR p_mutation IS NULL OR p_now IS NULL OR
     p_target NOT IN ('employee','equipment') OR p_columns IS NULL OR jsonb_typeof(p_columns)<>'array' OR
     jsonb_array_length(p_columns) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT user_id INTO owner FROM public.companies WHERE id=p_company FOR SHARE;
  IF owner IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  FOR column_name IN SELECT value FROM jsonb_array_elements_text(p_columns) AS t(value) LOOP
    IF NOT private_isg.import_column_allowed(column_name) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='HEALTH_COLUMN_REFUSED'; END IF;
  END LOOP;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_target,encode(p_file_sha256,'hex'),p_mapping_version)::text,'UTF8'));
  SELECT * INTO prior FROM private_isg.import_batches WHERE company_id=p_company AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'batch_id',prior.batch_id,'state',prior.state,'replayed',true);
  END IF;
  INSERT INTO private_isg.import_batches(company_id,owner_id,target_kind,asset_id,file_sha256,mapping_version,
      mutation_id,request_hash,date_system,decimal_separator,created_at,updated_at)
    VALUES(p_company,owner,p_target,p_asset,p_file_sha256,p_mapping_version,p_mutation,fingerprint,
      coalesce(p_date_system,'1900'),coalesce(p_decimal,','),p_now,p_now) RETURNING batch_id INTO batch;
  RETURN jsonb_build_object('schema_version',1,'batch_id',batch,'state','draft','replayed',false);
END $$;
-- Identity is never guessed from a name: without a code the row waits for the
-- expert instead of silently matching or creating a second person.
CREATE FUNCTION private_isg.stage_import_row(p_batch uuid,p_row integer,p_raw jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE batch private_isg.import_batches; code jsonb; name jsonb; hired jsonb;
  status text; reason text; normalised jsonb; target uuid; target_version bigint;
BEGIN
  PERFORM private_isg.import_gate(true);
  IF p_batch IS NULL OR p_row IS NULL OR p_row NOT BETWEEN 1 AND 10000 OR p_raw IS NULL OR
     jsonb_typeof(p_raw)<>'object' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO batch FROM private_isg.import_batches WHERE batch_id=p_batch FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF batch.state NOT IN ('draft','previewed') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BATCH_COMMITTED'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_raw) AS t(key) WHERE NOT private_isg.import_column_allowed(key)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='HEALTH_COLUMN_REFUSED'; END IF;
  code:=private_isg.import_cell_value('code',p_raw->>'employee_code',batch.date_system,batch.decimal_separator);
  name:=private_isg.import_cell_value('text',p_raw->>'full_name',batch.date_system,batch.decimal_separator);
  hired:=private_isg.import_cell_value('date',p_raw->>'hired_on',batch.date_system,batch.decimal_separator);
  status:='ok';
  IF name->>'state'<>'ok' THEN status:='error'; reason:='NAME_REQUIRED';
  ELSIF code->>'state'='empty' THEN status:='review'; reason:='IDENTITY_NOT_DERIVABLE';
  ELSIF code->>'state'<>'ok' THEN status:='error'; reason:=code->>'reason';
  ELSIF hired->>'state' NOT IN ('ok','empty') THEN status:='error'; reason:=hired->>'reason';
  END IF;
  IF status='ok' THEN
    SELECT id,record_version INTO target,target_version FROM private_isg.employees
      WHERE company_id=batch.company_id AND employee_code=(code->>'value');
    IF FOUND THEN status:='duplicate'; reason:='EMPLOYEE_CODE_EXISTS'; END IF;
  END IF;
  normalised:=jsonb_build_object('employee_code',code->'value','full_name',name->'value','hired_on',hired->'value',
    'sanitised',(name->>'sanitised')::boolean OR (code->>'sanitised')::boolean);
  INSERT INTO private_isg.import_rows(batch_id,row_no,raw,normalised,status,error_code,target_ref,target_version)
    VALUES(p_batch,p_row,p_raw,normalised,status,CASE WHEN status='ok' THEN NULL ELSE reason END,
      target,target_version)
  ON CONFLICT(batch_id,row_no) DO UPDATE SET raw=excluded.raw,normalised=excluded.normalised,status=excluded.status,
    error_code=excluded.error_code,target_ref=excluded.target_ref,target_version=excluded.target_version;
  UPDATE private_isg.import_batches SET state='draft',preview_sha256=NULL,updated_at=p_now WHERE batch_id=p_batch;
  RETURN jsonb_build_object('schema_version',1,'batch_id',p_batch,'row_no',p_row,'status',status,
    'error_code',CASE WHEN status='ok' THEN NULL ELSE reason END,'normalised',normalised);
END $$;
CREATE FUNCTION private_isg.preview_import_batch(p_batch uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE batch private_isg.import_batches; digest bytea; summary jsonb;
BEGIN
  PERFORM private_isg.import_gate(true);
  IF p_batch IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO batch FROM private_isg.import_batches WHERE batch_id=p_batch FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF batch.state='committed' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BATCH_COMMITTED'; END IF;
  -- The preview hash covers every row's status and the target versions it saw.
  SELECT sha256(convert_to(coalesce(string_agg(row_no::text||':'||status||':'||coalesce(error_code,'-')||':'||
    coalesce(target_ref::text,'-')||':'||coalesce(target_version::text,'-'),'|' ORDER BY row_no),''),'UTF8')),
    jsonb_build_object('rows',count(*),'ok',count(*) FILTER (WHERE status='ok'),
      'error',count(*) FILTER (WHERE status='error'),'duplicate',count(*) FILTER (WHERE status='duplicate'),
      'review',count(*) FILTER (WHERE status='review'))
    INTO digest,summary FROM private_isg.import_rows WHERE batch_id=p_batch;
  UPDATE private_isg.import_batches SET state='previewed',preview_sha256=digest,updated_at=p_now WHERE batch_id=p_batch;
  RETURN jsonb_build_object('schema_version',1,'batch_id',p_batch,'state','previewed',
    'preview_sha256',encode(digest,'hex'),'summary',summary);
END $$;
-- Commit needs the expert's preview hash. If a target record moved since the
-- preview, the commit conflicts instead of writing over the newer state.
CREATE FUNCTION private_isg.commit_import_batch(p_batch uuid,p_preview_sha256 bytea,p_allow_partial boolean,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE batch private_isg.import_batches; row_entry private_isg.import_rows;
  created integer:=0; skipped integer:=0; employee uuid; blocked integer;
BEGIN
  PERFORM private_isg.import_gate(true);
  IF p_batch IS NULL OR p_preview_sha256 IS NULL OR p_allow_partial IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO batch FROM private_isg.import_batches WHERE batch_id=p_batch FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF batch.state='committed' THEN
    SELECT count(*) INTO created FROM private_isg.import_rows WHERE batch_id=p_batch AND committed;
    RETURN jsonb_build_object('schema_version',1,'batch_id',p_batch,'state','committed','created',created,'replayed',true);
  END IF;
  IF batch.state<>'previewed' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PREVIEW_REQUIRED'; END IF;
  IF batch.preview_sha256 IS DISTINCT FROM p_preview_sha256 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PREVIEW_STALE'; END IF;
  -- A target that changed after the preview invalidates the preview itself.
  SELECT count(*) INTO blocked FROM private_isg.import_rows r JOIN private_isg.employees e ON e.id=r.target_ref
    WHERE r.batch_id=p_batch AND e.record_version IS DISTINCT FROM r.target_version;
  IF blocked>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PREVIEW_STALE'; END IF;
  SELECT count(*) INTO blocked FROM private_isg.import_rows WHERE batch_id=p_batch AND status<>'ok';
  IF blocked>0 AND NOT p_allow_partial THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTIAL_COMMIT_NOT_ALLOWED'; END IF;
  FOR row_entry IN SELECT * FROM private_isg.import_rows WHERE batch_id=p_batch ORDER BY row_no LOOP
    IF row_entry.status<>'ok' THEN skipped:=skipped+1; CONTINUE; END IF;
    employee:=gen_random_uuid();
    INSERT INTO private_isg.employees(id,company_id,owner_id,employee_code,full_name,hired_on)
      VALUES(employee,batch.company_id,batch.owner_id,row_entry.normalised->>'employee_code',
        row_entry.normalised->>'full_name',(row_entry.normalised->>'hired_on')::date);
    UPDATE private_isg.import_rows SET committed=true,target_ref=employee,target_version=0
      WHERE batch_id=p_batch AND row_no=row_entry.row_no;
    created:=created+1;
    INSERT INTO private_isg.import_checkpoints(batch_id,last_row_no,committed_rows,created_at)
      VALUES(p_batch,row_entry.row_no,created,p_now) ON CONFLICT DO NOTHING;
  END LOOP;
  UPDATE private_isg.import_batches SET state='committed',committed_at=p_now,updated_at=p_now WHERE batch_id=p_batch;
  RETURN jsonb_build_object('schema_version',1,'batch_id',p_batch,'state','committed','created',created,
    'skipped',skipped,'partial',skipped>0,'replayed',false);
END $$;
-- Compensation removes only what this batch created and only while it is still
-- exactly as this batch left it. A later edit is never undone.
CREATE FUNCTION private_isg.compensate_import_batch(p_batch uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE batch private_isg.import_batches; row_entry private_isg.import_rows; removed integer:=0; kept integer:=0;
  current_version bigint;
BEGIN
  PERFORM private_isg.import_gate(true);
  IF p_batch IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO batch FROM private_isg.import_batches WHERE batch_id=p_batch FOR UPDATE;
  IF NOT FOUND OR batch.state<>'committed' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR row_entry IN SELECT * FROM private_isg.import_rows WHERE batch_id=p_batch AND committed ORDER BY row_no LOOP
    SELECT record_version INTO current_version FROM private_isg.employees WHERE id=row_entry.target_ref FOR UPDATE;
    IF current_version IS NULL THEN kept:=kept+1; CONTINUE; END IF;
    IF current_version<>row_entry.target_version THEN kept:=kept+1; CONTINUE; END IF;
    DELETE FROM private_isg.employees WHERE id=row_entry.target_ref;
    UPDATE private_isg.import_rows SET committed=false WHERE batch_id=p_batch AND row_no=row_entry.row_no;
    removed:=removed+1;
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'batch_id',p_batch,'removed',removed,'kept_because_changed',kept);
END $$;
REVOKE ALL ON FUNCTION private_isg.document_gate(boolean),private_isg.import_gate(boolean),
  private_isg.sanitise_cell(text),private_isg.import_column_allowed(text),
  private_isg.import_cell_value(text,text,text,text),
  private_isg.allocate_document_number(uuid,text,integer),
  private_isg.register_document(uuid,uuid,text,text,text,timestamptz),
  private_isg.finalize_document_version(uuid,uuid,jsonb,text,text,integer,uuid,timestamptz),
  private_isg.request_export(uuid,integer,text,timestamptz),
  private_isg.settle_export(uuid,text,uuid,text,timestamptz),
  private_isg.open_import_batch(uuid,text,uuid,bytea,integer,uuid,text,text,jsonb,timestamptz),
  private_isg.stage_import_row(uuid,integer,jsonb,timestamptz),
  private_isg.preview_import_batch(uuid,timestamptz),
  private_isg.commit_import_batch(uuid,bytea,boolean,timestamptz),
  private_isg.compensate_import_batch(uuid,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
