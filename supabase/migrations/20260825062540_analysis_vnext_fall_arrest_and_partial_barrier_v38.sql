-- Activates prompt bundle v31.
--
-- Two hazards the photograph shows and the report could not carry:
--
--   * The scaffold. The model reported missing_mid_rail with barrier_state
--     partial_event_direct_or_conditional - the top rail is up, the mid-rail is
--     gone - and the gate dropped it for not claiming total absence, even
--     though missing_mid_rail is on its own whitelist. The two conditions
--     contradicted each other, so those codes were unreachable.
--
--   * The harness. Fall arrest was judged as ordinary person-worn PPE and
--     rejected as a visibility claim, which removed the last barrier left when
--     collective protection is absent from every report.

update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v31',
  policy_version = 'semantic-risk-v29',
  control_catalog_version = 'controls-v19',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'prompt_bundle_policy_version', 'prompt-bundle-sha256-v1',
    'prompt_bundle_sha256',
      '508f42409ea2929e0c43fce6d6b4ea8bfcad7c321a05f2d0f15b8939bc9cf144',
    'partial_barrier_sub_component_version', 1,
    'fall_arrest_absence_policy_version', 1,
    'structured_visible_barrier_evidence_version', 3,
    'contextual_ppe_guard_version', 2,
    'quality_trace_stage_version', 24
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
    or v_config.prompt_version <> 'vnext-photo-expert-v31'
    or v_config.config->>'prompt_bundle_sha256'
      <> '508f42409ea2929e0c43fce6d6b4ea8bfcad7c321a05f2d0f15b8939bc9cf144'
    or coalesce(
      (v_config.config->>'prompt_bundle_integrity_enabled')::boolean,
      false
    ) is not true
    or v_config.config #>> '{compute_profiles,premium,max_provider_output_tokens}'
      <> '12288'
  then
    raise exception 'vNext v31 activation verification failed';
  end if;
end;
$$;
