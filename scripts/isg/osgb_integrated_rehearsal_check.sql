\set ON_ERROR_STOP on

-- Cross-component acceptance on one disposable workspace. Every identifier and
-- store product below is synthetic; no production product or account is used.
CREATE TEMP TABLE integrated_state(key text PRIMARY KEY,value text NOT NULL);
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true;
UPDATE private_isg.workspace_domain_rollout SET read_enabled=true,write_enabled=true
  WHERE domain IN ('personnel','training','risk_nonconformity','emergency_ppe','equipment','operations','files','analysis_exports','tracking_notifications');

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH created AS (
  SELECT public.isg_osgb_workspace_create_v1(
    'a1000000-0000-4000-8000-000000000001','Entegre OSGB','Europe/Istanbul') body
)
INSERT INTO integrated_state VALUES
  ('workspace',(SELECT body->>'workspace_id' FROM created)),
  ('owner_membership',(SELECT body->'membership'->>'membership_id' FROM created));

-- A verified, allowlisted sandbox event activates the workspace and its seat
-- authority. Client success alone never reaches these server-only functions.
INSERT INTO private_isg.workspace_billing_products(provider,environment,product_id,product_kind,
  plan_code,credit_units,catalog_version,approved,active)
VALUES
  ('apple','sandbox','test.integration.growth','subscription','growth',NULL,1,true,true),
  ('apple','sandbox','test.integration.credits100','credit_pack',NULL,100,1,true,true);
WITH opened AS (
  SELECT public.isg_workspace_purchase_open_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),'apple','sandbox',
    'test.integration.growth','a1000000-0000-4000-8000-000000000016',
    sha256('integration-purchase-open'::bytea),clock_timestamp()+interval '30 minutes') body
)
INSERT INTO integrated_state VALUES
  ('purchase_intent',(SELECT body->>'intent_id' FROM opened)),
  ('purchase_token',(SELECT body->>'intent_token' FROM opened));
SELECT private_isg.workspace_purchase_record_verified(
  (SELECT value FROM integrated_state WHERE key='purchase_token'),'integration-subscription-1',
  'integration-transaction-1','integration-chain-1','active',clock_timestamp()-interval '1 minute',
  clock_timestamp()+interval '30 days',1,'callback','verified',sha256('integration-subscription'::bytea),
  'server_adapter',clock_timestamp());
SELECT private_isg.workspace_purchase_reconcile(
  (SELECT value::uuid FROM integrated_state WHERE key='purchase_intent'),clock_timestamp());

WITH opened AS (
  SELECT public.isg_workspace_purchase_open_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),'apple','sandbox',
    'test.integration.credits100','a1000000-0000-4000-8000-000000000017',
    sha256('integration-credit-open'::bytea),clock_timestamp()+interval '30 minutes') body
)
INSERT INTO integrated_state VALUES
  ('credit_intent',(SELECT body->>'intent_id' FROM opened)),
  ('credit_token',(SELECT body->>'intent_token' FROM opened));
SELECT private_isg.workspace_purchase_record_verified(
  (SELECT value FROM integrated_state WHERE key='credit_token'),'integration-credit-1',
  'integration-credit-transaction-1',NULL,NULL,clock_timestamp()-interval '30 seconds',NULL,1,
  'callback','verified',sha256('integration-credit'::bytea),'server_adapter',clock_timestamp());
SELECT private_isg.workspace_purchase_reconcile(
  (SELECT value::uuid FROM integrated_state WHERE key='credit_intent'),clock_timestamp());

-- Invite and accept two experts through the real seat-reservation path.
WITH invited AS (
  SELECT public.isg_workspace_invite_v1('a1000000-0000-4000-8000-000000000002',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),'admin@example.test','expert',
    clock_timestamp()+interval '1 day') body
)
INSERT INTO integrated_state VALUES('source_token',(SELECT body->>'invitation_token' FROM invited));
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
WITH accepted AS (
  SELECT public.isg_workspace_invitation_accept_v1('a1000000-0000-4000-8000-000000000003',
    (SELECT value FROM integrated_state WHERE key='source_token')) body
)
INSERT INTO integrated_state VALUES('source_membership',(SELECT body->'membership'->>'membership_id' FROM accepted));

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH invited AS (
  SELECT public.isg_workspace_invite_v1('a1000000-0000-4000-8000-000000000004',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),'expert@example.test','expert',
    clock_timestamp()+interval '1 day') body
)
INSERT INTO integrated_state VALUES('target_token',(SELECT body->>'invitation_token' FROM invited));
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
WITH accepted AS (
  SELECT public.isg_workspace_invitation_accept_v1('a1000000-0000-4000-8000-000000000005',
    (SELECT value FROM integrated_state WHERE key='target_token')) body
)
INSERT INTO integrated_state VALUES('target_membership',(SELECT body->'membership'->>'membership_id' FROM accepted));

-- Company creation and the initial expert assignment are versioned RPC writes.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH created AS (
  SELECT public.isg_workspace_company_create_v1('a1000000-0000-4000-8000-000000000006',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),'Entegre Firma','high') body
)
INSERT INTO integrated_state VALUES('company',(SELECT body->>'company_id' FROM created));
WITH assigned AS (
  SELECT public.isg_workspace_assignment_mutate_v1('a1000000-0000-4000-8000-000000000007',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),NULL,
    (SELECT value::uuid FROM integrated_state WHERE key='source_membership'),0,'create','primary',
    clock_timestamp()-interval '1 hour',NULL,'ilk uzman ataması') body
)
INSERT INTO integrated_state VALUES('source_assignment',(SELECT body->>'assignment_id' FROM assigned));
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_assignment_list_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'current',NULL,20);
  IF jsonb_array_length(body->'rows')<>1 OR
     body->'rows'->0->>'membership_id'<>(SELECT value FROM integrated_state WHERE key='source_membership') THEN
    RAISE EXCEPTION 'integrated assignment list failed: %',body; END IF;
END $$;

-- D1 uses the same canonical company id. A manager controls the directory,
-- while the assigned expert writes and reads employees as their own actor.
WITH initialized AS (
  SELECT public.isg_workspace_personnel_initialize_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company')) body
)
INSERT INTO integrated_state VALUES('workplace',(SELECT body->>'workplace_id' FROM initialized));
WITH created AS (
  SELECT public.isg_workspace_directory_mutate_v1('a1000000-0000-4000-8000-000000000019',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'department','create',NULL,0,
    (SELECT value::uuid FROM integrated_state WHERE key='workplace'),'OPERASYON','Operasyon') body
)
INSERT INTO integrated_state VALUES('department',(SELECT body->>'entity_id' FROM created));
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
WITH created AS (
  SELECT public.isg_workspace_employee_mutate_v1('a1000000-0000-4000-8000-000000000020',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'create',NULL,0,'P-001','Ayşe Uzman',
    (SELECT value::uuid FROM integrated_state WHERE key='department'),DATE '2026-01-01',NULL) body
)
INSERT INTO integrated_state VALUES('employee',(SELECT body->>'employee_id' FROM created));

-- D2 keeps the session, company projection and employee attendance inside the
-- same workspace. The assigned expert is the historical author.
WITH created AS (
  SELECT public.isg_workspace_training_mutate_v1('a1000000-0000-4000-8000-000000000021',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','save','expected_version',0,'title','Saha güvenliği',
      'trainer','Ayşe Uzman','method','face_to_face','starts_at',clock_timestamp()-interval '3 hours',
      'duration_minutes',60,'location','Toplantı salonu','notes','Sentetik eğitim',
      'participants',jsonb_build_array(jsonb_build_object(
        'id',(SELECT value FROM integrated_state WHERE key='employee'),'attended',true)))) body
)
INSERT INTO integrated_state VALUES
  ('training',(SELECT body->'row'->>'training_id' FROM created)),
  ('training_version',(SELECT body->'row'->>'version' FROM created));
WITH edited AS (
  SELECT public.isg_workspace_training_mutate_v1('a1000000-0000-4000-8000-000000000023',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','save','id',(SELECT value FROM integrated_state WHERE key='training'),
      'expected_version',(SELECT value::bigint FROM integrated_state WHERE key='training_version'),
      'title','Saha güvenliği','trainer','Ayşe Uzman','method','mixed',
      'starts_at',clock_timestamp()-interval '3 hours','duration_minutes',60,
      'location','Toplantı salonu','notes','Sentetik eğitim güncellendi',
      'participants',jsonb_build_array(jsonb_build_object(
        'id',(SELECT value FROM integrated_state WHERE key='employee'),'attended',true)))) body
)
UPDATE integrated_state SET value=(SELECT body->'row'->>'version' FROM edited) WHERE key='training_version';
WITH completed AS (
  SELECT public.isg_workspace_training_mutate_v1('a1000000-0000-4000-8000-000000000022',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','complete','id',(SELECT value FROM integrated_state WHERE key='training'),
      'expected_version',(SELECT value::bigint FROM integrated_state WHERE key='training_version'))) body
)
UPDATE integrated_state SET value=(SELECT body->'row'->>'version' FROM completed) WHERE key='training_version';
DO $$ DECLARE training_metrics jsonb; BEGIN
  training_metrics:=public.isg_workspace_training_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  IF (training_metrics->'records'->>'completed')::integer<>1 OR
     (training_metrics->>'trained_people')::integer<>1 OR
     (training_metrics->>'person_minutes')::integer<>60 OR
     (training_metrics->>'people_without_completed_training')::integer<>0 THEN
    RAISE EXCEPTION 'training metrics failed: %',training_metrics; END IF;
END $$;

-- D3: a versioned risk record, an auditable nonconformity transition and a
-- submitted checklist whose negative answer creates a linked finding.
WITH drafted AS (
  SELECT public.isg_workspace_risk_mutate_v1('a1000000-0000-4000-8000-000000000024',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','draft','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'expected_current',0,'kind','full','assessment_on',
      ((clock_timestamp() AT TIME ZONE 'UTC')::date-1))) body
)
INSERT INTO integrated_state VALUES
  ('risk',(SELECT body->'row'->>'assessment_id' FROM drafted)),
  ('risk_version',(SELECT body->'row'->'versions'->0->>'version' FROM drafted));
SELECT public.isg_workspace_risk_mutate_v1('a1000000-0000-4000-8000-000000000025',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('action','finalize','assessment_id',(SELECT value FROM integrated_state WHERE key='risk'),
    'expected_current',0,'version',(SELECT value::integer FROM integrated_state WHERE key='risk_version'),
    'period_years',2));
WITH opened AS (
  SELECT public.isg_workspace_nonconformity_mutate_v1('a1000000-0000-4000-8000-000000000026',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','create','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'source_kind','manual','title','Koruyucu eksik','severity','high',
      'opened_on',(clock_timestamp() AT TIME ZONE 'UTC')::date,
      'due_on',(clock_timestamp() AT TIME ZONE 'UTC')::date+7)) body
)
INSERT INTO integrated_state VALUES('nonconformity',(SELECT body->'row'->>'nonconformity_id' FROM opened));
SELECT public.isg_workspace_nonconformity_mutate_v1('a1000000-0000-4000-8000-000000000027',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('action','transition','id',(SELECT value FROM integrated_state WHERE key='nonconformity'),
    'expected_version',0,'to_state','open'));

INSERT INTO private_isg.checklist_templates(template_code,title) VALUES('integration_check','Entegrasyon kontrolü');
INSERT INTO private_isg.checklist_template_versions(template_code,version,status,approved_by,approval_note,published_at)
VALUES('integration_check',1,'published','20000000-0000-0000-0000-000000000001','sentetik',clock_timestamp());
INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,position)
VALUES('integration_check',1,'guard','Koruyucu mevcut mu?',1);
WITH opened AS (
  SELECT public.isg_workspace_checklist_mutate_v1('a1000000-0000-4000-8000-000000000028',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','create','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'template_code','integration_check','template_version',1,
      'started_on',(clock_timestamp() AT TIME ZONE 'UTC')::date)) body
)
INSERT INTO integrated_state VALUES
  ('checklist',(SELECT body->'row'->>'run_id' FROM opened)),
  ('checklist_version',(SELECT body->'row'->>'version' FROM opened));
WITH answered AS (
  SELECT public.isg_workspace_checklist_mutate_v1('a1000000-0000-4000-8000-000000000029',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','answer','id',(SELECT value FROM integrated_state WHERE key='checklist'),
      'expected_version',(SELECT value::bigint FROM integrated_state WHERE key='checklist_version'),
      'item_code','guard','result','nonconform','severity','medium',
      'due_on',(clock_timestamp() AT TIME ZONE 'UTC')::date+5)) body
)
UPDATE integrated_state SET value=(SELECT body->'row'->>'version' FROM answered) WHERE key='checklist_version';
SELECT public.isg_workspace_checklist_mutate_v1('a1000000-0000-4000-8000-000000000030',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('action','submit','id',(SELECT value FROM integrated_state WHERE key='checklist'),
    'expected_version',(SELECT value::bigint FROM integrated_state WHERE key='checklist_version')));
DO $$ DECLARE assurance jsonb; BEGIN
  assurance:=public.isg_workspace_assurance_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  IF (assurance->'risk'->>'total')::integer<>1 OR
     (assurance->'nonconformity'->>'total')::integer<>2 OR
     (assurance->'checklists'->>'submitted')::integer<>1 THEN
    RAISE EXCEPTION 'assurance metrics failed: %',assurance; END IF;
END $$;

-- D4 snapshots the selected company employee into an emergency team, keeps a
-- performed drill pinned to that plan version, records an effective-dated
-- appointment and tracks a partial PPE return without losing its author.
WITH published AS (
  SELECT public.isg_workspace_safety_mutate_v1('a1000000-0000-4000-8000-000000000031',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('entity','plan','action','publish',
      'workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'scope','Tüm işyeri','prepared_on',(clock_timestamp() AT TIME ZONE 'UTC')::date,
      'valid_until',(clock_timestamp() AT TIME ZONE 'UTC')::date+365,
      'team',jsonb_build_array(jsonb_build_object(
        'employee_id',(SELECT value FROM integrated_state WHERE key='employee'),
        'role','coordinator','contact','Dahili 101')))) body
)
INSERT INTO integrated_state VALUES
  ('emergency_plan',(SELECT body->'row'->>'plan_id' FROM published)),
  ('emergency_plan_version',(SELECT body->'row'->>'version' FROM published));
WITH planned AS (
  SELECT public.isg_workspace_safety_mutate_v1('a1000000-0000-4000-8000-000000000032',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('entity','drill','action','create',
      'workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'plan_id',(SELECT value FROM integrated_state WHERE key='emergency_plan'),
      'plan_version',(SELECT value::integer FROM integrated_state WHERE key='emergency_plan_version'),
      'planned_on',(clock_timestamp() AT TIME ZONE 'UTC')::date)) body
)
INSERT INTO integrated_state VALUES('drill',(SELECT body->'row'->>'drill_id' FROM planned));
SELECT public.isg_workspace_safety_mutate_v1('a1000000-0000-4000-8000-000000000033',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('entity','drill','action','perform','id',(SELECT value FROM integrated_state WHERE key='drill'),
    'expected_version',0,'performed_on',(clock_timestamp() AT TIME ZONE 'UTC')::date,
    'participants',jsonb_build_array((SELECT value FROM integrated_state WHERE key='employee')),
    'observation','Sentetik tatbikat','improvement','Çıkış levhası kontrol edildi'));
WITH appointed AS (
  SELECT public.isg_workspace_safety_mutate_v1('a1000000-0000-4000-8000-000000000034',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('entity','appointment','action','create',
      'employee_id',(SELECT value FROM integrated_state WHERE key='employee'),'kind','representative',
      'workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'starts_on',(clock_timestamp() AT TIME ZONE 'UTC')::date)) body
)
INSERT INTO integrated_state VALUES('appointment',(SELECT body->'row'->>'appointment_id' FROM appointed));
DO $$ BEGIN
  PERFORM public.isg_workspace_safety_mutate_v1('a1000000-0000-4000-8000-000000000037',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('entity','appointment','action','create',
      'employee_id',(SELECT value FROM integrated_state WHERE key='employee'),'kind','representative',
      'workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'starts_on',(clock_timestamp() AT TIME ZONE 'UTC')::date));
  RAISE EXCEPTION 'EXPECTED_APPOINTMENT_OVERLAP';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'APPOINTMENT_OVERLAP' THEN RAISE; END IF;
END $$;
WITH handed AS (
  SELECT public.isg_workspace_safety_mutate_v1('a1000000-0000-4000-8000-000000000035',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('entity','ppe','action','handover',
      'employee_id',(SELECT value FROM integrated_state WHERE key='employee'),
      'item','Koruyucu gözlük','quantity',2,'unit','piece',
      'handed_on',(clock_timestamp() AT TIME ZONE 'UTC')::date-2,'external_ref','PPE-INTEGRATION-1')) body
)
INSERT INTO integrated_state VALUES('ppe_handover',(SELECT body->'row'->>'handover_id' FROM handed));
SELECT public.isg_workspace_safety_mutate_v1('a1000000-0000-4000-8000-000000000036',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('entity','ppe','action','return','id',(SELECT value FROM integrated_state WHERE key='ppe_handover'),
    'quantity',1,'returned_on',(clock_timestamp() AT TIME ZONE 'UTC')::date-1,
    'condition','reusable','note','Sentetik iade'));
DO $$ DECLARE safety jsonb; BEGIN
  safety:=public.isg_workspace_safety_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  IF (safety->'plans'->>'active')::integer<>1 OR (safety->'drills'->>'performed')::integer<>1 OR
     (safety->'appointments'->>'active')::integer<>1 OR (safety->'ppe'->>'handovers')::integer<>1 OR
     (safety->'ppe'->>'outstanding_quantity')::numeric<>1 THEN
    RAISE EXCEPTION 'safety metrics failed: %',safety; END IF;
END $$;

-- D5 keeps equipment inventory separate from inspection history while the
-- mutation boundary still supports the compact register-and-check workflow.
WITH registered AS (
  SELECT public.isg_workspace_equipment_mutate_v1('a1000000-0000-4000-8000-000000000038',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','register','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'equipment_type','forklift','equipment_type_label','Forklift','serial_tag','FLT-100',
      'acquired_on',DATE '2025-01-01','location_note','Ana depo')) body
)
INSERT INTO integrated_state VALUES
  ('equipment',(SELECT body->'row'->>'equipment_id' FROM registered)),
  ('equipment_version',(SELECT body->'row'->>'version' FROM registered));
DO $$ DECLARE catalog jsonb; BEGIN
  catalog:=public.isg_workspace_equipment_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'catalog',NULL,NULL,NULL,NULL,50);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(catalog->'rules') rule
    WHERE rule->>'equipment_type'='forklift' AND rule->>'period_source'='regulation_default'
      AND (rule->>'period_months')::integer=12 AND (rule->>'needs_review')::boolean) THEN
    RAISE EXCEPTION 'default equipment period failed: %',catalog; END IF;
END $$;
SELECT public.isg_workspace_equipment_mutate_v1('a1000000-0000-4000-8000-000000000039',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('action','set_rule','equipment_type','forklift','period_months',12,
    'period_source','manufacturer','exception_note','Üretici bakım ve kontrol kılavuzu'));
WITH inspected AS (
  SELECT public.isg_workspace_equipment_mutate_v1('a1000000-0000-4000-8000-000000000040',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','record_inspection','id',(SELECT value FROM integrated_state WHERE key='equipment'),
      'expected_version',(SELECT value::bigint FROM integrated_state WHERE key='equipment_version'),
      'performed_on',(clock_timestamp() AT TIME ZONE 'UTC')::date-1,'result','pass',
      'inspector','Yetkili kontrol uzmanı','external_ref','RPR-100','note','Sentetik rapor',
      'katip_declared',true,'katip_note','Uzman beyanı')) body
)
INSERT INTO integrated_state VALUES
  ('inspection',(SELECT body->'row'->'inspections'->0->>'inspection_id' FROM inspected));
UPDATE integrated_state SET value=(SELECT version::text FROM private_isg.equipment_items
  WHERE equipment_id=(SELECT value::uuid FROM integrated_state WHERE key='equipment'))
  WHERE key='equipment_version';
WITH corrected AS (
  SELECT public.isg_workspace_equipment_mutate_v1('a1000000-0000-4000-8000-000000000041',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','update_inspection','id',(SELECT value FROM integrated_state WHERE key='equipment'),
      'inspection_id',(SELECT value FROM integrated_state WHERE key='inspection'),
      'expected_version',(SELECT value::bigint FROM integrated_state WHERE key='equipment_version'),
      'next_due_on',(clock_timestamp() AT TIME ZONE 'UTC')::date+400,'note','Uzman tarihi güncelledi')) body
)
UPDATE integrated_state SET value=(SELECT body->'row'->>'version' FROM corrected) WHERE key='equipment_version';
WITH registered AS (
  SELECT public.isg_workspace_equipment_mutate_v1('a1000000-0000-4000-8000-000000000042',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','register','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'equipment_type','laser_cutter','equipment_type_label','Lazer kesim makinesi','serial_tag','LZR-1')) body
)
INSERT INTO integrated_state VALUES('custom_equipment',(SELECT body->'row'->>'equipment_id' FROM registered));
SELECT public.isg_workspace_equipment_mutate_v1('a1000000-0000-4000-8000-000000000043',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('action','set_rule','equipment_type','laser_cutter','period_months',6,
    'period_source','unapproved_fixture','exception_note','Firma özel ekipmanı; uzman doğrulaması bekleniyor'));
DO $$ DECLARE equipment_metrics jsonb; BEGIN
  equipment_metrics:=public.isg_workspace_equipment_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  IF (equipment_metrics->>'total')::integer<>2 OR (equipment_metrics->>'current')::integer<>1 OR
     (equipment_metrics->>'untracked')::integer<>1 OR
     (equipment_metrics->>'periods_needing_review')::integer<>1 THEN
    RAISE EXCEPTION 'equipment metrics failed: %',equipment_metrics; END IF;
END $$;

-- The verified credit purchase funds an upload-backed AI job and its immutable usage entry.
INSERT INTO private_isg.workspace_ai_pricing(feature,model_code,pricing_version,reserve_units,max_settle_units,active)
VALUES('photo_analysis','integration-model','integration-v1',20,20,true);
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
SELECT public.isg_workspace_member_quota_set_v1(
  'a1000000-0000-4000-8000-000000000018',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='source_membership'),
  to_char(clock_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM'),20,0);

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
WITH opened AS (
  SELECT public.isg_workspace_upload_open_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    'a1000000-0000-4000-8000-000000000009',sha256('integration-upload'::bytea),
    'analysis_source','image/jpeg','jpg',4096,clock_timestamp()+interval '10 minutes') body
)
INSERT INTO integrated_state VALUES
  ('upload_token',(SELECT body->>'upload_token' FROM opened)),
  ('source_asset',(SELECT body->>'intent_id' FROM opened));
SELECT private_isg.workspace_upload_finalize_via_token(
  (SELECT value FROM integrated_state WHERE key='upload_token'),'source-v1',2048,
  sha256('integration-source-bytes'::bytea),clock_timestamp());

-- D7 files separate the physical object from each scoped filing. The same
-- source asset becomes a company logo entry, is linked to the company and then
-- cannot be physically deleted while that immutable revision remains.
WITH created AS (
  SELECT public.isg_workspace_file_mutate_v1('a1000000-0000-4000-8000-000000000060',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','create','asset_id',(SELECT value FROM integrated_state WHERE key='source_asset'),
      'category','company_logo','title','Entegre firma logosu','original_filename','logo.jpg',
      'tags',jsonb_build_array('marka','rapor'))) body
)
INSERT INTO integrated_state VALUES('file_entry',(SELECT body->>'entry_id' FROM created));
WITH linked AS (
  SELECT public.isg_workspace_file_mutate_v1('a1000000-0000-4000-8000-000000000061',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','set_company_logo','entry_id',(SELECT value FROM integrated_state WHERE key='file_entry'))) body
)
INSERT INTO integrated_state VALUES('file_reference',(SELECT body->>'reference_id' FROM linked));
DO $$ DECLARE files jsonb; BEGIN
  files:=public.isg_workspace_file_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),NULL,'marka','company_logo',false,20);
  IF jsonb_array_length(files->'rows')<>1 OR files->'rows'->0->>'title'<>'Entegre firma logosu' OR
     (SELECT workspace_logo_entry_id::text FROM public.companies WHERE id=(SELECT value::uuid FROM integrated_state WHERE key='company'))
       IS DISTINCT FROM (SELECT value FROM integrated_state WHERE key='file_entry') THEN
    RAISE EXCEPTION 'file filing or company logo failed: %',files; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_asset_delete_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='source_asset'),'referenced asset must remain');
  RAISE EXCEPTION 'EXPECTED_REFERENCED_ASSET_DELETE_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSET_IN_USE' THEN RAISE; END IF;
END $$;

-- D6 operational records share the same company, author and assignment scope.
-- Official KATİP integration, work authorization and AI-as-official-record stay
-- structurally false.
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000045',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','katip_contract','action','create','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'counterparty','Entegre OSGB','expert_contact','Ayşe Uzman','scope','İş güvenliği uzmanlığı',
      'starts_on',(clock_timestamp() AT TIME ZONE 'UTC')::date-30,'declared_monthly_minutes',600,
      'workspace_asset_id',(SELECT value FROM integrated_state WHERE key='source_asset'))) body
)
INSERT INTO integrated_state VALUES('katip_contract',(SELECT body->>'id' FROM created));
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000046',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','annual_plan','action','create','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'plan_year',extract(year FROM clock_timestamp() AT TIME ZONE 'UTC')::integer)) body
)
INSERT INTO integrated_state VALUES('annual_plan',(SELECT body->>'id' FROM created));
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000047',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','annual_item','action','create','plan_id',(SELECT value FROM integrated_state WHERE key='annual_plan'),
      'activity','Saha turu','responsible_contact','Ayşe Uzman',
      'planned_on',make_date(extract(year FROM clock_timestamp() AT TIME ZONE 'UTC')::integer,12,1))) body
)
INSERT INTO integrated_state VALUES('annual_item',(SELECT body->>'id' FROM created));
SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000048',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('kind','annual_item','action','perform','id',(SELECT value FROM integrated_state WHERE key='annual_item'),
    'expected_version',0,'performed_on',(clock_timestamp() AT TIME ZONE 'UTC')::date));
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000049',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','board','action','create','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'applicability','voluntary','planned_on',(clock_timestamp() AT TIME ZONE 'UTC')::date,
      'agenda',jsonb_build_array('Saha güvenliği'))) body
)
INSERT INTO integrated_state VALUES('board',(SELECT body->>'id' FROM created));
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000050',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','board_decision','action','create','meeting_id',(SELECT value FROM integrated_state WHERE key='board'),
      'decision_no',1,'decision_text','Çıkış levhası kontrol edilsin','responsible_contact','Ayşe Uzman',
      'due_on',(clock_timestamp() AT TIME ZONE 'UTC')::date+10)) body
)
INSERT INTO integrated_state VALUES('board_decision',(SELECT body->>'id' FROM created));
SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000051',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),
  jsonb_build_object('kind','board','action','hold','id',(SELECT value FROM integrated_state WHERE key='board'),
    'expected_version',0,'held_on',(clock_timestamp() AT TIME ZONE 'UTC')::date,
    'attendance',jsonb_build_array((SELECT value FROM integrated_state WHERE key='employee')),
    'workspace_asset_id',(SELECT value FROM integrated_state WHERE key='source_asset')));
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000052',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','work_permit','action','create','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'template_code','hot_work','job_description','Sentetik sıcak çalışma','parties',jsonb_build_array('Bakım ekibi'),
      'planned_on',(clock_timestamp() AT TIME ZONE 'UTC')::date,'work_location','Atölye',
      'workspace_asset_id',(SELECT value FROM integrated_state WHERE key='source_asset'))) body
)
INSERT INTO integrated_state VALUES('work_permit',(SELECT body->>'id' FROM created));
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000053',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','site_visit','action','create','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'visited_on',(clock_timestamp() AT TIME ZONE 'UTC')::date,'location_note','Atölye',
      'expert_note','Sentetik saha ziyareti','responsible_contact','Ayşe Uzman')) body
)
INSERT INTO integrated_state VALUES('site_visit',(SELECT body->>'id' FROM created));
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000054',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','site_observation','action','create','visit_id',(SELECT value FROM integrated_state WHERE key='site_visit'),
      'note','Koruyucu kontrol edildi','nonconformity_id',(SELECT value FROM integrated_state WHERE key='nonconformity'),
      'workspace_asset_id',(SELECT value FROM integrated_state WHERE key='source_asset'))) body
)
INSERT INTO integrated_state VALUES('site_observation',(SELECT body->>'id' FROM created));
WITH created AS (
  SELECT public.isg_workspace_operations_mutate_v1('a1000000-0000-4000-8000-000000000055',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('kind','notebook_archive','action','create','workplace_id',(SELECT value FROM integrated_state WHERE key='workplace'),
      'notebook_ref','OD-1','entry_on',(clock_timestamp() AT TIME ZONE 'UTC')::date,
      'workspace_asset_id',(SELECT value FROM integrated_state WHERE key='source_asset'),'ai_draft_ref','draft-only')) body
)
INSERT INTO integrated_state VALUES('notebook_archive',(SELECT body->>'id' FROM created));
DO $$ DECLARE operations_metrics jsonb; BEGIN
  operations_metrics:=public.isg_workspace_operations_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'));
  IF (operations_metrics->>'katip_active')::integer<>1 OR (operations_metrics->>'annual_open_items')::integer<>0 OR
     (operations_metrics->>'board_open_decisions')::integer<>1 OR (operations_metrics->>'work_permits')::integer<>1 OR
     (operations_metrics->>'site_visits')::integer<>1 OR (operations_metrics->>'notebook_archives')::integer<>1 THEN
    RAISE EXCEPTION 'operations metrics failed: %',operations_metrics; END IF;
END $$;

WITH submitted AS (
  SELECT public.isg_workspace_ai_submit_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'photo_analysis',
    'integration-model','integration-v1','a1000000-0000-4000-8000-000000000010',
    sha256('integration-ai'::bytea),'photo',
    (SELECT value FROM integrated_state WHERE key='source_asset'),1) body
)
INSERT INTO integrated_state VALUES('ai_job',(SELECT body->>'job_id' FROM submitted));
SELECT private_isg.workspace_ai_start((SELECT value::uuid FROM integrated_state WHERE key='ai_job'),
  sha256('integration-provider'::bytea),clock_timestamp());
SELECT private_isg.workspace_ai_complete((SELECT value::uuid FROM integrated_state WHERE key='ai_job'),
  12,900,180,'a1000000-0000-4000-8000-000000000011','generated',
  'integration/result.json','result-v1',1024,sha256('integration-result'::bytea),clock_timestamp());

-- D8 commits the structured result only after the pinned AI job succeeds.
-- Scoreless findings are expert-review items; they must not disappear from the
-- result hub or be reported as a zero-count section.
WITH committed AS (
  SELECT private_isg.workspace_analysis_commit(
    (SELECT value::uuid FROM integrated_state WHERE key='ai_job'),
    jsonb_build_object(
      'title','Entegre saha analizi','kind','photo','primary_method','fine_kinney',
      'findings',jsonb_build_array(
        jsonb_build_object('source_key','risk-1','ordinal',1,'display_order',1,
          'item_class','observed_finding','is_scored',true,'title','Koruyucusuz makine',
          'description','Hareketli parça koruyucusu bulunmuyor.','recommended_action','Koruyucu takın.',
          'references_text','İş ekipmanı güvenliği','responsible','İşveren',
          'fk_probability',3,'fk_frequency',6,'fk_severity',15,'fk_band','high',
          'm5_probability',4,'m5_severity',4,'m5_band','high','source_photo_indices',jsonb_build_array(0)),
        jsonb_build_object('source_key','review-1','ordinal',2,'display_order',2,
          'item_class','verification_request','is_scored',false,'title','Elektrik panosu doğrulaması',
          'description','Pano içeriği fotoğraftan doğrulanamadı.','recommended_action','Yetkili kişi yerinde kontrol etsin.',
          'references_text','Uzman doğrulaması gerekli','source_photo_indices',jsonb_build_array(0))),
      'expert_items',jsonb_build_array(
        jsonb_build_object('source_key','expert-1','display_order',3,'title','Uzman saha görüşü',
          'body','Makine çevresindeki erişim sınırlandırılmalıdır.','recommendation','Bariyer yerleşimini doğrulayın.',
          'source_finding_keys',jsonb_build_array('risk-1'))),
      'training_items',jsonb_build_array(
        jsonb_build_object('source_key','training-1','catalog_code','machine_safety','display_order',1,
          'title','Makine güvenliği eğitimi','audience','Operatörler','body','Koruyucu ve LOTO uygulaması',
          'duration_minutes',60,'source_finding_keys',jsonb_build_array('risk-1'))))) body
)
INSERT INTO integrated_state VALUES('analysis',(SELECT body->>'analysis_id' FROM committed));
INSERT INTO integrated_state
SELECT 'analysis_finding',id::text FROM private_isg.workspace_analysis_findings
  WHERE analysis_id=(SELECT value::uuid FROM integrated_state WHERE key='analysis') AND source_key='risk-1';
INSERT INTO integrated_state
SELECT 'analysis_expert',id::text FROM private_isg.workspace_analysis_expert_items
  WHERE analysis_id=(SELECT value::uuid FROM integrated_state WHERE key='analysis') AND source_key='expert-1';
DO $$ DECLARE result_hub jsonb; analysis_list jsonb; BEGIN
  analysis_list:=public.isg_workspace_analysis_list_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),0,30);
  result_hub:=public.isg_workspace_analysis_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='analysis'));
  IF (analysis_list->>'returned')::integer<>1 OR analysis_list->'rows'->0->>'title'<>'Entegre saha analizi' OR
     analysis_list->'rows'->0->>'highest_band'<>'high' OR
     (result_hub->'counts'->>'risk')::integer<>1 OR (result_hub->'counts'->>'expert')::integer<>2 OR
     (result_hub->'counts'->>'training')::integer<>1 OR
     NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result_hub->'expert_items') x WHERE x->>'kind'='unscored_finding') THEN
    RAISE EXCEPTION 'analysis result projection failed: %',result_hub; END IF;
END $$;

-- Filing succeeds only when the immutable source snapshot and the list-visible
-- nonconformity commit in the same transaction.
WITH filed AS (
  SELECT public.isg_workspace_analysis_file_v1('a1000000-0000-4000-8000-000000000062',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='workplace'),'workspace',
    (SELECT value::uuid FROM integrated_state WHERE key='analysis'),'finding',
    (SELECT value::uuid FROM integrated_state WHERE key='analysis_finding'),NULL,
    (clock_timestamp() AT TIME ZONE 'UTC')::date,(clock_timestamp() AT TIME ZONE 'UTC')::date+7) body
)
INSERT INTO integrated_state VALUES('analysis_nonconformity',(SELECT body->>'nonconformity_id' FROM filed));
DO $$ DECLARE listed jsonb; detail jsonb; BEGIN
  listed:=public.isg_workspace_nonconformity_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),NULL,NULL,100);
  detail:=public.isg_workspace_nonconformity_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='analysis_nonconformity'),NULL,1);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(listed->'rows') x
      WHERE x->>'nonconformity_id'=(SELECT value FROM integrated_state WHERE key='analysis_nonconformity')) OR
     detail->'row'->'source_snapshot'->>'description'<>'Hareketli parça koruyucusu bulunmuyor.' THEN
    RAISE EXCEPTION 'analysis filing is not visible with detail: %, %',listed,detail; END IF;
END $$;

-- The migration bridge may explicitly file a personal result into a company,
-- while ownership of the original analysis remains personal.
INSERT INTO public.analyses(id,user_id,title,kind,status,primary_method)
VALUES('a1000000-0000-4000-8000-000000000090','20000000-0000-0000-0000-000000000002',
  'Kişisel geçiş analizi','photo','completed','fine_kinney');
INSERT INTO public.findings(id,analysis_id,user_id,ordinal,title,description,recommended_action,references_text,
  responsible,fk_probability,fk_frequency,fk_severity,fk_score,fk_band,m5_probability,m5_severity,m5_score,m5_band,is_scored)
VALUES('a1000000-0000-4000-8000-000000000091','a1000000-0000-4000-8000-000000000090',
  '20000000-0000-0000-0000-000000000002',1,'Kişisel kaynak bulgusu','Kaynak açıklaması','Önlem alın','Kaynak','İşveren',
  3,3,15,135,'high',4,4,16,'high',true);
DO $$ DECLARE filed jsonb; BEGIN
  filed:=public.isg_workspace_analysis_file_v1('a1000000-0000-4000-8000-000000000063',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='workplace'),'personal',
    'a1000000-0000-4000-8000-000000000090','finding','a1000000-0000-4000-8000-000000000091',NULL,
    (clock_timestamp() AT TIME ZONE 'UTC')::date,NULL);
  IF filed->>'commit_state'<>'committed_and_visible' OR filed->>'success_message_key'<>'analysis_finding_filed' THEN
    RAISE EXCEPTION 'personal analysis filing failed: %',filed; END IF;
END $$;

WITH requested AS (
  SELECT public.isg_workspace_export_create_v1('a1000000-0000-4000-8000-000000000064',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='analysis'),'pdf',
    jsonb_build_object('finding_ids',jsonb_build_array((SELECT value FROM integrated_state WHERE key='analysis_finding')),
      'expert_item_ids',jsonb_build_array((SELECT value FROM integrated_state WHERE key='analysis_expert')),
      'training_item_ids','[]'::jsonb)) body
)
INSERT INTO integrated_state VALUES('export_job',(SELECT body->'row'->>'id' FROM requested));
SELECT private_isg.workspace_export_start((SELECT value::uuid FROM integrated_state WHERE key='export_job'),clock_timestamp());
INSERT INTO private_isg.workspace_file_assets(id,workspace_id,company_id,uploaded_by_membership_id,source_kind,
  bucket,object_path,object_version,byte_size,sha256,lifecycle,media_type,extension,finalized_at)
VALUES('a1000000-0000-4000-8000-000000000012',(SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),
  (SELECT value::uuid FROM integrated_state WHERE key='source_membership'),'generated','generated',
  'integration/export.pdf','export-v1',4096,sha256('integration-export'::bytea),'active','application/pdf','pdf',clock_timestamp());
SELECT private_isg.workspace_export_complete((SELECT value::uuid FROM integrated_state WHERE key='export_job'),
  'a1000000-0000-4000-8000-000000000012',clock_timestamp());
DO $$ DECLARE exported jsonb; BEGIN
  exported:=public.isg_workspace_export_get_v1((SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='export_job'));
  IF exported->'row'->>'status'<>'succeeded' OR exported->'row'->>'output_asset_id'<>'a1000000-0000-4000-8000-000000000012' THEN
    RAISE EXCEPTION 'export completion failed: %',exported; END IF;
END $$;

-- D9 binds a signed PPE form to an immutable logical file revision. Merely
-- sending signed_copy=true through the older safety command still fails closed.
WITH created AS (
  SELECT public.isg_workspace_file_mutate_v1('a1000000-0000-4000-8000-000000000065',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    jsonb_build_object('action','create','asset_id','a1000000-0000-4000-8000-000000000012',
      'category','other','title','İmzalı KKD teslim formu','original_filename','kkd-teslim.pdf')) body
)
INSERT INTO integrated_state VALUES('signed_ppe_file',(SELECT body->>'entry_id' FROM created));
WITH handed AS (
  SELECT public.isg_workspace_ppe_signed_handover_v1('a1000000-0000-4000-8000-000000000066',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='employee'),'Koruyucu gözlük',1,'piece',
    (clock_timestamp() AT TIME ZONE 'UTC')::date,'KKD-SIGNED-1',
    (SELECT value::uuid FROM integrated_state WHERE key='signed_ppe_file')) body
)
INSERT INTO integrated_state VALUES('signed_ppe',(SELECT body->>'handover_id' FROM handed));
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM private_isg.ppe_handovers h WHERE h.handover_id=
      (SELECT value::uuid FROM integrated_state WHERE key='signed_ppe') AND h.signed_copy AND
      h.signed_file_entry_id=(SELECT value::uuid FROM integrated_state WHERE key='signed_ppe_file')) OR
     NOT EXISTS(SELECT 1 FROM private_isg.workspace_file_references r WHERE r.parent_kind='ppe' AND
      r.parent_id=(SELECT value::uuid FROM integrated_state WHERE key='signed_ppe') AND r.field_name='signed_copy') THEN
    RAISE EXCEPTION 'signed PPE evidence link failed'; END IF;
END $$;

DO $$ DECLARE dashboard jsonb; searched jsonb; changes jsonb; BEGIN
  dashboard:=public.isg_workspace_dashboard_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  searched:=public.isg_workspace_search_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'Koruyucusuz',NULL,NULL,20);
  changes:=public.isg_workspace_change_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),0,100);
  IF (dashboard->'companies'->>'total')::integer<>1 OR (dashboard->'nonconformities'->>'open')::integer<2 OR
     jsonb_array_length(searched->'rows')<>1 OR searched->'rows'->0->>'kind'<>'nonconformity' OR
     jsonb_array_length(changes->'rows')=0 THEN
    RAISE EXCEPTION 'tracking projection failed: %, %, %',dashboard,searched,changes; END IF;
END $$;

WITH queued AS (
  SELECT private_isg.workspace_notification_enqueue(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='source_membership'),'deadline_soon','nonconformity',
    (SELECT value::uuid FROM integrated_state WHERE key='analysis_nonconformity'),'analysis-nc-due-soon',
    clock_timestamp(),'/nonconformity/detail') body
)
INSERT INTO integrated_state VALUES('notification_job',(SELECT body->>'job_id' FROM queued));
WITH claimed AS (SELECT private_isg.workspace_notification_claim(10,clock_timestamp(),60) body)
INSERT INTO integrated_state VALUES(
  'notification_token',(SELECT body->'jobs'->0->>'lease_token' FROM claimed));
SELECT private_isg.workspace_notification_complete(
  (SELECT value::uuid FROM integrated_state WHERE key='notification_job'),
  (SELECT value::uuid FROM integrated_state WHERE key='notification_token'),true,NULL,clock_timestamp());

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_personnel_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'employees','',false,NULL,NULL,20);
  RAISE EXCEPTION 'EXPECTED_UNASSIGNED_PERSONNEL_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_training_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),NULL,NULL,20);
  RAISE EXCEPTION 'EXPECTED_UNASSIGNED_TRAINING_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_assurance_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  RAISE EXCEPTION 'EXPECTED_UNASSIGNED_ASSURANCE_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_safety_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  RAISE EXCEPTION 'EXPECTED_UNASSIGNED_SAFETY_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_equipment_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  RAISE EXCEPTION 'EXPECTED_UNASSIGNED_EQUIPMENT_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_operations_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  RAISE EXCEPTION 'EXPECTED_UNASSIGNED_OPERATIONS_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_file_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),NULL,NULL,NULL,false,20);
  RAISE EXCEPTION 'EXPECTED_UNASSIGNED_FILE_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);

-- A token issued before handover must fail when the source expert loses the
-- assignment. The target expert can open and deliver a fresh download.
WITH opened AS (
  SELECT public.isg_workspace_download_open_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='source_asset'),'review',
    clock_timestamp()+interval '3 minutes') body
)
INSERT INTO integrated_state VALUES('old_download_token',(SELECT body->>'download_token' FROM opened));

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH previewed AS (
  SELECT public.isg_workspace_handover_preview_v1('a1000000-0000-4000-8000-000000000012',
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='source_membership'),
    (SELECT value::uuid FROM integrated_state WHERE key='target_membership'),
    ARRAY[(SELECT value::uuid FROM integrated_state WHERE key='company')],
    clock_timestamp()-interval '1 minute','sorumluluk devri') body
)
INSERT INTO integrated_state VALUES
  ('handover',(SELECT body->>'handover_id' FROM previewed)),
  ('handover_hash',(SELECT body->>'preview_hash' FROM previewed));
SELECT public.isg_workspace_handover_execute_v1('a1000000-0000-4000-8000-000000000013',
  (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
  (SELECT value::uuid FROM integrated_state WHERE key='handover'),
  (SELECT value::uuid FROM integrated_state WHERE key='company'),0,
  (SELECT value FROM integrated_state WHERE key='handover_hash'));

DO $$ BEGIN
  PERFORM private_isg.workspace_download_claim(
    (SELECT value FROM integrated_state WHERE key='old_download_token'),clock_timestamp());
  RAISE EXCEPTION 'EXPECTED_STALE_DOWNLOAD_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF;
END $$;

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
DO $$ DECLARE personnel jsonb; personnel_metrics jsonb; BEGIN
  personnel:=public.isg_workspace_personnel_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'employees','',false,NULL,NULL,20);
  personnel_metrics:=public.isg_workspace_personnel_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  IF jsonb_array_length(personnel->'rows')<>1 OR personnel->'rows'->0->>'name'<>'Ayşe Uzman' OR
     (personnel_metrics->'employees'->>'active')::integer<>1 OR
     (personnel_metrics->'departments'->>'active')::integer<>1 THEN
    RAISE EXCEPTION 'handover personnel visibility failed: %, metrics %',personnel,personnel_metrics; END IF;
END $$;
DO $$ DECLARE training jsonb; BEGIN
  training:=public.isg_workspace_training_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='training'),NULL,20);
  IF training->'row'->>'state'<>'completed' OR training->'row'->>'title'<>'Saha güvenliği' OR
     jsonb_array_length(training->'row'->'participants')<>1 THEN
    RAISE EXCEPTION 'handover training visibility failed: %',training; END IF;
END $$;
DO $$ DECLARE files jsonb; BEGIN
  files:=public.isg_workspace_file_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='file_entry'),NULL,NULL,false,20);
  IF files->'row'->>'title'<>'Entegre firma logosu' OR files->'row'->'asset'->>'byte_size'<>'2048' THEN
    RAISE EXCEPTION 'handover file visibility failed: %',files; END IF;
END $$;
DO $$ DECLARE risk jsonb; nonconformity jsonb; checklist jsonb; BEGIN
  risk:=public.isg_workspace_risk_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='risk'),20);
  nonconformity:=public.isg_workspace_nonconformity_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='nonconformity'),NULL,20);
  checklist:=public.isg_workspace_checklist_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='checklist'),20);
  IF risk->'row'->>'current_version'<>'1' OR nonconformity->'row'->>'state'<>'open' OR
     checklist->'rows'->0->>'state'<>'submitted' THEN
    RAISE EXCEPTION 'handover assurance visibility failed: %, %, %',risk,nonconformity,checklist; END IF;
END $$;
DO $$ DECLARE plans jsonb; drills jsonb; appointments jsonb; ppe jsonb; BEGIN
  plans:=public.isg_workspace_safety_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'plans',
    (SELECT value::uuid FROM integrated_state WHERE key='emergency_plan'),20);
  drills:=public.isg_workspace_safety_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'drills',
    (SELECT value::uuid FROM integrated_state WHERE key='drill'),20);
  appointments:=public.isg_workspace_safety_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'appointments',
    (SELECT value::uuid FROM integrated_state WHERE key='appointment'),20);
  ppe:=public.isg_workspace_safety_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'ppe',
    (SELECT value::uuid FROM integrated_state WHERE key='ppe_handover'),20);
  IF plans->'rows'->0->'team'->0->>'full_name'<>'Ayşe Uzman' OR
     drills->'rows'->0->>'state'<>'performed' OR
     drills->'rows'->0->'participants'->0->>'full_name'<>'Ayşe Uzman' OR
     appointments->'rows'->0->>'kind'<>'representative' OR
     (ppe->'rows'->0->>'returned_quantity')::numeric<>1 THEN
    RAISE EXCEPTION 'handover safety visibility failed: %, %, %, %',plans,drills,appointments,ppe; END IF;
END $$;
DO $$ DECLARE equipment jsonb; BEGIN
  equipment:=public.isg_workspace_equipment_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'detail',
    (SELECT value::uuid FROM integrated_state WHERE key='equipment'),NULL,NULL,NULL,20);
  IF equipment->'rows'->0->>'serial_tag'<>'FLT-100' OR
     equipment->'rows'->0->>'state'<>'valid' OR
     equipment->'rows'->0->>'due_source'<>'expert' OR
     equipment->'rows'->0->'inspections'->0->>'result'<>'pass' THEN
    RAISE EXCEPTION 'handover equipment visibility failed: %',equipment; END IF;
END $$;
DO $$ DECLARE katip jsonb; annual_plan jsonb; board jsonb; permit jsonb; visit jsonb; notebook jsonb; BEGIN
  katip:=public.isg_workspace_operations_read_v1((SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),'katip_contract',(SELECT value::uuid FROM integrated_state WHERE key='katip_contract'),20);
  annual_plan:=public.isg_workspace_operations_read_v1((SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),'annual_plan',(SELECT value::uuid FROM integrated_state WHERE key='annual_plan'),20);
  board:=public.isg_workspace_operations_read_v1((SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),'board',(SELECT value::uuid FROM integrated_state WHERE key='board'),20);
  permit:=public.isg_workspace_operations_read_v1((SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),'work_permit',(SELECT value::uuid FROM integrated_state WHERE key='work_permit'),20);
  visit:=public.isg_workspace_operations_read_v1((SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),'site_visit',(SELECT value::uuid FROM integrated_state WHERE key='site_visit'),20);
  notebook:=public.isg_workspace_operations_read_v1((SELECT value::uuid FROM integrated_state WHERE key='workspace'),(SELECT value::uuid FROM integrated_state WHERE key='company'),'notebook_archive',(SELECT value::uuid FROM integrated_state WHERE key='notebook_archive'),20);
  IF (katip->'rows'->0->>'official_integration')::boolean OR annual_plan->'rows'->0->'items'->0->>'state'<>'performed' OR
     board->'rows'->0->>'state'<>'held' OR (board->'rows'->0->>'counts_towards_legal_score')::boolean OR
     (permit->'rows'->0->>'authorises_work')::boolean OR jsonb_array_length(visit->'rows'->0->'observations')<>1 OR
     (notebook->'rows'->0->>'ai_text_is_official_record')::boolean THEN
    RAISE EXCEPTION 'handover operations visibility failed: %, %, %, %, %, %',katip,annual_plan,board,permit,visit,notebook; END IF;
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_personnel_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'employees','',false,NULL,NULL,20);
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_PERSONNEL_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_training_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),NULL,NULL,20);
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_TRAINING_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_assurance_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_ASSURANCE_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_safety_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_SAFETY_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_equipment_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_EQUIPMENT_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_operations_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'));
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_OPERATIONS_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_file_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),NULL,NULL,NULL,false,20);
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_FILE_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_analysis_read_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='analysis'));
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_ANALYSIS_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_export_get_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    (SELECT value::uuid FROM integrated_state WHERE key='export_job'));
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_EXPORT_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
DO $$ BEGIN
  PERFORM public.isg_workspace_search_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),'Koruyucusuz',NULL,NULL,20);
  RAISE EXCEPTION 'EXPECTED_TRANSFERRED_SEARCH_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'ASSIGNMENT_REQUIRED' THEN RAISE; END IF;
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
WITH opened AS (
  SELECT public.isg_workspace_download_open_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='source_asset'),'handover_review',
    clock_timestamp()+interval '3 minutes') body
), claimed AS (
  SELECT private_isg.workspace_download_claim((SELECT body->>'download_token' FROM opened),clock_timestamp()) body
)
INSERT INTO integrated_state VALUES('delivered_download',(SELECT body->>'download_id' FROM claimed));
SELECT private_isg.workspace_download_delivered(
  (SELECT value::uuid FROM integrated_state WHERE key='delivered_download'),'source-v1',2048,clock_timestamp());

-- Existing P16 authority sees aggregate state without direct table grants.
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true WHERE feature='workspace_admin';
INSERT INTO private_isg.admin_sessions(session_id,admin_user_id,assurance_level,granted_scopes,opened_at,expires_at)
VALUES('a1000000-0000-4000-8000-000000000014','a1000000-0000-4000-8000-000000000015','aal2',
  ARRAY['osgb.read'],clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1 hour');

DO $$ DECLARE metrics jsonb; BEGIN
  metrics:=public.isg_workspace_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    clock_timestamp()-interval '1 day',clock_timestamp());
  IF metrics->>'scope'<>'member' OR (metrics->'companies'->>'active')::integer<>1 OR
     (metrics->'storage'->>'current_bytes')::bigint<>0 OR metrics->'wallet'<>'null'::jsonb THEN
    RAISE EXCEPTION 'expert metrics leaked workspace aggregates: %',metrics; END IF;
END $$;

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
DO $$ DECLARE overview jsonb; memory jsonb; metrics jsonb; company_metrics jsonb;
  member_usage jsonb; member_quota jsonb; BEGIN
  overview:=private_isg.workspace_admin_overview('a1000000-0000-4000-8000-000000000014',100,clock_timestamp());
  memory:=public.isg_workspace_company_memory_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),20);
  metrics:=public.isg_workspace_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    clock_timestamp()-interval '1 day',clock_timestamp());
  company_metrics:=public.isg_workspace_company_metrics_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='company'),
    clock_timestamp()-interval '1 day',clock_timestamp());
  member_usage:=public.isg_workspace_member_usage_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    clock_timestamp()-interval '1 day',clock_timestamp(),20);
  member_quota:=public.isg_workspace_member_quota_get_v1(
    (SELECT value::uuid FROM integrated_state WHERE key='workspace'),
    (SELECT value::uuid FROM integrated_state WHERE key='source_membership'),
    to_char(clock_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM'));
  IF (SELECT status FROM private_isg.workspaces WHERE id=(SELECT value::uuid FROM integrated_state WHERE key='workspace'))<>'active' OR
     (SELECT count(*) FROM private_isg.workspace_memberships WHERE workspace_id=(SELECT value::uuid FROM integrated_state WHERE key='workspace') AND status='active')<>3 OR
     (SELECT count(*) FROM private_isg.workspace_seat_reservations WHERE workspace_id=(SELECT value::uuid FROM integrated_state WHERE key='workspace') AND status='activated')<>2 OR
     (SELECT count(*) FROM private_isg.company_assignments WHERE workspace_id=(SELECT value::uuid FROM integrated_state WHERE key='workspace') AND assignment_role='primary' AND ends_at IS NULL)<>1 OR
     (SELECT count(*) FROM private_isg.workspace_usage_records WHERE workspace_id=(SELECT value::uuid FROM integrated_state WHERE key='workspace'))<>1 OR
     (SELECT count(*) FROM private_isg.employees WHERE workspace_id=(SELECT value::uuid FROM integrated_state WHERE key='workspace')
       AND company_id=(SELECT value::uuid FROM integrated_state WHERE key='company') AND created_by_user_id='20000000-0000-0000-0000-000000000002')<>1 OR
     (SELECT count(*) FROM private_isg.workspace_purchase_intents WHERE workspace_id=(SELECT value::uuid FROM integrated_state WHERE key='workspace') AND state='verified')<>2 OR
     (SELECT posted_units FROM private_isg.workspace_wallets WHERE workspace_id=(SELECT value::uuid FROM integrated_state WHERE key='workspace'))<>88 OR
     (SELECT count(*) FROM private_isg.workspace_download_intents WHERE workspace_id=(SELECT value::uuid FROM integrated_state WHERE key='workspace') AND status='delivered')<>1 OR
     jsonb_array_length(memory->'rows')<>1 OR jsonb_array_length(overview->'rows')<>1 OR
     metrics->>'scope'<>'workspace' OR (metrics->'ai'->>'charged_units')::bigint<>12 OR
     (metrics->'storage'->>'current_bytes')::bigint<>7168 OR
     (metrics->'storage'->>'delivered_download_bytes')::bigint<>2048 OR
     (company_metrics->'assignments'->>'active')::integer<>1 OR
     jsonb_array_length(member_usage->'rows')<>3 OR
     (member_quota->>'configured')::boolean IS NOT TRUE OR
     (member_quota->>'used_units')::bigint<>12 OR
     (member_quota->>'remaining_units')::bigint<>8 OR
     (metrics->'operational_domains'->>'measured')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'integrated acceptance invariant failed: overview %, memory %, metrics %, company %, members %, quota %',
      overview,memory,metrics,company_metrics,member_usage,member_quota;
  END IF;
  IF has_table_privilege('authenticated','private_isg.workspace_wallet_entries','SELECT') OR
     has_function_privilege('authenticated','private_isg.workspace_provider_event_process(uuid)','EXECUTE') OR
     has_function_privilege('authenticated','private_isg.workspace_upload_finalize_via_token(text,text,bigint,bytea,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'integrated privilege boundary leak';
  END IF;
  RAISE NOTICE 'ok integrated subscription, seats, company, personnel, training, assurance, safety, equipment, operations, files, analysis, verified filing, export, tracking, notification lease, signed evidence, upload, AI wallet, quota, handover, revoked token, memory, metrics and admin projection';
END $$;
