begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

select has_trigger(
  'public',
  'analyses',
  'analyses_authenticated_write_guard',
  'analysis authenticated write guard exists'
);
select has_trigger(
  'public',
  'photos',
  'photos_authenticated_write_guard',
  'photo authenticated write guard exists'
);
select has_trigger(
  'public',
  'profiles',
  'profiles_authenticated_insert_guard',
  'profile authenticated insert guard exists'
);
select has_function(
  'public',
  'apply_finding_mutation_atomic',
  array[
    'text',
    'uuid',
    'uuid',
    'uuid',
    'integer',
    'jsonb',
    'text[]',
    'text',
    'text',
    'text'
  ],
  'atomic finding mutation function exists'
);
select ok(
  position(
    'auth.role()'
    in pg_get_functiondef(
      'public.apply_finding_mutation_atomic(text,uuid,uuid,uuid,integer,jsonb,text[],text,text,text)'
        ::regprocedure
    )
  ) = 0,
  'atomic finding mutation avoids deprecated auth.role'
);
select ok(
  position(
    'request.jwt.claims'
    in pg_get_functiondef(
      'public.apply_finding_mutation_atomic(text,uuid,uuid,uuid,integer,jsonb,text[],text,text,text)'
        ::regprocedure
    )
  ) > 0,
  'atomic finding mutation validates PostgREST JWT request context'
);

select ok(
  not has_table_privilege('anon', 'public.analyses', 'select'),
  'anon has no analysis table privileges'
);
select ok(
  not has_table_privilege('anon', 'public.photos', 'select'),
  'anon has no photo table privileges'
);
select ok(
  not has_table_privilege('anon', 'public.profiles', 'select'),
  'anon has no profile table privileges'
);

select ok(
  not has_table_privilege('authenticated', 'public.analyses', 'update'),
  'authenticated has no broad analysis update privilege'
);
select ok(
  has_column_privilege(
    'authenticated',
    'public.analyses',
    'company_id',
    'update'
  ),
  'authenticated can update the client-owned analysis company'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.analyses',
    'ai_summary',
    'update'
  ),
  'authenticated cannot update server analysis summary'
);
select ok(
  not has_table_privilege('authenticated', 'public.photos', 'update'),
  'authenticated has no broad photo update privilege'
);
select ok(
  has_column_privilege(
    'authenticated',
    'public.photos',
    'user_caption',
    'update'
  ),
  'authenticated can update the client-owned photo caption'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.photos',
    'retention_expires_at',
    'update'
  ),
  'authenticated cannot update photo retention'
);
select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'update'),
  'authenticated has no broad profile update privilege'
);
select ok(
  has_column_privilege(
    'authenticated',
    'public.profiles',
    'full_name',
    'update'
  ),
  'authenticated can update profile identity copy'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'tier',
    'update'
  ),
  'authenticated cannot update subscription tier'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000001701'::uuid,
  'authority-test@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  '00000000-0000-4000-8000-000000001701';
set local "request.jwt.claim.role" = 'authenticated';

select lives_ok(
  $$
    update public.profiles
    set full_name = 'Authority Test'
    where id = '00000000-0000-4000-8000-000000001701'::uuid
  $$,
  'shipping profile field update remains compatible'
);
select throws_ok(
  $$
    update public.profiles
    set tier = 'pro'
    where id = '00000000-0000-4000-8000-000000001701'::uuid
  $$,
  '42501',
  'permission denied for table profiles',
  'profile tier forgery is rejected'
);
select lives_ok(
  $$
    insert into public.analyses (
      id,
      user_id,
      title,
      kind,
      canvas,
      text_input,
      status,
      primary_method,
      analysis_sector,
      analysis_sector_source,
      analysis_sector_prompt_version
    ) values (
      '00000000-0000-4000-8000-000000001702'::uuid,
      '00000000-0000-4000-8000-000000001701'::uuid,
      'Authority Test Analysis',
      'photo',
      'general',
      null,
      'pending',
      'fine_kinney',
      'construction',
      'user_selected',
      'active-v1'
    )
  $$,
  'shipping analysis insert payload remains compatible'
);
select lives_ok(
  $$
    update public.analyses
    set status = 'failed',
        status_message = 'client submission failed'
    where id = '00000000-0000-4000-8000-000000001702'::uuid
      and status = 'pending'
  $$,
  'shipping pending-to-failed cleanup remains compatible'
);
select lives_ok(
  $$
    insert into public.photos (
      analysis_id,
      user_id,
      storage_path,
      width,
      height,
      size_bytes,
      byte_size,
      mime_type,
      sequence_index,
      client_photo_id,
      is_primary,
      upload_payload_version,
      compression_metadata
    ) values (
      '00000000-0000-4000-8000-000000001702'::uuid,
      '00000000-0000-4000-8000-000000001701'::uuid,
      '00000000-0000-4000-8000-000000001701/00000000-0000-4000-8000-000000001702/p1.jpg',
      1200,
      1600,
      1000,
      1000,
      'image/jpeg',
      1,
      'client-photo-1',
      true,
      'photo-batch-storage-v1',
      '{"quality_policy":"test"}'::jsonb
    )
  $$,
  'shipping photo insert payload remains compatible'
);
select throws_ok(
  $$
    insert into public.photos (
      analysis_id,
      user_id,
      storage_path,
      mime_type,
      sequence_index
    ) values (
      '00000000-0000-4000-8000-000000001702'::uuid,
      '00000000-0000-4000-8000-000000001701'::uuid,
      '00000000-0000-4000-8000-000000009999/00000000-0000-4000-8000-000000001702/victim.jpg',
      'image/jpeg',
      2
    )
  $$,
  '42501',
  'photo_storage_path_owner_mismatch',
  'cross-owner photo storage path is rejected'
);

reset role;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claim.role" = '';

delete from public.profiles
where id = '00000000-0000-4000-8000-000000001701'::uuid;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '00000000-0000-4000-8000-000000001701';
set local "request.jwt.claim.role" = 'authenticated';

select lives_ok(
  $$
    insert into public.profiles (id, email, full_name, initials, tier)
    values (
      '00000000-0000-4000-8000-000000001701'::uuid,
      'authority-test@example.invalid',
      'Authority Test',
      'AT',
      'pro'
    )
  $$,
  'legacy profile bootstrap remains compatible'
);

reset role;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claim.role" = '';

select is(
  (
    select tier::text
    from public.profiles
    where id = '00000000-0000-4000-8000-000000001701'::uuid
  ),
  'free',
  'authenticated profile bootstrap cannot forge tier'
);

insert into public.analyses (
  id,
  user_id,
  title,
  kind,
  canvas,
  status
) values (
  '00000000-0000-4000-8000-000000001703'::uuid,
  '00000000-0000-4000-8000-000000001701'::uuid,
  'Atomic Finding Test',
  'photo',
  'general',
  'completed'
);

insert into public.findings (
  id,
  analysis_id,
  user_id,
  ordinal,
  title,
  description,
  recommended_action,
  fk_probability,
  fk_frequency,
  fk_severity,
  fk_band,
  m5_probability,
  m5_severity,
  m5_band
) values (
  '00000000-0000-4000-8000-000000001704'::uuid,
  '00000000-0000-4000-8000-000000001703'::uuid,
  '00000000-0000-4000-8000-000000001701'::uuid,
  1,
  'Before',
  'Before description',
  'Before action',
  1,
  1,
  3,
  'low',
  1,
  1,
  'low'
);

set local role service_role;
set local "request.jwt.claim.role" = 'service_role';

select lives_ok(
  $$
    select public.apply_finding_mutation_atomic(
      'update',
      '00000000-0000-4000-8000-000000001703'::uuid,
      '00000000-0000-4000-8000-000000001704'::uuid,
      '00000000-0000-4000-8000-000000001701'::uuid,
      1,
      '{"title":"After"}'::jsonb,
      array['title']::text[],
      '1.3.0',
      'request-atomic-test',
      'support-atomic-test'
    )
  $$,
  'atomic finding update succeeds with the current version'
);

reset role;
set local "request.jwt.claim.role" = '';

select is(
  (
    select title
    from public.findings
    where id = '00000000-0000-4000-8000-000000001704'::uuid
  ),
  'After',
  'atomic mutation updates the finding'
);
select is(
  (
    select finding_version
    from public.findings
    where id = '00000000-0000-4000-8000-000000001704'::uuid
  ),
  2,
  'atomic mutation increments the finding version'
);
select is(
  (
    select count(*)::integer
    from public.finding_edit_events
    where finding_id = '00000000-0000-4000-8000-000000001704'::uuid
  ),
  1,
  'atomic mutation writes one matching audit event'
);

set local role service_role;
set local "request.jwt.claim.role" = 'service_role';

select throws_ok(
  $$
    select public.apply_finding_mutation_atomic(
      'update',
      '00000000-0000-4000-8000-000000001703'::uuid,
      '00000000-0000-4000-8000-000000001704'::uuid,
      '00000000-0000-4000-8000-000000001701'::uuid,
      1,
      '{"title":"Stale"}'::jsonb,
      array['title']::text[],
      '1.3.0',
      'request-stale-test',
      'support-stale-test'
    )
  $$,
  '40001',
  'finding_version_conflict',
  'stale finding mutation is rejected'
);

reset role;

select * from finish();

rollback;
