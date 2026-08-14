-- Align production function privileges with the local hardened migration chain.
-- These SECURITY DEFINER functions are admin/service-role internals and must not
-- be callable through the public Data API by anon or regular authenticated users.

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.admin_cohort_retention_matrix(integer, integer)',
    'public.admin_cohort_summary(integer)',
    'public.admin_dashboard_daily_series(integer)',
    'public.admin_data_quality_scan()',
    'public.admin_findings_analytics(integer)',
    'public.admin_pgmq_queue_messages(integer)',
    'public.admin_pgmq_queue_metrics()',
    'public.admin_recent_sign_ins(integer)',
    'public.admin_subscription_inconsistency_scan()',
    'public.admin_user_segments_list(text, integer, integer)',
    'public.admin_user_segments_summary()',
    'public.tg_recalc_finding_count()'
  ]
  loop
    if to_regprocedure(v_signature) is not null then
      execute format(
        'revoke all on function %s from public, anon, authenticated',
        v_signature
      );
      execute format('grant execute on function %s to service_role', v_signature);
    else
      raise notice 'Skipping function privilege hardening; % does not exist.',
        v_signature;
    end if;
  end loop;
end
$$;

select pg_notify('pgrst', 'reload schema');
