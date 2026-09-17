-- Workspace file transport, byte evidence, download delivery and two-phase deletion. NOT DEPLOYED.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE TABLE private_isg.workspace_upload_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  company_id uuid,
  membership_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  idempotency_key uuid NOT NULL,
  request_hash bytea NOT NULL CHECK(octet_length(request_hash)=32),
  token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
  purpose text NOT NULL CHECK(octet_length(purpose) BETWEEN 1 AND 80),
  media_type text NOT NULL CHECK(octet_length(media_type) BETWEEN 3 AND 120),
  extension text NOT NULL CHECK(extension ~ '^[a-z0-9]{1,12}$'),
  expected_bytes bigint NOT NULL CHECK(expected_bytes BETWEEN 1 AND 2147483648),
  bucket text NOT NULL CHECK(bucket='isg-workspace-private'),
  object_path text NOT NULL CHECK(octet_length(object_path) BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','finalized','expired','cancelled')),
  asset_id uuid REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finalized_at timestamptz,
  UNIQUE(workspace_id,idempotency_key),
  UNIQUE(workspace_id,bucket,object_path),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(expires_at>created_at),
  CHECK((status='finalized')=(asset_id IS NOT NULL AND finalized_at IS NOT NULL))
);
CREATE INDEX workspace_upload_expiry ON private_isg.workspace_upload_intents(status,expires_at,id)
  WHERE status='open';

CREATE TABLE private_isg.workspace_download_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  asset_id uuid NOT NULL REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT,
  membership_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
  purpose text NOT NULL CHECK(octet_length(purpose) BETWEEN 1 AND 80),
  status text NOT NULL DEFAULT 'issued' CHECK(status IN ('issued','claimed','delivered','expired','revoked')),
  expires_at timestamptz NOT NULL,
  claimed_at timestamptz,
  delivered_at timestamptz,
  delivered_bytes bigint CHECK(delivered_bytes>0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(expires_at>created_at),
  CHECK((status='delivered')=(delivered_at IS NOT NULL AND delivered_bytes IS NOT NULL))
);
CREATE INDEX workspace_download_timeline ON private_isg.workspace_download_intents(workspace_id,created_at,id);

CREATE TABLE private_isg.workspace_asset_deletions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  asset_id uuid NOT NULL UNIQUE REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT,
  requested_by_membership_id uuid NOT NULL,
  reason text NOT NULL CHECK(octet_length(reason) BETWEEN 3 AND 500),
  state text NOT NULL DEFAULT 'requested' CHECK(state IN ('requested','deleted','failed')),
  object_version_evidence text,
  failure_code text,
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  FOREIGN KEY(workspace_id,requested_by_membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK((state='deleted')=(completed_at IS NOT NULL AND object_version_evidence IS NOT NULL)),
  CHECK(state<>'failed' OR failure_code IS NOT NULL)
);
CREATE INDEX workspace_asset_delete_queue ON private_isg.workspace_asset_deletions(state,requested_at,id)
  WHERE state IN ('requested','failed');

ALTER TABLE private_isg.workspace_upload_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_download_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_asset_deletions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_upload_intents,private_isg.workspace_download_intents,
  private_isg.workspace_asset_deletions FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_random_token() RETURNS text
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path='' AS $$
  SELECT encode(sha256(convert_to(gen_random_uuid()::text||gen_random_uuid()::text||clock_timestamp()::text,'UTF8')),'hex')
$$;

-- Storage INSERT permission is tied to the authenticated actor's still-open
-- upload intent. The client can neither choose another tenant path nor update
-- an object after it has landed.
CREATE FUNCTION private_isg.workspace_storage_upload_allowed(p_bucket text,p_name text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT p_bucket='isg-workspace-private' AND EXISTS(
    SELECT 1 FROM private_isg.workspace_upload_intents i
    JOIN private_isg.workspace_memberships m
      ON m.workspace_id=i.workspace_id AND m.id=i.membership_id
    WHERE i.bucket=p_bucket AND i.object_path=p_name AND i.status='open'
      AND i.expires_at>clock_timestamp() AND i.actor_user_id=private_isg.active_actor()
      AND m.user_id=i.actor_user_id AND m.status='active'
  )
$$;

CREATE FUNCTION private_isg.workspace_upload_open(p_workspace uuid,p_company uuid,p_idempotency uuid,
  p_request_hash bytea,p_purpose text,p_media_type text,p_extension text,p_expected_bytes bigint,
  p_expires_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  prior private_isg.workspace_upload_intents; intent private_isg.workspace_upload_intents;
  token text; clean_purpose text; clean_media text; clean_extension text;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_storage',true);
  IF p_company IS NULL THEN member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],true);
  ELSE member:=private_isg.workspace_require_company(p_workspace,p_company,true); END IF;
  clean_purpose:=private_isg.workspace_text(p_purpose,80);
  clean_media:=lower(private_isg.workspace_text(p_media_type,120));
  clean_extension:=lower(private_isg.workspace_text(p_extension,12));
  IF p_idempotency IS NULL OR p_request_hash IS NULL OR octet_length(p_request_hash)<>32 OR
     clean_media !~ '^[a-z0-9][a-z0-9.+-]+/[a-z0-9][a-z0-9.+-]+$' OR
     clean_extension !~ '^[a-z0-9]{1,12}$' OR p_expected_bytes NOT BETWEEN 1 AND 2147483648 OR
     p_expires_at IS NULL OR p_expires_at<=clock_timestamp()+interval '1 minute' OR
     p_expires_at>clock_timestamp()+interval '1 hour' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO prior FROM private_isg.workspace_upload_intents
    WHERE workspace_id=p_workspace AND idempotency_key=p_idempotency;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM p_request_hash OR prior.company_id IS DISTINCT FROM p_company OR
       ROW(prior.purpose,prior.media_type,prior.extension,prior.expected_bytes,prior.expires_at)
       IS DISTINCT FROM ROW(clean_purpose,clean_media,clean_extension,p_expected_bytes,p_expires_at) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'intent_id',prior.id,'workspace_id',prior.workspace_id,
      'status',prior.status,'bucket',prior.bucket,'object_path',prior.object_path,
      'expires_at',prior.expires_at,'credential_returned',false,'replayed',true);
  END IF;
  token:=private_isg.workspace_random_token();
  INSERT INTO private_isg.workspace_upload_intents(workspace_id,company_id,membership_id,actor_user_id,
    idempotency_key,request_hash,token_hash,purpose,media_type,extension,expected_bytes,bucket,
    object_path,expires_at)
    VALUES(p_workspace,p_company,member.id,actor,p_idempotency,p_request_hash,sha256(convert_to(token,'UTF8')),
      clean_purpose,clean_media,clean_extension,p_expected_bytes,'isg-workspace-private',
      p_workspace::text||'/'||p_idempotency::text||'.'||clean_extension,p_expires_at) RETURNING * INTO intent;
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'workspace_id',intent.workspace_id,
    'status',intent.status,'bucket',intent.bucket,'object_path',intent.object_path,
    'expires_at',intent.expires_at,'upload_token',token,'credential_returned',true,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_upload_finalize_via_token(p_token text,p_object_version text,
  p_actual_bytes bigint,p_sha bytea,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE clean_token text; intent private_isg.workspace_upload_intents; asset private_isg.workspace_file_assets;
  member private_isg.workspace_memberships;
BEGIN
  clean_token:=private_isg.workspace_text(p_token,128);
  IF clean_token !~ '^[0-9a-f]{64}$' OR p_object_version IS NULL OR
     octet_length(p_object_version) NOT BETWEEN 1 AND 200 OR p_actual_bytes<=0 OR
     p_sha IS NULL OR octet_length(p_sha)<>32 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent FROM private_isg.workspace_upload_intents
    WHERE token_hash=sha256(convert_to(clean_token,'UTF8')) FOR UPDATE;
  IF intent.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_TOKEN_INVALID'; END IF;
  IF intent.status='finalized' THEN
    SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=intent.asset_id;
    IF asset.object_version<>p_object_version OR asset.byte_size<>p_actual_bytes OR asset.sha256<>p_sha THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'asset_id',asset.id,'workspace_id',asset.workspace_id,
      'byte_size',asset.byte_size,'replayed',true);
  END IF;
  IF intent.status<>'open' OR intent.expires_at<=p_now THEN
    UPDATE private_isg.workspace_upload_intents SET status='expired' WHERE id=intent.id AND status='open';
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_TOKEN_EXPIRED'; END IF;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=intent.workspace_id AND id=intent.membership_id FOR SHARE;
  IF member.id IS NULL OR member.status<>'active' OR member.user_id<>intent.actor_user_id OR
     (member.role='expert' AND intent.company_id IS NOT NULL AND NOT EXISTS(
       SELECT 1 FROM private_isg.company_assignments a WHERE a.workspace_id=intent.workspace_id
         AND a.company_id=intent.company_id AND a.membership_id=member.id AND a.starts_at<=p_now
         AND (a.ends_at IS NULL OR a.ends_at>p_now))) THEN
    UPDATE private_isg.workspace_upload_intents SET status='cancelled' WHERE id=intent.id;
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_actual_bytes>intent.expected_bytes THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_SIZE_EXCEEDED'; END IF;
  INSERT INTO private_isg.workspace_file_assets(id,workspace_id,company_id,uploaded_by_membership_id,
    source_kind,bucket,object_path,object_version,byte_size,sha256,lifecycle,finalized_at)
    VALUES(intent.id,intent.workspace_id,intent.company_id,intent.membership_id,'upload',intent.bucket,
      intent.object_path,p_object_version,p_actual_bytes,p_sha,'active',p_now) RETURNING * INTO asset;
  UPDATE private_isg.workspace_upload_intents SET status='finalized',asset_id=asset.id,finalized_at=p_now
    WHERE id=intent.id;
  RETURN jsonb_build_object('schema_version',1,'asset_id',asset.id,'workspace_id',asset.workspace_id,
    'byte_size',asset.byte_size,'sha256',encode(asset.sha256,'hex'),'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_upload_claim(p_token text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE clean_token text; intent private_isg.workspace_upload_intents; member private_isg.workspace_memberships;
BEGIN
  clean_token:=private_isg.workspace_text(p_token,128);
  IF clean_token !~ '^[0-9a-f]{64}$' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent FROM private_isg.workspace_upload_intents
    WHERE token_hash=sha256(convert_to(clean_token,'UTF8')) FOR UPDATE;
  IF intent.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_TOKEN_INVALID'; END IF;
  IF intent.status='finalized' THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'workspace_id',intent.workspace_id,
      'status',intent.status,'asset_id',intent.asset_id,'replayed',true); END IF;
  IF intent.status<>'open' OR intent.expires_at<=p_now THEN
    UPDATE private_isg.workspace_upload_intents SET status='expired'
      WHERE id=intent.id AND status='open';
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_TOKEN_EXPIRED'; END IF;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=intent.workspace_id AND id=intent.membership_id FOR SHARE;
  IF member.id IS NULL OR member.status<>'active' OR member.user_id<>intent.actor_user_id OR
     (member.role='expert' AND intent.company_id IS NOT NULL AND NOT EXISTS(
       SELECT 1 FROM private_isg.company_assignments a WHERE a.workspace_id=intent.workspace_id
         AND a.company_id=intent.company_id AND a.membership_id=member.id AND a.starts_at<=p_now
         AND (a.ends_at IS NULL OR a.ends_at>p_now))) THEN
    UPDATE private_isg.workspace_upload_intents SET status='cancelled' WHERE id=intent.id;
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'workspace_id',intent.workspace_id,
    'company_id',intent.company_id,'status',intent.status,'bucket',intent.bucket,
    'object_path',intent.object_path,'media_type',intent.media_type,'extension',intent.extension,
    'expected_bytes',intent.expected_bytes,'declared_sha256',encode(intent.request_hash,'hex'),
    'expires_at',intent.expires_at,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_download_open(p_workspace uuid,p_asset uuid,p_purpose text,
  p_expires_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  asset private_isg.workspace_file_assets; token text; intent private_isg.workspace_download_intents;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_storage',false);
  SELECT * INTO asset FROM private_isg.workspace_file_assets
    WHERE id=p_asset AND workspace_id=p_workspace AND lifecycle='active';
  IF asset.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF asset.company_id IS NULL THEN member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  ELSE member:=private_isg.workspace_require_company(p_workspace,asset.company_id,false); END IF;
  IF p_expires_at IS NULL OR p_expires_at<=clock_timestamp() OR
     p_expires_at>clock_timestamp()+interval '5 minutes' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  token:=private_isg.workspace_random_token();
  INSERT INTO private_isg.workspace_download_intents(workspace_id,asset_id,membership_id,actor_user_id,
    token_hash,purpose,expires_at) VALUES(p_workspace,p_asset,member.id,actor,
      sha256(convert_to(token,'UTF8')),private_isg.workspace_text(p_purpose,80),p_expires_at) RETURNING * INTO intent;
  RETURN jsonb_build_object('schema_version',1,'download_id',intent.id,'workspace_id',p_workspace,
    'expires_at',intent.expires_at,'download_token',token);
END $$;

CREATE FUNCTION private_isg.workspace_download_claim(p_token text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE clean_token text; intent private_isg.workspace_download_intents;
  asset private_isg.workspace_file_assets; member private_isg.workspace_memberships;
BEGIN
  clean_token:=private_isg.workspace_text(p_token,128);
  IF clean_token !~ '^[0-9a-f]{64}$' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent FROM private_isg.workspace_download_intents
    WHERE token_hash=sha256(convert_to(clean_token,'UTF8')) FOR UPDATE;
  IF intent.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DOWNLOAD_TOKEN_INVALID'; END IF;
  IF intent.status NOT IN ('issued','claimed') OR intent.expires_at<=p_now THEN
    UPDATE private_isg.workspace_download_intents SET status='expired'
      WHERE id=intent.id AND status IN ('issued','claimed');
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DOWNLOAD_TOKEN_EXPIRED'; END IF;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=intent.workspace_id AND id=intent.membership_id FOR SHARE;
  SELECT * INTO asset FROM private_isg.workspace_file_assets
    WHERE id=intent.asset_id AND workspace_id=intent.workspace_id FOR SHARE;
  IF member.id IS NULL OR member.status<>'active' OR asset.id IS NULL OR asset.lifecycle<>'active' THEN
    UPDATE private_isg.workspace_download_intents SET status='revoked' WHERE id=intent.id;
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF member.role='expert' AND asset.company_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM private_isg.company_assignments a WHERE a.workspace_id=intent.workspace_id
      AND a.company_id=asset.company_id AND a.membership_id=member.id AND a.starts_at<=p_now
      AND (a.ends_at IS NULL OR a.ends_at>p_now)) THEN
    UPDATE private_isg.workspace_download_intents SET status='revoked' WHERE id=intent.id;
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  UPDATE private_isg.workspace_download_intents SET status='claimed',claimed_at=coalesce(claimed_at,p_now)
    WHERE id=intent.id;
  RETURN jsonb_build_object('download_id',intent.id,'workspace_id',intent.workspace_id,'asset_id',asset.id,
    'bucket',asset.bucket,'object_path',asset.object_path,'object_version',asset.object_version,
    'byte_size',asset.byte_size,'sha256',encode(asset.sha256,'hex'));
END $$;

CREATE FUNCTION private_isg.workspace_download_delivered(p_download uuid,p_object_version text,p_bytes bigint,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE intent private_isg.workspace_download_intents; asset private_isg.workspace_file_assets;
BEGIN
  SELECT * INTO intent FROM private_isg.workspace_download_intents WHERE id=p_download FOR UPDATE;
  SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=intent.asset_id;
  IF intent.id IS NULL OR intent.status<>'claimed' OR asset.object_version<>p_object_version OR
     p_bytes<>asset.byte_size OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DELIVERY_EVIDENCE_CONFLICT'; END IF;
  UPDATE private_isg.workspace_download_intents SET status='delivered',delivered_at=p_now,
    delivered_bytes=p_bytes WHERE id=intent.id;
  RETURN jsonb_build_object('download_id',intent.id,'status','delivered','delivered_bytes',p_bytes);
END $$;

CREATE FUNCTION private_isg.workspace_asset_delete_request(p_workspace uuid,p_asset uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  asset private_isg.workspace_file_assets; deletion private_isg.workspace_asset_deletions;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_storage',true);
  SELECT * INTO asset FROM private_isg.workspace_file_assets
    WHERE id=p_asset AND workspace_id=p_workspace FOR UPDATE;
  IF asset.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF asset.company_id IS NULL THEN member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  ELSE member:=private_isg.workspace_require_company(p_workspace,asset.company_id,true); END IF;
  IF member.role='expert' AND member.id<>asset.uploaded_by_membership_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO deletion FROM private_isg.workspace_asset_deletions WHERE asset_id=p_asset;
  IF FOUND THEN RETURN jsonb_build_object('deletion_id',deletion.id,'state',deletion.state,'replayed',true); END IF;
  IF asset.lifecycle<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_STATE_CONFLICT'; END IF;
  UPDATE private_isg.workspace_file_assets SET lifecycle='delete_requested',delete_requested_at=clock_timestamp()
    WHERE id=asset.id;
  INSERT INTO private_isg.workspace_asset_deletions(workspace_id,asset_id,requested_by_membership_id,reason)
    VALUES(p_workspace,p_asset,member.id,private_isg.workspace_text(p_reason,500)) RETURNING * INTO deletion;
  RETURN jsonb_build_object('deletion_id',deletion.id,'asset_id',p_asset,'state','requested','replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_asset_delete_complete(p_deletion uuid,p_object_version text,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE deletion private_isg.workspace_asset_deletions; asset private_isg.workspace_file_assets;
BEGIN
  SELECT * INTO deletion FROM private_isg.workspace_asset_deletions WHERE id=p_deletion FOR UPDATE;
  IF deletion.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DELETION_NOT_FOUND'; END IF;
  IF deletion.state='deleted' THEN RETURN jsonb_build_object('deletion_id',deletion.id,'state','deleted','replayed',true); END IF;
  SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=deletion.asset_id FOR UPDATE;
  IF asset.lifecycle<>'delete_requested' OR asset.object_version<>p_object_version OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DELETION_EVIDENCE_CONFLICT'; END IF;
  UPDATE private_isg.workspace_file_assets SET lifecycle='deleted',deleted_at=p_now WHERE id=asset.id;
  UPDATE private_isg.workspace_asset_deletions SET state='deleted',object_version_evidence=p_object_version,
    completed_at=p_now WHERE id=deletion.id;
  RETURN jsonb_build_object('deletion_id',deletion.id,'asset_id',asset.id,'state','deleted','replayed',false);
END $$;

CREATE FUNCTION public.isg_workspace_upload_open_v1(p_workspace uuid,p_company uuid,p_idempotency uuid,
  p_request_hash bytea,p_purpose text,p_media_type text,p_extension text,p_expected_bytes bigint,p_expires_at timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_upload_open(
  p_workspace,p_company,p_idempotency,p_request_hash,p_purpose,p_media_type,p_extension,p_expected_bytes,p_expires_at) $$;
CREATE FUNCTION public.isg_workspace_download_open_v1(p_workspace uuid,p_asset uuid,p_purpose text,p_expires_at timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_download_open(
  p_workspace,p_asset,p_purpose,p_expires_at) $$;
CREATE FUNCTION public.isg_workspace_asset_delete_v1(p_workspace uuid,p_asset uuid,p_reason text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_asset_delete_request(
  p_workspace,p_asset,p_reason) $$;
CREATE FUNCTION public.isg_workspace_upload_claim_worker_v1(p_token text,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_upload_claim(p_token,p_now) $$;
CREATE FUNCTION public.isg_workspace_upload_finalize_worker_v1(p_token text,p_object_version text,
  p_actual_bytes bigint,p_sha bytea,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_upload_finalize_via_token(p_token,p_object_version,p_actual_bytes,p_sha,p_now) $$;
CREATE FUNCTION public.isg_workspace_download_claim_worker_v1(p_token text,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_download_claim(p_token,p_now) $$;
CREATE FUNCTION public.isg_workspace_download_delivered_worker_v1(p_download uuid,p_object_version text,
  p_bytes bigint,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_download_delivered(p_download,p_object_version,p_bytes,p_now) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_random_token(),
  private_isg.workspace_storage_upload_allowed(text,text),
  private_isg.workspace_upload_open(uuid,uuid,uuid,bytea,text,text,text,bigint,timestamptz),
  private_isg.workspace_upload_claim(text,timestamptz),
  private_isg.workspace_upload_finalize_via_token(text,text,bigint,bytea,timestamptz),
  private_isg.workspace_download_open(uuid,uuid,text,timestamptz),
  private_isg.workspace_download_claim(text,timestamptz),
  private_isg.workspace_download_delivered(uuid,text,bigint,timestamptz),
  private_isg.workspace_asset_delete_request(uuid,uuid,text),
  private_isg.workspace_asset_delete_complete(uuid,text,timestamptz),
  public.isg_workspace_upload_open_v1(uuid,uuid,uuid,bytea,text,text,text,bigint,timestamptz),
  public.isg_workspace_download_open_v1(uuid,uuid,text,timestamptz),
  public.isg_workspace_asset_delete_v1(uuid,uuid,text),
  public.isg_workspace_upload_claim_worker_v1(text,timestamptz),
  public.isg_workspace_upload_finalize_worker_v1(text,text,bigint,bytea,timestamptz),
  public.isg_workspace_download_claim_worker_v1(text,timestamptz),
  public.isg_workspace_download_delivered_worker_v1(uuid,text,bigint,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_upload_open(uuid,uuid,uuid,bytea,text,text,text,bigint,timestamptz),
  private_isg.workspace_storage_upload_allowed(text,text),
  private_isg.workspace_download_open(uuid,uuid,text,timestamptz),
  private_isg.workspace_asset_delete_request(uuid,uuid,text),
  public.isg_workspace_upload_open_v1(uuid,uuid,uuid,bytea,text,text,text,bigint,timestamptz),
  public.isg_workspace_download_open_v1(uuid,uuid,text,timestamptz),
  public.isg_workspace_asset_delete_v1(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private_isg.workspace_upload_finalize_via_token(text,text,bigint,bytea,timestamptz),
  private_isg.workspace_upload_claim(text,timestamptz),
  private_isg.workspace_download_claim(text,timestamptz),
  private_isg.workspace_download_delivered(uuid,text,bigint,timestamptz),
  private_isg.workspace_asset_delete_complete(uuid,text,timestamptz),
  public.isg_workspace_upload_claim_worker_v1(text,timestamptz),
  public.isg_workspace_upload_finalize_worker_v1(text,text,bigint,bytea,timestamptz),
  public.isg_workspace_download_claim_worker_v1(text,timestamptz),
  public.isg_workspace_download_delivered_worker_v1(uuid,text,bigint,timestamptz) TO service_role;

-- The disposable PostgreSQL acceptance fixture intentionally has no Storage
-- schema. Real Supabase projects receive the private bucket and a single
-- write-only policy when Storage is present.
DO $storage$
BEGIN
  IF to_regclass('storage.buckets') IS NOT NULL AND to_regclass('storage.objects') IS NOT NULL THEN
    EXECUTE $sql$INSERT INTO storage.buckets(id,name,public,file_size_limit)
      VALUES('isg-workspace-private','isg-workspace-private',false,52428800)
      ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=EXCLUDED.file_size_limit$sql$;
    EXECUTE 'DROP POLICY IF EXISTS isg_workspace_private_insert_intent ON storage.objects';
    EXECUTE $sql$CREATE POLICY isg_workspace_private_insert_intent ON storage.objects
      FOR INSERT TO authenticated WITH CHECK (
        private_isg.workspace_storage_upload_allowed(bucket_id,name)
      )$sql$;
  END IF;
END $storage$;
NOTIFY pgrst,'reload schema';
