-- Staging rollback fixture only. Tests the SQL state machine using synthetic
-- inspection evidence; real byte inspection must also be tested through the edge function.

CREATE TEMP TABLE expert_file_fixture(entry uuid,intent uuid,company uuid,asset uuid);
GRANT SELECT ON expert_file_fixture TO authenticated;
DO $open$
DECLARE w uuid:=current_setting('isg.test_workspace')::uuid; c uuid; r jsonb; args jsonb;
BEGIN
 c:=((public.isg_expert_rpc_v1(w,'isg_expert_companies_v1','{}')->'payload')#>>'{rows,0,id}')::uuid;
 args:=jsonb_build_object('p_company',c,'p_action','open_upload','p_operation',gen_random_uuid(),'p_mutation',gen_random_uuid(),
  'p_payload',jsonb_build_object('title','Rollback document','category','inspection_report','file_name','rollback.pdf','extension','pdf','bytes',100,'sha256',repeat('a',64),'tags','[]'::jsonb));
 r:=public.isg_expert_rpc_v1(w,'isg_pilot_file_library_mutate_v2',args)->'payload';
 PERFORM public.isg_expert_rpc_v1(w,'isg_expert_file_inspection_access_v1',jsonb_build_object('entry_id',r->>'entry_id'));
 INSERT INTO expert_file_fixture VALUES((r->>'entry_id')::uuid,(r#>>'{row,intent_id}')::uuid,c,NULL);
 IF NOT private_isg.expert_storage_allowed('isg-quarantine',r#>>'{row,upload_path}',true) THEN RAISE EXCEPTION 'UPLOAD_POLICY_DENIED'; END IF;
END $open$;
RESET ROLE;
DO $worker$
DECLARE f expert_file_fixture; r jsonb;
BEGIN
 SELECT * INTO STRICT f FROM expert_file_fixture;
 r:=public.isg_expert_file_inspection_v1(f.intent,'claim','{}');
 IF r->>'storage_scope'<>f.company::text THEN RAISE EXCEPTION 'WRONG_STORAGE_SCOPE'; END IF;
 PERFORM public.isg_expert_file_inspection_v1(f.intent,'received',jsonb_build_object('bytes',100,'sha256',repeat('a',64),'detected_type','application/pdf'));
 PERFORM public.isg_expert_file_inspection_v1(f.intent,'scanned',jsonb_build_object('scanner','format-inspector','scan_version','rollback-fixture','verdict','clean','finding_code','','sha256',repeat('a',64),'evidence','{}'::jsonb));
 r:=public.isg_expert_file_inspection_v1(f.intent,'promoted',jsonb_build_object('bytes',100,'sha256',repeat('a',64)));
 UPDATE expert_file_fixture SET asset=(r->>'asset_id')::uuid;
 IF NOT EXISTS(SELECT 1 FROM private_isg.file_assets WHERE asset_id=(r->>'asset_id')::uuid AND owner_id IS NULL AND workspace_id=current_setting('isg.test_workspace')::uuid) THEN RAISE EXCEPTION 'WRONG_ASSET_SCOPE'; END IF;
END $worker$;
SET LOCAL ROLE authenticated;
DO $read$
DECLARE f expert_file_fixture; r jsonb; args jsonb;
BEGIN
 SELECT * INTO STRICT f FROM expert_file_fixture;
 args:=jsonb_build_object('p_company',f.company,'p_kind','detail','p_query',NULL,'p_category',NULL,'p_state',NULL,'p_id',f.entry,'p_limit',NULL,'p_offset',NULL);
 r:=public.isg_expert_rpc_v1(current_setting('isg.test_workspace')::uuid,'isg_pilot_file_library_read_v2',args)->'payload';
 IF r#>>'{row,state}'<>'promoted' OR (r#>>'{row,asset_id}')::uuid<>f.asset THEN RAISE EXCEPTION 'PROMOTED_READ_INVALID'; END IF;
 IF NOT private_isg.expert_storage_allowed(r#>>'{row,download_bucket}',r#>>'{row,download_path}',false) THEN RAISE EXCEPTION 'DOWNLOAD_POLICY_DENIED'; END IF;
END $read$;
SELECT 'canonical file open/inspection state machine/promotion/read/storage authorization' test,true passed;
