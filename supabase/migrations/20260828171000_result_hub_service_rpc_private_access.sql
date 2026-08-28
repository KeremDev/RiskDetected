-- All result-hub RPCs below are service-role-only and access tables in the
-- locked private schema. Invoker rights therefore make every load/mutation fail
-- with 42501 even though the table privileges themselves are intentionally
-- granted only to service_role. Execute them with their postgres owner's rights
-- while retaining the existing empty search_path and explicit argument checks.
alter function public.result_hub_v4_metadata(uuid, uuid) security definer;
alter function public.result_hub_upsert_notebook_entries(uuid, uuid, text, text, text, jsonb) security definer;
alter function public.result_hub_list_notebook_entries(uuid, uuid, text) security definer;
alter function public.result_hub_mutate_notebook_entry(uuid, uuid, uuid, text, text, text, text) security definer;
alter function public.result_hub_upsert_feedback(uuid, uuid, text, text, uuid, uuid, text, text, integer, text, text, jsonb, jsonb) security definer;
alter function public.result_hub_feedback_for_analysis(uuid, uuid) security definer;
alter function public.result_hub_insert_event(uuid, uuid, uuid, uuid, text, text, text, text, text, text, text, text, jsonb) security definer;
alter function public.result_hub_create_report_intent(uuid, uuid, text, text, text[], jsonb, integer, text, text, text) security definer;
alter function public.result_hub_get_report_intent(uuid, uuid) security definer;
alter function public.result_hub_consume_report_intent(uuid, uuid, text) security definer;
alter function public.admin_analysis_feedback_v1(integer, integer, integer, text, integer) security definer;
alter function public.admin_analysis_result_funnel_v1(integer) security definer;

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.result_hub_v4_metadata(uuid,uuid)',
    'public.result_hub_upsert_notebook_entries(uuid,uuid,text,text,text,jsonb)',
    'public.result_hub_list_notebook_entries(uuid,uuid,text)',
    'public.result_hub_mutate_notebook_entry(uuid,uuid,uuid,text,text,text,text)',
    'public.result_hub_upsert_feedback(uuid,uuid,text,text,uuid,uuid,text,text,integer,text,text,jsonb,jsonb)',
    'public.result_hub_feedback_for_analysis(uuid,uuid)',
    'public.result_hub_insert_event(uuid,uuid,uuid,uuid,text,text,text,text,text,text,text,text,jsonb)',
    'public.result_hub_create_report_intent(uuid,uuid,text,text,text[],jsonb,integer,text,text,text)',
    'public.result_hub_get_report_intent(uuid,uuid)',
    'public.result_hub_consume_report_intent(uuid,uuid,text)',
    'public.admin_analysis_feedback_v1(integer,integer,integer,text,integer)',
    'public.admin_analysis_result_funnel_v1(integer)'
  ] loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_signature
    );
    execute format('grant execute on function %s to service_role', v_signature);
  end loop;

  if exists (
    select 1
    from unnest(array[
      'public.result_hub_v4_metadata(uuid,uuid)',
      'public.result_hub_upsert_notebook_entries(uuid,uuid,text,text,text,jsonb)',
      'public.result_hub_list_notebook_entries(uuid,uuid,text)',
      'public.result_hub_feedback_for_analysis(uuid,uuid)'
    ]) signature
    where not (
      select p.prosecdef
      from pg_proc p
      where p.oid = signature::regprocedure
    )
  ) then
    raise exception 'result hub private-access RPC must be security definer';
  end if;
end;
$$;

select pg_notify('pgrst', 'reload schema');
