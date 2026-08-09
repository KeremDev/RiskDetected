begin;

create extension if not exists pgtap with schema extensions;
select plan(4);

select has_column(
  'public',
  'analyses',
  'client_submission_id',
  'Android submission id is additive on analyses'
);

select col_is_null(
  'public',
  'analyses',
  'client_submission_id',
  'iOS and legacy rows are not required to send a submission id'
);

select has_index(
  'public',
  'analyses',
  'analyses_user_client_submission_unique',
  'Submission identity is indexed per owner'
);

select ok(
  has_column_privilege(
    'authenticated',
    'public.analyses',
    'client_submission_id',
    'INSERT'
  ),
  'Authenticated Android clients may insert their submission id'
);

select * from finish();
rollback;
