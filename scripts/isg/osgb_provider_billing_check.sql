\set ON_ERROR_STOP on
CREATE TEMP TABLE billing_state(key text PRIMARY KEY,value text NOT NULL);
INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('61000000-0000-4000-8000-000000000001','osgb','Ödeme OSGB','pending_purchase','Europe/Istanbul','20000000-0000-0000-0000-000000000001'),
  ('61000000-0000-4000-8000-000000000002','osgb','Diğer Ödeme OSGB','pending_purchase','Europe/Istanbul','20000000-0000-0000-0000-000000000004');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status) VALUES
  ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active'),
  ('62000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000002','20000000-0000-0000-0000-000000000004','owner','active');
INSERT INTO private_isg.workspace_billing_products(provider,environment,product_id,product_kind,plan_code,credit_units,catalog_version,approved,active) VALUES
  ('apple','sandbox','test.osgb.growth','subscription','growth',NULL,1,true,true),
  ('apple','sandbox','test.osgb.credits100','credit_pack',NULL,100,1,true,true);

-- Verified subscription activates exactly the mapped sandbox workspace entitlement.
WITH received AS (
  SELECT private_isg.workspace_provider_event_record('apple','sandbox','event-sub-10','subscription_state',
    'txn-sub-10','chain-a','test.osgb.growth','61000000-0000-4000-8000-000000000001',
    '20000000-0000-0000-0000-000000000001','active',clock_timestamp()-interval '1 minute',
    clock_timestamp()+interval '30 days',10,'callback','verified',sha256('sub10'::bytea),'server_adapter') body
) INSERT INTO billing_state VALUES('subscription_inbox',(SELECT body->>'inbox_id' FROM received));
DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_provider_event_process((SELECT value::uuid FROM billing_state WHERE key='subscription_inbox'));
  IF body->>'state'<>'applied' OR
     (SELECT plan_code FROM private_isg.workspace_entitlements WHERE workspace_id='61000000-0000-4000-8000-000000000001')<>'growth' OR
     (SELECT status FROM private_isg.workspaces WHERE id='61000000-0000-4000-8000-000000000001')<>'active' THEN
    RAISE EXCEPTION 'subscription apply failed: %',body; END IF;
END $$;
DO $$ DECLARE first_body jsonb; second_body jsonb; BEGIN
  first_body:=private_isg.workspace_provider_event_record('apple','sandbox','event-sub-10','subscription_state',
    'txn-sub-10','chain-a','test.osgb.growth','61000000-0000-4000-8000-000000000001',
    '20000000-0000-0000-0000-000000000001','active',(SELECT effective_at FROM private_isg.workspace_provider_inbox WHERE provider_event_id='event-sub-10'),
    (SELECT valid_until FROM private_isg.workspace_provider_inbox WHERE provider_event_id='event-sub-10'),10,'callback','verified',sha256('sub10'::bytea),'server_adapter');
  second_body:=private_isg.workspace_provider_event_process((first_body->>'inbox_id')::uuid);
  IF (first_body->>'replayed')::boolean IS NOT TRUE OR (second_body->>'replayed')::boolean IS NOT TRUE OR
     (SELECT count(*) FROM private_isg.workspace_subscription_bindings)<>1 THEN RAISE EXCEPTION 'subscription replay failed'; END IF;
END $$;

-- An older expiry cannot erase the newer active projection.
WITH received AS (
  SELECT private_isg.workspace_provider_event_record('apple','sandbox','event-sub-09','subscription_state',
    'txn-sub-09','chain-a','test.osgb.growth','61000000-0000-4000-8000-000000000001',
    '20000000-0000-0000-0000-000000000001','expired',clock_timestamp()-interval '2 days',NULL,
    9,'webhook','verified',sha256('sub09'::bytea),'server_adapter') body
) SELECT private_isg.workspace_provider_event_process((body->>'inbox_id')::uuid) FROM received;
DO $$ BEGIN
  IF (SELECT state FROM private_isg.workspace_provider_inbox WHERE provider_event_id='event-sub-09')<>'ignored' OR
     (SELECT status FROM private_isg.workspace_subscription_bindings WHERE subscription_chain_id='chain-a')<>'active' THEN
    RAISE EXCEPTION 'out of order subscription changed projection'; END IF;
END $$;

-- A production event cannot consume an unapproved/missing production product mapping.
WITH received AS (
  SELECT private_isg.workspace_provider_event_record('apple','production','event-wrong-env','subscription_state',
    'txn-prod','chain-prod','test.osgb.growth','61000000-0000-4000-8000-000000000001',
    '20000000-0000-0000-0000-000000000001','active',clock_timestamp(),clock_timestamp()+interval '30 days',
    1,'webhook','verified',sha256('prod'::bytea),'server_adapter') body
) SELECT private_isg.workspace_provider_event_process((body->>'inbox_id')::uuid) FROM received;
DO $$ BEGIN
  IF (SELECT outcome_code FROM private_isg.workspace_provider_inbox WHERE provider_event_id='event-wrong-env')<>'PRODUCT_NOT_APPROVED' THEN
    RAISE EXCEPTION 'environment isolation failed'; END IF;
END $$;

-- One consumable transaction grants once; a refund after spend creates debt once.
WITH received AS (
  SELECT private_isg.workspace_provider_event_record('apple','sandbox','event-credit-buy','consumable_purchase',
    'txn-credit-1',NULL,'test.osgb.credits100','61000000-0000-4000-8000-000000000001',
    '20000000-0000-0000-0000-000000000001',NULL,clock_timestamp(),NULL,1,'callback','verified',
    sha256('credit-buy'::bytea),'server_adapter') body
) INSERT INTO billing_state VALUES('credit_inbox',(SELECT body->>'inbox_id' FROM received));
SELECT private_isg.workspace_provider_event_process((SELECT value::uuid FROM billing_state WHERE key='credit_inbox'));
SELECT private_isg.workspace_provider_event_process((SELECT value::uuid FROM billing_state WHERE key='credit_inbox'));
UPDATE private_isg.workspace_wallets SET posted_units=30 WHERE workspace_id='61000000-0000-4000-8000-000000000001';
WITH received AS (
  SELECT private_isg.workspace_provider_event_record('apple','sandbox','event-credit-refund','consumable_refund',
    'txn-credit-1',NULL,'test.osgb.credits100','61000000-0000-4000-8000-000000000001',
    '20000000-0000-0000-0000-000000000001',NULL,clock_timestamp()+interval '1 minute',NULL,2,'webhook','verified',
    sha256('credit-refund'::bytea),'server_adapter') body
) INSERT INTO billing_state VALUES('refund_inbox',(SELECT body->>'inbox_id' FROM received));
SELECT private_isg.workspace_provider_event_process((SELECT value::uuid FROM billing_state WHERE key='refund_inbox'));
SELECT private_isg.workspace_provider_event_process((SELECT value::uuid FROM billing_state WHERE key='refund_inbox'));
DO $$ BEGIN
  IF (SELECT count(*) FROM private_isg.workspace_credit_grants)<>1 OR
     (SELECT count(*) FROM private_isg.workspace_wallet_entries WHERE entry_type='purchase_grant')<>1 OR
     (SELECT count(*) FROM private_isg.workspace_wallet_entries WHERE entry_type='refund_reversal')<>1 OR
     (SELECT posted_units FROM private_isg.workspace_wallets WHERE workspace_id='61000000-0000-4000-8000-000000000001')<>0 OR
     (SELECT debt_units FROM private_isg.workspace_wallets WHERE workspace_id='61000000-0000-4000-8000-000000000001')<>70 THEN
    RAISE EXCEPTION 'credit grant/refund invariant failed'; END IF;
END $$;

-- Finalization ownership is structural and raw provider material is not persisted.
DO $$ BEGIN
  BEGIN
    PERFORM private_isg.workspace_provider_event_record('revenuecat','sandbox','bad-owner','consumable_purchase',
      'bad-owner-txn',NULL,'test.osgb.credits100','61000000-0000-4000-8000-000000000001',
      '20000000-0000-0000-0000-000000000001',NULL,clock_timestamp(),NULL,1,'webhook','verified',
      sha256('bad'::bytea),'server_adapter');
    RAISE EXCEPTION 'EXPECTED_FINALIZATION_OWNER_REJECTION';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
  IF has_table_privilege('authenticated','private_isg.workspace_provider_inbox','SELECT') OR
     has_function_privilege('authenticated','private_isg.workspace_provider_event_process(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'provider boundary grant leak'; END IF;
  RAISE NOTICE 'ok provider verification boundary, duplicate and out-of-order events, environment isolation, single grant, refund debt and finalization owner';
END $$;
