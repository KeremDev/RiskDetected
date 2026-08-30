begin;

select plan(6);

select ok(
  has_table_privilege('service_role', 'public.analyses', 'select, update'),
  'analysis Edge Functions can read and update analyses'
);

select ok(
  has_table_privilege('service_role', 'public.photos', 'select, insert, update, delete'),
  'analysis Edge Functions can manage photo metadata'
);

select ok(
  has_table_privilege('service_role', 'public.findings', 'select, insert, update, delete'),
  'analysis Edge Functions can manage findings'
);

select ok(
  has_table_privilege('service_role', 'public.profiles', 'select, update'),
  'server-side profile and subscription functions can read and update profiles'
);

select ok(
  not has_table_privilege('anon', 'public.analyses', 'select')
    and not has_table_privilege('anon', 'public.profiles', 'select'),
  'the repair does not expose core user data to anonymous callers'
);

select ok(
  not has_table_privilege('authenticated', 'public.analyses', 'update')
    and not has_table_privilege('authenticated', 'public.profiles', 'update'),
  'the repair preserves authenticated column-level write restrictions'
);

select * from finish();

rollback;
