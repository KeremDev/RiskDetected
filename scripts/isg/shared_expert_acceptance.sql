-- Run only inside an explicit BEGIN / ROLLBACK transaction with test-account
-- JWT claims and isg.test_workspace set by the runner. Never commits fixtures.
CREATE TEMP TABLE expert_acceptance_results(test text,passed boolean,detail text);
DO $test$
DECLARE workspace uuid:=current_setting('isg.test_workspace')::uuid;
 company uuid; employee uuid; workplace uuid; training uuid; result jsonb; replay jsonb;
 mutation uuid:=gen_random_uuid(); operation uuid:=gen_random_uuid(); args jsonb; detail text;
BEGIN
 result:=public.isg_expert_rpc_v1(workspace,'isg_expert_companies_v1','{"p_archived":false}') -> 'payload';
 company:=(result#>>'{rows,0,id}')::uuid;
 IF company IS NULL THEN RAISE EXCEPTION 'TEST_ASSIGNED_COMPANY_REQUIRED'; END IF;
 BEGIN
  args:=jsonb_build_object('p_company',company,'p_action','create','p_operation',operation,'p_mutation',mutation,
   'p_employee',NULL,'p_expected',0,'p_name','Shared panel rollback fixture','p_change_department',true,
   'p_department',NULL,'p_department_name','Shared panel rollback department');
  result:=public.isg_expert_rpc_v1(workspace,'isg_personnel_mutate_v1',args)->'payload';
  employee:=(result->>'employee_id')::uuid;
  IF employee IS NULL OR (result->>'operation_id')::uuid<>operation THEN RAISE EXCEPTION 'PERSONNEL_RECEIPT_INVALID'; END IF;
  replay:=public.isg_expert_rpc_v1(workspace,'isg_personnel_mutate_v1',args)->'payload';
  IF replay->>'employee_id' IS DISTINCT FROM result->>'employee_id' THEN RAISE EXCEPTION 'REPLAY_CREATED_DUPLICATE'; END IF;
  INSERT INTO expert_acceptance_results VALUES('personnel create and idempotent replay',true,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_CONTEXT;
  INSERT INTO expert_acceptance_results VALUES('personnel create and idempotent replay',false,SQLERRM||E'\n'||detail);
 END;
 IF employee IS NOT NULL THEN
  BEGIN
   result:=public.isg_expert_rpc_v1(workspace,'isg_pilot_training_detail_v3','{}')->'payload';
   SELECT (value->>'id')::uuid INTO workplace FROM jsonb_array_elements(result->'workplaces') WHERE (value->>'company_id')::uuid=company LIMIT 1;
   IF workplace IS NULL THEN RAISE EXCEPTION 'TRAINING_WORKPLACES_MISSING'; END IF;
   mutation:=gen_random_uuid();
   args:=jsonb_build_object('p_mutation',mutation,'p_payload',jsonb_build_object('action','save',
    'title','Shared panel rollback education','provider_name','Synthetic QA','notes','rollback only',
    'trainers',jsonb_build_array(jsonb_build_object('id','fixture-trainer','name','Synthetic trainer','title','Expert')),
    'scopes',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'company_id',company,'workplace_id',workplace,
     'group_name','Fixture','cycle','custom','renewal_months',12,'context_note','Synthetic fixture',
     'employer_name','Synthetic employer','employer_capacity','representative','location','Synthetic location',
     'topics',jsonb_build_array(jsonb_build_object('code','fixture-topic','group','G4','title','Synthetic topic',
      'instruction_minutes',60,'method','face_to_face','trainer_ids',jsonb_build_array('fixture-trainer'))),
     'participants',jsonb_build_array(jsonb_build_object('id',employee,'job_title','Synthetic role')),
     'lessons',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'starts_at',clock_timestamp()-interval '2 days',
      'instruction_minutes',60,'break_minutes',0,'allocations',jsonb_build_array(jsonb_build_object('topic_code','fixture-topic','minutes',60))))))));
   result:=public.isg_expert_rpc_v1(workspace,'isg_pilot_training_record_v3',args)->'payload';
   training:=(result#>>'{row,id}')::uuid;
   IF training IS NULL OR (result->>'mutation_id')::uuid<>mutation THEN RAISE EXCEPTION 'EDUCATION_RECEIPT_INVALID'; END IF;
   replay:=public.isg_expert_rpc_v1(workspace,'isg_pilot_training_record_v3',args)->'payload';
   IF replay#>>'{row,id}' IS DISTINCT FROM result#>>'{row,id}' THEN RAISE EXCEPTION 'EDUCATION_REPLAY_CREATED_DUPLICATE'; END IF;
   result:=public.isg_expert_rpc_v1(workspace,'isg_pilot_training_detail_v3',jsonb_build_object('p_id',training))->'payload';
   IF result#>>'{row,education,scopes,0,topics,0,instruction_minutes}'<>'60'
    OR result#>>'{row,education,scopes,0,renewal_months}'<>'12' THEN RAISE EXCEPTION 'EDUCATION_FIELDS_NOT_PRESERVED'; END IF;
   INSERT INTO expert_acceptance_results VALUES('shared education save, replay, detail, editable duration and validity',true,NULL);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_CONTEXT;
   INSERT INTO expert_acceptance_results VALUES('shared education save, replay, detail, editable duration and validity',false,SQLERRM||E'\n'||detail);
  END;
 END IF;
 BEGIN
  result:=public.isg_expert_rpc_v1(workspace,'isg_nonconformity_read_v1',jsonb_build_object('p_company',company,'p_kind','workplaces','p_query',NULL,'p_state',NULL,'p_after',NULL,'p_id',NULL))->'payload';
  workplace:=(result#>>'{rows,0,id}')::uuid;
  args:=jsonb_build_object('p_company',company,'p_action','open_detailed','p_operation',gen_random_uuid(),'p_mutation',gen_random_uuid(),
    'p_payload',jsonb_build_object('workplace_id',workplace,'title','Shared panel rollback finding','severity','medium',
      'record_kind','nonconformity','opened_on',current_date,'description','Synthetic detail','control_measure','Synthetic measure'));
  result:=public.isg_expert_rpc_v1(workspace,'isg_nonconformity_mutate_v1',args)->'payload';
  IF result#>>'{outcome,nonconformity_id}' IS NULL THEN RAISE EXCEPTION 'FINDING_RECEIPT_MISSING'; END IF;
  replay:=public.isg_expert_rpc_v1(workspace,'isg_nonconformity_mutate_v1',args)->'payload';
  IF replay#>>'{outcome,nonconformity_id}' IS DISTINCT FROM result#>>'{outcome,nonconformity_id}' THEN RAISE EXCEPTION 'FINDING_REPLAY_DUPLICATE'; END IF;
  INSERT INTO expert_acceptance_results VALUES('detailed manual finding and replay',true,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_CONTEXT;
  INSERT INTO expert_acceptance_results VALUES('detailed manual finding and replay',false,SQLERRM||E'\n'||detail);
 END;
 BEGIN
  result:=public.isg_expert_rpc_v1(workspace,'isg_risk_versions_mutate_v1',jsonb_build_object('p_company',company,
   'p_action','open_assessment','p_operation',gen_random_uuid(),'p_mutation',gen_random_uuid(),'p_payload',jsonb_build_object('workplace_id',workplace)))->'payload';
  IF result->>'assessment_id' IS NULL THEN RAISE EXCEPTION 'RISK_RECEIPT_MISSING'; END IF;
  INSERT INTO expert_acceptance_results VALUES('shared risk assessment create',true,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_CONTEXT;
  INSERT INTO expert_acceptance_results VALUES('shared risk assessment create',false,SQLERRM||E'\n'||detail);
 END;
END $test$;
SELECT * FROM expert_acceptance_results;
-- Authorization failures must also restore the transaction context. Otherwise
-- a later personal request in the same connection could inherit tenant scope.
DO $security$
DECLARE workspace uuid:=current_setting('isg.test_workspace')::uuid; detail text;
BEGIN
 BEGIN
  PERFORM public.isg_expert_rpc_v1(gen_random_uuid(),'isg_expert_companies_v1','{}');
  INSERT INTO expert_acceptance_results VALUES('unknown workspace denied',false,'unexpected success');
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  INSERT INTO expert_acceptance_results VALUES('unknown workspace denied',SQLERRM='ACCESS_DENIED',SQLERRM);
 END;
 BEGIN
  PERFORM public.isg_expert_rpc_v1(workspace,'isg_personnel_read_v1',jsonb_build_object('p_company',gen_random_uuid(),'p_kind','list','p_query',NULL,'p_archived',false,'p_after',NULL,'p_id',NULL));
  INSERT INTO expert_acceptance_results VALUES('unassigned company denied',false,'unexpected success');
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  INSERT INTO expert_acceptance_results VALUES('unassigned company denied',SQLERRM='ACCESS_DENIED',SQLERRM);
 END;
 BEGIN
  PERFORM public.isg_expert_rpc_v1(workspace,'pg_sleep','{}');
  INSERT INTO expert_acceptance_results VALUES('arbitrary function rejected',false,'unexpected success');
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  INSERT INTO expert_acceptance_results VALUES('arbitrary function rejected',SQLERRM='EXPERT_OPERATION_NOT_READY',SQLERRM);
 END;
 detail:=nullif(current_setting('private_isg.expert_workspace',true),'');
 INSERT INTO expert_acceptance_results VALUES('tenant context cleared after success and failure',detail IS NULL,detail);
END $security$;
SELECT * FROM expert_acceptance_results;
