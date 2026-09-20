-- Service-role worker bridge for OSGB AI, exports, notifications and verified
-- RevenueCat purchase intents. All customer-facing rollout flags stay dark.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='35s';

ALTER TABLE private_isg.workspace_ai_jobs
  ADD COLUMN worker_token uuid,
  ADD COLUMN worker_lease_until timestamptz,
  ADD COLUMN worker_attempt_count integer NOT NULL DEFAULT 0 CHECK(worker_attempt_count BETWEEN 0 AND 20);
CREATE INDEX workspace_ai_worker_lease ON private_isg.workspace_ai_jobs(status,worker_lease_until,created_at,id)
  WHERE status IN ('queued','running');

ALTER TABLE private_isg.workspace_export_jobs
  ADD COLUMN worker_token uuid,
  ADD COLUMN worker_lease_until timestamptz,
  ADD COLUMN worker_attempt_count integer NOT NULL DEFAULT 0 CHECK(worker_attempt_count BETWEEN 0 AND 20);
CREATE INDEX workspace_export_worker_lease ON private_isg.workspace_export_jobs(status,worker_lease_until,created_at,id)
  WHERE status IN ('queued','running');

CREATE FUNCTION private_isg.workspace_worker_ai_claim(p_limit integer,p_now timestamptz,p_lease_seconds integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs; started jsonb; rows jsonb:='[]'; token uuid;
  asset private_isg.workspace_file_assets; provider_hash bytea;
BEGIN
  IF p_limit NOT BETWEEN 1 AND 20 OR p_now IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 600 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR job IN SELECT * FROM private_isg.workspace_ai_jobs j
      WHERE ((j.status='queued' AND j.worker_attempt_count<20) OR
             (j.status='running' AND j.worker_lease_until<=p_now AND j.worker_attempt_count<20))
      ORDER BY j.created_at,j.id FOR UPDATE SKIP LOCKED LIMIT p_limit LOOP
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
    asset:=NULL;
    IF job.source_reference ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
      SELECT * INTO asset FROM private_isg.workspace_file_assets
        WHERE id=job.source_reference::uuid AND workspace_id=job.workspace_id
          AND (job.company_id IS NULL OR company_id=job.company_id) AND lifecycle='active';
    END IF;
    rows:=rows||jsonb_build_array(jsonb_build_object(
      'job_id',job.id,'worker_token',token,'workspace_id',job.workspace_id,'company_id',job.company_id,
      'feature',job.feature,'model_code',job.model_code,'pricing_version',job.pricing_version,
      'reserve_units',(SELECT p.reserve_units FROM private_isg.workspace_ai_pricing p
        WHERE p.feature=job.feature AND p.model_code=job.model_code AND p.pricing_version=job.pricing_version),
      'source_kind',job.source_kind,'source_reference',job.source_reference,'source_version',job.source_version,
      'source_bucket',asset.bucket,'source_path',asset.object_path,'source_media_type',asset.media_type,
      'source_byte_size',asset.byte_size,'attempt_count',job.worker_attempt_count));
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'jobs',rows,'claimed',jsonb_array_length(rows));
END $$;

CREATE FUNCTION private_isg.workspace_worker_ai_complete(p_job uuid,p_token uuid,p_actual_units bigint,
  p_input_units bigint,p_output_units bigint,p_asset uuid,p_bucket text,p_path text,p_object_version text,
  p_bytes bigint,p_sha bytea,p_result jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs; completed jsonb; committed jsonb;
BEGIN
  SELECT * INTO job FROM private_isg.workspace_ai_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL OR job.status<>'running' OR job.worker_token<>p_token OR job.worker_lease_until<p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_CONFLICT'; END IF;
  completed:=private_isg.workspace_ai_complete(p_job,p_actual_units,p_input_units,p_output_units,p_asset,
    p_bucket,p_path,p_object_version,p_bytes,p_sha,p_now);
  committed:=private_isg.workspace_analysis_commit(p_job,p_result);
  UPDATE private_isg.workspace_ai_jobs SET worker_token=NULL,worker_lease_until=NULL,updated_at=clock_timestamp()
    WHERE id=p_job;
  RETURN jsonb_build_object('schema_version',1,'job',completed,'analysis',committed);
END $$;

CREATE FUNCTION private_isg.workspace_worker_ai_fail(p_job uuid,p_token uuid,p_error text,
  p_provider_started boolean,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs; result jsonb;
BEGIN
  SELECT * INTO job FROM private_isg.workspace_ai_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL OR job.status<>'running' OR job.worker_token<>p_token OR job.worker_lease_until<p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_CONFLICT'; END IF;
  result:=private_isg.workspace_ai_fail(p_job,p_error,p_provider_started,p_now);
  UPDATE private_isg.workspace_ai_jobs SET worker_token=NULL,worker_lease_until=NULL,updated_at=clock_timestamp()
    WHERE id=p_job;
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_worker_export_claim(p_limit integer,p_now timestamptz,p_lease_seconds integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_export_jobs; started jsonb; rows jsonb:='[]'; token uuid;
BEGIN
  IF p_limit NOT BETWEEN 1 AND 20 OR p_now IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 600 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR job IN SELECT * FROM private_isg.workspace_export_jobs j
      WHERE ((j.status='queued' AND j.worker_attempt_count<20) OR
             (j.status='running' AND j.worker_lease_until<=p_now AND j.worker_attempt_count<20))
      ORDER BY j.created_at,j.id FOR UPDATE SKIP LOCKED LIMIT p_limit LOOP
    IF job.status='queued' THEN
      started:=private_isg.workspace_export_start(job.id,p_now);
      IF started->>'status'<>'running' THEN CONTINUE; END IF;
    END IF;
    token:=gen_random_uuid();
    UPDATE private_isg.workspace_export_jobs SET worker_token=token,
      worker_lease_until=p_now+make_interval(secs=>p_lease_seconds),
      worker_attempt_count=worker_attempt_count+1,updated_at=clock_timestamp()
      WHERE id=job.id RETURNING * INTO job;
    rows:=rows||jsonb_build_array(jsonb_build_object('job_id',job.id,'worker_token',token,
      'workspace_id',job.workspace_id,'company_id',job.company_id,'analysis_id',job.analysis_id,
      'membership_id',job.membership_id,'format',job.format,'selection',job.selection,
      'source_snapshot',job.source_snapshot,'attempt_count',job.worker_attempt_count));
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'jobs',rows,'claimed',jsonb_array_length(rows));
END $$;

CREATE FUNCTION private_isg.workspace_worker_export_complete(p_job uuid,p_token uuid,p_asset uuid,
  p_bucket text,p_path text,p_object_version text,p_bytes bigint,p_sha bytea,p_media_type text,
  p_extension text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_export_jobs; asset private_isg.workspace_file_assets; result jsonb;
BEGIN
  SELECT * INTO job FROM private_isg.workspace_export_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL OR job.status<>'running' OR job.worker_token<>p_token OR job.worker_lease_until<p_now OR
     p_asset IS NULL OR p_bytes<=0 OR p_sha IS NULL OR octet_length(p_sha)<>32 OR
     p_bucket IS NULL OR p_path IS NULL OR p_object_version IS NULL OR p_media_type IS NULL OR
     p_extension NOT IN ('pdf','xlsx') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_CONFLICT'; END IF;
  INSERT INTO private_isg.workspace_file_assets(id,workspace_id,company_id,uploaded_by_membership_id,
    source_kind,bucket,object_path,object_version,byte_size,sha256,lifecycle,finalized_at,media_type,extension)
  VALUES(p_asset,job.workspace_id,job.company_id,job.membership_id,'generated',p_bucket,p_path,
    p_object_version,p_bytes,p_sha,'active',p_now,p_media_type,p_extension)
  ON CONFLICT(workspace_id,bucket,object_path,object_version) DO NOTHING;
  SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE workspace_id=job.workspace_id
    AND bucket=p_bucket AND object_path=p_path AND object_version=p_object_version;
  IF asset.id IS NULL OR asset.company_id<>job.company_id OR asset.byte_size<>p_bytes OR asset.sha256<>p_sha OR
     asset.lifecycle<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_SCOPE_CONFLICT'; END IF;
  result:=private_isg.workspace_export_complete(p_job,asset.id,p_now);
  UPDATE private_isg.workspace_export_jobs SET worker_token=NULL,worker_lease_until=NULL,updated_at=clock_timestamp()
    WHERE id=p_job;
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_worker_export_fail(p_job uuid,p_token uuid,p_error text,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_export_jobs; result jsonb;
BEGIN
  SELECT * INTO job FROM private_isg.workspace_export_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL OR job.status<>'running' OR job.worker_token<>p_token OR job.worker_lease_until<p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_CONFLICT'; END IF;
  result:=private_isg.workspace_export_fail(p_job,p_error,p_now);
  UPDATE private_isg.workspace_export_jobs SET worker_token=NULL,worker_lease_until=NULL,updated_at=clock_timestamp()
    WHERE id=p_job;
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_purchase_record_revenuecat(p_intent_token text,p_event_id text,
  p_product text,p_app_user uuid,p_transaction text,p_chain text,p_lifecycle text,p_effective_at timestamptz,
  p_valid_until timestamptz,p_sequence bigint,p_payload_hash bytea,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE intent private_isg.workspace_purchase_intents; recorded jsonb; reconciled jsonb;
BEGIN
  SELECT * INTO intent FROM private_isg.workspace_purchase_intents
    WHERE intent_token_hash=sha256(convert_to(private_isg.workspace_text(p_intent_token,128),'UTF8')) FOR UPDATE;
  IF intent.id IS NULL OR intent.provider<>'revenuecat' OR intent.product_id<>p_product OR
     intent.actor_user_id<>p_app_user THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PURCHASE_INTENT_MISMATCH'; END IF;
  recorded:=private_isg.workspace_purchase_record_verified(p_intent_token,p_event_id,p_transaction,p_chain,
    p_lifecycle,p_effective_at,p_valid_until,p_sequence,'webhook','verified',p_payload_hash,'revenuecat',p_now);
  reconciled:=private_isg.workspace_purchase_reconcile(intent.id,p_now);
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'recorded',recorded,'reconciled',reconciled);
END $$;

CREATE FUNCTION public.isg_workspace_worker_ai_claim_v1(p_limit integer,p_now timestamptz,p_lease_seconds integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_worker_ai_claim(p_limit,p_now,p_lease_seconds) $$;
CREATE FUNCTION public.isg_workspace_worker_ai_complete_v1(p_job uuid,p_token uuid,p_actual_units bigint,
  p_input_units bigint,p_output_units bigint,p_asset uuid,p_bucket text,p_path text,p_object_version text,
  p_bytes bigint,p_sha bytea,p_result jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_worker_ai_complete(
  p_job,p_token,p_actual_units,p_input_units,p_output_units,p_asset,p_bucket,p_path,p_object_version,
  p_bytes,p_sha,p_result,p_now) $$;
CREATE FUNCTION public.isg_workspace_worker_ai_fail_v1(p_job uuid,p_token uuid,p_error text,
  p_provider_started boolean,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_worker_ai_fail(p_job,p_token,p_error,p_provider_started,p_now) $$;
CREATE FUNCTION public.isg_workspace_worker_export_claim_v1(p_limit integer,p_now timestamptz,p_lease_seconds integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_worker_export_claim(p_limit,p_now,p_lease_seconds) $$;
CREATE FUNCTION public.isg_workspace_worker_export_complete_v1(p_job uuid,p_token uuid,p_asset uuid,
  p_bucket text,p_path text,p_object_version text,p_bytes bigint,p_sha bytea,p_media_type text,
  p_extension text,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_worker_export_complete(
  p_job,p_token,p_asset,p_bucket,p_path,p_object_version,p_bytes,p_sha,p_media_type,p_extension,p_now) $$;
CREATE FUNCTION public.isg_workspace_worker_export_fail_v1(p_job uuid,p_token uuid,p_error text,p_now timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_worker_export_fail(p_job,p_token,p_error,p_now) $$;
CREATE FUNCTION public.isg_workspace_worker_notification_claim_v1(p_limit integer,p_now timestamptz,p_lease_seconds integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_notification_claim(p_limit,p_now,p_lease_seconds) $$;
CREATE FUNCTION public.isg_workspace_worker_notification_complete_v1(p_job uuid,p_token uuid,p_sent boolean,
  p_error text,p_now timestamptz) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_notification_complete(p_job,p_token,p_sent,p_error,p_now) $$;
CREATE FUNCTION public.isg_workspace_purchase_record_revenuecat_v1(p_intent_token text,p_event_id text,
  p_product text,p_app_user uuid,p_transaction text,p_chain text,p_lifecycle text,p_effective_at timestamptz,
  p_valid_until timestamptz,p_sequence bigint,p_payload_hash bytea,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_purchase_record_revenuecat(
  p_intent_token,p_event_id,p_product,p_app_user,p_transaction,p_chain,p_lifecycle,p_effective_at,
  p_valid_until,p_sequence,p_payload_hash,p_now) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_worker_ai_claim(integer,timestamptz,integer),
  private_isg.workspace_worker_ai_complete(uuid,uuid,bigint,bigint,bigint,uuid,text,text,text,bigint,bytea,jsonb,timestamptz),
  private_isg.workspace_worker_ai_fail(uuid,uuid,text,boolean,timestamptz),
  private_isg.workspace_worker_export_claim(integer,timestamptz,integer),
  private_isg.workspace_worker_export_complete(uuid,uuid,uuid,text,text,text,bigint,bytea,text,text,timestamptz),
  private_isg.workspace_worker_export_fail(uuid,uuid,text,timestamptz),
  private_isg.workspace_purchase_record_revenuecat(text,text,text,uuid,text,text,text,timestamptz,timestamptz,bigint,bytea,timestamptz),
  public.isg_workspace_worker_ai_claim_v1(integer,timestamptz,integer),
  public.isg_workspace_worker_ai_complete_v1(uuid,uuid,bigint,bigint,bigint,uuid,text,text,text,bigint,bytea,jsonb,timestamptz),
  public.isg_workspace_worker_ai_fail_v1(uuid,uuid,text,boolean,timestamptz),
  public.isg_workspace_worker_export_claim_v1(integer,timestamptz,integer),
  public.isg_workspace_worker_export_complete_v1(uuid,uuid,uuid,text,text,text,bigint,bytea,text,text,timestamptz),
  public.isg_workspace_worker_export_fail_v1(uuid,uuid,text,timestamptz),
  public.isg_workspace_worker_notification_claim_v1(integer,timestamptz,integer),
  public.isg_workspace_worker_notification_complete_v1(uuid,uuid,boolean,text,timestamptz),
  public.isg_workspace_purchase_record_revenuecat_v1(text,text,text,uuid,text,text,text,timestamptz,timestamptz,bigint,bytea,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION private_isg.workspace_worker_ai_claim(integer,timestamptz,integer),
  private_isg.workspace_worker_ai_complete(uuid,uuid,bigint,bigint,bigint,uuid,text,text,text,bigint,bytea,jsonb,timestamptz),
  private_isg.workspace_worker_ai_fail(uuid,uuid,text,boolean,timestamptz),
  private_isg.workspace_worker_export_claim(integer,timestamptz,integer),
  private_isg.workspace_worker_export_complete(uuid,uuid,uuid,text,text,text,bigint,bytea,text,text,timestamptz),
  private_isg.workspace_worker_export_fail(uuid,uuid,text,timestamptz),
  private_isg.workspace_purchase_record_revenuecat(text,text,text,uuid,text,text,text,timestamptz,timestamptz,bigint,bytea,timestamptz),
  public.isg_workspace_worker_ai_claim_v1(integer,timestamptz,integer),
  public.isg_workspace_worker_ai_complete_v1(uuid,uuid,bigint,bigint,bigint,uuid,text,text,text,bigint,bytea,jsonb,timestamptz),
  public.isg_workspace_worker_ai_fail_v1(uuid,uuid,text,boolean,timestamptz),
  public.isg_workspace_worker_export_claim_v1(integer,timestamptz,integer),
  public.isg_workspace_worker_export_complete_v1(uuid,uuid,uuid,text,text,text,bigint,bytea,text,text,timestamptz),
  public.isg_workspace_worker_export_fail_v1(uuid,uuid,text,timestamptz),
  public.isg_workspace_worker_notification_claim_v1(integer,timestamptz,integer),
  public.isg_workspace_worker_notification_complete_v1(uuid,uuid,boolean,text,timestamptz),
  public.isg_workspace_purchase_record_revenuecat_v1(text,text,text,uuid,text,text,text,timestamptz,timestamptz,bigint,bytea,timestamptz)
  TO service_role;

NOTIFY pgrst,'reload schema';
