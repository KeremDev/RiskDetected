CREATE TEMP TABLE expert_module_results(test text,passed boolean,detail text);
CREATE FUNCTION pg_temp.expert_mutation(fn text,c uuid,action text,payload jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.isg_expert_rpc_v1(current_setting('isg.test_workspace')::uuid,fn,jsonb_build_object(
  'p_company',c,'p_action',action,'p_operation',gen_random_uuid(),'p_mutation',gen_random_uuid(),'p_payload',payload))->'payload'
$$;
CREATE FUNCTION pg_temp.module_probe(label text,fn text,c uuid,action text,payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; detail text;
BEGIN
 r:=pg_temp.expert_mutation(fn,c,action,payload);
 INSERT INTO expert_module_results VALUES(label,true,NULL); RETURN r;
EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_CONTEXT;
 INSERT INTO expert_module_results VALUES(label,false,SQLERRM||E'\n'||detail); RETURN NULL;
END $$;
DO $test$
DECLARE w uuid:=current_setting('isg.test_workspace')::uuid; c uuid; workplace uuid; employee uuid; plan uuid; result jsonb;
BEGIN
 result:=public.isg_expert_rpc_v1(w,'isg_expert_companies_v1','{}')->'payload'; c:=(result#>>'{rows,0,id}')::uuid;
 result:=public.isg_expert_rpc_v1(w,'isg_nonconformity_read_v1',jsonb_build_object('p_company',c,'p_kind','workplaces','p_query',NULL,'p_state',NULL,'p_after',NULL,'p_id',NULL))->'payload'; workplace:=(result#>>'{rows,0,id}')::uuid;
 result:=public.isg_expert_rpc_v1(w,'isg_personnel_read_v1',jsonb_build_object('p_company',c,'p_kind','employees','p_query','','p_archived',false,'p_after',NULL,'p_id',NULL))->'payload';
 employee:=(result#>>'{rows,0,id}')::uuid;
 result:=pg_temp.module_probe('emergency plan with editable validity','isg_emergency_plans_mutate_v1',c,'publish_plan',jsonb_build_object(
 'workplace_id',workplace,'scope','Rollback emergency plan','prepared_on',current_date,'valid_until',current_date+500,
 'team',jsonb_build_array(jsonb_build_object('full_name','Fixture person','role','coordinator')),'review_note','Synthetic QA'));
 plan:=(result->>'plan_id')::uuid;
 IF plan IS NOT NULL THEN PERFORM pg_temp.module_probe('drill planning','isg_drills_mutate_v1',c,'plan_drill',jsonb_build_object('plan_id',plan,'planned_on',current_date+10)); END IF;
 PERFORM pg_temp.module_probe('representative appointment','isg_appointments_mutate_v1',c,'record_appointment',jsonb_build_object(
 'employee_id',employee,'workplace_id',workplace,'kind','representative','starts_on',current_date,'basis','appointed'));
 PERFORM pg_temp.module_probe('equipment registration','isg_equipment_checks_mutate_v1',c,'register_equipment',jsonb_build_object(
 'workplace_id',workplace,'equipment_type','forklift','serial_tag','rollback-'||gen_random_uuid()::text));
 PERFORM pg_temp.module_probe('PPE handover','isg_ppe_mutate_v1',c,'create_form',jsonb_build_object(
 'employee_id',employee,'item','Fixture gloves','handed_on',current_date));
 PERFORM pg_temp.module_probe('checklist template','isg_checklists_mutate_v1',c,'draft_template',jsonb_build_object('title','Rollback checklist'));
END $test$;
SELECT * FROM expert_module_results;
