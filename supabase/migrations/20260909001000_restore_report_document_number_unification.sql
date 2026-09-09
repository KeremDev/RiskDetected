-- Preserve the shared RD-RA sequence after training reports added the EO scope.
-- The training migration expanded the function but inadvertently restored a separate
-- report_scope_year_counters row for risk-analysis exports.
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
    when 'training_recommendations' then 'EO'
    else null
  end;
  if v_prefix is null then
    raise exception 'invalid_report_content_scope' using errcode = '22023';
  end if;

  -- Standard/legacy and section-scoped risk reports use one globally locked RD-RA counter.
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
