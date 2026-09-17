\set ON_ERROR_STOP on
CREATE TEMP TABLE operations_state(key text PRIMARY KEY,value text NOT NULL);
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true
  WHERE feature IN ('workspace_context','workspace_mutations','workspace_invitations','workspace_companies',
    'workspace_assignments','workspace_seats','workspace_storage');

INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('b1000000-0000-4000-8000-000000000001','osgb','Operasyon OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status,is_practicing_expert) VALUES
  ('b2000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active',false),
  ('b2000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000002','expert','active',true);
INSERT INTO private_isg.workspace_entitlements(workspace_id,plan_code,source_kind,status,max_experts,valid_until)
VALUES('b1000000-0000-4000-8000-000000000001','starter','admin_trial','active',5,clock_timestamp()+interval '30 days');

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
SELECT public.isg_workspace_settings_update_v1('b3000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',0,'Yeni Operasyon OSGB','Europe/Istanbul');
WITH invited AS (
  SELECT public.isg_workspace_invite_v1('b3000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000001','expert@example.test','admin',
    clock_timestamp()+interval '1 day') body
) INSERT INTO operations_state VALUES
  ('invitation',(SELECT body->>'invitation_id' FROM invited)),
  ('old_token',(SELECT body->>'invitation_token' FROM invited));
WITH resent AS (
  SELECT public.isg_workspace_invitation_resend_v1('b3000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM operations_state WHERE key='invitation'),0,clock_timestamp()+interval '2 days') body
) INSERT INTO operations_state VALUES('new_token',(SELECT body->>'invitation_token' FROM resent));
DO $$ DECLARE replay jsonb; BEGIN
  replay:=public.isg_workspace_invitation_resend_v1('b3000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM operations_state WHERE key='invitation'),0,
    (SELECT expires_at FROM private_isg.workspace_invitations WHERE id=(SELECT value::uuid FROM operations_state WHERE key='invitation')));
  IF replay ? 'invitation_token' OR (replay->>'token_returned')::boolean IS NOT FALSE OR
     (SELECT value FROM operations_state WHERE key='old_token')=(SELECT value FROM operations_state WHERE key='new_token') THEN
    RAISE EXCEPTION 'resend replay exposed or reused token: %',replay; END IF;
END $$;

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_invitation_accept_v1('b3000000-0000-4000-8000-000000000004',
    (SELECT value FROM operations_state WHERE key='old_token'));
  RAISE EXCEPTION 'EXPECTED_ROTATED_TOKEN_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'INVITATION_INVALID' THEN RAISE; END IF; END $$;
SELECT public.isg_workspace_invitation_accept_v1('b3000000-0000-4000-8000-000000000005',
  (SELECT value FROM operations_state WHERE key='new_token'));

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH created AS (
  SELECT public.isg_workspace_company_create_v1('b3000000-0000-4000-8000-000000000006',
    'b1000000-0000-4000-8000-000000000001','Operasyon Firma','medium') body
) INSERT INTO operations_state VALUES('company',(SELECT body->>'company_id' FROM created));
SELECT public.isg_workspace_company_update_v1('b3000000-0000-4000-8000-000000000007',
  'b1000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM operations_state WHERE key='company'),
  0,'Güncel Operasyon Firma','high');
WITH assigned AS (
  SELECT public.isg_workspace_assignment_mutate_v1('b3000000-0000-4000-8000-000000000008',
    'b1000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM operations_state WHERE key='company'),
    NULL,'b2000000-0000-4000-8000-000000000002',0,'create','primary',
    clock_timestamp()-interval '1 hour',NULL,'operasyon testi') body
) INSERT INTO operations_state VALUES('assignment',(SELECT body->>'assignment_id' FROM assigned));
SELECT public.isg_workspace_company_archive_v1('b3000000-0000-4000-8000-000000000009',
  'b1000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM operations_state WHERE key='company'),
  1,'firma faaliyeti sona erdi');

DO $$ DECLARE members jsonb; invitations jsonb; BEGIN
  members:=public.isg_workspace_member_list_v1('b1000000-0000-4000-8000-000000000001','all',NULL,20);
  invitations:=public.isg_workspace_invitation_list_v1('b1000000-0000-4000-8000-000000000001','all',NULL,20);
  IF jsonb_array_length(members->'rows')<>3 OR jsonb_array_length(invitations->'rows')<>1 OR
     (SELECT status FROM private_isg.workspace_companies WHERE id=(SELECT value::uuid FROM operations_state WHERE key='company'))<>'archived' OR
     (SELECT ends_at FROM private_isg.company_assignments WHERE id=(SELECT value::uuid FROM operations_state WHERE key='assignment')) IS NULL OR
     (SELECT count(*) FROM private_isg.company_assignment_events WHERE assignment_id=(SELECT value::uuid FROM operations_state WHERE key='assignment') AND event_type='ended')<>1 THEN
    RAISE EXCEPTION 'workspace operation invariants failed: members %, invitations %',members,invitations; END IF;
END $$;

SELECT public.isg_workspace_archive_v1('b3000000-0000-4000-8000-000000000010',
  'b1000000-0000-4000-8000-000000000001',1,'OSGB kaydı kapatıldı');
DO $$ DECLARE listed jsonb; context jsonb; BEGIN
  listed:=public.isg_workspace_list_v1();
  context:=public.isg_workspace_context_v1('b1000000-0000-4000-8000-000000000001');
  IF jsonb_array_length(listed->'workspaces')<>0 OR (context->>'can_read')::boolean IS NOT FALSE OR
     (SELECT count(*) FROM private_isg.workspace_companies WHERE workspace_id='b1000000-0000-4000-8000-000000000001')<>1 THEN
    RAISE EXCEPTION 'workspace archive deleted data or stayed selectable: %, %',listed,context; END IF;
  RAISE NOTICE 'ok workspace settings, token rotation, member and invitation lists, company update/archive and non-destructive OSGB archive';
END $$;
