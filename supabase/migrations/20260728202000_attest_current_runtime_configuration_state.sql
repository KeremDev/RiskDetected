-- Forward-only attestation of mutable runtime configuration that existed in
-- production on 2026-07-28 but was not fully represented by migration history.
--
-- Existing unknown feature-flag keys are retained. Known keys are set to the
-- reviewed baseline. The nested multi_photo_analysis.features object is also
-- merged so future unknown feature switches are not deleted.

insert into public.app_feature_flags (key, value)
values
  ('analysis_ambiguous_dispatch_guard', '{"rollout_mode":"on","enabled_user_hashes":[]}'::jsonb),
  ('analysis_pipeline_v2', '{"rollout_mode":"on","lease_seconds":300,"enabled_user_hashes":[],"max_worker_attempts":3}'::jsonb),
  ('cancelled_plus_trial_free_routing', '{"mode":"on","user_hashes":[]}'::jsonb),
  ('multi_photo_analysis', '{"features":{"editable_findings":true,"manual_finding_add":false,"report_snapshot_v2":true,"multi_photo_analysis":true,"plus_pro_5_photo_limit":true,"multi_photo_coverage_v2":true,"photo_limit_locked_slots_for_free":true},"kill_switch":false,"rollout_mode":"build_allowlist","min_ios_build":null,"enabled_ios_builds":["63","64","65","66","67","68","69","70","71","72","73","74","75","76","77"],"runtime_guard_note":"Paid multi-photo product limit: Plus/Pro max 3 photos per analysis.","max_photo_count_pro":3,"max_photo_count_free":1,"max_photo_count_plus":3,"coverage_rollout_note":"Requires client_capabilities.multi_photo_coverage_v2=true; legacy builds stay on hazards[] flow.","max_findings_per_photo":13,"coverage_repair_enabled":true,"enable_editable_findings":false,"enable_manual_finding_add":false,"enable_report_snapshot_v2":false,"target_findings_total_max":39,"enable_multi_photo_analysis":false,"multi_photo_thinking_budget":3072,"single_photo_thinking_budget":6144,"enable_plus_pro_5_photo_limit":false,"target_findings_per_photo_max":13,"target_findings_per_photo_min":1,"enable_multi_photo_coverage_v2":false,"multi_photo_layer_audit_enabled":false,"single_photo_layer_audit_enabled":true,"single_photo_evidence_guard_enabled":true,"enable_photo_limit_locked_slots_for_free":false,"single_photo_compact_layer_schema_enabled":true}'::jsonb),
  ('multi_photo_exact_coverage_schema', '{"kill_switch":false,"rollout_mode":"on","schema_version":2,"enabled_user_hashes":[]}'::jsonb)
on conflict (key) do update
set value =
  case
    when excluded.key = 'multi_photo_analysis' then
      jsonb_set(
        public.app_feature_flags.value
          || (excluded.value - 'features'),
        '{features}',
        coalesce(public.app_feature_flags.value -> 'features', '{}'::jsonb)
          || coalesce(excluded.value -> 'features', '{}'::jsonb),
        true
      )
    else public.app_feature_flags.value || excluded.value
  end;

insert into public.plan_capability_rules (
  plan,
  max_photos_per_analysis,
  visible_photo_slots_in_ui,
  max_findings_per_photo,
  max_findings_per_analysis,
  can_use_multi_photo_analysis,
  can_edit_ai_findings,
  can_add_manual_findings
)
values
  ('free', 1, 5, 12, 12, false, true, false),
  ('plus', 3, 3, 13, 39, true, true, false),
  ('pro', 3, 3, 13, 39, true, true, false)
on conflict (plan) do update
set
  max_photos_per_analysis = excluded.max_photos_per_analysis,
  visible_photo_slots_in_ui = excluded.visible_photo_slots_in_ui,
  max_findings_per_photo = excluded.max_findings_per_photo,
  max_findings_per_analysis = excluded.max_findings_per_analysis,
  can_use_multi_photo_analysis = excluded.can_use_multi_photo_analysis,
  can_edit_ai_findings = excluded.can_edit_ai_findings,
  can_add_manual_findings = excluded.can_add_manual_findings,
  updated_at = now();
