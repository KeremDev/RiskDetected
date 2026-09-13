-- P16/D16 first slice: a technical event envelope that cannot carry a secret or
-- a person's content, a pre-submit funnel that starts before any analysis row
-- exists, and admin operations that need MFA, a scope, a simulation and a
-- written audit entry before anything is published.
-- Additive; rollout OFF; no client grant. Telemetry is non-blocking by
-- construction: nothing here is read or written by a domain mutation.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports','notifications','personal_notes','billing_lifecycle',
    'campaigns','observability'));
INSERT INTO private_isg.rollout(feature) VALUES('observability');

-- The ten stages of the diagnosis chain, as rows, in their real order.
CREATE TABLE private_isg.funnel_stages (
  stage text PRIMARY KEY,
  stage_no integer NOT NULL UNIQUE CHECK(stage_no BETWEEN 1 AND 50),
  before_analysis_row boolean NOT NULL,
  note text NOT NULL
);
INSERT INTO private_isg.funnel_stages(stage,stage_no,before_analysis_row,note) VALUES
  ('screen_open',1,true,'the screen was opened'),
  ('photo_pick',2,true,'a photo was chosen'),
  ('encode',3,true,'the client encoded the image'),
  ('upload_intent',4,true,'an upload intent was asked for'),
  ('upload',5,true,'the bytes were uploaded'),
  ('submit',6,true,'the analysis was submitted'),
  ('job_queued',7,false,'the server queued the job'),
  ('provider',8,false,'the provider was called'),
  ('result',9,false,'a result came back'),
  ('ui_render',10,false,'the user actually saw the result');
-- A typed allowlist per stage. A key that is not named here cannot be stored.
CREATE TABLE private_isg.telemetry_event_kinds (
  stage text PRIMARY KEY REFERENCES private_isg.funnel_stages(stage),
  allowed_keys text[] NOT NULL CHECK(array_length(allowed_keys,1) BETWEEN 1 AND 20),
  created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO private_isg.telemetry_event_kinds(stage,allowed_keys) VALUES
  ('screen_open',ARRAY['entry_point','cold_start']),
  ('photo_pick',ARRAY['source_kind','picked_count']),
  ('encode',ARRAY['input_bytes','output_bytes','encoder_version']),
  ('upload_intent',ARRAY['purpose','expected_bytes']),
  ('upload',ARRAY['bytes_sent','attempt_no','transport']),
  ('submit',ARRAY['payload_bytes','idempotent']),
  ('job_queued',ARRAY['queue_name','position_bucket']),
  ('provider',ARRAY['provider_name','model_family','timeout_ms']),
  ('result',ARRAY['result_kind','parts_count']),
  ('ui_render',ARRAY['render_ms_bucket','screen_name']);
-- The chain is opened by the client before any analysis row can exist, so a
-- failure that never reaches the server is still fully diagnosable.
CREATE TABLE private_isg.support_chains (
  support_id text PRIMARY KEY CHECK(support_id ~ '^[A-Z0-9]{8,24}$'),
  owner_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  environment text NOT NULL CHECK(environment IN ('development','staging','production')),
  app_build text NOT NULL CHECK(app_build ~ '^[A-Za-z0-9][A-Za-z0-9._+-]{1,63}$'),
  platform text NOT NULL CHECK(platform IN ('ios','android')),
  trace_id uuid NOT NULL,
  started_at timestamptz NOT NULL,
  last_stage text REFERENCES private_isg.funnel_stages(stage),
  analysis_row_created boolean NOT NULL DEFAULT false,
  outcome text CHECK(outcome IN ('rendered','failed_before_submit','failed_after_submit','abandoned')),
  closed_at timestamptz,
  -- A result that was never rendered is not a successful user outcome.
  CHECK(outcome<>'rendered' OR last_stage='ui_render'),
  CHECK(outcome<>'failed_before_submit' OR NOT analysis_row_created),
  CHECK((outcome IS NULL)=(closed_at IS NULL))
);
CREATE INDEX support_chain_owner_idx ON private_isg.support_chains(owner_id);
CREATE INDEX support_chain_stage_idx ON private_isg.support_chains(last_stage);
-- The envelope. There is no column for an address, a token, a signature, a
-- signed URL, a note body, an employee document or a photo, so none of them
-- can be logged even by mistake.
CREATE TABLE private_isg.technical_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  support_id text NOT NULL REFERENCES private_isg.support_chains(support_id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  operation_id uuid,
  trace_id uuid NOT NULL,
  stage text NOT NULL REFERENCES private_isg.funnel_stages(stage),
  outcome text NOT NULL CHECK(outcome IN ('started','ok','failed','abandoned')),
  reason_code text CHECK(reason_code IS NULL OR reason_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  retry_count integer NOT NULL DEFAULT 0 CHECK(retry_count BETWEEN 0 AND 1000),
  latency_ms integer CHECK(latency_ms IS NULL OR latency_ms BETWEEN 0 AND 3600000),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(metadata)='object' AND octet_length(metadata::text)<=2048),
  carries_user_content boolean NOT NULL DEFAULT false CHECK(NOT carries_user_content),
  recorded_at timestamptz NOT NULL,
  UNIQUE(support_id,stage,request_id),
  CHECK(outcome<>'failed' OR reason_code IS NOT NULL)
);
CREATE INDEX technical_event_chain_idx ON private_isg.technical_events(support_id,recorded_at);
CREATE INDEX technical_event_stage_idx ON private_isg.technical_events(stage,outcome);
-- The client queue is bounded. Losing telemetry is recorded, never escalated:
-- a dropped event must not change what the user's own operation did.
CREATE TABLE private_isg.telemetry_queue_reports (
  report_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  installation_id uuid NOT NULL,
  capacity integer NOT NULL CHECK(capacity BETWEEN 1 AND 100000),
  dropped_count bigint NOT NULL CHECK(dropped_count>=0),
  oldest_dropped_at timestamptz,
  transport_available boolean NOT NULL,
  blocks_domain boolean NOT NULL DEFAULT false CHECK(NOT blocks_domain),
  reported_at timestamptz NOT NULL
);
CREATE INDEX telemetry_queue_owner_idx ON private_isg.telemetry_queue_reports(owner_id);
-- Without an explicit tracking authorisation there is no attribution to claim
-- and no identifier to store.
CREATE TABLE private_isg.attribution_records (
  attribution_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tracking_authorized boolean NOT NULL,
  attribution_source text NOT NULL CHECK(attribution_source IN ('unknown','self_reported','store_provided')),
  identifier_stored boolean NOT NULL DEFAULT false CHECK(NOT identifier_stored),
  third_party_sdk_called boolean NOT NULL DEFAULT false CHECK(NOT third_party_sdk_called),
  recorded_at timestamptz NOT NULL,
  UNIQUE(owner_id),
  CHECK(tracking_authorized OR attribution_source='unknown')
);
CREATE TABLE private_isg.admin_scopes (
  scope_key text PRIMARY KEY CHECK(scope_key ~ '^[a-z][a-z0-9_.]{2,49}$'),
  requires_aal2 boolean NOT NULL DEFAULT true CHECK(requires_aal2),
  note text NOT NULL
);
INSERT INTO private_isg.admin_scopes(scope_key,note) VALUES
  ('billing.read','read the lifecycle and settlement ledgers'),
  ('billing.publish','change a billing or campaign switch'),
  ('campaign.read','read campaign budgets, episodes and suppressions'),
  ('campaign.publish','publish, pause or budget a campaign version'),
  ('telemetry.read','read technical events and support chains'),
  ('export.masked','export a masked, allowlisted projection');
-- A session carries its own assurance level and its own scopes; the server
-- never trusts a scope claimed by the client.
CREATE TABLE private_isg.admin_sessions (
  session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id uuid NOT NULL,
  assurance_level text NOT NULL CHECK(assurance_level IN ('aal1','aal2')),
  granted_scopes text[] NOT NULL CHECK(array_length(granted_scopes,1) BETWEEN 1 AND 20),
  opened_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK(expires_at>opened_at)
);
CREATE INDEX admin_session_user_idx ON private_isg.admin_sessions(admin_user_id);
-- Immutable audit. It is written before the publish, not after it.
CREATE TABLE private_isg.admin_audit_entries (
  audit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES private_isg.admin_sessions(session_id),
  admin_user_id uuid NOT NULL,
  action_kind text NOT NULL,
  scope_key text NOT NULL REFERENCES private_isg.admin_scopes(scope_key),
  target_ref text NOT NULL CHECK(length(target_ref) BETWEEN 1 AND 200),
  payload_digest bytea NOT NULL,
  carries_raw_payload boolean NOT NULL DEFAULT false CHECK(NOT carries_raw_payload),
  written_at timestamptz NOT NULL
);
CREATE INDEX admin_audit_session_idx ON private_isg.admin_audit_entries(session_id);
CREATE INDEX admin_audit_scope_idx ON private_isg.admin_audit_entries(scope_key);
-- Simulate first, then publish. A publish without a simulation or without its
-- audit entry has no row shape at all.
CREATE TABLE private_isg.admin_actions (
  action_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES private_isg.admin_sessions(session_id),
  action_kind text NOT NULL CHECK(action_kind IN ('campaign_pause','campaign_publish','budget_change',
    'rollout_switch','benefit_review','export_request')),
  scope_key text NOT NULL REFERENCES private_isg.admin_scopes(scope_key),
  target_ref text NOT NULL CHECK(length(target_ref) BETWEEN 1 AND 200),
  state text NOT NULL DEFAULT 'simulated' CHECK(state IN ('simulated','published','refused')),
  simulated_at timestamptz,
  published_at timestamptz,
  refused_code text CHECK(refused_code IS NULL OR refused_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  audit_id uuid REFERENCES private_isg.admin_audit_entries(audit_id),
  simulation_report jsonb NOT NULL,
  CHECK(state<>'published' OR (simulated_at IS NOT NULL AND published_at IS NOT NULL AND audit_id IS NOT NULL)),
  CHECK(state<>'refused' OR refused_code IS NOT NULL),
  CHECK(state<>'simulated' OR simulated_at IS NOT NULL)
);
CREATE INDEX admin_action_session_idx ON private_isg.admin_actions(session_id);
CREATE INDEX admin_action_scope_idx ON private_isg.admin_actions(scope_key);
CREATE INDEX admin_action_audit_idx ON private_isg.admin_actions(audit_id);
-- An export is a masked, allowlisted projection. Raw personal data has no flag
-- to set and no column to travel in.
CREATE TABLE private_isg.admin_exports (
  export_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action_id uuid NOT NULL UNIQUE REFERENCES private_isg.admin_actions(action_id) ON DELETE CASCADE,
  dataset text NOT NULL CHECK(dataset IN ('billing_settlements','campaign_suppressions','support_chains')),
  requested_columns text[] NOT NULL CHECK(array_length(requested_columns,1) BETWEEN 1 AND 20),
  masked_columns text[] NOT NULL,
  row_count bigint NOT NULL CHECK(row_count>=0),
  raw_pii_included boolean NOT NULL DEFAULT false CHECK(NOT raw_pii_included),
  created_at timestamptz NOT NULL
);
-- One switch for admin writes. Pausing them never pauses the audit trail, the
-- billing settlement chain or anything a user already earned.
CREATE TABLE private_isg.admin_operation_state (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  writes_paused boolean NOT NULL DEFAULT false,
  pause_reason text CHECK(pause_reason IS NULL OR length(pause_reason) BETWEEN 3 AND 200),
  changed_at timestamptz NOT NULL DEFAULT now(),
  audit_continues boolean NOT NULL DEFAULT true CHECK(audit_continues),
  settlement_continues boolean NOT NULL DEFAULT true CHECK(settlement_continues),
  CHECK(NOT writes_paused OR pause_reason IS NOT NULL)
);
INSERT INTO private_isg.admin_operation_state(singleton) VALUES(true);
CREATE TABLE private_isg.funnel_progress (
  progress_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  support_id text NOT NULL REFERENCES private_isg.support_chains(support_id) ON DELETE CASCADE,
  stage text NOT NULL REFERENCES private_isg.funnel_stages(stage),
  stage_no integer NOT NULL,
  outcome text NOT NULL CHECK(outcome IN ('started','ok','failed','abandoned')),
  reason_code text CHECK(reason_code IS NULL OR reason_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  reached_at timestamptz NOT NULL,
  UNIQUE(support_id,stage)
);
CREATE INDEX funnel_progress_stage_idx ON private_isg.funnel_progress(stage,outcome);

ALTER TABLE private_isg.funnel_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.telemetry_event_kinds ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.support_chains ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.technical_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.telemetry_queue_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.attribution_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.admin_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.admin_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.admin_audit_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.admin_exports ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.admin_operation_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.funnel_progress ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.observability_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='observability' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- Returns the first key whose value looks like something that must never be
-- logged: an address, a bearer token, a JWT, a signed URL or a body of text.
CREATE FUNCTION private_isg.telemetry_redaction_violation(p_metadata jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE offending text;
BEGIN
  IF p_metadata IS NULL OR jsonb_typeof(p_metadata)<>'object' THEN RETURN 'metadata'; END IF;
  SELECT key INTO offending FROM jsonb_each_text(p_metadata) AS pair(key,value)
    WHERE length(value)>200
       OR value ~ '[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,10}'
       OR value ~ '^ey[[:alnum:]_-]{10,200}[.]'
       OR value ~* 'bearer[[:space:]]'
       OR value ~* 'https?://[^[:space:]]*[?&](x-amz-signature|signature|token|sig)='
    ORDER BY key LIMIT 1;
  RETURN offending;
END $$;
-- The chain is opened by the client, before the server knows anything.
CREATE FUNCTION private_isg.start_support_chain(p_support text,p_owner uuid,p_environment text,p_build text,
  p_platform text,p_trace uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prior private_isg.support_chains;
BEGIN
  PERFORM private_isg.observability_gate(true);
  IF p_support IS NULL OR p_environment IS NULL OR p_build IS NULL OR p_platform IS NULL OR p_trace IS NULL OR
     p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO prior FROM private_isg.support_chains WHERE support_id=p_support;
  IF FOUND THEN
    RETURN jsonb_build_object('schema_version',1,'support_id',p_support,'replayed',true,
      'started_without_analysis',NOT prior.analysis_row_created); END IF;
  INSERT INTO private_isg.support_chains(support_id,owner_id,environment,app_build,platform,trace_id,started_at)
    VALUES(p_support,p_owner,p_environment,p_build,p_platform,p_trace,p_now);
  RETURN jsonb_build_object('schema_version',1,'support_id',p_support,'replayed',false,
    'started_without_analysis',true,'blocks_domain',false);
END $$;
-- Every key must be named in this stage's allowlist, and no value may look
-- like a secret or a person's content. Both are refused before any write.
CREATE FUNCTION private_isg.record_technical_event(p_support text,p_stage text,p_outcome text,p_reason text,
  p_request uuid,p_operation uuid,p_retry integer,p_latency integer,p_metadata jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE chain private_isg.support_chains; this_no integer; last_no integer; allowed text[]; offending text; created uuid;
BEGIN
  PERFORM private_isg.observability_gate(true);
  IF p_support IS NULL OR p_stage IS NULL OR p_outcome IS NULL OR p_request IS NULL OR p_now IS NULL OR
     p_retry IS NULL OR p_retry<0 OR p_metadata IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO chain FROM private_isg.support_chains WHERE support_id=p_support FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF chain.closed_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHAIN_CLOSED'; END IF;
  SELECT stage_no INTO this_no FROM private_isg.funnel_stages WHERE stage=p_stage;
  IF this_no IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT stage_no INTO last_no FROM private_isg.funnel_stages WHERE stage=chain.last_stage;
  IF last_no IS NOT NULL AND this_no<last_no THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='STAGE_OUT_OF_ORDER'; END IF;
  SELECT allowed_keys INTO allowed FROM private_isg.telemetry_event_kinds WHERE stage=p_stage;
  SELECT key INTO offending FROM jsonb_object_keys(p_metadata) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='METADATA_NOT_ALLOWED'; END IF;
  offending:=private_isg.telemetry_redaction_violation(p_metadata);
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='REDACTION_VIOLATION'; END IF;
  INSERT INTO private_isg.technical_events(support_id,request_id,operation_id,trace_id,stage,outcome,reason_code,
      retry_count,latency_ms,metadata,recorded_at)
    VALUES(p_support,p_request,p_operation,chain.trace_id,p_stage,p_outcome,p_reason,p_retry,p_latency,p_metadata,p_now)
    RETURNING event_id INTO created;
  INSERT INTO private_isg.funnel_progress(support_id,stage,stage_no,outcome,reason_code,reached_at)
    VALUES(p_support,p_stage,this_no,p_outcome,p_reason,p_now)
    ON CONFLICT(support_id,stage) DO UPDATE SET outcome=EXCLUDED.outcome,reason_code=EXCLUDED.reason_code,
      reached_at=EXCLUDED.reached_at;
  UPDATE private_isg.support_chains SET last_stage=p_stage,
    analysis_row_created=chain.analysis_row_created OR (p_stage='job_queued' AND p_outcome='ok')
    WHERE support_id=p_support;
  RETURN jsonb_build_object('schema_version',1,'event_id',created,'stage',p_stage,'stage_no',this_no,
    'analysis_row_created',chain.analysis_row_created OR (p_stage='job_queued' AND p_outcome='ok'),
    'carries_user_content',false,'blocks_domain',false);
END $$;
CREATE FUNCTION private_isg.close_support_chain(p_support text,p_outcome text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE chain private_isg.support_chains;
BEGIN
  PERFORM private_isg.observability_gate(true);
  IF p_support IS NULL OR p_outcome IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO chain FROM private_isg.support_chains WHERE support_id=p_support FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF chain.closed_at IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'support_id',p_support,'outcome',chain.outcome,'replayed',true); END IF;
  -- Only a rendered result counts as the user having seen anything.
  IF p_outcome='rendered' AND chain.last_stage IS DISTINCT FROM 'ui_render' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_outcome='failed_before_submit' AND chain.analysis_row_created THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.support_chains SET outcome=p_outcome,closed_at=p_now WHERE support_id=p_support;
  RETURN jsonb_build_object('schema_version',1,'support_id',p_support,'outcome',p_outcome,'replayed',false,
    'analysis_row_created',chain.analysis_row_created,
    'successful_user_outcome',p_outcome='rendered');
END $$;
-- A full or unavailable queue is reported, never escalated into a failure.
CREATE FUNCTION private_isg.record_queue_report(p_owner uuid,p_installation uuid,p_capacity integer,p_dropped bigint,
  p_oldest timestamptz,p_transport boolean,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE created uuid;
BEGIN
  PERFORM private_isg.observability_gate(true);
  IF p_installation IS NULL OR p_capacity IS NULL OR p_dropped IS NULL OR p_dropped<0 OR p_transport IS NULL OR
     p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.telemetry_queue_reports(owner_id,installation_id,capacity,dropped_count,oldest_dropped_at,
      transport_available,reported_at)
    VALUES(p_owner,p_installation,p_capacity,p_dropped,p_oldest,p_transport,p_now) RETURNING report_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'report_id',created,'dropped_count',p_dropped,
    'blocks_domain',false,'domain_operation_affected',false);
END $$;
CREATE FUNCTION private_isg.record_attribution(p_owner uuid,p_authorized boolean,p_source text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE resolved text;
BEGIN
  PERFORM private_isg.observability_gate(true);
  IF p_owner IS NULL OR p_authorized IS NULL OR p_source IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- No authorisation, no attribution claim: the answer is 'unknown', not a guess.
  resolved:=CASE WHEN p_authorized THEN p_source ELSE 'unknown' END;
  INSERT INTO private_isg.attribution_records(owner_id,tracking_authorized,attribution_source,recorded_at)
    VALUES(p_owner,p_authorized,resolved,p_now)
    ON CONFLICT(owner_id) DO UPDATE SET tracking_authorized=EXCLUDED.tracking_authorized,
      attribution_source=EXCLUDED.attribution_source,recorded_at=EXCLUDED.recorded_at;
  RETURN jsonb_build_object('schema_version',1,'tracking_authorized',p_authorized,'attribution_source',resolved,
    'identifier_stored',false,'third_party_sdk_called',false);
END $$;
CREATE FUNCTION private_isg.open_admin_session(p_admin uuid,p_aal text,p_scopes text[],p_expires timestamptz,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE unknown_scope text; created uuid;
BEGIN
  PERFORM private_isg.observability_gate(true);
  IF p_admin IS NULL OR p_aal IS NULL OR p_scopes IS NULL OR p_expires IS NULL OR p_now IS NULL OR
     p_expires<=p_now THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO unknown_scope FROM unnest(p_scopes) AS keys(key)
    WHERE NOT EXISTS(SELECT 1 FROM private_isg.admin_scopes WHERE scope_key=keys.key) LIMIT 1;
  IF unknown_scope IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.admin_sessions(admin_user_id,assurance_level,granted_scopes,opened_at,expires_at)
    VALUES(p_admin,p_aal,p_scopes,p_now,p_expires) RETURNING session_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'session_id',created,'assurance_level',p_aal,
    'scopes_verified_by','server');
END $$;
-- The server decides: a live session, the real assurance level, a scope this
-- session actually holds, and the admin write pause for anything that writes.
CREATE FUNCTION private_isg.admin_authorize(p_session uuid,p_scope text,p_write boolean,p_now timestamptz) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.admin_sessions; needs_mfa boolean; paused boolean;
BEGIN
  IF p_session IS NULL OR p_scope IS NULL OR p_write IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.admin_sessions WHERE session_id=p_session;
  IF NOT FOUND OR entry.revoked_at IS NOT NULL OR entry.expires_at<=p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT requires_aal2 INTO needs_mfa FROM private_isg.admin_scopes WHERE scope_key=p_scope;
  IF needs_mfa IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF needs_mfa AND entry.assurance_level<>'aal2' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MFA_REQUIRED'; END IF;
  IF NOT (p_scope=ANY(entry.granted_scopes)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SCOPE_DENIED'; END IF;
  IF p_write THEN
    SELECT writes_paused INTO paused FROM private_isg.admin_operation_state WHERE singleton;
    IF paused THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ADMIN_WRITES_PAUSED'; END IF; END IF;
END $$;
CREATE FUNCTION private_isg.simulate_admin_action(p_session uuid,p_kind text,p_scope text,p_target text,
  p_report jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE created uuid;
BEGIN
  PERFORM private_isg.observability_gate(true);
  -- A simulation reads and reports; it is not an admin write.
  PERFORM private_isg.admin_authorize(p_session,p_scope,false,p_now);
  IF p_kind IS NULL OR p_target IS NULL OR p_report IS NULL OR jsonb_typeof(p_report)<>'object' OR
     octet_length(p_report::text)>4096 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.admin_actions(session_id,action_kind,scope_key,target_ref,simulated_at,simulation_report)
    VALUES(p_session,p_kind,p_scope,p_target,p_now,p_report) RETURNING action_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'action_id',created,'state','simulated','domain_changed',false);
END $$;
-- Fail-closed publish: the audit entry is written first and the action points
-- at it, so a publish without a durable audit trail cannot exist.
CREATE FUNCTION private_isg.publish_admin_action(p_session uuid,p_action uuid,p_payload jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.admin_actions; session_row private_isg.admin_sessions; audit_ref uuid;
BEGIN
  PERFORM private_isg.observability_gate(true);
  IF p_action IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.admin_actions WHERE action_id=p_action FOR UPDATE;
  IF NOT FOUND OR entry.session_id<>p_session THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='published' THEN
    RETURN jsonb_build_object('schema_version',1,'action_id',p_action,'state','published','replayed',true); END IF;
  IF entry.state<>'simulated' OR entry.simulated_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SIMULATION_REQUIRED'; END IF;
  PERFORM private_isg.admin_authorize(p_session,entry.scope_key,true,p_now);
  SELECT * INTO session_row FROM private_isg.admin_sessions WHERE session_id=p_session;
  INSERT INTO private_isg.admin_audit_entries(session_id,admin_user_id,action_kind,scope_key,target_ref,
      payload_digest,written_at)
    VALUES(p_session,session_row.admin_user_id,entry.action_kind,entry.scope_key,entry.target_ref,
      sha256(convert_to(p_payload::text,'UTF8')),p_now) RETURNING audit_id INTO audit_ref;
  UPDATE private_isg.admin_actions SET state='published',published_at=p_now,audit_id=audit_ref WHERE action_id=p_action;
  RETURN jsonb_build_object('schema_version',1,'action_id',p_action,'state','published','audit_id',audit_ref,
    'audit_written_before_publish',true,'raw_payload_stored',false);
END $$;
-- A masked, allowlisted projection. A column nobody named cannot be exported.
CREATE FUNCTION private_isg.request_admin_export(p_session uuid,p_action uuid,p_dataset text,p_columns text[],
  p_rows bigint,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE safe_columns text[]; maskable text[]; offending text; masked text[]; created uuid;
BEGIN
  PERFORM private_isg.observability_gate(true);
  PERFORM private_isg.admin_authorize(p_session,'export.masked',false,p_now);
  IF p_dataset IS NULL OR p_columns IS NULL OR p_rows IS NULL OR p_rows<0 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_dataset='billing_settlements' THEN
    safe_columns:=ARRAY['settlement_id','environment','store','billing_period','state','settled_at'];
    maskable:=ARRAY['purchase_ref'];
  ELSIF p_dataset='campaign_suppressions' THEN
    safe_columns:=ARRAY['suppression_id','campaign_id','reason','decided_at_stage','decided_at'];
    maskable:=ARRAY['owner_id'];
  ELSIF p_dataset='support_chains' THEN
    safe_columns:=ARRAY['support_id','environment','app_build','platform','outcome','started_at'];
    maskable:=ARRAY['owner_id'];
  ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM unnest(p_columns) AS keys(key)
    WHERE NOT (keys.key=ANY(safe_columns)) AND NOT (keys.key=ANY(maskable)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EXPORT_DENIED'; END IF;
  SELECT coalesce(array_agg(keys.key ORDER BY keys.key),ARRAY[]::text[]) INTO masked
    FROM unnest(p_columns) AS keys(key) WHERE keys.key=ANY(maskable);
  INSERT INTO private_isg.admin_exports(action_id,dataset,requested_columns,masked_columns,row_count,created_at)
    VALUES(p_action,p_dataset,p_columns,masked,p_rows,p_now) RETURNING export_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'export_id',created,'dataset',p_dataset,'masked_columns',masked,
    'raw_pii_included',false);
END $$;
-- Pausing admin writes never pauses the audit trail or the billing settlement
-- chain; those belong to P14 and are not touched from here.
CREATE FUNCTION private_isg.set_admin_write_pause(p_paused boolean,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.observability_gate(true);
  IF p_paused IS NULL OR p_now IS NULL OR (p_paused AND (p_reason IS NULL OR length(p_reason) NOT BETWEEN 3 AND 200)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.admin_operation_state SET writes_paused=p_paused,
    pause_reason=CASE WHEN p_paused THEN p_reason ELSE NULL END,changed_at=p_now WHERE singleton;
  RETURN jsonb_build_object('schema_version',1,'writes_paused',p_paused,'audit_continues',true,
    'settlement_continues',true);
END $$;
REVOKE ALL ON FUNCTION private_isg.observability_gate(boolean),
  private_isg.telemetry_redaction_violation(jsonb),
  private_isg.start_support_chain(text,uuid,text,text,text,uuid,timestamptz),
  private_isg.record_technical_event(text,text,text,text,uuid,uuid,integer,integer,jsonb,timestamptz),
  private_isg.close_support_chain(text,text,timestamptz),
  private_isg.record_queue_report(uuid,uuid,integer,bigint,timestamptz,boolean,timestamptz),
  private_isg.record_attribution(uuid,boolean,text,timestamptz),
  private_isg.open_admin_session(uuid,text,text[],timestamptz,timestamptz),
  private_isg.admin_authorize(uuid,text,boolean,timestamptz),
  private_isg.simulate_admin_action(uuid,text,text,text,jsonb,timestamptz),
  private_isg.publish_admin_action(uuid,uuid,jsonb,timestamptz),
  private_isg.request_admin_export(uuid,uuid,text,text[],bigint,timestamptz),
  private_isg.set_admin_write_pause(boolean,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
