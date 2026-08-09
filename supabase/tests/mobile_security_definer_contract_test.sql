-- Cross-cutting contract for the five SECURITY DEFINER RPCs callable by mobile users.
-- Behavioral ownership/input-negative cases live in first_seen_device_region_test.sql,
-- notification_automation_test.sql and global_localization_delivery_test.sql; this test seals
-- the shared privilege/auth.uid/search_path invariants so a future replacement cannot weaken one.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(25);

create temporary table mobile_definer_functions(name text primary key) on commit drop;
insert into mobile_definer_functions(name) values
  ('acknowledge_legal_document_v1'),
  ('record_first_seen_device_region_v1'),
  ('record_notification_open_v1'),
  ('record_user_engagement_state_v1'),
  ('set_notification_master_preference_v1');

select extensions.ok(
  p.prosecdef,
  f.name || ' remains SECURITY DEFINER'
)
from mobile_definer_functions f
join pg_proc p on p.proname = f.name
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public';

select extensions.ok(
  coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""'],
  f.name || ' pins an empty search_path'
)
from mobile_definer_functions f
join pg_proc p on p.proname = f.name
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public';

select extensions.ok(
  position('auth.uid()' in pg_get_functiondef(p.oid)) > 0,
  f.name || ' derives ownership from auth.uid()'
)
from mobile_definer_functions f
join pg_proc p on p.proname = f.name
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public';

select extensions.ok(
  has_function_privilege('authenticated', p.oid, 'EXECUTE'),
  f.name || ' is executable by authenticated users'
)
from mobile_definer_functions f
join pg_proc p on p.proname = f.name
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public';

select extensions.ok(
  not has_function_privilege('anon', p.oid, 'EXECUTE'),
  f.name || ' rejects anonymous execution'
)
from mobile_definer_functions f
join pg_proc p on p.proname = f.name
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public';

select * from extensions.finish();
rollback;
