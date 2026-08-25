-- Return every vNext compute profile to Gemini-only execution while keeping
-- the Luna/background implementation available for an explicit future
-- re-enable. Historical experiment and usage records are intentionally kept.

update private.analysis_engine_configs
set
  config = jsonb_set(
    jsonb_set(
      config,
      '{compute_profiles,premium}',
      coalesce(config #> '{compute_profiles,premium}', '{}'::jsonb) ||
        jsonb_build_object(
          'primary_provider', 'gemini',
          'primary_model', 'gemini-2.5-flash',
          'fallback_provider', 'gemini',
          'fallback_model', 'gemini-2.5-flash'
        ),
      true
    ),
    '{compute_profiles,economy}',
    coalesce(config #> '{compute_profiles,economy}', '{}'::jsonb) ||
      jsonb_build_object(
        'primary_provider', 'gemini',
        'primary_model', 'gemini-2.5-flash',
        'fallback_provider', 'gemini',
        'fallback_model', 'gemini-2.5-flash'
      ),
    true
  ) || jsonb_build_object(
    'primary_provider', 'gemini',
    'primary_model', 'gemini-2.5-flash',
    'fallback_provider', 'gemini',
    'fallback_model', 'gemini-2.5-flash',
    'openai_luna_background_enabled', false,
    'openai_luna_background_version', 'openai-luna-background-disabled'
  ),
  updated_at = now()
where is_active;

update private.analysis_provider_experiment_overrides
set
  enabled = false,
  remaining_analyses = 0,
  updated_at = now()
where provider = 'openai'
   or model = 'gpt-5.6-luna';
