-- Live pilot bundle for supabase/migrations/20260922190000_analysis_list_summary_stats.sql:
-- lifetime analysis totals for the paged analysis list (Analizlerim summary counters).
--
-- Narrowed for the live project, which has no OSGB workspace layer
-- (no expert_workspace, expert_rpc or workspace_analyses):
-- - Only the personal branch: the signed-in owner's completed photo analyses,
--   optionally for one of their companies (require_company, unchanged).
-- - The workspace branch and the expert_rpc allowlist change are left out.
-- - The pilot gate is added: an account without pilot read access gets
--   ACCESS_DENIED, as the other live pilot reads do.
-- - Both functions are VOLATILE (the default): the pilot gate locks its rows
--   FOR SHARE, which a STABLE function cannot do under PostgREST.
-- Nothing existing is replaced; the old app never calls this function.
CREATE FUNCTION private_isg.analysis_list_stats(p_method text, p_company uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  actor uuid:=private_isg.active_actor();
  total_count integer:=0;
  critical_count integer:=0;
  finding_count bigint:=0;
BEGIN
  IF actor IS NULL OR p_method IS NOT NULL AND p_method NOT IN ('fk','m5') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  IF p_company IS NOT NULL THEN
    PERFORM private_isg.require_company(p_company,false);
  END IF;
  SELECT count(*)::integer,
    count(*) FILTER (WHERE CASE p_method
      WHEN 'fk' THEN a.highest_band_fk='critical'
      WHEN 'm5' THEN a.highest_band_m5='critical'
      ELSE a.highest_band_fk='critical' OR a.highest_band_m5='critical'
    END)::integer,
    coalesce(sum(a.finding_count),0)
  INTO total_count,critical_count,finding_count
  FROM public.analyses a
  WHERE a.user_id=actor AND a.status='completed' AND a.kind='photo'
    AND (p_company IS NULL OR a.company_id=p_company);

  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'workspace_id',NULL,
    'company_id',p_company,'method',p_method,'total',total_count,
    'critical',critical_count,'findings',finding_count);
END $$;
REVOKE ALL ON FUNCTION private_isg.analysis_list_stats(text,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.isg_analysis_list_stats_v1(p_method text DEFAULT NULL,p_company uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT private_isg.analysis_list_stats(p_method,p_company)
$$;
REVOKE ALL ON FUNCTION public.isg_analysis_list_stats_v1(text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.isg_analysis_list_stats_v1(text,uuid) TO authenticated;
