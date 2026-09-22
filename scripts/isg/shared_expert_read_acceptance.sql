-- Staging test-account reads. Run only inside BEGIN / ROLLBACK.
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','0eda5735-1e03-4d2f-9441-051ebc16c75f','session_id','32f65114-c8bf-41f8-acb9-6675f1fdee3e','role','authenticated','exp',floor(extract(epoch from clock_timestamp())+3600))::text,true);
CREATE FUNCTION pg_temp.expert_probe(fn text,args jsonb) RETURNS jsonb LANGUAGE plpgsql AS $p$
DECLARE result jsonb; required text[]; k text;
BEGIN
 SELECT ARRAY(SELECT unnest(proargnames[1:pronargs-pronargdefaults])) INTO required FROM pg_proc WHERE oid=(SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=fn);
 FOREACH k IN ARRAY coalesce(required,'{}') LOOP IF NOT args ? k THEN args:=args||jsonb_build_object(k,NULL); END IF; END LOOP;
 result:=public.isg_expert_rpc_v1('fab8ccc8-5893-498e-b330-c746bcbd4879',fn,args);
 result:=result->'payload';
 RETURN jsonb_build_object('function',fn,'ok',true,'rows',jsonb_array_length(coalesce(result->'rows',result->'companies','[]'::jsonb)));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('function',fn,'ok',false,'error',SQLERRM);
END $p$;
SET LOCAL ROLE authenticated;
SELECT jsonb_agg(pg_temp.expert_probe(value->>0,value->1)) AS results FROM jsonb_array_elements('[["isg_workspace_availability_v1",{}],["isg_expert_companies_v1",{"p_archived":true}],["isg_pilot_overview_v2",{}],["isg_pilot_training_sessions_v2",{}],["isg_pilot_training_detail_v3",{}],["isg_risk_versions_read_v1",{"p_kind":"list","p_query":"","p_offset":0,"p_limit":10}],["isg_appointments_read_v1",{"p_kind":"list","p_query":"","p_offset":0,"p_limit":10}],["isg_checklists_read_v1",{"p_kind":"list","p_query":"","p_offset":0,"p_limit":10}],["isg_drills_read_v1",{"p_kind":"list","p_query":"","p_offset":0,"p_limit":10}],["isg_emergency_plans_read_v1",{"p_kind":"list","p_query":"","p_offset":0,"p_limit":10}],["isg_equipment_checks_read_v1",{"p_kind":"list","p_query":"","p_offset":0,"p_limit":10}],["isg_ppe_read_v1",{"p_kind":"list","p_query":"","p_offset":0,"p_limit":10}],["isg_pilot_file_library_read_v2",{"p_kind":"list","p_query":"","p_offset":0,"p_limit":10}],["isg_document_portfolio_v1",{"p_limit":10,"p_offset":0}],["isg_pilot_module_tracking_v2",{}],["isg_pilot_followup_v1",{"p_offset":0,"p_query":""}],["isg_statistics_v1",{"p_months":3}],["isg_pilot_notice_feed_v1",{"p_scope":"active","p_limit":50}],["isg_pilot_process_read_v1",{"p_kind":"site_visit","p_query":"","p_offset":0}]]'::jsonb);
