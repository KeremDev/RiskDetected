-- Minimal contract-compatible copy of the pre-existing P16 admin authority for disposable tests.
CREATE TABLE private_isg.admin_scopes(scope_key text PRIMARY KEY,requires_aal2 boolean NOT NULL DEFAULT true,note text NOT NULL);
INSERT INTO private_isg.admin_scopes(scope_key,note) VALUES('billing.read','read');
CREATE TABLE private_isg.admin_sessions(session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),admin_user_id uuid NOT NULL,
  assurance_level text NOT NULL CHECK(assurance_level IN ('aal1','aal2')),granted_scopes text[] NOT NULL,
  opened_at timestamptz NOT NULL,expires_at timestamptz NOT NULL,revoked_at timestamptz);
CREATE TABLE private_isg.admin_audit_entries(audit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),session_id uuid NOT NULL REFERENCES private_isg.admin_sessions,
  admin_user_id uuid NOT NULL,action_kind text NOT NULL,scope_key text NOT NULL REFERENCES private_isg.admin_scopes,
  target_ref text NOT NULL,payload_digest bytea NOT NULL,carries_raw_payload boolean NOT NULL DEFAULT false CHECK(NOT carries_raw_payload),written_at timestamptz NOT NULL);
CREATE TABLE private_isg.admin_actions(action_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),session_id uuid NOT NULL REFERENCES private_isg.admin_sessions,
  action_kind text NOT NULL CHECK(action_kind IN ('campaign_pause','campaign_publish','budget_change','rollout_switch','benefit_review','export_request')),
  scope_key text NOT NULL REFERENCES private_isg.admin_scopes,target_ref text NOT NULL,state text NOT NULL DEFAULT 'simulated',
  simulated_at timestamptz,published_at timestamptz,refused_code text,audit_id uuid REFERENCES private_isg.admin_audit_entries,simulation_report jsonb NOT NULL);
CREATE TABLE private_isg.admin_operation_state(singleton boolean PRIMARY KEY DEFAULT true,writes_paused boolean NOT NULL DEFAULT false,
  pause_reason text,changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),audit_continues boolean NOT NULL DEFAULT true,
  settlement_continues boolean NOT NULL DEFAULT true);
INSERT INTO private_isg.admin_operation_state(singleton) VALUES(true);
CREATE FUNCTION private_isg.admin_authorize(p_session uuid,p_scope text,p_write boolean,p_now timestamptz) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$ DECLARE s private_isg.admin_sessions; paused boolean; BEGIN
  SELECT * INTO s FROM private_isg.admin_sessions WHERE session_id=p_session;
  IF s.session_id IS NULL OR s.revoked_at IS NOT NULL OR s.expires_at<=p_now THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF s.assurance_level<>'aal2' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MFA_REQUIRED'; END IF;
  IF (p_scope=ANY(s.granted_scopes)) IS NOT TRUE THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SCOPE_DENIED'; END IF;
  IF p_write THEN SELECT writes_paused INTO paused FROM private_isg.admin_operation_state WHERE singleton;
    IF paused THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ADMIN_WRITES_PAUSED'; END IF; END IF;
END $$;
CREATE FUNCTION private_isg.simulate_admin_action(p_session uuid,p_kind text,p_scope text,p_target text,p_report jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$ DECLARE created uuid; BEGIN
  PERFORM private_isg.admin_authorize(p_session,p_scope,false,p_now);
  INSERT INTO private_isg.admin_actions(session_id,action_kind,scope_key,target_ref,simulated_at,simulation_report)
    VALUES(p_session,p_kind,p_scope,p_target,p_now,p_report) RETURNING action_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'action_id',created,'state','simulated'); END $$;
CREATE FUNCTION private_isg.publish_admin_action(p_session uuid,p_action uuid,p_payload jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$ DECLARE a private_isg.admin_actions;s private_isg.admin_sessions;audit_ref uuid; BEGIN
  SELECT * INTO a FROM private_isg.admin_actions WHERE action_id=p_action FOR UPDATE;
  IF a.session_id<>p_session THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF a.state='published' THEN RETURN jsonb_build_object('audit_id',a.audit_id,'replayed',true); END IF;
  PERFORM private_isg.admin_authorize(p_session,a.scope_key,true,p_now);
  SELECT * INTO s FROM private_isg.admin_sessions WHERE session_id=p_session;
  INSERT INTO private_isg.admin_audit_entries(session_id,admin_user_id,action_kind,scope_key,target_ref,payload_digest,written_at)
    VALUES(p_session,s.admin_user_id,a.action_kind,a.scope_key,a.target_ref,sha256(convert_to(p_payload::text,'UTF8')),p_now) RETURNING audit_id INTO audit_ref;
  UPDATE private_isg.admin_actions SET state='published',published_at=p_now,audit_id=audit_ref WHERE action_id=p_action;
  RETURN jsonb_build_object('audit_id',audit_ref,'replayed',false); END $$;
