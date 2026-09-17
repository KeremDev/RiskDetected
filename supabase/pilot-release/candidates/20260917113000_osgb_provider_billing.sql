-- Verified, provider-neutral OSGB billing inbox and projection. NOT DEPLOYED.
-- Verification happens in the provider adapter. This layer never accepts a raw
-- receipt/token and never guesses a product, price, plan or finalization owner.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

INSERT INTO private_isg.workspace_rollout(feature) VALUES('workspace_billing');

CREATE TABLE private_isg.workspace_billing_products (
  provider text NOT NULL CHECK(provider IN ('apple','google','revenuecat')),
  environment text NOT NULL CHECK(environment IN ('sandbox','production')),
  product_id text NOT NULL CHECK(octet_length(product_id) BETWEEN 3 AND 200),
  product_kind text NOT NULL CHECK(product_kind IN ('subscription','credit_pack')),
  plan_code text REFERENCES private_isg.workspace_plan_catalog(plan_code),
  credit_units bigint CHECK(credit_units>0),
  catalog_version integer NOT NULL CHECK(catalog_version>0),
  approved boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(provider,environment,product_id),
  CHECK((product_kind='subscription')=(plan_code IS NOT NULL)),
  CHECK((product_kind='credit_pack')=(credit_units IS NOT NULL))
);

CREATE TABLE private_isg.workspace_provider_inbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL CHECK(provider IN ('apple','google','revenuecat')),
  environment text NOT NULL CHECK(environment IN ('sandbox','production')),
  provider_event_id text NOT NULL CHECK(octet_length(provider_event_id) BETWEEN 1 AND 300),
  event_kind text NOT NULL CHECK(event_kind IN ('subscription_state','consumable_purchase','consumable_refund')),
  transaction_id text NOT NULL CHECK(octet_length(transaction_id) BETWEEN 1 AND 300),
  subscription_chain_id text,
  product_id text NOT NULL CHECK(octet_length(product_id) BETWEEN 3 AND 200),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  purchaser_user_id uuid NOT NULL,
  lifecycle_state text CHECK(lifecycle_state IN ('pending','active','grace','canceled_active','hold','expired','revoked','verification_failed')),
  effective_at timestamptz NOT NULL,
  valid_until timestamptz,
  sequence_no bigint NOT NULL CHECK(sequence_no>=0),
  source text NOT NULL CHECK(source IN ('webhook','callback','restore','reconciliation')),
  verification_status text NOT NULL CHECK(verification_status IN ('verified','rejected')),
  payload_hash bytea NOT NULL CHECK(octet_length(payload_hash)=32),
  finalization_owner text NOT NULL CHECK(finalization_owner IN ('revenuecat','server_adapter')),
  state text NOT NULL DEFAULT 'received' CHECK(state IN ('received','applied','ignored','rejected')),
  outcome_code text,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  processed_at timestamptz,
  UNIQUE(provider,environment,provider_event_id),
  CHECK(subscription_chain_id IS NULL OR octet_length(subscription_chain_id) BETWEEN 1 AND 300),
  CHECK(event_kind<>'subscription_state' OR subscription_chain_id IS NOT NULL),
  CHECK(event_kind='subscription_state' OR lifecycle_state IS NULL),
  CHECK(valid_until IS NULL OR valid_until>effective_at),
  CHECK((provider='revenuecat')=(finalization_owner='revenuecat')),
  CHECK((state IN ('applied','ignored','rejected'))=(processed_at IS NOT NULL))
);
CREATE INDEX workspace_provider_inbox_queue
  ON private_isg.workspace_provider_inbox(state,received_at,id) WHERE state='received';
CREATE INDEX workspace_provider_inbox_transaction
  ON private_isg.workspace_provider_inbox(provider,environment,transaction_id,effective_at,id);

CREATE TABLE private_isg.workspace_billing_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  environment text NOT NULL,
  transaction_id text NOT NULL,
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  product_id text NOT NULL,
  product_kind text NOT NULL CHECK(product_kind IN ('subscription','credit_pack')),
  purchaser_user_id uuid NOT NULL,
  purchase_event_id uuid NOT NULL REFERENCES private_isg.workspace_provider_inbox(id) ON DELETE RESTRICT,
  state text NOT NULL CHECK(state IN ('verified','applied','refunded','revoked')),
  grant_id uuid REFERENCES private_isg.workspace_credit_grants(id) ON DELETE RESTRICT,
  granted_units bigint CHECK(granted_units>0),
  refund_event_id uuid REFERENCES private_isg.workspace_provider_inbox(id) ON DELETE RESTRICT,
  grant_entry_key uuid NOT NULL DEFAULT gen_random_uuid(),
  refund_entry_key uuid NOT NULL DEFAULT gen_random_uuid(),
  effective_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(provider,environment,transaction_id),
  CHECK((product_kind='credit_pack')=(granted_units IS NOT NULL))
);
CREATE INDEX workspace_billing_transaction_workspace
  ON private_isg.workspace_billing_transactions(workspace_id,effective_at,id);

CREATE TABLE private_isg.workspace_subscription_projection (
  provider text NOT NULL,
  environment text NOT NULL,
  subscription_chain_id text NOT NULL,
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  binding_id uuid NOT NULL REFERENCES private_isg.workspace_subscription_bindings(id) ON DELETE RESTRICT,
  last_event_id uuid NOT NULL REFERENCES private_isg.workspace_provider_inbox(id) ON DELETE RESTRICT,
  applied_effective_at timestamptz NOT NULL,
  applied_sequence_no bigint NOT NULL CHECK(applied_sequence_no>=0),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(provider,environment,subscription_chain_id)
);

ALTER TABLE private_isg.workspace_billing_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_provider_inbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_billing_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_subscription_projection ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_billing_products,private_isg.workspace_provider_inbox,
  private_isg.workspace_billing_transactions,private_isg.workspace_subscription_projection
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_provider_event_record(p_provider text,p_environment text,
  p_event_id text,p_event_kind text,p_transaction text,p_chain text,p_product text,p_workspace uuid,
  p_purchaser uuid,p_lifecycle text,p_effective_at timestamptz,p_valid_until timestamptz,
  p_sequence bigint,p_source text,p_verification text,p_payload_hash bytea,p_finalization_owner text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE prior private_isg.workspace_provider_inbox; created private_isg.workspace_provider_inbox;
BEGIN
  IF p_provider NOT IN ('apple','google','revenuecat') OR p_environment NOT IN ('sandbox','production') OR
     p_event_id IS NULL OR octet_length(p_event_id) NOT BETWEEN 1 AND 300 OR
     p_event_kind NOT IN ('subscription_state','consumable_purchase','consumable_refund') OR
     p_transaction IS NULL OR octet_length(p_transaction) NOT BETWEEN 1 AND 300 OR
     p_product IS NULL OR octet_length(p_product) NOT BETWEEN 3 AND 200 OR p_workspace IS NULL OR
     p_purchaser IS NULL OR p_effective_at IS NULL OR p_sequence IS NULL OR p_sequence<0 OR
     p_source NOT IN ('webhook','callback','restore','reconciliation') OR
     p_verification NOT IN ('verified','rejected') OR p_payload_hash IS NULL OR octet_length(p_payload_hash)<>32 OR
     p_finalization_owner NOT IN ('revenuecat','server_adapter') OR
     (p_provider='revenuecat') IS DISTINCT FROM (p_finalization_owner='revenuecat') OR
     (p_event_kind='subscription_state' AND (p_chain IS NULL OR p_lifecycle NOT IN
       ('pending','active','grace','canceled_active','hold','expired','revoked','verification_failed'))) OR
     (p_event_kind<>'subscription_state' AND p_lifecycle IS NOT NULL) OR
     (p_valid_until IS NOT NULL AND p_valid_until<=p_effective_at) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO prior FROM private_isg.workspace_provider_inbox
    WHERE provider=p_provider AND environment=p_environment AND provider_event_id=p_event_id;
  IF FOUND THEN
    IF ROW(prior.event_kind,prior.transaction_id,prior.subscription_chain_id,prior.product_id,
      prior.workspace_id,prior.purchaser_user_id,prior.lifecycle_state,prior.effective_at,prior.valid_until,
      prior.sequence_no,prior.source,prior.verification_status,prior.payload_hash,prior.finalization_owner)
      IS DISTINCT FROM ROW(p_event_kind,p_transaction,p_chain,p_product,p_workspace,p_purchaser,
      p_lifecycle,p_effective_at,p_valid_until,p_sequence,p_source,p_verification,p_payload_hash,p_finalization_owner) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PROVIDER_EVENT_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'inbox_id',prior.id,'state',prior.state,'replayed',true);
  END IF;
  INSERT INTO private_isg.workspace_provider_inbox(provider,environment,provider_event_id,event_kind,
    transaction_id,subscription_chain_id,product_id,workspace_id,purchaser_user_id,lifecycle_state,
    effective_at,valid_until,sequence_no,source,verification_status,payload_hash,finalization_owner,
    state,outcome_code,processed_at)
    VALUES(p_provider,p_environment,p_event_id,p_event_kind,p_transaction,p_chain,p_product,p_workspace,
      p_purchaser,p_lifecycle,p_effective_at,p_valid_until,p_sequence,p_source,p_verification,p_payload_hash,
      p_finalization_owner,CASE p_verification WHEN 'rejected' THEN 'rejected' ELSE 'received' END,
      CASE p_verification WHEN 'rejected' THEN 'VERIFICATION_REJECTED' END,
      CASE p_verification WHEN 'rejected' THEN clock_timestamp() END)
    RETURNING * INTO created;
  RETURN jsonb_build_object('schema_version',1,'inbox_id',created.id,'state',created.state,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_recompute_store_entitlement(p_workspace uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE selected record; current_entitlement private_isg.workspace_entitlements;
BEGIN
  SELECT b.id binding_id,p.plan_code,c.max_experts,b.status,b.valid_until INTO selected
  FROM private_isg.workspace_subscription_bindings b
  JOIN private_isg.workspace_billing_products p ON p.provider=b.provider AND p.environment=b.environment
    AND p.product_id=b.product_id AND p.product_kind='subscription' AND p.approved AND p.active
  JOIN private_isg.workspace_plan_catalog c ON c.plan_code=p.plan_code AND c.active
  WHERE b.workspace_id=p_workspace AND b.status IN ('active','grace','canceled_active')
    AND (b.valid_until IS NULL OR b.valid_until>clock_timestamp())
  ORDER BY c.max_experts DESC,b.effective_at DESC,b.id LIMIT 1;
  SELECT * INTO current_entitlement FROM private_isg.workspace_entitlements WHERE workspace_id=p_workspace FOR UPDATE;
  IF selected.binding_id IS NOT NULL THEN
    INSERT INTO private_isg.workspace_entitlements(workspace_id,plan_code,source_binding_id,source_kind,
      status,max_experts,valid_until)
      VALUES(p_workspace,selected.plan_code,selected.binding_id,'store',selected.status,
        selected.max_experts,selected.valid_until)
    ON CONFLICT(workspace_id) DO UPDATE SET plan_code=EXCLUDED.plan_code,
      source_binding_id=EXCLUDED.source_binding_id,source_kind='store',status=EXCLUDED.status,
      max_experts=EXCLUDED.max_experts,valid_until=EXCLUDED.valid_until,
      version=private_isg.workspace_entitlements.version+1,updated_at=clock_timestamp()
    WHERE private_isg.workspace_entitlements.source_kind='store';
    UPDATE private_isg.workspaces SET status='active',version=version+1,updated_at=clock_timestamp()
      WHERE id=p_workspace AND status='pending_purchase';
    RETURN jsonb_build_object('active',true,'plan_code',selected.plan_code,'max_experts',selected.max_experts,
      'source_binding_id',selected.binding_id);
  END IF;
  IF current_entitlement.workspace_id IS NOT NULL AND current_entitlement.source_kind='store' THEN
    UPDATE private_isg.workspace_entitlements SET status='expired',valid_until=coalesce(valid_until,clock_timestamp()),
      version=version+1,updated_at=clock_timestamp() WHERE workspace_id=p_workspace;
  END IF;
  RETURN jsonb_build_object('active',false);
END $$;

CREATE FUNCTION private_isg.workspace_provider_event_process(p_inbox uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE event private_isg.workspace_provider_inbox; product private_isg.workspace_billing_products;
  projection private_isg.workspace_subscription_projection; binding private_isg.workspace_subscription_bindings;
  transaction_row private_isg.workspace_billing_transactions; grant_result jsonb; entitlement jsonb; result jsonb;
BEGIN
  SELECT * INTO event FROM private_isg.workspace_provider_inbox WHERE id=p_inbox FOR UPDATE;
  IF event.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EVENT_NOT_FOUND'; END IF;
  IF event.state<>'received' THEN
    RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state',event.state,
      'outcome_code',event.outcome_code,'replayed',true); END IF;
  SELECT * INTO product FROM private_isg.workspace_billing_products
    WHERE provider=event.provider AND environment=event.environment AND product_id=event.product_id
      AND approved AND active FOR SHARE;
  IF product.product_id IS NULL THEN
    UPDATE private_isg.workspace_provider_inbox SET state='rejected',outcome_code='PRODUCT_NOT_APPROVED',
      processed_at=clock_timestamp() WHERE id=event.id;
    RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state','rejected',
      'outcome_code','PRODUCT_NOT_APPROVED','replayed',false);
  END IF;
  IF (event.event_kind='subscription_state') IS DISTINCT FROM (product.product_kind='subscription') THEN
    UPDATE private_isg.workspace_provider_inbox SET state='rejected',outcome_code='PRODUCT_KIND_MISMATCH',
      processed_at=clock_timestamp() WHERE id=event.id;
    RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state','rejected',
      'outcome_code','PRODUCT_KIND_MISMATCH','replayed',false);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('osgb-provider:'||event.provider||':'||event.environment||':'||event.transaction_id,0));
  IF event.event_kind='subscription_state' THEN
    SELECT * INTO projection FROM private_isg.workspace_subscription_projection
      WHERE provider=event.provider AND environment=event.environment
        AND subscription_chain_id=event.subscription_chain_id FOR UPDATE;
    IF projection.subscription_chain_id IS NOT NULL AND projection.workspace_id<>event.workspace_id THEN
      UPDATE private_isg.workspace_provider_inbox SET state='rejected',outcome_code='PURCHASE_OWNED_ELSEWHERE',
        processed_at=clock_timestamp() WHERE id=event.id;
      RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state','rejected',
        'outcome_code','PURCHASE_OWNED_ELSEWHERE','replayed',false);
    END IF;
    IF projection.subscription_chain_id IS NOT NULL AND
       (event.effective_at,event.sequence_no)<=(projection.applied_effective_at,projection.applied_sequence_no) THEN
      UPDATE private_isg.workspace_provider_inbox SET state='ignored',outcome_code='OUT_OF_ORDER',
        processed_at=clock_timestamp() WHERE id=event.id;
      RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state','ignored',
        'outcome_code','OUT_OF_ORDER','replayed',false);
    END IF;
    SELECT * INTO binding FROM private_isg.workspace_subscription_bindings
      WHERE provider=event.provider AND environment=event.environment
        AND subscription_chain_id=event.subscription_chain_id FOR UPDATE;
    IF binding.id IS NOT NULL AND binding.workspace_id<>event.workspace_id THEN
      UPDATE private_isg.workspace_provider_inbox SET state='rejected',outcome_code='PURCHASE_OWNED_ELSEWHERE',
        processed_at=clock_timestamp() WHERE id=event.id;
      RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state','rejected',
        'outcome_code','PURCHASE_OWNED_ELSEWHERE','replayed',false);
    END IF;
    IF binding.id IS NULL THEN
      INSERT INTO private_isg.workspace_subscription_bindings(workspace_id,provider,environment,product_id,
        subscription_chain_id,purchaser_user_id,status,effective_at,valid_until)
        VALUES(event.workspace_id,event.provider,event.environment,event.product_id,event.subscription_chain_id,
          event.purchaser_user_id,event.lifecycle_state,event.effective_at,event.valid_until) RETURNING * INTO binding;
    ELSE
      UPDATE private_isg.workspace_subscription_bindings SET product_id=event.product_id,
        purchaser_user_id=event.purchaser_user_id,status=event.lifecycle_state,effective_at=event.effective_at,
        valid_until=event.valid_until,version=version+1,updated_at=clock_timestamp()
        WHERE id=binding.id RETURNING * INTO binding;
    END IF;
    INSERT INTO private_isg.workspace_subscription_projection(provider,environment,subscription_chain_id,
      workspace_id,binding_id,last_event_id,applied_effective_at,applied_sequence_no)
      VALUES(event.provider,event.environment,event.subscription_chain_id,event.workspace_id,binding.id,event.id,
        event.effective_at,event.sequence_no)
      ON CONFLICT(provider,environment,subscription_chain_id) DO UPDATE SET
        binding_id=EXCLUDED.binding_id,last_event_id=EXCLUDED.last_event_id,
        applied_effective_at=EXCLUDED.applied_effective_at,applied_sequence_no=EXCLUDED.applied_sequence_no,
        version=private_isg.workspace_subscription_projection.version+1,updated_at=clock_timestamp();
    entitlement:=private_isg.workspace_recompute_store_entitlement(event.workspace_id);
    result:=jsonb_build_object('binding_id',binding.id,'lifecycle_state',binding.status,'entitlement',entitlement);
  ELSIF event.event_kind='consumable_purchase' THEN
    SELECT * INTO transaction_row FROM private_isg.workspace_billing_transactions
      WHERE provider=event.provider AND environment=event.environment AND transaction_id=event.transaction_id FOR UPDATE;
    IF transaction_row.id IS NOT NULL AND transaction_row.workspace_id<>event.workspace_id THEN
      UPDATE private_isg.workspace_provider_inbox SET state='rejected',outcome_code='PURCHASE_OWNED_ELSEWHERE',
        processed_at=clock_timestamp() WHERE id=event.id;
      RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state','rejected',
        'outcome_code','PURCHASE_OWNED_ELSEWHERE','replayed',false);
    END IF;
    IF transaction_row.id IS NULL THEN
      INSERT INTO private_isg.workspace_billing_transactions(provider,environment,transaction_id,workspace_id,
        product_id,product_kind,purchaser_user_id,purchase_event_id,state,granted_units,effective_at)
        VALUES(event.provider,event.environment,event.transaction_id,event.workspace_id,event.product_id,
          'credit_pack',event.purchaser_user_id,event.id,'verified',product.credit_units,event.effective_at)
        RETURNING * INTO transaction_row;
    END IF;
    grant_result:=private_isg.workspace_credit_grant(transaction_row.grant_entry_key,event.workspace_id,'purchase',
      event.provider||':'||event.environment||':'||event.transaction_id,product.credit_units,event.purchaser_user_id);
    UPDATE private_isg.workspace_billing_transactions SET state='applied',grant_id=(grant_result->>'grant_id')::uuid,
      updated_at=clock_timestamp() WHERE id=transaction_row.id RETURNING * INTO transaction_row;
    result:=jsonb_build_object('transaction_id',transaction_row.id,'grant_id',transaction_row.grant_id,
      'granted_units',transaction_row.granted_units,'wallet',grant_result);
  ELSE
    SELECT * INTO transaction_row FROM private_isg.workspace_billing_transactions
      WHERE provider=event.provider AND environment=event.environment AND transaction_id=event.transaction_id FOR UPDATE;
    IF transaction_row.id IS NULL OR transaction_row.workspace_id<>event.workspace_id OR
       transaction_row.product_id<>event.product_id OR transaction_row.grant_id IS NULL THEN
      UPDATE private_isg.workspace_provider_inbox SET state='rejected',outcome_code='PURCHASE_NOT_FOUND',
        processed_at=clock_timestamp() WHERE id=event.id;
      RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state','rejected',
        'outcome_code','PURCHASE_NOT_FOUND','replayed',false);
    END IF;
    grant_result:=private_isg.workspace_credit_refund(transaction_row.refund_entry_key,
      transaction_row.grant_id,transaction_row.granted_units);
    UPDATE private_isg.workspace_billing_transactions SET state='refunded',refund_event_id=event.id,
      updated_at=clock_timestamp() WHERE id=transaction_row.id RETURNING * INTO transaction_row;
    result:=jsonb_build_object('transaction_id',transaction_row.id,'state','refunded','wallet',grant_result);
  END IF;
  UPDATE private_isg.workspace_provider_inbox SET state='applied',outcome_code='APPLIED',
    processed_at=clock_timestamp() WHERE id=event.id;
  INSERT INTO private_isg.workspace_audit(workspace_id,actor_user_id,action,entity_type,entity_id,
    after_state,correlation_id) VALUES(event.workspace_id,event.purchaser_user_id,'provider_event.applied',
      CASE event.event_kind WHEN 'subscription_state' THEN 'subscription' ELSE 'wallet' END,event.id,result,event.id);
  INSERT INTO private_isg.workspace_outbox(workspace_id,event_type,aggregate_type,aggregate_id,
    aggregate_version,payload,correlation_id) VALUES(event.workspace_id,'workspace.provider_event.applied.v1',
      CASE event.event_kind WHEN 'subscription_state' THEN 'subscription' ELSE 'wallet' END,event.id,0,result,event.id);
  RETURN jsonb_build_object('schema_version',1,'inbox_id',event.id,'state','applied',
    'outcome_code','APPLIED','result',result,'replayed',false);
END $$;

REVOKE ALL ON FUNCTION private_isg.workspace_provider_event_record(text,text,text,text,text,text,text,uuid,uuid,text,timestamptz,timestamptz,bigint,text,text,bytea,text),
  private_isg.workspace_recompute_store_entitlement(uuid),private_isg.workspace_provider_event_process(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_provider_event_record(text,text,text,text,text,text,text,uuid,uuid,text,timestamptz,timestamptz,bigint,text,text,bytea,text),
  private_isg.workspace_provider_event_process(uuid) TO service_role;
