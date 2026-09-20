-- Product-scoped photo analysis entry point for OSGB workspaces.
-- The client supplies only the selected company and finalized image asset;
-- model and pricing choices remain server-owned.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

INSERT INTO private_isg.workspace_ai_pricing(
  feature,model_code,pricing_version,reserve_units,max_settle_units,active
) VALUES('photo_analysis','gemini-2.5-flash','osgb-photo-v1',20,20,true)
ON CONFLICT(feature,model_code,pricing_version) DO UPDATE SET
  reserve_units=EXCLUDED.reserve_units,
  max_settle_units=EXCLUDED.max_settle_units,
  active=true;

-- The file-domain migration added media_type/extension to finalized assets,
-- but the original finalizer still inserted only the older column set. Keep
-- all future workspace uploads complete and repair already-finalized rows from
-- their immutable upload intent before an AI job can claim them.
UPDATE private_isg.workspace_file_assets asset
  SET media_type=intent.media_type,extension=intent.extension
  FROM private_isg.workspace_upload_intents intent
  WHERE intent.asset_id=asset.id AND intent.status='finalized'
    AND (asset.media_type IS NULL OR asset.extension IS NULL);

CREATE OR REPLACE FUNCTION private_isg.workspace_upload_finalize_via_token(
  p_token text,p_object_version text,p_actual_bytes bigint,p_sha bytea,p_now timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  clean_token text;
  intent private_isg.workspace_upload_intents;
  asset private_isg.workspace_file_assets;
  member private_isg.workspace_memberships;
BEGIN
  clean_token:=private_isg.workspace_text(p_token,128);
  IF clean_token !~ '^[0-9a-f]{64}$' OR p_object_version IS NULL OR
     octet_length(p_object_version) NOT BETWEEN 1 AND 200 OR p_actual_bytes<=0 OR
     p_sha IS NULL OR octet_length(p_sha)<>32 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  SELECT * INTO intent FROM private_isg.workspace_upload_intents
    WHERE token_hash=sha256(convert_to(clean_token,'UTF8')) FOR UPDATE;
  IF intent.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_TOKEN_INVALID';
  END IF;
  IF intent.status='finalized' THEN
    SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=intent.asset_id;
    IF asset.object_version<>p_object_version OR asset.byte_size<>p_actual_bytes OR asset.sha256<>p_sha THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT';
    END IF;
    RETURN jsonb_build_object('schema_version',1,'asset_id',asset.id,'workspace_id',asset.workspace_id,
      'byte_size',asset.byte_size,'sha256',encode(asset.sha256,'hex'),'replayed',true);
  END IF;
  IF intent.status<>'open' OR intent.expires_at<=p_now THEN
    UPDATE private_isg.workspace_upload_intents SET status='expired'
      WHERE id=intent.id AND status='open';
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_TOKEN_EXPIRED';
  END IF;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=intent.workspace_id AND id=intent.membership_id FOR SHARE;
  IF member.id IS NULL OR member.status<>'active' OR member.user_id<>intent.actor_user_id OR
     (member.role='expert' AND intent.company_id IS NOT NULL AND NOT EXISTS(
       SELECT 1 FROM private_isg.company_assignments assignment
       WHERE assignment.workspace_id=intent.workspace_id AND assignment.company_id=intent.company_id
         AND assignment.membership_id=member.id AND assignment.starts_at<=p_now
         AND (assignment.ends_at IS NULL OR assignment.ends_at>p_now))) THEN
    UPDATE private_isg.workspace_upload_intents SET status='cancelled' WHERE id=intent.id;
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  IF p_actual_bytes>intent.expected_bytes THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_SIZE_EXCEEDED';
  END IF;
  INSERT INTO private_isg.workspace_file_assets(
    id,workspace_id,company_id,uploaded_by_membership_id,source_kind,bucket,object_path,
    object_version,byte_size,sha256,lifecycle,finalized_at,media_type,extension
  ) VALUES(
    intent.id,intent.workspace_id,intent.company_id,intent.membership_id,'upload',intent.bucket,
    intent.object_path,p_object_version,p_actual_bytes,p_sha,'active',p_now,intent.media_type,intent.extension
  ) RETURNING * INTO asset;
  UPDATE private_isg.workspace_upload_intents
    SET status='finalized',asset_id=asset.id,finalized_at=p_now WHERE id=intent.id;
  RETURN jsonb_build_object('schema_version',1,'asset_id',asset.id,'workspace_id',asset.workspace_id,
    'byte_size',asset.byte_size,'sha256',encode(asset.sha256,'hex'),'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_photo_analysis_submit(
  p_workspace uuid,p_company uuid,p_idempotency uuid,p_source_asset uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  asset private_isg.workspace_file_assets;
  result jsonb;
BEGIN
  IF p_workspace IS NULL OR p_company IS NULL OR p_idempotency IS NULL OR p_source_asset IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;

  -- Check company authority before touching the private asset table so this
  -- wrapper cannot be used as an asset-existence oracle.
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  SELECT * INTO asset
    FROM private_isg.workspace_file_assets
    WHERE id=p_source_asset AND workspace_id=p_workspace AND company_id=p_company
      AND lifecycle='active' AND media_type LIKE 'image/%';
  IF asset.id IS NULL OR asset.sha256 IS NULL OR octet_length(asset.sha256)<>32 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SOURCE_NOT_FOUND';
  END IF;

  result:=private_isg.workspace_ai_submit(
    p_workspace,p_company,'photo_analysis','gemini-2.5-flash','osgb-photo-v1',
    p_idempotency,asset.sha256,'photo',asset.id::text,1
  );
  RETURN result||jsonb_build_object('company_id',p_company,'source_asset_id',asset.id);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_photo_analysis_get(
  p_workspace uuid,p_job uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  result jsonb;
  analysis_id uuid;
BEGIN
  result:=private_isg.workspace_ai_get(p_workspace,p_job);
  IF result->>'feature'<>'photo_analysis' OR result->>'source_kind'<>'photo' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  SELECT a.id INTO analysis_id
    FROM private_isg.workspace_analyses a
    WHERE a.workspace_id=p_workspace AND a.ai_job_id=p_job;
  RETURN result||jsonb_build_object('analysis_id',analysis_id);
END $$;

CREATE OR REPLACE FUNCTION public.isg_workspace_photo_analysis_submit_v1(
  p_workspace uuid,p_company uuid,p_idempotency uuid,p_source_asset uuid
) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_photo_analysis_submit(
    p_workspace,p_company,p_idempotency,p_source_asset
  )
$$;

CREATE OR REPLACE FUNCTION public.isg_workspace_photo_analysis_get_v1(
  p_workspace uuid,p_job uuid
) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_photo_analysis_get(p_workspace,p_job)
$$;

REVOKE ALL ON FUNCTION
  private_isg.workspace_photo_analysis_submit(uuid,uuid,uuid,uuid),
  private_isg.workspace_photo_analysis_get(uuid,uuid),
  public.isg_workspace_photo_analysis_submit_v1(uuid,uuid,uuid,uuid),
  public.isg_workspace_photo_analysis_get_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  private_isg.workspace_photo_analysis_submit(uuid,uuid,uuid,uuid),
  private_isg.workspace_photo_analysis_get(uuid,uuid),
  public.isg_workspace_photo_analysis_submit_v1(uuid,uuid,uuid,uuid),
  public.isg_workspace_photo_analysis_get_v1(uuid,uuid)
  TO authenticated;

NOTIFY pgrst,'reload schema';
