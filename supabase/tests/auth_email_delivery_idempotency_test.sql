begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(17);

select has_table(
  'private',
  'auth_email_delivery_attempts',
  '1 durable auth-email delivery ledger exists'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'private.auth_email_delivery_attempts'::regclass
  ),
  '2 delivery ledger has RLS'
);
select ok(
  not has_table_privilege(
    'anon',
    'private.auth_email_delivery_attempts',
    'select'
  ),
  '3 anon cannot read the delivery ledger'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'private.auth_email_delivery_attempts',
    'select'
  ),
  '4 authenticated cannot read the delivery ledger'
);
select ok(
  to_regprocedure(
    'public.claim_auth_email_delivery_v1(text,integer,text)'
  ) is not null,
  '5 atomic claim function exists'
);
select ok(
  to_regprocedure(
    'public.complete_auth_email_delivery_v1(text,integer,text,uuid,text)'
  ) is not null,
  '6 completion function exists'
);
select ok(
  to_regprocedure(
    'public.release_auth_email_delivery_v1(text,integer,text,uuid)'
  ) is not null,
  '7 retry release function exists'
);

create temporary table first_claim as
select public.claim_auth_email_delivery_v1(
  repeat('a', 64),
  0,
  repeat('b', 64)
) as response;

select ok(
  (
    select response ->> 'status' = 'claimed'
      and (response ->> 'claimed')::boolean
      and response ->> 'lease_token' is not null
    from first_claim
  ),
  '8 first delivery obtains the lease'
);
select is(
  (
    public.claim_auth_email_delivery_v1(
      repeat('a', 64),
      0,
      repeat('b', 64)
    ) ->> 'status'
  ),
  'processing',
  '9 concurrent duplicate cannot send'
);
select throws_ok(
  $$
    select public.claim_auth_email_delivery_v1(
      repeat('a', 64),
      0,
      repeat('c', 64)
    )
  $$,
  '22023',
  'AUTH_EMAIL_WEBHOOK_BODY_MISMATCH',
  '10 the same signed event cannot change bodies'
);
select is(
  public.complete_auth_email_delivery_v1(
    repeat('a', 64),
    0,
    repeat('b', 64),
    '00000000-0000-4000-8000-000000000001'::uuid,
    'provider-id'
  ),
  false,
  '11 a wrong lease token cannot complete delivery'
);
select is(
  public.complete_auth_email_delivery_v1(
    repeat('a', 64),
    0,
    repeat('b', 64),
    (select (response ->> 'lease_token')::uuid from first_claim),
    'provider-id'
  ),
  true,
  '12 the active lease marks delivery sent'
);
select is(
  (
    public.claim_auth_email_delivery_v1(
      repeat('a', 64),
      0,
      repeat('b', 64)
    ) ->> 'status'
  ),
  'sent',
  '13 a completed duplicate is skipped permanently'
);

create temporary table retry_claim as
select public.claim_auth_email_delivery_v1(
  repeat('a', 64),
  1,
  repeat('b', 64)
) as response;

select is(
  public.release_auth_email_delivery_v1(
    repeat('a', 64),
    1,
    repeat('b', 64),
    (select (response ->> 'lease_token')::uuid from retry_claim)
  ),
  true,
  '14 failed delivery releases its lease'
);
select ok(
  (
    select response ->> 'status' = 'claimed'
      and (response ->> 'attempt_count')::integer = 2
    from (
      select public.claim_auth_email_delivery_v1(
        repeat('a', 64),
        1,
        repeat('b', 64)
      ) as response
    ) retried
  ),
  '15 a released delivery is safely reclaimable'
);
select throws_ok(
  $$
    select public.claim_auth_email_delivery_v1('invalid', 0, repeat('b', 64))
  $$,
  '22023',
  'AUTH_EMAIL_IDEMPOTENCY_INPUT_INVALID',
  '16 malformed idempotency material fails closed'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.claim_auth_email_delivery_v1(text,integer,text)',
    'execute'
  ),
  '17 only the service role can claim a delivery'
);

select * from extensions.finish();
rollback;
