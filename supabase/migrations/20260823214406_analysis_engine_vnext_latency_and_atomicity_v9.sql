-- vNext latency, atomicity and deterministic scoring policy v9.
--
-- No public/mobile schema change. Each fact now carries one required semantic
-- mechanism code, sparse module audits are completed server-side, same-photo
-- dedup retains distinct physical entities, and timeout recovery retries the
-- primary provider with a lower budget before any eligible fallback.

do $$
begin
  update private.analysis_engine_configs
  set schema_version = 'hazard-fact-v3.1',
      prompt_version = 'vnext-photo-expert-v9',
      policy_version = 'semantic-risk-v9',
      config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
        'gemini_thinking_budget', 8192,
        'max_provider_output_tokens', 20480,
        'primary_timeout_ms', 50000,
        'technical_retry_timeout_ms', 35000,
        'technical_retry_gemini_thinking_budget', 6144,
        'recovery_route_version', 2,
        'sparse_module_audit_version', 1,
        'mechanism_code_version', 1,
        'entity_aware_same_photo_dedup_version', 1,
        'zero_fact_signal_targeting_version', 2,
        'canonical_text_normalization_version', 1,
        'hook_latch_evidence_policy_version', 2
      ),
      updated_at = now()
  where engine_version = 'vnext-v3'
    and is_active = true;

  if not found then
    raise exception 'active vnext-v3 engine configuration not found';
  end if;
end;
$$;
