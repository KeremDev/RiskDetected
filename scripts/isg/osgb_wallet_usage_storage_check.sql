\set ON_ERROR_STOP on
CREATE TEMP TABLE wallet_test_state(key text PRIMARY KEY,value text NOT NULL);
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true
  WHERE feature IN ('workspace_wallet','workspace_storage');
INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('61000000-0000-4000-8000-000000000001','osgb','Wallet OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status) VALUES
  ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active');

SELECT private_isg.workspace_credit_grant('63000000-0000-4000-8000-000000000001',
  '61000000-0000-4000-8000-000000000001','purchase','sandbox:purchase:1',100,NULL);
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH reserved AS (
  SELECT public.isg_workspace_credit_reserve_v1('61000000-0000-4000-8000-000000000001',NULL,
    'analysis',80,'63000000-0000-4000-8000-000000000002',sha256(convert_to('request-1','UTF8'))) body
) INSERT INTO wallet_test_state VALUES('reservation',(SELECT body->>'reservation_id' FROM reserved));
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_credit_reserve_v1('61000000-0000-4000-8000-000000000001',NULL,
    'analysis',80,'63000000-0000-4000-8000-000000000002',sha256(convert_to('request-1','UTF8')));
  IF (body->>'replayed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'reserve replay failed'; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_credit_reserve_v1('61000000-0000-4000-8000-000000000001',NULL,
    'analysis',30,'63000000-0000-4000-8000-000000000003',sha256(convert_to('request-2','UTF8')));
  RAISE EXCEPTION 'EXPECTED_INSUFFICIENT';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'INSUFFICIENT_CREDITS' THEN RAISE; END IF; END $$;

DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_credit_settle('63000000-0000-4000-8000-000000000004',
    (SELECT value::uuid FROM wallet_test_state WHERE key='reservation'),60,1000,200,'fixture-model','fixture-v1');
  IF (body->>'posted_units')::integer<>40 OR (body->>'reserved_units')::integer<>0 THEN
    RAISE EXCEPTION 'settlement failed: %',body; END IF;
  body:=private_isg.workspace_credit_settle('63000000-0000-4000-8000-000000000004',
    (SELECT value::uuid FROM wallet_test_state WHERE key='reservation'),60,1000,200,'fixture-model','fixture-v1');
  IF (body->>'replayed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'settlement replay failed'; END IF;
END $$;

INSERT INTO wallet_test_state VALUES('grant',(SELECT id::text FROM private_isg.workspace_credit_grants
  WHERE source_reference='sandbox:purchase:1'));
DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_credit_refund('63000000-0000-4000-8000-000000000005',
    (SELECT value::uuid FROM wallet_test_state WHERE key='grant'),80);
  IF (body->>'posted_units')::integer<>0 OR (body->>'debt_units')::integer<>40 THEN
    RAISE EXCEPTION 'refund debt failed: %',body; END IF;
  body:=private_isg.workspace_credit_grant('63000000-0000-4000-8000-000000000006',
    '61000000-0000-4000-8000-000000000001','admin_support','ticket:fixture',50,NULL);
  IF (body->>'posted_units')::integer<>10 OR (body->>'debt_units')::integer<>0 THEN
    RAISE EXCEPTION 'debt repayment ordering failed: %',body; END IF;
END $$;

-- Finalized physical bytes are server facts and duplicate finalize is stable.
DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_asset_finalize('64000000-0000-4000-8000-000000000001',
    '61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001',NULL,
    'upload','fixture','workspace/object.pdf','v1',4096,sha256(convert_to('file','UTF8')));
  IF (body->>'byte_size')::integer<>4096 OR (body->>'replayed')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'asset finalize failed'; END IF;
  body:=private_isg.workspace_asset_finalize('64000000-0000-4000-8000-000000000001',
    '61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001',NULL,
    'upload','fixture','workspace/object.pdf','v1',4096,sha256(convert_to('file','UTF8')));
  IF (body->>'replayed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'asset replay failed'; END IF;
END $$;
DO $$ BEGIN
  PERFORM private_isg.workspace_asset_finalize('64000000-0000-4000-8000-000000000001',
    '61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001',NULL,
    'upload','fixture','workspace/object.pdf','v1',4097,sha256(convert_to('file','UTF8')));
  RAISE EXCEPTION 'EXPECTED_ASSET_CONFLICT';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'IDEMPOTENCY_CONFLICT' THEN RAISE; END IF; END $$;

DO $$ BEGIN
  IF has_table_privilege('authenticated','private_isg.workspace_wallets','SELECT') OR
     has_function_privilege('service_role','private_isg.workspace_credit_settle(uuid,uuid,bigint,bigint,bigint,text,text)','EXECUTE') OR
     (SELECT count(*) FROM private_isg.workspace_usage_records)<>1 OR
     (SELECT sum(byte_size) FROM private_isg.workspace_file_assets WHERE lifecycle='active')<>4096 THEN
    RAISE EXCEPTION 'wallet/storage grants or reconciliation failed'; END IF;
  RAISE NOTICE 'ok wallet reserve, over-reserve denial, settle replay, refund debt, repayment order and asset byte idempotency';
END $$;
