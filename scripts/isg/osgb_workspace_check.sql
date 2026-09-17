\set ON_ERROR_STOP on

CREATE TEMP TABLE osgb_test_state(key text PRIMARY KEY,value text NOT NULL);

-- Rollout is fail-closed.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_list_v1();
  RAISE EXCEPTION 'EXPECTED_FEATURE_UNAVAILABLE';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'FEATURE_UNAVAILABLE' THEN RAISE; END IF;
END $$;
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true;

-- A personal workspace is unique and a mutation replay is stable.
INSERT INTO osgb_test_state VALUES('personal',(
  SELECT public.isg_personal_workspace_ensure_v1('70000000-0000-4000-8000-000000000001')->>'workspace_id'));
DO $$ DECLARE first_id uuid; replay jsonb; BEGIN
  SELECT value::uuid INTO first_id FROM osgb_test_state WHERE key='personal';
  replay:=public.isg_personal_workspace_ensure_v1('70000000-0000-4000-8000-000000000001');
  IF (replay->>'workspace_id')::uuid<>first_id OR (replay->>'replayed')::boolean IS NOT TRUE OR
     (SELECT count(*) FROM private_isg.workspaces WHERE kind='personal')<>1 THEN
    RAISE EXCEPTION 'personal replay failed'; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_osgb_workspace_create_v1('70000000-0000-4000-8000-000000000001','Conflict','Europe/Istanbul');
  RAISE EXCEPTION 'EXPECTED_CONFLICT';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'IDEMPOTENCY_CONFLICT' THEN RAISE; END IF;
END $$;

-- Creating an OSGB never invents a paid entitlement.
INSERT INTO osgb_test_state VALUES('osgb',(
  SELECT public.isg_osgb_workspace_create_v1('70000000-0000-4000-8000-000000000002',
    'Deneme OSGB','Europe/Istanbul')->>'workspace_id'));
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_context_v1((SELECT value::uuid FROM osgb_test_state WHERE key='osgb'));
  IF body->>'status'<>'pending_purchase' OR (body->>'can_read')::boolean IS NOT TRUE OR
     (body->>'can_operate')::boolean IS NOT FALSE OR body->'membership'->>'role'<>'owner' THEN
    RAISE EXCEPTION 'pending workspace authority failed: %',body; END IF;
END $$;

-- The owner invites an admin. Only the first response contains the raw token.
WITH invited AS (
  SELECT public.isg_workspace_invite_v1('70000000-0000-4000-8000-000000000003',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),'ADMIN@example.test','admin',
    clock_timestamp()+interval '1 day') body
) INSERT INTO osgb_test_state VALUES
  ('admin_invitation',(SELECT body->>'invitation_id' FROM invited)),
  ('admin_token',(SELECT body->>'invitation_token' FROM invited));
DO $$ DECLARE replay jsonb; BEGIN
  replay:=public.isg_workspace_invite_v1('70000000-0000-4000-8000-000000000003',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),'ADMIN@example.test','admin',
    (SELECT expires_at FROM private_isg.workspace_invitations
      WHERE id=(SELECT value::uuid FROM osgb_test_state WHERE key='admin_invitation')));
  IF (replay->>'replayed')::boolean IS NOT TRUE OR replay ? 'invitation_token' THEN
    RAISE EXCEPTION 'invite token was persisted or replay failed: %',replay; END IF;
  IF EXISTS(SELECT 1 FROM private_isg.workspace_receipts WHERE response::text LIKE '%admin_token%') OR
     EXISTS(SELECT 1 FROM private_isg.workspace_receipts WHERE response ? 'invitation_token') OR
     EXISTS(SELECT 1 FROM private_isg.workspace_audit WHERE after_state ? 'invitation_token') OR
     EXISTS(SELECT 1 FROM private_isg.workspace_outbox WHERE payload ? 'invitation_token') THEN
    RAISE EXCEPTION 'plaintext invitation token persisted'; END IF;
END $$;

-- Wrong authenticated email cannot accept a token.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000004',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_invitation_accept_v1('70000000-0000-4000-8000-000000000004',
    (SELECT value FROM osgb_test_state WHERE key='admin_token'));
  RAISE EXCEPTION 'EXPECTED_EMAIL_MISMATCH';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'INVITATION_EMAIL_MISMATCH' THEN RAISE; END IF;
END $$;

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_invitation_accept_v1('70000000-0000-4000-8000-000000000005',
    (SELECT value FROM osgb_test_state WHERE key='admin_token'));
  IF body->'membership'->>'role'<>'admin' OR body->'membership'->>'status'<>'active' THEN
    RAISE EXCEPTION 'admin accept failed: %',body; END IF;
  INSERT INTO osgb_test_state VALUES('admin_membership',body->'membership'->>'membership_id');
END $$;

-- Membership in the OSGB does not expose the owner's personal workspace.
DO $$ BEGIN
  PERFORM public.isg_workspace_context_v1((SELECT value::uuid FROM osgb_test_state WHERE key='personal'));
  RAISE EXCEPTION 'EXPECTED_ACCESS_DENIED';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF;
END $$;
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_list_v1();
  IF jsonb_array_length(body->'workspaces')<>1 OR body->'workspaces'->0->>'kind'<>'osgb' THEN
    RAISE EXCEPTION 'workspace list isolation failed: %',body; END IF;
END $$;

-- Expert acceptance remains closed until Phase H supplies a real seat authority.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH invited AS (
  SELECT public.isg_workspace_invite_v1('70000000-0000-4000-8000-000000000006',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),'expert@example.test','expert',
    clock_timestamp()+interval '1 day') body
) INSERT INTO osgb_test_state VALUES
  ('expert_invitation',(SELECT body->>'invitation_id' FROM invited)),
  ('expert_token',(SELECT body->>'invitation_token' FROM invited));
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_invitation_accept_v1('70000000-0000-4000-8000-000000000007',
    (SELECT value FROM osgb_test_state WHERE key='expert_token'));
  RAISE EXCEPTION 'EXPECTED_SEAT_GATE';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'SEAT_AUTHORITY_UNAVAILABLE' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  IF (SELECT status FROM private_isg.workspace_invitations
      WHERE id=(SELECT value::uuid FROM osgb_test_state WHERE key='expert_invitation'))<>'pending' OR
     EXISTS(SELECT 1 FROM private_isg.workspace_memberships
      WHERE workspace_id=(SELECT value::uuid FROM osgb_test_state WHERE key='osgb')
        AND user_id='20000000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'seat failure made a partial membership'; END IF;
END $$;

-- The test-only hook stands in for the later locked entitlement implementation.
CREATE OR REPLACE FUNCTION private_isg.workspace_require_expert_seat(
  p_workspace uuid,p_user uuid,p_reference uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  RETURN;
END $$;
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_invitation_accept_v1('70000000-0000-4000-8000-000000000008',
    (SELECT value FROM osgb_test_state WHERE key='expert_token'));
  IF body->'membership'->>'role'<>'expert' OR
     (body->'membership'->>'is_practicing_expert')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'expert accept failed: %',body; END IF;
  INSERT INTO osgb_test_state VALUES('expert_membership',body->'membership'->>'membership_id');
END $$;

-- An admin cannot transfer ownership or suspend the owner.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
DO $$ DECLARE owner_id uuid; owner_version bigint; BEGIN
  SELECT id,version INTO owner_id,owner_version FROM private_isg.workspace_memberships
    WHERE workspace_id=(SELECT value::uuid FROM osgb_test_state WHERE key='osgb') AND role='owner';
  PERFORM public.isg_workspace_member_mutate_v1('70000000-0000-4000-8000-000000000009',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),owner_id,owner_version,
    'suspend',NULL,'wrong attempt');
  RAISE EXCEPTION 'EXPECTED_OWNER_PROTECTION';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'MEMBERSHIP_CONFLICT' THEN RAISE; END IF;
END $$;
DO $$ DECLARE owner_id uuid; owner_version bigint; BEGIN
  SELECT id,version INTO owner_id,owner_version FROM private_isg.workspace_memberships
    WHERE workspace_id=(SELECT value::uuid FROM osgb_test_state WHERE key='osgb') AND role='owner';
  PERFORM public.isg_workspace_member_mutate_v1('70000000-0000-4000-8000-000000000010',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),owner_id,owner_version,
    'transfer_owner',NULL,'wrong actor');
  RAISE EXCEPTION 'EXPECTED_OWNER_ONLY';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'MEMBERSHIP_CONFLICT' THEN RAISE; END IF;
END $$;

-- Owner transfer changes responsibility, not authentication or history.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
DO $$ DECLARE target uuid; target_version bigint; body jsonb; BEGIN
  SELECT id,version INTO target,target_version FROM private_isg.workspace_memberships
    WHERE id=(SELECT value::uuid FROM osgb_test_state WHERE key='admin_membership');
  body:=public.isg_workspace_member_mutate_v1('70000000-0000-4000-8000-000000000011',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),target,target_version,
    'transfer_owner',NULL,'planned transfer');
  IF body->'membership'->>'role'<>'owner' THEN RAISE EXCEPTION 'transfer failed: %',body; END IF;
  IF (SELECT role FROM private_isg.workspace_memberships
      WHERE workspace_id=(SELECT value::uuid FROM osgb_test_state WHERE key='osgb')
        AND user_id='20000000-0000-0000-0000-000000000001')<>'admin' THEN
    RAISE EXCEPTION 'old owner was not demoted'; END IF;
END $$;

-- The new owner can suspend/reactivate/end an expert with optimistic locking.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
DO $$ DECLARE target uuid; target_version bigint; body jsonb; BEGIN
  SELECT id,version INTO target,target_version FROM private_isg.workspace_memberships
    WHERE id=(SELECT value::uuid FROM osgb_test_state WHERE key='expert_membership');
  body:=public.isg_workspace_member_mutate_v1('70000000-0000-4000-8000-000000000012',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),target,target_version,
    'suspend',NULL,'security hold');
  IF body->'membership'->>'status'<>'suspended' OR
     (body->'membership'->>'is_practicing_expert')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'suspend failed: %',body; END IF;
END $$;
-- A stale success receipt never restores access after suspension.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_invitation_accept_v1('70000000-0000-4000-8000-000000000008',
    (SELECT value FROM osgb_test_state WHERE key='expert_token'));
  RAISE EXCEPTION 'EXPECTED_REPLAY_ACCESS_DENIED';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF;
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
DO $$ DECLARE target uuid; target_version bigint; BEGIN
  SELECT id,version INTO target,target_version FROM private_isg.workspace_memberships
    WHERE id=(SELECT value::uuid FROM osgb_test_state WHERE key='expert_membership');
  PERFORM public.isg_workspace_member_mutate_v1('70000000-0000-4000-8000-000000000013',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),target,target_version-1,
    'reactivate',NULL,'stale attempt');
  RAISE EXCEPTION 'EXPECTED_VERSION_CONFLICT';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'VERSION_CONFLICT' THEN RAISE; END IF;
END $$;

-- Storage invariants reject invalid personal membership shapes.
DO $$ BEGIN
  INSERT INTO private_isg.workspace_memberships(workspace_id,user_id,role,status)
    VALUES((SELECT value::uuid FROM osgb_test_state WHERE key='personal'),
      '20000000-0000-0000-0000-000000000004','admin','active');
  RAISE EXCEPTION 'EXPECTED_PERSONAL_INVARIANT';
EXCEPTION WHEN SQLSTATE '23514' THEN
  IF SQLERRM<>'PERSONAL_MEMBERSHIP_INVARIANT' THEN RAISE; END IF;
END $$;
DO $$ DECLARE target uuid; target_version bigint; body jsonb; BEGIN
  SELECT id,version INTO target,target_version FROM private_isg.workspace_memberships
    WHERE id=(SELECT value::uuid FROM osgb_test_state WHERE key='expert_membership');
  body:=public.isg_workspace_member_mutate_v1('70000000-0000-4000-8000-000000000014',
    (SELECT value::uuid FROM osgb_test_state WHERE key='osgb'),target,target_version,
    'reactivate',NULL,'hold cleared');
  IF body->'membership'->>'status'<>'active' THEN RAISE EXCEPTION 'reactivate failed'; END IF;
END $$;

-- Direct table access remains absent for client and service roles.
DO $$ BEGIN
  IF has_table_privilege('authenticated','private_isg.workspaces','SELECT') OR
     has_table_privilege('authenticated','private_isg.workspace_memberships','UPDATE') OR
     has_table_privilege('service_role','private_isg.workspace_audit','SELECT') THEN
    RAISE EXCEPTION 'workspace table grant escaped'; END IF;
  IF (SELECT count(*) FROM private_isg.workspace_audit)<8 OR
     (SELECT count(*) FROM private_isg.workspace_receipts)<8 OR
     (SELECT count(*) FROM private_isg.workspace_outbox)<7 OR
     (SELECT count(*) FROM private_isg.workspace_membership_events)<6 THEN
    RAISE EXCEPTION 'audit/receipt/outbox evidence missing'; END IF;
  IF EXISTS(SELECT 1 FROM private_isg.workspace_receipts r
    WHERE r.response::text LIKE '%'||(SELECT value FROM osgb_test_state WHERE key='admin_token')||'%'
       OR r.response::text LIKE '%'||(SELECT value FROM osgb_test_state WHERE key='expert_token')||'%') THEN
    RAISE EXCEPTION 'raw token present in receipt'; END IF;
  RAISE NOTICE 'ok workspace isolation, invitation token/email, seat fail-closed, owner transfer, suspension, replay revocation, personal invariant, version and audit';
END $$;
