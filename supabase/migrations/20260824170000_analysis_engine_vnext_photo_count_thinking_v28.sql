-- Apply photo-count-aware Gemini thinking budgets only to new vNext route
-- snapshots. Existing routes keep the engine config already pinned to them.

update private.analysis_engine_configs
set
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'gemini_thinking_by_photo_enabled', true,
    'gemini_thinking_policy_version', 'gemini-thinking-by-photo-v1',
    'compute_profiles',
      coalesce(config->'compute_profiles', '{}'::jsonb) || jsonb_build_object(
        'premium',
          coalesce(config#>'{compute_profiles,premium}', '{}'::jsonb) ||
          jsonb_build_object(
            'gemini_thinking_budget', 2048,
            'single_photo_gemini_thinking_budget', 3072,
            'multi_photo_gemini_thinking_budget', 2048,
            'technical_retry_gemini_thinking_budget', 1536,
            'targeted_gemini_thinking_budget', 768
          ),
        'economy',
          coalesce(config#>'{compute_profiles,economy}', '{}'::jsonb) ||
          jsonb_build_object(
            'gemini_thinking_budget', 1024,
            'single_photo_gemini_thinking_budget', 1024,
            'multi_photo_gemini_thinking_budget', 1024,
            'technical_retry_gemini_thinking_budget', 256,
            'targeted_gemini_thinking_budget', 256
          )
      )
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

do $verify_vnext_photo_thinking$
declare
  v_matching integer;
begin
  select count(*) into v_matching
  from private.analysis_engine_configs
  where engine_version = 'vnext-v3'
    and is_active = true
    and config->>'gemini_thinking_by_photo_enabled' = 'true'
    and config->>'gemini_thinking_policy_version' =
      'gemini-thinking-by-photo-v1'
    and config#>>'{compute_profiles,premium,single_photo_gemini_thinking_budget}' =
      '3072'
    and config#>>'{compute_profiles,premium,multi_photo_gemini_thinking_budget}' =
      '2048'
    and config#>>'{compute_profiles,economy,gemini_thinking_budget}' = '1024'
    and config#>>'{compute_profiles,premium,technical_retry_gemini_thinking_budget}' =
      '1536'
    and config#>>'{compute_profiles,premium,targeted_gemini_thinking_budget}' =
      '768'
    and config#>>'{compute_profiles,economy,technical_retry_gemini_thinking_budget}' =
      '256'
    and config#>>'{compute_profiles,economy,targeted_gemini_thinking_budget}' =
      '256';

  if v_matching < 1 then
    raise exception 'vNext photo-count thinking policy did not apply';
  end if;
end;
$verify_vnext_photo_thinking$;
