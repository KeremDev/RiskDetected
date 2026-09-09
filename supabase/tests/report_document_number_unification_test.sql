begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(6);

select extensions.has_function(
  'public',
  'next_document_no',
  array['uuid'],
  'legacy report document number function exists'
);
select extensions.has_function(
  'public',
  'next_report_document_no_v2',
  array['uuid', 'text'],
  'section report document number function exists'
);
select extensions.ok(
  position(
    'return public.next_document_no(p_user_id)'
    in lower(pg_get_functiondef(
      'public.next_report_document_no_v2(uuid,text)'::regprocedure
    ))
  ) > 0,
  'risk-analysis reports share the legacy RD-RA counter'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.next_report_document_no_v2(uuid,text)',
    'execute'
  ),
  'authenticated clients cannot reserve report document numbers'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.next_report_document_no_v2(uuid,text)',
    'execute'
  ),
  'service role can reserve report document numbers'
);
select extensions.ok(
  position(
    'counters.last_no + 1'
    in lower(pg_get_functiondef('public.next_document_no(uuid)'::regprocedure))
  ) > 0,
  'the shared RD-RA counter increments atomically'
);

select * from extensions.finish();
rollback;
