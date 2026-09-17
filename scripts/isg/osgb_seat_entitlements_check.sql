\set ON_ERROR_STOP on
CREATE TEMP TABLE seat_test_state(key text PRIMARY KEY,value text NOT NULL);
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true
  WHERE feature IN ('workspace_mutations','workspace_invitations','workspace_seats');
INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('51000000-0000-4000-8000-000000000001','osgb','Seat OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status) VALUES
  ('52000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active');
INSERT INTO private_isg.workspace_entitlements(workspace_id,plan_code,source_kind,status,max_experts,valid_until)
  VALUES('51000000-0000-4000-8000-000000000001','starter','admin_trial','active',1,clock_timestamp()+interval '7 days');

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH invited AS (
  SELECT public.isg_workspace_invite_v1('53000000-0000-4000-8000-000000000001',
    '51000000-0000-4000-8000-000000000001','admin@example.test','expert',clock_timestamp()+interval '1 day') body
) INSERT INTO seat_test_state VALUES
  ('first_invitation',(SELECT body->>'invitation_id' FROM invited)),('first_token',(SELECT body->>'invitation_token' FROM invited));
DO $$ BEGIN
  IF (SELECT count(*) FROM private_isg.workspace_seat_reservations WHERE status='reserved')<>1 THEN
    RAISE EXCEPTION 'expert invitation did not reserve seat'; END IF;
END $$;

DO $$ BEGIN
  PERFORM public.isg_workspace_invite_v1('53000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000001','expert@example.test','expert',clock_timestamp()+interval '1 day');
  RAISE EXCEPTION 'EXPECTED_SEAT_LIMIT';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'SEAT_LIMIT_REACHED' THEN RAISE; END IF; END $$;
DO $$ BEGIN
  IF (SELECT count(*) FROM private_isg.workspace_invitations)<>1 OR
     (SELECT count(*) FROM private_isg.workspace_seat_reservations)<>1 THEN
    RAISE EXCEPTION 'failed invite left partial state'; END IF;
END $$;

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_invitation_accept_v1('53000000-0000-4000-8000-000000000003',
    (SELECT value FROM seat_test_state WHERE key='first_token'));
  IF (body->'membership'->>'is_practicing_expert')::boolean IS NOT TRUE OR
     (SELECT status FROM private_isg.workspace_seat_reservations
       WHERE reference_id=(SELECT value::uuid FROM seat_test_state WHERE key='first_invitation'))<>'activated' THEN
    RAISE EXCEPTION 'reserved seat activation failed: %',body; END IF;
  INSERT INTO seat_test_state VALUES('member',body->'membership'->>'membership_id');
END $$;

-- Suspending a practicing member frees capacity; the next invite can reserve it.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
DO $$ DECLARE member_version bigint; BEGIN
  SELECT version INTO member_version FROM private_isg.workspace_memberships
    WHERE id=(SELECT value::uuid FROM seat_test_state WHERE key='member');
  PERFORM public.isg_workspace_member_mutate_v1('53000000-0000-4000-8000-000000000004',
    '51000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM seat_test_state WHERE key='member'),
    member_version,'suspend',NULL,'izin askıya alındı');
END $$;
WITH invited AS (
  SELECT public.isg_workspace_invite_v1('53000000-0000-4000-8000-000000000005',
    '51000000-0000-4000-8000-000000000001','expert@example.test','expert',clock_timestamp()+interval '1 day') body
) INSERT INTO seat_test_state VALUES('second_invitation',(SELECT body->>'invitation_id' FROM invited));

-- An operational owner/admin also consumes a seat and cannot exceed capacity.
DO $$ DECLARE owner_version bigint; BEGIN
  SELECT version INTO owner_version FROM private_isg.workspace_memberships
    WHERE id='52000000-0000-4000-8000-000000000001';
  PERFORM public.isg_workspace_member_mutate_v1('53000000-0000-4000-8000-000000000006',
    '51000000-0000-4000-8000-000000000001','52000000-0000-4000-8000-000000000001',
    owner_version,'set_practicing','true','operasyon rolü');
  RAISE EXCEPTION 'EXPECTED_OWNER_SEAT_LIMIT';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'SEAT_LIMIT_REACHED' THEN RAISE; END IF; END $$;

DO $$ BEGIN
  IF has_table_privilege('authenticated','private_isg.workspace_entitlements','SELECT') OR
     has_table_privilege('service_role','private_isg.workspace_seat_reservations','UPDATE') OR
     EXISTS(SELECT 1 FROM private_isg.workspace_plan_catalog WHERE plan_code='scale') THEN
    RAISE EXCEPTION 'seat grant or undecided scale capacity escaped'; END IF;
  RAISE NOTICE 'ok seat entitlement, invitation reservation, last-seat denial, activation, release and operational owner counting';
END $$;
