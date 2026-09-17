-- Optional per-member monthly AI credit budgets. NOT DEPLOYED.
-- Missing quota means no member-specific cap; the workspace wallet still applies.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE TABLE private_isg.workspace_member_credit_quotas (
  workspace_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  period_key text NOT NULL CHECK(period_key ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  limit_units bigint NOT NULL CHECK(limit_units>=0),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(workspace_id,membership_id,period_key),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT
);
ALTER TABLE private_isg.workspace_member_credit_quotas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_member_credit_quotas FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_member_quota_set(p_mutation uuid,p_workspace uuid,p_membership uuid,
  p_period text,p_limit bigint,p_expected bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  target private_isg.workspace_memberships; quota private_isg.workspace_member_credit_quotas;
  fingerprint bytea; replay jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_wallet',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  IF p_mutation IS NULL OR p_membership IS NULL OR p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' OR
     p_limit IS NULL OR p_limit<0 OR p_expected IS NULL OR p_expected<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO target FROM private_isg.workspace_memberships
    WHERE workspace_id=p_workspace AND id=p_membership FOR SHARE;
  IF target.id IS NULL OR target.status<>'active' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_membership,p_period,p_limit,p_expected)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'member.quota.set',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO quota FROM private_isg.workspace_member_credit_quotas
    WHERE workspace_id=p_workspace AND membership_id=p_membership AND period_key=p_period FOR UPDATE;
  IF quota.membership_id IS NULL THEN
    IF p_expected<>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    INSERT INTO private_isg.workspace_member_credit_quotas(workspace_id,membership_id,period_key,
      limit_units,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_membership,p_period,p_limit,actor,actor) RETURNING * INTO quota;
  ELSE
    IF quota.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    UPDATE private_isg.workspace_member_credit_quotas SET limit_units=p_limit,version=version+1,
      updated_by_user_id=actor,updated_at=clock_timestamp()
      WHERE workspace_id=p_workspace AND membership_id=p_membership AND period_key=p_period
      RETURNING * INTO quota;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'membership_id',p_membership,
    'period_key',p_period,'limit_units',quota.limit_units,'version',quota.version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'member.quota.set',fingerprint,p_workspace,
    'membership',p_membership,quota.version,NULL,result,NULL,result);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_credit_reserve(p_workspace uuid,p_company uuid,p_feature text,
  p_units bigint,p_idempotency uuid,p_request_hash bytea) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships;
  wallet private_isg.workspace_wallets; prior private_isg.workspace_credit_reservations;
  reservation private_isg.workspace_credit_reservations; period text;
  quota private_isg.workspace_member_credit_quotas; quota_used bigint;
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
    RETURN jsonb_build_object('reservation_id',prior.id,'status',prior.status,
      'reserved_units',prior.reserved_units,'period_key',prior.period_key,'replayed',true);
  END IF;
  SELECT * INTO wallet FROM private_isg.workspace_wallets WHERE workspace_id=p_workspace FOR UPDATE;
  IF wallet.workspace_id IS NULL OR wallet.posted_units-wallet.reserved_units-wallet.debt_units<p_units THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INSUFFICIENT_CREDITS'; END IF;
  period:=to_char(clock_timestamp() AT TIME ZONE
    (SELECT timezone FROM private_isg.workspaces WHERE id=p_workspace),'YYYY-MM');
  SELECT * INTO quota FROM private_isg.workspace_member_credit_quotas
    WHERE workspace_id=p_workspace AND membership_id=member.id AND period_key=period FOR UPDATE;
  IF quota.membership_id IS NOT NULL THEN
    SELECT coalesce(sum(CASE status WHEN 'reserved' THEN reserved_units WHEN 'settled' THEN settled_units ELSE 0 END),0)
      INTO quota_used FROM private_isg.workspace_credit_reservations
      WHERE workspace_id=p_workspace AND membership_id=member.id AND period_key=period
        AND status IN ('reserved','settled');
    IF quota_used+p_units>quota.limit_units THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBER_QUOTA_EXCEEDED'; END IF;
  END IF;
  INSERT INTO private_isg.workspace_credit_reservations(workspace_id,actor_user_id,membership_id,company_id,
    feature,idempotency_key,request_hash,reserved_units,status,period_key)
    VALUES(p_workspace,actor,member.id,p_company,p_feature,p_idempotency,p_request_hash,p_units,'reserved',period)
    RETURNING * INTO reservation;
  UPDATE private_isg.workspace_wallets SET reserved_units=reserved_units+p_units,version=version+1,
    updated_at=clock_timestamp() WHERE workspace_id=p_workspace;
  RETURN jsonb_build_object('reservation_id',reservation.id,'status','reserved','reserved_units',p_units,
    'period_key',period,'member_limit_units',quota.limit_units,'replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_member_quota_get(p_workspace uuid,p_membership uuid,p_period text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor_member private_isg.workspace_memberships; quota private_isg.workspace_member_credit_quotas;
  used bigint;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_wallet',false);
  actor_member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  IF p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' OR
     (actor_member.role='expert' AND actor_member.id<>p_membership) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO quota FROM private_isg.workspace_member_credit_quotas
    WHERE workspace_id=p_workspace AND membership_id=p_membership AND period_key=p_period;
  SELECT coalesce(sum(CASE status WHEN 'reserved' THEN reserved_units WHEN 'settled' THEN settled_units ELSE 0 END),0)
    INTO used FROM private_isg.workspace_credit_reservations
    WHERE workspace_id=p_workspace AND membership_id=p_membership AND period_key=p_period
      AND status IN ('reserved','settled');
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'membership_id',p_membership,
    'period_key',p_period,'limit_units',quota.limit_units,'used_units',used,
    'remaining_units',CASE WHEN quota.membership_id IS NULL THEN NULL ELSE greatest(0,quota.limit_units-used) END,
    'configured',quota.membership_id IS NOT NULL,'version',quota.version);
END $$;

CREATE FUNCTION public.isg_workspace_member_quota_set_v1(p_mutation uuid,p_workspace uuid,p_membership uuid,
  p_period text,p_limit bigint,p_expected bigint) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_member_quota_set(
  p_mutation,p_workspace,p_membership,p_period,p_limit,p_expected) $$;
CREATE FUNCTION public.isg_workspace_member_quota_get_v1(p_workspace uuid,p_membership uuid,p_period text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_member_quota_get(
  p_workspace,p_membership,p_period) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_member_quota_set(uuid,uuid,uuid,text,bigint,bigint),
  private_isg.workspace_member_quota_get(uuid,uuid,text),
  public.isg_workspace_member_quota_set_v1(uuid,uuid,uuid,text,bigint,bigint),
  public.isg_workspace_member_quota_get_v1(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_member_quota_set(uuid,uuid,uuid,text,bigint,bigint),
  private_isg.workspace_member_quota_get(uuid,uuid,text),
  public.isg_workspace_member_quota_set_v1(uuid,uuid,uuid,text,bigint,bigint),
  public.isg_workspace_member_quota_get_v1(uuid,uuid,text)
  TO authenticated;
NOTIFY pgrst,'reload schema';
