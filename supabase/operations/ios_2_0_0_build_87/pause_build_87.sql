-- Client-incident brake. Build 87 will fail closed; it will not use V3/legacy.
begin;

update public.app_feature_flags
set value = jsonb_set(value, '{kill_switch}', 'true'::jsonb, true),
    updated_at = now()
where key in ('analysis_engine_v4', 'analysis_result_hub_v1');

do $verification$
begin
  if exists (
    select 1
    from public.app_feature_flags
    where key in ('analysis_engine_v4', 'analysis_result_hub_v1')
      and coalesce(value->>'kill_switch', 'false') <> 'true'
  ) then
    raise exception 'build 87 pause did not close every release gate';
  end if;
end
$verification$;

commit;
