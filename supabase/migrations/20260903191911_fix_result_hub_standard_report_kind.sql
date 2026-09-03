-- Result Hub risk findings can be exported either as the free/basic standard PDF or as the
-- one-time/premium risk-assessment table. Preserve that explicit report kind when checking
-- quota; the previous wrapper classified every risk_analysis scope as riskAnalysis.

create or replace function public.check_report_quota_eligibility_v2(
  p_user_id uuid,
  p_kind text,
  p_format text,
  p_content_scope text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tier text;
  v_kind text;
  v_format text;
begin
  if p_content_scope not in (
    'legacy_combined', 'risk_analysis', 'expert_recommendations',
    'approved_notebook'
  ) then
    raise exception 'invalid_report_content_scope' using errcode = '22023';
  end if;

  v_tier := coalesce(private.user_plan_tier(p_user_id), 'free');
  if v_tier = 'free'
    and p_content_scope in ('expert_recommendations', 'approved_notebook') then
    return jsonb_build_object(
      'allowed', false,
      'error_code', 'premium_required',
      'limit', 0,
      'used', 0,
      'period', 'subscription'
    );
  end if;

  v_kind := case
    when p_content_scope = 'risk_analysis'
      and coalesce(p_kind, '') in ('standard', 'standardReport') then 'standard'
    when p_content_scope = 'risk_analysis' then 'riskAnalysis'
    else 'standard'
  end;
  v_format := case
    when v_kind = 'riskAnalysis' then 'pdf'
    else coalesce(nullif(p_format, ''), 'pdf')
  end;

  return public.check_report_quota_eligibility(
    p_user_id,
    v_kind,
    v_format
  );
end;
$$;

revoke all on function public.check_report_quota_eligibility_v2(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.check_report_quota_eligibility_v2(uuid, text, text, text)
  to service_role;
