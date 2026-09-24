-- isg_pilot_followup_v1 and isg_pilot_file_sources_v1 were declared STABLE.
-- PostgREST runs STABLE functions in a read-only transaction, but both call
-- private_isg.p05_pilot_account_enabled, which takes a FOR SHARE lock on the
-- pilot account and rollout rows. Every call therefore failed with "cannot
-- execute SELECT FOR SHARE in a read-only transaction": Evrak Takibi, the home
-- deadline board and a file's linked records never loaded. Marking them
-- VOLATILE lets PostgREST use a normal transaction; the bodies, settings and
-- grants are unchanged. Each is altered only where it exists.
DO $migration$
BEGIN
  IF to_regprocedure('public.isg_pilot_followup_v1(uuid,text,text,integer)') IS NOT NULL THEN
    ALTER FUNCTION public.isg_pilot_followup_v1(uuid,text,text,integer) VOLATILE;
  END IF;
  IF to_regprocedure('public.isg_pilot_file_sources_v1(uuid)') IS NOT NULL THEN
    ALTER FUNCTION public.isg_pilot_file_sources_v1(uuid) VOLATILE;
  END IF;
END
$migration$;
