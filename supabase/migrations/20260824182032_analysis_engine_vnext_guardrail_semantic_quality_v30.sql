-- vNext deterministic quality hardening for the latest three-photo
-- manufacturing regression. The provider prompt/schema, scoring policy,
-- compute profiles, quotas, assurance catalogue and UI contract stay intact.

update private.analysis_engine_configs
set
  policy_version = 'semantic-risk-v26',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'public_copy_renderer_version', 8,
    'public_spatial_address_policy_version', 5,
    'public_narrative_address_policy_version', 3,
    'root_cause_claim_policy_version', 6,
    'root_cause_qualification_version', 4,
    'same_photo_equivalent_condition_merge_version', 3,
    'generic_visual_hazard_gate_version', 4,
    'excavation_slope_evidence_policy_version', 5,
    'guardrail_geometry_synonym_version', 1,
    'housekeeping_semantic_merge_version', 1,
    'rack_same_region_semantic_merge_version', 1,
    'hose_positive_anomaly_gate_version', 1,
    'ambiguous_pipe_object_gate_version', 2
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

do $verify_vnext_guardrail_semantic_quality_v30$
declare
  v_matching integer;
begin
  select count(*) into v_matching
  from private.analysis_engine_configs
  where engine_version = 'vnext-v3'
    and is_active = true
    and schema_version = 'hazard-fact-v3.5'
    and prompt_version = 'vnext-photo-expert-v24'
    and policy_version = 'semantic-risk-v26'
    and config->>'public_copy_renderer_version' = '8'
    and config->>'public_spatial_address_policy_version' = '5'
    and config->>'public_narrative_address_policy_version' = '3'
    and config->>'root_cause_claim_policy_version' = '6'
    and config->>'root_cause_qualification_version' = '4'
    and config->>'same_photo_equivalent_condition_merge_version' = '3'
    and config->>'generic_visual_hazard_gate_version' = '4'
    and config->>'excavation_slope_evidence_policy_version' = '5'
    and config->>'guardrail_geometry_synonym_version' = '1'
    and config->>'housekeeping_semantic_merge_version' = '1'
    and config->>'rack_same_region_semantic_merge_version' = '1'
    and config->>'hose_positive_anomaly_gate_version' = '1'
    and config->>'ambiguous_pipe_object_gate_version' = '2';

  if v_matching < 1 then
    raise exception 'vNext guardrail and semantic quality policy v30 did not apply';
  end if;
end;
$verify_vnext_guardrail_semantic_quality_v30$;
