-- Covers E8 (20260806224500 + 20260810152500): additive columns accept ios/android/null and
-- server-owned platform telemetry is derived from the audited analysis result.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(10);

select has_column('public', 'analyses', 'client_platform', 'analyses.client_platform exists');
select has_column('public', 'ai_usage_logs', 'client_platform', 'ai_usage_logs.client_platform exists');

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000901'::uuid,
  'client-platform-test@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

select lives_ok(
  $$
    insert into public.analyses (id, user_id, status, kind, client_platform)
    values (
      '00000000-0000-4000-8000-000000000902'::uuid,
      '00000000-0000-4000-8000-000000000901'::uuid,
      'pending', 'photo',
      'android'
    )
  $$,
  'analyses row with client_platform=android is insertable'
);

select lives_ok(
  $$
    insert into public.analyses (id, user_id, status, kind, client_platform)
    values (
      '00000000-0000-4000-8000-000000000903'::uuid,
      '00000000-0000-4000-8000-000000000901'::uuid,
      'pending', 'photo',
      null
    )
  $$,
  'analyses row with client_platform=null is insertable (predates-this-column case)'
);

select throws_ok(
  $$
    insert into public.analyses (id, user_id, status, kind, client_platform)
    values (
      '00000000-0000-4000-8000-000000000904'::uuid,
      '00000000-0000-4000-8000-000000000901'::uuid,
      'pending', 'photo',
      'web'
    )
  $$,
  '23514', null,
  'an unknown client_platform value is rejected'
);

select throws_ok(
  $$
    insert into public.ai_usage_logs (analysis_id, user_id, model, client_platform)
    values (
      '00000000-0000-4000-8000-000000000902'::uuid,
      '00000000-0000-4000-8000-000000000901'::uuid,
      'test-model',
      'web'
    )
  $$,
  '23514', null,
  'ai_usage_logs.client_platform rejects the same unknown value'
);

select lives_ok(
  $$
    update public.analyses
    set raw_ai_response = jsonb_build_object(
      '_input_audit',
      jsonb_build_object('client_platform', 'android', 'client_build', '1')
    )
    where id = '00000000-0000-4000-8000-000000000903'::uuid
  $$,
  'audited Android result can be synchronized'
);

select is(
  (
    select client_platform
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000903'::uuid
  ),
  'android',
  'analysis platform is derived from raw input audit'
);

select is(
  (
    select client_build
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000903'::uuid
  ),
  '1',
  'analysis build continues to be derived from the same audit'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.tg_sync_analysis_localization_telemetry()',
    'execute'
  ),
  'authenticated cannot execute the trigger function directly'
);

select * from finish();
rollback;
