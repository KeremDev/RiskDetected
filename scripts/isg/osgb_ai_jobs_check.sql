\set ON_ERROR_STOP on
CREATE TEMP TABLE ai_state(key text PRIMARY KEY,value text NOT NULL);
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true
  WHERE feature IN ('workspace_companies','workspace_assignments','workspace_wallet','workspace_storage','workspace_ai');
INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('81000000-0000-4000-8000-000000000001','osgb','AI OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status,is_practicing_expert) VALUES
  ('82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active',false),
  ('82000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000002','expert','active',true);
INSERT INTO private_isg.workspace_companies(id,workspace_id,name,hazard_class,created_by_user_id,updated_by_user_id) VALUES
  ('83000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','AI Firma','high','20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.company_assignments(id,workspace_id,company_id,membership_id,assignment_role,starts_at,created_by_user_id) VALUES
  ('84000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000002','primary',clock_timestamp()-interval '1 day','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.workspace_ai_pricing(feature,model_code,pricing_version,reserve_units,max_settle_units,active)
  VALUES('photo_analysis','test-model','test-v1',20,20,true);
SELECT private_isg.workspace_credit_grant('85000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','migration','fixture',100,NULL);

-- A permission revision change before provider start releases the reservation and fails closed.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
WITH submitted AS (SELECT public.isg_workspace_ai_submit_v1('81000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000001','photo_analysis','test-model','test-v1',
  '85000000-0000-4000-8000-000000000002',sha256('revoked-job'::bytea),'photo','photo:1',1) body)
INSERT INTO ai_state VALUES('revoked_job',(SELECT body->>'job_id' FROM submitted));
UPDATE private_isg.workspace_memberships SET permission_revision=permission_revision+1
  WHERE id='82000000-0000-4000-8000-000000000002';
DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_ai_start((SELECT value::uuid FROM ai_state WHERE key='revoked_job'),sha256('provider-1'::bytea),clock_timestamp());
  IF body->>'error_code'<>'AUTHORITY_REVOKED' OR
     (SELECT reserved_units FROM private_isg.workspace_wallets WHERE workspace_id='81000000-0000-4000-8000-000000000001')<>0 THEN
    RAISE EXCEPTION 'revoked job was not released: %',body; END IF;
END $$;

-- A successful job remains pinned to its original workspace, actor, company and wallet.
WITH submitted AS (SELECT public.isg_workspace_ai_submit_v1('81000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000001','photo_analysis','test-model','test-v1',
  '85000000-0000-4000-8000-000000000003',sha256('success-job'::bytea),'photo','photo:2',3) body)
INSERT INTO ai_state VALUES('success_job',(SELECT body->>'job_id' FROM submitted));
SELECT private_isg.workspace_ai_start((SELECT value::uuid FROM ai_state WHERE key='success_job'),sha256('provider-2'::bytea),clock_timestamp());
SELECT private_isg.workspace_ai_complete((SELECT value::uuid FROM ai_state WHERE key='success_job'),12,1000,200,
  '85000000-0000-4000-8000-000000000004','generated','81000000/result.json','v1',1200,
  sha256('result-bytes'::bytea),clock_timestamp());
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_ai_get_v1('81000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM ai_state WHERE key='success_job'));
  IF body->>'status'<>'succeeded' OR body->>'source_reference'<>'photo:2' OR
     (SELECT posted_units FROM private_isg.workspace_wallets WHERE workspace_id='81000000-0000-4000-8000-000000000001')<>88 OR
     (SELECT charged_units FROM private_isg.workspace_usage_records LIMIT 1)<>12 OR
     (SELECT workspace_id FROM private_isg.workspace_file_assets WHERE id='85000000-0000-4000-8000-000000000004')<>'81000000-0000-4000-8000-000000000001' THEN
    RAISE EXCEPTION 'AI pin/settle failed: %',body; END IF;
END $$;

-- Once the expert is suspended, the finished result is no longer readable by that actor.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
UPDATE private_isg.workspace_memberships SET status='suspended',is_practicing_expert=false,suspended_at=clock_timestamp(),
  permission_revision=permission_revision+1,version=version+1 WHERE id='82000000-0000-4000-8000-000000000002';
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_ai_get_v1('81000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM ai_state WHERE key='success_job'));
  RAISE EXCEPTION 'EXPECTED_REVOKED_RESULT_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END $$;

DO $$ BEGIN
  IF has_table_privilege('authenticated','private_isg.workspace_ai_jobs','SELECT') OR
     has_function_privilege('authenticated','private_isg.workspace_ai_complete(uuid,bigint,bigint,bigint,uuid,text,text,text,bigint,bytea,timestamptz)','EXECUTE') OR
     has_function_privilege('service_role','public.isg_workspace_ai_submit_v1(uuid,uuid,text,text,text,uuid,bytea,text,text,bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'AI authority grant leak'; END IF;
  RAISE NOTICE 'ok AI server pricing, workspace pin, pre-provider revocation, reservation release, settlement, asset ownership and result revocation';
END $$;
