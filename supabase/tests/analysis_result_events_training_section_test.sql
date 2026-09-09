begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(4);

select ok(
  position(
    'training_recommendations' in (
      select pg_get_constraintdef(oid)
      from pg_constraint
      where conrelid = 'private.analysis_result_events'::regclass
        and conname = 'analysis_result_events_section_check'
    )
  ) > 0,
  'result event ledger accepts the training section'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000891',
  'result-event-training@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.analyses (
  id,
  user_id,
  kind,
  status,
  photo_count,
  plan_at_creation
)
values (
  '00000000-0000-4000-8000-000000000892',
  '00000000-0000-4000-8000-000000000891',
  'photo',
  'pending',
  1,
  'free'
);

select is(
  public.result_hub_insert_event(
    '00000000-0000-4000-8000-000000000891',
    '00000000-0000-4000-8000-000000000892',
    '00000000-0000-4000-8000-000000000893',
    '00000000-0000-4000-8000-000000000894',
    'result_section_selected',
    'training_recommendations',
    null,
    null,
    'free',
    'ios',
    '2.0.0',
    '88',
    '{}'::jsonb
  ),
  true,
  'iOS build 88 can persist a training-section event'
);

select is(
  (
    select section
    from private.analysis_result_events
    where user_id = '00000000-0000-4000-8000-000000000891'
      and client_event_id = '00000000-0000-4000-8000-000000000893'
  ),
  'training_recommendations',
  'training section is stored without rewriting the event payload'
);

select is(
  public.result_hub_insert_event(
    '00000000-0000-4000-8000-000000000891',
    '00000000-0000-4000-8000-000000000892',
    '00000000-0000-4000-8000-000000000893',
    '00000000-0000-4000-8000-000000000894',
    'result_section_selected',
    'training_recommendations',
    null,
    null,
    'free',
    'android',
    '2.0.0',
    '9',
    '{}'::jsonb
  ),
  false,
  'event idempotency remains intact across mobile retries'
);

select * from extensions.finish();
rollback;
