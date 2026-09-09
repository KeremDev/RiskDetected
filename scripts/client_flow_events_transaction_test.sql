-- Integration assertions, not pgTAP. Caller MUST wrap this in BEGIN / ROLLBACK.
-- Requires at least one existing auth user. No account/profile/quota is changed.
do $$ begin
  assert not has_table_privilege('anon', 'public.client_flow_events', 'select');
  assert not has_table_privilege('anon', 'public.client_flow_events', 'insert');
  assert not has_table_privilege('authenticated', 'public.client_flow_events', 'update');
  assert not has_table_privilege('authenticated', 'public.client_flow_events', 'delete');
  assert (select relrowsecurity from pg_class where oid = 'public.client_flow_events'::regclass);
end $$;
select set_config('request.jwt.claim.sub', (select id::text from auth.users order by created_at limit 1), true);
set local role authenticated;
do $$
declare event_id uuid := gen_random_uuid();
begin
  insert into public.client_flow_events(client_event_id,user_id,session_id,platform,app_version,app_build,stage,outcome,client_occurred_at)
    values(event_id,auth.uid(),gen_random_uuid(),'ios','test','0','photo_picker','started',now());
  insert into public.client_flow_events select * from public.client_flow_events where client_event_id=event_id
    on conflict(client_event_id) do nothing;
  assert (select count(*)=1 from public.client_flow_events where client_event_id=event_id), 'Retry must deduplicate';
  begin
    insert into public.client_flow_events(client_event_id,user_id,session_id,platform,app_version,app_build,stage,outcome,client_occurred_at)
      values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'ios','test','0','photo_picker','started',now());
    raise exception 'cross-owner insert accepted';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.client_flow_events(client_event_id,user_id,session_id,platform,app_version,app_build,stage,outcome,client_occurred_at)
      values(gen_random_uuid(),auth.uid(),gen_random_uuid(),'android','test','0','raw_private_content','failed',now());
    raise exception 'unlisted stage accepted';
  exception when check_violation then null; end;
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  assert (select count(*)=0 from public.client_flow_events where client_event_id=event_id), 'Cross-owner read';
end $$;
reset role;
