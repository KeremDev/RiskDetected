-- Workspace-bound purchase intents and verified provider reconciliation. NOT DEPLOYED.
-- No provider receipt/token is persisted. The only credential stored is a hash
-- of this app's short-lived intent token; entitlement comes from the verified inbox.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE TABLE private_isg.workspace_purchase_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  membership_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  permission_revision bigint NOT NULL CHECK(permission_revision>=0),
  provider text NOT NULL CHECK(provider IN ('apple','google','revenuecat')),
  environment text NOT NULL CHECK(environment IN ('sandbox','production')),
  product_id text NOT NULL,
  product_kind text NOT NULL CHECK(product_kind IN ('subscription','credit_pack')),
  idempotency_key uuid NOT NULL,
  request_hash bytea NOT NULL CHECK(octet_length(request_hash)=32),
  intent_token_hash bytea NOT NULL UNIQUE CHECK(octet_length(intent_token_hash)=32),
  state text NOT NULL DEFAULT 'open' CHECK(state IN ('open','verification_pending','verified','rejected','expired')),
  provider_inbox_id uuid UNIQUE REFERENCES private_isg.workspace_provider_inbox(id) ON DELETE RESTRICT,
  outcome_code text,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  UNIQUE(workspace_id,idempotency_key),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(expires_at>created_at),
  CHECK((state IN ('verified','rejected'))=(completed_at IS NOT NULL)),
  CHECK(state='open' OR provider_inbox_id IS NOT NULL OR state='expired')
);
CREATE INDEX workspace_purchase_intent_status
  ON private_isg.workspace_purchase_intents(workspace_id,state,created_at,id);
ALTER TABLE private_isg.workspace_purchase_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_purchase_intents FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_purchase_open(p_workspace uuid,p_provider text,p_environment text,
  p_product text,p_idempotency uuid,p_request_hash bytea,p_expires_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  product private_isg.workspace_billing_products; prior private_isg.workspace_purchase_intents;
  intent private_isg.workspace_purchase_intents; token text;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_billing',true);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner'],false);
  IF p_idempotency IS NULL OR p_request_hash IS NULL OR octet_length(p_request_hash)<>32 OR
     p_expires_at IS NULL OR p_expires_at<=clock_timestamp()+interval '5 minutes' OR
     p_expires_at>clock_timestamp()+interval '1 hour' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO product FROM private_isg.workspace_billing_products
    WHERE provider=p_provider AND environment=p_environment AND product_id=p_product
      AND approved AND active FOR SHARE;
  IF product.product_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PRODUCT_NOT_APPROVED'; END IF;
  SELECT * INTO prior FROM private_isg.workspace_purchase_intents
    WHERE workspace_id=p_workspace AND idempotency_key=p_idempotency;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM p_request_hash OR
       ROW(prior.provider,prior.environment,prior.product_id,prior.expires_at)
       IS DISTINCT FROM ROW(p_provider,p_environment,p_product,p_expires_at) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'intent_id',prior.id,'workspace_id',prior.workspace_id,
      'state',prior.state,'provider',prior.provider,'environment',prior.environment,
      'product_id',prior.product_id,'product_kind',prior.product_kind,'expires_at',prior.expires_at,
      'credential_returned',false,'replayed',true);
  END IF;
  token:=private_isg.workspace_random_token();
  INSERT INTO private_isg.workspace_purchase_intents(workspace_id,membership_id,actor_user_id,
    permission_revision,provider,environment,product_id,product_kind,idempotency_key,request_hash,
    intent_token_hash,expires_at) VALUES(p_workspace,member.id,actor,member.permission_revision,
      product.provider,product.environment,product.product_id,product.product_kind,p_idempotency,
      p_request_hash,sha256(convert_to(token,'UTF8')),p_expires_at) RETURNING * INTO intent;
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'workspace_id',intent.workspace_id,
    'state',intent.state,'provider',intent.provider,'environment',intent.environment,
    'product_id',intent.product_id,'product_kind',intent.product_kind,'plan_code',product.plan_code,
    'credit_units',product.credit_units,'catalog_version',product.catalog_version,
    'expires_at',intent.expires_at,'intent_token',token,'credential_returned',true,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_purchase_record_verified(p_intent_token text,p_event_id text,
  p_transaction text,p_chain text,p_lifecycle text,p_effective_at timestamptz,p_valid_until timestamptz,
  p_sequence bigint,p_source text,p_verification text,p_payload_hash bytea,p_finalization_owner text,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE clean_token text; intent private_isg.workspace_purchase_intents;
  member private_isg.workspace_memberships; event_kind text; recorded jsonb;
BEGIN
  clean_token:=private_isg.workspace_text(p_intent_token,128);
  IF clean_token !~ '^[0-9a-f]{64}$' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent FROM private_isg.workspace_purchase_intents
    WHERE intent_token_hash=sha256(convert_to(clean_token,'UTF8')) FOR UPDATE;
  IF intent.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PURCHASE_INTENT_INVALID'; END IF;
  IF intent.state IN ('verified','rejected','verification_pending') THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'state',intent.state,
      'provider_inbox_id',intent.provider_inbox_id,'replayed',true); END IF;
  IF intent.state<>'open' OR intent.expires_at<=p_now THEN
    UPDATE private_isg.workspace_purchase_intents SET state='expired',updated_at=clock_timestamp()
      WHERE id=intent.id AND state='open';
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PURCHASE_INTENT_EXPIRED'; END IF;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=intent.workspace_id AND id=intent.membership_id FOR SHARE;
  IF member.id IS NULL OR member.user_id<>intent.actor_user_id OR member.status<>'active' OR
     member.role<>'owner' OR member.permission_revision<>intent.permission_revision THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PURCHASE_AUTHORITY_REVOKED'; END IF;
  event_kind:=CASE intent.product_kind WHEN 'subscription' THEN 'subscription_state' ELSE 'consumable_purchase' END;
  recorded:=private_isg.workspace_provider_event_record(intent.provider,intent.environment,p_event_id,
    event_kind,p_transaction,CASE WHEN intent.product_kind='subscription' THEN p_chain END,intent.product_id,
    intent.workspace_id,intent.actor_user_id,CASE WHEN intent.product_kind='subscription' THEN p_lifecycle END,
    p_effective_at,p_valid_until,p_sequence,p_source,p_verification,p_payload_hash,p_finalization_owner);
  UPDATE private_isg.workspace_purchase_intents SET state='verification_pending',
    provider_inbox_id=(recorded->>'inbox_id')::uuid,updated_at=clock_timestamp() WHERE id=intent.id;
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'state','verification_pending',
    'provider_inbox_id',recorded->>'inbox_id','event_state',recorded->>'state','replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_purchase_reconcile(p_intent uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE intent private_isg.workspace_purchase_intents; inbox private_isg.workspace_provider_inbox;
  processed jsonb; final_state text;
BEGIN
  IF p_intent IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent FROM private_isg.workspace_purchase_intents WHERE id=p_intent FOR UPDATE;
  IF intent.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PURCHASE_INTENT_INVALID'; END IF;
  IF intent.state IN ('verified','rejected') THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'state',intent.state,
      'outcome_code',intent.outcome_code,'replayed',true); END IF;
  IF intent.state<>'verification_pending' OR intent.provider_inbox_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PURCHASE_NOT_READY'; END IF;
  processed:=private_isg.workspace_provider_event_process(intent.provider_inbox_id);
  SELECT * INTO inbox FROM private_isg.workspace_provider_inbox WHERE id=intent.provider_inbox_id;
  IF inbox.state IN ('received','processing') THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'state','verification_pending',
      'provider_state',inbox.state,'replayed',false); END IF;
  final_state:=CASE WHEN inbox.state='applied' THEN 'verified' ELSE 'rejected' END;
  UPDATE private_isg.workspace_purchase_intents SET state=final_state,outcome_code=inbox.outcome_code,
    completed_at=p_now,updated_at=clock_timestamp() WHERE id=intent.id RETURNING * INTO intent;
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'state',intent.state,
    'provider_state',inbox.state,'outcome_code',inbox.outcome_code,'provider_result',processed,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_purchase_get(p_workspace uuid,p_intent uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; intent private_isg.workspace_purchase_intents;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_billing',false);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner'],false);
  SELECT * INTO intent FROM private_isg.workspace_purchase_intents
    WHERE id=p_intent AND workspace_id=p_workspace AND actor_user_id=member.user_id;
  IF intent.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent.id,'workspace_id',intent.workspace_id,
    'provider',intent.provider,'environment',intent.environment,'product_id',intent.product_id,
    'product_kind',intent.product_kind,'state',intent.state,'outcome_code',intent.outcome_code,
    'expires_at',intent.expires_at,'completed_at',intent.completed_at);
END $$;

CREATE FUNCTION public.isg_workspace_purchase_open_v1(p_workspace uuid,p_provider text,p_environment text,
  p_product text,p_idempotency uuid,p_request_hash bytea,p_expires_at timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_purchase_open(
  p_workspace,p_provider,p_environment,p_product,p_idempotency,p_request_hash,p_expires_at) $$;
CREATE FUNCTION public.isg_workspace_purchase_get_v1(p_workspace uuid,p_intent uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_purchase_get(p_workspace,p_intent) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_purchase_open(uuid,text,text,text,uuid,bytea,timestamptz),
  private_isg.workspace_purchase_record_verified(text,text,text,text,text,timestamptz,timestamptz,bigint,text,text,bytea,text,timestamptz),
  private_isg.workspace_purchase_reconcile(uuid,timestamptz),private_isg.workspace_purchase_get(uuid,uuid),
  public.isg_workspace_purchase_open_v1(uuid,text,text,text,uuid,bytea,timestamptz),
  public.isg_workspace_purchase_get_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_purchase_open(uuid,text,text,text,uuid,bytea,timestamptz),
  private_isg.workspace_purchase_get(uuid,uuid),
  public.isg_workspace_purchase_open_v1(uuid,text,text,text,uuid,bytea,timestamptz),
  public.isg_workspace_purchase_get_v1(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION
  private_isg.workspace_purchase_record_verified(text,text,text,text,text,timestamptz,timestamptz,bigint,text,text,bytea,text,timestamptz),
  private_isg.workspace_purchase_reconcile(uuid,timestamptz) TO service_role;
NOTIFY pgrst,'reload schema';
