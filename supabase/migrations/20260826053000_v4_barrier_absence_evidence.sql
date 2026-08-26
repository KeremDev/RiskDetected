-- v4-vision-core-v5 / claim-routing-v7.
--
-- On analysis 4534c158 the provider produced four guardrail candidates for
-- photo 1 -- mid-rail missing and toeboard missing on both the upper and the
-- lower platform -- with occlusion "none" and empty counter_cues. The photograph
-- shows all three members present on both guardrails. Two of the four were
-- published as scored findings at FK 270 and FK 126.
--
-- Nothing downstream could catch it: the router demotes absence claims that
-- carry contradicting counter-cues, and the provider supplied none. Two changes.
--
-- Prompt (bundle changes, so prompt_version and prompt_sha256 both move):
-- before writing a guardrail absence claim the model must decide each of the
-- three members separately and put every member it can see into counter_cues;
-- it may only call a member missing when it can localise the gap and see that
-- the gap is empty; an edge-on, backlit or occluded rail line must be closed as
-- unresolved_requires_verification instead; and claiming two members of the same
-- guardrail missing at once must be questioned, because that is the signature of
-- having registered only the top rail.
--
-- Router: when a photo's own positive controls affirm the very component a
-- candidate calls missing, the candidate becomes a verification_request rather
-- than a scored finding. An earlier run held both statements at once -- "Üst
-- platformda tam korkuluk sistemi ... mevcuttur" beside a candidate calling that
-- system incomplete -- and published the finding anyway. Nothing is lost by the
-- demotion: the engine already had both claims and cannot settle them.
--
-- Also: rocky uneven ground on an excavation site was published under the
-- clutter title "Zemindeki dağınık malzemelerde takılma riski", identical to a
-- warehouse floor covered in cardboard, and the title-uniqueness pass hid the
-- collision behind a "(2)" suffix.
do $$
declare
  v_sha constant text :=
    '116ac911e576c83c61810ecfc956a8f7d0a4b1bb51b16fe8a7c4ec3d1caefb2e';
begin
  update private.analysis_v4_configs
  set prompt_version = 'v4-vision-core-v5',
      prompt_sha256 = v_sha,
      router_version = 'claim-routing-v7',
      config = config
        || jsonb_build_object(
             'prompt_version', 'v4-vision-core-v5',
             'prompt_sha256', v_sha,
             'prompt_bundle_sha256', v_sha,
             'router_version', 'claim-routing-v7',
             'barrier_member_enumeration_version', 1,
             'provider_self_contradiction_gate_version', 1,
             'visible_safety_barrier_evidence_version', 4,
             'housekeeping_terrain_title_version', 1,
             'finding_title_policy_version', 4
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v5'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v7'
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 prompt/router bump did not land cleanly';
  end if;
end $$;
