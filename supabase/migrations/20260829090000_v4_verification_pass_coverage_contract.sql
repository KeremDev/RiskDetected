-- v4-vision-core-v7 / claim-routing-v17.
--
-- The verification pass shipped in v6 never ran. On analysis 63c74d15 the
-- second call returned HTTP 200 with a full 3736-token answer and was thrown
-- away as provider_schema_invalid, costing $0.017 for nothing. The analysis
-- itself was unaffected -- the pass is best-effort and the run continued on the
-- first pass -- but the feature delivered nothing.
--
-- Cause: parseOutput holds every response to the coverage contract, and
-- expectedCoverageModules always unions Core-7 regardless of the requiredModules
-- argument, so there was no way to ask for a partial answer. The second pass is
-- a gap-finding look whose module_coverage is never read -- the report is
-- projected from the primary pass -- so the contract could only discard valid
-- answers. This is the same trap the targeted-reinspection code carries a
-- comment about; I walked into it from the other side.
--
-- Three changes:
--   * callV4Gemini takes skipCoverageContract for calls whose coverage matrix is
--     never consumed, and the verification pass sets it.
--   * The second-pass prompt no longer asks for full coverage; it records only
--     the modules it re-examined, and may leave the array empty.
--   * The failure detail is written to the quality trace. The bare error code
--     said "provider_schema_invalid" and the message was nowhere, so diagnosing
--     this meant reading the parser.
--
-- The prompt bundle changed, so prompt_version and prompt_sha256 both move.
do $$
declare
  v_sha constant text :=
    '7a1ff1e61401699a1264af54a71c3c65a97939a31511de0bc3193022be61d2e3';
begin
  update private.analysis_v4_configs
  set prompt_version = 'v4-vision-core-v7',
      prompt_sha256 = v_sha,
      router_version = 'claim-routing-v17',
      config = config
        || jsonb_build_object(
             'prompt_version', 'v4-vision-core-v7',
             'prompt_sha256', v_sha,
             'prompt_bundle_sha256', v_sha,
             'router_version', 'claim-routing-v17',
             'verification_pass_skips_coverage_contract', true,
             'single_photo_verification_pass_version', 2,
             'verification_pass_failure_detail_version', 1
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v7'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v17'
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
