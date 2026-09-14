-- P04/D04 first vertical slice: purpose matrix, upload intent, quarantine state
-- machine, anti-TOCTOU promotion and immutable assets. Additive; rollout OFF.
-- No bucket, storage policy, scanner or client surface is created here, and the
-- legacy analysis photo / report storage paths are untouched.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core'));
INSERT INTO private_isg.rollout(feature) VALUES('file_core');

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
  reservation_id uuid REFERENCES private_isg.quota_reservations(reservation_id) ON DELETE SET NULL,
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
NOTIFY pgrst,'reload schema';
COMMIT;
