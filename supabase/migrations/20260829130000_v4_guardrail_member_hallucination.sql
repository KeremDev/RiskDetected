-- v4-vision-core-v10 / claim-routing-v21: stop scoring a guardrail member the
-- photograph shows.
--
-- Four consecutive runs of one process-tank photograph each named a DIFFERENT
-- missing guardrail member: toeboard (v8), top rail (v9/router v19), then mid
-- rail three times over at fatal criticality, FK 972, band critical (d32d23f8).
-- The photograph carries top rail, mid rail and toeboard on every platform in
-- the frame. The member rotates run to run, which is what a guess looks like.
--
-- Three defects, all of them ours:
--
-- 1. "ara korkuluk bulunması gereken boşluk açıkça görünür" parsed as a SIGHTING
--    of the rail. The presence verb cancelled the label's own "eksikliği", the
--    candidate carried no claimed-absent component, and every barrier gate was
--    skipped. Gap nouns now read as absence context, not presence.
--
-- 2. A guardrail is a welded assembly. When the photo's own positive controls
--    affirm the member above AND the member below the one called missing, the
--    claim asks the reader to believe one bar was cut out of a factory rail.
--    That is now a field check rather than a scored finding -- a genuine cut-out
--    mid rail is rare, not impossible, so it is asked, not dropped.
--
-- 3. The output-language check pooled the whole answer into one string. This run
--    replied in BOTH languages -- one Turkish candidate, then three English ones
--    -- and the first block's diacritics carried the rest through. The report
--    published "Missing mid-rail on the foreground right platform guardrail"
--    beneath a Turkish finding. The check now runs per claim.
--
-- The prompt gains the same rule the router now enforces, so the claim is
-- discouraged at the source rather than only downgraded after the fact.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set prompt_version = 'v4-vision-core-v10',
      prompt_sha256 = v_sha,
      router_version = 'claim-routing-v21',
      config = config
        || jsonb_build_object(
             'prompt_version', 'v4-vision-core-v10',
             'prompt_sha256', v_sha,
             'prompt_bundle_sha256', v_sha,
             'router_version', 'claim-routing-v21',
             'barrier_member_sandwich_gate', true,
             'output_language_contract_version', 2
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
    and router_version = 'claim-routing-v21'
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 prompt/router bump did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
