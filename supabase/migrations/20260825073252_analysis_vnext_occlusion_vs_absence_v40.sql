-- Separates "not there" from "could not be seen".
--
-- The 3-photo run lost a missing mid-rail whose own second cue read "korkuluk
-- sisteminde düşme korumasını azaltan boşluk" - the gap between two visible
-- posts. The barrier gate dropped it on the word "görünmüyor" in the first
-- cue, which in Turkish is the ordinary way to report an absence rather than
-- an admission that the view failed. Terms that really do say the component
-- could not be assessed still close the gate.
--
-- Server-only: the pinned prompt bundle stays on v31.

update private.analysis_engine_configs
set
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'occlusion_absence_separation_version', 1,
    'structured_visible_barrier_evidence_version', 4,
    'quality_trace_stage_version', 26
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

do $$
declare
  v_config private.analysis_engine_configs%rowtype;
begin
  select * into v_config
  from private.analysis_engine_configs
  where engine_version = 'vnext-v3' and is_active = true;

  if not found
    or v_config.prompt_version <> 'vnext-photo-expert-v31'
    or v_config.config->>'prompt_bundle_sha256'
      <> '508f42409ea2929e0c43fce6d6b4ea8bfcad7c321a05f2d0f15b8939bc9cf144'
    or (v_config.config->>'occlusion_absence_separation_version')::int <> 1
  then
    raise exception 'vNext occlusion separation activation verification failed';
  end if;
end;
$$;
