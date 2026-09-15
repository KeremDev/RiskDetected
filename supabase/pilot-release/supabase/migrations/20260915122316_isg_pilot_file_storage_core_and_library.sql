-- Pilot-only deployment of P04's file storage core + P11's third slice (the
-- client surface behind what is being renamed "Dosyalarım"). Both candidate
-- migrations (20260913130000_isg_file_core.sql, 20260915010000_isg_file_library.sql)
-- are applied verbatim below, merged into one transaction; the only change
-- from the candidate text is the rollout_feature_check constraint, which is
-- widened additively against the live feature list instead of each file's
-- own narrower list (which would have dropped 'modules','document_tracking',
-- 'nonconformity','risk' off the live constraint and broken their existing
-- rows). Live: personnel, modules, document_tracking, nonconformity, risk.
SET LOCAL lock_timeout='5s';

ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','modules','document_tracking','nonconformity','risk',
    'event_dispatch','quota_ledger','file_core','rule_engine','training','documents','imports',
    'notifications','personal_notes','billing_lifecycle','campaigns','observability','score','file_library'));
INSERT INTO private_isg.rollout(feature) VALUES('file_core'),('file_library');


-- Server-side acceptance matrix. An OS picker that hides a format is a UX
-- convenience; this table is the authority for what may be uploaded at all.
CREATE TABLE private_isg.file_purposes (
  purpose text PRIMARY KEY CHECK(purpose IN ('company_document','evidence_photo','structured_import','company_logo')),
  extensions text[] NOT NULL CHECK(array_length(extensions,1) BETWEEN 1 AND 13),
  max_bytes bigint NOT NULL CHECK(max_bytes BETWEEN 1 AND 1073741824),
  requires_scan boolean NOT NULL DEFAULT true,
  -- The V5 source calls 50 MiB / 10 MiB candidates. They are test inputs until
  -- P04/P11 closes the cost and performance gate, so the row says so.
  limit_approved boolean NOT NULL DEFAULT false,
  limit_source text NOT NULL CHECK(limit_source IN ('v5_candidate','approved')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(limit_approved=(limit_source='approved'))
);
INSERT INTO private_isg.file_purposes(purpose,extensions,max_bytes,requires_scan,limit_source) VALUES
  ('company_document',ARRAY['pdf','doc','docx','xls','xlsx'],52428800,true,'v5_candidate'),
  ('evidence_photo',ARRAY['jpg','jpeg','png','heic','heif','webp','avif'],52428800,true,'v5_candidate'),
  ('structured_import',ARRAY['xls','xlsx','csv'],10485760,true,'v5_candidate'),
  ('company_logo',ARRAY['jpg','jpeg','png','webp'],5242880,true,'v5_candidate');

CREATE TABLE private_isg.upload_intents (
  intent_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id uuid,
  purpose text NOT NULL REFERENCES private_isg.file_purposes(purpose),
  declared_extension text NOT NULL CHECK(declared_extension ~ '^[a-z0-9]{2,5}$'),
  declared_bytes bigint NOT NULL CHECK(declared_bytes BETWEEN 0 AND 1073741824),
  declared_sha256 bytea NOT NULL CHECK(octet_length(declared_sha256)=32),
  received_bytes bigint CHECK(received_bytes IS NULL OR received_bytes>=0),
  received_sha256 bytea CHECK(received_sha256 IS NULL OR octet_length(received_sha256)=32),
  detected_type text CHECK(detected_type IS NULL OR detected_type ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  -- Written once at creation and never rewritten: a scanned object can not be
  -- swapped under a path that was already cleared.
  quarantine_path text NOT NULL UNIQUE CHECK(quarantine_path ~ '^quarantine/[0-9a-f-]{36}/[0-9a-f-]{36}$'),
  state text NOT NULL DEFAULT 'pending'
    CHECK(state IN ('pending','uploaded','scanning','clean','rejected','scan_failed','promoted','expired')),
  rejection_code text CHECK(rejection_code IS NULL OR rejection_code IN
    ('UNSUPPORTED_FORMAT','SIZE_LIMIT','HASH_MISMATCH','MIME_MISMATCH','SCAN_REJECTED','SCAN_UNAVAILABLE','EXPIRED')),
  reservation_id uuid,  -- quota_ledger not deployed live; shadow reservation never populated while it stays closed
  storage_shadow_denied boolean NOT NULL DEFAULT false,
  operation_id uuid NOT NULL, mutation_id uuid NOT NULL, request_hash bytea NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_id,mutation_id),
  CHECK((state IN ('rejected','scan_failed','expired'))=(rejection_code IS NOT NULL))
);
-- Only a clean, hash-reverified original becomes an asset, and its path is
-- unique forever: promotion can never overwrite an existing object.
CREATE TABLE private_isg.file_assets (
  asset_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id uuid, purpose text NOT NULL REFERENCES private_isg.file_purposes(purpose),
  bucket text NOT NULL CHECK(bucket ~ '^[a-z0-9-]{3,63}$'),
  immutable_path text NOT NULL UNIQUE CHECK(immutable_path ~ '^assets/[0-9a-f-]{36}/[0-9a-f]{64}$'),
  extension text NOT NULL, detected_type text NOT NULL,
  sha256 bytea NOT NULL CHECK(octet_length(sha256)=32),
  bytes bigint NOT NULL CHECK(bytes>=0),
  scan_version text NOT NULL, scan_status text NOT NULL DEFAULT 'clean' CHECK(scan_status='clean'),
  preview_status text NOT NULL DEFAULT 'none' CHECK(preview_status IN ('none','pending','ready','failed')),
  source_intent_id uuid NOT NULL UNIQUE REFERENCES private_isg.upload_intents(intent_id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_isg.file_derivatives (
  derivative_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_asset_id uuid NOT NULL REFERENCES private_isg.file_assets(asset_id) ON DELETE CASCADE,
  kind text NOT NULL CHECK(kind IN ('preview','thumbnail','text_extract')),
  renderer_version text NOT NULL CHECK(btrim(renderer_version)<>''),
  state text NOT NULL CHECK(state IN ('pending','ready','failed')),
  path text UNIQUE CHECK(path IS NULL OR path ~ '^derivatives/[0-9a-f-]{36}/[a-z_]+/[0-9a-f]{64}$'),
  bytes bigint CHECK(bytes IS NULL OR bytes>=0),
  failure_code text CHECK(failure_code IS NULL OR failure_code IN ('RENDER_FAILED','UNSUPPORTED_FORMAT','RESOURCE_LIMIT')),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(source_asset_id,kind,renderer_version),
  CHECK((state='ready')=(path IS NOT NULL)), CHECK((state='failed')=(failure_code IS NOT NULL))
);
CREATE TABLE private_isg.file_scan_results (
  intent_id uuid PRIMARY KEY REFERENCES private_isg.upload_intents(intent_id) ON DELETE CASCADE,
  scanner text NOT NULL CHECK(btrim(scanner)<>''), scan_version text NOT NULL CHECK(btrim(scan_version)<>''),
  verdict text NOT NULL CHECK(verdict IN ('clean','rejected','failed')),
  finding_code text CHECK(finding_code IS NULL OR finding_code ~ '^[A-Z][A-Z_]{2,39}$'),
  scanned_sha256 bytea NOT NULL CHECK(octet_length(scanned_sha256)=32),
  evidence jsonb NOT NULL, scanned_at timestamptz NOT NULL,
  CHECK((verdict='clean')=(finding_code IS NULL))
);
CREATE INDEX upload_intent_owner_idx ON private_isg.upload_intents(owner_id,state);
CREATE INDEX upload_intent_purpose_idx ON private_isg.upload_intents(purpose);
CREATE INDEX upload_intent_company_idx ON private_isg.upload_intents(company_id);
CREATE INDEX upload_intent_expiry_idx ON private_isg.upload_intents(state,expires_at);
CREATE INDEX upload_intent_reservation_idx ON private_isg.upload_intents(reservation_id);
CREATE INDEX file_asset_owner_idx ON private_isg.file_assets(owner_id,purpose);
CREATE INDEX file_asset_purpose_idx ON private_isg.file_assets(purpose);
CREATE INDEX file_asset_company_idx ON private_isg.file_assets(company_id);
CREATE INDEX file_derivative_asset_idx ON private_isg.file_derivatives(source_asset_id);
ALTER TABLE private_isg.file_purposes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.upload_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.file_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.file_derivatives ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.file_scan_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.file_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='file_core' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
CREATE FUNCTION private_isg.quota_ledger_open() RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT coalesce((SELECT write_enabled FROM private_isg.rollout WHERE feature='quota_ledger'),false)
$$;
CREATE FUNCTION private_isg.file_acceptance(p_purpose text,p_extension text,p_bytes bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE policy private_isg.file_purposes; normalized text;
BEGIN
  IF p_purpose IS NULL OR p_extension IS NULL OR p_bytes IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO policy FROM private_isg.file_purposes WHERE purpose=p_purpose;
  IF NOT FOUND THEN RETURN jsonb_build_object('accepted',false,'reason','UNSUPPORTED_FORMAT'); END IF;
  normalized:=lower(btrim(p_extension));
  IF normalized<>ALL(policy.extensions) THEN RETURN jsonb_build_object('accepted',false,'reason','UNSUPPORTED_FORMAT'); END IF;
  -- Zero bytes is not a document. limit, limit-1 pass; limit+1 does not.
  IF p_bytes<1 OR p_bytes>policy.max_bytes THEN RETURN jsonb_build_object('accepted',false,'reason','SIZE_LIMIT'); END IF;
  RETURN jsonb_build_object('accepted',true,'reason',NULL,'max_bytes',policy.max_bytes,
    'requires_scan',policy.requires_scan,'limit_approved',policy.limit_approved);
END $$;
CREATE FUNCTION private_isg.open_upload_intent(p_owner uuid,p_company uuid,p_purpose text,p_extension text,
  p_bytes bigint,p_sha256 bytea,p_operation uuid,p_mutation uuid,p_storage_limit bigint,p_storage_unlimited boolean,
  p_ttl_seconds integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prior private_isg.upload_intents; verdict jsonb; fingerprint bytea; intent uuid:=gen_random_uuid();
  reservation uuid; denied boolean:=false; ledger_open boolean;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_owner IS NULL OR p_purpose IS NULL OR p_extension IS NULL OR p_bytes IS NULL OR p_sha256 IS NULL OR
     octet_length(p_sha256)<>32 OR p_operation IS NULL OR p_mutation IS NULL OR p_now IS NULL OR
     p_ttl_seconds IS NULL OR p_ttl_seconds NOT BETWEEN 60 AND 86400 OR p_storage_unlimited IS NULL OR
     (p_storage_unlimited AND p_storage_limit IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_owner,p_company,p_purpose,lower(btrim(p_extension)),p_bytes,encode(p_sha256,'hex'),p_operation)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(p_owner::text||':isg-upload:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.upload_intents WHERE owner_id=p_owner AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'intent_id',prior.intent_id,'state',prior.state,
      'quarantine_path',prior.quarantine_path,'replayed',true);
  END IF;
  verdict:=private_isg.file_acceptance(p_purpose,p_extension,p_bytes);
  IF NOT (verdict->>'accepted')::boolean THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE=verdict->>'reason'; END IF;
  -- The ledger is still shadow: a storage disagreement is recorded, not enforced.
  ledger_open:=private_isg.quota_ledger_open();
  IF ledger_open THEN
    BEGIN
      reservation:=(private_isg.reserve_quota(p_owner,p_company,'storage_bytes','lifetime',p_bytes,'plan',
        p_operation,p_mutation,p_storage_limit,p_storage_unlimited,p_ttl_seconds,p_now)->>'reservation_id')::uuid;
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM<>'CAPACITY_EXCEEDED' THEN RAISE; END IF;
      denied:=true;
    END;
  END IF;
  INSERT INTO private_isg.upload_intents(intent_id,owner_id,company_id,purpose,declared_extension,declared_bytes,
      declared_sha256,quarantine_path,reservation_id,storage_shadow_denied,operation_id,mutation_id,request_hash,
      expires_at,created_at,updated_at)
    VALUES(intent,p_owner,p_company,p_purpose,lower(btrim(p_extension)),p_bytes,p_sha256,
      'quarantine/'||p_owner::text||'/'||intent::text,reservation,denied,p_operation,p_mutation,fingerprint,
      p_now+make_interval(secs=>p_ttl_seconds),p_now,p_now);
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent,'state','pending',
    'quarantine_path','quarantine/'||p_owner::text||'/'||intent::text,'reservation_id',reservation,
    'storage_shadow_denied',denied,'storage_authority','legacy','replayed',false);
END $$;
CREATE FUNCTION private_isg.reject_upload_intent(p_intent uuid,p_code text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.upload_intents; next_state text;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_intent IS NULL OR p_now IS NULL OR p_code IS NULL OR p_code NOT IN
     ('UNSUPPORTED_FORMAT','SIZE_LIMIT','HASH_MISMATCH','MIME_MISMATCH','SCAN_REJECTED','SCAN_UNAVAILABLE','EXPIRED') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.upload_intents WHERE intent_id=p_intent FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='promoted' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF entry.state IN ('rejected','scan_failed','expired') THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state',entry.state,'replayed',true); END IF;
  next_state:=CASE p_code WHEN 'SCAN_UNAVAILABLE' THEN 'scan_failed' WHEN 'EXPIRED' THEN 'expired' ELSE 'rejected' END;
  UPDATE private_isg.upload_intents SET state=next_state,rejection_code=p_code,updated_at=p_now WHERE intent_id=p_intent;
  -- The shadow ledger can be closed independently; that must not block a rejection.
  IF entry.reservation_id IS NOT NULL AND private_isg.quota_ledger_open() THEN
    PERFORM private_isg.release_quota(entry.reservation_id,p_now); END IF;
  RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state',next_state,'rejection_code',p_code,'replayed',false);
END $$;
CREATE FUNCTION private_isg.mark_upload_received(p_intent uuid,p_bytes bigint,p_sha256 bytea,p_detected_type text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.upload_intents; verdict jsonb; failure text;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_intent IS NULL OR p_bytes IS NULL OR p_sha256 IS NULL OR octet_length(p_sha256)<>32 OR
     p_detected_type IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.upload_intents WHERE intent_id=p_intent FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='uploaded' AND entry.received_sha256=p_sha256 AND entry.received_bytes=p_bytes THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state','uploaded','replayed',true); END IF;
  IF entry.state<>'pending' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF entry.expires_at<=p_now THEN
    RETURN private_isg.reject_upload_intent(p_intent,'EXPIRED',p_now); END IF;
  -- What actually landed decides, not what the client declared.
  verdict:=private_isg.file_acceptance(entry.purpose,entry.declared_extension,p_bytes);
  failure:=CASE WHEN p_sha256<>entry.declared_sha256 THEN 'HASH_MISMATCH'
                WHEN NOT (verdict->>'accepted')::boolean THEN verdict->>'reason'
                WHEN p_bytes<>entry.declared_bytes THEN 'SIZE_LIMIT'
                WHEN p_detected_type !~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$' THEN 'MIME_MISMATCH' END;
  IF failure IS NOT NULL THEN RETURN private_isg.reject_upload_intent(p_intent,failure,p_now); END IF;
  UPDATE private_isg.upload_intents SET state='uploaded',received_bytes=p_bytes,received_sha256=p_sha256,
    detected_type=p_detected_type,updated_at=p_now WHERE intent_id=p_intent;
  RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state','uploaded','replayed',false);
END $$;
-- A scanner error, timeout or network failure is never 'clean'.
CREATE FUNCTION private_isg.record_scan_result(p_intent uuid,p_scanner text,p_version text,p_verdict text,
  p_finding text,p_scanned_sha256 bytea,p_evidence jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.upload_intents; state text;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_intent IS NULL OR p_scanner IS NULL OR p_version IS NULL OR p_now IS NULL OR p_verdict IS NULL OR
     p_verdict NOT IN ('clean','rejected','failed') OR p_scanned_sha256 IS NULL OR octet_length(p_scanned_sha256)<>32 OR
     p_evidence IS NULL OR jsonb_typeof(p_evidence)<>'object' OR octet_length(p_evidence::text)>4096 OR
     (p_verdict='clean')<>(p_finding IS NULL) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.upload_intents WHERE intent_id=p_intent FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state NOT IN ('uploaded','scanning') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF entry.expires_at<=p_now THEN RETURN private_isg.reject_upload_intent(p_intent,'EXPIRED',p_now); END IF;
  -- The scanner must have read the same bytes the upload recorded.
  IF p_scanned_sha256<>entry.received_sha256 THEN RETURN private_isg.reject_upload_intent(p_intent,'HASH_MISMATCH',p_now); END IF;
  INSERT INTO private_isg.file_scan_results(intent_id,scanner,scan_version,verdict,finding_code,scanned_sha256,evidence,scanned_at)
    VALUES(p_intent,p_scanner,p_version,p_verdict,p_finding,p_scanned_sha256,p_evidence,p_now)
  ON CONFLICT(intent_id) DO UPDATE SET scanner=excluded.scanner,scan_version=excluded.scan_version,
    verdict=excluded.verdict,finding_code=excluded.finding_code,evidence=excluded.evidence,scanned_at=excluded.scanned_at;
  IF p_verdict='rejected' THEN RETURN private_isg.reject_upload_intent(p_intent,'SCAN_REJECTED',p_now); END IF;
  IF p_verdict='failed' THEN RETURN private_isg.reject_upload_intent(p_intent,'SCAN_UNAVAILABLE',p_now); END IF;
  UPDATE private_isg.upload_intents SET state='clean',updated_at=p_now WHERE intent_id=p_intent;
  RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state','clean','replayed',false);
END $$;
CREATE FUNCTION private_isg.promote_clean_upload(p_intent uuid,p_bucket text,p_final_sha256 bytea,p_final_bytes bigint,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.upload_intents; scan private_isg.file_scan_results; asset uuid; path text;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_intent IS NULL OR p_bucket IS NULL OR p_final_sha256 IS NULL OR octet_length(p_final_sha256)<>32 OR
     p_final_bytes IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.upload_intents WHERE intent_id=p_intent FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='promoted' THEN
    SELECT asset_id,immutable_path INTO asset,path FROM private_isg.file_assets WHERE source_intent_id=p_intent;
    RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'asset_id',asset,'immutable_path',path,'replayed',true);
  END IF;
  IF entry.state<>'clean' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF entry.expires_at<=p_now THEN RETURN private_isg.reject_upload_intent(p_intent,'EXPIRED',p_now); END IF;
  SELECT * INTO scan FROM private_isg.file_scan_results WHERE intent_id=p_intent FOR SHARE;
  IF NOT FOUND OR scan.verdict<>'clean' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- Anti-TOCTOU: the bytes promoted must still be the bytes that were scanned.
  IF p_final_sha256<>scan.scanned_sha256 OR p_final_bytes<>entry.received_bytes THEN
    RETURN private_isg.reject_upload_intent(p_intent,'HASH_MISMATCH',p_now); END IF;
  asset:=gen_random_uuid(); path:='assets/'||entry.owner_id::text||'/'||encode(p_final_sha256,'hex');
  INSERT INTO private_isg.file_assets(asset_id,owner_id,company_id,purpose,bucket,immutable_path,extension,
      detected_type,sha256,bytes,scan_version,source_intent_id,created_at)
    VALUES(asset,entry.owner_id,entry.company_id,entry.purpose,p_bucket,path,entry.declared_extension,
      entry.detected_type,p_final_sha256,p_final_bytes,scan.scan_version,p_intent,p_now);
  UPDATE private_isg.upload_intents SET state='promoted',updated_at=p_now WHERE intent_id=p_intent;
  IF entry.reservation_id IS NOT NULL AND private_isg.quota_ledger_open() THEN
    PERFORM private_isg.settle_quota(entry.reservation_id,jsonb_build_object('asset_id',asset,'bytes',p_final_bytes),p_now);
  END IF;
  RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'asset_id',asset,'immutable_path',path,
    'bucket',p_bucket,'scan_version',scan.scan_version,'replayed',false);
END $$;
CREATE FUNCTION private_isg.expire_upload_intents(p_now timestamptz) RETURNS integer
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE expired integer:=0; stale uuid;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR stale IN SELECT intent_id FROM private_isg.upload_intents
    WHERE state IN ('pending','uploaded','scanning','clean') AND expires_at<=p_now ORDER BY intent_id LOOP
    PERFORM private_isg.reject_upload_intent(stale,'EXPIRED',p_now); expired:=expired+1;
  END LOOP;
  RETURN expired;
END $$;
-- A failed preview never invalidates a clean original.
CREATE FUNCTION private_isg.record_derivative(p_asset uuid,p_kind text,p_renderer text,p_state text,
  p_path text,p_bytes bigint,p_failure text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; derivative uuid;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_asset IS NULL OR p_kind IS NULL OR p_renderer IS NULL OR p_now IS NULL OR p_state IS NULL OR
     p_state NOT IN ('pending','ready','failed') OR (p_state='ready')<>(p_path IS NOT NULL) OR
     (p_state='failed')<>(p_failure IS NOT NULL) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT owner_id INTO owner FROM private_isg.file_assets WHERE asset_id=p_asset FOR SHARE;
  IF owner IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  INSERT INTO private_isg.file_derivatives(source_asset_id,kind,renderer_version,state,path,bytes,failure_code,created_at,updated_at)
    VALUES(p_asset,p_kind,p_renderer,p_state,p_path,p_bytes,p_failure,p_now,p_now)
  ON CONFLICT(source_asset_id,kind,renderer_version) DO UPDATE SET state=excluded.state,path=excluded.path,
    bytes=excluded.bytes,failure_code=excluded.failure_code,updated_at=excluded.updated_at
  RETURNING derivative_id INTO derivative;
  UPDATE private_isg.file_assets SET preview_status=CASE WHEN p_kind='preview' THEN
    CASE p_state WHEN 'ready' THEN 'ready' WHEN 'failed' THEN 'failed' ELSE 'pending' END ELSE preview_status END
    WHERE asset_id=p_asset;
  RETURN jsonb_build_object('schema_version',1,'derivative_id',derivative,'asset_id',p_asset,'kind',p_kind,'state',p_state);
END $$;
REVOKE ALL ON FUNCTION private_isg.file_gate(boolean),private_isg.quota_ledger_open(),private_isg.file_acceptance(text,text,bigint),
  private_isg.open_upload_intent(uuid,uuid,text,text,bigint,bytea,uuid,uuid,bigint,boolean,integer,timestamptz),
  private_isg.reject_upload_intent(uuid,text,timestamptz),
  private_isg.mark_upload_received(uuid,bigint,bytea,text,timestamptz),
  private_isg.record_scan_result(uuid,text,text,text,text,bytea,jsonb,timestamptz),
  private_isg.promote_clean_upload(uuid,text,bytea,bigint,timestamptz),
  private_isg.expire_upload_intents(timestamptz),
  private_isg.record_derivative(uuid,text,text,text,text,bigint,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;


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
