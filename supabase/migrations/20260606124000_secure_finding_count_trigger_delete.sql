-- Allow analysis deletion to cascade through findings without granting users
-- direct write access to analyses.finding_count.

create or replace function public.tg_recalc_finding_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  update public.analyses
  set finding_count = (
    select count(*)
    from public.findings
    where analysis_id = coalesce(new.analysis_id, old.analysis_id)
  )
  where id = coalesce(new.analysis_id, old.analysis_id);

  return null;
end
$function$;
