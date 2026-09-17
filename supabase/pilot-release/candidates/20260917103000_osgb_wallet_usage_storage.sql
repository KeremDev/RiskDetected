-- Workspace credit accounting, usage reservation and physical asset metering. NOT DEPLOYED.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';
INSERT INTO private_isg.workspace_rollout(feature) VALUES('workspace_wallet'),('workspace_storage');

CREATE TABLE private_isg.workspace_wallets (
  workspace_id uuid PRIMARY KEY REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  posted_units bigint NOT NULL DEFAULT 0 CHECK(posted_units>=0),
  reserved_units bigint NOT NULL DEFAULT 0 CHECK(reserved_units>=0),
  debt_units bigint NOT NULL DEFAULT 0 CHECK(debt_units>=0),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(reserved_units<=posted_units)
);
CREATE TABLE private_isg.workspace_credit_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  source_kind text NOT NULL CHECK(source_kind IN ('purchase','admin_support','migration')),
  source_reference text NOT NULL CHECK(octet_length(source_reference) BETWEEN 1 AND 300),
  granted_units bigint NOT NULL CHECK(granted_units>0),
  refunded_units bigint NOT NULL DEFAULT 0 CHECK(refunded_units>=0 AND refunded_units<=granted_units),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,source_kind,source_reference)
);
CREATE TABLE private_isg.workspace_wallet_entries (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  entry_key uuid NOT NULL,
  entry_type text NOT NULL CHECK(entry_type IN ('purchase_grant','admin_grant','migration_opening','usage_debit','refund_reversal','debt_repayment','correction')),
  units_delta bigint NOT NULL,
  debt_delta bigint NOT NULL DEFAULT 0,
  source_kind text NOT NULL,
  source_id uuid,
  actor_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,entry_key),
  CHECK(units_delta<>0 OR debt_delta<>0)
);
CREATE INDEX workspace_wallet_timeline ON private_isg.workspace_wallet_entries(workspace_id,created_at,id);

CREATE TABLE private_isg.workspace_credit_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  company_id uuid,
  feature text NOT NULL CHECK(octet_length(feature) BETWEEN 1 AND 80),
  idempotency_key uuid NOT NULL,
  request_hash bytea NOT NULL CHECK(octet_length(request_hash)=32),
  reserved_units bigint NOT NULL CHECK(reserved_units>0),
  settled_units bigint CHECK(settled_units>=0),
  status text NOT NULL CHECK(status IN ('reserved','settled','released','reconcile')),
  period_key text NOT NULL CHECK(period_key ~ '^[0-9]{4}-[0-9]{2}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,idempotency_key),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT
);
CREATE INDEX workspace_reservation_status_idx
  ON private_isg.workspace_credit_reservations(workspace_id,status,created_at,id);

CREATE TABLE private_isg.workspace_usage_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  reservation_id uuid NOT NULL UNIQUE REFERENCES private_isg.workspace_credit_reservations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  company_id uuid,
  feature text NOT NULL,
  model_code text NOT NULL,
  input_units bigint NOT NULL CHECK(input_units>=0),
  output_units bigint NOT NULL CHECK(output_units>=0),
  charged_units bigint NOT NULL CHECK(charged_units>=0),
  pricing_version text NOT NULL CHECK(octet_length(pricing_version) BETWEEN 1 AND 80),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT
);
CREATE INDEX workspace_usage_timeline ON private_isg.workspace_usage_records(workspace_id,created_at,id);

CREATE TABLE private_isg.workspace_file_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  company_id uuid,
  uploaded_by_membership_id uuid NOT NULL,
  source_kind text NOT NULL CHECK(source_kind IN ('upload','generated','derivative','legacy_inventory')),
  bucket text NOT NULL CHECK(octet_length(bucket) BETWEEN 1 AND 100),
  object_path text NOT NULL CHECK(octet_length(object_path) BETWEEN 1 AND 1000),
  object_version text NOT NULL CHECK(octet_length(object_version) BETWEEN 1 AND 200),
  byte_size bigint CHECK(byte_size>0),
  sha256 bytea CHECK(sha256 IS NULL OR octet_length(sha256)=32),
  lifecycle text NOT NULL CHECK(lifecycle IN ('quarantine','active','delete_requested','deleted')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finalized_at timestamptz,
  delete_requested_at timestamptz,
  deleted_at timestamptz,
  UNIQUE(workspace_id,bucket,object_path,object_version),
  FOREIGN KEY(workspace_id,uploaded_by_membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK((lifecycle='active')=(finalized_at IS NOT NULL) OR lifecycle IN ('delete_requested','deleted')),
  CHECK((lifecycle='deleted')=(deleted_at IS NOT NULL))
);
CREATE INDEX workspace_asset_meter_idx ON private_isg.workspace_file_assets(workspace_id,lifecycle,created_at,id);

ALTER TABLE private_isg.workspace_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_credit_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_wallet_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_credit_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_usage_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_file_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_wallets,private_isg.workspace_credit_grants,
  private_isg.workspace_wallet_entries,private_isg.workspace_credit_reservations,
  private_isg.workspace_usage_records,private_isg.workspace_file_assets
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE private_isg.workspace_wallet_entries_id_seq FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_credit_grant(p_entry_key uuid,p_workspace uuid,p_source_kind text,
  p_source_reference text,p_units bigint,p_actor uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE grant_row private_isg.workspace_credit_grants; wallet private_isg.workspace_wallets;
  entry private_isg.workspace_wallet_entries; repaid bigint;
BEGIN
  IF p_entry_key IS NULL OR p_workspace IS NULL OR p_source_kind NOT IN ('purchase','admin_support','migration') OR
     p_source_reference IS NULL OR octet_length(p_source_reference) NOT BETWEEN 1 AND 300 OR p_units<=0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.workspace_wallets(workspace_id) VALUES(p_workspace) ON CONFLICT DO NOTHING;
  SELECT * INTO wallet FROM private_isg.workspace_wallets WHERE workspace_id=p_workspace FOR UPDATE;
  SELECT * INTO entry FROM private_isg.workspace_wallet_entries WHERE workspace_id=p_workspace AND entry_key=p_entry_key;
  IF FOUND THEN RETURN jsonb_build_object('workspace_id',p_workspace,'posted_units',wallet.posted_units,'debt_units',wallet.debt_units,'replayed',true); END IF;
  INSERT INTO private_isg.workspace_credit_grants(workspace_id,source_kind,source_reference,granted_units)
    VALUES(p_workspace,p_source_kind,p_source_reference,p_units) RETURNING * INTO grant_row;
  -- Debt is repaid before new units become spendable.
  repaid:=least(wallet.debt_units,p_units);
  UPDATE private_isg.workspace_wallets SET
    debt_units=debt_units-repaid,
    posted_units=posted_units+(p_units-repaid),version=version+1,updated_at=clock_timestamp()
    WHERE workspace_id=p_workspace RETURNING * INTO wallet;
  INSERT INTO private_isg.workspace_wallet_entries(workspace_id,entry_key,entry_type,units_delta,debt_delta,source_kind,source_id,actor_user_id)
    VALUES(p_workspace,p_entry_key,CASE p_source_kind WHEN 'purchase' THEN 'purchase_grant' WHEN 'admin_support' THEN 'admin_grant' ELSE 'migration_opening' END,
      p_units-repaid,-repaid,p_source_kind,grant_row.id,p_actor);
  RETURN jsonb_build_object('workspace_id',p_workspace,'grant_id',grant_row.id,'posted_units',wallet.posted_units,
    'reserved_units',wallet.reserved_units,'debt_units',wallet.debt_units,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_credit_reserve(p_workspace uuid,p_company uuid,p_feature text,
  p_units bigint,p_idempotency uuid,p_request_hash bytea) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  wallet private_isg.workspace_wallets; prior private_isg.workspace_credit_reservations;
  reservation private_isg.workspace_credit_reservations; period text;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_wallet',true);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],true);
  IF p_company IS NOT NULL THEN PERFORM private_isg.workspace_require_company(p_workspace,p_company,true); END IF;
  IF p_feature IS NULL OR octet_length(p_feature) NOT BETWEEN 1 AND 80 OR p_units<=0 OR
     p_idempotency IS NULL OR p_request_hash IS NULL OR octet_length(p_request_hash)<>32 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO prior FROM private_isg.workspace_credit_reservations
    WHERE workspace_id=p_workspace AND idempotency_key=p_idempotency;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM p_request_hash OR prior.reserved_units<>p_units OR
       prior.feature<>p_feature OR prior.company_id IS DISTINCT FROM p_company THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('reservation_id',prior.id,'status',prior.status,'reserved_units',prior.reserved_units,'replayed',true);
  END IF;
  SELECT * INTO wallet FROM private_isg.workspace_wallets WHERE workspace_id=p_workspace FOR UPDATE;
  IF wallet.workspace_id IS NULL OR wallet.posted_units-wallet.reserved_units-wallet.debt_units<p_units THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INSUFFICIENT_CREDITS'; END IF;
  period:=to_char(clock_timestamp() AT TIME ZONE (SELECT timezone FROM private_isg.workspaces WHERE id=p_workspace),'YYYY-MM');
  INSERT INTO private_isg.workspace_credit_reservations(workspace_id,actor_user_id,membership_id,company_id,
    feature,idempotency_key,request_hash,reserved_units,status,period_key)
    VALUES(p_workspace,actor,member.id,p_company,p_feature,p_idempotency,p_request_hash,p_units,'reserved',period)
    RETURNING * INTO reservation;
  UPDATE private_isg.workspace_wallets SET reserved_units=reserved_units+p_units,version=version+1,
    updated_at=clock_timestamp() WHERE workspace_id=p_workspace;
  RETURN jsonb_build_object('reservation_id',reservation.id,'status','reserved','reserved_units',p_units,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_credit_settle(p_entry_key uuid,p_reservation uuid,p_actual bigint,
  p_input bigint,p_output bigint,p_model text,p_pricing text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE reservation private_isg.workspace_credit_reservations; wallet private_isg.workspace_wallets; usage private_isg.workspace_usage_records;
BEGIN
  IF p_entry_key IS NULL OR p_reservation IS NULL OR p_actual<0 OR p_input<0 OR p_output<0 OR
     p_model IS NULL OR p_pricing IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO reservation FROM private_isg.workspace_credit_reservations WHERE id=p_reservation FOR UPDATE;
  IF reservation.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RESERVATION_NOT_FOUND'; END IF;
  IF reservation.status='settled' THEN
    IF reservation.settled_units<>p_actual THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    SELECT * INTO usage FROM private_isg.workspace_usage_records WHERE reservation_id=p_reservation;
    RETURN jsonb_build_object('reservation_id',p_reservation,'usage_id',usage.id,'charged_units',p_actual,'replayed',true);
  END IF;
  IF reservation.status<>'reserved' OR p_actual>reservation.reserved_units THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RESERVATION_CONFLICT'; END IF;
  SELECT * INTO wallet FROM private_isg.workspace_wallets WHERE workspace_id=reservation.workspace_id FOR UPDATE;
  UPDATE private_isg.workspace_wallets SET reserved_units=reserved_units-reservation.reserved_units,
    posted_units=posted_units-p_actual,version=version+1,updated_at=clock_timestamp()
    WHERE workspace_id=reservation.workspace_id RETURNING * INTO wallet;
  UPDATE private_isg.workspace_credit_reservations SET status='settled',settled_units=p_actual,
    updated_at=clock_timestamp() WHERE id=reservation.id;
  IF p_actual>0 THEN
    INSERT INTO private_isg.workspace_wallet_entries(workspace_id,entry_key,entry_type,units_delta,source_kind,source_id,actor_user_id)
      VALUES(reservation.workspace_id,p_entry_key,'usage_debit',-p_actual,'usage',reservation.id,reservation.actor_user_id);
  END IF;
  INSERT INTO private_isg.workspace_usage_records(workspace_id,reservation_id,actor_user_id,membership_id,company_id,
    feature,model_code,input_units,output_units,charged_units,pricing_version)
    VALUES(reservation.workspace_id,reservation.id,reservation.actor_user_id,reservation.membership_id,reservation.company_id,
      reservation.feature,p_model,p_input,p_output,p_actual,p_pricing) RETURNING * INTO usage;
  RETURN jsonb_build_object('reservation_id',reservation.id,'usage_id',usage.id,'charged_units',p_actual,
    'posted_units',wallet.posted_units,'reserved_units',wallet.reserved_units,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_credit_release(p_reservation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE reservation private_isg.workspace_credit_reservations; wallet private_isg.workspace_wallets;
BEGIN
  SELECT * INTO reservation FROM private_isg.workspace_credit_reservations WHERE id=p_reservation FOR UPDATE;
  IF reservation.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RESERVATION_NOT_FOUND'; END IF;
  SELECT * INTO wallet FROM private_isg.workspace_wallets WHERE workspace_id=reservation.workspace_id FOR UPDATE;
  IF reservation.status='released' THEN RETURN jsonb_build_object('reservation_id',p_reservation,'status','released','replayed',true); END IF;
  IF reservation.status<>'reserved' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RESERVATION_CONFLICT'; END IF;
  UPDATE private_isg.workspace_credit_reservations SET status='released',settled_units=0,updated_at=clock_timestamp() WHERE id=p_reservation;
  UPDATE private_isg.workspace_wallets SET reserved_units=reserved_units-reservation.reserved_units,
    version=version+1,updated_at=clock_timestamp() WHERE workspace_id=reservation.workspace_id;
  RETURN jsonb_build_object('reservation_id',p_reservation,'status','released','replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_credit_refund(p_entry_key uuid,p_grant uuid,p_units bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE grant_row private_isg.workspace_credit_grants; wallet private_isg.workspace_wallets; available bigint; uncovered bigint;
BEGIN
  IF p_entry_key IS NULL OR p_grant IS NULL OR p_units<=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO grant_row FROM private_isg.workspace_credit_grants WHERE id=p_grant FOR UPDATE;
  IF grant_row.id IS NULL OR grant_row.refunded_units+p_units>grant_row.granted_units THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='REFUND_CONFLICT'; END IF;
  IF EXISTS(SELECT 1 FROM private_isg.workspace_wallet_entries WHERE workspace_id=grant_row.workspace_id AND entry_key=p_entry_key) THEN
    SELECT * INTO wallet FROM private_isg.workspace_wallets WHERE workspace_id=grant_row.workspace_id;
    RETURN jsonb_build_object('workspace_id',grant_row.workspace_id,'posted_units',wallet.posted_units,'debt_units',wallet.debt_units,'replayed',true);
  END IF;
  SELECT * INTO wallet FROM private_isg.workspace_wallets WHERE workspace_id=grant_row.workspace_id FOR UPDATE;
  available:=wallet.posted_units-wallet.reserved_units; uncovered:=greatest(0,p_units-available);
  UPDATE private_isg.workspace_wallets SET posted_units=posted_units-least(available,p_units),
    debt_units=debt_units+uncovered,version=version+1,updated_at=clock_timestamp()
    WHERE workspace_id=grant_row.workspace_id RETURNING * INTO wallet;
  UPDATE private_isg.workspace_credit_grants SET refunded_units=refunded_units+p_units WHERE id=grant_row.id;
  INSERT INTO private_isg.workspace_wallet_entries(workspace_id,entry_key,entry_type,units_delta,debt_delta,source_kind,source_id)
    VALUES(grant_row.workspace_id,p_entry_key,'refund_reversal',-least(available,p_units),uncovered,'refund',grant_row.id);
  RETURN jsonb_build_object('workspace_id',grant_row.workspace_id,'posted_units',wallet.posted_units,
    'reserved_units',wallet.reserved_units,'debt_units',wallet.debt_units,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_asset_finalize(p_asset uuid,p_workspace uuid,p_membership uuid,p_company uuid,
  p_source text,p_bucket text,p_path text,p_version text,p_bytes bigint,p_sha bytea) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE asset private_isg.workspace_file_assets;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_storage',true);
  IF p_asset IS NULL OR p_bytes<=0 OR p_sha IS NULL OR octet_length(p_sha)<>32 OR
     p_source NOT IN ('upload','generated','derivative','legacy_inventory') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_company IS NULL THEN PERFORM private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],true);
  ELSE PERFORM private_isg.workspace_require_company(p_workspace,p_company,true); END IF;
  SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=p_asset FOR UPDATE;
  IF FOUND THEN
    IF ROW(asset.workspace_id,asset.uploaded_by_membership_id,asset.company_id,asset.bucket,asset.object_path,asset.object_version,asset.byte_size,asset.sha256)
      IS DISTINCT FROM ROW(p_workspace,p_membership,p_company,p_bucket,p_path,p_version,p_bytes,p_sha) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('asset_id',asset.id,'lifecycle',asset.lifecycle,'byte_size',asset.byte_size,'replayed',true);
  END IF;
  INSERT INTO private_isg.workspace_file_assets(id,workspace_id,company_id,uploaded_by_membership_id,source_kind,
    bucket,object_path,object_version,byte_size,sha256,lifecycle,finalized_at)
    VALUES(p_asset,p_workspace,p_company,p_membership,p_source,p_bucket,p_path,p_version,p_bytes,p_sha,'active',clock_timestamp())
    RETURNING * INTO asset;
  RETURN jsonb_build_object('asset_id',asset.id,'lifecycle',asset.lifecycle,'byte_size',asset.byte_size,'replayed',false);
END $$;

CREATE FUNCTION public.isg_workspace_credit_reserve_v1(p_workspace uuid,p_company uuid,p_feature text,p_units bigint,
  p_idempotency uuid,p_request_hash bytea) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_credit_reserve(p_workspace,p_company,p_feature,p_units,p_idempotency,p_request_hash) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_credit_grant(uuid,uuid,text,text,bigint,uuid),
  private_isg.workspace_credit_reserve(uuid,uuid,text,bigint,uuid,bytea),
  private_isg.workspace_credit_settle(uuid,uuid,bigint,bigint,bigint,text,text),
  private_isg.workspace_credit_release(uuid),private_isg.workspace_credit_refund(uuid,uuid,bigint),
  private_isg.workspace_asset_finalize(uuid,uuid,uuid,uuid,text,text,text,text,bigint,bytea),
  public.isg_workspace_credit_reserve_v1(uuid,uuid,text,bigint,uuid,bytea)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_credit_reserve(uuid,uuid,text,bigint,uuid,bytea),
  public.isg_workspace_credit_reserve_v1(uuid,uuid,text,bigint,uuid,bytea) TO authenticated;
