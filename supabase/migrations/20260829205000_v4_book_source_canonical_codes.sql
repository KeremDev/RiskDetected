-- claim-routing-v27: canonical codes on every routed item, for the book engine.
--
-- The approved-book feature plans a paragraph from codes and never rewrites the
-- model's own sentences. That is not a style preference. On one process-tank
-- photograph the engine produced, across five consecutive runs, five different
-- guardrail claims in the model's words -- missing toeboard, missing top rail,
-- missing mid rail twice, then an unnamed gap -- where every platform carried
-- all three members. Rewriting any of those into a more official register would
-- have produced a well-written false record.
--
-- So each routed item now carries `internal_priority.book_source`: module,
-- condition code, mechanism, evidence tier, criticality, occlusion, asset,
-- barrier members claimed absent, the three confidence axes, and whether people
-- were visible. No free text: raw_label, cues and event_path stay out.
--
-- Nothing user-facing changes. `canonical_payload` already stores the whole
-- routed item and `internal_priority` is already its own column, so the block
-- lands without a schema change.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v27',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v27',
             'book_source_schema_version', 'book-source-v1'
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v27'
    and integrity_status = 'valid'
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 3072;
  if not found then
    raise exception 'v4 router bump did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
