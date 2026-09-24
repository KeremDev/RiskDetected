-- Small, lifetime analysis totals for the paged analysis list. Row access is
-- scoped to the signed-in owner or the selected OSGB workspace; no list rows
-- are expanded just to paint the overview counters.
CREATE FUNCTION private_isg.analysis_list_stats(p_method text, p_company uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  actor uuid:=private_isg.active_actor();
  workspace uuid:=private_isg.expert_workspace();
  total_count integer:=0;
  critical_count integer:=0;
  finding_count bigint:=0;
BEGIN
  IF actor IS NULL OR p_method IS NOT NULL AND p_method NOT IN ('fk','m5') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;

  IF workspace IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(workspace,ARRAY['owner','admin','expert'],false);
    PERFORM private_isg.workspace_domain_gate('analysis_exports',false);
    IF p_company IS NOT NULL THEN
      PERFORM private_isg.workspace_require_company(workspace,p_company,false);
    END IF;

    WITH scoped AS (
      SELECT a.id,
        count(f.analysis_id)::integer AS findings,
        coalesce(bool_or(f.is_scored AND CASE p_method
          WHEN 'fk' THEN f.fk_band='critical'
          WHEN 'm5' THEN f.m5_band='critical'
          ELSE f.fk_band='critical' OR f.m5_band='critical'
        END),false) AS critical
      FROM private_isg.workspace_analyses a
      JOIN public.companies c ON c.id=a.company_id
      LEFT JOIN private_isg.workspace_analysis_findings f ON f.analysis_id=a.id
      WHERE a.workspace_id=workspace AND a.status='ready'
        AND (p_company IS NULL OR a.company_id=p_company)
        AND private_isg.expert_company_visible(c.user_id,c.id,actor)
      GROUP BY a.id
    )
    SELECT count(*)::integer,
      count(*) FILTER (WHERE critical)::integer,
      coalesce(sum(findings),0)
    INTO total_count,critical_count,finding_count
    FROM scoped;
  ELSE
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
  END IF;

  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'workspace_id',workspace,
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

-- Add the read-only aggregate to the existing, workspace-validated RPC allowlist.
CREATE OR REPLACE FUNCTION private_isg.expert_rpc(p_workspace uuid,p_function text,p_arguments jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); previous text:=current_setting('private_isg.expert_workspace',true);
 result jsonb; target oid; declarations text; arguments text; names text[]; required_count integer;
 company uuid; can_write boolean:=false; row_ public.companies;
 original_mutation uuid:=(p_arguments->>'p_mutation')::uuid; original_certificate_mutation uuid:=(p_arguments#>>'{p_payload,mutation_id}')::uuid;
BEGIN
 IF p_workspace IS NULL OR p_function IS NULL OR jsonb_typeof(p_arguments) IS DISTINCT FROM 'object'
  OR octet_length(p_arguments::text)>4194304 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 PERFORM private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
 IF NOT EXISTS(SELECT 1 FROM private_isg.workspaces WHERE id=p_workspace AND kind='osgb') THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 PERFORM set_config('private_isg.expert_workspace',p_workspace::text,true);
 company:=(p_arguments->>'p_company')::uuid;
 IF original_mutation IS NOT NULL THEN
  p_arguments:=p_arguments||jsonb_build_object('p_mutation',md5(p_workspace::text||':'||original_mutation::text)::uuid);
 END IF;
 IF original_certificate_mutation IS NOT NULL THEN
  p_arguments:=jsonb_set(p_arguments,'{p_payload,mutation_id}',to_jsonb(md5(p_workspace::text||':'||original_certificate_mutation::text)::uuid));
 END IF;
 IF p_function='isg_workspace_availability_v1' THEN
  IF company IS NOT NULL THEN
   PERFORM private_isg.workspace_require_company(p_workspace,company,false);
   SELECT * INTO STRICT row_ FROM public.companies WHERE id=company AND workspace_id=p_workspace;
   BEGIN
    PERFORM private_isg.workspace_require_company(p_workspace,company,true);
    can_write:=NOT row_.is_archived;
   EXCEPTION WHEN SQLSTATE 'P0001' THEN can_write:=false;
   END;
  END IF;
  result:=jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',company,
   'company_name',row_.name,'is_archived',row_.is_archived,'can_read',true,'can_write',can_write);
 ELSIF p_function='isg_expert_file_inspection_access_v1' THEN
  SELECT e.company_id INTO company FROM private_isg.file_library_entries e
   WHERE e.entry_id=(p_arguments->>'entry_id')::uuid AND e.workspace_id=p_workspace;
  IF company IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  PERFORM private_isg.workspace_require_company(p_workspace,company,true);
  result:=public.isg_file_library_read_v1(company,'detail',NULL,NULL,NULL,(p_arguments->>'entry_id')::uuid,NULL,NULL);
 ELSIF p_function='isg_expert_analysis_v1' THEN
  result:=private_isg.expert_analysis(p_arguments->>'p_action',coalesce(p_arguments->'p_payload','{}'::jsonb));
 ELSIF p_function='isg_expert_companies_v1' THEN
  SELECT jsonb_build_object('rows',coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('user_id',actor) ORDER BY c.name,c.id),'[]'::jsonb))
  INTO result FROM public.companies c WHERE c.workspace_id=p_workspace
   AND (coalesce((p_arguments->>'p_archived')::boolean,false) OR NOT c.is_archived)
   AND private_isg.expert_company_visible(c.user_id,c.id,actor);
 ELSE
  IF NOT p_function=ANY(ARRAY['isg_analysis_list_stats_v1','isg_pilot_notice_mark_v1','isg_pilot_file_library_mutate_v2','isg_appointments_mutate_v1','isg_checklists_mutate_v1','isg_directory_mutate_v1','isg_document_tracking_mutate_v1','isg_drills_mutate_v1','isg_emergency_plans_mutate_v1','isg_equipment_checks_mutate_v1','isg_nonconformity_mutate_v1','isg_personnel_mutate_v1','isg_pilot_module_mutate_v1','isg_pilot_process_mutate_v1','isg_pilot_training_certificate_v1','isg_pilot_training_record_v2','isg_pilot_training_record_v3','isg_ppe_mutate_v1','isg_risk_versions_mutate_v1','isg_appointments_read_v1','isg_checklists_read_v1','isg_directory_read_v1','isg_document_portfolio_v1','isg_document_tracking_read_v1','isg_drills_read_v1','isg_emergency_plans_read_v1','isg_equipment_checks_read_v1','isg_file_library_read_v1','isg_nonconformity_read_v1','isg_personnel_read_v1','isg_pilot_employee_learning_v1','isg_pilot_file_library_read_v2','isg_pilot_file_sources_v1','isg_pilot_followup_v1','isg_pilot_module_editor_v1','isg_pilot_module_tracking_v1','isg_pilot_module_tracking_v2','isg_pilot_notice_feed_v1','isg_pilot_overview_v1','isg_pilot_overview_v2','isg_pilot_process_attachment_v1','isg_pilot_process_documents_v1','isg_pilot_process_read_v1','isg_pilot_process_references_v1','isg_pilot_training_detail_v3','isg_pilot_training_read_v1','isg_pilot_training_sessions_v2','isg_pilot_training_sessions_v3','isg_pilot_visit_summary_v1','isg_ppe_form_v1','isg_ppe_read_v1','isg_risk_versions_read_v1','isg_statistics_v1']) THEN
   RAISE EXCEPTION 'EXPERT_OPERATION_NOT_READY';
  END IF;
  SELECT p.oid,p.proargnames,p.pronargs-p.pronargdefaults INTO STRICT target,names,required_count FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=p_function;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_arguments) k WHERE NOT k=ANY(names)) THEN RAISE EXCEPTION 'PAYLOAD_NOT_ALLOWED'; END IF;
  IF EXISTS(SELECT 1 FROM generate_series(1,required_count) i WHERE NOT p_arguments ? names[i]) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  SELECT string_agg(format('%I %s',names[t.ordinality],pg_catalog.format_type(t.type,NULL)),',' ORDER BY t.ordinality),
   string_agg(format('%I => a.%I',names[t.ordinality],names[t.ordinality]),',' ORDER BY t.ordinality)
  INTO declarations,arguments FROM pg_catalog.pg_proc p,
   LATERAL unnest(p.proargtypes::oid[]) WITH ORDINALITY t(type,ordinality)
   WHERE p.oid=target AND p_arguments ? names[t.ordinality];
  IF arguments IS NULL THEN
   EXECUTE format('SELECT public.%I()',p_function) INTO result;
  ELSE
   EXECUTE format('SELECT public.%I(%s) FROM jsonb_to_record($1) AS a(%s)',p_function,arguments,declarations)
    INTO result USING p_arguments;
  END IF;
 END IF;
 IF original_mutation IS NOT NULL AND result ? 'mutation_id' THEN result:=result||jsonb_build_object('mutation_id',original_mutation); END IF;
 IF original_certificate_mutation IS NOT NULL AND result ? 'mutation_id' THEN result:=result||jsonb_build_object('mutation_id',original_certificate_mutation); END IF;
 result:=jsonb_build_object('_expert_workspace_id',p_workspace,'payload',private_isg.expert_response(result,actor));
 PERFORM set_config('private_isg.expert_workspace',coalesce(previous,''),true);
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('private_isg.expert_workspace',coalesce(previous,''),true);
 RAISE;
END $$;
NOTIFY pgrst,'reload schema';
