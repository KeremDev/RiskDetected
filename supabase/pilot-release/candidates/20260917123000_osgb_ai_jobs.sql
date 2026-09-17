-- Workspace-pinned AI jobs with authoritative pricing and wallet settlement. NOT DEPLOYED.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';
INSERT INTO private_isg.workspace_rollout(feature) VALUES('workspace_ai');

CREATE TABLE private_isg.workspace_ai_pricing (
  feature text NOT NULL CHECK(octet_length(feature) BETWEEN 1 AND 80),
  model_code text NOT NULL CHECK(octet_length(model_code) BETWEEN 1 AND 80),
  pricing_version text NOT NULL CHECK(octet_length(pricing_version) BETWEEN 1 AND 80),
  reserve_units bigint NOT NULL CHECK(reserve_units>0),
  max_settle_units bigint NOT NULL CHECK(max_settle_units BETWEEN 1 AND 1000000000),
  active boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(feature,model_code,pricing_version),
  CHECK(reserve_units<=max_settle_units)
);

CREATE TABLE private_isg.workspace_ai_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  permission_revision bigint NOT NULL CHECK(permission_revision>=0),
  company_id uuid,
  feature text NOT NULL,
  model_code text NOT NULL,
  pricing_version text NOT NULL,
  reservation_id uuid NOT NULL UNIQUE REFERENCES private_isg.workspace_credit_reservations(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL,
  request_hash bytea NOT NULL CHECK(octet_length(request_hash)=32),
  source_kind text NOT NULL CHECK(source_kind IN ('photo','document','record_set')),
  source_reference text NOT NULL CHECK(octet_length(source_reference) BETWEEN 1 AND 300),
  source_version bigint NOT NULL CHECK(source_version>=0),
  status text NOT NULL CHECK(status IN ('queued','running','succeeded','failed','cancelled','reconcile')),
  provider_started boolean NOT NULL DEFAULT false,
  provider_reference_hash bytea CHECK(provider_reference_hash IS NULL OR octet_length(provider_reference_hash)=32),
  output_asset_id uuid REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT,
  error_code text CHECK(error_code IS NULL OR error_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,idempotency_key),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(feature,model_code,pricing_version)
    REFERENCES private_isg.workspace_ai_pricing(feature,model_code,pricing_version) ON DELETE RESTRICT,
  CHECK((status='running')=(started_at IS NOT NULL) OR status IN ('succeeded','failed','reconcile')),
  CHECK((status IN ('succeeded','failed','cancelled'))=(completed_at IS NOT NULL)),
  CHECK(status<>'succeeded' OR output_asset_id IS NOT NULL),
  CHECK(status NOT IN ('failed','reconcile') OR error_code IS NOT NULL)
);
CREATE INDEX workspace_ai_job_queue ON private_isg.workspace_ai_jobs(status,created_at,id)
  WHERE status IN ('queued','running','reconcile');
CREATE INDEX workspace_ai_job_timeline ON private_isg.workspace_ai_jobs(workspace_id,company_id,created_at,id);

ALTER TABLE private_isg.workspace_ai_pricing ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_ai_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_ai_pricing,private_isg.workspace_ai_jobs
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_ai_submit(p_workspace uuid,p_company uuid,p_feature text,p_model text,
  p_pricing_version text,p_idempotency uuid,p_request_hash bytea,p_source_kind text,
  p_source_reference text,p_source_version bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  pricing private_isg.workspace_ai_pricing; prior private_isg.workspace_ai_jobs;
  reservation jsonb; job private_isg.workspace_ai_jobs;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_ai',true);
  IF p_company IS NULL THEN member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],true);
  ELSE member:=private_isg.workspace_require_company(p_workspace,p_company,true); END IF;
  IF p_idempotency IS NULL OR p_request_hash IS NULL OR octet_length(p_request_hash)<>32 OR
     p_source_kind NOT IN ('photo','document','record_set') OR p_source_reference IS NULL OR
     octet_length(p_source_reference) NOT BETWEEN 1 AND 300 OR p_source_version IS NULL OR p_source_version<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO pricing FROM private_isg.workspace_ai_pricing
    WHERE feature=p_feature AND model_code=p_model AND pricing_version=p_pricing_version AND active FOR SHARE;
  IF pricing.feature IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PRICING_NOT_AVAILABLE'; END IF;
  SELECT * INTO prior FROM private_isg.workspace_ai_jobs
    WHERE workspace_id=p_workspace AND idempotency_key=p_idempotency;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM p_request_hash OR prior.company_id IS DISTINCT FROM p_company OR
       ROW(prior.feature,prior.model_code,prior.pricing_version,prior.source_kind,prior.source_reference,prior.source_version)
       IS DISTINCT FROM ROW(p_feature,p_model,p_pricing_version,p_source_kind,p_source_reference,p_source_version) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'job_id',prior.id,'workspace_id',prior.workspace_id,
      'status',prior.status,'reservation_id',prior.reservation_id,'replayed',true);
  END IF;
  reservation:=private_isg.workspace_credit_reserve(p_workspace,p_company,p_feature,pricing.reserve_units,
    p_idempotency,p_request_hash);
  INSERT INTO private_isg.workspace_ai_jobs(workspace_id,actor_user_id,membership_id,permission_revision,
    company_id,feature,model_code,pricing_version,reservation_id,idempotency_key,request_hash,
    source_kind,source_reference,source_version,status)
    VALUES(p_workspace,actor,member.id,member.permission_revision,p_company,p_feature,p_model,
      p_pricing_version,(reservation->>'reservation_id')::uuid,p_idempotency,p_request_hash,
      p_source_kind,p_source_reference,p_source_version,'queued') RETURNING * INTO job;
  RETURN jsonb_build_object('schema_version',1,'job_id',job.id,'workspace_id',job.workspace_id,
    'status',job.status,'reservation_id',job.reservation_id,'reserved_units',pricing.reserve_units,
    'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_ai_start(p_job uuid,p_provider_reference_hash bytea,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs; member private_isg.workspace_memberships;
BEGIN
  IF p_job IS NULL OR p_now IS NULL OR p_provider_reference_hash IS NULL OR
     octet_length(p_provider_reference_hash)<>32 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.workspace_ai_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_NOT_FOUND'; END IF;
  IF job.status='running' AND job.provider_reference_hash=p_provider_reference_hash THEN
    RETURN jsonb_build_object('job_id',job.id,'status','running','replayed',true); END IF;
  IF job.status<>'queued' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_STATE_CONFLICT'; END IF;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=job.workspace_id AND id=job.membership_id FOR SHARE;
  IF member.id IS NULL OR member.user_id<>job.actor_user_id OR member.status<>'active' OR
     member.permission_revision<>job.permission_revision THEN
    PERFORM private_isg.workspace_credit_release(job.reservation_id);
    UPDATE private_isg.workspace_ai_jobs SET status='failed',error_code='AUTHORITY_REVOKED',
      completed_at=p_now,version=version+1,updated_at=clock_timestamp() WHERE id=job.id;
    RETURN jsonb_build_object('job_id',job.id,'status','failed','error_code','AUTHORITY_REVOKED','provider_started',false);
  END IF;
  IF job.company_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.company_assignments a
    WHERE a.workspace_id=job.workspace_id AND a.company_id=job.company_id AND a.membership_id=job.membership_id
      AND a.starts_at<=p_now AND (a.ends_at IS NULL OR a.ends_at>p_now)) AND member.role='expert' THEN
    PERFORM private_isg.workspace_credit_release(job.reservation_id);
    UPDATE private_isg.workspace_ai_jobs SET status='failed',error_code='ASSIGNMENT_REVOKED',
      completed_at=p_now,version=version+1,updated_at=clock_timestamp() WHERE id=job.id;
    RETURN jsonb_build_object('job_id',job.id,'status','failed','error_code','ASSIGNMENT_REVOKED','provider_started',false);
  END IF;
  UPDATE private_isg.workspace_ai_jobs SET status='running',provider_started=true,
    provider_reference_hash=p_provider_reference_hash,started_at=p_now,version=version+1,
    updated_at=clock_timestamp() WHERE id=job.id;
  RETURN jsonb_build_object('job_id',job.id,'status','running','workspace_id',job.workspace_id,
    'actor_user_id',job.actor_user_id,'company_id',job.company_id,'source_reference',job.source_reference,
    'source_version',job.source_version,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_ai_complete(p_job uuid,p_actual_units bigint,p_input_units bigint,
  p_output_units bigint,p_asset uuid,p_bucket text,p_path text,p_object_version text,p_bytes bigint,
  p_sha bytea,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs; pricing private_isg.workspace_ai_pricing;
  settlement jsonb; asset private_isg.workspace_file_assets; result jsonb;
BEGIN
  IF p_job IS NULL OR p_actual_units<0 OR p_input_units<0 OR p_output_units<0 OR p_asset IS NULL OR
     p_bucket IS NULL OR p_path IS NULL OR p_object_version IS NULL OR p_bytes<=0 OR
     p_sha IS NULL OR octet_length(p_sha)<>32 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.workspace_ai_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_NOT_FOUND'; END IF;
  IF job.status='succeeded' THEN
    RETURN jsonb_build_object('job_id',job.id,'status','succeeded','asset_id',job.output_asset_id,'replayed',true); END IF;
  IF job.status<>'running' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_STATE_CONFLICT'; END IF;
  SELECT * INTO pricing FROM private_isg.workspace_ai_pricing
    WHERE feature=job.feature AND model_code=job.model_code AND pricing_version=job.pricing_version;
  IF p_actual_units>pricing.reserve_units OR p_actual_units>pricing.max_settle_units THEN
    UPDATE private_isg.workspace_ai_jobs SET status='reconcile',error_code='SETTLEMENT_EXCEEDS_RESERVATION',
      version=version+1,updated_at=clock_timestamp() WHERE id=job.id;
    RETURN jsonb_build_object('job_id',job.id,'status','reconcile','error_code','SETTLEMENT_EXCEEDS_RESERVATION','replayed',false);
  END IF;
  INSERT INTO private_isg.workspace_file_assets(id,workspace_id,company_id,uploaded_by_membership_id,
    source_kind,bucket,object_path,object_version,byte_size,sha256,lifecycle,finalized_at)
    VALUES(p_asset,job.workspace_id,job.company_id,job.membership_id,'generated',p_bucket,p_path,
      p_object_version,p_bytes,p_sha,'active',p_now) RETURNING * INTO asset;
  settlement:=private_isg.workspace_credit_settle(job.id,job.reservation_id,p_actual_units,
    p_input_units,p_output_units,job.model_code,job.pricing_version);
  UPDATE private_isg.workspace_ai_jobs SET status='succeeded',output_asset_id=asset.id,
    completed_at=p_now,version=version+1,updated_at=clock_timestamp() WHERE id=job.id RETURNING * INTO job;
  result:=jsonb_build_object('job_id',job.id,'status','succeeded','workspace_id',job.workspace_id,
    'asset_id',asset.id,'settlement',settlement,'replayed',false);
  INSERT INTO private_isg.workspace_outbox(workspace_id,event_type,aggregate_type,aggregate_id,
    aggregate_version,payload,correlation_id) VALUES(job.workspace_id,'workspace.ai_job.succeeded.v1',
      'asset',asset.id,job.version,result,job.id);
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_ai_fail(p_job uuid,p_error text,p_provider_started boolean,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs;
BEGIN
  IF p_job IS NULL OR p_error !~ '^[A-Z][A-Z0-9_]{2,49}$' OR p_provider_started IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.workspace_ai_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_NOT_FOUND'; END IF;
  IF job.status IN ('failed','cancelled') THEN RETURN jsonb_build_object('job_id',job.id,'status',job.status,'replayed',true); END IF;
  IF job.status NOT IN ('queued','running') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_STATE_CONFLICT'; END IF;
  IF p_provider_started OR job.provider_started THEN
    UPDATE private_isg.workspace_ai_jobs SET status='reconcile',error_code=p_error,
      provider_started=true,version=version+1,updated_at=clock_timestamp() WHERE id=job.id;
    RETURN jsonb_build_object('job_id',job.id,'status','reconcile','reservation_status','reserved','replayed',false);
  END IF;
  PERFORM private_isg.workspace_credit_release(job.reservation_id);
  UPDATE private_isg.workspace_ai_jobs SET status='failed',error_code=p_error,completed_at=p_now,
    version=version+1,updated_at=clock_timestamp() WHERE id=job.id;
  RETURN jsonb_build_object('job_id',job.id,'status','failed','reservation_status','released','replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_ai_get(p_workspace uuid,p_job uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_ai_jobs; member private_isg.workspace_memberships;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_ai',false);
  SELECT * INTO job FROM private_isg.workspace_ai_jobs WHERE id=p_job AND workspace_id=p_workspace;
  IF job.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF job.company_id IS NULL THEN member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  ELSE member:=private_isg.workspace_require_company(p_workspace,job.company_id,false); END IF;
  RETURN jsonb_build_object('schema_version',1,'job_id',job.id,'workspace_id',job.workspace_id,
    'company_id',job.company_id,'feature',job.feature,'status',job.status,'source_kind',job.source_kind,
    'source_reference',job.source_reference,'source_version',job.source_version,
    'output_asset_id',job.output_asset_id,'error_code',job.error_code,'version',job.version);
END $$;

CREATE FUNCTION public.isg_workspace_ai_submit_v1(p_workspace uuid,p_company uuid,p_feature text,p_model text,
  p_pricing_version text,p_idempotency uuid,p_request_hash bytea,p_source_kind text,
  p_source_reference text,p_source_version bigint) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_ai_submit(p_workspace,p_company,
  p_feature,p_model,p_pricing_version,p_idempotency,p_request_hash,p_source_kind,p_source_reference,p_source_version) $$;
CREATE FUNCTION public.isg_workspace_ai_get_v1(p_workspace uuid,p_job uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_ai_get(p_workspace,p_job) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_ai_submit(uuid,uuid,text,text,text,uuid,bytea,text,text,bigint),
  private_isg.workspace_ai_start(uuid,bytea,timestamptz),
  private_isg.workspace_ai_complete(uuid,bigint,bigint,bigint,uuid,text,text,text,bigint,bytea,timestamptz),
  private_isg.workspace_ai_fail(uuid,text,boolean,timestamptz),private_isg.workspace_ai_get(uuid,uuid),
  public.isg_workspace_ai_submit_v1(uuid,uuid,text,text,text,uuid,bytea,text,text,bigint),
  public.isg_workspace_ai_get_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_ai_submit(uuid,uuid,text,text,text,uuid,bytea,text,text,bigint),
  private_isg.workspace_ai_get(uuid,uuid),
  public.isg_workspace_ai_submit_v1(uuid,uuid,text,text,text,uuid,bytea,text,text,bigint),
  public.isg_workspace_ai_get_v1(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private_isg.workspace_ai_start(uuid,bytea,timestamptz),
  private_isg.workspace_ai_complete(uuid,bigint,bigint,bigint,uuid,text,text,text,bigint,bytea,timestamptz),
  private_isg.workspace_ai_fail(uuid,text,boolean,timestamptz) TO service_role;
NOTIFY pgrst,'reload schema';
