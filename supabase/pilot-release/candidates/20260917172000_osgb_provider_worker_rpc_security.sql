-- PostgREST exposes only public wrappers. These worker-only wrappers must cross
-- into private_isg as their owner; EXECUTE remains granted solely to service_role.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';

ALTER FUNCTION public.isg_workspace_worker_ai_claim_v1(integer,timestamptz,integer) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_worker_ai_complete_v1(uuid,uuid,bigint,bigint,bigint,uuid,text,text,text,bigint,bytea,jsonb,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_worker_ai_fail_v1(uuid,uuid,text,boolean,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_worker_export_claim_v1(integer,timestamptz,integer) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_worker_export_complete_v1(uuid,uuid,uuid,text,text,text,bigint,bytea,text,text,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_worker_export_fail_v1(uuid,uuid,text,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_worker_notification_claim_v1(integer,timestamptz,integer) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_worker_notification_complete_v1(uuid,uuid,boolean,text,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_purchase_record_revenuecat_v1(text,text,text,uuid,text,text,text,timestamptz,timestamptz,bigint,bytea,timestamptz) SECURITY DEFINER;

NOTIFY pgrst,'reload schema';
