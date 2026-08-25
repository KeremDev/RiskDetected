-- Close the live manufacturing guardrail regression without using sector
-- hazard class as evidence or changing the accepted P/S semantics. The
-- manufacturing F=6 prior remains unchanged. Three-photo high-hazard scenes
-- receive at most one bounded guardrail-family reinspection when a guardrail
-- is actually present in scene inventory.

update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v25',
  policy_version = 'semantic-risk-v27',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'multi_photo_high_hazard_critical_coverage_enabled', true,
    'multi_photo_high_hazard_critical_coverage_version', 1,
    'sector_profile_critical_height_version', 1,
    'guardrail_geometry_synonym_version', 2,
    'public_copy_renderer_version', 9,
    'public_spatial_address_policy_version', 6,
    'public_narrative_address_policy_version', 4,
    'unsupported_compliance_copy_policy_version', 1,
    'quality_trace_stage_version', 18
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

do $verify_vnext_high_hazard_guardrail_coverage_v31$
declare
  v_matching integer;
begin
  select count(*) into v_matching
  from private.analysis_engine_configs
  where engine_version = 'vnext-v3'
    and is_active = true
    and schema_version = 'hazard-fact-v3.5'
    and prompt_version = 'vnext-photo-expert-v25'
    and policy_version = 'semantic-risk-v27'
    and control_catalog_version = 'controls-v18'
    and config->>'sector_profile_version' = 'sector-profile-v2'
    and config->>'multi_photo_high_hazard_critical_coverage_enabled' = 'true'
    and config->>'multi_photo_high_hazard_critical_coverage_version' = '1'
    and config->>'sector_profile_critical_height_version' = '1'
    and config->>'guardrail_geometry_synonym_version' = '2'
    and config->>'public_copy_renderer_version' = '9'
    and config->>'public_spatial_address_policy_version' = '6'
    and config->>'public_narrative_address_policy_version' = '4'
    and config->>'unsupported_compliance_copy_policy_version' = '1'
    and config->>'quality_trace_stage_version' = '18';

  if v_matching < 1 then
    raise exception 'vNext high-hazard guardrail coverage policy v31 did not apply';
  end if;
end;
$verify_vnext_high_hazard_guardrail_coverage_v31$;
