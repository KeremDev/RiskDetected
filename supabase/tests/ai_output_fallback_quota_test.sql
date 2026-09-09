begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

select ok(
  exists (
    select 1 from public.app_feature_flags
    where key = 'ai_output_certainty_policy_v2'
  ),
  'certainty policy flag exists'
);
select is(
  (select value->>'rollout_mode' from public.app_feature_flags
   where key = 'ai_output_certainty_policy_v2'),
  'on',
  'certainty policy starts on'
);
select is(
  (select (value->>'kill_switch')::boolean from public.app_feature_flags
   where key = 'ai_output_certainty_policy_v2'),
  false,
  'certainty policy kill switch starts clear'
);
select ok(
  exists (
    select 1 from public.app_feature_flags
    where key = 'ai_output_deterministic_fallback_v1'
  ),
  'deterministic fallback flag exists'
);
select is(
  (select value->>'rollout_mode' from public.app_feature_flags
   where key = 'ai_output_deterministic_fallback_v1'),
  'on',
  'deterministic fallback starts on'
);
select is(
  (select (value->>'kill_switch')::boolean from public.app_feature_flags
   where key = 'ai_output_deterministic_fallback_v1'),
  false,
  'deterministic fallback kill switch starts clear'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000401'::uuid,
  'fallback-quota-test@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.analyses (id, user_id, kind, status, photo_count)
values
  ('00000000-0000-4000-8000-000000000402'::uuid, '00000000-0000-4000-8000-000000000401'::uuid, 'photo', 'pending', 1),
  ('00000000-0000-4000-8000-000000000403'::uuid, '00000000-0000-4000-8000-000000000401'::uuid, 'photo', 'pending', 1),
  ('00000000-0000-4000-8000-000000000404'::uuid, '00000000-0000-4000-8000-000000000401'::uuid, 'photo', 'pending', 1),
  ('00000000-0000-4000-8000-000000000405'::uuid, '00000000-0000-4000-8000-000000000401'::uuid, 'photo', 'pending', 1);

insert into public.usage_events (user_id, feature, event_type, source_id)
select
  '00000000-0000-4000-8000-000000000401'::uuid,
  'analysis_standard',
  'reserved',
  id
from public.analyses
where id in (
  '00000000-0000-4000-8000-000000000402'::uuid,
  '00000000-0000-4000-8000-000000000403'::uuid,
  '00000000-0000-4000-8000-000000000404'::uuid,
  '00000000-0000-4000-8000-000000000405'::uuid
);

create function pg_temp.final_result(
  consume_quota boolean,
  fallback_zero boolean
) returns jsonb
language sql
as $$
  select jsonb_build_object(
    'status_message', 'test completed',
    'ai_summary', 'test',
    'total_score_fk', 0,
    'total_score_m5', 0,
    'highest_band_fk', 'low',
    'highest_band_m5', 'low',
    'hidden_or_rejected_findings_count', 0,
    'max_findings_per_photo', 13,
    'max_findings_total', 13,
    'consume_analysis_quota', consume_quota,
    'raw_ai_response', jsonb_build_object(
      '_input_audit', jsonb_build_object(
        'deterministic_fallback_used', fallback_zero,
        'deterministic_fallback_zero_findings', fallback_zero
      )
    ),
    'ai_models_used', jsonb_build_array('test-model')
  );
$$;

do $$
declare
  analysis_id uuid;
begin
  foreach analysis_id in array array[
    '00000000-0000-4000-8000-000000000402'::uuid,
    '00000000-0000-4000-8000-000000000403'::uuid,
    '00000000-0000-4000-8000-000000000404'::uuid,
    '00000000-0000-4000-8000-000000000405'::uuid
  ] loop
    perform public.submit_analysis_job_v2(
      '00000000-0000-4000-8000-000000000401'::uuid,
      analysis_id,
      jsonb_build_object('job_mode', 'analysis')
    );
  end loop;
end;
$$;

create temporary table fallback_claims as
select
  s.analysis_id,
  s.active_msg_id,
  s.generation,
  public.claim_analysis_job_v2(
    s.user_id,
    s.analysis_id,
    s.active_msg_id,
    s.generation,
    s.job_mode,
    300,
    3
  ) as response
from private.analysis_job_state s
where s.analysis_id in (
  '00000000-0000-4000-8000-000000000402'::uuid,
  '00000000-0000-4000-8000-000000000403'::uuid,
  '00000000-0000-4000-8000-000000000404'::uuid,
  '00000000-0000-4000-8000-000000000405'::uuid
);

create temporary table legitimate_zero as
select public.finalize_analysis_result_v2(
  s.user_id,
  s.analysis_id,
  s.active_msg_id,
  s.generation,
  (c.response->>'claim_token')::uuid,
  '[]'::jsonb,
  pg_temp.final_result(true, false),
  '[]'::jsonb
) as response
from private.analysis_job_state s
join fallback_claims c using (analysis_id)
where s.analysis_id = '00000000-0000-4000-8000-000000000402'::uuid;

select is(
  (select (response->>'quota_consumed')::boolean from legitimate_zero),
  true,
  'legitimate model zero findings consumes quota'
);
select is(
  (select event_type from public.usage_events
   where source_id = '00000000-0000-4000-8000-000000000402'::uuid),
  'completed',
  'legitimate zero reservation completes'
);

create temporary table fallback_zero as
select public.finalize_analysis_result_v2(
  s.user_id,
  s.analysis_id,
  s.active_msg_id,
  s.generation,
  (c.response->>'claim_token')::uuid,
  '[]'::jsonb,
  pg_temp.final_result(false, true),
  '[]'::jsonb
) as response
from private.analysis_job_state s
join fallback_claims c using (analysis_id)
where s.analysis_id = '00000000-0000-4000-8000-000000000403'::uuid;

select is(
  (select (response->>'quota_consumed')::boolean from fallback_zero),
  false,
  'fallback-created zero findings refunds quota'
);
select is(
  (select count(*)::integer from public.usage_events
   where source_id = '00000000-0000-4000-8000-000000000403'::uuid),
  0,
  'fallback-created zero reservation is deleted'
);
select is(
  (
    select public.finalize_analysis_result_v2(
      s.user_id,
      s.analysis_id,
      c.active_msg_id,
      c.generation,
      (c.response->>'claim_token')::uuid,
      '[]'::jsonb,
      pg_temp.final_result(false, true),
      '[]'::jsonb
    )->>'state'
    from private.analysis_job_state s
    join fallback_claims c using (analysis_id)
    where s.analysis_id = '00000000-0000-4000-8000-000000000403'::uuid
  ),
  'already_completed',
  'fallback finalization retry is idempotent'
);
select is(
  (select count(*)::integer from public.usage_events
   where source_id = '00000000-0000-4000-8000-000000000403'::uuid),
  0,
  'idempotent retry does not recreate quota usage'
);

create temporary table fallback_with_finding as
select public.finalize_analysis_result_v2(
  s.user_id,
  s.analysis_id,
  s.active_msg_id,
  s.generation,
  (c.response->>'claim_token')::uuid,
  jsonb_build_array(jsonb_build_object(
    'ordinal', 1,
    'title', 'Visible guard issue',
    'category', 'Workplace safety',
    'description', 'A visible condition requires control.',
    'recommended_action', 'Install a guard.',
    'recommended_measures', jsonb_build_array(),
    'references_text', '',
    'root_cause_text', 'A possible contributing factor requires review.',
    'confidence', 0.8,
    'needs_field_verification', false,
    'ai_original_snapshot', jsonb_build_object(),
    'source_photo_indices', jsonb_build_array(1),
    'source_photo_observations', jsonb_build_array(),
    'finding_budget_policy', jsonb_build_object(),
    'ai_confidence', 0.8,
    'fk_probability', 3,
    'fk_frequency', 2,
    'fk_severity', 15,
    'fk_band', 'high',
    'm5_probability', 3,
    'm5_severity', 4,
    'm5_band', 'high',
    'display_order', 1
  )),
  pg_temp.final_result(false, true),
  '[]'::jsonb
) as response
from private.analysis_job_state s
join fallback_claims c using (analysis_id)
where s.analysis_id = '00000000-0000-4000-8000-000000000404'::uuid;

select is(
  (select (response->>'quota_consumed')::boolean from fallback_with_finding),
  true,
  'fallback with a retained finding still consumes quota'
);
select is(
  (select event_type from public.usage_events
   where source_id = '00000000-0000-4000-8000-000000000404'::uuid),
  'completed',
  'retained-finding reservation completes'
);
select is(
  (select finding_count from public.analyses
   where id = '00000000-0000-4000-8000-000000000404'::uuid),
  1,
  'retained fallback finding is saved'
);

select is(
  (
    select public.finalize_analysis_result_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      gen_random_uuid(),
      '[]'::jsonb,
      pg_temp.final_result(false, true),
      '[]'::jsonb
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000405'::uuid
  ),
  'lost_claim',
  'lost worker claim cannot settle quota'
);
select is(
  (select event_type from public.usage_events
   where source_id = '00000000-0000-4000-8000-000000000405'::uuid),
  'reserved',
  'lost claim leaves reservation untouched'
);

select * from finish();
rollback;
