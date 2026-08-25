-- Activates v4 prompt v4-vision-core-v4 and router claim-routing-v3.
--
-- Live run b5c46b89 published three ordinary E3 candidates as scored findings
-- and demoted the single fatal E3 candidate - accessible event path, no
-- occlusion - to a field-check item. Eight defects behind that outcome:
--
--   1. routeClass tested criticality before the finding branch, so severity
--      raised the evidence bar instead of the consequence.
--   2. The escape hatch beside it demanded counter_cues.length === 0, which
--      punished the model for writing the counter-cues the prompt asks for.
--   3. STRUCTURAL_ABSENCE used a trailing \b, which never fires on Turkish
--      suffixes: "eksikliği" failed "\beksik\b".
--   4. severity() returned 7 for both "ordinary" and "serious".
--   5. A missing evidence_region capped every candidate at E3.
--   6. Scene ids (person_2) and module ids reached titles and categories.
--   7. The prompt had lost the scene-level mandatory scan lists.
--   8. The critical-fate invariant accepted a demotion as success.

update private.analysis_v4_configs
set
  prompt_version = 'v4-vision-core-v4',
  prompt_sha256 = '88d544bf23827e39385b75aabe9ad2ea45a61139b047721944d4a86618d58d63',
  router_version = 'claim-routing-v3',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'severity_parity_routing_version', 1,
    'turkish_absence_stem_version', 1,
    'counter_cue_tolerance_version', 1,
    'inherited_region_localization_version', 1,
    'fine_kinney_ordinary_severity_version', 1,
    'module_category_projection_version', 1,
    'mandatory_scene_scan_version', 1,
    'critical_demotion_audit_version', 1
  ),
  updated_at = now()
where engine_version = 'vnext-v4'
  and is_active = true;

do $$
declare
  v_config private.analysis_v4_configs%rowtype;
begin
  select * into v_config
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  if not found
    or v_config.prompt_version <> 'v4-vision-core-v4'
    or v_config.prompt_sha256
      <> '88d544bf23827e39385b75aabe9ad2ea45a61139b047721944d4a86618d58d63'
    or v_config.router_version <> 'claim-routing-v3'
  then
    raise exception 'v4 severity-parity routing activation verification failed';
  end if;
end;
$$;
