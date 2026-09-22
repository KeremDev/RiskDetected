-- Run after shared_expert_modules_acceptance.sql inside BEGIN/ROLLBACK.
DO $$
DECLARE c uuid; wp uuid; employee uuid; a uuid; b uuid; v uuid; org uuid; r jsonb;
BEGIN
 r:=public.isg_expert_rpc_v1(current_setting('isg.test_workspace')::uuid,'isg_expert_companies_v1','{}')->'payload';
 c:=(r#>>'{rows,0,id}')::uuid;
 r:=public.isg_expert_rpc_v1(current_setting('isg.test_workspace')::uuid,'isg_personnel_read_v1',jsonb_build_object('p_company',c,'p_kind','employees','p_query','','p_archived',false,'p_after',NULL,'p_id',NULL))->'payload';
 employee:=(r#>>'{rows,0,id}')::uuid;
 r:=public.isg_expert_rpc_v1(current_setting('isg.test_workspace')::uuid,'isg_nonconformity_read_v1',jsonb_build_object('p_company',c,'p_kind','workplaces','p_query',NULL,'p_state',NULL,'p_after',NULL,'p_id',NULL))->'payload';
 wp:=(r#>>'{rows,0,id}')::uuid;
 PERFORM pg_temp.module_probe('contract save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','katip_contract','values',jsonb_build_object('workplace_id',wp,'counterparty','QA','expert_contact','QA Expert','scope','QA scope','starts_on',current_date,'declared_monthly_minutes',120)));
 r:=pg_temp.module_probe('annual plan save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','annual_work_plan','values',jsonb_build_object('workplace_id',wp,'plan_year',extract(year from current_date)::int)));
 a:=(r->>'id')::uuid;
 PERFORM pg_temp.module_probe('annual plan child save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','annual_work_item','values',jsonb_build_object('plan_id',a,'activity','QA activity','planned_on',current_date,'state','planned')));
 r:=pg_temp.module_probe('board save with decision','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','board','values',jsonb_build_object('workplace_id',wp,'applicability','voluntary','planned_on',current_date,'agenda',jsonb_build_array('QA agenda'),'state','planned','initial_decisions',jsonb_build_array('QA decision'))));
 b:=(r->>'id')::uuid;
 PERFORM pg_temp.module_probe('board child save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','board_decision','values',jsonb_build_object('meeting_id',b,'decision_no',2,'decision_text','QA followup','state','open')));
 r:=pg_temp.module_probe('site visit save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','site_visit','values',jsonb_build_object('workplace_id',wp,'visited_on',current_date,'expert_note','QA visit','duration_minutes',30)));
 v:=(r->>'id')::uuid;
 PERFORM pg_temp.module_probe('site observation save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','site_observation','values',jsonb_build_object('visit_id',v,'note','QA observation')));
 PERFORM pg_temp.module_probe('work permit save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','work_permit','values',jsonb_build_object('workplace_id',wp,'template_code','general','job_description','QA job','planned_on',current_date,'starts_at',now(),'ends_at',now()+interval '1 hour','parties',jsonb_build_array(jsonb_build_object('id',employee)))));
 r:=pg_temp.module_probe('contractor save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','contractor','values',jsonb_build_object('code','qa-'||gen_random_uuid(),'name','QA Contractor','relationship','contractor')));
 org:=(r->>'id')::uuid;
 PERFORM pg_temp.module_probe('contractor engagement save','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','contractor_engagement','values',jsonb_build_object('organization_id',org,'workplace_id',wp,'starts_on',current_date,'ends_before',current_date+30,'description','QA engagement')));
 PERFORM pg_temp.module_probe('completed drill editable validity','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','completed_drill','values',jsonb_build_object('workplace_id',wp,'held_on',current_date,'drill_type','fire','announcement','announced','bekra',false,'duration_minutes',30,'scenario','QA drill','valid_until',current_date+400,'due_override',true)));
 PERFORM pg_temp.module_probe('personnel certificate editable validity','isg_pilot_process_mutate_v1',c,'save',jsonb_build_object('kind','personnel_certificate','values',jsonb_build_object('employee_id',employee,'certificate_kind','custom','title','QA Certificate','issued_on',current_date,'valid_until',current_date+500,'due_override',true)));
END $$;
SELECT * FROM expert_module_results;
