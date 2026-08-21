insert into public.app_feature_flags (key, value)
values (
  'ai_expert_depth_v1',
  jsonb_build_object(
    'policy_version', 1,
    'rollout_mode', 'shadow',
    'kill_switch', false,
    'enabled_user_hashes', jsonb_build_array()
  )
)
on conflict (key) do nothing;

create or replace function public.finalize_analysis_result_v2(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid,
  p_findings jsonb,
  p_analysis_result jsonb,
  p_photo_summaries jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_finding jsonb;
  v_summary jsonb;
  v_source_indices integer[];
  v_inserted integer := 0;
  v_refund_fallback_quota boolean := false;
begin
  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;
  if v_analysis.status::text = 'completed' then
    return jsonb_build_object(
      'ok', true,
      'state', 'already_completed',
      'finding_count', v_analysis.finding_count
    );
  end if;

  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id
  for update;

  if not found
    or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token
  then
    return jsonb_build_object('ok', false, 'state', 'lost_claim');
  end if;

  delete from public.findings
  where analysis_id = p_analysis_id
    and user_id = p_user_id
    and origin = 'ai';

  for v_finding in
    select value from jsonb_array_elements(coalesce(p_findings, '[]'::jsonb))
  loop
    select coalesce(array_agg(value::integer), '{}'::integer[])
      into v_source_indices
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(v_finding->'source_photo_indices') = 'array'
          then v_finding->'source_photo_indices'
        else '[]'::jsonb
      end
    );

    insert into public.findings (
      analysis_id,
      user_id,
      ordinal,
      title,
      category,
      description,
      recommended_action,
      recommended_measures,
      references_text,
      root_cause_text,
      confidence,
      needs_field_verification,
      origin,
      ai_original_snapshot,
      source_photo_indices,
      source_photo_observations,
      finding_budget_policy,
      ai_confidence,
      fk_probability,
      fk_frequency,
      fk_severity,
      fk_band,
      m5_probability,
      m5_severity,
      m5_band,
      display_group,
      display_order
    ) values (
      p_analysis_id,
      p_user_id,
      (v_finding->>'ordinal')::integer,
      v_finding->>'title',
      v_finding->>'category',
      v_finding->>'description',
      v_finding->>'recommended_action',
      coalesce(v_finding->'recommended_measures', '[]'::jsonb),
      v_finding->>'references_text',
      v_finding->>'root_cause_text',
      coalesce((v_finding->>'confidence')::numeric, 0),
      coalesce((v_finding->>'needs_field_verification')::boolean, false),
      'ai',
      v_finding->'ai_original_snapshot',
      v_source_indices,
      v_finding->'source_photo_observations',
      v_finding->'finding_budget_policy',
      nullif(v_finding->>'ai_confidence', '')::numeric,
      (v_finding->>'fk_probability')::numeric,
      (v_finding->>'fk_frequency')::numeric,
      (v_finding->>'fk_severity')::numeric,
      (v_finding->>'fk_band')::public.risk_level,
      (v_finding->>'m5_probability')::integer,
      (v_finding->>'m5_severity')::integer,
      (v_finding->>'m5_band')::public.risk_level,
      nullif(v_finding->>'display_group', ''),
      (v_finding->>'display_order')::integer
    );
    v_inserted := v_inserted + 1;
  end loop;

  v_refund_fallback_quota :=
    v_inserted = 0
    and p_analysis_result->>'consume_analysis_quota' = 'false'
    and p_analysis_result->'raw_ai_response'->'_input_audit'
      ->>'deterministic_fallback_used' = 'true'
    and p_analysis_result->'raw_ai_response'->'_input_audit'
      ->>'deterministic_fallback_zero_findings' = 'true';

  update public.analyses
  set status = 'completed',
      status_message = p_analysis_result->>'status_message',
      completed_at = now(),
      ai_summary = p_analysis_result->>'ai_summary',
      total_score_fk = nullif(p_analysis_result->>'total_score_fk', '')::numeric,
      total_score_m5 = nullif(p_analysis_result->>'total_score_m5', '')::integer,
      highest_band_fk = nullif(p_analysis_result->>'highest_band_fk', '')::public.risk_level,
      highest_band_m5 = nullif(p_analysis_result->>'highest_band_m5', '')::public.risk_level,
      finding_count = v_inserted,
      generated_findings_count = v_inserted,
      visible_findings_count = v_inserted,
      hidden_or_rejected_findings_count = coalesce(
        nullif(p_analysis_result->>'hidden_or_rejected_findings_count', '')::integer,
        0
      ),
      max_findings_per_photo = coalesce(
        nullif(p_analysis_result->>'max_findings_per_photo', '')::integer,
        max_findings_per_photo
      ),
      max_findings_total = nullif(p_analysis_result->>'max_findings_total', '')::integer,
      raw_ai_response = p_analysis_result->'raw_ai_response',
      ai_models_used = array(
        select jsonb_array_elements_text(
          coalesce(p_analysis_result->'ai_models_used', '[]'::jsonb)
        )
      ),
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  if v_refund_fallback_quota then
    delete from public.usage_events
    where user_id = p_user_id
      and source_id = p_analysis_id
      and feature in ('analysis_standard', 'analysis_detailed')
      and event_type = 'reserved';
  else
    update public.usage_events
    set event_type = 'completed'
    where user_id = p_user_id
      and source_id = p_analysis_id
      and feature in ('analysis_standard', 'analysis_detailed')
      and event_type = 'reserved';
  end if;

  begin
    for v_summary in
      select value
      from jsonb_array_elements(coalesce(p_photo_summaries, '[]'::jsonb))
    loop
      insert into public.analysis_photo_summaries (
        analysis_id,
        user_id,
        photo_id,
        photo_sequence_index,
        scene_summary,
        candidate_findings_count,
        generated_findings_count,
        highest_risk_level,
        ai_confidence,
        coverage_status,
        coverage_gap_reason,
        target_findings_min,
        target_findings_max,
        raw_summary
      ) values (
        p_analysis_id,
        p_user_id,
        nullif(v_summary->>'photo_id', '')::uuid,
        (v_summary->>'photo_sequence_index')::integer,
        v_summary->>'scene_summary',
        coalesce(nullif(v_summary->>'candidate_findings_count', '')::integer, 0),
        coalesce(nullif(v_summary->>'generated_findings_count', '')::integer, 0),
        v_summary->>'highest_risk_level',
        nullif(v_summary->>'ai_confidence', '')::numeric,
        v_summary->>'coverage_status',
        v_summary->>'coverage_gap_reason',
        nullif(v_summary->>'target_findings_min', '')::integer,
        nullif(v_summary->>'target_findings_max', '')::integer,
        v_summary->'raw_summary'
      )
      on conflict (analysis_id, photo_sequence_index) do update set
        user_id = excluded.user_id,
        photo_id = excluded.photo_id,
        scene_summary = excluded.scene_summary,
        candidate_findings_count = excluded.candidate_findings_count,
        generated_findings_count = excluded.generated_findings_count,
        highest_risk_level = excluded.highest_risk_level,
        ai_confidence = excluded.ai_confidence,
        coverage_status = excluded.coverage_status,
        coverage_gap_reason = excluded.coverage_gap_reason,
        target_findings_min = excluded.target_findings_min,
        target_findings_max = excluded.target_findings_max,
        raw_summary = excluded.raw_summary;
    end loop;
  exception when others then
    raise warning 'analysis_photo_summaries skipped for analysis %: %',
      p_analysis_id, sqlerrm;
  end;

  update private.analysis_job_state
  set claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      updated_at = now()
  where analysis_id = p_analysis_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'completed',
    'finding_count', v_inserted,
    'quota_consumed', not v_refund_fallback_quota
  );
end;
$$;
