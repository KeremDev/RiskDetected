begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(14);

select extensions.has_table(
  'private', 'report_activity_events',
  'report activity ledger exists'
);
select extensions.ok(
  (select relrowsecurity
   from pg_class
   where oid = 'private.report_activity_events'::regclass),
  'report activity ledger has RLS enabled'
);
select extensions.ok(
  not has_table_privilege(
    'authenticated', 'private.report_activity_events', 'select'
  ),
  'authenticated users cannot read the private ledger directly'
);
select extensions.ok(
  not has_table_privilege(
    'authenticated', 'private.report_activity_events', 'insert'
  ),
  'authenticated users cannot forge ledger rows directly'
);
select extensions.ok(
  has_table_privilege(
    'service_role', 'private.report_activity_events', 'select'
  ),
  'service role can read report activity'
);
select extensions.has_function(
  'public', 'record_report_activity_event_v1',
  array['uuid','text','uuid','text','text','text','text','text','text','jsonb'],
  'authenticated download event RPC exists'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.record_report_activity_event_v1(uuid,text,uuid,text,text,text,text,text,text,jsonb)',
    'execute'
  ),
  'authenticated clients can record owned report downloads'
);
select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.record_report_activity_event_v1(uuid,text,uuid,text,text,text,text,text,text,jsonb)',
    'execute'
  ),
  'anonymous clients cannot record report activity'
);
select extensions.ok(
  (select prosecdef
   from pg_proc
   where oid = 'public.record_report_activity_event_v1(uuid,text,uuid,text,text,text,text,text,text,jsonb)'::regprocedure),
  'download RPC uses definer rights for the private ledger'
);
select extensions.ok(
  position(
    'r.user_id = v_user_id'
    in pg_get_functiondef(
      'public.record_report_activity_event_v1(uuid,text,uuid,text,text,text,text,text,text,jsonb)'::regprocedure
    )
  ) > 0,
  'download RPC enforces report ownership'
);
select extensions.has_function(
  'public', 'admin_report_activity_v1',
  array['integer','integer','integer','uuid','text','text'],
  'admin report activity query exists'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_report_activity_v1(integer,integer,integer,uuid,text,text)',
    'execute'
  ),
  'authenticated users cannot access admin report analytics'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.admin_report_activity_v1(integer,integer,integer,uuid,text,text)',
    'execute'
  ),
  'service role can query admin report analytics'
);
select extensions.ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.reports'::regclass
      and tgname = 'reports_capture_activity_created_v1'
      and not tgisinternal
  ),
  'successful report inserts are captured server-side'
);

select * from extensions.finish();
rollback;
