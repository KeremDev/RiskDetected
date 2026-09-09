begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

select has_table('private', 'analysis_job_state', 'private job state table exists');
select has_function(
  'public',
  'submit_analysis_job_v2',
  array['uuid', 'uuid', 'jsonb'],
  'atomic submit RPC exists'
);
select has_function(
  'public',
  'claim_analysis_job_v2',
  array['uuid', 'uuid', 'bigint', 'integer', 'text', 'integer', 'integer'],
  'leased claim RPC exists'
);
select has_function(
  'public',
  'finalize_analysis_result_v2',
  array['uuid', 'uuid', 'bigint', 'integer', 'uuid', 'jsonb', 'jsonb', 'jsonb'],
  'transactional finalization RPC exists'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.submit_analysis_job_v2(uuid,uuid,jsonb)',
    'execute'
  ),
  'anon cannot submit backend queue jobs'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.claim_analysis_job_v2(uuid,uuid,bigint,integer,text,integer,integer)',
    'execute'
  ),
  'authenticated cannot claim backend queue jobs'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000201'::uuid,
  'pipeline-v2-test@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.analyses (id, user_id, kind, status, photo_count)
values (
  '00000000-0000-4000-8000-000000000202'::uuid,
  '00000000-0000-4000-8000-000000000201'::uuid,
  'photo',
  'pending',
  1
);

create temporary table pipeline_v2_baseline as
select count(*)::bigint as queue_depth from pgmq.q_analysis_jobs;

create temporary table pipeline_v2_submit as
select public.submit_analysis_job_v2(
  '00000000-0000-4000-8000-000000000201'::uuid,
  '00000000-0000-4000-8000-000000000202'::uuid,
  jsonb_build_object(
    'analysis_id', '00000000-0000-4000-8000-000000000202',
    'user_id', '00000000-0000-4000-8000-000000000201',
    'job_mode', 'analysis'
  )
) as response;

select is(
  (select response->>'state' from pipeline_v2_submit),
  'queued',
  'first submit queues the analysis'
);
select is(
  (select count(*)::bigint from pgmq.q_analysis_jobs),
  (select queue_depth + 1 from pipeline_v2_baseline),
  'first submit creates one queue message'
);
select is(
  (public.submit_analysis_job_v2(
    '00000000-0000-4000-8000-000000000201'::uuid,
    '00000000-0000-4000-8000-000000000202'::uuid,
    '{}'::jsonb
  )->>'enqueued')::boolean,
  false,
  'duplicate submit is accepted without enqueue'
);
select is(
  (select count(*)::bigint from pgmq.q_analysis_jobs),
  (select queue_depth + 1 from pipeline_v2_baseline),
  'duplicate submit still leaves exactly one queue message'
);

create temporary table pipeline_v2_superseded_msg as
select * from pgmq.send(
  'analysis_jobs',
  jsonb_build_object(
    'analysis_id', '00000000-0000-4000-8000-000000000202',
    'user_id', '00000000-0000-4000-8000-000000000201',
    'pipeline_version', 2,
    '__job_generation', 1
  ),
  0
);

select is(
  (
    select public.claim_analysis_job_v2(
      s.user_id,
      s.analysis_id,
      (select send from pipeline_v2_superseded_msg),
      s.generation,
      s.job_mode,
      300,
      3
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000202'::uuid
  ),
  'superseded',
  'a different duplicate message cannot claim the analysis'
);
do $$
begin
  perform pgmq.delete(
    'analysis_jobs',
    (select send from pipeline_v2_superseded_msg)
  );
end;
$$;

create temporary table pipeline_v2_claim as
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
where s.analysis_id = '00000000-0000-4000-8000-000000000202'::uuid;

select is(
  (select response->>'state' from pipeline_v2_claim),
  'claimed',
  'first worker wins the claim'
);
select is(
  (
    select public.claim_analysis_job_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      s.job_mode,
      300,
      3
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000202'::uuid
  ),
  'busy',
  'second worker cannot claim a live lease'
);
select is(
  (select worker_attempt_count from private.analysis_job_state
   where analysis_id = '00000000-0000-4000-8000-000000000202'::uuid),
  1,
  'busy reads do not consume attempts'
);

update private.analysis_job_state
set lease_expires_at = now() - interval '1 second'
where analysis_id = '00000000-0000-4000-8000-000000000202'::uuid;

create temporary table pipeline_v2_reclaim as
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
where s.analysis_id = '00000000-0000-4000-8000-000000000202'::uuid;

select is(
  (select response->>'state' from pipeline_v2_reclaim),
  'claimed',
  'expired lease can be reclaimed'
);
select isnt(
  (select response->>'claim_token' from pipeline_v2_reclaim),
  (select response->>'claim_token' from pipeline_v2_claim),
  'reclaim receives a new token'
);
select is(
  (select worker_attempt_count from private.analysis_job_state
   where analysis_id = '00000000-0000-4000-8000-000000000202'::uuid),
  2,
  'successful reclaim consumes the next real attempt'
);
select is(
  (
    select public.record_analysis_job_failure_v2(
      s.user_id,
      s.analysis_id,
      s.active_msg_id,
      s.generation,
      (select (response->>'claim_token')::uuid from pipeline_v2_claim),
      'old worker',
      'old_worker',
      'old worker',
      true,
      null
    )->>'state'
    from private.analysis_job_state s
    where s.analysis_id = '00000000-0000-4000-8000-000000000202'::uuid
  ),
  'lost_claim',
  'old token cannot fail a newly claimed analysis'
);

create temporary table pipeline_v2_finalize as
select public.finalize_analysis_result_v2(
  s.user_id,
  s.analysis_id,
  s.active_msg_id,
  s.generation,
  (select (response->>'claim_token')::uuid from pipeline_v2_reclaim),
  '[]'::jsonb,
  jsonb_build_object(
    'status_message', 'test completed',
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
where s.analysis_id = '00000000-0000-4000-8000-000000000202'::uuid;

select is(
  (select response->>'state' from pipeline_v2_finalize),
  'completed',
  'claim owner finalizes atomically'
);
select is(
  (select status::text from public.analyses
   where id = '00000000-0000-4000-8000-000000000202'::uuid),
  'completed',
  'analysis reaches completed'
);
select set_config('app.analysis_checkpoint_refinalize_id', '', true);
select throws_ok(
  $$
    update public.analyses
    set status = 'failed'
    where id = '00000000-0000-4000-8000-000000000202'::uuid
  $$,
  '23514',
  'completed_analysis_status_is_terminal',
  'database rejects completed to failed regression'
);

select * from finish();
rollback;
