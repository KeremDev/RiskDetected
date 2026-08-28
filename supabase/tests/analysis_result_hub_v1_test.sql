begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(34);

select has_table('private', 'analysis_result_hub_allowlist', 'result hub allowlist exists');
select has_table('private', 'analysis_notebook_entries', 'notebook projections exist');
select has_table('private', 'analysis_notebook_entry_revisions', 'notebook revision ledger exists');
select has_table('private', 'analysis_item_feedback', 'item feedback ledger exists');
select has_table('private', 'analysis_result_events', 'result funnel events exist');
select has_table('private', 'report_export_intents', 'authoritative report intents exist');

select has_column('public', 'reports', 'content_scope', 'reports store section scope');
select has_column('public', 'reports', 'selected_item_keys', 'reports store selected item keys');
select has_column('public', 'reports', 'content_snapshot_json', 'reports freeze content snapshots');
select has_column('public', 'reports', 'export_intent_id', 'reports link to idempotent intents');

select ok(
  (select relrowsecurity from pg_class where oid = 'private.analysis_notebook_entries'::regclass),
  'notebook projections have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'private.analysis_item_feedback'::regclass),
  'feedback has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'private.analysis_result_events'::regclass),
  'events have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'private.report_export_intents'::regclass),
  'report intents have RLS enabled'
);

select ok(
  not has_table_privilege('authenticated', 'private.analysis_notebook_entries', 'select'),
  'authenticated clients cannot read notebook projections directly'
);
select ok(
  not has_table_privilege('authenticated', 'private.analysis_item_feedback', 'select'),
  'authenticated clients cannot read feedback directly'
);
select ok(
  not has_table_privilege('authenticated', 'private.analysis_result_events', 'select'),
  'authenticated clients cannot read funnel events directly'
);
select ok(
  not has_table_privilege('authenticated', 'private.report_export_intents', 'select'),
  'authenticated clients cannot read report intents directly'
);
select ok(
  has_table_privilege('service_role', 'private.analysis_notebook_entries', 'select'),
  'service role can project notebook entries'
);
select ok(
  has_table_privilege('service_role', 'private.report_export_intents', 'select'),
  'service role can validate report intents'
);

select has_function(
  'public', 'result_hub_create_report_intent',
  array['uuid','uuid','text','text','text[]','jsonb','integer','text','text','text'],
  'report intent RPC exists'
);
select has_function(
  'public', 'result_hub_consume_report_intent', array['uuid','uuid','text'],
  'report intent consumption RPC exists'
);
select has_function(
  'public', 'result_hub_upsert_feedback',
  array['uuid','uuid','text','text','uuid','uuid','text','text','integer','text','text','jsonb','jsonb'],
  'feedback RPC exists'
);
select has_function(
  'public', 'result_hub_insert_event',
  array['uuid','uuid','uuid','uuid','text','text','text','text','text','text','text','text','jsonb'],
  'idempotent event RPC exists'
);
select ok(
  position(
    'analysis_claim_candidates'
    in pg_get_functiondef('public.result_hub_v4_metadata(uuid,uuid)'::regprocedure)
  ) > 0,
  'notebook metadata includes the authoritative candidate asset and region'
);
select ok(
  (select p.prosecdef
   from pg_proc p
   where p.oid = 'public.result_hub_allowlist_decision(uuid)'::regprocedure),
  'result hub allowlist RPC uses definer rights for its private source table'
);
select is(
  (select count(*)::integer
   from pg_proc p
   where p.oid = any(array[
     'public.result_hub_v4_metadata(uuid,uuid)'::regprocedure,
     'public.result_hub_upsert_notebook_entries(uuid,uuid,text,text,text,jsonb)'::regprocedure,
     'public.result_hub_list_notebook_entries(uuid,uuid,text)'::regprocedure,
     'public.result_hub_feedback_for_analysis(uuid,uuid)'::regprocedure
   ]) and p.prosecdef),
  4,
  'service-only result hub RPCs can read their locked private source tables'
);
select has_function(
  'public', 'check_report_quota_eligibility_v2', array['uuid','text','text','text'],
  'section-aware report quota RPC exists'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.result_hub_create_report_intent(uuid,uuid,text,text,text[],jsonb,integer,text,text,text)',
    'execute'
  ),
  'clients cannot forge report intents through Data API'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.result_hub_create_report_intent(uuid,uuid,text,text,text[],jsonb,integer,text,text,text)',
    'execute'
  ),
  'result endpoint can create report intents'
);

select is(
  (select value->>'rollout_mode' from public.app_feature_flags where key = 'analysis_result_hub_v1'),
  'user_allowlist',
  'result hub remains isolated to the allowlist'
);
select is(
  (select value->>'required_capability' from public.app_feature_flags where key = 'analysis_result_hub_v1'),
  'analysis_result_hub_v1',
  'result hub requires the new client capability'
);
select ok(
  (select position('is_scored' in coalesce(qual, '')) > 0
   from pg_policies
   where schemaname = 'public' and tablename = 'findings' and policyname = 'findings_select_own'),
  'direct findings RLS distinguishes scored and scoreless rows'
);
select ok(
  (select position('result_hub_has_paid_access' in coalesce(qual, '')) > 0
   from pg_policies
   where schemaname = 'public' and tablename = 'findings' and policyname = 'findings_select_own'),
  'direct scoreless access uses server-side product entitlement'
);

select * from extensions.finish();
rollback;
