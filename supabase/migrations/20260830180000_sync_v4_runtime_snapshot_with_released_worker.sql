-- Keep the active V4 snapshot aligned with the released worker bundle.
--
-- claim-routing-v36/v37 and Gemini 3 core-v5/v6 were released in code while
-- the active database snapshot still advertised v35/core-v4. The worker is
-- fail-closed on that mismatch, so every queued analysis stopped before any
-- provider call. This migration advances only the versioned snapshot; the
-- base v4-vision-core-v10 bundle and its measured SHA remain byte-identical.

update private.analysis_v4_configs
set router_version = 'claim-routing-v37',
    config = config || jsonb_build_object(
      'router_version', 'claim-routing-v37',
      'gemini3_prompt_version', 'v4-gemini3-core-v6',
      'gemini3_prompt_sha256',
        '047a9a50dc64a2e889bd97258d6c9dd962e8547a6f15ace3294147021e3fa025'
    ),
    updated_at = now()
where engine_version = 'vnext-v4'
  and is_active = true;

do $verification$
begin
  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and domain_schema_version = 'safety-claim-v4.0'
    and provider_contract_version = 'visual-claim-candidate-v1'
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and router_version = 'claim-routing-v37'
    and config->>'router_version' = 'claim-routing-v37'
    and config->>'gemini3_prompt_version' = 'v4-gemini3-core-v6'
    and config->>'gemini3_prompt_sha256' =
      '047a9a50dc64a2e889bd97258d6c9dd962e8547a6f15ace3294147021e3fa025';

  if not found then
    raise exception 'released V4 worker and active runtime snapshot are not aligned';
  end if;
end;
$verification$;
