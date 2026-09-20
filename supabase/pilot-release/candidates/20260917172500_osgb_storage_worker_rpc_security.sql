-- Storage workers also enter private schemas through PostgREST. Their public
-- facades are executable only by service_role and therefore run as owner.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';

ALTER FUNCTION public.isg_workspace_upload_claim_worker_v1(text,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_upload_finalize_worker_v1(text,text,bigint,bytea,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_download_claim_worker_v1(text,timestamptz) SECURITY DEFINER;
ALTER FUNCTION public.isg_workspace_download_delivered_worker_v1(uuid,text,bigint,timestamptz) SECURITY DEFINER;
DO $$ BEGIN
  IF to_regprocedure('public.isg_file_inspection_v1(uuid,text,jsonb)') IS NOT NULL THEN
    ALTER FUNCTION public.isg_file_inspection_v1(uuid,text,jsonb) SECURITY DEFINER;
  END IF;
END $$;

NOTIFY pgrst,'reload schema';
