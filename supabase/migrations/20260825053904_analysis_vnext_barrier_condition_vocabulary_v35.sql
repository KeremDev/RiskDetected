-- Activates prompt bundle v28.
--
-- The structured barrier gate matches observed_condition.condition_code
-- against a closed map, but the field is free text in the schema and the
-- prompt never published the list. Three consecutive live construction
-- analyses lost every single_fatality fall fact to
-- `condition_code_not_whitelisted`, on `fall_protection_absent`, then
-- `unguarded_edge_work` and `unguarded_edge_work_distant`.
--
-- v28 publishes the canonical codes in the prompt and reads unseen spellings
-- semantically on the server. The prompt text changed, so the pinned bundle
-- hash has to move with it or every run fails the integrity contract.

update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v28',
  policy_version = 'semantic-risk-v29',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'prompt_bundle_policy_version', 'prompt-bundle-sha256-v1',
    'prompt_bundle_sha256',
      '6a4a29d11f2c29989705cc4a1e38aed158b03b3871279e4261baacd0b6a1cf52',
    'barrier_condition_vocabulary_version', 1,
    'evidence_rejection_ratio_alert_inclusive', true,
    'structured_visible_barrier_evidence_version', 2,
    'quality_trace_stage_version', 21
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

do $$
declare
  v_config private.analysis_engine_configs%rowtype;
begin
  select * into v_config
  from private.analysis_engine_configs
  where engine_version = 'vnext-v3' and is_active = true;

  if not found
    or v_config.prompt_version <> 'vnext-photo-expert-v28'
    or v_config.policy_version <> 'semantic-risk-v29'
    or v_config.config->>'prompt_bundle_sha256'
      <> '6a4a29d11f2c29989705cc4a1e38aed158b03b3871279e4261baacd0b6a1cf52'
    or coalesce(
      (v_config.config->>'prompt_bundle_integrity_enabled')::boolean,
      false
    ) is not true
    or coalesce(
      (v_config.config->>'contextual_fall_barrier_alias_enabled')::boolean,
      false
    ) is not true
    -- v34 raised this ceiling so the primary call stops being discarded.
    -- The vocabulary fix only pays off on a primary call that survives.
    or v_config.config #>> '{compute_profiles,premium,max_provider_output_tokens}'
      <> '12288'
  then
    raise exception 'vNext v28 activation verification failed';
  end if;
end;
$$;
