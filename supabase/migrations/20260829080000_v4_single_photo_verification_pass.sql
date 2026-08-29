-- v4-vision-core-v6 / claim-routing-v16: a second look at single-photo analyses.
--
-- Analysis 96c7f819 is why. On a photograph earlier runs had read as four heavy
-- candidates the model produced one, and that one was false: a missing toeboard
-- reported at visibility 0.9 over an evidence region where the toeboard is
-- plainly visible, while machinery was closed as "görünürde korumasız hareketli
-- makine parçaları yok" over two unguarded agitator drives. Neither failure is
-- reachable from the router. It classifies what it is handed; it cannot recover
-- a candidate that was never produced, and it cannot dispute a claim that
-- nothing contradicts.
--
-- The engine now looks twice at a single-photo analysis and reconciles, with a
-- deliberately asymmetric rule:
--
--   Recall  -- anything the second pass finds that the first did not is added,
--              no agreement required. A missed hazard is the worse error.
--   Caution -- a first-pass ABSENCE claim becomes a field check, never a
--              deletion, when the second pass says it can SEE the component the
--              first pass called missing. Silence does not count, and neither
--              does a module closed as "nothing actionable": this model closes
--              modules wholesale, so accepting that as contradiction would
--              demote more true findings than false ones.
--
-- Single photo only, as instructed. A multi-photo analysis already spends one
-- call per photo and doubling that is a separate cost decision.
--
-- Cost: one extra primary-sized call on single-photo runs, about +$0.006 on a
-- ~$0.016 analysis. Multi-photo runs are untouched. The pass is best-effort --
-- if it fails the run continues on the first pass alone and the failure is
-- recorded as a provider attempt.
--
-- The prompt bundle gains the second-pass instructions, so prompt_version and
-- prompt_sha256 both move.
alter table private.analysis_provider_attempts
  drop constraint if exists analysis_provider_attempts_attempt_kind_check;

alter table private.analysis_provider_attempts
  add constraint analysis_provider_attempts_attempt_kind_check
  check (attempt_kind in (
    'primary', 'technical_retry', 'schema_repair',
    'targeted_reinspection', 'provider_fallback', 'verification_pass'
  ));

do $$
declare
  v_sha constant text :=
    'c066259216d0dbb3c43e966e2b9bad48afc6f8c33fd133a0ca0b07fd2e96cb61';
begin
  update private.analysis_v4_configs
  set prompt_version = 'v4-vision-core-v6',
      prompt_sha256 = v_sha,
      router_version = 'claim-routing-v16',
      config = config
        || jsonb_build_object(
             'prompt_version', 'v4-vision-core-v6',
             'prompt_sha256', v_sha,
             'prompt_bundle_sha256', v_sha,
             'router_version', 'claim-routing-v16',
             'single_photo_verification_pass_enabled', true,
             'single_photo_verification_pass_version', 1,
             'verification_pass_recall_only_merge_version', 1,
             'verification_disagreement_demotion_version', 1
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v6'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v16'
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 prompt/router bump did not land cleanly';
  end if;

  -- The known-good checkpoint must survive this, inert and unchanged.
  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
