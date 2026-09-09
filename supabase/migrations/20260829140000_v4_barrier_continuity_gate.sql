-- claim-routing-v22: a guardrail claim that names no member is still a guardrail
-- claim.
--
-- The member-specific gates closed one door and analysis 09e812b0 walked through
-- the next: "Ana platformun sağ tarafındaki korkulukta boşluk" -- fatal, FK 720,
-- band critical, confidence 0.9. A break in the rail LINE rather than a missing
-- top rail, mid rail or toeboard, so nothing was named and nothing could be
-- matched against the positive controls. Those controls, in the same output,
-- read "Platform kenarı boyunca uzanan sarı üst korkuluk mevcuttur" and the same
-- for the mid rail. The rail runs unbroken to both frame edges.
--
-- Fifth consecutive run of this photograph with a false guardrail claim, each in
-- a different form: toeboard, top rail, mid rail, mid rail again, now an unnamed
-- gap. So the gate stops chasing the wording. When the photo's own controls
-- describe a barrier that RUNS ALONG the edge and affirm more than one of its
-- members, any claim that the same barrier is deficient becomes a field check.
--
-- Deliberately narrow: two members at least AND continuity language ("boyunca",
-- "eksiksiz", "kesintisiz"). One member seen at one point says nothing about the
-- rest of the run and gates nothing -- a genuinely unprotected edge still scores.
-- And this is a demotion, never a drop: rails do get removed and not put back.
--
-- Prompt bundle untouched: v4-vision-core-v10 and its hash carry over.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v22',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v22',
             'barrier_continuity_gate', true
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
    and router_version = 'claim-routing-v22'
    and integrity_status = 'valid';
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
