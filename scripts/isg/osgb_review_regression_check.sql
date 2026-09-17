-- Run after the integrated acceptance scenario, using its synthetic workspace.
UPDATE private_isg.ppe_handovers SET item='Updated legacy helmet'
WHERE handover_id='d1000000-0000-4000-8000-000000000003';
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000004',false);
SELECT public.isg_personal_workspace_ensure_v1('d1000000-0000-4000-8000-000000000004');
SELECT private_isg.workspace_company_backfill_batch('d1000000-0000-4000-8000-000000000005',repeat('d',64),NULL,250,true);
UPDATE private_isg.employees SET full_name='Updated legacy employee'
WHERE id='d1000000-0000-4000-8000-000000000002';
UPDATE private_isg.ppe_handovers SET item='Updated after personal mapping'
WHERE handover_id='d1000000-0000-4000-8000-000000000003';
DO $$ BEGIN RAISE NOTICE 'ok review populated legacy PPE upgrade and personal employee/PPE edits after mapping'; END $$;

BEGIN;
UPDATE private_isg.workspace_file_entries SET visibility='member_private',company_id=NULL,private_to_membership_id=(SELECT value::uuid FROM integrated_state WHERE key='target_membership'),title='ConfidentialReviewDocument'
WHERE id=(SELECT value::uuid FROM integrated_state WHERE key='file_entry');
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',true);
DO $$ DECLARE result jsonb; BEGIN
 result:=private_isg.workspace_search((SELECT value::uuid FROM integrated_state WHERE key='workspace'),
 (SELECT value::uuid FROM integrated_state WHERE key='company'),'ConfidentialReviewDocument',NULL,NULL,30);
 IF jsonb_array_length(result->'rows')<>0 THEN RAISE EXCEPTION 'private file leaked through search: %',result; END IF;
 RAISE NOTICE 'ok review workspace-private file excluded from company search';
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
INSERT INTO private_isg.workspace_outbox(workspace_id,event_type,aggregate_type,aggregate_id,aggregate_version,payload,correlation_id)
SELECT (SELECT value::uuid FROM integrated_state WHERE key='workspace'),'file.private.review','file_entry',
(SELECT value::uuid FROM integrated_state WHERE key='file_entry'),99,'{}',gen_random_uuid();
DO $$ DECLARE result jsonb; BEGIN
 result:=private_isg.workspace_change_read((SELECT value::uuid FROM integrated_state WHERE key='workspace'),NULL,0,200);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'rows') r WHERE r->>'event_type'='file.private.review') THEN
 RAISE EXCEPTION 'member-private file existence leaked to owner through change feed'; END IF;
 RAISE NOTICE 'ok review member-private change events hidden from non-recipient owner';
END $$;
ROLLBACK;

BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
UPDATE private_isg.workspace_domain_rollout SET read_enabled=false,write_enabled=false WHERE domain='personnel';
DO $$ DECLARE result jsonb; BEGIN
 result:=private_isg.workspace_search((SELECT value::uuid FROM integrated_state WHERE key='workspace'),
 (SELECT value::uuid FROM integrated_state WHERE key='company'),'Ayşe',NULL,NULL,100);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'rows') r WHERE r->>'kind'='employee') THEN
 RAISE EXCEPTION 'disabled personnel domain exposed by search'; END IF;
 RAISE NOTICE 'ok review disabled source domain excluded from global search';
END $$;
ROLLBACK;

-- Old clients send none of the new workspace/author fields.
BEGIN;
INSERT INTO private_isg.workplaces(id,company_id,owner_id,name,code)
VALUES('d1000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000001',
'20000000-0000-0000-0000-000000000004','Legacy workplace','OLD');
INSERT INTO private_isg.equipment_items(equipment_id,company_id,owner_id,workplace_id,equipment_type,serial_tag)
VALUES('d1000000-0000-4000-8000-000000000007','d1000000-0000-4000-8000-000000000001',
'20000000-0000-0000-0000-000000000004','d1000000-0000-4000-8000-000000000006','forklift','OLD-1');
INSERT INTO private_isg.equipment_inspections(equipment_id,performed_on,result)
VALUES('d1000000-0000-4000-8000-000000000007','2026-09-01','pass');
INSERT INTO private_isg.annual_work_plans(plan_id,company_id,owner_id,workplace_id,plan_year)
VALUES('d1000000-0000-4000-8000-000000000008','d1000000-0000-4000-8000-000000000001',
'20000000-0000-0000-0000-000000000004','d1000000-0000-4000-8000-000000000006',2026);
INSERT INTO private_isg.annual_work_plan_items(plan_id,activity,planned_on)
VALUES('d1000000-0000-4000-8000-000000000008','Legacy activity','2026-10-01');
DO $$ BEGIN RAISE NOTICE 'ok review old-client workplace, equipment, annual plan and nested item writes'; END $$;
ROLLBACK;

BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
DO $$ DECLARE workspace uuid:=(SELECT value::uuid FROM integrated_state WHERE key='workspace');
 company uuid; result jsonb; BEGIN
 result:=public.isg_workspace_company_create_v1(gen_random_uuid(),workspace,'Archive timeline review','low');
 company:=(result->>'company_id')::uuid;
 INSERT INTO private_isg.company_assignments(workspace_id,company_id,membership_id,assignment_role,starts_at,ends_at,created_by_user_id)
 VALUES(workspace,company,(SELECT value::uuid FROM integrated_state WHERE key='target_membership'),'primary',
 clock_timestamp()+interval '1 day',NULL,'20000000-0000-0000-0000-000000000001'),
 (workspace,company,(SELECT value::uuid FROM integrated_state WHERE key='source_membership'),'support',
 clock_timestamp()-interval '1 day',clock_timestamp()+interval '10 days','20000000-0000-0000-0000-000000000001');
 UPDATE private_isg.workspace_memberships SET status='suspended',suspended_at=clock_timestamp(),is_practicing_expert=false
 WHERE id=(SELECT value::uuid FROM integrated_state WHERE key='source_membership');
 result:=public.isg_workspace_company_archive_v1(gen_random_uuid(),workspace,company,0,'Review cancellation');
 IF (result->>'ended_assignments')::int<>2 OR EXISTS(SELECT 1 FROM private_isg.company_assignments a
 WHERE a.company_id=company AND (a.ends_at IS NULL OR (a.ends_at>a.starts_at AND a.ends_at>clock_timestamp()))) THEN
 RAISE EXCEPTION 'future/finite assignment archive failed'; END IF;
 RAISE NOTICE 'ok review archive cancels future and ends finite assignments of a suspended member';
END $$;
ROLLBACK;

-- Same-name personal companies were legal before the new mirror index.
BEGIN;
INSERT INTO public.companies(user_id,name,hazard_class)
VALUES('20000000-0000-0000-0000-000000000004','Legacy review company','low');
DO $$ BEGIN RAISE NOTICE 'ok review same-name personal company creation remains compatible'; END $$;
ROLLBACK;

-- Backfill must work for expired users and preserve the original updated_at.
BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
SELECT public.isg_personal_workspace_ensure_v1(gen_random_uuid());
-- This user has a workspace but this fixture simulates a preexisting unmapped company.
INSERT INTO public.companies(id,user_id,name,hazard_class)
VALUES('d1000000-0000-4000-8000-000000000009','20000000-0000-0000-0000-000000000002','Expired user company','low');
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',true);
SELECT public.isg_personal_workspace_ensure_v1(gen_random_uuid());
CREATE OR REPLACE FUNCTION private.company_limit_for_user(uuid) RETURNS integer
LANGUAGE sql STABLE SET search_path='' AS $$ SELECT 0 $$;
DO $$ DECLARE before_time timestamptz; result jsonb; run uuid:=gen_random_uuid(); BEGIN
 SELECT updated_at INTO before_time FROM public.companies WHERE id='d1000000-0000-4000-8000-000000000009';
 result:=private_isg.workspace_company_backfill_batch(run,repeat('f',64),NULL,250,true);
 IF (SELECT updated_at FROM public.companies WHERE id='d1000000-0000-4000-8000-000000000009') IS DISTINCT FROM before_time THEN
 RAISE EXCEPTION 'backfill rewrote a legacy timestamp'; END IF;
 result:=private_isg.workspace_company_backfill_batch(run,repeat('f',64),NULL,250,true);
 IF (result->>'scanned')::int<>0 THEN RAISE EXCEPTION 'completed backfill replay counted twice'; END IF;
 RAISE NOTICE 'ok review expired-owner scope backfill preserves timestamps and completed replay';
END $$;
ROLLBACK;

BEGIN;
UPDATE private_isg.workspace_memberships SET role='admin'
WHERE id=(SELECT value::uuid FROM integrated_state WHERE key='target_membership');
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',true);
DO $$ DECLARE company uuid:=(SELECT value::uuid FROM integrated_state WHERE key='company'); result jsonb; BEGIN
 result:=public.isg_workspace_company_update_v1(gen_random_uuid(),
 (SELECT value::uuid FROM integrated_state WHERE key='workspace'),company,
 (SELECT version FROM private_isg.workspace_companies c WHERE c.id=company),'Admin review update','medium');
 IF (SELECT updated_by_user_id FROM private_isg.workspace_companies c WHERE c.id=company)<>'20000000-0000-0000-0000-000000000003'::uuid THEN
 RAISE EXCEPTION 'canonical sync replaced actual admin with workspace creator'; END IF;
 RAISE NOTICE 'ok review canonical sync preserves the actual updating admin';
END $$;
ROLLBACK;

BEGIN;
DELETE FROM public.companies WHERE id='d1000000-0000-4000-8000-000000000001';
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM private_isg.workspace_companies WHERE id='d1000000-0000-4000-8000-000000000001'
 AND status='archived' AND legacy_company_id IS NULL) THEN RAISE EXCEPTION 'deleted personal company mirror is still visible'; END IF;
 IF EXISTS(SELECT 1 FROM private_isg.employees WHERE id='d1000000-0000-4000-8000-000000000002') THEN
 RAISE EXCEPTION 'old personal deletion cascade no longer works'; END IF;
 RAISE NOTICE 'ok review legacy personal company deletion retains an archived mirror without stale link';
END $$;
ROLLBACK;
