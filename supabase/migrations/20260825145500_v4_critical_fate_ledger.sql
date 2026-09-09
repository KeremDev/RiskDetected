-- Same-event-path dedup keeps one public card and one routing-ledger row per
-- candidate. An explainable ledger route is therefore a valid critical fate.
do $$
declare
  v_oid regprocedure := 'public.finalize_analysis_result_v4(uuid,uuid,bigint,integer,uuid,uuid,jsonb)'::regprocedure;
  v_definition text;
  v_before text := $needle$
    and not exists (
      select 1 from jsonb_array_elements(coalesce(p_bundle->'hard_rejections','[]'::jsonb)) h
      where h->>'candidate_id'=c->>'id' and nullif(h->>'reason_code','') is not null
    );$needle$;
  v_after text := $replacement$
    and not exists (
      select 1 from jsonb_array_elements(coalesce(p_bundle->'hard_rejections','[]'::jsonb)) h
      where h->>'candidate_id'=c->>'id' and nullif(h->>'reason_code','') is not null
    )
    and not exists (
      select 1 from jsonb_array_elements(coalesce(p_bundle->'routing_ledger','[]'::jsonb)) l
      where l->>'candidate_id'=c->>'id'
        and l->>'to_state' in (
          'observed_finding','assurance_requirement','verification_request',
          'positive_control','not_assessable','hard_reject'
        )
        and nullif(l->>'reason_code','') is not null
    );$replacement$;
begin
  select pg_get_functiondef(v_oid) into v_definition;
  if position(v_after in v_definition) > 0 then return; end if;
  if position(v_before in v_definition) = 0 then
    raise exception 'finalize_analysis_result_v4 critical fate block changed unexpectedly';
  end if;
  execute replace(v_definition,v_before,v_after);
end $$;

revoke all on function public.finalize_analysis_result_v4(
  uuid,uuid,bigint,integer,uuid,uuid,jsonb
) from public,anon,authenticated;
grant execute on function public.finalize_analysis_result_v4(
  uuid,uuid,bigint,integer,uuid,uuid,jsonb
) to service_role;
