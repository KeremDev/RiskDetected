-- Reject missing photo/document inputs before an AI provider call starts.
-- This releases the reservation instead of sending a never-started job to
-- reconciliation. Record-set jobs intentionally have no file asset.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE OR REPLACE FUNCTION private_isg.workspace_worker_ai_claim(
  p_limit integer,p_now timestamptz,p_lease_seconds integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs; started jsonb; rows jsonb:='[]'; token uuid;
  asset private_isg.workspace_file_assets; provider_hash bytea;
BEGIN
  IF p_limit NOT BETWEEN 1 AND 20 OR p_now IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 600 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR job IN SELECT * FROM private_isg.workspace_ai_jobs j
      WHERE ((j.status='queued' AND j.worker_attempt_count<20) OR
             (j.status='running' AND j.worker_lease_until<=p_now AND j.worker_attempt_count<20))
      ORDER BY j.created_at,j.id FOR UPDATE SKIP LOCKED LIMIT p_limit LOOP
    asset:=NULL;
    IF job.source_kind IN ('photo','document') THEN
      IF job.source_reference ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
        SELECT * INTO asset FROM private_isg.workspace_file_assets
          WHERE id=job.source_reference::uuid AND workspace_id=job.workspace_id
            AND (job.company_id IS NULL OR company_id=job.company_id) AND lifecycle='active';
      END IF;
      IF asset.id IS NULL THEN
        IF job.status='queued' THEN
          PERFORM private_isg.workspace_ai_fail(job.id,'SOURCE_NOT_FOUND',false,p_now);
        ELSE
          PERFORM private_isg.workspace_ai_fail(job.id,'SOURCE_NOT_FOUND',true,p_now);
        END IF;
        CONTINUE;
      END IF;
    END IF;
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

REVOKE ALL ON FUNCTION private_isg.workspace_worker_ai_claim(integer,timestamptz,integer)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private_isg.workspace_worker_ai_claim(integer,timestamptz,integer)
  TO service_role;

NOTIFY pgrst,'reload schema';
