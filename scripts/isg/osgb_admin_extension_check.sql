\set ON_ERROR_STOP on
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true WHERE feature='workspace_admin';
INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('71000000-0000-4000-8000-000000000001','osgb','Admin OSGB','pending_purchase','Europe/Istanbul','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status,is_practicing_expert) VALUES
  ('72000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active',false),
  ('72000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000002','expert','active',true);
INSERT INTO private_isg.admin_sessions(session_id,admin_user_id,assurance_level,granted_scopes,opened_at,expires_at) VALUES
  ('73000000-0000-4000-8000-000000000001','74000000-0000-4000-8000-000000000001','aal2',
    ARRAY['osgb.read','osgb.support','osgb.billing'],clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1 hour'),
  ('73000000-0000-4000-8000-000000000002','74000000-0000-4000-8000-000000000002','aal1',
    ARRAY['osgb.billing'],clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1 hour');

-- AAL1 cannot even simulate an economic command.
DO $$ BEGIN
  PERFORM private_isg.workspace_admin_simulate('73000000-0000-4000-8000-000000000002','osgb_credit_grant',
    '71000000-0000-4000-8000-000000000001',NULL,NULL,50,NULL,NULL,'destek kredisi',clock_timestamp());
  RAISE EXCEPTION 'EXPECTED_MFA_REQUIRED';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'MFA_REQUIRED' THEN RAISE; END IF; END $$;

CREATE TEMP TABLE admin_state(key text PRIMARY KEY,value text NOT NULL);
WITH simulated AS (SELECT private_isg.workspace_admin_simulate('73000000-0000-4000-8000-000000000001',
  'osgb_trial_grant','71000000-0000-4000-8000-000000000001',NULL,'starter',NULL,
  clock_timestamp()+interval '14 days',NULL,'pilot deneme',clock_timestamp()) body)
INSERT INTO admin_state VALUES('trial_command',(SELECT body->>'command_id' FROM simulated));
DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_admin_execute('73000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM admin_state WHERE key='trial_command'),clock_timestamp());
  IF body->>'state'<>'executed' OR (body->>'audit_written_before_effect')::boolean IS NOT TRUE OR
     (SELECT source_kind FROM private_isg.workspace_entitlements WHERE workspace_id='71000000-0000-4000-8000-000000000001')<>'admin_trial' THEN
    RAISE EXCEPTION 'trial command failed: %',body; END IF;
END $$;

WITH simulated AS (SELECT private_isg.workspace_admin_simulate('73000000-0000-4000-8000-000000000001',
  'osgb_credit_grant','71000000-0000-4000-8000-000000000001',NULL,NULL,50,NULL,NULL,
  'destek kredisi',clock_timestamp()) body)
INSERT INTO admin_state VALUES('credit_command',(SELECT body->>'command_id' FROM simulated));
SELECT private_isg.workspace_admin_execute('73000000-0000-4000-8000-000000000001',
  (SELECT value::uuid FROM admin_state WHERE key='credit_command'),clock_timestamp());
SELECT private_isg.workspace_admin_execute('73000000-0000-4000-8000-000000000001',
  (SELECT value::uuid FROM admin_state WHERE key='credit_command'),clock_timestamp());

-- Write pause blocks publish and rolls the audit/publish back together.
WITH simulated AS (SELECT private_isg.workspace_admin_simulate('73000000-0000-4000-8000-000000000001',
  'osgb_member_suspend','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000002',
  NULL,NULL,NULL,0,'destek askısı',clock_timestamp()) body)
INSERT INTO admin_state VALUES('suspend_command',(SELECT body->>'command_id' FROM simulated));
UPDATE private_isg.admin_operation_state SET writes_paused=true,pause_reason='bakım' WHERE singleton;
DO $$ BEGIN
  PERFORM private_isg.workspace_admin_execute('73000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM admin_state WHERE key='suspend_command'),clock_timestamp());
  RAISE EXCEPTION 'EXPECTED_ADMIN_WRITE_PAUSE';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ADMIN_WRITES_PAUSED' THEN RAISE; END IF; END $$;
UPDATE private_isg.admin_operation_state SET writes_paused=false,pause_reason=NULL WHERE singleton;
SELECT private_isg.workspace_admin_execute('73000000-0000-4000-8000-000000000001',
  (SELECT value::uuid FROM admin_state WHERE key='suspend_command'),clock_timestamp());

DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_admin_overview('73000000-0000-4000-8000-000000000001',20,clock_timestamp());
  IF jsonb_array_length(body->'rows')<>1 OR
     (SELECT count(*) FROM private_isg.admin_audit_entries)<>3 OR
     (SELECT count(*) FROM private_isg.workspace_wallet_entries WHERE entry_type='admin_grant')<>1 OR
     (SELECT status FROM private_isg.workspace_memberships WHERE id='72000000-0000-4000-8000-000000000002')<>'suspended' OR
     has_function_privilege('authenticated','private_isg.workspace_admin_execute(uuid,uuid,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'admin extension invariant failed: %',body; END IF;
  RAISE NOTICE 'ok existing admin authority, MFA, scope, simulation, write pause, audit-first, idempotent credit and member suspension';
END $$;
