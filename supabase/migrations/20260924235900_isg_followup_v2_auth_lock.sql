-- PostgREST runs STABLE RPCs in read-only transactions. The pilot's active_actor
-- checks the live auth session with FOR SHARE, so this reader must be VOLATILE.
ALTER FUNCTION public.isg_pilot_followup_v2(uuid,text,text,text,integer) VOLATILE;
NOTIFY pgrst, 'reload schema';
