-- Staging-only acceptance against the established OSGB expert fixture.
-- Every mutation is rolled back; the catalogue itself is read-only here.
BEGIN;
-- The owner creates a second rollback-only firm and assigns the same expert.
SELECT set_config('request.jwt.claims',jsonb_build_object(
  'sub','__OWNER_ID__','session_id','__OWNER_SESSION_ID__','role','authenticated',
  'exp',floor(extract(epoch from clock_timestamp())+3600))::text,true);
SET LOCAL ROLE authenticated;
SELECT set_config('isg.test_company2',(
  SELECT public.isg_workspace_company_create_v1(gen_random_uuid(),'__WORKSPACE_ID__'::uuid,
    'Staging ikinci firma · rollback','high')->>'company_id'),true);
SELECT public.isg_workspace_assignment_mutate_v1(gen_random_uuid(),'__WORKSPACE_ID__'::uuid,
  current_setting('isg.test_company2')::uuid,NULL,'__EXPERT_MEMBERSHIP_ID__'::uuid,0,
  'create','support',clock_timestamp()-interval '1 minute',NULL,'Checklist iki firma kabulü');
RESET ROLE;

SELECT set_config('request.jwt.claims',jsonb_build_object(
  'sub','__EXPERT_ID__',
  'session_id','__SESSION_ID__',
  'role','authenticated',
  'exp',floor(extract(epoch from clock_timestamp())+3600))::text,true);
SELECT set_config('isg.test_workplace',(
  SELECT id::text FROM private_isg.workplaces
  WHERE company_id='__COMPANY_ID__'::uuid AND NOT is_archived ORDER BY name LIMIT 1),true);
SELECT set_config('isg.test_workplace2',(
  SELECT id::text FROM private_isg.workplaces
  WHERE company_id=current_setting('isg.test_company2')::uuid AND NOT is_archived ORDER BY name LIMIT 1),true);
SET LOCAL ROLE authenticated;

DO $acceptance$
DECLARE
  workspace constant uuid := '__WORKSPACE_ID__';
  company constant uuid := '__COMPANY_ID__';
  company2 constant uuid := current_setting('isg.test_company2')::uuid;
  workplace constant uuid := current_setting('isg.test_workplace')::uuid;
  workplace2 constant uuid := current_setting('isg.test_workplace2')::uuid;
  library jsonb; turkish_search jsonb; detail jsonb; started jsonb; first_answer jsonb; repeated jsonb;
  drafted jsonb; template_view jsonb; template_row jsonb; assigned jsonb; assignment_view jsonb;
  template_code text; item_code text; run_id uuid; finding_id uuid; custom_code text;
  custom_first text; custom_second text; n integer;
  run_company1 uuid; run_company2 uuid; company1_answer jsonb; company2_answer jsonb;
  personal_started jsonb; personal_run uuid; personal_answer jsonb;
  nonconformity_detail jsonb;
  operation_id uuid := gen_random_uuid(); mutation_id uuid := gen_random_uuid();
BEGIN
  library := public.isg_expert_rpc_v1(workspace,'isg_checklists_read_v1',jsonb_build_object(
    'p_company',NULL,'p_kind','library','p_query','forklift','p_state',NULL,
    'p_workplace',NULL,'p_template',NULL,'p_id',NULL,'p_limit',30,'p_offset',0))->'payload';
  IF (library->>'total')::integer < 1 OR jsonb_array_length(library->'rows') < 1 OR
      jsonb_array_length(library->'matched_items') < 1 THEN
    RAISE EXCEPTION 'TURKISH_CATALOG_SEARCH_FAILED';
  END IF;
  IF library->>'professional_review_status'<>'approved' OR library->>'publication_status'<>'pilot_approved' THEN
    RAISE EXCEPTION 'CATALOG_PROFESSIONAL_APPROVAL_MISSING';
  END IF;
  turkish_search := public.isg_expert_rpc_v1(workspace,'isg_checklists_read_v1',jsonb_build_object(
    'p_company',NULL,'p_kind','library','p_query','acil çıkış','p_state',NULL,
    'p_workplace',NULL,'p_template',NULL,'p_id',NULL,'p_limit',30,'p_offset',0))->'payload';
  IF jsonb_array_length(turkish_search->'matched_items') < 1 THEN
    RAISE EXCEPTION 'TURKISH_LIVE_ITEM_SEARCH_FAILED';
  END IF;
  template_code := library#>>'{rows,0,template_code}';
  detail := public.isg_expert_rpc_v1(workspace,'isg_checklists_read_v1',jsonb_build_object(
    'p_company',NULL,'p_kind','template_detail','p_query',NULL,'p_state',NULL,
    'p_workplace',NULL,'p_template',template_code,'p_id',NULL,'p_limit',NULL,'p_offset',NULL))->'payload';
  IF jsonb_array_length(detail#>'{row,items}') <> 10 OR detail#>>'{row,catalog_version}' IS NULL THEN
    RAISE EXCEPTION 'CATALOG_DETAIL_FAILED';
  END IF;
  item_code := detail#>>'{row,items,0,item_code}';

  -- A user can build many independent lists and compose one from catalogue
  -- items without altering the product template.
  FOR n IN 1..15 LOOP
    drafted := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
      'p_company',NULL,'p_action','draft_template','p_operation',gen_random_uuid(),
      'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
        'title','Staging katalog kabul '||n::text)))->'payload';
    IF n=1 THEN custom_code:=drafted#>>'{answer,template_code}'; END IF;
  END LOOP;
  IF custom_code IS NULL THEN RAISE EXCEPTION 'CUSTOM_TEMPLATE_15_FAILED'; END IF;
  PERFORM set_config('isg.test_custom_code',custom_code,true);

  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',NULL,'p_action','copy_items','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'template_code',custom_code,'version',1,'expected_revision',0,
      'items',jsonb_build_array(jsonb_build_object(
        'source_template_code',template_code,'source_item_code',item_code,
        'section_title','Forklift','scope_key','forklift-1')))));
  BEGIN
    PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
      'p_company',NULL,'p_action','copy_items','p_operation',gen_random_uuid(),
      'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
        'template_code',custom_code,'version',1,'expected_revision',1,
        'items',jsonb_build_array(jsonb_build_object(
          'source_template_code',template_code,'source_item_code',item_code,
          'section_title','Forklift','scope_key','forklift-1')))));
    RAISE EXCEPTION 'DUPLICATE_ATOMIC_ITEM_ACCEPTED';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'DUPLICATE_CHECKLIST_ITEM' THEN RAISE; END IF;
  END;
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',NULL,'p_action','copy_items','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'template_code',custom_code,'version',1,'expected_revision',1,
      'items',jsonb_build_array(jsonb_build_object(
        'source_template_code',template_code,'source_item_code',item_code,
        'section_title','Forklift','scope_key','forklift-2')))));
  template_view := public.isg_expert_rpc_v1(workspace,'isg_checklists_read_v1',jsonb_build_object(
    'p_company',company,'p_kind','templates','p_query',NULL,'p_state',NULL,
    'p_workplace',NULL,'p_template',NULL,'p_id',NULL,'p_limit',NULL,'p_offset',NULL))->'payload';
  FOR template_row IN SELECT value FROM jsonb_array_elements(template_view->'rows') LOOP
    IF template_row->>'template_code'=custom_code THEN EXIT; END IF;
  END LOOP;
  custom_first:=template_row#>>'{versions,0,items,0,item_code}';
  custom_second:=template_row#>>'{versions,0,items,1,item_code}';
  IF custom_first IS NULL OR custom_second IS NULL THEN RAISE EXCEPTION 'COMPOSED_ITEMS_FAILED'; END IF;
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',NULL,'p_action','reorder_items','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'template_code',custom_code,'version',1,'expected_revision',2,
      'item_codes',jsonb_build_array(custom_second,custom_first))));
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',NULL,'p_action','publish_template','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'template_code',custom_code,'version',1,'expected_revision',3,
      'approval_note','Staging uzman kabulü')));

  -- A company-free run is owned by the expert/workspace, has a real question
  -- snapshot and never accepts a company finding or company attachment.
  personal_started := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',NULL,'p_action','start_run','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'template_code',template_code,'started_on',(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date,
      'area_label','Bağımsız saha')))->'payload';
  personal_run := (personal_started->>'run_id')::uuid;
  IF personal_run IS NULL OR (personal_started#>>'{row,snapshot_count}')::integer<>10 THEN
    RAISE EXCEPTION 'PERSONAL_RUN_SNAPSHOT_FAILED'; END IF;
  personal_answer := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',NULL,'p_action','record_item','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'run_id',personal_run,'item_code',item_code,'result','compliant','expected_revision',0)))->'payload';
  IF personal_answer#>>'{row,is_personal}' <> 'true' THEN RAISE EXCEPTION 'PERSONAL_RUN_SCOPE_FAILED'; END IF;
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',NULL,'p_action','cancel_run','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'run_id',personal_run,'expected_revision',1)));
  assigned := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','assign_template','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'template_code',custom_code,'workplace_id',workplace)))->'payload';
  assignment_view := public.isg_expert_rpc_v1(workspace,'isg_checklists_read_v1',jsonb_build_object(
    'p_company',company,'p_kind','assignments','p_query',NULL,'p_state',NULL,
    'p_workplace',NULL,'p_template',NULL,'p_id',NULL,'p_limit',NULL,'p_offset',NULL))->'payload';
  IF assigned#>>'{answer,assignment_id}' IS NULL OR NOT EXISTS(
      SELECT 1 FROM jsonb_array_elements(assignment_view->'rows') x
      WHERE x->>'template_code'=custom_code) THEN RAISE EXCEPTION 'ASSIGNMENT_READ_FAILED'; END IF;
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company2,'p_action','assign_template','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'template_code',custom_code,'workplace_id',workplace2)));

  run_company1 := (public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','start_run','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object('workplace_id',workplace,
      'template_code',custom_code,'started_on',(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date)))
      ->'payload'->>'run_id')::uuid;
  run_company2 := (public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company2,'p_action','start_run','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object('workplace_id',workplace2,
      'template_code',custom_code,'started_on',(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date)))
      ->'payload'->>'run_id')::uuid;
  company1_answer := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','record_item','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object('run_id',run_company1,
      'item_code',custom_second,'result','compliant','expected_revision',0)))->'payload';
  company2_answer := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company2,'p_action','record_item','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object('run_id',run_company2,
      'item_code',custom_second,'result','non_compliant','note','Firma 2 bağımsız sonucu',
      'expected_revision',0)))->'payload';
  IF company1_answer#>>'{answer,result}' <> 'conform' OR
     company2_answer#>>'{answer,result}' <> 'nonconform' THEN
    RAISE EXCEPTION 'MULTI_COMPANY_INDEPENDENCE_FAILED'; END IF;
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','cancel_run','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'run_id',run_company1,'expected_revision',1)));
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company2,'p_action','cancel_run','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'run_id',run_company2,'expected_revision',1)));

  started := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','start_run','p_operation',operation_id,'p_mutation',mutation_id,
    'p_payload',jsonb_build_object('workplace_id',workplace,'template_code',template_code,
      'started_on',(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date)))->'payload';
  run_id := (started->>'run_id')::uuid;
  IF run_id IS NULL OR started#>>'{row,catalog_version}' IS NULL OR
      jsonb_array_length(started#>'{row,items}') <> 10 THEN
    RAISE EXCEPTION 'PINNED_RUN_FAILED';
  END IF;

  BEGIN
    PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
      'p_company',company,'p_action','record_item','p_operation',gen_random_uuid(),
      'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
        'run_id',run_id,'item_code',item_code,'result','non_compliant','expected_revision',0,
        'open_nonconformity',false)));
    RAISE EXCEPTION 'EMPTY_NONCOMPLIANCE_EXPLANATION_ACCEPTED';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'EXPLANATION_REQUIRED' THEN RAISE; END IF;
  END;

  first_answer := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','record_item','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'run_id',run_id,'item_code',item_code,'result','non_compliant','expected_revision',0,
      'note','Staging kabul: uygunsuzluk açıklaması','open_nonconformity',true,
      'severity','medium')))->'payload';
  finding_id := (first_answer#>>'{answer,nonconformity_id}')::uuid;
  IF finding_id IS NULL THEN RAISE EXCEPTION 'EXPLICIT_NONCONFORMITY_NOT_CREATED'; END IF;
  nonconformity_detail := public.isg_expert_rpc_v1(workspace,'isg_nonconformity_read_v1',jsonb_build_object(
    'p_company',company,'p_kind','detail','p_query',NULL,'p_state',NULL,'p_after',NULL,
    'p_id',finding_id))->'payload';
  IF nonconformity_detail#>>'{row,detail,description}' <> 'Staging kabul: uygunsuzluk açıklaması' OR
     nonconformity_detail#>>'{row,source_kind}' <> 'checklist' THEN
    RAISE EXCEPTION 'CHECKLIST_NONCONFORMITY_DETAIL_MISSING';
  END IF;

  -- Fill the record from its normal detail editor. A later checklist answer
  -- may update the observation, but must retain these expert-maintained fields.
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_nonconformity_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','set_detail','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'nonconformity_id',finding_id,'description','Staging kabul: uygunsuzluk açıklaması',
      'control_measure','Staging kabul: düzeltici önlem','legislation_ref','Staging kabul mevzuatı',
      'responsible_contact','Staging sorumlusu')));

  BEGIN
    PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
      'p_company',company,'p_action','record_item','p_operation',gen_random_uuid(),
      'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
        'run_id',run_id,'item_code',item_code,'result','compliant','expected_revision',0)));
    RAISE EXCEPTION 'STALE_REVISION_ACCEPTED';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'CHECKLIST_CONFLICT' THEN RAISE; END IF;
  END;

  repeated := public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','record_item','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object(
      'run_id',run_id,'item_code',item_code,'result','non_compliant','expected_revision',1,
      'note','Staging kabul: güncellenmiş açıklama','open_nonconformity',true,
      'severity','medium')))->'payload';
  IF (repeated#>>'{answer,nonconformity_id}')::uuid IS DISTINCT FROM finding_id THEN
    RAISE EXCEPTION 'NONCONFORMITY_IDEMPOTENCY_FAILED';
  END IF;
  nonconformity_detail := public.isg_expert_rpc_v1(workspace,'isg_nonconformity_read_v1',jsonb_build_object(
    'p_company',company,'p_kind','detail','p_query',NULL,'p_state',NULL,'p_after',NULL,
    'p_id',finding_id))->'payload';
  IF nonconformity_detail#>>'{row,detail,description}' <> 'Staging kabul: güncellenmiş açıklama' OR
     nonconformity_detail#>>'{row,detail,control_measure}' <> 'Staging kabul: düzeltici önlem' OR
     nonconformity_detail#>>'{row,detail,responsible_contact}' <> 'Staging sorumlusu' THEN
    RAISE EXCEPTION 'CHECKLIST_NONCONFORMITY_MANUAL_DETAIL_LOST';
  END IF;

  PERFORM public.isg_expert_rpc_v1(workspace,'isg_checklists_mutate_v1',jsonb_build_object(
    'p_company',company,'p_action','cancel_run','p_operation',gen_random_uuid(),
    'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object('run_id',run_id,'expected_revision',2)));
END
$acceptance$;

RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object(
  'sub','__OWNER_ID__','session_id','__OWNER_SESSION_ID__','role','authenticated',
  'exp',floor(extract(epoch from clock_timestamp())+3600))::text,true);
SET LOCAL ROLE authenticated;
DO $cross_user$
BEGIN
  PERFORM public.isg_expert_rpc_v1('__WORKSPACE_ID__'::uuid,'isg_checklists_read_v1',jsonb_build_object(
    'p_company',NULL,'p_kind','template_detail','p_query',NULL,'p_state',NULL,
    'p_workplace',NULL,'p_template',current_setting('isg.test_custom_code'),
    'p_id',NULL,'p_limit',NULL,'p_offset',NULL));
  RAISE EXCEPTION 'CROSS_USER_TEMPLATE_READ_ACCEPTED';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM <> 'ACCESS_DENIED' THEN RAISE; END IF;
END
$cross_user$;
RESET ROLE;
ROLLBACK;
