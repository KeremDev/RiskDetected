\set ON_ERROR_STOP on
CREATE TEMP TABLE backfill_test_state(key text PRIMARY KEY,value text NOT NULL);

-- Observation mode mutates neither workspaces nor checkpoints.
DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_backfill_personal_batch(
    '80000000-0000-4000-8000-000000000001',repeat('a',64),NULL,2,false);
  IF (body->>'scanned')::integer<>2 OR (body->>'proposed')::integer<>2 OR
     EXISTS(SELECT 1 FROM private_isg.workspaces) OR
     EXISTS(SELECT 1 FROM private_isg.workspace_backfill_checkpoints) THEN
    RAISE EXCEPTION 'dry run mutated or counted incorrectly: %',body; END IF;
END $$;

WITH first_batch AS (
  SELECT private_isg.workspace_backfill_personal_batch(
    '80000000-0000-4000-8000-000000000001',repeat('a',64),NULL,2,true) body
) INSERT INTO backfill_test_state VALUES('cursor',(SELECT body->>'last_profile_id' FROM first_batch));
DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_backfill_personal_batch(
    '80000000-0000-4000-8000-000000000001',repeat('a',64),
    (SELECT value::uuid FROM backfill_test_state WHERE key='cursor'),2,true);
  IF (body->>'completed')::boolean IS NOT TRUE OR (SELECT count(*) FROM private_isg.workspaces)<>4 OR
     (SELECT count(*) FROM private_isg.workspace_memberships)<>4 THEN
    RAISE EXCEPTION 'resume failed: %',body; END IF;
END $$;

-- Replaying a completed run and running a new source pass do not duplicate rows.
DO $$ DECLARE body jsonb; BEGIN
  body:=private_isg.workspace_backfill_personal_batch(
    '80000000-0000-4000-8000-000000000001',repeat('a',64),
    (SELECT value::uuid FROM backfill_test_state WHERE key='cursor'),2,true);
  IF (body->>'replayed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'completed replay failed'; END IF;
  body:=private_isg.workspace_backfill_personal_batch(
    '80000000-0000-4000-8000-000000000002',repeat('b',64),NULL,100,true);
  IF (body->>'created_workspaces')::integer<>0 OR (body->>'created_memberships')::integer<>0 OR
     (SELECT count(*) FROM private_isg.workspaces)<>4 THEN RAISE EXCEPTION 'idempotent pass failed: %',body; END IF;
END $$;

DO $$ BEGIN
  PERFORM private_isg.workspace_backfill_personal_batch(
    '80000000-0000-4000-8000-000000000001',repeat('c',64),NULL,2,true);
  RAISE EXCEPTION 'EXPECTED_SOURCE_CONFLICT';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'SOURCE_FINGERPRINT_CONFLICT' THEN RAISE; END IF;
END $$;

DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM private_isg.workspace_memberships m
    JOIN private_isg.workspaces w ON w.id=m.workspace_id
    WHERE w.kind<>'personal' OR m.user_id<>w.personal_owner_user_id OR m.role<>'owner' OR m.status<>'active') OR
     has_function_privilege('service_role',
       'private_isg.workspace_backfill_personal_batch(uuid,text,uuid,integer,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'backfill invariant or grant escaped'; END IF;
  RAISE NOTICE 'ok personal workspace dry-run, resume, replay, source fingerprint and membership mapping';
END $$;
