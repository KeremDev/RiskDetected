-- Activate the measured v27 recovery package only after the v33-compatible
-- worker is deployed. Raising a generation ceiling is not pre-billed; it
-- prevents paid primary calls from being discarded at 8192 tokens.

update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v27',
  policy_version = 'semantic-risk-v29',
  config = jsonb_set(
    coalesce(config, '{}'::jsonb),
    '{compute_profiles,premium,max_provider_output_tokens}',
    '12288'::jsonb,
    true
  ) || jsonb_build_object(
    'contextual_fall_barrier_alias_enabled', true,
    'contextual_fall_barrier_alias_version', 1,
    'person_barrier_equivalent_merge_enabled', true,
    'person_barrier_equivalent_merge_version', 1,
    'provider_attempt_budget_trace_enabled', true,
    'provider_attempt_budget_trace_version', 1,
    'prompt_bundle_integrity_enabled', true,
    'prompt_bundle_policy_version', 'prompt-bundle-sha256-v1',
    'prompt_bundle_sha256',
      'b17620edb75c638bfdba3227a82d791cfa07ddfe34d4f03e89537725a49db063',
    'premium_output_cap_recovery_version', 1,
    'quality_trace_stage_version', 20
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
    or v_config.prompt_version <> 'vnext-photo-expert-v27'
    or v_config.policy_version <> 'semantic-risk-v29'
    or v_config.config #>> '{compute_profiles,premium,max_provider_output_tokens}'
      <> '12288'
    or coalesce(
      (v_config.config->>'contextual_fall_barrier_alias_enabled')::boolean,
      false
    ) is not true
    or coalesce(
      (v_config.config->>'prompt_bundle_integrity_enabled')::boolean,
      false
    ) is not true
    or v_config.config->>'prompt_bundle_sha256'
      <> 'b17620edb75c638bfdba3227a82d791cfa07ddfe34d4f03e89537725a49db063'
  then
    raise exception 'vNext v27 activation verification failed';
  end if;
end;
$$;
