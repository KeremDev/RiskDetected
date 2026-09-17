\set ON_ERROR_STOP on
CREATE TEMP TABLE handover_state(key text PRIMARY KEY,value text NOT NULL);
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true
  WHERE feature IN ('workspace_companies','workspace_assignments','workspace_handover');

INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('51000000-0000-4000-8000-000000000001','osgb','Devir OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000001'),
  ('51000000-0000-4000-8000-000000000002','osgb','Diğer OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000004');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status,is_practicing_expert) VALUES
  ('52000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active',false),
  ('52000000-0000-4000-8000-000000000002','51000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000002','expert','active',true),
  ('52000000-0000-4000-8000-000000000003','51000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000003','expert','active',true),
  ('52000000-0000-4000-8000-000000000004','51000000-0000-4000-8000-000000000002','20000000-0000-0000-0000-000000000004','owner','active',false);
INSERT INTO private_isg.workspace_companies(id,workspace_id,name,hazard_class,created_by_user_id,updated_by_user_id) VALUES
  ('53000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000001','Birinci Firma','high','20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
  ('53000000-0000-4000-8000-000000000002','51000000-0000-4000-8000-000000000001','İkinci Firma','medium','20000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.company_assignments(id,workspace_id,company_id,membership_id,assignment_role,starts_at,created_by_user_id,reason) VALUES
  ('54000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000001','53000000-0000-4000-8000-000000000001','52000000-0000-4000-8000-000000000002','primary',clock_timestamp()-interval '1 year','20000000-0000-0000-0000-000000000001','ilk'),
  ('54000000-0000-4000-8000-000000000002','51000000-0000-4000-8000-000000000001','53000000-0000-4000-8000-000000000002','52000000-0000-4000-8000-000000000002','primary',clock_timestamp()-interval '1 year','20000000-0000-0000-0000-000000000001','ilk');

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH made AS (
  SELECT public.isg_workspace_handover_preview_v1('55000000-0000-4000-8000-000000000001',
    '51000000-0000-4000-8000-000000000001','52000000-0000-4000-8000-000000000002',
    '52000000-0000-4000-8000-000000000003',ARRAY['53000000-0000-4000-8000-000000000001'::uuid],
    clock_timestamp()-interval '1 minute','uzman değişikliği') body
) INSERT INTO handover_state VALUES
  ('handover',(SELECT body->>'handover_id' FROM made)),
  ('preview_hash',(SELECT body->>'preview_hash' FROM made));

-- A still-unexecuted company plan can be cancelled without touching its assignment.
WITH made AS (
  SELECT public.isg_workspace_handover_preview_v1('55000000-0000-4000-8000-000000000007',
    '51000000-0000-4000-8000-000000000001','52000000-0000-4000-8000-000000000002',
    '52000000-0000-4000-8000-000000000003',ARRAY['53000000-0000-4000-8000-000000000002'::uuid],
    clock_timestamp()+interval '1 day','iptal edilecek devir') body
) INSERT INTO handover_state VALUES
  ('cancel_handover',(SELECT body->>'handover_id' FROM made)),
  ('cancel_hash',(SELECT body->>'preview_hash' FROM made));
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_handover_cancel_v1('55000000-0000-4000-8000-000000000008',
    '51000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM handover_state WHERE key='cancel_handover'),0,'plan değişti');
  IF body->>'status'<>'cancelled' OR
     (SELECT count(*) FROM private_isg.company_assignments WHERE id='54000000-0000-4000-8000-000000000002' AND ends_at IS NULL)<>1 THEN
    RAISE EXCEPTION 'handover cancellation changed assignment: %',body; END IF;
END $$;

-- Cross-workspace actors cannot execute another workspace's plan.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000004',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_handover_execute_v1('55000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM handover_state WHERE key='handover'),
    '53000000-0000-4000-8000-000000000001',0,(SELECT value FROM handover_state WHERE key='preview_hash'));
  RAISE EXCEPTION 'EXPECTED_CROSS_WORKSPACE_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END $$;

-- Suspending the target after preview fails closed and changes no assignment.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
UPDATE private_isg.workspace_memberships SET status='suspended',is_practicing_expert=false,
  suspended_at=clock_timestamp(),version=version+1 WHERE id='52000000-0000-4000-8000-000000000003';
DO $$ BEGIN
  PERFORM public.isg_workspace_handover_execute_v1('55000000-0000-4000-8000-000000000003',
    '51000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM handover_state WHERE key='handover'),
    '53000000-0000-4000-8000-000000000001',0,(SELECT value FROM handover_state WHERE key='preview_hash'));
  RAISE EXCEPTION 'EXPECTED_SUSPENDED_TARGET_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'PRACTICING_MEMBERSHIP_REQUIRED' THEN RAISE; END IF; END $$;
UPDATE private_isg.workspace_memberships SET status='active',is_practicing_expert=true,
  suspended_at=NULL,version=0 WHERE id='52000000-0000-4000-8000-000000000003';

-- Company version drift also fails before ending the source assignment.
UPDATE private_isg.workspace_companies SET version=version+1 WHERE id='53000000-0000-4000-8000-000000000001';
DO $$ BEGIN
  PERFORM public.isg_workspace_handover_execute_v1('55000000-0000-4000-8000-000000000004',
    '51000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM handover_state WHERE key='handover'),
    '53000000-0000-4000-8000-000000000001',0,(SELECT value FROM handover_state WHERE key='preview_hash'));
  RAISE EXCEPTION 'EXPECTED_COMPANY_VERSION_CONFLICT';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VERSION_CONFLICT' THEN RAISE; END IF; END $$;
UPDATE private_isg.workspace_companies SET version=0 WHERE id='53000000-0000-4000-8000-000000000001';

-- Successful execution closes the source, opens one target assignment and records redacted memory.
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_handover_execute_v1('55000000-0000-4000-8000-000000000005',
    '51000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM handover_state WHERE key='handover'),
    '53000000-0000-4000-8000-000000000001',0,(SELECT value FROM handover_state WHERE key='preview_hash'));
  IF body->>'item_status'<>'completed' OR body->>'handover_status'<>'completed' THEN
    RAISE EXCEPTION 'handover execute failed: %',body; END IF;
END $$;
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_handover_execute_v1('55000000-0000-4000-8000-000000000006',
    '51000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM handover_state WHERE key='handover'),
    '53000000-0000-4000-8000-000000000001',1,(SELECT value FROM handover_state WHERE key='preview_hash'));
  IF (body->>'replayed')::boolean IS NOT TRUE OR (SELECT count(*) FROM private_isg.company_memory_events)<>1 OR
     (SELECT count(*) FROM private_isg.company_assignments WHERE company_id='53000000-0000-4000-8000-000000000001')<>2 THEN
    RAISE EXCEPTION 'completed replay duplicated effects: %',body; END IF;
END $$;
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_company_memory_v1('51000000-0000-4000-8000-000000000001',
    '53000000-0000-4000-8000-000000000001',20);
  IF jsonb_array_length(body->'rows')<>1 OR body::text LIKE '%private_note%' OR
     (SELECT count(*) FROM private_isg.company_handover_briefs)<>1 OR
     (SELECT count(*) FROM private_isg.company_assignments WHERE id='54000000-0000-4000-8000-000000000001' AND ends_at IS NOT NULL)<>1 THEN
    RAISE EXCEPTION 'memory/history invariant failed: %',body; END IF;
END $$;

-- Compensation creates a linked reverse handover; it never restores a stale
-- snapshot or erases the original assignment, memory event, actor or brief.
WITH made AS (
  SELECT public.isg_workspace_handover_compensate_v1('55000000-0000-4000-8000-000000000009',
    '51000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM handover_state WHERE key='handover'),
    '53000000-0000-4000-8000-000000000001',clock_timestamp()-interval '30 seconds','yanlış hedef düzeltmesi') body
) INSERT INTO handover_state VALUES
  ('compensation_handover',(SELECT body->>'handover_id' FROM made)),
  ('compensation_hash',(SELECT body->>'preview_hash' FROM made));
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_handover_execute_v1('55000000-0000-4000-8000-000000000010',
    '51000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM handover_state WHERE key='compensation_handover'),
    '53000000-0000-4000-8000-000000000001',0,
    (SELECT value FROM handover_state WHERE key='compensation_hash'));
  IF body->>'handover_status'<>'completed' OR
     (SELECT count(*) FROM private_isg.company_assignments WHERE company_id='53000000-0000-4000-8000-000000000001')<>3 OR
     (SELECT count(*) FROM private_isg.company_memory_events WHERE company_id='53000000-0000-4000-8000-000000000001')<>2 OR
     (SELECT count(*) FROM private_isg.workspace_handovers WHERE compensation_for_handover_id=
       (SELECT value::uuid FROM handover_state WHERE key='handover') AND status='completed')<>1 THEN
    RAISE EXCEPTION 'compensation did not create immutable reverse history: %',body; END IF;
END $$;
DO $$ BEGIN
  IF has_table_privilege('authenticated','private_isg.workspace_handovers','SELECT') OR
     has_table_privilege('service_role','private_isg.company_memory_events','INSERT') THEN
    RAISE EXCEPTION 'handover private table grant leak'; END IF;
  RAISE NOTICE 'ok handover isolation, cancellation, target suspension, version drift, atomic assignment, compensation, replay and redacted memory';
END $$;
