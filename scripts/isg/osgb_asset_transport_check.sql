\set ON_ERROR_STOP on
CREATE TEMP TABLE asset_state(key text PRIMARY KEY,value text NOT NULL);
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true
  WHERE feature IN ('workspace_companies','workspace_assignments','workspace_storage');
INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('91000000-0000-4000-8000-000000000001','osgb','Dosya OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status,is_practicing_expert) VALUES
  ('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active',false),
  ('92000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000002','expert','active',true);
INSERT INTO private_isg.workspace_companies(id,workspace_id,name,hazard_class,created_by_user_id,updated_by_user_id) VALUES
  ('93000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','Dosya Firma','medium','20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.company_assignments(id,workspace_id,company_id,membership_id,assignment_role,starts_at,created_by_user_id) VALUES
  ('94000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002','primary',clock_timestamp()-interval '1 day','20000000-0000-0000-0000-000000000001');

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
WITH opened AS (SELECT public.isg_workspace_upload_open_v1('91000000-0000-4000-8000-000000000001',
  '93000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001',sha256('upload-request'::bytea),
  'risk_report','application/pdf','pdf',2000,clock_timestamp()+interval '10 minutes') body)
INSERT INTO asset_state VALUES
  ('upload_token',(SELECT body->>'upload_token' FROM opened)),
  ('upload_intent',(SELECT body->>'intent_id' FROM opened));
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_upload_open_v1('91000000-0000-4000-8000-000000000001',
    '93000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001',sha256('upload-request'::bytea),
    'risk_report','application/pdf','pdf',2000,(SELECT expires_at FROM private_isg.workspace_upload_intents LIMIT 1));
  IF (body->>'replayed')::boolean IS NOT TRUE OR (body->>'credential_returned')::boolean IS NOT FALSE OR body ? 'upload_token' THEN
    RAISE EXCEPTION 'upload credential replay leaked token: %',body; END IF;
END $$;
SELECT private_isg.workspace_upload_finalize_via_token((SELECT value FROM asset_state WHERE key='upload_token'),
  'object-v1',1200,sha256('file-bytes'::bytea),clock_timestamp());
SELECT private_isg.workspace_upload_finalize_via_token((SELECT value FROM asset_state WHERE key='upload_token'),
  'object-v1',1200,sha256('file-bytes'::bytea),clock_timestamp());

WITH opened AS (SELECT public.isg_workspace_download_open_v1('91000000-0000-4000-8000-000000000001',
  (SELECT value::uuid FROM asset_state WHERE key='upload_intent'),'view',clock_timestamp()+interval '2 minutes') body)
INSERT INTO asset_state VALUES('download_token',(SELECT body->>'download_token' FROM opened));
WITH claimed AS (SELECT private_isg.workspace_download_claim((SELECT value FROM asset_state WHERE key='download_token'),clock_timestamp()) body)
INSERT INTO asset_state VALUES('download_id',(SELECT body->>'download_id' FROM claimed));
SELECT private_isg.workspace_download_delivered((SELECT value::uuid FROM asset_state WHERE key='download_id'),'object-v1',1200,clock_timestamp());

-- A token issued before membership suspension fails closed at claim time.
WITH opened AS (SELECT public.isg_workspace_download_open_v1('91000000-0000-4000-8000-000000000001',
  (SELECT value::uuid FROM asset_state WHERE key='upload_intent'),'view',clock_timestamp()+interval '2 minutes') body)
INSERT INTO asset_state VALUES('revoked_download_token',(SELECT body->>'download_token' FROM opened));
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
UPDATE private_isg.workspace_memberships SET status='suspended',is_practicing_expert=false,suspended_at=clock_timestamp()
  WHERE id='92000000-0000-4000-8000-000000000002';
DO $$ BEGIN
  PERFORM private_isg.workspace_download_claim((SELECT value FROM asset_state WHERE key='revoked_download_token'),clock_timestamp());
  RAISE EXCEPTION 'EXPECTED_REVOKED_DOWNLOAD';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END $$;

-- Deletion becomes logical immediately and physical only with matching object-version evidence.
WITH requested AS (SELECT public.isg_workspace_asset_delete_v1('91000000-0000-4000-8000-000000000001',
  (SELECT value::uuid FROM asset_state WHERE key='upload_intent'),'saklama talebi') body)
INSERT INTO asset_state VALUES('deletion',(SELECT body->>'deletion_id' FROM requested));
SELECT private_isg.workspace_asset_delete_complete((SELECT value::uuid FROM asset_state WHERE key='deletion'),
  'object-v1',clock_timestamp());
DO $$ BEGIN
  IF (SELECT lifecycle FROM private_isg.workspace_file_assets LIMIT 1)<>'deleted' OR
     (SELECT count(*) FROM private_isg.workspace_download_intents WHERE status='delivered')<>1 OR
     (SELECT sum(delivered_bytes) FROM private_isg.workspace_download_intents WHERE status='delivered')<>1200 OR
     has_table_privilege('authenticated','private_isg.workspace_upload_intents','SELECT') OR
     has_function_privilege('authenticated','private_isg.workspace_upload_finalize_via_token(text,text,bigint,bytea,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'asset transport invariant failed'; END IF;
  RAISE NOTICE 'ok server path ownership, one-time token, byte finalize, download delivery, revoke check and evidence-based delete';
END $$;
