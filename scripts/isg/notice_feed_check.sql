-- Checks for the header bell's notice feed. Disposable database only. Every
-- expected value is written here by hand; none is read back from the function
-- under test to decide what that function should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set B '20000000-0000-0000-0000-000000000002'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
\set CC '10000000-0000-0000-0000-000000000003'

CREATE FUNCTION pg_temp.expect(got text,want text,label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF got IS NOT DISTINCT FROM want THEN RAISE NOTICE 'ok   % (%)',label,coalesce(want,'NULL'); RETURN; END IF;
  RAISE EXCEPTION '% expected % got %',label,coalesce(want,'NULL'),coalesce(got,'NULL');
END $$;
CREATE FUNCTION pg_temp.expect_refusal(sql text,want text,label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM=want THEN RAISE NOTICE 'ok   % (%)',label,want; RETURN; END IF;
    RAISE EXCEPTION '% expected % got %',label,want,SQLERRM;
  END;
  RAISE EXCEPTION '% expected % but the call succeeded',label,want;
END $$;
CREATE FUNCTION pg_temp.today() RETURNS date LANGUAGE sql STABLE AS $$
  SELECT (clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date $$;
CREATE FUNCTION pg_temp.feed(p_scope text DEFAULT 'active') RETURNS jsonb
LANGUAGE sql AS $$ SELECT public.isg_pilot_notice_feed_v1(NULL,p_scope,50) $$;
-- The key of one record, built here from the record's own columns so the test
-- never asks the function under test what its own key is.
CREATE FUNCTION pg_temp.key(p_kind text,p_id uuid,p_due date) RETURNS text
LANGUAGE sql AS $$ SELECT p_kind||':'||p_id::text||':'||p_due::text $$;

INSERT INTO public.profiles(id) VALUES (:'A'),(:'B');
INSERT INTO public.companies(id,user_id,name) VALUES
  (:'CA',:'A','Alfa'),(:'CB',:'A','Beta'),(:'CC',:'B','Gama');
INSERT INTO private_isg.p05_pilot_accounts(actor_id) VALUES (:'A'),(:'B');
-- Only Alfa is in the pilot audience. Beta is the same owner's company and is
-- still unreachable.
INSERT INTO private_isg.p05_pilot_grants(actor_id,company_id) VALUES (:'A',:'CA'),(:'B',:'CC');
INSERT INTO private_isg.actor_stub(actor_id) VALUES (:'A');
INSERT INTO private_isg.workplaces(id,company_id,owner_id,name) VALUES
  ('40000000-0000-0000-0000-000000000001',:'CA',:'A','Merkez'),
  ('40000000-0000-0000-0000-000000000009',:'CC',:'B','Uzak');
INSERT INTO private_isg.employees(id,company_id,owner_id,full_name) VALUES
  ('30000000-0000-0000-0000-000000000001',:'CA',:'A','Ali Veli');

-- Katip: one inside the 30 day window, one past, one far away, one ended, one
-- deleted, one with no end date at all.
INSERT INTO private_isg.katip_contracts(contract_id,company_id,owner_id,counterparty,starts_on,ends_before,state,is_deleted) VALUES
  ('a1000000-0000-0000-0000-000000000001',:'CA',:'A','OSGB Bir',pg_temp.today()-200,pg_temp.today()+10,'active',false),
  ('a1000000-0000-0000-0000-000000000002',:'CA',:'A','OSGB İki',pg_temp.today()-200,pg_temp.today()-4,'active',false),
  ('a1000000-0000-0000-0000-000000000003',:'CA',:'A','OSGB Üç',pg_temp.today()-200,pg_temp.today()+100,'active',false),
  ('a1000000-0000-0000-0000-000000000004',:'CA',:'A','OSGB Dört',pg_temp.today()-200,pg_temp.today()+5,'ended',false),
  ('a1000000-0000-0000-0000-000000000005',:'CA',:'A','OSGB Beş',pg_temp.today()-200,pg_temp.today()+5,'active',true),
  ('a1000000-0000-0000-0000-000000000006',:'CA',:'A','OSGB Altı',pg_temp.today()-200,NULL,'active',false),
  ('a1000000-0000-0000-0000-000000000007',:'CB',:'A','Beta OSGB',pg_temp.today()-200,pg_temp.today()+1,'active',false),
  ('a1000000-0000-0000-0000-000000000008',:'CC',:'B','Gama OSGB',pg_temp.today()-200,pg_temp.today()+1,'active',false);
INSERT INTO private_isg.appointments(appointment_id,company_id,employee_id,kind,starts_on,ends_before) VALUES
  ('a2000000-0000-0000-0000-000000000001',:'CA','30000000-0000-0000-0000-000000000001','representative',pg_temp.today()-100,pg_temp.today()+3);
INSERT INTO private_isg.emergency_plan_versions(plan_id,version,company_id,workplace_id,valid_until,state) VALUES
  ('a3000000-0000-0000-0000-000000000001',2,:'CA','40000000-0000-0000-0000-000000000001',pg_temp.today()+5,'active'),
  ('a3000000-0000-0000-0000-000000000002',1,:'CA','40000000-0000-0000-0000-000000000001',NULL,'active');
INSERT INTO private_isg.drill_records(drill_id,company_id,workplace_id,planned_on,state) VALUES
  ('a4000000-0000-0000-0000-000000000001',:'CA','40000000-0000-0000-0000-000000000001',pg_temp.today()+20,'planned'),
  ('a4000000-0000-0000-0000-000000000002',:'CA','40000000-0000-0000-0000-000000000001',pg_temp.today()+2,'planned');
INSERT INTO private_isg.annual_work_plans(plan_id,company_id,plan_year,state,is_deleted) VALUES
  ('a5000000-0000-0000-0000-000000000001',:'CA',2026,'open',false),
  ('a5000000-0000-0000-0000-000000000002',:'CA',2025,'open',true);
INSERT INTO private_isg.annual_work_plan_items(item_id,plan_id,activity,planned_on,state) VALUES
  ('a6000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001','Saha turu',pg_temp.today()-1,'planned'),
  ('a6000000-0000-0000-0000-000000000002','a5000000-0000-0000-0000-000000000002','Silinmiş plan işi',pg_temp.today()-1,'planned');
INSERT INTO private_isg.board_meetings(meeting_id,company_id,workplace_id,planned_on,state) VALUES
  ('a7000000-0000-0000-0000-000000000001',:'CA','40000000-0000-0000-0000-000000000001',pg_temp.today()+5,'planned'),
  ('a7000000-0000-0000-0000-000000000002',:'CA','40000000-0000-0000-0000-000000000001',pg_temp.today()+5,'cancelled');
INSERT INTO private_isg.board_decisions(decision_id,meeting_id,decision_no,due_on,state) VALUES
  ('a8000000-0000-0000-0000-000000000001','a7000000-0000-0000-0000-000000000001',1,pg_temp.today()+3,'open'),
  ('a8000000-0000-0000-0000-000000000002','a7000000-0000-0000-0000-000000000001',2,pg_temp.today()+10,'open'),
  ('a8000000-0000-0000-0000-000000000003','a7000000-0000-0000-0000-000000000002',3,pg_temp.today()+3,'open');
-- Risk carries a 60 day window; 50 days out is a notice, and only here.
INSERT INTO private_isg.risk_assessments(assessment_id,company_id,owner_id,workplace_id,valid_until) VALUES
  ('a9000000-0000-0000-0000-000000000001',:'CA',:'A','40000000-0000-0000-0000-000000000001',pg_temp.today()+50);
INSERT INTO private_isg.equipment_items(equipment_id,company_id,owner_id,workplace_id,equipment_type,serial_tag) VALUES
  ('b1000000-0000-0000-0000-000000000001',:'CA',:'A','40000000-0000-0000-0000-000000000001','crane','VINC-1'),
  ('b1000000-0000-0000-0000-000000000002',:'CA',:'A','40000000-0000-0000-0000-000000000001','crane','VINC-2');
-- The newest inspection is the one that counts, in both directions.
INSERT INTO private_isg.equipment_inspections(inspection_id,equipment_id,performed_on,result,next_due_on) VALUES
  ('b2000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',pg_temp.today()-400,'pass',pg_temp.today()+2),
  ('b2000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001',pg_temp.today()-10,'pass',pg_temp.today()+200),
  ('b2000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000002',pg_temp.today()-100,'pass',pg_temp.today()-3);
INSERT INTO private_isg.document_obligations(obligation_id,company_id,owner_id,title,notice_days,is_archived) VALUES
  ('b3000000-0000-0000-0000-000000000001',:'CA',:'A','İşe giriş raporu',10,false),
  ('b3000000-0000-0000-0000-000000000002',:'CA',:'A','Ortam ölçümü',10,false),
  ('b3000000-0000-0000-0000-000000000003',:'CA',:'A','Yangın raporu',10,false),
  ('b3000000-0000-0000-0000-000000000004',:'CA',:'A','Arşivlenmiş evrak',300,true);
INSERT INTO private_isg.document_obligation_records(record_id,obligation_id,company_id,owner_id,issued_on,valid_until) VALUES
  ('b4000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000001',:'CA',:'A',pg_temp.today()-300,pg_temp.today()+5),
  ('b4000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000002',:'CA',:'A',pg_temp.today()-300,pg_temp.today()+20),
  ('b4000000-0000-0000-0000-000000000003','b3000000-0000-0000-0000-000000000003',:'CA',:'A',pg_temp.today()-300,pg_temp.today()+1),
  ('b4000000-0000-0000-0000-000000000004','b3000000-0000-0000-0000-000000000003',:'CA',:'A',pg_temp.today()-10,pg_temp.today()+90),
  ('b4000000-0000-0000-0000-000000000005','b3000000-0000-0000-0000-000000000004',:'CA',:'A',pg_temp.today()-300,pg_temp.today()+5);

-- 1. Eleven situations are due, three of them already past.
SELECT pg_temp.expect((pg_temp.feed()->>'total'),'11','eleven situations are due');
SELECT pg_temp.expect((pg_temp.feed()->>'overdue'),'3','three of them are already past');
SELECT pg_temp.expect((pg_temp.feed()->>'unread'),'11','nothing has been read yet');
SELECT pg_temp.expect(jsonb_array_length(pg_temp.feed()->'rows')::text,'11','every due situation is listed');

-- 2. The most overdue comes first, and the order inside overdue is by date.
SELECT pg_temp.expect((pg_temp.feed()->'rows'->0->>'title'),'OSGB İki','the longest overdue is first');
SELECT pg_temp.expect((pg_temp.feed()->'rows'->0->>'severity'),'overdue','and it is called overdue');
SELECT pg_temp.expect((pg_temp.feed()->'rows'->0->>'days'),'-5','with the days it is past');
SELECT pg_temp.expect((pg_temp.feed()->'rows'->1->>'title'),'VINC-2','then the next oldest');
SELECT pg_temp.expect((pg_temp.feed()->'rows'->2->>'activity'),NULL,'a row carries no field it was not given');
SELECT pg_temp.expect((pg_temp.feed()->'rows'->2->>'title'),'Saha turu','then the planned item from yesterday');

-- 3. Another owner's record, and an ungranted company of the same owner, are
--    both unreachable.
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'title' IN ('Gama OSGB','Beta OSGB')),'0','another company is never in the feed');
SELECT pg_temp.expect_refusal(format('SELECT public.isg_pilot_notice_feed_v1(%L,%L,50)','10000000-0000-0000-0000-000000000002','active'),
  'ACCESS_DENIED','an ungranted company is refused by name');

-- 4. No date is invented: a contract with no end and a plan with no validity
--    produce nothing at all.
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'title'='OSGB Altı'),'0','an open ended contract is not a notice');
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'kind'='emergency_plan'),'1','only the plan that carries a date is a notice');

-- 5. Ended, deleted and cancelled parents are out.
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'title' IN ('OSGB Dört','OSGB Beş','Silinmiş plan işi','3')),'0',
  'ended, deleted and cancelled records raise nothing');

-- 6. Each kind keeps its own window.
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'kind'='drill'),'1','a drill 20 days out is outside the 14 day window');
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'kind'='risk_assessment'),'1','a risk record 50 days out is inside the 60 day window');
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'title'='OSGB Üç'),'0','a contract 99 days out is outside the 30 day window');
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'title'='Ortam ölçümü'),'0','evrak keeps the window written on the obligation');
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'kind'='board_decision'),'1','a decision 10 days out is outside the 7 day window');

-- 7. Only the newest copy counts, for equipment and for evrak.
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'title'='VINC-1'),'0','the newest inspection is the one that counts');
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'title'='Yangın raporu'),'0','the newest recorded copy is the one that counts');
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'title'='Arşivlenmiş evrak'),'0','an archived obligation raises nothing');

-- 8. Every row says where it goes, and never to a surface behind a closed
--    switch (checked again in 14).
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed()->'rows') r
  WHERE r->>'destination' NOT IN ('katipContracts','appointments','emergencyPlans','drills',
    'annualWorkPlans','boardMeetings','riskAssessments','periodicChecks','documentChecklist')),
  '0','every notice points at a real surface');

-- 9. Reading one notice changes that one notice.
SELECT public.isg_pilot_notice_mark_v1('read',
  ARRAY[pg_temp.key('katip_contract','a1000000-0000-0000-0000-000000000002',pg_temp.today()-5)]);
SELECT pg_temp.expect((pg_temp.feed()->>'unread'),'10','one read leaves ten unread');
SELECT pg_temp.expect((pg_temp.feed()->>'total'),'11','and removes nothing from the list');
SELECT pg_temp.expect((pg_temp.feed()->'rows'->0->>'unread'),'false','the row itself is read');
SELECT pg_temp.expect(jsonb_array_length(pg_temp.feed('unread')->'rows')::text,'10','the unread view shows the rest');

-- 10. Reading everything is one call and takes no list.
SELECT public.isg_pilot_notice_mark_v1('read_all');
SELECT pg_temp.expect((pg_temp.feed()->>'unread'),'0','read all leaves nothing unread');
SELECT pg_temp.expect((pg_temp.feed()->>'total'),'11','and still removes nothing');
SELECT pg_temp.expect_refusal($$SELECT public.isg_pilot_notice_mark_v1('read_all',ARRAY['katip_contract:x:y'])$$,
  'PAYLOAD_NOT_ALLOWED','the bulk action takes no list');

-- 11. Deleting a notice hides the situation, not the record.
SELECT public.isg_pilot_notice_mark_v1('dismiss',
  ARRAY[pg_temp.key('katip_contract','a1000000-0000-0000-0000-000000000001',pg_temp.today()+9)]);
SELECT pg_temp.expect((pg_temp.feed()->>'total'),'10','a dismissed notice leaves the list');
SELECT pg_temp.expect((pg_temp.feed()->>'dismissed'),'1','and is counted as dismissed');
SELECT pg_temp.expect(jsonb_array_length(pg_temp.feed('all')->'rows')::text,'11','the full view still shows it');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.katip_contracts
  WHERE contract_id='a1000000-0000-0000-0000-000000000001' AND NOT is_deleted),'1',
  'the record itself is untouched');
SELECT pg_temp.expect((pg_temp.feed()->>'dismiss_is_permanent'),'false','and the answer says so');

-- 12. The situation changing brings the notice back, and the stale mark goes.
UPDATE private_isg.katip_contracts SET ends_before=pg_temp.today()+12
  WHERE contract_id='a1000000-0000-0000-0000-000000000001';
SELECT pg_temp.expect((pg_temp.feed()->>'total'),'11','a moved date is a new situation');
SELECT pg_temp.expect((pg_temp.feed()->>'unread'),'1','which is unread again');
SELECT public.isg_pilot_notice_mark_v1('read_all');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.notice_marks
  WHERE notice_key=pg_temp.key('katip_contract','a1000000-0000-0000-0000-000000000001',pg_temp.today()+9)),
  '0','the mark on the situation that is gone is pruned');

-- 13. A key the feed does not hold is refused, so the table is not free storage.
SELECT pg_temp.expect_refusal($$SELECT public.isg_pilot_notice_mark_v1('read',ARRAY['katip_contract:a1000000-0000-0000-0000-000000000009:2030-01-01'])$$,
  'NOTICE_NOT_FOUND','an unknown key is refused');
SELECT pg_temp.expect_refusal($$SELECT public.isg_pilot_notice_mark_v1('burn',ARRAY['x'])$$,
  'VALIDATION_ERROR','an unknown action is refused');
SELECT pg_temp.expect_refusal($$SELECT public.isg_pilot_notice_feed_v1(NULL,'everything',50)$$,
  'VALIDATION_ERROR','an unknown scope is refused');
SELECT pg_temp.expect_refusal($$SELECT public.isg_pilot_notice_feed_v1(NULL,'active',0)$$,
  'VALIDATION_ERROR','a zero page is refused');

-- 14. A closed switch removes its kind; the bell can not point at a closed door.
UPDATE private_isg.module_registry SET read_enabled=false WHERE module='katip_contract';
SELECT pg_temp.expect((pg_temp.feed('all')->>'total'),'9','a closed module drops its own notices');
UPDATE private_isg.rollout SET read_enabled=false WHERE feature='modules';
SELECT pg_temp.expect((pg_temp.feed('all')->>'total'),'2','the module switch drops every module kind');
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(pg_temp.feed('all')->'rows') r
  WHERE r->>'kind' IN ('risk_assessment','document')),'2','risk and evrak answer to their own switches');
UPDATE private_isg.rollout SET read_enabled=true WHERE feature='modules';
UPDATE private_isg.module_registry SET read_enabled=true WHERE module='katip_contract';

-- 15. Nothing here claims a push happened.
SELECT pg_temp.expect((pg_temp.feed()->>'push_delivery_claimed'),'false','the feed claims no push delivery');
SELECT pg_temp.expect((public.isg_pilot_notice_mark_v1('read_all')->>'push_delivery_claimed'),'false',
  'and marking one read claims none either');
SELECT pg_temp.expect((public.isg_pilot_notice_mark_v1('read_all')->>'records_changed'),'false',
  'marking changes no record');

-- 16. An account outside the pilot gets nothing, in either direction.
DELETE FROM private_isg.p05_pilot_accounts WHERE actor_id=:'A';
SELECT pg_temp.expect_refusal($$SELECT public.isg_pilot_notice_feed_v1(NULL,'active',50)$$,
  'ACCESS_DENIED','an account outside the pilot can not read the feed');
SELECT pg_temp.expect_refusal($$SELECT public.isg_pilot_notice_mark_v1('read_all')$$,
  'ACCESS_DENIED','and can not mark anything');
INSERT INTO private_isg.p05_pilot_accounts(actor_id) VALUES (:'A');

-- 17. The client boundary is the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='private_isg' AND grantee IN ('anon','authenticated')
    AND routine_name IN ('notice_rows','notice_keys','notice_window','notice_kind_available')),
  '0','the row builders are not callable by a client');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_pilot_notice%'),
  '2','exactly the two public wrappers are callable');

SELECT 'ALL NOTICE FEED CHECKS PASSED' AS result;
