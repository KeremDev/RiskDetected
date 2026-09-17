-- Canonical OSGB plan entitlement and seat authority. NOT DEPLOYED.
-- No store purchase is created here; verified provider reconciliation owns bindings.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

INSERT INTO private_isg.workspace_rollout(feature) VALUES('workspace_seats');

CREATE TABLE private_isg.workspace_plan_catalog (
  plan_code text PRIMARY KEY CHECK(plan_code IN ('starter','growth','pro','scale')),
  max_experts integer NOT NULL CHECK(max_experts BETWEEN 1 AND 100000),
  catalog_version integer NOT NULL CHECK(catalog_version>0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO private_isg.workspace_plan_catalog(plan_code,max_experts,catalog_version) VALUES
  ('starter',5,1),('growth',10,1),('pro',20,1);
-- Scale is intentionally absent until DEC-02 provides an explicit capacity.

CREATE TABLE private_isg.workspace_subscription_bindings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  provider text NOT NULL CHECK(provider IN ('apple','google','revenuecat','admin')),
  environment text NOT NULL CHECK(environment IN ('sandbox','production','admin')),
  product_id text NOT NULL CHECK(octet_length(product_id) BETWEEN 1 AND 200),
  subscription_chain_id text NOT NULL CHECK(octet_length(subscription_chain_id) BETWEEN 1 AND 300),
  purchaser_user_id uuid NOT NULL,
  status text NOT NULL CHECK(status IN ('pending','active','grace','canceled_active','hold','expired','revoked','verification_failed')),
  effective_at timestamptz NOT NULL,
  valid_until timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(provider,environment,subscription_chain_id),
  CHECK(valid_until IS NULL OR valid_until>effective_at)
);
CREATE INDEX workspace_subscription_timeline
  ON private_isg.workspace_subscription_bindings(workspace_id,effective_at,id);

CREATE TABLE private_isg.workspace_entitlements (
  workspace_id uuid PRIMARY KEY REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  plan_code text NOT NULL REFERENCES private_isg.workspace_plan_catalog(plan_code),
  source_binding_id uuid REFERENCES private_isg.workspace_subscription_bindings(id) ON DELETE RESTRICT,
  source_kind text NOT NULL CHECK(source_kind IN ('store','admin_trial','admin_sponsored')),
  status text NOT NULL CHECK(status IN ('active','grace','canceled_active','expired','revoked')),
  max_experts integer NOT NULL CHECK(max_experts BETWEEN 1 AND 100000),
  valid_until timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(source_kind<>'store' OR source_binding_id IS NOT NULL)
);

CREATE TABLE private_isg.workspace_seat_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  reference_kind text NOT NULL CHECK(reference_kind='invitation'),
  reference_id uuid NOT NULL,
  status text NOT NULL CHECK(status IN ('reserved','activated','released','expired')),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,reference_kind,reference_id),
  CHECK(expires_at>created_at)
);
CREATE INDEX workspace_seat_reservation_capacity
  ON private_isg.workspace_seat_reservations(workspace_id,status,expires_at,id);

ALTER TABLE private_isg.workspace_plan_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_subscription_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_seat_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_plan_catalog,private_isg.workspace_subscription_bindings,
  private_isg.workspace_entitlements,private_isg.workspace_seat_reservations
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_seat_capacity(p_workspace uuid) RETURNS integer
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE capacity integer;
BEGIN
  SELECT max_experts INTO capacity FROM private_isg.workspace_entitlements e
    WHERE e.workspace_id=p_workspace AND e.status IN ('active','grace','canceled_active')
      AND (e.valid_until IS NULL OR e.valid_until>clock_timestamp());
  IF capacity IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ENTITLEMENT_REQUIRED'; END IF;
  RETURN capacity;
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_require_expert_seat(
  p_workspace uuid,p_user uuid,p_reference uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE capacity integer; occupied integer; reserved integer;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_seats',true);
  IF p_workspace IS NULL OR p_reference IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.workspaces WHERE id=p_workspace AND kind='osgb' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  capacity:=private_isg.workspace_seat_capacity(p_workspace);
  IF EXISTS(SELECT 1 FROM private_isg.workspace_seat_reservations r
    WHERE r.workspace_id=p_workspace AND r.reference_id=p_reference AND r.status='reserved'
      AND r.expires_at>clock_timestamp()) THEN RETURN; END IF;
  SELECT count(*) INTO occupied FROM private_isg.workspace_memberships m
    WHERE m.workspace_id=p_workspace AND m.status='active' AND m.is_practicing_expert
      AND (p_user IS NULL OR m.user_id<>p_user);
  SELECT count(*) INTO reserved FROM private_isg.workspace_seat_reservations r
    WHERE r.workspace_id=p_workspace AND r.status='reserved' AND r.expires_at>clock_timestamp();
  IF occupied+reserved>=capacity THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SEAT_LIMIT_REACHED'; END IF;
END $$;

CREATE FUNCTION private_isg.workspace_invitation_seat_reserve() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.role='expert' THEN
    PERFORM private_isg.workspace_require_expert_seat(NEW.workspace_id,NULL,NEW.id);
    INSERT INTO private_isg.workspace_seat_reservations(workspace_id,reference_kind,reference_id,status,expires_at)
      VALUES(NEW.workspace_id,'invitation',NEW.id,'reserved',NEW.expires_at);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workspace_invitation_seat_reserve_after
AFTER INSERT ON private_isg.workspace_invitations
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_invitation_seat_reserve();

CREATE FUNCTION private_isg.workspace_invitation_seat_transition() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.role='expert' AND NEW.status IS DISTINCT FROM OLD.status THEN
    UPDATE private_isg.workspace_seat_reservations SET
      status=CASE NEW.status WHEN 'accepted' THEN 'activated' WHEN 'expired' THEN 'expired' ELSE 'released' END,
      updated_at=clock_timestamp()
      WHERE workspace_id=NEW.workspace_id AND reference_kind='invitation' AND reference_id=NEW.id
        AND status='reserved';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workspace_invitation_seat_transition_after
AFTER UPDATE OF status ON private_isg.workspace_invitations
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_invitation_seat_transition();

CREATE FUNCTION private_isg.workspace_expire_seat_reservations(p_now timestamptz,p_limit integer) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE changed integer;
BEGIN
  IF p_now IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  WITH expired AS (SELECT id FROM private_isg.workspace_seat_reservations
    WHERE status='reserved' AND expires_at<=p_now ORDER BY expires_at,id FOR UPDATE SKIP LOCKED LIMIT p_limit)
  UPDATE private_isg.workspace_seat_reservations r SET status='expired',updated_at=clock_timestamp()
    FROM expired e WHERE r.id=e.id;
  GET DIAGNOSTICS changed=ROW_COUNT; RETURN changed;
END $$;

REVOKE ALL ON FUNCTION private_isg.workspace_seat_capacity(uuid),
  private_isg.workspace_require_expert_seat(uuid,uuid,uuid),
  private_isg.workspace_invitation_seat_reserve(),private_isg.workspace_invitation_seat_transition(),
  private_isg.workspace_expire_seat_reservations(timestamptz,integer)
  FROM PUBLIC,anon,authenticated,service_role;
