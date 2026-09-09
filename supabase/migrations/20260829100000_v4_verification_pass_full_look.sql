-- v4-vision-core-v8 / claim-routing-v18.
--
-- The verification pass ran for the first time on analysis 1c1dfd44 and
-- contributed nothing: zero candidates added, zero disputed, zero duplicates,
-- for 3071 thinking tokens and $0.017. Zero duplicates is the tell -- the second
-- pass returned no candidates at all, so there was nothing for the reconciler
-- to match.
--
-- The prompt caused it. It said "birinci incelemenin bulduğu bir koşulu tekrar
-- yazma; yalnızca onun görmediği tehlikeler için aday üret", which asks the
-- model to compute a diff against another pass's reasoning -- an unnatural task
-- that it answered by producing nothing. The engine already knows how to match
-- two passes: reconcileVerificationPass compares by asset ref, then event path,
-- then label overlap, and that path is covered by tests.
--
-- So the second pass is now told to do a full independent look and report every
-- hazard it sees, repeats included, and that producing no candidates is not an
-- answer. Deduplication stays where it belongs, in code. Agreement between the
-- passes becomes visible as a duplicate count rather than being suppressed at
-- the source.
--
-- The pass also could not be diagnosed. Its output was never stored, so the
-- first failure had to be traced by reading the parser and this one by
-- inferring from a zero duplicate count. A compact summary of what the second
-- pass returned -- candidate labels, positive controls, entity and coverage
-- counts -- now goes to the quality trace.
--
-- The prompt bundle changed, so prompt_version and prompt_sha256 both move.
do $$
declare
  v_sha constant text :=
    '5b3e980edc035e3e6d4206b31011e159c6319e98850475c2c0cd4c55b1cb7e12';
begin
  update private.analysis_v4_configs
  set prompt_version = 'v4-vision-core-v8',
      prompt_sha256 = v_sha,
      router_version = 'claim-routing-v18',
      config = config
        || jsonb_build_object(
             'prompt_version', 'v4-vision-core-v8',
             'prompt_sha256', v_sha,
             'prompt_bundle_sha256', v_sha,
             'router_version', 'claim-routing-v18',
             'single_photo_verification_pass_version', 3,
             'verification_pass_full_look_version', 1,
             'verification_pass_output_trace_version', 1
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v8'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v18'
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
