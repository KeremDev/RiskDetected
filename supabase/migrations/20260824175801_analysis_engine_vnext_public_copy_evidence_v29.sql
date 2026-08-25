-- vNext public-copy and evidence hardening for the latest manufacturing
-- regression. This is a config-only activation: the provider schema,
-- compute profiles, quotas, UI contract and scoring tables stay unchanged.

update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v24',
  policy_version = 'semantic-risk-v25',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'public_copy_renderer_version', 7,
    'public_spatial_address_policy_version', 4,
    'public_narrative_address_policy_version', 2,
    'root_cause_claim_policy_version', 5,
    'root_cause_qualification_version', 3,
    'same_photo_equivalent_condition_merge_version', 2,
    'generic_visual_hazard_gate_version', 3,
    'excavation_slope_evidence_policy_version', 4,
    'ordinary_excavation_material_guard_version', 1,
    'asset_assurance_catalog_version', 'asset-assurance-v7',
    'assurance_public_copy_version', 3,
    'secondary_containment_visibility_gate_version', 1,
    'quality_trace_stage_version', 17
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

do $verify_vnext_public_copy_evidence_v29$
declare
  v_matching integer;
begin
  select count(*) into v_matching
  from private.analysis_engine_configs
  where engine_version = 'vnext-v3'
    and is_active = true
    and schema_version = 'hazard-fact-v3.5'
    and prompt_version = 'vnext-photo-expert-v24'
    and policy_version = 'semantic-risk-v25'
    and config->>'public_copy_renderer_version' = '7'
    and config->>'public_spatial_address_policy_version' = '4'
    and config->>'public_narrative_address_policy_version' = '2'
    and config->>'root_cause_claim_policy_version' = '5'
    and config->>'root_cause_qualification_version' = '3'
    and config->>'same_photo_equivalent_condition_merge_version' = '2'
    and config->>'generic_visual_hazard_gate_version' = '3'
    and config->>'excavation_slope_evidence_policy_version' = '4'
    and config->>'ordinary_excavation_material_guard_version' = '1'
    and config->>'asset_assurance_catalog_version' = 'asset-assurance-v7'
    and config->>'assurance_public_copy_version' = '3'
    and config->>'secondary_containment_visibility_gate_version' = '1'
    and config->>'quality_trace_stage_version' = '17';

  if v_matching < 1 then
    raise exception 'vNext public-copy and evidence policy v29 did not apply';
  end if;
end;
$verify_vnext_public_copy_evidence_v29$;
