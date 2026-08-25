-- vNext v11 removes free-text regulation matching, constrains the optional
-- targeted pass to its selected entity/mechanism, reconciles targeted output
-- against primary findings and reduces provider reasoning/output ceilings.
-- Public/mobile request and finding schemas remain unchanged.

do $$
begin
  update private.analysis_engine_configs
  set prompt_version = 'vnext-photo-expert-v11',
      policy_version = 'semantic-risk-v11',
      control_catalog_version = 'controls-v7',
      config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
        'gemini_thinking_budget', 4096,
        'technical_retry_gemini_thinking_budget', 3072,
        'targeted_gemini_thinking_budget', 2048,
        'max_provider_output_tokens', 12288,
        'targeted_max_provider_output_tokens', 6144,
        'approved_reference_renderer_version', 2,
        'targeted_signal_gate_version', 3,
        'targeted_scope_constraint_version', 1,
        'targeted_primary_reconciliation_version', 1,
        'quality_trace_stage_version', 4,
        'mechanism_control_mapping_version', 7,
        'provider_token_budget_policy_version', 1
      ),
      updated_at = now()
  where engine_version = 'vnext-v3'
    and is_active = true;

  if not found then
    raise exception 'active vnext-v3 engine configuration not found';
  end if;
end;
$$;
