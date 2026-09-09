-- Keep legacy/standard reports and section-scoped risk-analysis reports on the
-- same global RD-RA sequence. They previously used separate counters while
-- reports.document_no is globally unique, which could make the next report
-- collide with a number already issued by the other path.

insert into public.report_year_counters(year, last_no)
select parsed.year, max(parsed.no)::integer
from (
  select
    substring(document_no from '^RD-RA-([0-9]{4})-[0-9]+$')::integer as year,
    substring(document_no from '^RD-RA-[0-9]{4}-([0-9]+)$')::integer as no
  from public.reports
  where document_no ~ '^RD-RA-[0-9]{4}-[0-9]+$'
) parsed
where parsed.year is not null
group by parsed.year
on conflict (year) do update
set last_no = greatest(public.report_year_counters.last_no, excluded.last_no);

create or replace function public.next_document_no(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_year integer := extract(year from now())::integer;
  v_no integer;
begin
  if p_user_id is null then
    raise exception 'missing_user_id';
  end if;

  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;

  insert into public.report_year_counters as counters(year, last_no)
  values (
    v_year,
    coalesce((
      select max(substring(r.document_no from '^RD-RA-[0-9]{4}-([0-9]+)$')::integer)
      from public.reports r
      where r.document_no ~ ('^RD-RA-' || v_year::text || '-[0-9]+$')
    ), 0) + 1
  )
  on conflict (year) do update
  set last_no = greatest(
    counters.last_no + 1,
    coalesce((
      select max(substring(r.document_no from '^RD-RA-[0-9]{4}-([0-9]+)$')::integer)
      from public.reports r
      where r.document_no ~ ('^RD-RA-' || v_year::text || '-[0-9]+$')
    ), 0) + 1
  )
  returning last_no into v_no;

  return 'RD-RA-' || v_year::text || '-' || lpad(v_no::text, 4, '0');
end
$function$;

revoke all on function public.next_document_no(uuid)
  from public, anon, authenticated;
grant execute on function public.next_document_no(uuid)
  to service_role;

create or replace function public.next_report_document_no_v2(
  p_user_id uuid,
  p_content_scope text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_year integer := extract(year from now())::integer;
  v_no integer;
  v_prefix text;
begin
  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;

  v_prefix := case p_content_scope
    when 'risk_analysis' then 'RA'
    when 'expert_recommendations' then 'UG'
    when 'approved_notebook' then 'OD'
    else null
  end;
  if v_prefix is null then
    raise exception 'invalid_report_content_scope' using errcode = '22023';
  end if;

  -- Standard/legacy and section-scoped risk reports both use RD-RA numbers.
  -- Route both paths through the same locked counter row.
  if v_prefix = 'RA' then
    return public.next_document_no(p_user_id);
  end if;

  insert into public.report_scope_year_counters as counters(
    scope_prefix,
    year,
    last_no
  )
  values (
    v_prefix,
    v_year,
    coalesce((
      select max(split_part(r.document_no, '-', 4)::integer)
      from public.reports r
      where r.document_no ~ (
        '^RD-' || v_prefix || '-' || v_year::text || '-[0-9]+$'
      )
    ), 0) + 1
  )
  on conflict (scope_prefix, year) do update
  set last_no = greatest(
    counters.last_no + 1,
    coalesce((
      select max(split_part(r.document_no, '-', 4)::integer)
      from public.reports r
      where r.document_no ~ (
        '^RD-' || v_prefix || '-' || v_year::text || '-[0-9]+$'
      )
    ), 0) + 1
  )
  returning last_no into v_no;

  return 'RD-' || v_prefix || '-' || v_year::text || '-' ||
    lpad(v_no::text, 4, '0');
end
$function$;

revoke all on function public.next_report_document_no_v2(uuid, text)
  from public, anon, authenticated;
grant execute on function public.next_report_document_no_v2(uuid, text)
  to service_role;
