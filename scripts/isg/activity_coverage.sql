-- Run against the deployed staging schema (read-only assertions).
DO $$
DECLARE missing text;
BEGIN
 SELECT string_agg(p.proname,', ' ORDER BY p.proname) INTO missing
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname LIKE 'isg_%'
 AND (p.proname ~ '(mutate|create|submit|record|certificate|organize|commit|export|finalize|cancel|delete|archive)'
      OR 'p_mutation'=ANY(p.proargnames))
 AND NOT EXISTS(SELECT 1 FROM private_isg.business_activity_rpc_contracts c WHERE c.rpc_name=p.proname);
 ASSERT missing IS NULL,'Unmapped mutation RPC: '||coalesce(missing,'');
 SELECT string_agg(s.table_schema||'.'||s.table_name,', ') INTO missing
 FROM private_isg.business_activity_sources s
 WHERE NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass(format('%I.%I',s.table_schema,s.table_name))
                  AND t.tgname='business_activity_row' AND t.tgenabled='O');
 ASSERT missing IS NULL,'Missing transactional journal trigger: '||coalesce(missing,'');
 ASSERT NOT has_table_privilege('authenticated','private_isg.business_activity_events','SELECT');
 ASSERT NOT has_function_privilege('authenticated','public.isg_notebook_delivery_claim_v1(integer)','EXECUTE');
 ASSERT EXISTS(SELECT 1 FROM cron.job WHERE jobname='isg-notebook-reminders-staging' AND active);
 ASSERT EXISTS(SELECT 1 FROM cron.job WHERE jobname='isg-expert-activity-retention' AND active);
END $$;
