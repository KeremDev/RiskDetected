-- Ensure RD-RA document numbers are globally unique across users.
-- The previous counter was scoped by user, but reports.document_no is globally unique.

create table if not exists public.report_year_counters (
  year integer primary key,
  last_no integer not null default 0
);

alter table public.report_year_counters enable row level security;

revoke all on table public.report_year_counters from public, anon, authenticated;

insert into public.report_year_counters(year, last_no)
select parsed.year, max(parsed.no)::integer as last_no
from (
  select
    substring(document_no from '^RD-RA-([0-9]{4})-[0-9]+$')::integer as year,
    substring(document_no from '^RD-RA-[0-9]{4}-([0-9]+)$')::integer as no
  from public.reports
  where document_no ~ '^RD-RA-[0-9]{4}-[0-9]+$'
) as parsed
where parsed.year is not null
group by parsed.year
on conflict (year) do update
  set last_no = greatest(public.report_year_counters.last_no, excluded.last_no);

create or replace function public.next_document_no(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  y int := extract(year from now())::int;
  n int;
begin
  if p_user_id is null then
    raise exception 'missing_user_id';
  end if;

  perform 1
  from public.profiles
  where id = p_user_id;

  if not found then
    raise exception 'user_not_found';
  end if;

  insert into public.report_year_counters(year, last_no)
  values (y, 1)
  on conflict (year) do update
    set last_no = public.report_year_counters.last_no + 1
  returning last_no into n;

  return 'RD-RA-' || y::text || '-' || lpad(n::text, 4, '0');
end
$function$;

revoke all on function public.next_document_no(uuid) from public, anon, authenticated;
grant execute on function public.next_document_no(uuid) to service_role;
