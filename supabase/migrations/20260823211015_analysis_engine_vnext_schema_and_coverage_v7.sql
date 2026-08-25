-- vNext schema recovery and evidence-led component coverage policy v7.
--
-- No public/mobile schema change. The provider still emits HazardFactV3, but
-- the server now treats the one-photo call context as the authoritative photo
-- lineage, clips evidence regions to image bounds during tolerant parsing and
-- records each repair as a reason code. The prompt uses a three-pass expert
-- sweep and the optional targeted pass is bounded to a lower thinking budget.

do $$
begin
  update private.analysis_engine_configs
  set prompt_version = 'vnext-photo-expert-v7',
      policy_version = 'semantic-risk-v7',
      config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
        'schema_salvage_version', 2,
        'component_coverage_prompt_version', 2,
        'targeted_signal_gate_version', 2,
        'targeted_timeout_ms', 30000,
        'targeted_gemini_thinking_budget', 4096,
        'worker_explicit_failure_retry_version', 1
      ),
      updated_at = now()
  where engine_version = 'vnext-v3'
    and is_active = true;

  if not found then
    raise exception 'active vnext-v3 engine configuration not found';
  end if;
end;
$$;
