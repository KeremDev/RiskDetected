begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(32);

select has_table(
  'private',
  'analysis_job_events',
  'private analysis job event table exists'
);
select has_function(
  'public',
  'record_analysis_job_event_v2',
  array[
    'uuid', 'uuid', 'bigint', 'integer', 'integer', 'text', 'text',
    'integer', 'text', 'text', 'text'
  ],
  'job event RPC exists'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.record_analysis_job_event_v2(uuid,uuid,bigint,integer,integer,text,text,integer,text,text,text)',
    'execute'
  ),
  'anon cannot record job events'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_analysis_job_event_v2(uuid,uuid,bigint,integer,integer,text,text,integer,text,text,text)',
    'execute'
  ),
  'authenticated cannot record job events'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.record_analysis_job_event_v2(uuid,uuid,bigint,integer,integer,text,text,integer,text,text,text)',
    'execute'
  ),
  'service role can record job events'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'private.analysis_job_events'::regclass
  ),
  'job event table has RLS defense in depth'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000301'::uuid,
  'ambiguous-guard-test@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.analyses (id, user_id, kind, status, photo_count)
values
  (
    '00000000-0000-4000-8000-000000000302'::uuid,
    '00000000-0000-4000-8000-000000000301'::uuid,
    'photo',
    'pending',
    1
  ),
  (
    '00000000-0000-4000-8000-000000000303'::uuid,
    '00000000-0000-4000-8000-000000000301'::uuid,
    'photo',
    'pending',
    1
  ),
  (
    '00000000-0000-4000-8000-000000000304'::uuid,
    '00000000-0000-4000-8000-000000000301'::uuid,
    'photo',
    'pending',
    1
  );

create temporary table guard_submit_one as
select public.submit_analysis_job_v2(
  '00000000-0000-4000-8000-000000000301'::uuid,
  '00000000-0000-4000-8000-000000000302'::uuid,
  jsonb_build_object('claim_guard_version', 2)
) as response;

select is(
  (select response->>'state' from guard_submit_one),
  'queued',
  'guarded job submits normally'
);
select is(
  (
    select q.message->>'claim_guard_version'
    from private.analysis_job_state s
    join pgmq.q_analysis_jobs q on q.msg_id = s.active_msg_id
    where s.analysis_id = '00000000-0000-4000-8000-000000000302'::uuid
  ),
  '2',
  'claim guard version is snapshotted into queue message'
);

create temporary table guard_claim_one as
select public.claim_analysis_job_v2(
  s.user_id,
  s.analysis_id,
  s.active_msg_id,
  s.generation,
  s.job_mode,
  300,
  3
) as response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000302'::uuid;

select is(
  (select response->>'state' from guard_claim_one),
  'claimed',
  'first guarded worker claims job'
);
select is(
  (select response->>'claim_reason' from guard_claim_one),
  'initial',
  'first claim is classified as initial'
);
select is(
  (
    select public.record_analysis_job_event_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      s.worker_attempt_count,
      s.job_mode,
      'dispatch_ambiguous_transport',
      504,
      'gateway_timeout',
      'keep',
      'nested response lost'
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000302'::uuid
  ),
  'recorded',
  'ambiguous transport event records successfully'
);
select is(
  (
    select count(*)::bigint
    from private.analysis_job_events
    where analysis_id = '00000000-0000-4000-8000-000000000302'::uuid
      and event_type = 'dispatch_ambiguous_transport'
  ),
  1::bigint,
  'ambiguous event is durable'
);
select is(
  (
    select claim_token::text
    from private.analysis_job_state
    where analysis_id = '00000000-0000-4000-8000-000000000302'::uuid
  ),
  (select response->>'claim_token' from guard_claim_one),
  'telemetry cannot mutate the active claim token'
);
select is(
  (
    select public.validate_analysis_job_claim_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      (select (response->>'claim_token')::uuid from guard_claim_one)
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000302'::uuid
  ),
  'claimed',
  'original token remains valid after ambiguous event'
);

create temporary table guard_finalize_one as
select public.finalize_analysis_result_v2(
  s.user_id,
  s.analysis_id,
  s.active_msg_id,
  s.generation,
  (select (response->>'claim_token')::uuid from guard_claim_one),
  '[]'::jsonb,
  jsonb_build_object(
    'status_message', 'completed after response loss',
    'ai_summary', 'test',
    'total_score_fk', 0,
    'total_score_m5', 0,
    'highest_band_fk', 'low',
    'highest_band_m5', 'low',
    'hidden_or_rejected_findings_count', 0,
    'max_findings_per_photo', 13,
    'max_findings_total', 13,
    'raw_ai_response', jsonb_build_object('test', true),
    'ai_models_used', jsonb_build_array('test-model')
  ),
  '[]'::jsonb
) as response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000302'::uuid;

select is(
  (select response->>'state' from guard_finalize_one),
  'completed',
  'original token finalizes after ambiguous transport'
);
select is(
  (
    select status::text
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000302'::uuid
  ),
  'completed',
  'analysis completes without a replacement worker'
);

do $$
begin
  perform public.submit_analysis_job_v2(
    '00000000-0000-4000-8000-000000000301'::uuid,
    '00000000-0000-4000-8000-000000000303'::uuid,
    jsonb_build_object('claim_guard_version', 2)
  );
end;
$$;
create temporary table guard_claim_two_initial as
select public.claim_analysis_job_v2(
  s.user_id, s.analysis_id, s.active_msg_id, s.generation, s.job_mode, 300, 3
) as response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000303'::uuid;

select is(
  (select response->>'state' from guard_claim_two_initial),
  'claimed',
  'lease test receives first claim'
);

update private.analysis_job_state
set lease_expires_at = now() - interval '1 second'
where analysis_id = '00000000-0000-4000-8000-000000000303'::uuid;

create temporary table guard_claim_two_reclaim as
select public.claim_analysis_job_v2(
  s.user_id, s.analysis_id, s.active_msg_id, s.generation, s.job_mode, 300, 3
) as response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000303'::uuid;

select is(
  (select response->>'claim_reason' from guard_claim_two_reclaim),
  'lease_expired',
  'expired lease retry is distinguished'
);
select is(
  (select (response->>'worker_attempt')::integer from guard_claim_two_reclaim),
  2,
  'lease expiry starts real attempt two'
);
select is(
  (
    select public.record_analysis_job_failure_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      (select (response->>'claim_token')::uuid from guard_claim_two_initial),
      'stale worker',
      'stale_worker',
      'stale worker',
      true,
      null
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000303'::uuid
  ),
  'lost_claim',
  'old token cannot mutate attempt two'
);

update private.analysis_job_state
set lease_expires_at = now() - interval '1 second'
where analysis_id = '00000000-0000-4000-8000-000000000303'::uuid;
create temporary table guard_claim_two_third as
select public.claim_analysis_job_v2(
  s.user_id, s.analysis_id, s.active_msg_id, s.generation, s.job_mode, 300, 3
) as response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000303'::uuid;
select is(
  (select (response->>'worker_attempt')::integer from guard_claim_two_third),
  3,
  'third real attempt is allowed'
);

update private.analysis_job_state
set lease_expires_at = now() - interval '1 second'
where analysis_id = '00000000-0000-4000-8000-000000000303'::uuid;
select is(
  (
    select public.claim_analysis_job_v2(
      s.user_id, s.analysis_id, s.active_msg_id, s.generation, s.job_mode, 300, 3
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000303'::uuid
  ),
  'max_attempts',
  'attempt four is rejected'
);
select is(
  (
    select status::text
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000303'::uuid
  ),
  'failed',
  'max attempts closes analysis terminally'
);

do $$
begin
  perform public.submit_analysis_job_v2(
    '00000000-0000-4000-8000-000000000301'::uuid,
    '00000000-0000-4000-8000-000000000304'::uuid,
    jsonb_build_object('claim_guard_version', 2)
  );
end;
$$;
create temporary table guard_claim_three_initial as
select public.claim_analysis_job_v2(
  s.user_id, s.analysis_id, s.active_msg_id, s.generation, s.job_mode, 300, 3
) as response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000304'::uuid;

insert into public.usage_events (user_id, feature, event_type, source_id)
values (
  '00000000-0000-4000-8000-000000000301'::uuid,
  'analysis_standard',
  'reserved',
  '00000000-0000-4000-8000-000000000304'::uuid
);

select is(
  (
    select public.record_analysis_job_failure_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      (select (response->>'claim_token')::uuid from guard_claim_three_initial),
      'provider 429',
      'provider_rate_limited',
      'retry later',
      false,
      null
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000304'::uuid
  ),
  'retry_pending',
  'controlled retry releases claim non-terminally'
);
select is(
  (
    select count(*)::bigint
    from public.usage_events
    where source_id = '00000000-0000-4000-8000-000000000304'::uuid
      and event_type = 'reserved'
  ),
  1::bigint,
  'controlled retry preserves quota reservation'
);

create temporary table guard_claim_three_retry as
select public.claim_analysis_job_v2(
  s.user_id, s.analysis_id, s.active_msg_id, s.generation, s.job_mode, 300, 3
) as response
from private.analysis_job_state s
where s.analysis_id = '00000000-0000-4000-8000-000000000304'::uuid;
select is(
  (select response->>'claim_reason' from guard_claim_three_retry),
  'released_retry',
  'controlled release is distinct from lease expiry'
);
select is(
  (
    select public.record_analysis_job_failure_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      (select (response->>'claim_token')::uuid from guard_claim_three_retry),
      'terminal data error',
      'terminal_data_error',
      'terminal',
      true,
      null
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000304'::uuid
  ),
  'failed',
  'terminal owner closes the analysis'
);
select is(
  (
    select count(*)::bigint
    from public.usage_events
    where source_id = '00000000-0000-4000-8000-000000000304'::uuid
      and event_type = 'reserved'
  ),
  0::bigint,
  'terminal failure releases reservation exactly once'
);
select is(
  public.record_analysis_job_event_v2(
    '00000000-0000-4000-8000-000000000399'::uuid,
    '00000000-0000-4000-8000-000000000304'::uuid,
    1,
    1,
    1,
    'analysis',
    'claim_kept',
    null,
    null,
    null,
    null
  )->>'state',
  'analysis_not_found',
  'owner mismatch cannot write telemetry'
);
select is(
  (
    select public.record_analysis_job_event_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      2,
      s.job_mode,
      'not_an_allowed_event',
      null,
      null,
      null,
      null
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000304'::uuid
  ),
  'validation_failed',
  'invalid event is rejected without raising'
);

do $$
begin
  perform public.record_analysis_job_event_v2(
    s.user_id,
    s.analysis_id,
    s.active_msg_id,
    s.generation,
    2,
    s.job_mode,
    'claim_kept',
    504,
    'timeout',
    'keep',
    'Bearer secret-value must not survive'
  )
  from private.analysis_job_state s
  where s.analysis_id = '00000000-0000-4000-8000-000000000304'::uuid;
end;
$$;
select ok(
  not exists (
    select 1
    from private.analysis_job_events
    where analysis_id = '00000000-0000-4000-8000-000000000304'::uuid
      and safe_error_text like '%secret-value%'
  ),
  'event RPC redacts bearer material'
);
select ok(
  public.admin_analysis_pipeline_metrics_v2()
    ? 'ambiguous_dispatches_24h',
  'admin metrics expose ambiguous dispatch count'
);

select * from finish();
rollback;
