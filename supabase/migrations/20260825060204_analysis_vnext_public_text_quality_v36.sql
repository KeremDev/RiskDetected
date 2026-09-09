-- Activates prompt bundle v29 and control catalog controls-v19.
--
-- Eight public-text defects observed in the 2026-08-25 construction analysis:
-- English entity names spliced into Turkish sentences, a fatal unprotected
-- slab edge titled as a missing toeboard, two findings published under one
-- identical title, exposed rebar routed to work-at-height controls, an
-- electrical measure asserting an exposed conductor the finding denies,
-- template root causes, a pinch-shear hazard filed under fall and guarding
-- with a tank-agitator control, and a chemical record raised from an unmarked
-- blue barrel.
--
-- The prompt now publishes the output-language contract for entity and control
-- target fields, and the catalog gains protect_sharp_ends.

update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v29',
  policy_version = 'semantic-risk-v29',
  control_catalog_version = 'controls-v19',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'prompt_bundle_policy_version', 'prompt-bundle-sha256-v1',
    'prompt_bundle_sha256',
      '3c6e06ac01f80c4165c8cb420c9d3c78e2cf6a75aa97cee56a520b95d0cb5131',
    'public_output_language_contract_version', 1,
    'sharp_edge_control_routing_version', 1,
    'title_total_absence_policy_version', 1,
    'title_collision_disambiguation_version', 2,
    'electrical_control_evidence_gate_version', 1,
    'asset_assurance_catalog_version', 'asset-assurance-v9',
    'public_copy_renderer_version', 11,
    'mechanism_control_mapping_version', 16,
    'quality_trace_stage_version', 22
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
    or v_config.prompt_version <> 'vnext-photo-expert-v29'
    or v_config.control_catalog_version <> 'controls-v19'
    or v_config.config->>'prompt_bundle_sha256'
      <> '3c6e06ac01f80c4165c8cb420c9d3c78e2cf6a75aa97cee56a520b95d0cb5131'
    or coalesce(
      (v_config.config->>'prompt_bundle_integrity_enabled')::boolean,
      false
    ) is not true
    or coalesce(
      (v_config.config->>'contextual_fall_barrier_alias_enabled')::boolean,
      false
    ) is not true
    or v_config.config #>> '{compute_profiles,premium,max_provider_output_tokens}'
      <> '12288'
  then
    raise exception 'vNext v29 activation verification failed';
  end if;
end;
$$;
