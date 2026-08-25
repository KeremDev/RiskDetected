-- vNext schema salvage, component coverage and score-stability policy v6.
--
-- No public/mobile schema change. Future engine runs snapshot these policy
-- versions so mixed-provider recovery and deterministic score normalization
-- remain auditable.

do $$
begin
  update private.analysis_engine_configs
  set prompt_version = 'vnext-photo-expert-v6',
      policy_version = 'semantic-risk-v6',
      config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
        'schema_salvage_version', 1,
        'retry_schema_invalid_same_prompt', false,
        'component_coverage_audit_version', 1,
        'score_stability_policy_version', 1,
        'provider_usage_before_schema_validation', true,
        'primary_timeout_ms', 55000,
        'technical_retry_timeout_ms', 35000,
        'fallback_timeout_ms', 65000,
        'targeted_timeout_ms', 20000
      ),
      updated_at = now()
  where engine_version = 'vnext-v3'
    and is_active = true;

  if not found then
    raise exception 'active vnext-v3 engine configuration not found';
  end if;
end;
$$;
