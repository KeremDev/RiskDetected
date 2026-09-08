-- Training recommendations are exportable by Plus/Pro, with existing quotas.
alter table public.reports drop constraint reports_content_scope_check;
alter table public.reports add constraint reports_content_scope_check check (
  content_scope in ('legacy_combined', 'risk_analysis', 'expert_recommendations', 'approved_notebook', 'training_recommendations')
);
alter table private.report_export_intents drop constraint report_export_intents_content_scope_check;
alter table private.report_export_intents add constraint report_export_intents_content_scope_check check (
  content_scope in ('risk_analysis', 'expert_recommendations', 'approved_notebook', 'training_recommendations')
);
alter table public.report_scope_year_counters drop constraint report_scope_year_counters_scope_prefix_check;
alter table public.report_scope_year_counters add constraint report_scope_year_counters_scope_prefix_check check (
  scope_prefix in ('RA', 'UG', 'OD', 'EO')
);

create or replace function public.check_report_quota_eligibility_v2(
  p_user_id uuid, p_kind text, p_format text, p_content_scope text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tier text;
  v_kind text;
  v_format text;
begin
  if p_content_scope not in ('legacy_combined', 'risk_analysis', 'expert_recommendations', 'approved_notebook', 'training_recommendations') then
    raise exception 'invalid_report_content_scope' using errcode = '22023';
  end if;
  v_tier := coalesce(private.user_plan_tier(p_user_id), 'free');
  if v_tier = 'free' and p_content_scope in ('expert_recommendations', 'approved_notebook', 'training_recommendations') then
    return jsonb_build_object('allowed', false, 'error_code', 'premium_required', 'limit', 0, 'used', 0, 'period', 'subscription');
  end if;
  v_kind := case
    when p_content_scope = 'risk_analysis' and coalesce(p_kind, '') in ('standard', 'standardReport') then 'standard'
    when p_content_scope = 'risk_analysis' then 'riskAnalysis'
    else 'standard'
  end;
  v_format := case when v_kind = 'riskAnalysis' then 'pdf' else coalesce(nullif(p_format, ''), 'pdf') end;
  return public.check_report_quota_eligibility(p_user_id, v_kind, v_format);
end;
$$;
revoke all on function public.check_report_quota_eligibility_v2(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.check_report_quota_eligibility_v2(uuid, text, text, text) to service_role;

create or replace function public.next_report_document_no_v2(p_user_id uuid, p_content_scope text)
returns text language plpgsql security definer set search_path = '' as $$
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
    else null end;
  if v_prefix is null then
    raise exception 'invalid_report_content_scope' using errcode = '22023';
  end if;
  insert into public.report_scope_year_counters(scope_prefix, year, last_no)
  values (v_prefix, v_year, 1)
  on conflict (scope_prefix, year) do update
    set last_no = public.report_scope_year_counters.last_no + 1
  returning last_no into v_no;
  return 'RD-' || v_prefix || '-' || v_year::text || '-' || lpad(v_no::text, 4, '0');
end;
$$;
revoke all on function public.next_report_document_no_v2(uuid, text) from public, anon, authenticated;
grant execute on function public.next_report_document_no_v2(uuid, text) to service_role;
