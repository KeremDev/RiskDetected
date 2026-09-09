-- vNext confirmation, entity-linked coverage, scoring ceiling and controls v8.
--
-- No public/mobile schema change. Ambiguous physical conditions are withheld
-- from scored findings and may consume the existing single targeted pass.
-- Critical-component coverage is based on accepted entity-linked facts, and
-- deterministic scoring can no longer increase semantic consequence severity.

do $$
begin
  update private.analysis_engine_configs
  set prompt_version = 'vnext-photo-expert-v8',
      policy_version = 'semantic-risk-v8',
      control_catalog_version = 'controls-v5',
      config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
        'uncertain_fact_targeting_version', 1,
        'zero_fact_signal_targeting_version', 1,
        'entity_linked_component_coverage_version', 1,
        'semantic_severity_ceiling_version', 1,
        'inventory_compliance_sanitizer_version', 1,
        'mechanism_control_mapping_version', 5
      ),
      updated_at = now()
  where engine_version = 'vnext-v3'
    and is_active = true;

  if not found then
    raise exception 'active vnext-v3 engine configuration not found';
  end if;
end;
$$;
