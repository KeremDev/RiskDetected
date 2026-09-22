-- One expert UI and one set of domain workflows. Workspace selection changes
-- authorization, not the identity of the authenticated actor.
-- Staging candidate; do not deploy to production before both-role acceptance.
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='60s';

CREATE FUNCTION private_isg.expert_workspace() RETURNS uuid
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT nullif(current_setting('private_isg.expert_workspace',true),'')::uuid
$$;

CREATE FUNCTION private_isg.expert_company_visible(p_owner uuid,p_company uuid,p_actor uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace uuid:=private_isg.expert_workspace(); member private_isg.workspace_memberships;
BEGIN
 IF workspace IS NULL THEN RETURN p_owner=p_actor; END IF;
 IF p_actor IS DISTINCT FROM private_isg.active_actor() OR p_company IS NULL THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.companies c WHERE c.id=p_company AND c.workspace_id=workspace) THEN RETURN false; END IF;
 BEGIN
  member:=private_isg.workspace_require_company(workspace,p_company,false);
 EXCEPTION WHEN SQLSTATE 'P0001' THEN RETURN false;
 END;
 RETURN member.user_id=p_actor;
END $$;

CREATE FUNCTION private_isg.expert_session_visible(p_owner uuid,p_session uuid,p_actor uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace uuid:=private_isg.expert_workspace();
BEGIN
 IF workspace IS NULL THEN RETURN p_owner=p_actor; END IF;
 RETURN p_actor=private_isg.active_actor()
  AND EXISTS(SELECT 1 FROM private_isg.pilot_training_sessions s WHERE s.id=p_session AND s.workspace_id=workspace)
  AND EXISTS(SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id=p_session)
  AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id=p_session
   AND NOT private_isg.expert_company_visible(r.owner_id,r.company_id,p_actor));
END $$;

CREATE FUNCTION private_isg.expert_require_company(p_company uuid,p_write boolean,p_domain text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace uuid:=private_isg.expert_workspace(); actor uuid:=private_isg.active_actor();
BEGIN
 IF workspace IS NULL OR p_write IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF p_domain IS NOT NULL THEN PERFORM private_isg.workspace_domain_gate(p_domain,p_write); END IF;
 IF p_company IS NULL THEN
  IF p_write THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  PERFORM private_isg.workspace_require_member(workspace,ARRAY['owner','admin','expert'],false);
 ELSE
  PERFORM private_isg.workspace_require_company(workspace,p_company,p_write);
 END IF;
 RETURN actor;
END $$;

-- Legacy presentation DTOs name the actor correlation field owner_id. Never
-- write that projection back as ownership: workspace rows keep owner_id NULL.
CREATE FUNCTION private_isg.expert_response(p_value jsonb,p_actor uuid) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE result jsonb; pair record;
BEGIN
 IF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(private_isg.expert_response(value,p_actor)),'[]'::jsonb) INTO result FROM jsonb_array_elements(p_value);
  RETURN result;
 ELSIF jsonb_typeof(p_value)='object' THEN
  result:='{}'::jsonb;
  FOR pair IN SELECT * FROM jsonb_each(p_value) LOOP
   result:=result||jsonb_build_object(pair.key,private_isg.expert_response(pair.value,p_actor));
  END LOOP;
  IF result->'owner_id'='null'::jsonb AND (result ? 'company_id' OR result ? 'companies') THEN
   result:=result||jsonb_build_object('owner_id',p_actor);
  END IF;
  RETURN result;
 END IF;
 RETURN p_value;
END $$;

REVOKE ALL ON FUNCTION private_isg.expert_workspace(),private_isg.expert_company_visible(uuid,uuid,uuid),
 private_isg.expert_session_visible(uuid,uuid,uuid),private_isg.expert_require_company(uuid,boolean,text),
 private_isg.expert_response(jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.expert_overview(p_company uuid,p_schema integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.expert_require_company(p_company,false,'personnel'); rows jsonb;
BEGIN
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'owner_id',actor,'name',c.name,
  'hazard_class',c.hazard_class,'is_archived',c.is_archived,'sector',p.sector,'email',p.email,
  'declared_employee_count',p.declared_employee_count,'responsible_employee_id',NULL,
  'responsible_name',p.responsible_name,'responsible_phone',p.responsible_phone,'responsible_email',p.responsible_email,
  'personnel_count',(SELECT count(*) FROM private_isg.employees e WHERE e.company_id=c.id AND NOT e.is_archived),
  'workplace_count',(SELECT count(*) FROM private_isg.workplaces w WHERE w.company_id=c.id AND NOT w.is_archived),
  'department_count',(SELECT count(*) FROM private_isg.departments d WHERE d.company_id=c.id AND NOT d.is_archived),
  'finding_count',NULL,'document_count',NULL,'completion_score',NULL) ORDER BY c.id),'[]'::jsonb)
 INTO rows FROM public.companies c LEFT JOIN private_isg.workspace_company_profiles p
  ON p.company_id=c.id AND p.workspace_id=c.workspace_id
 WHERE c.workspace_id=private_isg.expert_workspace() AND (p_company IS NULL OR c.id=p_company)
  AND private_isg.expert_company_visible(c.user_id,c.id,actor);
 RETURN jsonb_build_object('schema_version',p_schema,'owner_id',actor,'company_id',p_company,'companies',rows);
END $$;
REVOKE ALL ON FUNCTION private_isg.expert_overview(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;

-- Existing normal-expert readers retain their DTOs, catalogue rules and totals.
-- Only their company visibility predicate is made workspace aware.
CREATE OR REPLACE FUNCTION private_isg.education_detail(p_id uuid, p_company uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); result jsonb; co uuid;
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_id IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_sessions WHERE id=p_id AND private_isg.expert_session_visible(owner_id,id,actor)) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  FOR co IN SELECT company_id FROM private_isg.pilot_training_records WHERE session_id=p_id LOOP PERFORM private_isg.require_company(co,false); END LOOP;
  result:=private_isg.pilot_training_session_row(p_id);
 END IF;
 IF p_company IS NOT NULL THEN PERFORM private_isg.require_company(p_company,false); END IF;
 RETURN jsonb_build_object('schema_version',3,'owner_id',actor,'row',result,
 'package_checksum',(SELECT content_checksum FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1),
 'package',(SELECT content_package FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1),
 'certificates',(SELECT coalesce(jsonb_agg(jsonb_build_object('document_id',d.document_id,'revision',v.version,'scope_id',split_part(d.source_ref,':',2),'person_id',split_part(d.source_ref,':',3),'source_session_revision',v.snapshot->'source_session_revision') ORDER BY v.version DESC),'[]') FROM private_isg.documents d JOIN private_isg.document_versions v ON v.document_id=d.document_id WHERE private_isg.expert_company_visible(d.owner_id,d.company_id,actor) AND d.source_domain='training' AND d.template_code IN ('basic_training_certificate','training_record_certificate') AND split_part(d.source_ref,':',1)=p_id::text),
 'catalog_enabled',(SELECT enabled FROM private_isg.education_controls WHERE key='catalog_v1'),
 'certificate_enabled',(SELECT enabled FROM private_isg.education_controls WHERE key='certificate_v1'),
 'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'company_id',w.company_id,'company_name',(SELECT name FROM public.companies WHERE id=w.company_id),'name',w.name,'hazard_class',w.hazard_class) ORDER BY w.name),'[]')
 FROM private_isg.workplaces w WHERE private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived AND (p_company IS NULL OR w.company_id=p_company) AND private_isg.p05_pilot_can_read(actor,w.company_id)),
 'curricula',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.curriculum_id,'company_id',c.company_id,'workplace_id',c.workplace_id,'scope_key',c.scope_key,'education',c.education)),'[]')
 FROM private_isg.company_curriculum_versions c WHERE private_isg.expert_company_visible(c.owner_id,c.company_id,actor) AND c.education IS NOT NULL AND c.state='active' AND (p_company IS NULL OR c.company_id=p_company) AND private_isg.p05_pilot_can_read(actor,c.company_id)));
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.notice_rows(p_actor uuid, p_company uuid)
 RETURNS TABLE(kind text, destination text, company_id uuid, company_name text, record_id uuid, title text, due_on date, window_days integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
WITH scoped AS MATERIALIZED (
  SELECT c.id,c.name FROM public.companies c
  WHERE private_isg.expert_company_visible(c.user_id,c.id,p_actor) AND NOT c.is_archived
    AND (p_company IS NULL OR c.id=p_company)
    AND private_isg.p05_pilot_can_read(p_actor,c.id)),
raw AS (
  SELECT 'katip_contract'::text kind,'katipContracts'::text destination,c.id company_id,c.name company_name,
         t.contract_id record_id,t.counterparty title,(t.ends_before-1) due_on
    FROM private_isg.katip_contracts t JOIN scoped c ON c.id=t.company_id
   WHERE NOT t.is_deleted AND t.state='active' AND t.ends_before IS NOT NULL
  UNION ALL
  SELECT 'appointment','appointments',c.id,c.name,t.appointment_id,e.full_name,(t.ends_before-1)
    FROM private_isg.appointments t JOIN scoped c ON c.id=t.company_id
    JOIN private_isg.employees e ON e.id=t.employee_id
   WHERE NOT t.is_deleted AND t.ends_before IS NOT NULL
  UNION ALL
  SELECT 'emergency_plan','emergencyPlans',c.id,c.name,t.plan_id,w.name,t.valid_until
    FROM private_isg.emergency_plan_versions t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE NOT t.is_deleted AND t.state='active' AND t.valid_until IS NOT NULL
  UNION ALL
  SELECT 'drill','drills',c.id,c.name,t.record_id,t.scenario,t.valid_until
    FROM private_isg.pilot_completed_drills t JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted
  UNION ALL
  SELECT 'personnel_certificate','documentChecklist',c.id,c.name,t.record_id,e.full_name||' · '||t.title,t.valid_until
    FROM private_isg.pilot_personnel_certificates t JOIN scoped c ON c.id=t.company_id JOIN private_isg.employees e ON e.id=t.employee_id
    WHERE NOT t.is_deleted AND NOT e.is_archived
  UNION ALL
  SELECT 'training','training',c.id,c.name,(s->>'id')::uuid,t.title||' · '||coalesce(s->>'group_name',''),(s->>'valid_until')::date
    FROM private_isg.pilot_training_sessions t CROSS JOIN LATERAL jsonb_array_elements(t.education->'scopes') s JOIN scoped c ON c.id=(s->>'company_id')::uuid
    WHERE private_isg.expert_session_visible(t.owner_id,t.id,p_actor) AND t.deleted_at IS NULL AND s->>'valid_until' IS NOT NULL
  UNION ALL
  SELECT 'annual_work_item','annualWorkPlans',c.id,c.name,t.item_id,t.activity,t.planned_on
    FROM private_isg.annual_work_plan_items t
    JOIN private_isg.annual_work_plans p ON p.plan_id=t.plan_id
    JOIN scoped c ON c.id=p.company_id
   WHERE NOT t.is_deleted AND NOT p.is_deleted AND t.state='planned' AND t.planned_on IS NOT NULL
  UNION ALL
  SELECT 'board','boardMeetings',c.id,c.name,t.meeting_id,w.name,t.planned_on
    FROM private_isg.board_meetings t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE NOT t.is_deleted AND t.state='planned' AND t.planned_on IS NOT NULL
  UNION ALL
  SELECT 'board_decision','boardMeetings',c.id,c.name,t.decision_id,t.decision_no::text,t.due_on
    FROM private_isg.board_decisions t
    JOIN private_isg.board_meetings p ON p.meeting_id=t.meeting_id
    JOIN scoped c ON c.id=p.company_id
   WHERE NOT t.is_deleted AND NOT p.is_deleted AND p.state<>'cancelled'
     AND t.state='open' AND t.due_on IS NOT NULL
  UNION ALL
  SELECT 'risk_assessment','riskAssessments',c.id,c.name,t.assessment_id,w.name,t.valid_until
    FROM private_isg.risk_assessments t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE t.valid_until IS NOT NULL
  UNION ALL
  SELECT 'equipment','periodicChecks',c.id,c.name,t.equipment_id,t.serial_tag,i.next_due_on
    FROM private_isg.equipment_items t JOIN scoped c ON c.id=t.company_id
    JOIN LATERAL (SELECT x.next_due_on FROM private_isg.equipment_inspections x
                   WHERE x.equipment_id=t.equipment_id
                   ORDER BY x.performed_on DESC,x.inspection_id DESC LIMIT 1) i ON true
   WHERE NOT t.is_archived AND i.next_due_on IS NOT NULL)
SELECT r.kind,r.destination,r.company_id,r.company_name,r.record_id,
       coalesce(nullif(btrim(r.title),''),'—'),r.due_on,private_isg.notice_window(r.kind)
  FROM raw r WHERE private_isg.notice_kind_available(r.kind)
UNION ALL
-- Evrak carries its own window, and only the newest recorded copy counts.
SELECT 'document','documentChecklist',c.id,c.name,o.obligation_id,o.title,d.valid_until,o.notice_days
  FROM private_isg.document_obligations o JOIN scoped c ON c.id=o.company_id
  JOIN LATERAL (SELECT x.valid_until FROM private_isg.document_obligation_records x
                 WHERE x.obligation_id=o.obligation_id
                 ORDER BY x.issued_on DESC,x.record_id DESC LIMIT 1) d ON true
 WHERE NOT o.is_archived AND d.valid_until IS NOT NULL
   AND private_isg.notice_kind_available('document')
$function$
;

CREATE OR REPLACE FUNCTION private_isg.p05_company_overview(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); company public.companies; profile private_isg.p05_company_profiles;
  rows jsonb:='[]';
BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_overview(p_company,1); END IF;
  IF NOT private_isg.p05_pilot_can_read(actor,NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL THEN PERFORM private_isg.require_company(p_company,false); END IF;
  FOR company IN SELECT c.* FROM public.companies c
    JOIN private_isg.p05_pilot_company_origins o ON o.company_id=c.id AND o.actor_id=c.user_id
    WHERE c.user_id=actor AND (p_company IS NULL OR c.id=p_company) ORDER BY c.id LOOP
    IF NOT private_isg.p05_pilot_can_read(actor,company.id) THEN CONTINUE; END IF;
    PERFORM private_isg.require_company(company.id,false);
    SELECT * INTO profile FROM private_isg.p05_company_profiles WHERE company_id=company.id AND owner_id=actor;
    rows:=rows || jsonb_build_array(jsonb_build_object(
      'id',company.id,'owner_id',actor,'name',company.name,'hazard_class',company.hazard_class,'is_archived',company.is_archived,
      'sector',profile.sector,'email',profile.email,'declared_employee_count',profile.declared_employee_count,
      'responsible_employee_id',profile.responsible_employee_id,
      'personnel_count',(SELECT count(*) FROM private_isg.employees WHERE company_id=company.id AND owner_id=actor AND NOT is_archived),
      'workplace_count',(SELECT count(*) FROM private_isg.workplaces WHERE company_id=company.id AND owner_id=actor AND NOT is_archived),
      'department_count',(SELECT count(*) FROM private_isg.departments WHERE company_id=company.id AND owner_id=actor AND NOT is_archived),
      'finding_count',NULL,'document_count',NULL,'completion_score',NULL));
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'companies',rows);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.p05_company_overview_v2(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE result jsonb; rows jsonb;
BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_overview(p_company,2); END IF;
  -- Only enrich rows already authorized by the existing pilot/owner checks.
  result:=private_isg.p05_company_overview(p_company);
  SELECT coalesce(jsonb_agg(entry || jsonb_build_object('responsible_name',e.full_name,
    'responsible_phone',p.responsible_phone,'responsible_email',p.responsible_email) ORDER BY ordinal),'[]'::jsonb)
    INTO rows FROM jsonb_array_elements(result->'companies') WITH ORDINALITY AS r(entry,ordinal)
    LEFT JOIN private_isg.p05_company_profiles p ON p.company_id=(entry->>'id')::uuid AND p.owner_id=(result->>'owner_id')::uuid
    LEFT JOIN private_isg.employees e ON e.company_id=p.company_id AND e.owner_id=p.owner_id AND e.id=p.responsible_employee_id;
  RETURN result || jsonb_build_object('schema_version',2,'companies',rows);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.p05_pilot_account_enabled(p_actor uuid, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN
  IF p_actor IS DISTINCT FROM private_isg.active_actor() OR p_write IS NULL THEN RETURN false; END IF;
  PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
  RETURN true;
 END IF;
  IF p_actor IS NULL OR p_write IS NULL THEN RETURN false; END IF;
  PERFORM 1 FROM private_isg.p05_pilot_accounts a JOIN private_isg.rollout r ON r.feature='personnel'
    WHERE a.actor_id=p_actor AND a.read_enabled AND r.read_enabled
      AND (NOT p_write OR (a.write_enabled AND r.write_enabled))
      AND a.revoked_at IS NULL AND a.created_at<=clock_timestamp() AND a.expires_at>clock_timestamp()
    FOR SHARE OF a,r;
  RETURN FOUND;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.p05_pilot_can_read(p_actor uuid, p_company uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN
  IF NOT private_isg.p05_pilot_account_enabled(p_actor,false) THEN RETURN false; END IF;
  RETURN p_company IS NULL OR private_isg.expert_company_visible(NULL,p_company,p_actor);
 END IF;
  IF NOT private_isg.p05_pilot_account_enabled(p_actor,false) THEN RETURN false; END IF;
  IF p_company IS NULL THEN RETURN true; END IF; -- Account can reach an empty company list.
  PERFORM 1 FROM private_isg.p05_pilot_grants g
    JOIN private_isg.p05_pilot_company_origins o ON o.company_id=g.company_id AND o.actor_id=g.actor_id
    JOIN public.companies c ON c.id=g.company_id AND c.user_id=g.actor_id
    WHERE g.actor_id=p_actor AND g.company_id=p_company AND g.revoked_at IS NULL
      AND g.created_at<=clock_timestamp() AND g.expires_at>clock_timestamp()
    FOR SHARE OF g,o;
  RETURN FOUND;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_employee_learning(p_company uuid, p_employee uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.process_guard('personnel_certificate',p_company,false); scopes_ jsonb; package_ jsonb; expired_ int; legacy_ int; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
 IF p_company IS NULL OR NOT EXISTS(SELECT 1 FROM private_isg.employees WHERE id=p_employee AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor)) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 -- Scope is gated by process_guard and the employee ownership check.
 SELECT content_package INTO package_ FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1;
 IF package_ IS NULL THEN RAISE EXCEPTION 'PROFILE_UNAVAILABLE'; END IF;
 SELECT coalesce(jsonb_agg(s||jsonb_build_object('_session_id',t.id,'_title',t.title)) FILTER(WHERE (s->>'valid_until')::date>=today),'[]'),
 count(*) FILTER(WHERE (s->>'valid_until')::date<today) INTO scopes_,expired_
 FROM private_isg.pilot_training_sessions t CROSS JOIN LATERAL jsonb_array_elements(t.education->'scopes') s
 WHERE private_isg.expert_session_visible(t.owner_id,t.id,actor) AND t.deleted_at IS NULL AND (s->>'company_id')::uuid=p_company
 AND s->>'cycle' IN ('initial','periodic_repeat') AND EXISTS(SELECT 1 FROM jsonb_array_elements(s->'participants') p WHERE (p->>'id')::uuid=p_employee);
 -- Legacy rows have no reliable topic breakdown; do not invent credit from them.
 SELECT count(*) INTO legacy_ FROM private_isg.pilot_training_records r WHERE r.company_id=p_company AND private_isg.expert_company_visible(r.owner_id,r.company_id,actor) AND r.state='completed' AND r.session_id IS NULL;
 RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'employee_id',p_employee,
 'groups',private_isg.pilot_learning_totals(scopes_,package_),'expired_scopes',expired_,
 'legacy_company_records',legacy_,'source','expert_record','certificate_issued',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_file_owner(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'files'); END IF;
 IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 PERFORM private_isg.file_library_gate(p_write);
 IF p_company IS NOT NULL THEN
  IF NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  RETURN private_isg.require_file_library_company(p_company,p_write);
 END IF;
 IF p_write AND (private.user_plan_tier(actor) NOT IN ('plus','pro') OR NOT EXISTS(SELECT 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND status IN ('active','trialing','grace_period') AND (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()))) THEN RAISE EXCEPTION 'PAID_PLAN_REQUIRED'; END IF;
 RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_followup_rows(p_actor uuid, p_company uuid)
 RETURNS TABLE(kind text, company_id uuid, company_name text, record_id uuid, title text, due_on date, window_days integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT CASE r.kind WHEN 'drill' THEN 'completed_drill' ELSE r.kind END,r.company_id,r.company_name,r.record_id,r.title,r.due_on,r.window_days
 FROM private_isg.notice_rows(p_actor,p_company) r WHERE r.kind NOT IN ('annual_work_item','board','board_decision')
 UNION ALL
 SELECT 'file',f.company_id,c.name,f.entry_id,f.title,NULL::date,NULL::int
 FROM private_isg.file_library_entries f JOIN public.companies c ON c.id=f.company_id AND private_isg.expert_company_visible(c.user_id,c.id,p_actor)
 WHERE private_isg.expert_company_visible(f.owner_id,f.company_id,p_actor) AND NOT c.is_archived AND NOT f.is_archived AND f.asset_id IS NOT NULL AND private_isg.p05_pilot_can_read(p_actor,c.id)
 AND (p_company IS NULL OR f.company_id=p_company)
 AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_personnel_certificates x WHERE x.asset_id=f.asset_id AND NOT x.is_deleted)
 AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_completed_drills x WHERE (x.asset_id=f.asset_id OR f.asset_id=ANY(x.photo_ids)) AND NOT x.is_deleted)
$function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_process_attachment(p_kind text, p_record uuid, p_field text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); row_ jsonb; entry_ uuid; asset_ uuid;
BEGIN
 IF p_kind='completed_drill' AND p_field LIKE 'photo_ids:%' THEN
  row_:=private_isg.process_row(p_kind,p_record);
  asset_:=split_part(p_field,':',2)::uuid;
  IF NOT (row_->'values'->'photo_ids' ? asset_::text) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 ELSE
 IF p_field IS NULL OR p_field NOT IN ('asset_id','minutes_asset_id','visit_asset_id') OR NOT (private_isg.process_spec(p_kind)->'fields' ? p_field) THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 row_:=private_isg.process_row(p_kind,p_record);
 asset_:=(row_->'values'->>p_field)::uuid;
 END IF;
 SELECT fle.entry_id INTO entry_ FROM private_isg.file_library_entries fle JOIN private_isg.file_assets fa ON fa.asset_id=fle.asset_id
 WHERE fle.asset_id=asset_ AND private_isg.expert_company_visible(fle.owner_id,fle.company_id,actor) AND fle.company_id=(row_->>'company_id')::uuid
   AND NOT fle.is_archived AND private_isg.expert_company_visible(fa.owner_id,fa.company_id,actor) AND (fa.company_id=fle.company_id OR private_isg.p05_pilot_account_enabled(actor,false)) AND fa.scan_status='clean'
 ORDER BY fle.created_at DESC,fle.entry_id LIMIT 1;
 IF entry_ IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 RETURN jsonb_build_object('entry_id',entry_);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_read_file_library(p_company uuid, p_kind text, p_query text, p_category text, p_state text, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_categories jsonb; tally_rows jsonb; matching_rows integer;
  catalog_rows jsonb; accept_rows jsonb;
BEGIN
  actor:=private_isg.pilot_file_owner(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;

  IF p_kind='catalog' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('code',c.category,'ordinal',c.ordinal,'section',c.section)
      ORDER BY c.ordinal),'[]'::jsonb) INTO catalog_rows FROM private_isg.file_library_categories c;
    SELECT coalesce(jsonb_agg(jsonb_build_object('purpose',p.purpose,'extensions',to_jsonb(p.extensions),
      'max_bytes',p.max_bytes,'limit_approved',p.limit_approved) ORDER BY p.purpose),'[]'::jsonb)
      INTO accept_rows FROM private_isg.file_purposes p WHERE p.purpose IN ('company_document','evidence_photo');
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','categories',catalog_rows,
      'accepts',accept_rows,
      'scanners',(SELECT coalesce(jsonb_agg(jsonb_build_object('scanner',s.scanner,'assurance',s.assurance,
        'detects_malware',s.detects_malware) ORDER BY s.scanner),'[]'::jsonb) FROM private_isg.file_scanners s),
      'malware_scanning_available',
        (SELECT coalesce(bool_or(s.detects_malware),false) FROM private_isg.file_scanners s));
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.file_library_entries
      WHERE entry_id=p_id AND private_isg.expert_company_visible(owner_id,company_id,actor) AND (p_company IS NULL OR company_id=p_company)
        AND (company_id IS NULL OR private_isg.p05_pilot_can_read(actor,company_id));
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail',
      'row',private_isg.file_library_entry_row(p_id));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('pending','uploaded','scanning','clean','rejected',
    'scan_failed','promoted','expired','filed','working','unchecked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_category IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM private_isg.file_library_categories WHERE category=p_category) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived
  ), page AS (
    SELECT e.entry_id,e.company_id,coalesce(s.name,'Kişisel Dosyalar') AS company_name,e.category,e.title,e.note,e.tags,
      CASE WHEN e.asset_id IS NOT NULL THEN 'promoted' ELSE i.state END AS entry_state,
      row_number() OVER (ORDER BY
        CASE WHEN e.asset_id IS NOT NULL THEN 4
          WHEN i.state='rejected' THEN 0 WHEN i.state='scan_failed' THEN 1
          WHEN i.state='expired' THEN 2 ELSE 3 END,
        e.created_at DESC,e.entry_id) AS ordinal
    FROM private_isg.file_library_entries e
    LEFT JOIN scope s ON s.id=e.company_id
    JOIN private_isg.upload_intents i ON i.intent_id=e.intent_id
    WHERE private_isg.expert_company_visible(e.owner_id,e.company_id,actor) AND NOT e.is_archived AND (e.company_id IS NULL OR (s.id IS NOT NULL AND private_isg.p05_pilot_can_read(actor,e.company_id)))
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_category IS NULL OR category=p_category)
      AND (p_state IS NULL OR entry_state=p_state
        OR (p_state='filed' AND entry_state='promoted')
        OR (p_state='working' AND entry_state IN ('pending','uploaded','scanning','clean'))
        OR (p_state='unchecked' AND entry_state IN ('scan_failed','expired')))
      AND (needle IS NULL OR title ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%' OR note ILIKE '%'||needle||'%' OR array_to_string(tags,' ') ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,sum(state_total) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page WHERE company_id IS NOT NULL
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT coalesce(jsonb_object_agg(category,states),'{}'::jsonb) FROM
      (SELECT category,jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT category,entry_state,count(*) AS state_total FROM scoped
          GROUP BY category,entry_state) d GROUP BY category) e),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.file_library_entry_row(picked.entry_id)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,tally_categories,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,
    'counts',tally_all,'companies',tally_companies,'category_counts',tally_categories,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    'compliance_verdict',NULL,
    'malware_scanning_available',
      (SELECT coalesce(bool_or(s.detects_malware),false) FROM private_isg.file_scanners s));
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_training_read(p_company uuid, p_id uuid, p_after uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; rows jsonb; next_id uuid; total integer; completed integer;
BEGIN
  actor:=private_isg.require_company(p_company,false);
  IF p_id IS NOT NULL THEN
    rows:=private_isg.pilot_training_row(p_company,p_id);
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'rows',jsonb_build_array(rows));
  END IF;
  SELECT coalesce(jsonb_agg(private_isg.pilot_training_row(p_company,page.id) ORDER BY page.id DESC),'[]') INTO rows
    FROM (SELECT id FROM private_isg.pilot_training_records WHERE company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor)
      AND (p_after IS NULL OR id<p_after) ORDER BY id DESC LIMIT 50) page;
  IF jsonb_array_length(rows)=50 THEN next_id:=(rows->49->>'id')::uuid; END IF;
  SELECT count(*),count(*) FILTER(WHERE state='completed') INTO total,completed
    FROM private_isg.pilot_training_records WHERE company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor);
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'rows',rows,
    'next_id',next_id,'total',total,'completed',completed);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_training_sessions_read(p_company uuid, p_after uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); rows jsonb; next_id uuid; company uuid; writable uuid[]:='{}';
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_company IS NOT NULL THEN PERFORM private_isg.require_company(p_company,false); END IF;
 FOR company IN SELECT c.id FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id) ORDER BY c.id LOOP
  BEGIN
   PERFORM private_isg.require_company(company,true); writable:=array_append(writable,company);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
   IF SQLERRM NOT IN ('FEATURE_UNAVAILABLE','PAID_PLAN_REQUIRED','ACCESS_DENIED') THEN RAISE; END IF;
  END;
 END LOOP;
 SELECT coalesce(jsonb_agg(private_isg.pilot_training_session_row(q.id) ORDER BY q.id DESC),'[]') INTO rows FROM (
  SELECT s.id FROM private_isg.pilot_training_sessions s WHERE private_isg.expert_session_visible(s.owner_id,s.id,actor) AND s.deleted_at IS NULL
   AND (p_after IS NULL OR s.id<p_after)
   AND EXISTS(SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id=s.id AND (p_company IS NULL OR r.company_id=p_company))
   AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id=s.id AND NOT private_isg.p05_pilot_can_read(actor,r.company_id))
   ORDER BY s.id DESC LIMIT 30) q;
 IF jsonb_array_length(rows)=30 THEN next_id:=(rows->29->>'id')::uuid; END IF;
 RETURN jsonb_build_object('schema_version',2,'owner_id',actor,'rows',rows,'next_id',next_id,'writable_companies',writable,'catalog',
  (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.created_at,c.title),'[]') FROM private_isg.pilot_training_catalog c WHERE c.owner_id IS NULL OR c.owner_id=actor));
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_visit_summary(p_company uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.process_guard('site_visit',p_company,false); result jsonb;
BEGIN
 IF (p_from IS NOT NULL AND NOT isfinite(p_from)) OR (p_to IS NOT NULL AND NOT isfinite(p_to)) OR p_from>p_to THEN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 SELECT jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'from',p_from,'to',p_to,
   'visits',count(*),'recorded_minutes',sum(v.duration_minutes),'timed_visits',count(v.duration_minutes),
   'last_visited_on',max(v.visited_on)) INTO result
 FROM private_isg.site_visits v JOIN public.companies c ON c.id=v.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor)
 WHERE private_isg.expert_company_visible(v.owner_id,v.company_id,actor) AND NOT v.is_deleted AND private_isg.p05_pilot_can_read(actor,v.company_id)
   AND (p_company IS NULL OR v.company_id=p_company) AND (p_from IS NULL OR v.visited_on>=p_from) AND (p_to IS NULL OR v.visited_on<=p_to);
 RETURN result;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.process_documents(p_company uuid, p_document uuid, p_version integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ DECLARE actor uuid:=private_isg.active_actor(); d private_isg.documents; result jsonb; BEGIN
IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
IF p_document IS NOT NULL THEN
 SELECT * INTO d FROM private_isg.documents WHERE document_id=p_document AND private_isg.expert_company_visible(owner_id,company_id,actor) AND source_domain='module' AND template_code LIKE 'process_%';
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 PERFORM private_isg.process_guard(split_part(d.source_ref,':',1),d.company_id,false);
 SELECT snapshot INTO result FROM private_isg.document_versions WHERE document_id=d.document_id AND version=coalesce(p_version,d.current_version);
 IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 RETURN result;
END IF;
IF p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
RETURN (SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') FROM (
 SELECT listed.document_id AS id,v.version,v.document_no,v.finalized_at,c.name AS company_name,split_part(listed.source_ref,':',1) AS kind
 FROM private_isg.documents listed JOIN private_isg.document_versions v ON v.document_id=listed.document_id JOIN public.companies c ON c.id=listed.company_id
 WHERE private_isg.expert_company_visible(listed.owner_id,listed.company_id,actor) AND listed.source_domain='module' AND listed.template_code LIKE 'process_%' AND private_isg.p05_pilot_can_read(actor,listed.company_id) AND (p_company IS NULL OR listed.company_id=p_company)
 ORDER BY v.finalized_at DESC,listed.document_id,v.version DESC OFFSET p_offset LIMIT 20) q);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.process_guard(p_kind text, p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ DECLARE actor uuid:=private_isg.active_actor(); spec jsonb:=private_isg.process_spec(p_kind); BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'operations'); END IF;
IF spec IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
PERFORM private_isg.module_gate(spec->>'module',p_write);
IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_company IS NOT NULL THEN
 PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND (NOT p_write OR NOT is_archived) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
END IF;
IF p_write THEN
 IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 IF private.user_plan_tier(actor) NOT IN ('plus','pro') OR NOT EXISTS(SELECT 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND status IN ('active','trialing','grace_period') AND (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp())) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
END IF;
RETURN actor; END $function$
;

CREATE OR REPLACE FUNCTION private_isg.process_read(p_kind text, p_company uuid, p_id uuid, p_parent uuid, p_query text, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ DECLARE actor uuid; spec jsonb:=private_isg.process_spec(p_kind); ids uuid[]; rows_ jsonb:='[]'; id_ uuid; join_ text:=''; where_ text; parent_spec jsonb; BEGIN
actor:=private_isg.process_guard(p_kind,p_company,false);
IF p_id IS NOT NULL THEN RETURN private_isg.process_row(p_kind,p_id); END IF;
IF p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
IF spec ? 'parent' THEN
 parent_spec:=private_isg.process_spec(spec->>'parent_kind');
 join_:=format(' JOIN private_isg.%I p ON p.%I=t.%I ',parent_spec->>'table',parent_spec->>'id',spec->>'parent');
 where_:='p.company_id';
ELSE where_:='t.company_id'; END IF;
EXECUTE format('SELECT array_agg(id) FROM (SELECT t.%I id FROM private_isg.%I t %s JOIN public.companies c ON c.id=%s WHERE private_isg.expert_company_visible(c.user_id,c.id,$1) AND private_isg.p05_pilot_can_read($1,c.id) AND ($2 IS NULL OR c.id=$2) AND NOT coalesce((to_jsonb(t)->>''is_deleted'')::boolean,false) AND NOT coalesce((to_jsonb(t)->>''is_archived'')::boolean,false) %s AND ($3 IS NULL OR to_jsonb(t)->>%L ILIKE ''%%''||$3||''%%'') %s ORDER BY t.%I DESC OFFSET $4 LIMIT 21) q',spec->>'id',spec->>'table',join_,where_,CASE WHEN spec ? 'parent' THEN 'AND NOT p.is_deleted' ELSE '' END,spec->>'title',CASE WHEN spec ? 'parent' THEN format('AND ($5 IS NULL OR t.%I=$5)',spec->>'parent') WHEN p_kind='personnel_certificate' THEN 'AND ($5 IS NULL OR t.employee_id=$5)' WHEN p_kind='contractor_engagement' THEN 'AND ($5 IS NULL OR t.organization_id=$5)' ELSE '' END,spec->>'id') INTO ids USING actor,p_company,nullif(btrim(p_query),''),p_offset,p_parent;
FOREACH id_ IN ARRAY coalesce(ids[1:20],ARRAY[]::uuid[]) LOOP rows_:=rows_||jsonb_build_array(private_isg.process_row(p_kind,id_)); END LOOP;
RETURN jsonb_build_object('rows',rows_,'has_more',coalesce(cardinality(ids)>20,false),
 'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]') FROM private_isg.workplaces WHERE company_id=p_company AND NOT is_archived),
 'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) ORDER BY full_name),'[]') FROM private_isg.employees WHERE company_id=p_company AND NOT is_archived),
 'documents',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',obligation_id,'name',title) ORDER BY title),'[]') FROM private_isg.document_obligations WHERE company_id=p_company AND NOT is_archived),
 'organizations',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]') FROM private_isg.contractor_organizations WHERE company_id=p_company AND NOT is_archived));
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.process_references(p_kind text, p_company uuid, p_id uuid, p_query text, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); rows_ jsonb; row_ jsonb; from_ text; id_ text; title_ text; date_ text; state_ text; company_ text; predicate text; BEGIN
 IF p_company IS NULL OR p_offset IS NULL OR p_offset<0 OR p_offset>100000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) OR NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 PERFORM 1 FROM public.companies WHERE id=p_company AND private_isg.expert_company_visible(user_id,id,actor) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF p_kind NOT IN ('training_record','equipment_inspection','nonconformity','checklist_run') THEN
  IF p_id IS NULL THEN RETURN private_isg.process_read(p_kind,p_company,NULL,NULL,p_query,p_offset); END IF;
  row_:=private_isg.process_row(p_kind,p_id);
  IF (row_->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('rows',jsonb_build_array(row_),'has_more',false,'workplaces','[]'::jsonb,'employees','[]'::jsonb,'documents','[]'::jsonb,'organizations','[]'::jsonb);
 END IF;
 CASE p_kind
 WHEN 'training_record' THEN
  from_:='private_isg.pilot_training_records t';id_:='t.id';title_:='t.title';date_:='t.starts_at';state_:='t.state';company_:='t.company_id';predicate:='t.state=''completed'' AND t.owner_id=$1';
 WHEN 'equipment_inspection' THEN
  PERFORM private_isg.require_equipment_company(p_company,false);
  from_:='private_isg.equipment_inspections t JOIN private_isg.equipment_items e ON e.equipment_id=t.equipment_id';id_:='t.inspection_id';title_:='e.serial_tag';date_:='t.performed_on';state_:='t.result';company_:='e.company_id';predicate:='NOT e.is_archived AND e.owner_id=$1';
 WHEN 'checklist_run' THEN
  PERFORM private_isg.require_checklist_company(p_company,false);
  from_:='private_isg.checklist_runs t JOIN private_isg.checklist_templates ct ON ct.template_code=t.template_code';id_:='t.run_id';title_:='ct.title';date_:='t.started_on';state_:='t.state';company_:='t.company_id';predicate:='t.state=''submitted''';
 WHEN 'nonconformity' THEN
  PERFORM private_isg.require_nonconformity_company(p_company,false);
  from_:='private_isg.nonconformities t';id_:='t.nonconformity_id';title_:='t.title';date_:='t.opened_on';state_:='t.state';company_:='t.company_id';predicate:='t.state<>''cancelled'' AND t.owner_id=$1';
 END CASE;
 EXECUTE format('SELECT coalesce(jsonb_agg(r),''[]''::jsonb) FROM (SELECT jsonb_build_object(''id'',%s,''company_id'',%s,''company_name'',c.name,''title'',%s,''date'',%s,''expected'','''',''values'',jsonb_build_object(''state'',%s)) r FROM %s JOIN public.companies c ON c.id=%s WHERE %s AND %s=$2 AND ($3 IS NULL OR %s=$3) AND ($4 IS NULL OR %s ILIKE ''%%''||$4||''%%'') ORDER BY %s DESC,%s DESC OFFSET $5 LIMIT 21) q',id_,company_,title_,date_,state_,from_,company_,predicate,company_,id_,title_,date_,id_) INTO rows_ USING actor,p_company,p_id,nullif(btrim(p_query),''),p_offset;
 IF p_id IS NOT NULL AND jsonb_array_length(rows_)=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 RETURN jsonb_build_object('rows',(SELECT coalesce(jsonb_agg(value ORDER BY ord),'[]') FROM jsonb_array_elements(rows_) WITH ORDINALITY x(value,ord) WHERE ord<=20),'has_more',jsonb_array_length(rows_)>20,'workplaces','[]'::jsonb,'employees','[]'::jsonb,'documents','[]'::jsonb,'organizations','[]'::jsonb);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_appointments(p_company uuid, p_kind text, p_query text, p_state text, p_workplace uuid, p_role text, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; today date;
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_appointment_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog',
      'kinds',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',k.kind,'ordinal',k.ordinal,
          'usual_basis',k.usual_basis) ORDER BY k.ordinal),'[]'::jsonb)
        FROM private_isg.appointment_kinds k),
      'bases',jsonb_build_array('elected','appointed'),
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name)
          ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived),
      'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)
          ORDER BY e.full_name),'[]'::jsonb)
        FROM private_isg.employees e
        WHERE p_company IS NOT NULL AND e.company_id=p_company AND NOT e.is_archived),
      -- Said plainly rather than left to be inferred from a silent screen.
      'required_count_known',false,
      'qualification_check_available',false,
      'letter_storage_available',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.live_appointments a
      JOIN public.companies c ON c.id=a.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor)
      WHERE a.appointment_id=p_id AND (p_company IS NULL OR a.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.appointment_row(p_id,today));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('upcoming','active','ended') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_role IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.appointment_kinds WHERE kind=p_role) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), page AS (
    SELECT a.appointment_id,a.company_id,s.name AS company_name,a.employee_id,e.full_name AS employee_name,
      a.scope_workplace_id,w.name AS workplace_name,a.kind AS role_kind,a.starts_on,
      private_isg.appointment_status(a.starts_on,a.ends_before,today) AS entry_state,
      -- Active first, then what is about to begin, then what is over.
      row_number() OVER (ORDER BY
        CASE private_isg.appointment_status(a.starts_on,a.ends_before,today)
          WHEN 'active' THEN 0 WHEN 'upcoming' THEN 1 ELSE 2 END,
        a.starts_on DESC,s.name,w.name,e.full_name,a.appointment_id) AS ordinal
    FROM private_isg.live_appointments a
    JOIN scope s ON s.id=a.company_id
    JOIN private_isg.employees e ON e.company_id=a.company_id AND e.id=a.employee_id
    JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.scope_workplace_id
    WHERE private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR scope_workplace_id=p_workplace)
      AND (p_role IS NULL OR role_kind=p_role)
      AND (p_state IS NULL OR entry_state=p_state)
      AND (needle IS NULL OR employee_name ILIKE '%'||needle||'%'
           OR workplace_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.appointment_row(picked.appointment_id,today)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    -- A tally of who holds which role, never a statement that a workplace has
    -- enough of them or that anyone is qualified.
    'compliance_verdict',NULL,'required_count_known',false,
    'qualification_check_available',false,'health_records_tracked',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_checklists(p_company uuid, p_kind text, p_query text, p_state text, p_workplace uuid, p_template text, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; today date;
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_checklist_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','templates','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog',
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived),
      -- The lists a run may be started from: published only, and only the
      -- expert's own or a product one.
      'templates',(SELECT coalesce(jsonb_agg(jsonb_build_object('template_code',t.template_code,
          'title',t.title,'version',v.version,'items',
          (SELECT count(*) FROM private_isg.checklist_template_items i
            WHERE i.template_code=t.template_code AND i.version=v.version),
          'is_product',t.owner_id IS NULL) ORDER BY t.title),'[]'::jsonb)
        FROM private_isg.checklist_templates t
        JOIN private_isg.checklist_template_versions v
          ON v.template_code=t.template_code AND v.status='published'
        WHERE NOT t.is_archived AND ((t.owner_id IS NULL AND t.workspace_id IS NULL) OR (t.owner_id=actor AND t.workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace()))),
      -- Said plainly rather than implied by an empty list: the product does not
      -- ship a question set, because no approved one exists.
      'product_templates_offered',false,
      'auto_nonconformity',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='templates' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','templates',
      'rows',(SELECT coalesce(jsonb_agg(jsonb_build_object('template_code',t.template_code,'title',t.title,
          'is_product',t.owner_id IS NULL,'is_archived',t.is_archived,
          'versions',(SELECT coalesce(jsonb_agg(jsonb_build_object('version',v.version,'status',v.status,
              'published_at',v.published_at,'approval_note',v.approval_note,
              'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('item_code',i.item_code,'prompt',i.prompt,
                  'position',i.position,'allows_not_applicable',i.allows_not_applicable)
                  ORDER BY i.position),'[]'::jsonb)
                FROM private_isg.checklist_template_items i
                WHERE i.template_code=v.template_code AND i.version=v.version))
              ORDER BY v.version DESC),'[]'::jsonb)
            FROM private_isg.checklist_template_versions v WHERE v.template_code=t.template_code))
          ORDER BY t.title),'[]'::jsonb)
        FROM private_isg.checklist_templates t
        WHERE (t.owner_id IS NULL AND t.workspace_id IS NULL) OR (t.owner_id=actor AND t.workspace_id IS NOT DISTINCT FROM private_isg.expert_workspace())),
      -- An expert's approval of their own list is exactly that, and no more.
      'approval_is_self_declared',true,
      'product_templates_offered',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.checklist_runs r
      JOIN public.companies c ON c.id=r.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor)
      WHERE r.run_id=p_id AND (p_company IS NULL OR r.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.checklist_run_row(p_id,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('open','submitted','cancelled') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), page AS (
    SELECT r.run_id,r.company_id,s.name AS company_name,r.workplace_id,w.name AS workplace_name,
      r.template_code,t.title AS template_title,r.state AS entry_state,r.started_on,
      -- Open first, because an unfinished run is the one that needs a person.
      row_number() OVER (ORDER BY
        CASE r.state WHEN 'open' THEN 0 WHEN 'submitted' THEN 1 ELSE 2 END,
        r.started_on DESC,s.name,w.name,r.run_id) AS ordinal
    FROM private_isg.checklist_runs r
    JOIN scope s ON s.id=r.company_id
    JOIN private_isg.workplaces w ON w.company_id=r.company_id AND w.id=r.workplace_id
    JOIN private_isg.checklist_templates t ON t.template_code=r.template_code
    WHERE private_isg.expert_company_visible(r.owner_id,r.company_id,actor)
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_template IS NULL OR template_code=p_template)
      AND (p_state IS NULL OR entry_state=p_state)
      AND (needle IS NULL OR template_title ILIKE '%'||needle||'%'
           OR workplace_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.checklist_run_row(picked.run_id,false)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    -- A tally of checks that were run, never a statement that any workplace is
    -- compliant, and never a claim that a failing answer became a finding.
    'compliance_verdict',NULL,'auto_nonconformity',false,'health_records_tracked',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_document_portfolio(p_query text, p_status text, p_company uuid, p_kinds text[], p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); today date; needle text;
  page_limit integer; page_offset integer;
  -- Prefixed so a local can never be mistaken for a column of the same name:
  -- the aggregates below alias total, state and states.
  tally_all jsonb; tally_companies jsonb; tally_kinds jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  PERFORM private_isg.document_tracking_gate(false);
  -- PILOT DIVERGENCE: the account-wide read is a pilot surface too. An account
  -- with no pilot enrolment gets the closed answer, not an empty portfolio.
  IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('missing','due_soon','expired','valid') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- The page size is the client's, inside a bound the server owns.
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  -- One statement: the tally, the per-company summary and the page all read the
  -- same CTE, so the count can never disagree with the list it is counting.
  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived
  ), latest AS (
    SELECT DISTINCT ON (r.obligation_id) r.obligation_id,r.valid_until,r.issued_on
    FROM private_isg.document_obligation_records r
    JOIN private_isg.document_obligations o ON o.obligation_id=r.obligation_id
    WHERE o.company_id IN (SELECT id FROM scope)
    ORDER BY r.obligation_id,r.issued_on DESC,r.recorded_at DESC
  ), page AS (
    SELECT o.obligation_id,o.company_id,s.name AS company_name,o.title,o.kind_code,
      private_isg.document_obligation_status(l.valid_until,l.obligation_id IS NOT NULL,o.notice_days,today) AS state,
      l.valid_until,
      -- Worst first: what ran out, then what was never filed, then what is due.
      row_number() OVER (ORDER BY
        CASE private_isg.document_obligation_status(l.valid_until,l.obligation_id IS NOT NULL,o.notice_days,today)
          WHEN 'expired' THEN 0 WHEN 'missing' THEN 1 WHEN 'due_soon' THEN 2 ELSE 3 END,
        l.valid_until NULLS LAST,s.name,o.title,o.obligation_id) AS ordinal
    FROM private_isg.document_obligations o
    JOIN scope s ON s.id=o.company_id
    LEFT JOIN latest l ON l.obligation_id=o.obligation_id
    WHERE private_isg.expert_company_visible(o.owner_id,o.company_id,actor) AND NOT o.is_archived
  ), scoped AS (
    -- The company page asks one heading at a time, so a per-kind tally that
    -- follows only the company filter lets it read every heading in one call.
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM page
    WHERE (p_status IS NULL OR state=p_status)
      AND (p_company IS NULL OR company_id=p_company)
      AND (p_kinds IS NULL OR kind_code=ANY(p_kinds))
      AND (needle IS NULL OR title ILIKE '%'||needle||'%' OR kind_code ILIKE '%'||needle||'%'
           OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    -- The headline counts the whole account, before any filter, so selecting a
    -- chip never makes the account look smaller than it is.
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb)
       FROM (SELECT state,count(*) AS total FROM page GROUP BY state) tally),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',company_id,'name',company_name,
        'total',total,'counts',states) ORDER BY company_name),'[]'::jsonb)
       FROM (SELECT company_id,company_name,count(*) AS total,
               jsonb_object_agg(state,state_total) AS states
             FROM (SELECT company_id,company_name,state,count(*) AS state_total
                   FROM page GROUP BY company_id,company_name,state) per_state
             GROUP BY company_id,company_name) grouped),
    (SELECT coalesce(jsonb_object_agg(kind_code,states),'{}'::jsonb)
       FROM (SELECT kind_code,jsonb_object_agg(state,state_total) AS states
             FROM (SELECT kind_code,state,count(*) AS state_total
                   FROM scoped GROUP BY kind_code,state) per_kind
             GROUP BY kind_code) by_kind),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.document_obligation_row(picked.company_id,picked.obligation_id,today)
           ||jsonb_build_object('company_id',picked.company_id,'company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,tally_kinds,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','portfolio','today',today,
    'counts',tally_all,'companies',tally_companies,'kind_counts',tally_kinds,'rows',tally_rows,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    -- A tally of tracked documents, never a statement that any company or any
    -- person is compliant, and never a claim that a file is held here.
    'compliance_verdict',NULL,'file_storage_available',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_document_tracking(p_company uuid, p_kind text, p_query text, p_status text, p_workplace uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; rows jsonb; needle text; today date; summary jsonb;
BEGIN
  actor:=private_isg.require_document_tracking_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('list','detail','kinds','workplaces') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;
  IF p_kind='kinds' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('code',k.kind_code,'ordinal',k.ordinal,
      'default_validity_days',k.default_validity_days) ORDER BY k.ordinal),'[]'::jsonb) INTO rows
      FROM private_isg.document_obligation_kinds k;
    -- Health records are not a kind here and the schema has no code for one.
    RETURN jsonb_build_object('schema_version',1,'kind','kinds','rows',rows,'health_records_tracked',false);
  END IF;
  IF p_kind='workplaces' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'needs_review',w.needs_review)
      ORDER BY w.name),'[]'::jsonb) INTO rows
      FROM private_isg.workplaces w WHERE w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived;
    RETURN jsonb_build_object('schema_version',1,'kind','workplaces','rows',rows);
  END IF;
  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    rows:=private_isg.document_obligation_row(p_company,p_id,today);
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','row',rows,'today',today);
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('missing','due_soon','expired','valid') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  needle:=nullif(btrim(coalesce(p_query,'')),'');
  SELECT coalesce(jsonb_agg(entry ORDER BY (entry->>'title')),'[]'::jsonb) INTO rows FROM (
    SELECT private_isg.document_obligation_row(p_company,o.obligation_id,today) AS entry
    FROM private_isg.document_obligations o
    WHERE o.company_id=p_company AND private_isg.expert_company_visible(o.owner_id,o.company_id,actor) AND NOT o.is_archived
      AND (p_workplace IS NULL OR o.workplace_id=p_workplace)
      AND (needle IS NULL OR o.title ILIKE '%'||needle||'%' OR o.kind_code ILIKE '%'||needle||'%')
    ORDER BY o.title,o.obligation_id LIMIT 200) page
  WHERE p_status IS NULL OR entry->>'status'=p_status;
  -- Counts of what the list holds. This is a tally of tracked documents, not a
  -- statement that the company or any person is compliant.
  SELECT jsonb_object_agg(state,total) INTO summary FROM (
    SELECT value->>'status' AS state,count(*) AS total FROM jsonb_array_elements(rows) AS value
    GROUP BY value->>'status') counted;
  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',rows,'today',today,
    'counts',coalesce(summary,'{}'::jsonb),'compliance_verdict',NULL,'file_storage_available',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_drills(p_company uuid, p_kind text, p_query text, p_state text, p_workplace uuid, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.drill_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_drill_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      -- Only plans that are in force can be rehearsed, and only this actor's.
      -- A drill without a plan is not offered, because the record has nowhere
      -- to point.
      'plans',(SELECT coalesce(jsonb_agg(jsonb_build_object('plan_id',v.plan_id,'version',v.version,
          'scope',v.scope,'workplace_id',v.workplace_id,'workplace_name',w.name,
          'valid_until',v.valid_until) ORDER BY w.name,v.scope),'[]'::jsonb)
        FROM private_isg.emergency_plan_versions v
        JOIN private_isg.workplaces w ON w.company_id=v.company_id AND w.id=v.workplace_id
        WHERE p_company IS NOT NULL AND v.company_id=p_company AND private_isg.expert_company_visible(v.owner_id,v.company_id,actor)
          AND v.state='active' AND NOT w.is_archived),
      'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)
          ORDER BY e.full_name),'[]'::jsonb)
        FROM private_isg.employees e
        WHERE p_company IS NOT NULL AND e.company_id=p_company AND NOT e.is_archived),
      -- The product proposes no drill period: no approved catalogue exists.
      'period_defaults_offered',false,
      'participants_are_snapshotted',true,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.live_drill_records d
      JOIN public.companies c ON c.id=d.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor)
      WHERE d.drill_id=p_id AND (p_company IS NULL OR d.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.drill_row(p_id,today));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('overdue','due_soon','scheduled','performed','cancelled',
    'closed') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), page AS (
    SELECT d.drill_id,d.company_id,s.name AS company_name,d.workplace_id,w.name AS workplace_name,
      v.scope AS plan_scope,
      private_isg.drill_status(d.state,d.planned_on,notice,today) AS entry_state,
      d.planned_on,
      -- Worst first: what was missed, then what is coming up.
      row_number() OVER (ORDER BY
        CASE private_isg.drill_status(d.state,d.planned_on,notice,today)
          WHEN 'overdue' THEN 0 WHEN 'due_soon' THEN 1 WHEN 'scheduled' THEN 2 ELSE 3 END,
        d.planned_on,s.name,w.name,d.drill_id) AS ordinal
    FROM private_isg.live_drill_records d
    JOIN scope s ON s.id=d.company_id
    JOIN private_isg.workplaces w ON w.company_id=d.company_id AND w.id=d.workplace_id
    JOIN private_isg.emergency_plan_versions v
      ON v.plan_id=d.plan_id AND v.version=d.plan_version
    WHERE private_isg.expert_company_visible(v.owner_id,v.company_id,actor) AND NOT w.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.drill_group(entry_state)=p_state)
      AND (needle IS NULL OR plan_scope ILIKE '%'||needle||'%'
           OR workplace_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.drill_row(picked.drill_id,today)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    -- A tally of drills, never a statement that a workplace is prepared.
    'compliance_verdict',NULL,'health_records_tracked',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_emergency_plans(p_company uuid, p_kind text, p_query text, p_state text, p_workplace uuid, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.emergency_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_emergency_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review,'hazard_class',w.hazard_class,
          'suggested_period_years',private_isg.risk_period_years_for_hazard_class(w.hazard_class)) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived),
      'team_roles',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',r.role_code,'ordinal',r.ordinal)
          ORDER BY r.ordinal),'[]'::jsonb) FROM private_isg.emergency_team_roles r),
      -- The product proposes no renewal period, because no approved catalogue
      -- exists. Whatever date the expert writes is stored as the expert's.
      'period_defaults_offered',false,
      'expert_period_source','expert',
      'review_cleared_by_note',true,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.live_emergency_plan_versions v
      JOIN public.companies c ON c.id=v.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor)
      WHERE v.plan_id=p_id AND (p_company IS NULL OR v.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.emergency_plan_row(p_id,today,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('never_published','period_unknown','expired','due_soon','valid',
    'current','untracked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), page AS (
    SELECT v.plan_id,v.company_id,s.name AS company_name,v.workplace_id,w.name AS workplace_name,
      v.scope AS plan_scope,
      private_isg.emergency_plan_status(v.valid_until,true,notice,today) AS entry_state,
      v.valid_until,v.needs_review,
      row_number() OVER (ORDER BY
        CASE private_isg.emergency_plan_status(v.valid_until,true,notice,today)
          WHEN 'expired' THEN 0 WHEN 'period_unknown' THEN 1 WHEN 'due_soon' THEN 2 ELSE 3 END,
        v.valid_until NULLS FIRST,s.name,w.name,v.plan_id) AS ordinal
    FROM private_isg.live_emergency_plan_versions v
    JOIN scope s ON s.id=v.company_id
    JOIN private_isg.workplaces w ON w.company_id=v.company_id AND w.id=v.workplace_id
    WHERE private_isg.expert_company_visible(v.owner_id,v.company_id,actor) AND v.state='active' AND NOT w.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.emergency_plan_group(entry_state)=p_state)
      AND (needle IS NULL OR plan_scope ILIKE '%'||needle||'%'
           OR workplace_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.emergency_plan_row(picked.plan_id,today,false)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_equipment_checks(p_company uuid, p_kind text, p_query text, p_state text, p_workplace uuid, p_type text, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.equipment_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_types jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_equipment_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',2,'kind','catalog','notice_days',notice,
      'suggestions',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.equipment_type,
          'ordinal',s.ordinal,'default_period_months',d.period_months,
          'default_basis_note',d.basis_note) ORDER BY s.ordinal),'[]'::jsonb)
        FROM private_isg.equipment_type_suggestions s
        LEFT JOIN private_isg.equipment_default_periods d ON d.equipment_type=s.equipment_type),
      -- The product now starts a type at a period. It is a general default that
      -- the expert confirms, never a determination made for this company.
      'period_defaults_offered',true,
      'period_default_source','regulation_default',
      'period_default_needs_review',true,
      'rules',(SELECT coalesce(jsonb_agg(jsonb_build_object('equipment_type',r.equipment_type,
          'period_months',r.period_months,'period_source',r.period_source,
          'needs_review',r.needs_review,'exception_note',r.exception_note) ORDER BY r.equipment_type),'[]'::jsonb)
        FROM private_isg.equipment_inspection_rules r WHERE p_company IS NOT NULL AND r.company_id=p_company),
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name)
          ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived),
      'katip_official_verification',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.equipment_items e
      JOIN public.companies c ON c.id=e.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor)
      WHERE e.equipment_id=p_id AND (p_company IS NULL OR e.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',2,'kind','detail','today',today,
      'row',private_isg.equipment_check_row(p_id,today,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('never_inspected','period_unknown','failed','overdue',
    'due_soon','valid','current','untracked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived
  ), latest AS (
    SELECT DISTINCT ON (i.equipment_id) i.equipment_id,i.next_due_on,i.result,i.performed_on
    FROM private_isg.equipment_inspections i
    JOIN private_isg.equipment_items e ON e.equipment_id=i.equipment_id
    WHERE e.company_id IN (SELECT id FROM scope)
    ORDER BY i.equipment_id,i.performed_on DESC,i.inspection_id
  ), page AS (
    SELECT e.equipment_id,e.company_id,s.name AS company_name,e.equipment_type,e.serial_tag,
      e.workplace_id,
      private_isg.equipment_check_status(l.next_due_on,l.equipment_id IS NOT NULL,l.result,notice,today) AS entry_state,
      l.next_due_on,
      row_number() OVER (ORDER BY
        CASE private_isg.equipment_check_status(l.next_due_on,l.equipment_id IS NOT NULL,l.result,notice,today)
          WHEN 'overdue' THEN 0 WHEN 'failed' THEN 1 WHEN 'never_inspected' THEN 2
          WHEN 'period_unknown' THEN 3 WHEN 'due_soon' THEN 4 ELSE 5 END,
        l.next_due_on NULLS FIRST,s.name,e.serial_tag,e.equipment_id) AS ordinal
    FROM private_isg.equipment_items e
    JOIN scope s ON s.id=e.company_id
    LEFT JOIN latest l ON l.equipment_id=e.equipment_id
    WHERE private_isg.expert_company_visible(e.owner_id,e.company_id,actor) AND NOT e.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_type IS NULL OR equipment_type=p_type)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.equipment_check_group(entry_state)=p_state)
      AND (needle IS NULL OR serial_tag ILIKE '%'||needle||'%'
           OR equipment_type ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT coalesce(jsonb_object_agg(equipment_type,states),'{}'::jsonb) FROM
      (SELECT equipment_type,jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT equipment_type,entry_state,count(*) AS state_total FROM scoped
          GROUP BY equipment_type,entry_state) d GROUP BY equipment_type) e),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.equipment_check_row(picked.equipment_id,today,false)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,tally_types,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',2,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,'type_counts',tally_types,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    'katip_official_verification',false,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_file_library(p_company uuid, p_kind text, p_query text, p_category text, p_state text, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_categories jsonb; tally_rows jsonb; matching_rows integer;
  catalog_rows jsonb; accept_rows jsonb;
BEGIN
  actor:=private_isg.require_file_library_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;

  IF p_kind='catalog' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('code',c.category,'ordinal',c.ordinal,'section',c.section)
      ORDER BY c.ordinal),'[]'::jsonb) INTO catalog_rows FROM private_isg.file_library_categories c;
    SELECT coalesce(jsonb_agg(jsonb_build_object('purpose',p.purpose,'extensions',to_jsonb(p.extensions),
      'max_bytes',p.max_bytes,'limit_approved',p.limit_approved) ORDER BY p.purpose),'[]'::jsonb)
      INTO accept_rows FROM private_isg.file_purposes p WHERE p.purpose IN ('company_document','evidence_photo');
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','categories',catalog_rows,
      'accepts',accept_rows,
      'scanners',(SELECT coalesce(jsonb_agg(jsonb_build_object('scanner',s.scanner,'assurance',s.assurance,
        'detects_malware',s.detects_malware) ORDER BY s.scanner),'[]'::jsonb) FROM private_isg.file_scanners s),
      'malware_scanning_available',
        (SELECT coalesce(bool_or(s.detects_malware),false) FROM private_isg.file_scanners s));
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.file_library_entries
      WHERE entry_id=p_id AND private_isg.expert_company_visible(owner_id,company_id,actor) AND (p_company IS NULL OR company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail',
      'row',private_isg.file_library_entry_row(p_id));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('pending','uploaded','scanning','clean','rejected',
    'scan_failed','promoted','expired','filed','working','unchecked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_category IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM private_isg.file_library_categories WHERE category=p_category) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived
  ), page AS (
    SELECT e.entry_id,e.company_id,s.name AS company_name,e.category,e.title,e.note,e.tags,
      CASE WHEN e.asset_id IS NOT NULL THEN 'promoted' ELSE i.state END AS entry_state,
      row_number() OVER (ORDER BY
        CASE WHEN e.asset_id IS NOT NULL THEN 4
          WHEN i.state='rejected' THEN 0 WHEN i.state='scan_failed' THEN 1
          WHEN i.state='expired' THEN 2 ELSE 3 END,
        e.created_at DESC,e.entry_id) AS ordinal
    FROM private_isg.file_library_entries e
    JOIN scope s ON s.id=e.company_id
    JOIN private_isg.upload_intents i ON i.intent_id=e.intent_id
    WHERE private_isg.expert_company_visible(e.owner_id,e.company_id,actor) AND NOT e.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_category IS NULL OR category=p_category)
      AND (p_state IS NULL OR entry_state=p_state
        OR (p_state='filed' AND entry_state='promoted')
        OR (p_state='working' AND entry_state IN ('pending','uploaded','scanning','clean'))
        OR (p_state='unchecked' AND entry_state IN ('scan_failed','expired')))
      AND (needle IS NULL OR title ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%' OR note ILIKE '%'||needle||'%' OR array_to_string(tags,' ') ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT coalesce(jsonb_object_agg(category,states),'{}'::jsonb) FROM
      (SELECT category,jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT category,entry_state,count(*) AS state_total FROM scoped
          GROUP BY category,entry_state) d GROUP BY category) e),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.file_library_entry_row(picked.entry_id)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,tally_categories,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,
    'counts',tally_all,'companies',tally_companies,'category_counts',tally_categories,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    'compliance_verdict',NULL,
    'malware_scanning_available',
      (SELECT coalesce(bool_or(s.detects_malware),false) FROM private_isg.file_scanners s));
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_module_editor(p_module text, p_company uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; snapshot jsonb; BEGIN
actor:=private_isg.module_editor_guard(p_module,p_company,false);
snapshot:=private_isg.module_editor_snapshot(p_module,p_company,p_id);
RETURN jsonb_build_object('snapshot',snapshot,'expected',md5(snapshot::text),'company_name',(SELECT name FROM public.companies WHERE id=p_company),
 'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]') FROM private_isg.workplaces WHERE company_id=p_company AND NOT is_archived),
 'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) ORDER BY full_name),'[]') FROM private_isg.employees WHERE company_id=p_company AND NOT is_archived),
 'documents',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',obligation_id,'name',title) ORDER BY title),'[]') FROM private_isg.document_obligations WHERE company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived),
 'plans',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',plan_id,'name',scope) ORDER BY scope),'[]') FROM private_isg.emergency_plan_versions WHERE company_id=p_company AND state='active' AND NOT is_deleted));
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_nonconformities(p_company uuid, p_kind text, p_query text, p_state text, p_after uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; rows jsonb; needle text;
BEGIN
  actor:=private_isg.require_nonconformity_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('list','detail','workplaces') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    rows:=private_isg.nonconformity_row(p_company,p_id);
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','row',rows);
  END IF;
  IF p_kind='workplaces' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'needs_review',w.needs_review)
      ORDER BY w.name),'[]'::jsonb) INTO rows
      FROM private_isg.workplaces w WHERE w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived;
    RETURN jsonb_build_object('schema_version',1,'kind','workplaces','rows',rows);
  END IF;
  IF p_state IS NOT NULL AND p_state NOT IN ('draft','open','assigned','in_progress','pending_verification',
      'closed','reopened','cancelled') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  needle:=nullif(btrim(coalesce(p_query,'')),'');
  -- 'row' is a keyword-shaped alias; name it something the parser cannot claim.
  SELECT coalesce(jsonb_agg(entry ORDER BY (entry->>'opened_on') DESC,(entry->>'id')),'[]'::jsonb) INTO rows FROM (
    SELECT jsonb_build_object('id',n.nonconformity_id,'workplace_id',n.workplace_id,'title',n.title,
      'severity',n.severity,'state',n.state,'version',n.version,'opened_on',n.opened_on,'due_on',n.due_on,
      'record_kind',n.record_kind,'risk_band',d.risk_band,
      'source_kind',n.source_kind,'source_ref',n.source_ref) AS entry
    FROM private_isg.nonconformities n
    LEFT JOIN private_isg.nonconformity_details d ON d.nonconformity_id=n.nonconformity_id
    WHERE n.company_id=p_company AND private_isg.expert_company_visible(n.owner_id,n.company_id,actor)
      AND (p_state IS NULL OR n.state=p_state)
      AND (needle IS NULL OR n.title ILIKE '%'||needle||'%')
      AND (p_after IS NULL OR n.nonconformity_id<>p_after)
    ORDER BY n.opened_on DESC,n.nonconformity_id LIMIT 200) page;
  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',rows,'legacy_findings_written',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_notice_feed(p_company uuid, p_scope text, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
        today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
        answer jsonb;
BEGIN
  IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false)
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('active','unread','all')
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_limit IS NULL OR p_limit<1 OR p_limit>200
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_company IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM public.companies c WHERE c.id=p_company AND private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived
        AND private_isg.p05_pilot_can_read(actor,c.id))
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  WITH due AS (
    SELECT r.*,r.kind||':'||r.record_id::text||':'||coalesce(r.due_on::text,'none') AS notice_key,
           (r.due_on-today) AS days
      FROM private_isg.notice_rows(actor,p_company) r
     WHERE r.due_on IS NOT NULL AND r.window_days IS NOT NULL
       AND r.due_on<=today+r.window_days),
  marked AS (
    SELECT d.*,m.read_at,m.dismissed_at,
           CASE WHEN d.days<0 THEN 'overdue' ELSE 'soon' END AS severity
      FROM due d LEFT JOIN private_isg.notice_marks m
        ON m.owner_id=actor AND m.context_key=coalesce(private_isg.expert_workspace()::text,'personal') AND m.notice_key=d.notice_key),
  shown AS (
    SELECT * FROM marked
     WHERE CASE p_scope
             WHEN 'all' THEN true
             WHEN 'unread' THEN dismissed_at IS NULL AND read_at IS NULL
             ELSE dismissed_at IS NULL END)
  SELECT jsonb_build_object(
    'today',today,'generated_at',clock_timestamp(),'company_id',p_company,'scope',p_scope,
    -- What the bell shows, and what it may never be mistaken for.
    'unread',(SELECT count(*) FROM marked WHERE dismissed_at IS NULL AND read_at IS NULL),
    'overdue',(SELECT count(*) FROM marked WHERE dismissed_at IS NULL AND severity='overdue'),
    'total',(SELECT count(*) FROM marked WHERE dismissed_at IS NULL),
    'dismissed',(SELECT count(*) FROM marked WHERE dismissed_at IS NOT NULL),
    'has_more',(SELECT count(*) FROM shown)>p_limit,
    'push_delivery_claimed',false,'dismiss_is_permanent',false,'records_changed',false,
    'rows',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'notice_key',s.notice_key,'kind',s.kind,'destination',s.destination,
        'company_id',s.company_id,'company_name',s.company_name,'record_id',s.record_id,
        'title',s.title,'due_on',s.due_on,'days',s.days,'severity',s.severity,
        'unread',s.read_at IS NULL,'dismissed',s.dismissed_at IS NOT NULL)
      ORDER BY (s.severity='overdue') DESC,s.due_on,s.company_name,s.kind,s.record_id)
      FROM (SELECT * FROM shown ORDER BY (severity='overdue') DESC,due_on,company_name,kind,record_id
             LIMIT p_limit) s),'[]'::jsonb))
  INTO answer;
  RETURN answer;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_ppe_handovers(p_company uuid, p_kind text, p_query text, p_state text, p_employee uuid, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; today date;
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_ppe_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog',
      'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)
          ORDER BY e.full_name),'[]'::jsonb)
        FROM private_isg.employees e
        WHERE p_company IS NOT NULL AND e.company_id=p_company AND NOT e.is_archived),
      'units',jsonb_build_array('piece','pair','set','metre','litre'),
      'conditions',jsonb_build_array('reusable','worn','damaged','lost'),
      -- No equipment catalogue ships: naming a fixed list of protective
      -- equipment would read as a statement of what the law requires, and no
      -- such list has been approved. The expert names the item.
      'item_catalogue_offered',false,
      -- The product holds no signed form, on any handover.
      'signed_copy_storage_available',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.live_ppe_handovers h
      JOIN public.companies c ON c.id=h.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor)
      WHERE h.handover_id=p_id AND (p_company IS NULL OR h.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.ppe_handover_row(p_id,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('outstanding','partial','closed') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), page AS (
    SELECT h.handover_id,h.company_id,s.name AS company_name,h.employee_id,e.full_name AS employee_name,
      h.item,h.handed_on,
      private_isg.ppe_handover_status(h.quantity,
        (SELECT coalesce(sum(r.quantity),0) FROM private_isg.ppe_returns r
          WHERE r.handover_id=h.handover_id)) AS entry_state,
      -- What is still out first: that is the question the page answers.
      row_number() OVER (ORDER BY
        CASE private_isg.ppe_handover_status(h.quantity,
          (SELECT coalesce(sum(r.quantity),0) FROM private_isg.ppe_returns r
            WHERE r.handover_id=h.handover_id))
          WHEN 'outstanding' THEN 0 WHEN 'partial' THEN 1 ELSE 2 END,
        h.handed_on DESC,s.name,e.full_name,h.handover_id) AS ordinal
    FROM private_isg.live_ppe_handovers h
    JOIN scope s ON s.id=h.company_id
    JOIN private_isg.employees e ON e.company_id=h.company_id AND e.id=h.employee_id
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_employee IS NULL OR employee_id=p_employee)
      AND (p_state IS NULL OR entry_state=p_state)
      AND (needle IS NULL OR item ILIKE '%'||needle||'%'
           OR employee_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.ppe_handover_row(picked.handover_id,false)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    -- A tally of what is still out, never a statement that anyone is
    -- adequately protected.
    'compliance_verdict',NULL,'signed_copy_storage_available',false,
    'health_records_tracked',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.read_risk_versions(p_company uuid, p_kind text, p_query text, p_state text, p_workplace uuid, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.risk_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_risk_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review,'hazard_class',w.hazard_class,
          'suggested_period_years',private_isg.risk_period_years_for_hazard_class(w.hazard_class)) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived),
      'kinds',jsonb_build_array('full','partial','metadata'),
      -- Which rules the product could attribute a period to. An empty list is
      -- the honest answer while no rule set has been approved, and the client
      -- then has only the expert's own number or the workplace's hazard
      -- class default, both marked as such.
      'rules','[]'::jsonb,
      'period_defaults_offered',false,
      'expert_period_source','unapproved_fixture',
      'expert_period_needs_review',true,
      'analysis_is_not_an_assessment',true,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.risk_assessments a
      JOIN public.companies c ON c.id=a.company_id AND private_isg.expert_company_visible(c.user_id,c.id,actor) AND private_isg.p05_pilot_can_read(actor,c.id)
      WHERE a.assessment_id=p_id AND (p_company IS NULL OR a.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.risk_assessment_row(p_id,today,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('never_assessed','period_unknown','expired','due_soon','valid',
    'current','untracked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND private_isg.p05_pilot_can_read(actor,c.id) AND NOT c.is_archived
  ), page AS (
    SELECT a.assessment_id,a.company_id,s.name AS company_name,a.workplace_id,w.name AS workplace_name,
      private_isg.risk_assessment_status(a.current_version,a.current_version>0,a.valid_until,notice,today) AS entry_state,
      a.valid_until,
      -- Worst first: what ran out, then what was never assessed, then what has
      -- no period, then what is due.
      row_number() OVER (ORDER BY
        CASE private_isg.risk_assessment_status(a.current_version,a.current_version>0,a.valid_until,notice,today)
          WHEN 'expired' THEN 0 WHEN 'never_assessed' THEN 1 WHEN 'period_unknown' THEN 2
          WHEN 'due_soon' THEN 3 ELSE 4 END,
        a.valid_until NULLS FIRST,s.name,w.name,a.assessment_id) AS ordinal
    FROM private_isg.risk_assessments a
    JOIN scope s ON s.id=a.company_id
    JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.workplace_id
    WHERE private_isg.expert_company_visible(a.owner_id,a.company_id,actor) AND private_isg.p05_pilot_can_read(actor,a.company_id) AND NOT w.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.risk_assessment_group(entry_state)=p_state)
      AND (needle IS NULL OR workplace_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.risk_assessment_row(picked.assessment_id,today,false)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    -- A tally of tracked assessments, never a statement that any workplace is
    -- compliant, and never a claim that an analysis is an assessment.
    'compliance_verdict',NULL,'analysis_is_not_an_assessment',true,'health_records_tracked',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_appointment_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'emergency_ppe'); END IF;
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.appointment_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_checklist_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'risk_nonconformity'); END IF;
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.checklist_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'personnel'); END IF;
  IF p_company IS NULL OR p_write IS NULL OR NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_write THEN
    IF NOT private_isg.p05_pilot_account_enabled(actor,true) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro')
      AND status IN ('active','trialing','grace_period')
      AND (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_document_tracking_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'files'); END IF;
  PERFORM private_isg.document_tracking_gate(p_write);
  IF p_company IS NULL OR NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_write THEN
    IF NOT private_isg.p05_pilot_account_enabled(actor,true) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_drill_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'emergency_ppe'); END IF;
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.drill_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_emergency_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'emergency_ppe'); END IF;
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.emergency_plan_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_equipment_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'equipment'); END IF;
  PERFORM private_isg.equipment_check_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF NOT private_isg.p05_pilot_can_read(actor,p_company) OR
       NOT private_isg.p05_pilot_account_enabled(actor,true) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    IF NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    -- The account-wide read is still a pilot surface: an account with no pilot
    -- enrolment does not get an empty board, it gets the closed answer.
    IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_file_library_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'files'); END IF;
  PERFORM private_isg.file_library_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_nonconformity_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'risk_nonconformity'); END IF;
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='nonconformity' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_write THEN
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_ppe_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'emergency_ppe'); END IF;
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.ppe_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.require_risk_company(p_company uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN RETURN private_isg.expert_require_company(p_company,p_write,'risk_nonconformity'); END IF;
  PERFORM private_isg.risk_version_gate(p_write);
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.statistics_read(p_company uuid, p_months integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
 first_day date; overview jsonb; companies jsonb; ids uuid[]; result jsonb; findings jsonb:=NULL; docs jsonb:=NULL; raw_docs jsonb;
 c uuid; states jsonb; available boolean;
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_months IS NULL OR p_months NOT IN (1,3,6,12) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 IF p_company IS NOT NULL THEN PERFORM private_isg.require_company(p_company,false); END IF;
 first_day:=(date_trunc('month',today::timestamp)-make_interval(months=>p_months-1))::date;
 overview:=public.isg_pilot_overview_v1(NULL);
 SELECT coalesce(jsonb_agg(x ORDER BY x->>'name'),'[]'),coalesce(array_agg((x->>'id')::uuid),'{}') INTO companies,ids
 FROM jsonb_array_elements(overview->'companies') x WHERE NOT (x->>'is_archived')::boolean
 AND (p_company IS NULL OR (x->>'id')::uuid=p_company);
 IF p_company IS NOT NULL AND cardinality(ids)=0 THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 -- One company projection per event, then distinct event/person keys across companies.
 WITH training AS MATERIALIZED (
  SELECT r.id,r.company_id,coalesce(r.session_id,r.id) AS event_id,
   (r.starts_at AT TIME ZONE 'Europe/Istanbul')::date AS day
  FROM private_isg.pilot_training_records r LEFT JOIN private_isg.pilot_training_sessions s ON s.id=r.session_id
  WHERE private_isg.expert_company_visible(r.owner_id,r.company_id,actor) AND r.company_id=ANY(ids) AND r.state='completed'
   AND (r.session_id IS NULL OR (private_isg.expert_session_visible(s.owner_id,s.id,actor) AND s.deleted_at IS NULL))
   AND r.starts_at>=first_day::timestamp AT TIME ZONE 'Europe/Istanbul'
   AND r.starts_at<(today+1)::timestamp AT TIME ZONE 'Europe/Istanbul'
 ), events AS (SELECT event_id,min(day) AS day FROM training GROUP BY event_id), analysis AS MATERIALIZED (
  SELECT a.id,(coalesce(a.completed_at,a.created_at) AT TIME ZONE 'Europe/Istanbul')::date AS day
  FROM public.analyses a WHERE private_isg.expert_company_visible(a.user_id,a.company_id,actor) AND a.kind='photo' AND a.status='completed'
   AND (a.company_id=ANY(ids) OR (p_company IS NULL AND a.company_id IS NULL))
   AND coalesce(a.completed_at,a.created_at)>=first_day::timestamp AT TIME ZONE 'Europe/Istanbul'
   AND coalesce(a.completed_at,a.created_at)<(today+1)::timestamp AT TIME ZONE 'Europe/Istanbul'
  UNION ALL
  SELECT a.id,(a.created_at AT TIME ZONE 'Europe/Istanbul')::date FROM private_isg.workspace_analyses a
   WHERE a.workspace_id=private_isg.expert_workspace() AND a.company_id=ANY(ids)
    AND a.created_at>=first_day::timestamp AT TIME ZONE 'Europe/Istanbul'
    AND a.created_at<(today+1)::timestamp AT TIME ZONE 'Europe/Istanbul'
 ), months AS (SELECT generate_series(first_day::timestamp,date_trunc('month',today::timestamp),interval '1 month')::date AS month)
 SELECT jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'months',p_months,
  'from_day',first_day,'today',today,'generated_at',clock_timestamp(),
  'companies',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',x->'id','name',x->'name','personnel',x->'personnel_count','workplaces',x->'workplace_count','hazard',x->'hazard_class') ORDER BY x->>'name'),'[]') FROM jsonb_array_elements(overview->'companies') x WHERE NOT (x->>'is_archived')::boolean),
  'company_count',cardinality(ids),'personnel',(SELECT coalesce(sum((x->>'personnel_count')::int),0) FROM jsonb_array_elements(companies) x),
  'workplaces',(SELECT coalesce(sum((x->>'workplace_count')::int),0) FROM jsonb_array_elements(companies) x),
  'analyses',(SELECT count(*) FROM analysis),'trainings',(SELECT count(DISTINCT event_id) FROM training),
  'trained_people',(SELECT count(DISTINCT p.employee_id) FROM training t JOIN private_isg.pilot_training_participants p ON p.training_id=t.id AND p.company_id=t.company_id),
  'training_enrollments',(SELECT count(DISTINCT (t.event_id,p.employee_id)) FROM training t JOIN private_isg.pilot_training_participants p ON p.training_id=t.id AND p.company_id=t.company_id),
  'series',(SELECT jsonb_agg(jsonb_build_object('month',m.month,'analyses',(SELECT count(*) FROM analysis a WHERE date_trunc('month',a.day::timestamp)::date=m.month),
   'trainings',(SELECT count(*) FROM events t WHERE date_trunc('month',t.day::timestamp)::date=m.month)) ORDER BY m.month) FROM months m)
 ) INTO result;
 -- Optional modules may not yet be installed on the narrow pilot. NULL means unavailable, never zero.
 IF to_regclass('private_isg.nonconformities') IS NOT NULL AND to_regprocedure('private_isg.require_nonconformity_company(uuid,boolean)') IS NOT NULL THEN
  EXECUTE 'SELECT coalesce(bool_or(read_enabled),false) FROM private_isg.rollout WHERE feature=''nonconformity''' INTO available;
  IF available THEN
   FOREACH c IN ARRAY ids LOOP EXECUTE 'SELECT private_isg.require_nonconformity_company($1,false)' USING c; END LOOP;
   EXECUTE $q$ SELECT jsonb_build_object(
    'open',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened')),
    'overdue',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND due_on<$3),
    'pending',count(*) FILTER(WHERE state='pending_verification'),
    'opened',count(*) FILTER(WHERE state NOT IN ('draft','cancelled') AND opened_on BETWEEN $4 AND $3),
    'closed',count(*) FILTER(WHERE state='closed' AND closed_on BETWEEN $4 AND $3),
    'severity',jsonb_build_object('critical',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND severity='critical'),
     'high',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND severity='high'),
     'medium',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND severity='medium'),
     'low',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND severity='low')))
    FROM private_isg.nonconformities n WHERE private_isg.expert_company_visible(owner_id,company_id,$1) AND company_id=ANY($2) AND coalesce(to_jsonb(n)->>'record_kind','nonconformity')='nonconformity' $q$
    INTO findings USING actor,ids,today,first_day;
  END IF;
 END IF;
 IF to_regprocedure('private_isg.read_document_portfolio(text,text,uuid,text[],integer,integer)') IS NOT NULL THEN
  BEGIN
   EXECUTE 'SELECT private_isg.read_document_portfolio(NULL,NULL,NULL,NULL,1,0)' INTO raw_docs;
   SELECT jsonb_build_object('valid',coalesce(sum((x->'counts'->>'valid')::int),0),'missing',coalesce(sum((x->'counts'->>'missing')::int),0),
    'due_soon',coalesce(sum((x->'counts'->>'due_soon')::int),0),'expired',coalesce(sum((x->'counts'->>'expired')::int),0))
   INTO docs FROM jsonb_array_elements(raw_docs->'companies') x WHERE (x->>'id')::uuid=ANY(ids);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'FEATURE_UNAVAILABLE' THEN RAISE; END IF;
  END;
 END IF;
 RETURN result||jsonb_build_object('findings',findings,'documents',docs);
END $function$
;

CREATE OR REPLACE FUNCTION public.isg_pilot_file_sources_v1(p_entry uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); f private_isg.file_library_entries; answer jsonb;
BEGIN
 IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 SELECT * INTO f FROM private_isg.file_library_entries WHERE entry_id=p_entry AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
 IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF; IF f.company_id IS NULL THEN RETURN '[]'::jsonb; END IF; IF NOT private_isg.p05_pilot_can_read(actor,f.company_id) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 WITH links(kind,id,title) AS (
 SELECT 'completed_drill',record_id,scenario FROM private_isg.pilot_completed_drills WHERE company_id=f.company_id AND NOT is_deleted AND (asset_id=f.asset_id OR f.asset_id=ANY(photo_ids))
 UNION ALL SELECT 'personnel_certificate',record_id,title FROM private_isg.pilot_personnel_certificates WHERE company_id=f.company_id AND NOT is_deleted AND asset_id=f.asset_id
 UNION ALL SELECT 'approved_notebook',record_id,title FROM private_isg.pilot_notebook_images WHERE company_id=f.company_id AND NOT is_deleted AND asset_id=f.asset_id
 UNION ALL SELECT 'site_visit',visit_id,expert_note FROM private_isg.site_visits WHERE company_id=f.company_id AND NOT is_deleted AND visit_asset_id=f.asset_id
 UNION ALL SELECT 'board',meeting_id,'Kurul toplantısı' FROM private_isg.board_meetings WHERE company_id=f.company_id AND NOT is_deleted AND minutes_asset_id=f.asset_id
 UNION ALL SELECT 'emergency_plan',plan_id,scope FROM private_isg.emergency_plan_versions WHERE company_id=f.company_id AND NOT is_deleted AND asset_id=f.asset_id
 UNION ALL SELECT 'katip_contract',contract_id,counterparty FROM private_isg.katip_contracts WHERE company_id=f.company_id AND NOT is_deleted AND asset_id=f.asset_id
 UNION ALL SELECT 'risk_assessment',assessment_id,'Risk değerlendirmesi' FROM private_isg.risk_assessments t WHERE company_id=f.company_id AND (to_jsonb(t)->>'asset_id')::uuid=f.asset_id
 UNION ALL SELECT 'equipment',e.equipment_id,e.serial_tag FROM private_isg.equipment_inspections i JOIN private_isg.equipment_items e ON e.equipment_id=i.equipment_id WHERE e.company_id=f.company_id AND NOT e.is_archived AND i.evidence_asset_id=f.asset_id)
 SELECT coalesce(jsonb_agg(jsonb_build_object('kind',kind,'record_id',id,'source_id',id,'title',title,'company_id',f.company_id,'company_name',(SELECT name FROM public.companies WHERE id=f.company_id),'status','undated','due_on',NULL)),'[]') INTO answer FROM links;
 RETURN answer;
END $function$
;
CREATE OR REPLACE FUNCTION public.isg_pilot_followup_v1(p_company uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_query text DEFAULT ''::text, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); answer jsonb; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
 IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF p_company IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies WHERE id=p_company AND private_isg.expert_company_visible(user_id,id,actor) AND NOT is_archived AND private_isg.p05_pilot_can_read(actor,id)) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 OR length(p_query)>200 OR (p_status IS NOT NULL AND p_status NOT IN ('current','soon','expired','undated')) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 WITH raw AS MATERIALIZED (SELECT r.*,CASE WHEN due_on IS NULL THEN 'undated' WHEN due_on<today THEN 'expired' WHEN due_on<=today+coalesce(window_days,30) THEN 'soon' ELSE 'current' END status FROM private_isg.pilot_followup_rows(actor,p_company) r),
 filtered AS (SELECT * FROM raw WHERE (p_status IS NULL OR status=p_status) AND (coalesce(p_query,'')='' OR title ILIKE '%'||p_query||'%' OR company_name ILIKE '%'||p_query||'%'))
 SELECT jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'today',today,
 'current',(SELECT count(*) FROM raw WHERE status='current'),'soon',(SELECT count(*) FROM raw WHERE status='soon'),'expired',(SELECT count(*) FROM raw WHERE status='expired'),'undated',(SELECT count(*) FROM raw WHERE status='undated'),
 'has_more',(SELECT count(*) FROM filtered)>p_offset+30,
 'rows',coalesce((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object('source_id',CASE WHEN t.kind='training' THEN (SELECT x.id FROM private_isg.pilot_training_sessions x WHERE private_isg.expert_session_visible(x.owner_id,x.id,actor) AND x.deleted_at IS NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(x.education->'scopes') sc WHERE sc->>'id'=t.record_id::text) LIMIT 1) ELSE t.record_id END) ORDER BY t.due_on NULLS LAST,t.company_name,t.kind,t.record_id) FROM (SELECT * FROM filtered ORDER BY due_on NULLS LAST,company_name,kind,record_id OFFSET p_offset LIMIT 30) t),'[]')) INTO answer;
 RETURN answer;
END $function$
;
CREATE OR REPLACE FUNCTION public.isg_pilot_module_tracking_v1(p_company uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); answer jsonb; today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_company IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies c WHERE c.id=p_company AND private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
WITH scoped AS MATERIALIZED (SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND (p_company IS NULL OR c.id=p_company) AND private_isg.p05_pilot_can_read(actor,c.id)),
kinds(kind,module) AS (VALUES ('katip_contract','katip_contract'),('annual_work_plan','annual_work_plan'),('annual_work_item','annual_work_plan'),('board','board'),('board_decision','board'),('site_visit','site_visit'),('work_permit','work_permit'),('contractor','contractor'),('emergency_plan','emergency_plan'),('drill','drill'),('appointment','appointment'),('ppe','ppe'),('checklist_run','checklist')),
records AS (SELECT t.company_id, 'checklist_run'::text kind, t.state='open' pending, NULL::date due_on, false review FROM private_isg.checklist_runs t JOIN scoped c ON c.id=t.company_id WHERE t.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'katip_contract'::text kind, (false) pending, (t.ends_before-1) due_on, (t.ends_before IS NULL) review FROM private_isg.katip_contracts t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'annual_work_plan'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.annual_work_plans t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'annual_work_item'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.annual_work_plan_items t JOIN private_isg.annual_work_plans p ON p.plan_id=t.plan_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted UNION ALL SELECT t.company_id company_id, 'board'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.board_meetings t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'board_decision'::text kind, (t.state='open') pending, (CASE WHEN t.state='open' THEN t.due_on END) due_on, (false) review FROM private_isg.board_decisions t JOIN private_isg.board_meetings p ON p.meeting_id=t.meeting_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted AND p.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'site_visit'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.site_visits t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'work_permit'::text kind, (t.state='draft') pending, (NULL::date) due_on, (false) review FROM private_isg.work_permit_forms t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'contractor'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.contractor_organizations t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_archived UNION ALL SELECT t.company_id company_id, 'emergency_plan'::text kind, (false) pending, (t.valid_until) due_on, (t.valid_until IS NULL) review FROM private_isg.emergency_plan_versions t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'drill'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.drill_records t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'appointment'::text kind, (false) pending, (t.ends_before-1) due_on, (false) review FROM private_isg.appointments t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'ppe'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.ppe_handovers t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted),
summary AS (
 SELECT c.id company_id,c.name company_name,k.kind,
 CASE WHEN k.kind='checklist_run' THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='nonconformity'),false) ELSE coalesce(m.read_enabled,false) AND coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='modules'),false) END available,
 count(r.kind) total,count(r.kind) FILTER(WHERE r.pending) pending,
 count(r.kind) FILTER(WHERE r.due_on<today) overdue,
 count(r.kind) FILTER(WHERE r.due_on BETWEEN today AND today+30) upcoming,
 count(r.kind) FILTER(WHERE r.review) review,
 min(r.due_on) FILTER(WHERE r.due_on>=today) next_on
 FROM scoped c CROSS JOIN kinds k LEFT JOIN private_isg.module_registry m ON m.module=k.module
 LEFT JOIN records r ON r.company_id=c.id AND r.kind=k.kind
 GROUP BY c.id,c.name,k.kind,m.read_enabled)
SELECT jsonb_build_object('today',today,'generated_at',clock_timestamp(),'company_id',p_company,'rows',coalesce(jsonb_agg(jsonb_build_object(
 'company_id',company_id,'company_name',company_name,'kind',kind,'available',available,
 'total',CASE WHEN available THEN total END,'pending',CASE WHEN available THEN pending END,
 'overdue',CASE WHEN available THEN overdue END,'upcoming',CASE WHEN available THEN upcoming END,
 'review',CASE WHEN available THEN review END,'next_on',CASE WHEN available THEN next_on END)
 ORDER BY company_name,company_id,kind),'[]'::jsonb)) INTO answer FROM summary;
RETURN answer;
END $function$
;
CREATE OR REPLACE FUNCTION public.isg_pilot_module_tracking_v2(p_company uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); answer jsonb; today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_company IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies c WHERE c.id=p_company AND private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
WITH scoped AS MATERIALIZED (SELECT c.id,c.name FROM public.companies c WHERE private_isg.expert_company_visible(c.user_id,c.id,actor) AND NOT c.is_archived AND (p_company IS NULL OR c.id=p_company) AND private_isg.p05_pilot_can_read(actor,c.id)),
kinds(kind,module) AS (VALUES ('katip_contract','katip_contract'),('annual_work_plan','annual_work_plan'),('annual_work_item','annual_work_plan'),('board','board'),('board_decision','board'),('site_visit','site_visit'),('work_permit','work_permit'),('contractor','contractor'),('emergency_plan','emergency_plan'),('drill','drill'),('appointment','appointment'),('ppe','ppe'),('checklist_run','checklist'),('personnel_certificate','personnel_certificate')),
records AS (SELECT t.company_id, 'drill'::text kind, false pending,t.valid_until due_on,false review FROM private_isg.pilot_completed_drills t JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted
 UNION ALL SELECT t.company_id,'personnel_certificate',false,t.valid_until,false FROM private_isg.pilot_personnel_certificates t JOIN scoped c ON c.id=t.company_id JOIN private_isg.employees e ON e.id=t.employee_id WHERE NOT t.is_deleted AND NOT e.is_archived
 UNION ALL SELECT t.company_id, 'checklist_run'::text kind, t.state='open' pending, NULL::date due_on, false review FROM private_isg.checklist_runs t JOIN scoped c ON c.id=t.company_id WHERE t.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'katip_contract'::text kind, (false) pending, (t.ends_before-1) due_on, (t.ends_before IS NULL) review FROM private_isg.katip_contracts t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'annual_work_plan'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.annual_work_plans t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'annual_work_item'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.annual_work_plan_items t JOIN private_isg.annual_work_plans p ON p.plan_id=t.plan_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted UNION ALL SELECT t.company_id company_id, 'board'::text kind, (t.state='planned') pending, (CASE WHEN t.state='planned' THEN t.planned_on END) due_on, (false) review FROM private_isg.board_meetings t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT p.company_id company_id, 'board_decision'::text kind, (t.state='open') pending, (CASE WHEN t.state='open' THEN t.due_on END) due_on, (false) review FROM private_isg.board_decisions t JOIN private_isg.board_meetings p ON p.meeting_id=t.meeting_id JOIN scoped c ON c.id=p.company_id WHERE NOT t.is_deleted AND NOT p.is_deleted AND p.state<>'cancelled' UNION ALL SELECT t.company_id company_id, 'site_visit'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.site_visits t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'work_permit'::text kind, (t.state='draft') pending, (NULL::date) due_on, (false) review FROM private_isg.work_permit_forms t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'contractor'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.contractor_organizations t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_archived UNION ALL SELECT t.company_id company_id, 'emergency_plan'::text kind, (false) pending, (t.valid_until) due_on, (t.valid_until IS NULL) review FROM private_isg.emergency_plan_versions t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted AND t.state='active' UNION ALL SELECT t.company_id company_id, 'drill'::text kind, false pending, NULL::date due_on, (false) review FROM private_isg.drill_records t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'appointment'::text kind, (false) pending, (t.ends_before-1) due_on, (false) review FROM private_isg.appointments t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted UNION ALL SELECT t.company_id company_id, 'ppe'::text kind, (false) pending, (NULL::date) due_on, (false) review FROM private_isg.ppe_handovers t  JOIN scoped c ON c.id=t.company_id WHERE NOT t.is_deleted),
summary AS (
 SELECT c.id company_id,c.name company_name,k.kind,
 CASE WHEN k.kind='checklist_run' THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='nonconformity'),false) ELSE coalesce(m.read_enabled,false) AND coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='modules'),false) END available,
 count(r.kind) total,count(r.kind) FILTER(WHERE r.pending) pending,
 count(r.kind) FILTER(WHERE r.due_on<today) overdue,
 count(r.kind) FILTER(WHERE r.due_on BETWEEN today AND today+30) upcoming,
 count(r.kind) FILTER(WHERE r.review) review,
 min(r.due_on) FILTER(WHERE r.due_on>=today) next_on
 FROM scoped c CROSS JOIN kinds k LEFT JOIN private_isg.module_registry m ON m.module=k.module
 LEFT JOIN records r ON r.company_id=c.id AND r.kind=k.kind
 GROUP BY c.id,c.name,k.kind,m.read_enabled)
SELECT jsonb_build_object('today',today,'generated_at',clock_timestamp(),'company_id',p_company,'rows',coalesce(jsonb_agg(jsonb_build_object(
 'company_id',company_id,'company_name',company_name,'kind',kind,'available',available,
 'total',CASE WHEN available THEN total END,'pending',CASE WHEN available THEN pending END,
 'overdue',CASE WHEN available THEN overdue END,'upcoming',CASE WHEN available THEN upcoming END,
 'review',CASE WHEN available THEN review END,'next_on',CASE WHEN available THEN next_on END)
 ORDER BY company_name,company_id,kind),'[]'::jsonb)) INTO answer FROM summary;
RETURN answer;
END $function$
;


CREATE FUNCTION private_isg.expert_rpc(p_workspace uuid,p_function text,p_arguments jsonb) RETURNS jsonb
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
  IF NOT p_function=ANY(ARRAY['isg_pilot_notice_mark_v1','isg_pilot_file_library_mutate_v2','isg_appointments_mutate_v1','isg_checklists_mutate_v1','isg_directory_mutate_v1','isg_document_tracking_mutate_v1','isg_drills_mutate_v1','isg_emergency_plans_mutate_v1','isg_equipment_checks_mutate_v1','isg_nonconformity_mutate_v1','isg_personnel_mutate_v1','isg_pilot_module_mutate_v1','isg_pilot_process_mutate_v1','isg_pilot_training_certificate_v1','isg_pilot_training_record_v2','isg_pilot_training_record_v3','isg_ppe_mutate_v1','isg_risk_versions_mutate_v1','isg_appointments_read_v1','isg_checklists_read_v1','isg_directory_read_v1','isg_document_portfolio_v1','isg_document_tracking_read_v1','isg_drills_read_v1','isg_emergency_plans_read_v1','isg_equipment_checks_read_v1','isg_file_library_read_v1','isg_nonconformity_read_v1','isg_personnel_read_v1','isg_pilot_employee_learning_v1','isg_pilot_file_library_read_v2','isg_pilot_file_sources_v1','isg_pilot_followup_v1','isg_pilot_module_editor_v1','isg_pilot_module_tracking_v1','isg_pilot_module_tracking_v2','isg_pilot_notice_feed_v1','isg_pilot_overview_v1','isg_pilot_overview_v2','isg_pilot_process_attachment_v1','isg_pilot_process_documents_v1','isg_pilot_process_read_v1','isg_pilot_process_references_v1','isg_pilot_training_detail_v3','isg_pilot_training_read_v1','isg_pilot_training_sessions_v2','isg_pilot_training_sessions_v3','isg_pilot_visit_summary_v1','isg_ppe_form_v1','isg_ppe_read_v1','isg_risk_versions_read_v1','isg_statistics_v1']) THEN
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
CREATE FUNCTION public.isg_expert_rpc_v1(p_workspace uuid,p_function text,p_arguments jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 SELECT private_isg.expert_rpc(p_workspace,p_function,p_arguments)
$$;
REVOKE ALL ON FUNCTION private_isg.expert_rpc(uuid,text,jsonb),public.isg_expert_rpc_v1(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.expert_rpc(uuid,text,jsonb),public.isg_expert_rpc_v1(uuid,text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';

-- Persist shared-domain writes with tenant ownership and the real actor.
ALTER TABLE private_isg.job_roles ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.job_roles ADD CONSTRAINT job_roles_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.job_roles ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.job_roles ADD CONSTRAINT job_roles_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.employee_assignments ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.employee_assignments ADD CONSTRAINT employee_assignments_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.employee_assignments ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.employee_assignments ADD CONSTRAINT employee_assignments_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.workplace_context_versions ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.workplace_context_versions ADD CONSTRAINT workplace_context_versions_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.workplace_context_versions ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.workplace_context_versions ADD CONSTRAINT workplace_context_versions_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.contractor_organizations ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.contractor_organizations ADD CONSTRAINT contractor_organizations_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.contractor_organizations ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.contractor_organizations ADD CONSTRAINT contractor_organizations_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.contractor_engagements ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.contractor_engagements ADD CONSTRAINT contractor_engagements_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.contractor_engagements ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.contractor_engagements ADD CONSTRAINT contractor_engagements_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.company_curriculum_versions ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.company_curriculum_versions ADD CONSTRAINT company_curriculum_versions_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.company_curriculum_versions ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.company_curriculum_versions ADD CONSTRAINT company_curriculum_versions_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.documents ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.documents ADD CONSTRAINT documents_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.documents ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.documents ADD CONSTRAINT documents_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.document_versions ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.document_obligations ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.document_obligations ADD CONSTRAINT document_obligations_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.document_obligations ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.document_obligations ADD CONSTRAINT document_obligations_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.document_obligation_records ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.document_obligation_records ADD CONSTRAINT document_obligation_records_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.document_obligation_records ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.document_obligation_records ADD CONSTRAINT document_obligation_records_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.pilot_completed_drills ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.pilot_completed_drills ADD CONSTRAINT pilot_completed_drills_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.pilot_completed_drills ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.pilot_completed_drills ADD CONSTRAINT pilot_completed_drills_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.pilot_notebook_images ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.pilot_notebook_images ADD CONSTRAINT pilot_notebook_images_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.pilot_notebook_images ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.pilot_notebook_images ADD CONSTRAINT pilot_notebook_images_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);
ALTER TABLE private_isg.pilot_personnel_certificates ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id);
ALTER TABLE private_isg.pilot_personnel_certificates ADD CONSTRAINT pilot_personnel_certificates_expert_company_fk FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id);
ALTER TABLE private_isg.pilot_personnel_certificates ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.pilot_personnel_certificates ADD CONSTRAINT pilot_personnel_certificates_expert_owner_check CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR workspace_id IS NOT NULL);

CREATE FUNCTION private_isg.expert_write_scope() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace uuid:=private_isg.expert_workspace(); actor uuid; data jsonb:=to_jsonb(NEW);
 company uuid:=(data->>'company_id')::uuid; prior jsonb; patch jsonb;
BEGIN
 IF workspace IS NULL THEN RETURN NEW; END IF;
 actor:=private_isg.active_actor();
 IF company IS NULL THEN
  CASE TG_TABLE_NAME
   WHEN 'risk_assessment_versions','risk_source_links','risk_impacts' THEN SELECT company_id INTO company FROM private_isg.risk_assessments WHERE assessment_id=(data->>'assessment_id')::uuid;
   WHEN 'checklist_run_items' THEN SELECT company_id INTO company FROM private_isg.checklist_runs WHERE run_id=(data->>'run_id')::uuid;
   WHEN 'equipment_inspections' THEN SELECT company_id INTO company FROM private_isg.equipment_items WHERE equipment_id=(data->>'equipment_id')::uuid;
   WHEN 'annual_work_plan_items' THEN SELECT company_id INTO company FROM private_isg.annual_work_plans WHERE plan_id=(data->>'plan_id')::uuid;
   WHEN 'board_decisions' THEN SELECT company_id INTO company FROM private_isg.board_meetings WHERE meeting_id=(data->>'meeting_id')::uuid;
   WHEN 'document_versions' THEN SELECT company_id INTO company FROM private_isg.documents WHERE document_id=(data->>'document_id')::uuid;
   WHEN 'ppe_returns' THEN SELECT company_id INTO company FROM private_isg.ppe_handovers WHERE handover_id=(data->>'handover_id')::uuid;
   WHEN 'pilot_training_sessions','pilot_training_session_revisions' THEN
    PERFORM private_isg.workspace_require_member(workspace,ARRAY['owner','admin','expert'],true);
   ELSE RAISE EXCEPTION 'COMPANY_SCOPE_REQUIRED';
  END CASE;
 END IF;
 IF company IS NOT NULL THEN PERFORM private_isg.workspace_require_company(workspace,company,true); END IF;
 IF TG_OP='UPDATE' THEN
  prior:=to_jsonb(OLD);
  IF (prior->>'workspace_id')::uuid IS DISTINCT FROM workspace
    OR prior->>'company_id' IS DISTINCT FROM data->>'company_id'
    OR prior->>'owner_id' IS DISTINCT FROM data->>'owner_id' THEN RAISE EXCEPTION 'IMMUTABLE_SCOPE'; END IF;
 END IF;
 IF data->>'workspace_id' IS NOT NULL AND (data->>'workspace_id')::uuid<>workspace THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 patch:=jsonb_build_object('workspace_id',workspace);
 IF data ? 'company_id' THEN patch:=patch||jsonb_build_object('company_id',company); END IF;
 IF data ? 'owner_id' THEN patch:=patch||jsonb_build_object('owner_id',NULL); END IF;
 IF data ? 'created_by_user_id' THEN patch:=patch||jsonb_build_object('created_by_user_id',
  CASE WHEN TG_OP='UPDATE' THEN (prior->>'created_by_user_id')::uuid ELSE actor END); END IF;
 IF data ? 'updated_by_user_id' THEN patch:=patch||jsonb_build_object('updated_by_user_id',actor); END IF;
 IF data ? 'recorded_by_user_id' THEN patch:=patch||jsonb_build_object('recorded_by_user_id',actor); END IF;
 NEW:=jsonb_populate_record(NEW,patch);
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.expert_write_scope() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.workplaces FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.departments FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.employees FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.job_roles FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.employee_assignments FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.workplace_context_versions FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.contractor_organizations FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.contractor_engagements FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.risk_assessments FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.risk_assessment_versions FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.risk_source_links FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.nonconformities FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.checklist_runs FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.checklist_run_items FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.emergency_plan_versions FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.drill_records FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.ppe_handovers FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.ppe_returns FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.appointments FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.equipment_items FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.equipment_inspections FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.equipment_inspection_rules FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.annual_work_plans FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.annual_work_plan_items FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.board_meetings FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.board_decisions FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.katip_contracts FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.site_visits FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.pilot_training_sessions FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.pilot_training_records FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.pilot_training_participants FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.pilot_training_session_revisions FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.company_curriculum_versions FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.documents FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.document_versions FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.document_obligations FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.document_obligation_records FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.pilot_completed_drills FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.pilot_notebook_images FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();
CREATE TRIGGER aa_expert_write_scope BEFORE INSERT OR UPDATE ON private_isg.pilot_personnel_certificates FOR EACH ROW EXECUTE FUNCTION private_isg.expert_write_scope();

-- Receipt actor_id is provenance, not company ownership. Company and actor
-- authorization is rechecked before every replay by the shared domain APIs.
DO $receipts$
DECLARE item record;
BEGIN
 FOR item IN SELECT c.conname,c.conrelid FROM pg_catalog.pg_constraint c
 JOIN pg_catalog.pg_class t ON t.oid=c.conrelid JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
 WHERE n.nspname='private_isg' AND t.relname=ANY(ARRAY['appointment_receipts','checklist_receipts','document_tracking_receipts','drill_receipts','emergency_plan_receipts','equipment_check_receipts','file_library_receipts','nonconformity_receipts','personnel_receipts','pilot_training_receipts','ppe_receipts','risk_version_receipts','directory_events','personnel_audit'])
 AND c.contype='f' AND c.confrelid='public.companies'::regclass AND cardinality(c.conkey)=2 LOOP
  EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',item.conrelid::regclass,item.conname);
  EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY(company_id) REFERENCES public.companies(id)',item.conrelid::regclass,item.conname||'_company');
 END LOOP;
END $receipts$;

-- Existing validators and forms keep the same write contracts.
CREATE OR REPLACE FUNCTION private_isg.education_certificate(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); sid uuid:=(p_payload->>'session_id')::uuid; scope_id uuid:=(p_payload->>'scope_id')::uuid;
 person_id uuid:=(p_payload->>'person_id')::uuid; mutation uuid:=(p_payload->>'mutation_id')::uuid; action text:=p_payload->>'action';
 session private_isg.pilot_training_sessions; scope jsonb; person jsonb; issues jsonb; snapshot jsonb; tr jsonb; doc private_isg.documents;
 stored private_isg.document_versions; fingerprint bytea; prior private_isg.education_receipts; issued date; serial bigint; year_no integer;
 result jsonb; template text; reference text; new_version integer; number text; relevant_trainers jsonb; logo text:=nullif(p_payload->>'logo_png_base64',''); logo_bytes bytea;
BEGIN
 IF p_payload IS NULL OR octet_length(p_payload::text)>1048576 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 IF action='read' THEN
  SELECT * INTO doc FROM private_isg.documents WHERE documents.document_id=(p_payload->>'document_id')::uuid AND private_isg.expert_company_visible(owner_id,company_id,actor);
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  PERFORM private_isg.require_company(doc.company_id,false);
  SELECT * INTO stored FROM private_isg.document_versions WHERE document_versions.document_id=doc.document_id AND version=coalesce((p_payload->>'revision')::int,doc.current_version);
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'ready',true,'issues','[]'::jsonb,'document_id',doc.document_id,'revision',stored.version,'snapshot',stored.snapshot,'snapshot_hash',encode(stored.snapshot_sha256,'hex'));
 END IF;
 IF logo IS NOT NULL THEN
  IF length(logo)>350000 THEN RAISE EXCEPTION 'LOGO_INVALID'; END IF;
  BEGIN logo_bytes:=decode(logo,'base64'); EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'LOGO_INVALID'; END;
  IF octet_length(logo_bytes) NOT BETWEEN 33 AND 262144 OR substring(logo_bytes from 1 for 8) IS DISTINCT FROM decode('89504e470d0a1a0a','hex') THEN RAISE EXCEPTION 'LOGO_INVALID'; END IF;
 END IF;
 IF action IS NULL OR action NOT IN ('preview','issue') OR NOT private_isg.p05_pilot_account_enabled(actor,true) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 SELECT * INTO session FROM private_isg.pilot_training_sessions WHERE id=sid AND private_isg.expert_session_visible(owner_id,id,actor) FOR UPDATE;
 IF NOT FOUND OR session.deleted_at IS NOT NULL OR session.education IS NULL THEN RAISE EXCEPTION 'EDUCATION_DETAILS_REQUIRED'; END IF;
 SELECT x INTO scope FROM jsonb_array_elements(session.education->'scopes') x WHERE (x->>'id')::uuid=scope_id;
 IF scope IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 PERFORM private_isg.require_company((scope->>'company_id')::uuid,true);
 SELECT x INTO person FROM jsonb_array_elements(scope->'participants') x WHERE (x->>'id')::uuid=person_id;
 IF person IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF action='issue' THEN
  IF mutation IS NULL OR NOT coalesce((SELECT enabled FROM private_isg.education_controls WHERE key='certificate_v1'),false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
  fingerprint:=sha256(convert_to(p_payload::text,'UTF8'));
  SELECT * INTO prior FROM private_isg.education_receipts WHERE owner_id=actor AND mutation_id=mutation;
  IF FOUND THEN IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF; RETURN prior.response; END IF;
 END IF;
 IF session.version IS DISTINCT FROM (p_payload->>'expected_version')::bigint THEN RAISE EXCEPTION 'VERSION_CONFLICT'; END IF;
 issued:=coalesce((p_payload->>'issued_on')::date,(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date);
 IF NOT isfinite(issued) OR issued<(scope->>'held_on')::date OR issued>(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date THEN RAISE EXCEPTION 'DOCUMENT_DATE_INVALID'; END IF;
 issues:=scope->'issues';
 IF btrim(coalesce(person->>'job_title',''))='' THEN issues:=issues||jsonb_build_array('JOB_TITLE_MISSING'); END IF;
 IF btrim(coalesce(session.education->>'provider_name',''))='' THEN issues:=issues||jsonb_build_array('PROVIDER_MISSING'); END IF;
 SELECT coalesce(jsonb_agg(t),'[]') INTO relevant_trainers FROM jsonb_array_elements(session.education->'trainers') t WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(scope->'topics') topic WHERE topic->'trainer_ids' ? (t->>'id'));
 FOR tr IN SELECT value FROM jsonb_array_elements(relevant_trainers) LOOP
  IF btrim(coalesce(tr->>'title',''))='' THEN issues:=issues||jsonb_build_array('TRAINER_TITLE_MISSING'); END IF;
 END LOOP;
 SELECT coalesce(jsonb_agg(DISTINCT value),'[]') INTO issues FROM jsonb_array_elements(issues);
 template:=CASE WHEN scope->>'cycle' IN ('initial','periodic_repeat') THEN 'basic_training_certificate' ELSE 'training_record_certificate' END;
 snapshot:=jsonb_build_object('schema_version',1,'template_version',1,'theme_version',1,'completion_basis','expert_record','signature_status','prepared_for_signature',
  'source_session_id',sid,'source_session_revision',session.version,'person',person,'scope',scope-'participants','trainers',relevant_trainers,
  'provider_name',session.education->>'provider_name','title',CASE WHEN template='basic_training_certificate' THEN 'TEMEL EĞİTİM BELGESİ' ELSE session.title END,
  'logo_png_base64',logo,'issued_on',issued,'is_draft',true,'number','','revision',0,'document_type',template);
 IF action='preview' AND jsonb_array_length(issues)=0 THEN
  SELECT v.* INTO stored FROM private_isg.documents d JOIN private_isg.document_versions v ON v.document_id=d.document_id AND v.version=d.current_version
   WHERE private_isg.expert_company_visible(d.owner_id,d.company_id,actor) AND d.company_id=(scope->>'company_id')::uuid AND d.source_domain='training' AND d.template_code=template
   AND d.source_ref=sid::text||':'||scope_id::text||':'||person_id::text AND (v.snapshot->>'source_session_revision')::bigint=session.version;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'ready',true,'issues','[]'::jsonb,'document_id',stored.document_id,'revision',stored.version,'snapshot',stored.snapshot,'snapshot_hash',encode(stored.snapshot_sha256,'hex')); END IF;
 END IF;
 IF action='preview' OR jsonb_array_length(issues)>0 THEN
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'ready',false,'issues',issues,'snapshot',snapshot);
 END IF;
 reference:=sid::text||':'||scope_id::text||':'||person_id::text;
 INSERT INTO private_isg.document_templates(template_code,source_domain,title) VALUES(template,'training','Eğitim belgesi') ON CONFLICT DO NOTHING;
 -- This template is approved by the expert issuing it, never by a fabricated reviewer.
 INSERT INTO private_isg.document_template_versions(template_code,version,status,approved_by,approval_note,published_at)
 VALUES(template,1,'published',actor,'EDU-1.0 + user-approved expert-record scope; blank paper signatures',now()) ON CONFLICT DO NOTHING;
 INSERT INTO private_isg.documents(company_id,owner_id,workplace_id,source_domain,source_ref,template_code)
 VALUES((scope->>'company_id')::uuid,actor,(scope->>'workplace_id')::uuid,'training',reference,template)
 ON CONFLICT(company_id,source_domain,source_ref,template_code) DO NOTHING;
 SELECT * INTO doc FROM private_isg.documents WHERE company_id=(scope->>'company_id')::uuid AND source_domain='training' AND source_ref=reference AND template_code=template FOR UPDATE;
 SELECT * INTO stored FROM private_isg.document_versions v WHERE v.document_id=doc.document_id AND v.version=doc.current_version;
 IF FOUND AND (stored.snapshot->>'source_session_revision')::bigint=session.version THEN
  snapshot:=stored.snapshot; new_version:=stored.version;
 ELSE
  year_no:=extract(year FROM issued)::int;
  PERFORM pg_advisory_xact_lock(hashtextextended('education-certificate:'||year_no::text,0));
  INSERT INTO private_isg.education_document_counters(scope,year,next_value)
  SELECT 'EG',year_no,coalesce(max(split_part(document_no,'-',3)::bigint),0)+1 FROM private_isg.document_versions
   WHERE document_no ~ ('^EG-'||year_no::text||'-[0-9]+$') ON CONFLICT DO NOTHING;
  UPDATE private_isg.education_document_counters SET next_value=next_value+1 WHERE education_document_counters.scope='EG' AND year=year_no RETURNING next_value-1 INTO serial;
  number:='EG-'||year_no::text||'-'||serial::text; new_version:=doc.current_version+1;
  snapshot:=snapshot||jsonb_build_object('is_draft',false,'number',number,'revision',new_version);
  INSERT INTO private_isg.document_versions(document_id,version,template_version,document_no,source_kind,snapshot,snapshot_sha256,finalized_by,finalized_at,mutation_id)
  VALUES(doc.document_id,new_version,1,number,'structured',snapshot,sha256(convert_to(snapshot::text,'UTF8')),actor,now(),mutation);
  UPDATE private_isg.documents SET current_version=new_version WHERE documents.document_id=doc.document_id;
 END IF;
 result:=jsonb_build_object('schema_version',1,'owner_id',actor,'ready',true,'issues','[]'::jsonb,'document_id',doc.document_id,'revision',new_version,
  'snapshot',snapshot,'snapshot_hash',encode(sha256(convert_to(snapshot::text,'UTF8')),'hex'));
 INSERT INTO private_isg.education_receipts(owner_id,mutation_id,request_hash,response) VALUES(actor,mutation,fingerprint,result);
 RETURN result;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.education_save(p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); sid uuid:=(p_payload->>'id')::uuid; old private_isg.pilot_training_sessions;
 prior private_isg.education_receipts; fingerprint bytea; action text:=p_payload->>'action'; package jsonb; scopes jsonb:='[]'; trainers jsonb:=p_payload->'trainers';
 s jsonb; scope jsonb; person jsonb; co uuid; companies uuid[]:='{}'; scope_ids uuid[]:='{}'; person_ids uuid[]:='{}'; record_id uuid; version_no bigint;
 result jsonb; training_title text:=btrim(p_payload->>'title'); provider text:=btrim(p_payload->>'provider_name'); tr jsonb; curriculum_key text;
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,true) OR NOT coalesce((SELECT enabled FROM private_isg.education_controls WHERE key='catalog_v1'),false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_mutation IS NULL OR p_payload IS NULL OR octet_length(p_payload::text)>2097152 OR action IS NULL OR action NOT IN ('save','delete','curriculum') THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':training-v2',0));
 IF sid IS NOT NULL THEN
  SELECT * INTO old FROM private_isg.pilot_training_sessions WHERE id=sid AND private_isg.expert_session_visible(owner_id,id,actor) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  FOR co IN SELECT company_id FROM private_isg.pilot_training_records WHERE session_id=sid ORDER BY company_id LOOP PERFORM private_isg.require_company(co,true); END LOOP;
 END IF;
 IF action<>'delete' THEN
  IF jsonb_typeof(p_payload->'scopes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'scopes') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  FOR co IN SELECT DISTINCT (value->>'company_id')::uuid FROM jsonb_array_elements(p_payload->'scopes') ORDER BY 1 LOOP PERFORM private_isg.require_company(co,true); companies:=array_append(companies,co); END LOOP;
  IF array_length(companies,1)>30 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 END IF;
 fingerprint:=sha256(convert_to(p_payload::text,'UTF8'));
 SELECT * INTO prior FROM private_isg.education_receipts WHERE owner_id=actor AND mutation_id=p_mutation;
 IF FOUND THEN IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF; RETURN prior.response; END IF;
 IF sid IS NOT NULL AND (old.deleted_at IS NOT NULL OR old.version IS DISTINCT FROM (p_payload->>'expected_version')::bigint) THEN RAISE EXCEPTION 'VERSION_CONFLICT'; END IF;
 IF action='delete' THEN
  IF sid IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.pilot_training_session_revisions(session_id,version,snapshot,changed_at) VALUES(sid,old.version,private_isg.pilot_training_session_row(sid),now());
  UPDATE private_isg.pilot_training_sessions SET deleted_at=now(),version=version+1 WHERE id=sid;
  UPDATE private_isg.pilot_training_records SET state='cancelled',version=version+1 WHERE session_id=sid;
 ELSE
  IF training_title IS NULL OR length(training_title) NOT BETWEEN 1 AND 200 OR provider IS NULL OR length(provider)>300 OR jsonb_typeof(trainers) IS DISTINCT FROM 'array' OR jsonb_array_length(trainers) NOT BETWEEN 1 AND 20
   OR length(coalesce(p_payload->>'notes',''))>2000 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  FOR tr IN SELECT value FROM jsonb_array_elements(trainers) LOOP
   IF tr->>'id' IS NULL OR length(btrim(coalesce(tr->>'name',''))) NOT BETWEEN 1 AND 200 OR length(coalesce(tr->>'title',''))>200 THEN RAISE EXCEPTION 'TRAINER_INVALID'; END IF;
  END LOOP;
  IF (SELECT count(*)<>count(DISTINCT value->>'id') FROM jsonb_array_elements(trainers)) THEN RAISE EXCEPTION 'TRAINER_INVALID'; END IF;
  SELECT content_package INTO package FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1;
  FOR s IN SELECT value FROM jsonb_array_elements(p_payload->'scopes') LOOP
   scope:=private_isg.education_scope(s||jsonb_build_object('_session_id',sid),package,trainers,action='curriculum');
   IF (scope->>'id')::uuid=ANY(scope_ids) THEN RAISE EXCEPTION 'SCOPE_INVALID'; END IF;
   scope_ids:=array_append(scope_ids,(scope->>'id')::uuid);
   FOR person IN SELECT value FROM jsonb_array_elements(scope->'participants') LOOP
    IF (person->>'id')::uuid=ANY(person_ids) THEN RAISE EXCEPTION 'PARTICIPANT_DUPLICATE'; END IF;
    person_ids:=array_append(person_ids,(person->>'id')::uuid);
   END LOOP;
   scopes:=scopes||jsonb_build_array(scope);
  END LOOP;
  IF action='curriculum' THEN
   IF jsonb_array_length(scopes)<>1 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
   scope:=scopes->0; co:=(scope->>'company_id')::uuid; curriculum_key:=(scope->>'cycle')||':'||(scope->>'group_name')||':'||(scope->>'hazard_class');
   PERFORM pg_advisory_xact_lock(hashtextextended(co::text||':'||(scope->>'workplace_id'),0));
   SELECT coalesce(max(version),0)+1 INTO version_no FROM private_isg.company_curriculum_versions WHERE company_id=co AND workplace_id=(scope->>'workplace_id')::uuid AND catalog_code='tr_isg_basic_2026';
   UPDATE private_isg.company_curriculum_versions SET state='superseded' WHERE company_id=co AND workplace_id=(scope->>'workplace_id')::uuid AND catalog_code='tr_isg_basic_2026' AND scope_key=curriculum_key AND state='active';
   INSERT INTO private_isg.company_curriculum_versions(company_id,owner_id,workplace_id,catalog_code,catalog_version,version,hazard_class,g4_topics,g4_lessons,state,education,scope_key)
   VALUES(co,actor,(scope->>'workplace_id')::uuid,'tr_isg_basic_2026',1,version_no,scope->>'hazard_class',scope->'topics',(scope->>'group4_minutes')::int/45,'active',scope-'participants'-'lessons',curriculum_key);
   result:=jsonb_build_object('schema_version',3,'owner_id',actor,'mutation_id',p_mutation,'curriculum_saved',true);
  ELSE
   IF sid IS NULL THEN
    INSERT INTO private_isg.pilot_training_sessions(owner_id,title,trainer,held_on) VALUES(actor,training_title,trainers->0->>'name',(scopes->0->>'held_on')::date) RETURNING id INTO sid;
   ELSE
    INSERT INTO private_isg.pilot_training_session_revisions(session_id,version,snapshot,changed_at) VALUES(sid,old.version,private_isg.pilot_training_session_row(sid),now());
    UPDATE private_isg.pilot_training_sessions SET version=version+1 WHERE id=sid;
   END IF;
   UPDATE private_isg.pilot_training_sessions SET title=training_title,trainer=trainers->0->>'name',notes=coalesce(p_payload->>'notes',''),
    held_on=(SELECT max((x->>'held_on')::date) FROM jsonb_array_elements(scopes) x),
    method=CASE WHEN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(scopes) x,LATERAL jsonb_array_elements(x->'topics') t WHERE t->>'method'='online') THEN 'face_to_face'
     WHEN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(scopes) x,LATERAL jsonb_array_elements(x->'topics') t WHERE t->>'method'='face_to_face') THEN 'online' ELSE 'mixed' END,
    education=jsonb_build_object('schema_version',1,'completion_basis','expert_record','provider_name',provider,'trainers',trainers,'scopes',scopes) WHERE id=sid;
   UPDATE private_isg.pilot_training_records SET state='cancelled' WHERE session_id=sid AND NOT(company_id=ANY(companies));
   FOREACH co IN ARRAY companies LOOP
    SELECT id INTO record_id FROM private_isg.pilot_training_records WHERE session_id=sid AND company_id=co;
    IF record_id IS NULL THEN
     INSERT INTO private_isg.pilot_training_records(company_id,owner_id,title,trainer,starts_at,duration_minutes,state,completed_at,session_id)
     VALUES(co,actor,training_title,trainers->0->>'name',(scopes->0->>'starts_at')::timestamptz,1,'completed',now(),sid) RETURNING id INTO record_id;
    END IF;
    UPDATE private_isg.pilot_training_records SET title=training_title,trainer=trainers->0->>'name',state='completed',completed_at=now(),version=version+1,
     starts_at=(SELECT min((x->>'starts_at')::timestamptz) FROM jsonb_array_elements(scopes) x WHERE (x->>'company_id')::uuid=co),
     duration_minutes=(SELECT max((x->>'instruction_minutes')::int+(x->>'break_minutes')::int) FROM jsonb_array_elements(scopes) x WHERE (x->>'company_id')::uuid=co),
     valid_until=(SELECT min((x->>'valid_until')::date) FROM jsonb_array_elements(scopes) x WHERE (x->>'company_id')::uuid=co),
     company_snapshot=(SELECT jsonb_build_object('company_name',name,'hazard_class',hazard_class) FROM public.companies WHERE id=co) WHERE id=record_id;
    DELETE FROM private_isg.pilot_training_participants WHERE training_id=record_id AND NOT(employee_id=ANY(person_ids));
    FOR person IN SELECT p FROM jsonb_array_elements(scopes) x,LATERAL jsonb_array_elements(x->'participants') p WHERE (x->>'company_id')::uuid=co LOOP
     INSERT INTO private_isg.pilot_training_participants(company_id,training_id,employee_id,employee_name,attended) VALUES(co,record_id,(person->>'id')::uuid,person->>'name',true)
     ON CONFLICT(training_id,employee_id) DO UPDATE SET employee_name=excluded.employee_name;
    END LOOP;
   END LOOP;
  END IF;
 END IF;
 IF result IS NULL THEN result:=jsonb_build_object('schema_version',3,'owner_id',actor,'mutation_id',p_mutation,'row',private_isg.pilot_training_session_row(sid)); END IF;
 INSERT INTO private_isg.education_receipts(owner_id,mutation_id,request_hash,response) VALUES(actor,p_mutation,fingerprint,result);
 RETURN result;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.education_scope(p_scope jsonb, p_package jsonb, p_trainers jsonb, p_curriculum boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE company uuid:=(p_scope->>'company_id')::uuid; workplace uuid:=(p_scope->>'workplace_id')::uuid;
 actor uuid; hazard text; co public.companies; wp private_isg.workplaces;
 preset jsonb; topics jsonb:='[]'; people jsonb:='[]'; issues jsonb:='[]'; t jsonb; person jsonb; lesson jsonb; allocation jsonb;
 canonical jsonb; code text; groupcode text; label text; mins integer; total integer:=0; g4 integer:=0; common integer:=0;
 breaks integer:=0; taught integer:=0; lesson_count integer:=0; assigned integer; method text; ids uuid[]:='{}'; topic_ids text[]:='{}'; trainer_id text;
 start_time timestamptz; finish_time timestamptz; first_time timestamptz; last_time timestamptz; previous_end timestamptz;
 person_id uuid; name text; previous_name text; job text; dept text; jobdate date; renewal integer:=0; cycle text:=p_scope->>'cycle'; row_id uuid;
BEGIN
 actor:=private_isg.require_company(company,true);
 SELECT * INTO co FROM public.companies WHERE id=company AND private_isg.expert_company_visible(user_id,id,actor);
 SELECT * INTO wp FROM private_isg.workplaces WHERE id=workplace AND company_id=company AND private_isg.expert_company_visible(owner_id,company_id,actor);
 IF NOT FOUND THEN RAISE EXCEPTION 'WORKPLACE_REQUIRED'; END IF;
 IF p_scope->>'id' IS NULL OR length(coalesce(p_scope->>'group_name',''))>160 OR cycle IS NULL
 OR cycle NOT IN ('initial','periodic_repeat','onboarding','knowledge_refresh','additional','workplace_specific','custom')
 OR jsonb_typeof(p_scope->'topics') IS DISTINCT FROM 'array' OR jsonb_array_length(p_scope->'topics') NOT BETWEEN 1 AND 150
 OR jsonb_typeof(p_scope->'participants') IS DISTINCT FROM 'array' OR jsonb_array_length(p_scope->'participants') NOT BETWEEN (CASE WHEN p_curriculum THEN 0 ELSE 1 END) AND 500
 OR jsonb_typeof(p_scope->'lessons') IS DISTINCT FROM 'array' OR jsonb_array_length(p_scope->'lessons') NOT BETWEEN (CASE WHEN p_curriculum THEN 0 ELSE 1 END) AND 200
 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 row_id:=(p_scope->>'id')::uuid;
 SELECT min((x->>'starts_at')::timestamptz),max((x->>'starts_at')::timestamptz+make_interval(mins=>(x->>'instruction_minutes')::int+(x->>'break_minutes')::int))
 INTO first_time,last_time FROM jsonb_array_elements(p_scope->'lessons') x;
 IF p_curriculum AND first_time IS NULL THEN first_time:=clock_timestamp(); last_time:=first_time; END IF;
 IF first_time IS NULL OR NOT isfinite(first_time) OR NOT isfinite(last_time) OR last_time>clock_timestamp()
 OR last_time-first_time>interval '366 days' THEN RAISE EXCEPTION 'TRAINING_DATE_INVALID'; END IF;
 jobdate:=(first_time AT TIME ZONE 'Europe/Istanbul')::date;
 SELECT c.hazard_class INTO hazard FROM private_isg.workplace_context_versions c
 WHERE c.company_id=company AND c.workplace_id=workplace AND c.starts_on<=jobdate AND (c.ends_before IS NULL OR c.ends_before>jobdate)
 ORDER BY c.starts_on DESC LIMIT 1;
 hazard:=coalesce(hazard,wp.hazard_class,co.hazard_class);
 SELECT value INTO preset FROM jsonb_array_elements(p_package->'presets')
 WHERE value->>'cycle'=cycle AND value->>'hazard_class'=CASE hazard WHEN 'medium' THEN 'hazardous' WHEN 'high' THEN 'very_hazardous' ELSE hazard END;
 IF cycle IN ('initial','periodic_repeat') THEN
  IF preset IS NULL THEN RAISE EXCEPTION 'PROFILE_UNAVAILABLE'; END IF;
  IF jobdate<'2026-04-02' THEN RAISE EXCEPTION 'RULE_DATE_UNSUPPORTED'; END IF;
  renewal:=(preset->>'renewal_interval_months')::integer;
 ELSIF cycle='custom' THEN
  renewal:=coalesce((p_scope->>'renewal_months')::integer,0);
  IF renewal NOT BETWEEN 0 AND 120 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_scope->'topics') child JOIN jsonb_array_elements(p_scope->'topics') parent ON child->>'parent_code'=parent->>'code') THEN RAISE EXCEPTION 'TOPIC_HIERARCHY_INVALID'; END IF;
 FOR t IN SELECT value FROM jsonb_array_elements(p_scope->'topics') LOOP
  code:=t->>'code'; groupcode:=t->>'group'; method:=t->>'method';
  IF code IS NULL OR code !~ '^[A-Za-z0-9_-]{1,80}$' OR code=ANY(topic_ids) OR groupcode IS NULL OR groupcode NOT IN ('G1','G2','G3','G4')
   OR coalesce(t->>'instruction_minutes','') !~ '^[0-9]{1,5}$' OR method IS NULL OR method NOT IN ('face_to_face','online')
   OR jsonb_typeof(t->'trainer_ids') IS DISTINCT FROM 'array' OR jsonb_array_length(t->'trainer_ids')>20 THEN RAISE EXCEPTION 'TOPIC_INVALID'; END IF;
  topic_ids:=array_append(topic_ids,code); mins:=(t->>'instruction_minutes')::integer;
  IF mins>1440 THEN RAISE EXCEPTION 'TOPIC_INVALID'; END IF;
  canonical:=NULL;
  IF preset IS NOT NULL AND groupcode<>'G4' THEN
   SELECT value INTO canonical FROM jsonb_array_elements(p_package->'topics') WHERE value->>'code'=coalesce(nullif(t->>'parent_code',''),code);
   IF canonical IS NULL OR canonical->>'group_code' IS DISTINCT FROM groupcode THEN RAISE EXCEPTION 'TOPIC_INVALID'; END IF;
  END IF;
  label:=coalesce(canonical->>'legal_label',canonical->>'title',t->>'title');
  IF nullif(t->>'parent_code','') IS NOT NULL THEN label:=t->>'title'; END IF;
  IF label IS NULL OR length(btrim(label)) NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'TOPIC_INVALID'; END IF;
  IF mins=0 THEN issues:=issues||jsonb_build_array('TOPIC_MINUTES_MISSING'); END IF;
  IF jsonb_array_length(t->'trainer_ids')=0 THEN issues:=issues||jsonb_build_array('TRAINER_SCOPE_MISSING'); END IF;
  FOR trainer_id IN SELECT jsonb_array_elements_text(t->'trainer_ids') LOOP
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_trainers) z WHERE z->>'id'=trainer_id) THEN RAISE EXCEPTION 'TRAINER_INVALID'; END IF;
  END LOOP;
  IF (preset IS NOT NULL AND groupcode='G4' AND hazard<>'low' OR cycle='onboarding') AND method='online' THEN issues:=issues||jsonb_build_array('FACE_TO_FACE_REQUIRED'); END IF;
  total:=total+mins; IF groupcode='G4' THEN g4:=g4+mins; ELSE common:=common+mins; END IF;
  topics:=topics||jsonb_build_array(jsonb_build_object('code',code,'parent_code',nullif(t->>'parent_code',''),'group',groupcode,'title',label,
   'instruction_minutes',mins,'method',method,'trainer_ids',t->'trainer_ids','legal_title',canonical->>'legal_label'));
 END LOOP;
 IF preset IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_package->'topics') required WHERE NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(topics) actual WHERE coalesce(actual->>'parent_code',actual->>'code')=required->>'code' AND (actual->>'instruction_minutes')::int>0))
  THEN issues:=issues||jsonb_build_array('REQUIRED_TOPIC_MISSING'); END IF;
  IF total<(preset->>'default_instruction_minutes')::int THEN issues:=issues||jsonb_build_array('TOTAL_TOO_SHORT'); END IF;
  IF g4<(preset->'group4'->>'budget_instruction_minutes')::int THEN issues:=issues||jsonb_build_array('GROUP4_TOO_SHORT'); END IF;
  IF cycle='initial' AND common<(preset->'common_groups_review_guard'->>'reference_instruction_minutes')::int THEN issues:=issues||jsonb_build_array('COMMON_GROUPS_TOO_SHORT'); END IF;
  IF length(btrim(coalesce(p_scope->>'context_note','')))=0 THEN issues:=issues||jsonb_build_array('GROUP4_CONTEXT_MISSING'); END IF;
 END IF;
 IF cycle='onboarding' AND total<120 THEN issues:=issues||jsonb_build_array('TOTAL_TOO_SHORT'); END IF;
 IF total<1 OR total>100000 OR length(coalesce(p_scope->>'context_note',''))>4000 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 FOR lesson IN SELECT value FROM jsonb_array_elements(p_scope->'lessons') ORDER BY (value->>'starts_at')::timestamptz LOOP
  IF coalesce(lesson->>'instruction_minutes','') !~ '^[0-9]{1,4}$' OR coalesce(lesson->>'break_minutes','') !~ '^[0-9]{1,4}$'
    OR jsonb_typeof(lesson->'allocations') IS DISTINCT FROM 'array' OR jsonb_array_length(lesson->'allocations')>150 THEN RAISE EXCEPTION 'LESSON_INVALID'; END IF;
  mins:=(lesson->>'instruction_minutes')::int; assigned:=0;
  IF mins NOT BETWEEN 1 AND 1440 OR (lesson->>'break_minutes')::int NOT BETWEEN 0 AND 720 THEN RAISE EXCEPTION 'LESSON_INVALID'; END IF;
  start_time:=(lesson->>'starts_at')::timestamptz;
  finish_time:=start_time+make_interval(mins=>mins+(lesson->>'break_minutes')::int);
  IF start_time IS NULL OR NOT isfinite(start_time) OR finish_time>clock_timestamp() OR start_time<previous_end THEN RAISE EXCEPTION 'LESSON_OVERLAP_OR_FUTURE'; END IF;
  previous_end:=finish_time;
  FOR allocation IN SELECT value FROM jsonb_array_elements(lesson->'allocations') LOOP
   IF allocation->>'topic_code' IS NULL OR coalesce(allocation->>'minutes','') !~ '^[0-9]{1,4}$' OR NOT (allocation->>'topic_code'=ANY(topic_ids)) THEN RAISE EXCEPTION 'LESSON_ALLOCATION_INVALID'; END IF;
   assigned:=assigned+(allocation->>'minutes')::int;
  END LOOP;
  IF assigned<>mins THEN issues:=issues||jsonb_build_array('LESSON_TOPIC_MISMATCH'); END IF;
  IF preset IS NOT NULL AND (mins<45 OR (lesson->>'break_minutes')::int<15) THEN issues:=issues||jsonb_build_array('LESSON_BREAK_INVALID'); END IF;
  taught:=taught+mins; breaks:=breaks+(lesson->>'break_minutes')::int; lesson_count:=lesson_count+1;
 END LOOP;
 FOR t IN SELECT value FROM jsonb_array_elements(topics) LOOP
  SELECT coalesce(sum((a->>'minutes')::int),0) INTO assigned FROM jsonb_array_elements(p_scope->'lessons') l,
   LATERAL jsonb_array_elements(l->'allocations') a WHERE a->>'topic_code'=t->>'code';
  IF assigned<>(t->>'instruction_minutes')::int THEN issues:=issues||jsonb_build_array('LESSON_TOPIC_MISMATCH'); END IF;
 END LOOP;
 IF taught<>total THEN issues:=issues||jsonb_build_array('LESSON_TOPIC_MISMATCH'); END IF;
 IF length(btrim(coalesce(p_scope->>'employer_name','')))=0 THEN issues:=issues||jsonb_build_array('EMPLOYER_MISSING'); END IF;
 IF coalesce(p_scope->>'employer_capacity','') NOT IN ('employer','representative') THEN issues:=issues||jsonb_build_array('EMPLOYER_CAPACITY_MISSING'); END IF;
 IF length(coalesce(p_scope->>'employer_name',''))>200 OR length(coalesce(p_scope->>'legal_name',''))>1000 OR length(coalesce(p_scope->>'location',''))>300 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 FOR person IN SELECT value FROM jsonb_array_elements(p_scope->'participants') LOOP
  person_id:=(person->>'id')::uuid;
  IF person_id IS NULL OR person_id=ANY(ids) THEN RAISE EXCEPTION 'PARTICIPANT_INVALID'; END IF;
  SELECT full_name INTO name FROM private_isg.employees WHERE id=person_id AND company_id=company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PARTICIPANT_UNAVAILABLE'; END IF;
  SELECT p->>'name' INTO previous_name FROM private_isg.pilot_training_sessions session, LATERAL jsonb_array_elements(session.education->'scopes') old_scope, LATERAL jsonb_array_elements(old_scope->'participants') p WHERE private_isg.expert_session_visible(session.owner_id,session.id,actor) AND session.id=(p_scope->>'_session_id')::uuid AND old_scope->>'id'=p_scope->>'id' AND p->>'id'=person_id::text ORDER BY session.id DESC LIMIT 1;
  name:=coalesce(previous_name,name);
  ids:=array_append(ids,person_id); job:=NULL; dept:=NULL;
  SELECT job_title_snapshot,department_name_snapshot INTO job,dept FROM private_isg.employee_assignments a
   WHERE a.company_id=company AND a.employee_id=person_id AND a.starts_on<=jobdate AND (a.ends_before IS NULL OR a.ends_before>jobdate) ORDER BY a.starts_on DESC LIMIT 1;
  job:=coalesce(nullif(btrim(person->>'job_title'),''),job,'');
  IF length(job)>300 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  people:=people||jsonb_build_array(jsonb_build_object('id',person_id,'name',name,'job_title',job,'department',coalesce(dept,'')));
 END LOOP;
 SELECT coalesce(jsonb_agg(DISTINCT value),'[]') INTO issues FROM jsonb_array_elements(issues);
 RETURN jsonb_build_object('id',row_id,'company_id',company,'workplace_id',workplace,'company_name',co.name,'workplace_name',wp.name,
  'logo_path',to_jsonb(co)->>'logo_path','legal_name',coalesce(nullif(btrim(p_scope->>'legal_name'),''),co.name),'hazard_class',hazard,'cycle',cycle,'group_name',coalesce(p_scope->>'group_name',''),
  'preset_code',preset->>'code','package_version',1,'context_note',coalesce(p_scope->>'context_note',''),'topics',topics,'lessons',p_scope->'lessons',
  'participants',people,'instruction_minutes',total,'break_minutes',breaks,'lesson_units',lesson_count,'group4_minutes',g4,'issues',issues,
  'starts_at',first_time,'ends_at',last_time,'held_on',(last_time AT TIME ZONE 'Europe/Istanbul')::date,
  'valid_until',CASE WHEN renewal>0 THEN ((last_time AT TIME ZONE 'Europe/Istanbul')::date+make_interval(months=>renewal))::date ELSE NULL END,
  'renewal_months',renewal,'employer_name',coalesce(p_scope->>'employer_name',''),'employer_capacity',coalesce(p_scope->>'employer_capacity','representative'),
  'location',coalesce(p_scope->>'location',''));
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_appointments(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.appointment_receipts;
  result jsonb; answer jsonb; appointment uuid; entry private_isg.appointments; asset uuid;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_appointment_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;
  allowed:=CASE p_action
    -- No qualification field of any kind: holding a role is not being
    -- qualified for it, and nothing here may say otherwise.
    WHEN 'record_appointment' THEN ARRAY['employee_id','kind','workplace_id','starts_on','ends_before',
      'basis','basis_note','asset_id']
    WHEN 'end_appointment' THEN ARRAY['appointment_id','ends_before']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-appointment:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.appointment_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='record_appointment' THEN
    IF p_payload->>'employee_id' IS NULL OR p_payload->>'kind' IS NULL OR
       p_payload->>'workplace_id' IS NULL OR p_payload->>'starts_on' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- Saying why the person holds the role is the point of the field.
    IF p_payload->>'basis' IS NULL OR p_payload->>'basis' NOT IN ('elected','appointed') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BASIS_REQUIRED'; END IF;
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    -- Only a clean, owned asset may be attached — the same rule every other
    -- module's asset_id enforces.
    IF p_payload->>'asset_id' IS NOT NULL THEN
      asset:=(p_payload->>'asset_id')::uuid;
      PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
        WHERE fa.asset_id=asset AND fa.scan_status='clean' AND fle.company_id=p_company AND private_isg.expert_company_visible(fle.owner_id,fle.company_id,actor);
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    END IF;
    answer:=private_isg.record_appointment(p_company,(p_payload->>'employee_id')::uuid,
      p_payload->>'kind',(p_payload->>'workplace_id')::uuid,
      (p_payload->>'starts_on')::date,(p_payload->>'ends_before')::date,NULL,stamp);
    appointment:=(answer->>'appointment_id')::uuid;
    UPDATE private_isg.appointments SET basis=p_payload->>'basis',
      basis_note=nullif(btrim(coalesce(p_payload->>'basis_note','')),''),
      asset_id=asset
      WHERE appointment_id=appointment;
  ELSE
    appointment:=(p_payload->>'appointment_id')::uuid;
    SELECT * INTO entry FROM private_isg.appointments
      WHERE appointment_id=appointment AND company_id=p_company FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_payload->>'ends_before' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.end_appointment(appointment,(p_payload->>'ends_before')::date,stamp);
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'appointment_id',appointment,
    'answer',answer,'row',private_isg.appointment_row(appointment,today));
  INSERT INTO private_isg.appointment_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_checklists(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.checklist_receipts;
  result jsonb; answer jsonb; run uuid; entry private_isg.checklist_runs;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_checklist_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;
  allowed:=CASE p_action
    WHEN 'draft_template' THEN ARRAY['title']
    WHEN 'set_item' THEN ARRAY['template_code','version','item_code','prompt','allows_not_applicable','position']
    WHEN 'remove_item' THEN ARRAY['template_code','version','item_code']
    -- No approver here: an expert approves their own list, and the boundary
    -- supplies who that is rather than letting the client name someone.
    WHEN 'publish_template' THEN ARRAY['template_code','version','approval_note']
    WHEN 'start_run' THEN ARRAY['workplace_id','template_code','started_on']
    -- `open_nonconformity` is its own field on purpose: a failing answer never
    -- becomes a record unless this says so.
    WHEN 'record_item' THEN ARRAY['run_id','item_code','result','note','open_nonconformity',
      'severity','due_on']
    WHEN 'submit_run' THEN ARRAY['run_id']
    WHEN 'cancel_run' THEN ARRAY['run_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-checklist:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.checklist_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='draft_template' THEN
    IF p_payload->>'title' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.draft_checklist_template(actor,p_payload->>'title',stamp);
  ELSIF p_action IN ('set_item','remove_item','publish_template') THEN
    IF p_payload->>'template_code' IS NULL OR p_payload->>'version' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- A product template is readable but never editable, and another account's
    -- is neither.
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,true);
    IF p_action='set_item' THEN
      IF p_payload->>'item_code' IS NULL OR p_payload->>'prompt' IS NULL OR
         p_payload->>'position' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.set_checklist_item(p_payload->>'template_code',(p_payload->>'version')::integer,
        p_payload->>'item_code',p_payload->>'prompt',
        coalesce((p_payload->>'allows_not_applicable')::boolean,true),
        (p_payload->>'position')::integer,stamp);
    ELSIF p_action='remove_item' THEN
      IF p_payload->>'item_code' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.remove_checklist_item(p_payload->>'template_code',
        (p_payload->>'version')::integer,p_payload->>'item_code');
    ELSE
      IF p_payload->>'approval_note' IS NULL OR btrim(p_payload->>'approval_note')='' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.publish_checklist_version(p_payload->>'template_code',
        (p_payload->>'version')::integer,actor,p_payload->>'approval_note',stamp);
    END IF;
  ELSIF p_action='start_run' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'template_code' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,false);
    answer:=private_isg.start_checklist_run(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'template_code',
      coalesce((p_payload->>'started_on')::date,today),stamp);
    run:=(answer->>'run_id')::uuid;
  ELSE
    run:=(p_payload->>'run_id')::uuid;
    SELECT * INTO entry FROM private_isg.checklist_runs
      WHERE run_id=run AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_action='record_item' THEN
      IF p_payload->>'item_code' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.record_run_item(run,p_payload->>'item_code',p_payload->>'result',
        nullif(btrim(coalesce(p_payload->>'note','')),''),NULL,
        coalesce((p_payload->>'open_nonconformity')::boolean,false),
        nullif(btrim(coalesce(p_payload->>'severity','')),''),
        (p_payload->>'due_on')::date,stamp);
    ELSIF p_action='submit_run' THEN
      answer:=private_isg.submit_checklist_run(run,stamp);
    ELSE
      answer:=private_isg.cancel_checklist_run(run,stamp);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'answer',answer,
    'run_id',run,'row',CASE WHEN run IS NOT NULL THEN private_isg.checklist_run_row(run,true) END,
    'auto_nonconformity',false);
  INSERT INTO private_isg.checklist_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_document_tracking(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.document_tracking_receipts;
  result jsonb; target uuid; expected bigint; current_version bigint; obligation private_isg.document_obligations;
  computed_until date; issued date; stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_document_tracking_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    WHEN 'add_obligation' THEN ARRAY['workplace_id','kind_code','title','basis','legal_ref',
      'validity_days','notice_days','responsible_contact','note']
    WHEN 'update_obligation' THEN ARRAY['obligation_id','expected_version','title','basis','legal_ref',
      'validity_days','notice_days','responsible_contact','note','workplace_id']
    WHEN 'archive_obligation' THEN ARRAY['obligation_id','expected_version']
    WHEN 'record_copy' THEN ARRAY['obligation_id','issued_on','valid_until','document_no','location_note']
    WHEN 'remove_copy' THEN ARRAY['obligation_id','record_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-document-tracking:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.document_tracking_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='add_obligation' THEN
    IF p_payload->>'kind_code' IS NULL OR p_payload->>'title' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF p_payload->>'workplace_id' IS NOT NULL THEN
      PERFORM 1 FROM private_isg.workplaces WHERE id=(p_payload->>'workplace_id')::uuid
        AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    END IF;
    INSERT INTO private_isg.document_obligations(company_id,owner_id,workplace_id,kind_code,title,basis,
      legal_ref,validity_days,notice_days,responsible_contact,note)
      VALUES(p_company,actor,(p_payload->>'workplace_id')::uuid,p_payload->>'kind_code',
        btrim(p_payload->>'title'),coalesce(p_payload->>'basis','expert'),
        nullif(btrim(coalesce(p_payload->>'legal_ref','')),''),
        (p_payload->>'validity_days')::integer,
        coalesce((p_payload->>'notice_days')::integer,30),
        nullif(btrim(coalesce(p_payload->>'responsible_contact','')),''),
        nullif(btrim(coalesce(p_payload->>'note','')),''))
      RETURNING obligation_id INTO target;
  ELSIF p_action IN ('update_obligation','archive_obligation') THEN
    target:=(p_payload->>'obligation_id')::uuid;
    expected:=(p_payload->>'expected_version')::bigint;
    SELECT * INTO obligation FROM private_isg.document_obligations
      WHERE obligation_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF expected IS NULL OR obligation.version<>expected THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF p_action='archive_obligation' THEN
      UPDATE private_isg.document_obligations SET is_archived=true,version=version+1,updated_at=stamp
        WHERE obligation_id=target;
    ELSE
      IF p_payload ? 'workplace_id' AND p_payload->>'workplace_id' IS NOT NULL THEN
        PERFORM 1 FROM private_isg.workplaces WHERE id=(p_payload->>'workplace_id')::uuid
          AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
      UPDATE private_isg.document_obligations SET
        title=coalesce(nullif(btrim(coalesce(p_payload->>'title','')),''),title),
        basis=coalesce(p_payload->>'basis',basis),
        legal_ref=CASE WHEN p_payload ? 'legal_ref'
          THEN nullif(btrim(coalesce(p_payload->>'legal_ref','')),'') ELSE legal_ref END,
        validity_days=CASE WHEN p_payload ? 'validity_days'
          THEN (p_payload->>'validity_days')::integer ELSE validity_days END,
        notice_days=coalesce((p_payload->>'notice_days')::integer,notice_days),
        responsible_contact=CASE WHEN p_payload ? 'responsible_contact'
          THEN nullif(btrim(coalesce(p_payload->>'responsible_contact','')),'') ELSE responsible_contact END,
        note=CASE WHEN p_payload ? 'note'
          THEN nullif(btrim(coalesce(p_payload->>'note','')),'') ELSE note END,
        workplace_id=CASE WHEN p_payload ? 'workplace_id'
          THEN (p_payload->>'workplace_id')::uuid ELSE workplace_id END,
        version=version+1,updated_at=stamp
        WHERE obligation_id=target;
    END IF;
  ELSIF p_action='record_copy' THEN
    target:=(p_payload->>'obligation_id')::uuid;
    SELECT * INTO obligation FROM private_isg.document_obligations
      WHERE obligation_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF obligation.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='OBLIGATION_ARCHIVED'; END IF;
    issued:=coalesce((p_payload->>'issued_on')::date,today);
    -- An explicit end date wins. Otherwise the obligation's own period decides,
    -- and an obligation without one produces a copy that does not expire.
    computed_until:=CASE
      WHEN p_payload ? 'valid_until' AND p_payload->>'valid_until' IS NOT NULL THEN (p_payload->>'valid_until')::date
      WHEN obligation.validity_days IS NOT NULL THEN issued+obligation.validity_days
      ELSE NULL END;
    INSERT INTO private_isg.document_obligation_records(obligation_id,company_id,owner_id,issued_on,
      valid_until,document_no,location_note,recorded_by,recorded_at,mutation_id)
      VALUES(target,p_company,actor,issued,computed_until,
        nullif(btrim(coalesce(p_payload->>'document_no','')),''),
        nullif(btrim(coalesce(p_payload->>'location_note','')),''),actor,stamp,p_mutation);
  ELSE
    target:=(p_payload->>'obligation_id')::uuid;
    PERFORM 1 FROM private_isg.document_obligations
      WHERE obligation_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    DELETE FROM private_isg.document_obligation_records
      WHERE record_id=(p_payload->>'record_id')::uuid AND obligation_id=target;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'operation_id',p_operation,
    'row',private_isg.document_obligation_row(p_company,target,today),'file_stored',false);
  INSERT INTO private_isg.document_tracking_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_drills(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.drill_receipts;
  result jsonb; answer jsonb; drill uuid; entry private_isg.drill_records;
  plan private_isg.emergency_plan_versions; snapshot jsonb;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_drill_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>16384 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;
  allowed:=CASE p_action
    -- No plan_version: the boundary pins the version in force, so a drill can
    -- never be aimed at a version the expert did not see.
    WHEN 'plan_drill' THEN ARRAY['plan_id','planned_on']
    WHEN 'record_result' THEN ARRAY['drill_id','performed_on','participants','observation','improvement']
    WHEN 'cancel_drill' THEN ARRAY['drill_id','reason']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-drill:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.drill_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='plan_drill' THEN
    IF p_payload->>'plan_id' IS NULL OR p_payload->>'planned_on' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- The plan must be this actor's, in force, and its workplace is the
    -- drill's: a drill cannot rehearse another workplace's plan.
    SELECT * INTO plan FROM private_isg.emergency_plan_versions
      WHERE plan_id=(p_payload->>'plan_id')::uuid AND company_id=p_company
        AND private_isg.expert_company_visible(owner_id,company_id,actor) AND state='active' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    answer:=private_isg.plan_drill(p_company,plan.workplace_id,plan.plan_id,plan.version,
      (p_payload->>'planned_on')::date,stamp);
    drill:=(answer->>'drill_id')::uuid;
  ELSE
    drill:=(p_payload->>'drill_id')::uuid;
    SELECT * INTO entry FROM private_isg.drill_records
      WHERE drill_id=drill AND company_id=p_company FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    -- The company is the caller's, but the plan behind the drill must be too.
    PERFORM 1 FROM private_isg.emergency_plan_versions
      WHERE plan_id=entry.plan_id AND version=entry.plan_version AND private_isg.expert_company_visible(owner_id,company_id,actor);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

    IF p_action='record_result' THEN
      IF p_payload->>'performed_on' IS NULL OR NOT p_payload ? 'participants' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      -- A drill held tomorrow has not been held.
      IF (p_payload->>'performed_on')::date>today THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERFORMED_IN_THE_FUTURE'; END IF;
      answer:=private_isg.record_drill_result(drill,(p_payload->>'performed_on')::date,
        p_payload->'participants',
        nullif(btrim(coalesce(p_payload->>'observation','')),''),
        nullif(btrim(coalesce(p_payload->>'improvement','')),''),stamp);
      -- Freeze who that was, as they are named now. The register may change
      -- afterwards; this record does not.
      IF NOT coalesce((answer->>'replayed')::boolean,false) THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)
            ORDER BY e.full_name),'[]'::jsonb) INTO snapshot
          FROM private_isg.employees e
          WHERE e.company_id=p_company
            AND e.id::text IN (SELECT value FROM jsonb_array_elements_text(p_payload->'participants') AS t(value));
        UPDATE private_isg.drill_records SET participant_snapshot=snapshot WHERE drill_id=drill;
      END IF;
    ELSE
      IF p_payload->>'reason' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.cancel_drill(drill,p_payload->>'reason',stamp);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'drill_id',drill,'answer',answer,
    'row',private_isg.drill_row(drill,today));
  INSERT INTO private_isg.drill_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_emergency_plans(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.emergency_plan_receipts;
  result jsonb; answer jsonb; plan uuid; team jsonb; asset uuid;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_emergency_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>16384 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    WHEN 'publish_plan' THEN ARRAY['plan_id','workplace_id','scope','prepared_on','valid_until',
      'team','review_note','asset_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-emergency:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.emergency_plan_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_payload->>'workplace_id' IS NULL OR p_payload->>'scope' IS NULL OR
     p_payload->>'prepared_on' IS NULL OR NOT p_payload ? 'team' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
    AND id=(p_payload->>'workplace_id')::uuid AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_payload->>'plan_id' IS NOT NULL THEN
    plan:=(p_payload->>'plan_id')::uuid;
    PERFORM 1 FROM private_isg.emergency_plan_versions
      WHERE plan_id=plan AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  IF (p_payload->>'prepared_on')::date>today THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PREPARED_IN_THE_FUTURE'; END IF;
  IF p_payload->>'asset_id' IS NOT NULL THEN
    asset:=(p_payload->>'asset_id')::uuid;
    PERFORM 1 FROM private_isg.file_library_entries WHERE asset_id=asset AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  team:=private_isg.emergency_team_snapshot(p_payload->'team');
  answer:=private_isg.publish_emergency_plan(p_company,(p_payload->>'workplace_id')::uuid,plan,
    p_payload->>'scope',(p_payload->>'prepared_on')::date,(p_payload->>'valid_until')::date,
    team,asset,nullif(btrim(coalesce(p_payload->>'review_note','')),''),stamp);
  plan:=(answer->>'plan_id')::uuid;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'plan_id',plan,'answer',answer,
    'row',private_isg.emergency_plan_row(plan,today,true));
  INSERT INTO private_isg.emergency_plan_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_equipment_checks(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.equipment_check_receipts;
  result jsonb; answer jsonb; target uuid; item private_isg.equipment_items;
  report private_isg.equipment_inspections;
  stamp timestamptz:=clock_timestamp(); today date; derived date; chosen date; inspection uuid; asset uuid;
BEGIN
  actor:=private_isg.require_equipment_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    WHEN 'set_rule' THEN ARRAY['equipment_type','period_months','period_source','exception_note']
    WHEN 'register_equipment' THEN ARRAY['workplace_id','equipment_type','serial_tag','acquired_on','location_note']
    WHEN 'update_equipment' THEN ARRAY['equipment_id','workplace_id','serial_tag','acquired_on','location_note']
    WHEN 'archive_equipment' THEN ARRAY['equipment_id']
    WHEN 'record_inspection' THEN ARRAY['equipment_id','performed_on','result','inspector',
      'external_ref','note','evidence_asset_id','next_due_on','katip_declared','katip_note']
    -- The date and the result are not here: they are what the report is.
    WHEN 'update_inspection' THEN ARRAY['equipment_id','inspection_id','inspector',
      'external_ref','note','evidence_asset_id','next_due_on','katip_declared','katip_note']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-equipment:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.equipment_check_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='set_rule' THEN
    IF p_payload->>'equipment_type' IS NULL OR p_payload->>'period_months' IS NULL OR
       p_payload->>'period_source' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.set_equipment_inspection_rule(p_company,p_payload->>'equipment_type',
      (p_payload->>'period_months')::integer,p_payload->>'period_source',
      nullif(btrim(coalesce(p_payload->>'exception_note','')),''),stamp);
    result:=jsonb_build_object('schema_version',3,'action',p_action,'rule',answer);
  ELSIF p_action='register_equipment' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'equipment_type' IS NULL OR
       p_payload->>'serial_tag' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM private_isg.ensure_equipment_period(p_company,p_payload->>'equipment_type',stamp);
    answer:=private_isg.register_equipment(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'equipment_type',p_payload->>'serial_tag',
      (p_payload->>'acquired_on')::date,stamp);
    target:=(answer->>'equipment_id')::uuid;
    IF NOT (answer->>'replayed')::boolean THEN
      UPDATE private_isg.equipment_items
        SET location_note=nullif(btrim(coalesce(p_payload->>'location_note','')),'')
        WHERE equipment_id=target;
    END IF;
    result:=jsonb_build_object('schema_version',3,'action',p_action,'equipment_id',target,
      'row',private_isg.equipment_check_row(target,today,true));
  ELSE
    target:=(p_payload->>'equipment_id')::uuid;
    SELECT * INTO item FROM private_isg.equipment_items
      WHERE equipment_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

    IF p_action='update_equipment' THEN
      IF p_payload ? 'workplace_id' THEN
        PERFORM 1 FROM private_isg.workplaces WHERE id=(p_payload->>'workplace_id')::uuid
          AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
      UPDATE private_isg.equipment_items SET
        workplace_id=coalesce((p_payload->>'workplace_id')::uuid,workplace_id),
        serial_tag=coalesce(private_isg.text_value(p_payload->>'serial_tag',100),serial_tag),
        acquired_on=CASE WHEN p_payload ? 'acquired_on' THEN (p_payload->>'acquired_on')::date ELSE acquired_on END,
        location_note=CASE WHEN p_payload ? 'location_note'
          THEN nullif(btrim(coalesce(p_payload->>'location_note','')),'') ELSE location_note END
        WHERE equipment_id=target;
    ELSIF p_action='archive_equipment' THEN
      UPDATE private_isg.equipment_items SET is_archived=true WHERE equipment_id=target;

    ELSIF p_action='update_inspection' THEN
      IF p_payload->>'inspection_id' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT * INTO report FROM private_isg.equipment_inspections
        WHERE inspection_id=(p_payload->>'inspection_id')::uuid AND equipment_id=target FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      -- Only a clean, owned asset may be attached — the same rule every other
      -- module's asset_id enforces.
      IF p_payload ? 'evidence_asset_id' AND p_payload->>'evidence_asset_id' IS NOT NULL THEN
        asset:=(p_payload->>'evidence_asset_id')::uuid;
        PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
          WHERE fa.asset_id=asset AND fa.scan_status='clean' AND fle.company_id=p_company AND private_isg.expert_company_visible(fle.owner_id,fle.company_id,actor);
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
      -- The date is measured against the report's own date and result, which
      -- this action cannot change.
      derived:=private_isg.equipment_period_due(p_company,item.equipment_type,
        report.performed_on,report.result);
      chosen:=CASE WHEN p_payload ? 'next_due_on' THEN (p_payload->>'next_due_on')::date
                   ELSE report.next_due_on END;
      IF chosen IS NOT NULL THEN
        IF chosen<=report.performed_on THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_BEFORE_REPORT'; END IF;
        IF report.result='fail' THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_ON_A_FAILED_CHECK'; END IF;
      END IF;
      UPDATE private_isg.equipment_inspections SET
        inspector=CASE WHEN p_payload ? 'inspector'
          THEN nullif(btrim(coalesce(p_payload->>'inspector','')),'') ELSE inspector END,
        external_ref=CASE WHEN p_payload ? 'external_ref'
          THEN nullif(btrim(coalesce(p_payload->>'external_ref','')),'') ELSE external_ref END,
        note=CASE WHEN p_payload ? 'note'
          THEN nullif(btrim(coalesce(p_payload->>'note','')),'') ELSE note END,
        evidence_asset_id=CASE WHEN p_payload ? 'evidence_asset_id' THEN asset ELSE evidence_asset_id END,
        next_due_on=chosen,
        -- Recomputed the same way it is on entry: a corrected date that lands
        -- on what the period produces reads as the period's answer again.
        due_source=CASE WHEN chosen IS NULL THEN NULL
          WHEN chosen=derived THEN 'period' ELSE 'expert' END,
        katip_assignment_declared=CASE WHEN p_payload ? 'katip_declared'
          THEN coalesce((p_payload->>'katip_declared')::boolean,false)
          ELSE katip_assignment_declared END,
        katip_declared_note=CASE
          WHEN p_payload ? 'katip_declared' AND NOT coalesce((p_payload->>'katip_declared')::boolean,false) THEN NULL
          WHEN p_payload ? 'katip_note' THEN nullif(btrim(coalesce(p_payload->>'katip_note','')),'')
          ELSE katip_declared_note END
        WHERE inspection_id=report.inspection_id;

    ELSE
      IF p_payload->>'performed_on' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF (p_payload->>'performed_on')::date>today THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERFORMED_IN_THE_FUTURE'; END IF;
      PERFORM private_isg.ensure_equipment_period(p_company,item.equipment_type,stamp);
      derived:=private_isg.equipment_period_due(p_company,item.equipment_type,
        (p_payload->>'performed_on')::date,p_payload->>'result');
      answer:=private_isg.record_equipment_inspection(target,(p_payload->>'performed_on')::date,
        p_payload->>'result',(p_payload->>'evidence_asset_id')::uuid,
        nullif(btrim(coalesce(p_payload->>'external_ref','')),''),
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
      inspection:=(answer->>'inspection_id')::uuid;
      IF NOT (answer->>'replayed')::boolean THEN
        chosen:=(p_payload->>'next_due_on')::date;
        IF chosen IS NOT NULL THEN
          IF chosen<=(p_payload->>'performed_on')::date THEN
            RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_BEFORE_REPORT'; END IF;
          IF p_payload->>'result'='fail' THEN
            RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_ON_A_FAILED_CHECK'; END IF;
        END IF;
        UPDATE private_isg.equipment_inspections SET
          inspector=nullif(btrim(coalesce(p_payload->>'inspector','')),''),
          next_due_on=coalesce(chosen,next_due_on),
          due_source=CASE
            WHEN coalesce(chosen,derived) IS NULL THEN NULL
            WHEN chosen IS NULL OR chosen=derived THEN 'period' ELSE 'expert' END,
          katip_assignment_declared=coalesce((p_payload->>'katip_declared')::boolean,false),
          katip_declared_note=CASE WHEN coalesce((p_payload->>'katip_declared')::boolean,false)
            THEN nullif(btrim(coalesce(p_payload->>'katip_note','')),'') END
          WHERE inspection_id=inspection;
      END IF;
    END IF;
    result:=jsonb_build_object('schema_version',3,'action',p_action,'equipment_id',target,
      'row',private_isg.equipment_check_row(target,today,true));
  END IF;

  INSERT INTO private_isg.equipment_check_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_module_editor(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; module text:=p_payload->>'module'; id uuid; snapshot jsonb; values_ jsonb:=p_payload->'values';
 fingerprint bytea; receipt private_isg.module_edit_receipts; result jsonb; document uuid; allowed text[]; place uuid; person uuid; total numeric;
BEGIN
actor:=private_isg.module_editor_guard(module,p_company,true);
IF p_action NOT IN ('update','delete','link_document') OR p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL
 OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>32768
 OR p_payload->>'id' IS NULL OR p_payload->>'expected' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('module','id','expected','values','document_id')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
id:=(p_payload->>'id')::uuid;
fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||p_mutation::text,8741));
SELECT * INTO receipt FROM private_isg.module_edit_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
IF FOUND THEN IF receipt.request_hash<>fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF; RETURN receipt.response; END IF;
snapshot:=private_isg.module_editor_snapshot(module,p_company,id);
IF md5(snapshot::text)<>p_payload->>'expected' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
IF p_action='link_document' THEN
 IF NOT p_payload ? 'document_id' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 document:=(p_payload->>'document_id')::uuid;
 IF document IS NOT NULL THEN
  PERFORM private_isg.require_document_tracking_company(p_company,false);
  PERFORM 1 FROM private_isg.document_obligations WHERE obligation_id=document AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 INSERT INTO private_isg.module_record_links(module,record_id,company_id,owner_id,obligation_id) VALUES(module,id,p_company,actor,document)
 ON CONFLICT ON CONSTRAINT module_record_links_pkey DO UPDATE SET obligation_id=excluded.obligation_id;
ELSIF p_action='delete' THEN
 IF module='emergency_plan' AND EXISTS(SELECT 1 FROM private_isg.drill_records WHERE plan_id=id AND NOT is_deleted) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPENDENT_RECORDS'; END IF;
IF module='emergency_plan' THEN UPDATE private_isg.emergency_plan_versions SET is_deleted=true WHERE plan_id=id AND company_id=p_company; END IF;
IF module='drill' THEN UPDATE private_isg.drill_records SET is_deleted=true WHERE drill_id=id AND company_id=p_company; END IF;
IF module='ppe' THEN UPDATE private_isg.ppe_handovers SET is_deleted=true WHERE handover_id=id AND company_id=p_company; END IF;
IF module='appointment' THEN UPDATE private_isg.appointments SET is_deleted=true WHERE appointment_id=id AND company_id=p_company; END IF;
ELSE
 IF jsonb_typeof(values_) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 allowed:=CASE module WHEN 'emergency_plan' THEN ARRAY['workplace_id','scope','prepared_on','valid_until','review_note','team_snapshot']
 WHEN 'drill' THEN ARRAY['plan_id','planned_on','performed_on','participants','observation','improvement']
 WHEN 'ppe' THEN ARRAY['employee_id','item','quantity','unit','handed_on','signed_copy_location']
 WHEN 'appointment' THEN ARRAY['employee_id','kind','scope_workplace_id','starts_on','ends_before','basis','basis_note','asset_id'] END;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(values_) k WHERE NOT k=ANY(allowed)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
 place:=coalesce((values_->>'workplace_id')::uuid,(values_->>'scope_workplace_id')::uuid);
 IF place IS NOT NULL THEN PERFORM 1 FROM private_isg.workplaces w WHERE w.id=place AND w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF; END IF;
 person:=(values_->>'employee_id')::uuid;
 IF person IS NOT NULL THEN PERFORM 1 FROM private_isg.employees e WHERE e.id=person AND e.company_id=p_company AND NOT e.is_archived FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF; END IF;
 IF module='emergency_plan' THEN
  IF (values_->>'prepared_on')::date>(now() AT TIME ZONE 'Europe/Istanbul')::date THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM private_isg.publish_emergency_plan(p_company,place,id,values_->>'scope',(values_->>'prepared_on')::date,
   (values_->>'valid_until')::date,private_isg.emergency_team_snapshot(values_->'team_snapshot'),NULL,nullif(btrim(values_->>'review_note'),''),clock_timestamp());
 ELSIF module='ppe' THEN
  SELECT coalesce(sum(quantity),0) INTO total FROM private_isg.ppe_returns WHERE handover_id=id;
  IF (values_->>'quantity')::numeric<total OR (values_->>'handed_on')::date>(now() AT TIME ZONE 'Europe/Istanbul')::date
   OR EXISTS(SELECT 1 FROM private_isg.ppe_returns WHERE handover_id=id AND returned_on<(values_->>'handed_on')::date)
   OR (total>0 AND ((values_->>'employee_id') IS DISTINCT FROM snapshot->>'employee_id' OR values_->>'unit' IS DISTINCT FROM snapshot->>'unit')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RETURN_CONFLICT'; END IF;
  UPDATE private_isg.ppe_handovers SET employee_id=person,item=btrim(values_->>'item'),quantity=(values_->>'quantity')::numeric,
   unit=values_->>'unit',handed_on=(values_->>'handed_on')::date,signed_copy_location=nullif(btrim(values_->>'signed_copy_location'),'') WHERE handover_id=id;
 ELSIF module='appointment' THEN
  IF values_->>'basis' NOT IN ('elected','appointed') OR values_->>'basis' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BASIS_REQUIRED'; END IF;
  -- Only a clean, owned asset may be attached — the same rule the emergency
  -- plan and katip_contract enforce.
  IF values_ ? 'asset_id' AND values_->>'asset_id' IS NOT NULL THEN
   PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
     WHERE fa.asset_id=(values_->>'asset_id')::uuid AND fa.scan_status='clean' AND fle.company_id=p_company AND private_isg.expert_company_visible(fle.owner_id,fle.company_id,actor);
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  UPDATE private_isg.appointments SET employee_id=person,kind=values_->>'kind',scope_workplace_id=place,
   starts_on=(values_->>'starts_on')::date,ends_before=(values_->>'ends_before')::date,basis=values_->>'basis',
   basis_note=nullif(btrim(values_->>'basis_note'),''),asset_id=nullif(values_->>'asset_id','')::uuid,updated_at=clock_timestamp() WHERE appointment_id=id;
 ELSIF module='drill' THEN
  PERFORM 1 FROM private_isg.emergency_plan_versions WHERE plan_id=(values_->>'plan_id')::uuid AND company_id=p_company AND state='active' AND NOT is_deleted FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF snapshot->>'state'='performed' THEN
   IF (values_->>'performed_on')::date>(now() AT TIME ZONE 'Europe/Istanbul')::date OR jsonb_typeof(values_->'participants') IS DISTINCT FROM 'array'
    OR jsonb_array_length(values_->'participants') NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(values_->'participants') p WHERE NOT EXISTS(SELECT 1 FROM private_isg.employees e WHERE e.company_id=p_company AND e.id::text=p AND NOT e.is_archived)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_OUT_OF_SCOPE'; END IF;
  END IF;
  UPDATE private_isg.drill_records SET plan_id=(values_->>'plan_id')::uuid,
   plan_version=(SELECT version FROM private_isg.emergency_plan_versions WHERE plan_id=(values_->>'plan_id')::uuid AND state='active' AND NOT is_deleted),
   workplace_id=(SELECT workplace_id FROM private_isg.emergency_plan_versions WHERE plan_id=(values_->>'plan_id')::uuid AND state='active' AND NOT is_deleted),
   planned_on=(values_->>'planned_on')::date,performed_on=CASE WHEN state='performed' THEN (values_->>'performed_on')::date ELSE NULL END,
   participants=CASE WHEN state='performed' THEN values_->'participants' ELSE NULL END,
   observation=values_->>'observation',improvement=values_->>'improvement',updated_at=clock_timestamp() WHERE drill_id=id;
 END IF;
END IF;
INSERT INTO private_isg.module_record_history(module,record_id,company_id,actor_id,operation,before_snapshot) VALUES(module,id,p_company,actor,p_action,snapshot);
result:=jsonb_build_object('id',id,'deleted',p_action='delete');
INSERT INTO private_isg.module_edit_receipts(actor_id,mutation_id,request_hash,response) VALUES(actor,p_mutation,fingerprint,result);
RETURN result;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_nonconformity(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.nonconformity_receipts;
  result jsonb; detail jsonb; resolved_severity text; resolved_kind text; target uuid;
  stamp timestamptz:=clock_timestamp();
BEGIN
  actor:=private_isg.require_nonconformity_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  allowed:=CASE p_action
    WHEN 'open_manual' THEN ARRAY['workplace_id','title','severity','opened_on','due_on','assignee','evidence_asset_ids']
    WHEN 'open_from_finding' THEN ARRAY['workplace_id','title','risk_band','severity','finding_id','opened_on','due_on']
    -- An expert-opinion item arrives unscored. There is deliberately no
    -- 'risk_band' key here: nothing can be mapped from a score that does not exist.
    WHEN 'open_from_expert_item' THEN ARRAY['workplace_id','title','severity','record_kind','item_id',
      'opened_on','due_on','assignee','description']
    WHEN 'open_detailed' THEN ARRAY['workplace_id','title','severity','record_kind','opened_on','due_on','assignee',
      'description','control_measure','legislation_ref','responsible_contact','risk_method',
      'fk_probability','fk_frequency','fk_severity','m5_probability','m5_severity','evidence_asset_ids']
    WHEN 'set_detail' THEN ARRAY['nonconformity_id','description','control_measure','legislation_ref',
      'responsible_contact','risk_method','fk_probability','fk_frequency','fk_severity','m5_probability','m5_severity']
    WHEN 'transition' THEN ARRAY['nonconformity_id','expected_version','to_state','reason','assignee','closed_on']
    WHEN 'add_action' THEN ARRAY['nonconformity_id','description','assignee','due_on','external_ref']
    WHEN 'verify' THEN ARRAY['nonconformity_id','outcome','verified_on','note']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-nonconformity:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.nonconformity_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action IN ('open_manual','open_from_finding','open_from_expert_item','open_detailed') THEN
    -- An explicitly chosen severity wins; otherwise the legacy band maps across,
    -- and an unreadable band refuses instead of guessing the lowest one.
    resolved_severity:=CASE WHEN p_payload ? 'severity' THEN p_payload->>'severity'
      ELSE private_isg.severity_for_risk_band(p_payload->>'risk_band') END;
    -- Only the two screens that can say so may file an improvement; the older
    -- two actions carry no record_kind key at all and stay nonconformities.
    resolved_kind:=coalesce(p_payload->>'record_kind','nonconformity');
    result:=private_isg.open_nonconformity_record(p_company,(p_payload->>'workplace_id')::uuid,
      CASE p_action WHEN 'open_from_finding' THEN 'legacy_finding'
                    WHEN 'open_from_expert_item' THEN 'legacy_expert_item' ELSE 'manual' END,
      CASE p_action WHEN 'open_from_finding' THEN p_payload->>'finding_id'
                    WHEN 'open_from_expert_item' THEN p_payload->>'item_id' ELSE NULL END,
      p_payload->>'title',resolved_severity,resolved_kind,
      coalesce((p_payload->>'opened_on')::date,(stamp AT TIME ZONE 'Europe/Istanbul')::date),
      (p_payload->>'due_on')::date,p_payload->>'assignee',stamp);
    target:=(result->>'nonconformity_id')::uuid;
    -- A replayed open must not overwrite the detail that is already there.
    IF (result->>'replayed')::boolean IS NOT TRUE AND p_action IN ('open_detailed','open_from_expert_item')
       AND p_payload ?| ARRAY['description','control_measure','legislation_ref','responsible_contact','risk_method',
         'fk_probability','fk_frequency','fk_severity','m5_probability','m5_severity'] THEN
      detail:=private_isg.set_nonconformity_detail(target,p_payload->>'description',
        p_payload->>'control_measure',p_payload->>'legislation_ref',p_payload->>'responsible_contact',
        p_payload->>'risk_method',(p_payload->>'fk_probability')::numeric,(p_payload->>'fk_frequency')::numeric,
        (p_payload->>'fk_severity')::numeric,(p_payload->>'m5_probability')::integer,
        (p_payload->>'m5_severity')::integer,stamp);
      result:=result||jsonb_build_object('detail',detail);
    END IF;
    -- Only clean, owned assets may be attached — the same rule every other
    -- module's asset_id enforces. A replay must not silently re-attach a
    -- different set than what was actually cleared the first time.
    IF (result->>'replayed')::boolean IS NOT TRUE AND p_action IN ('open_manual','open_detailed')
       AND p_payload ? 'evidence_asset_ids' AND jsonb_array_length(p_payload->'evidence_asset_ids')>0 THEN
      IF jsonb_array_length(p_payload->'evidence_asset_ids')>3 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_payload->'evidence_asset_ids') a
          WHERE NOT EXISTS(SELECT 1 FROM private_isg.file_assets fa
            JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
            WHERE fa.asset_id=a::uuid AND fa.scan_status='clean'
              AND fle.company_id=p_company AND private_isg.expert_company_visible(fle.owner_id,fle.company_id,actor))) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      UPDATE private_isg.nonconformities SET evidence_asset_ids=
          (SELECT array_agg(a::uuid) FROM jsonb_array_elements_text(p_payload->'evidence_asset_ids') a)
        WHERE nonconformity_id=target;
    END IF;
  ELSIF p_action='set_detail' THEN
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.set_nonconformity_detail(target,p_payload->>'description',
      p_payload->>'control_measure',p_payload->>'legislation_ref',p_payload->>'responsible_contact',
      p_payload->>'risk_method',(p_payload->>'fk_probability')::numeric,(p_payload->>'fk_frequency')::numeric,
      (p_payload->>'fk_severity')::numeric,(p_payload->>'m5_probability')::integer,
      (p_payload->>'m5_severity')::integer,stamp);
  ELSIF p_action='transition' THEN
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.transition_nonconformity(target,p_payload->>'to_state',
      (p_payload->>'expected_version')::bigint,p_payload->>'reason',p_payload->>'assignee',actor,
      (p_payload->>'closed_on')::date,stamp);
  ELSIF p_action='add_action' THEN
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.add_corrective_action(target,p_payload->>'description',p_payload->>'assignee',
      (p_payload->>'due_on')::date,p_payload->>'external_ref',stamp);
  ELSE
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.record_verification(target,p_payload->>'outcome',actor,
      coalesce((p_payload->>'verified_on')::date,(stamp AT TIME ZONE 'Europe/Istanbul')::date),NULL,p_payload->>'note',stamp);
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'operation_id',p_operation,
    'row',private_isg.nonconformity_row(p_company,target),'outcome',result,'legacy_finding_written',false);
  INSERT INTO private_isg.nonconformity_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.mutate_risk_versions(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.risk_version_receipts;
  result jsonb; answer jsonb; target uuid; entry private_isg.risk_assessments;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_risk_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;
  IF p_action NOT IN ('open_assessment','draft_version','finalize_version','record_impact') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  allowed:=CASE p_action
    WHEN 'open_assessment' THEN ARRAY['workplace_id']
    -- No verified_by here: the verification is the signed-in expert's own, and
    -- the boundary supplies it rather than letting the client name someone.
    WHEN 'draft_version' THEN ARRAY['assessment_id','kind','assessment_on','revision_on','scope','reason',
      'file_asset_id','expected_current']
    WHEN 'attach_source' THEN ARRAY['assessment_id','version','analysis_id','finding_id','source_version',
      'copied_fields']
    WHEN 'record_impact' THEN ARRAY['assessment_id','version','target_kind','target_ref','action','note']
    WHEN 'finalize_version' THEN ARRAY['expected_edit_revision','assessment_id','version','expected_current','rule_code','period_years']
    WHEN 'flag_drift' THEN ARRAY['assessment_id','version','analysis_id','current_source_version','note']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-risk:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.risk_version_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='open_assessment' THEN
    IF p_payload->>'workplace_id' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- The workplace has to be this company's and this actor's before the domain
    -- function, which was written for a caller that had already checked.
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    answer:=private_isg.open_risk_assessment(p_company,(p_payload->>'workplace_id')::uuid,stamp);
    target:=(answer->>'assessment_id')::uuid;
  ELSE
    target:=(p_payload->>'assessment_id')::uuid;
    SELECT * INTO entry FROM private_isg.risk_assessments
      WHERE assessment_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

    IF p_action='draft_version' THEN
      IF p_payload->>'kind' IS NULL OR p_payload->>'expected_current' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      -- Only clean, owned assets may be attached — the same rule every other
      -- module's asset_id enforces.
      IF p_payload->>'file_asset_id' IS NOT NULL THEN
        PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
          WHERE fa.asset_id=(p_payload->>'file_asset_id')::uuid AND fa.scan_status='clean'
            AND fle.company_id=p_company AND private_isg.expert_company_visible(fle.owner_id,fle.company_id,actor);
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
      answer:=private_isg.draft_risk_version(target,p_payload->>'kind',
        (p_payload->>'assessment_on')::date,(p_payload->>'revision_on')::date,
        CASE WHEN p_payload ? 'scope' THEN p_payload->'scope' END,
        nullif(btrim(coalesce(p_payload->>'reason','')),''),
        (p_payload->>'file_asset_id')::uuid,(p_payload->>'expected_current')::integer,stamp);
    ELSIF p_action='attach_source' THEN
      IF p_payload->>'version' IS NULL OR p_payload->>'analysis_id' IS NULL OR
         p_payload->>'finding_id' IS NULL OR p_payload->>'source_version' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.attach_risk_source(target,(p_payload->>'version')::integer,
        (p_payload->>'analysis_id')::uuid,(p_payload->>'finding_id')::uuid,
        (p_payload->>'source_version')::bigint,
        coalesce(p_payload->'copied_fields','{}'::jsonb),stamp);
    ELSIF p_action='record_impact' THEN
      IF p_payload->>'version' IS NULL OR p_payload->>'target_kind' IS NULL OR
         p_payload->>'target_ref' IS NULL OR p_payload->>'action' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.record_revision_impact(target,(p_payload->>'version')::integer,
        p_payload->>'target_kind',p_payload->>'target_ref',p_payload->>'action',
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
    ELSIF p_action='finalize_version' THEN
      IF coalesce((p_payload->>'expected_edit_revision')::integer,0) IS DISTINCT FROM (SELECT edit_revision FROM private_isg.risk_assessment_versions WHERE assessment_id=target AND version=(p_payload->>'version')::integer) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      IF p_payload->>'version' IS NULL OR p_payload->>'expected_current' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      -- The expert who is signed in is the one verifying. The client cannot
      -- name a verifier, so no record can carry someone else's confirmation.
      answer:=private_isg.finalize_risk_version(target,(p_payload->>'version')::integer,
        (p_payload->>'expected_current')::integer,actor,
        nullif(btrim(coalesce(p_payload->>'rule_code','')),''),
        (p_payload->>'period_years')::integer,stamp);
    ELSE
      IF p_payload->>'version' IS NULL OR p_payload->>'analysis_id' IS NULL OR
         p_payload->>'current_source_version' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.flag_source_drift(target,(p_payload->>'version')::integer,
        (p_payload->>'analysis_id')::uuid,(p_payload->>'current_source_version')::bigint,
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'assessment_id',target,
    'answer',answer,'row',private_isg.risk_assessment_row(target,today,true));
  INSERT INTO private_isg.risk_version_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_record_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE actor uuid; asset uuid; wp jsonb; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
 actor:=private_isg.process_guard(CASE TG_TABLE_NAME WHEN 'pilot_completed_drills' THEN 'completed_drill' ELSE 'personnel_certificate' END,NEW.company_id,true);
 IF NOT private_isg.expert_company_visible(NEW.owner_id,NEW.company_id,actor) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF TG_OP='UPDATE' AND (NEW.company_id<>OLD.company_id OR NEW.owner_id<>OLD.owner_id) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 -- Deleting retains its historical snapshots, including archived attachments/persons.
 IF TG_OP='UPDATE' AND NEW.is_deleted THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME='pilot_completed_drills' THEN
  IF NEW.held_on>today THEN RAISE EXCEPTION 'FUTURE_DATE'; END IF;
  SELECT to_jsonb(w) INTO wp FROM private_isg.workplaces w WHERE w.id=NEW.workplace_id AND w.company_id=NEW.company_id AND NOT w.is_archived;
  IF wp IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  -- Drill interval is annual, mining six-monthly; hazard class governs the plan,
  -- not this interval. BEKRA is recorded separately, never extends this deadline.
  NEW.period_months:=CASE WHEN coalesce(wp->>'nace_code','') ~ '^0[5-9]' THEN 6 ELSE 12 END;
  NEW.hazard_snapshot:=wp->>'hazard_class';
  NEW.calculated_due:=(NEW.held_on+make_interval(months=>NEW.period_months))::date;
  IF NOT NEW.due_override OR NEW.valid_until IS NULL THEN NEW.valid_until:=NEW.calculated_due;NEW.due_override:=false; END IF;
  IF NEW.photo_ids IS NULL OR cardinality(NEW.photo_ids)>10 OR cardinality(NEW.photo_ids)<>(SELECT count(DISTINCT x) FROM unnest(NEW.photo_ids) x) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  FOREACH asset IN ARRAY NEW.photo_ids LOOP
   IF NOT EXISTS(SELECT 1 FROM private_isg.file_assets a JOIN private_isg.file_library_entries f ON f.asset_id=a.asset_id WHERE a.asset_id=asset AND private_isg.expert_company_visible(a.owner_id,a.company_id,actor) AND a.scan_status='clean' AND a.detected_type LIKE 'image/%' AND private_isg.expert_company_visible(f.owner_id,f.company_id,actor) AND f.company_id=NEW.company_id AND NOT f.is_archived) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  END LOOP;
 ELSE
  IF NEW.issued_on>today THEN RAISE EXCEPTION 'FUTURE_DATE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM private_isg.employees WHERE id=NEW.employee_id AND company_id=NEW.company_id AND NOT is_archived) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  NEW.calculated_due:=CASE WHEN NEW.certificate_kind='first_aid' THEN (NEW.issued_on+interval '3 years')::date END;
  IF NEW.calculated_due IS NOT NULL AND (NOT NEW.due_override OR NEW.valid_until IS NULL) THEN NEW.valid_until:=NEW.calculated_due;NEW.due_override:=false; END IF;
 END IF;
 IF NEW.asset_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.file_assets a JOIN private_isg.file_library_entries f ON f.asset_id=a.asset_id WHERE a.asset_id=NEW.asset_id AND private_isg.expert_company_visible(a.owner_id,a.company_id,actor) AND a.scan_status='clean' AND (TG_TABLE_NAME<>'pilot_completed_drills' OR a.detected_type='application/pdf') AND private_isg.expert_company_visible(f.owner_id,f.company_id,actor) AND f.company_id=NEW.company_id AND NOT f.is_archived) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_training_sessions_save(p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
 IF EXISTS(SELECT 1 FROM private_isg.pilot_training_sessions WHERE id=(p_payload->>'id')::uuid AND private_isg.expert_session_visible(owner_id,id,actor) AND education IS NOT NULL) THEN RAISE EXCEPTION 'UPGRADE_REQUIRED'; END IF;
 RETURN private_isg.pilot_training_sessions_save_legacy_v2(p_mutation,p_payload);
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.pilot_training_sessions_save_legacy_v2(p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=private_isg.active_actor(); sid uuid; old private_isg.pilot_training_sessions;
 cat private_isg.pilot_training_catalog; prior private_isg.pilot_training_session_receipts;
 action text; fingerprint bytea; result jsonb; before_row jsonb; company uuid; person uuid; record_id uuid; nm text; hazard text;
 companies uuid[]; ids uuid[]; entry jsonb; rule jsonb; minutes integer; months integer; held date; validity date;
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,true) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>131072
  THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 action:=p_payload->>'action'; sid:=(p_payload->>'id')::uuid;
 IF action IS NULL OR action NOT IN ('save','delete','catalog') THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':training-v2',0));
 IF action='catalog' THEN
  company:=(p_payload->>'company_id')::uuid; PERFORM private_isg.require_company(company,true);
 ELSE
  IF sid IS NOT NULL THEN
   SELECT * INTO old FROM private_isg.pilot_training_sessions WHERE id=sid AND private_isg.expert_session_visible(owner_id,id,actor) FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  END IF;
  IF action='save' AND (jsonb_typeof(p_payload->'companies') IS DISTINCT FROM 'array'
    OR jsonb_array_length(p_payload->'companies') NOT BETWEEN 1 AND 30) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  SELECT array_agg(DISTINCT x ORDER BY x) INTO companies FROM (
   SELECT r.company_id x FROM private_isg.pilot_training_records r WHERE r.session_id=sid
   UNION SELECT (v->>'id')::uuid FROM jsonb_array_elements(coalesce(p_payload->'companies','[]')) v) a;
  IF companies IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  FOREACH company IN ARRAY companies LOOP PERFORM private_isg.require_company(company,true); END LOOP;
 END IF;
 fingerprint:=sha256(convert_to(p_payload::text,'UTF8'));
 SELECT * INTO prior FROM private_isg.pilot_training_session_receipts WHERE owner_id=actor AND mutation_id=p_mutation;
 IF FOUND THEN
  IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  RETURN prior.response;
 END IF;
 IF action='catalog' THEN
  minutes:=(p_payload->>'minutes')::integer; months:=(p_payload->>'months')::integer;
  IF minutes IS NULL OR minutes NOT BETWEEN 1 AND 1440 OR months IS NULL OR months NOT BETWEEN 0 AND 120
   OR length(btrim(coalesce(p_payload->>'title',''))) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  rule:=jsonb_build_object('minutes',minutes,'months',months);
  INSERT INTO private_isg.pilot_training_catalog(owner_id,code,title,rules) VALUES(actor,'custom',btrim(p_payload->>'title'),
   jsonb_build_object('low',rule,'medium',rule,'high',rule)) RETURNING * INTO cat;
  result:=jsonb_build_object('schema_version',2,'owner_id',actor,'mutation_id',p_mutation,'catalog',to_jsonb(cat));
 ELSE
  IF sid IS NOT NULL AND (old.version IS DISTINCT FROM (p_payload->>'expected_version')::bigint OR old.deleted_at IS NOT NULL) THEN RAISE EXCEPTION 'VERSION_CONFLICT'; END IF;
  IF sid IS NULL AND action='delete' THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF sid IS NOT NULL THEN
   before_row:=private_isg.pilot_training_session_row(sid);
   INSERT INTO private_isg.pilot_training_session_revisions(session_id,version,snapshot,changed_at) VALUES(sid,old.version,before_row,now());
  END IF;
  IF action='delete' THEN
   UPDATE private_isg.pilot_training_sessions SET deleted_at=now(),version=version+1 WHERE id=sid;
   UPDATE private_isg.pilot_training_records SET state='cancelled',version=version+1 WHERE session_id=sid;
  ELSE
   SELECT * INTO cat FROM private_isg.pilot_training_catalog WHERE id=(p_payload->>'catalog_id')::uuid AND (owner_id IS NULL OR owner_id=actor);
   IF NOT FOUND THEN RAISE EXCEPTION 'CATALOG_REQUIRED'; END IF;
   held:=(p_payload->>'held_on')::date;
   IF cat.code<>'custom' AND held<'2026-04-02'::date THEN RAISE EXCEPTION 'RULE_DATE_UNSUPPORTED'; END IF;
   IF held IS NULL OR NOT isfinite(held) OR held>(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date
    OR length(btrim(coalesce(p_payload->>'trainer',''))) NOT BETWEEN 1 AND 200
    OR length(coalesce(p_payload->>'location',''))>300 OR length(coalesce(p_payload->>'notes',''))>2000
    OR p_payload->>'method' IS NULL OR p_payload->>'method' NOT IN ('face_to_face','online','mixed')
    OR p_payload->>'confirmed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
   IF cat.code='onboarding' AND p_payload->>'method'<>'face_to_face' THEN RAISE EXCEPTION 'FACE_TO_FACE_REQUIRED'; END IF;
   IF sid IS NULL THEN
    INSERT INTO private_isg.pilot_training_sessions(owner_id,title,trainer,held_on) VALUES(actor,cat.title,btrim(p_payload->>'trainer'),held) RETURNING id INTO sid;
   ELSE
    UPDATE private_isg.pilot_training_sessions SET version=version+1 WHERE id=sid;
   END IF;
   UPDATE private_isg.pilot_training_sessions SET catalog_id=cat.id,catalog_snapshot=to_jsonb(cat),title=cat.title,
    trainer=btrim(p_payload->>'trainer'),held_on=held,method=p_payload->>'method',location=coalesce(p_payload->>'location',''),notes=coalesce(p_payload->>'notes','') WHERE id=sid;
   -- Rebuild per-company projections atomically; previous snapshots stay in revisions.
   DELETE FROM private_isg.pilot_training_records WHERE session_id=sid;
   companies:='{}';
   FOR entry IN SELECT value FROM jsonb_array_elements(p_payload->'companies') LOOP
    company:=(entry->>'id')::uuid;
    IF company IS NULL OR company=ANY(companies) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
    companies:=array_append(companies,company);
    SELECT hazard_class INTO hazard FROM public.companies WHERE id=company AND private_isg.expert_company_visible(user_id,id,actor);
    rule:=cat.rules->hazard; minutes:=(rule->>'minutes')::integer; months:=(rule->>'months')::integer;
    IF minutes IS NULL THEN RAISE EXCEPTION 'HAZARD_REQUIRED'; END IF;
    IF cat.code IN ('basic','renewal') AND hazard<>'low' AND p_payload->>'method'='online' THEN RAISE EXCEPTION 'WORKPLACE_FACE_TO_FACE_REQUIRED'; END IF;
    validity:=CASE WHEN months=0 THEN NULL ELSE (held+make_interval(months=>months))::date END;
    INSERT INTO private_isg.pilot_training_records(company_id,owner_id,title,trainer,starts_at,duration_minutes,valid_until,state,completed_at,location,notes,session_id)
     VALUES(company,actor,cat.title,btrim(p_payload->>'trainer'),held::timestamp AT TIME ZONE 'Europe/Istanbul',minutes,validity,'completed',now(),coalesce(p_payload->>'location',''),coalesce(p_payload->>'notes',''),sid) RETURNING id INTO record_id;
    UPDATE private_isg.pilot_training_records SET company_snapshot=(SELECT jsonb_build_object('company_name',c.name,'hazard_class',c.hazard_class) FROM public.companies c WHERE c.id=company) WHERE id=record_id;
    IF jsonb_typeof(entry->'participants') IS DISTINCT FROM 'array' OR jsonb_array_length(entry->'participants') NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'PARTICIPANT_REQUIRED'; END IF;
    ids:='{}';
    FOR person IN SELECT value::text::uuid FROM jsonb_array_elements_text(entry->'participants') LOOP
     IF person IS NULL OR person=ANY(ids) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
     SELECT full_name INTO nm FROM private_isg.employees WHERE id=person AND company_id=company AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived FOR SHARE;
     IF NOT FOUND THEN
      -- Retain an existing archived participant when correcting a historical record.
      SELECT p->>'name' INTO nm FROM jsonb_array_elements(before_row->'companies') c,
       LATERAL jsonb_array_elements(c->'participants') p WHERE c->>'company_id'=company::text AND p->>'id'=person::text;
      IF nm IS NULL THEN RAISE EXCEPTION 'PARTICIPANT_UNAVAILABLE'; END IF;
     END IF;
     ids:=array_append(ids,person);
     INSERT INTO private_isg.pilot_training_participants(company_id,training_id,employee_id,employee_name,attended) VALUES(company,record_id,person,nm,true);
    END LOOP;
   END LOOP;
  END IF;
  result:=jsonb_build_object('schema_version',2,'owner_id',actor,'mutation_id',p_mutation,'row',private_isg.pilot_training_session_row(sid));
 END IF;
 INSERT INTO private_isg.pilot_training_session_receipts(owner_id,mutation_id,request_hash,response,created_at) VALUES(actor,p_mutation,fingerprint,result,now());
 RETURN result;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.process_mutate(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE kind text:=p_payload->>'kind'; spec jsonb:=private_isg.process_spec(kind); actor uuid; id_ uuid; row_ jsonb; vals jsonb:=p_payload->'values'; old_ jsonb; result jsonb; parent jsonb; cols text; expr text; key_ text; hash_ bytea; receipt private_isg.module_edit_receipts; doc uuid; other jsonb; today date:=(now() AT TIME ZONE 'Europe/Istanbul')::date; document_ private_isg.documents; stored_ private_isg.document_versions; template_ text; serial_ bigint; version_ integer; source_hash_ text; child_kind_ text; child_spec_ jsonb; child_id_ uuid; children_ jsonb:='[]'; decisions_ jsonb; decision_ jsonb; decision_no_ int:=0;
BEGIN
actor:=private_isg.process_guard(kind,p_company,true);
IF kind='approved_notebook' AND p_action='export' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
IF p_operation IS NULL OR p_mutation IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>32768 OR p_action IS NULL OR p_action NOT IN ('save','delete','export') OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('kind','id','expected','values','document_id','related_kind','related_id')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
hash_:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':process:'||p_mutation::text,0));
SELECT * INTO receipt FROM private_isg.module_edit_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
IF FOUND THEN IF receipt.request_hash<>hash_ THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF; RETURN receipt.response; END IF;
id_:=(p_payload->>'id')::uuid;
IF id_ IS NOT NULL THEN
 EXECUTE format('SELECT to_jsonb(t) FROM private_isg.%I t WHERE %I=$1 FOR UPDATE',spec->>'table',spec->>'id') INTO old_ USING id_;
 row_:=private_isg.process_row(kind,id_);
 IF (row_->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF row_->>'expected' IS DISTINCT FROM p_payload->>'expected' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
ELSE IF p_action<>'save' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF; END IF;
IF p_action='delete' THEN
 IF kind='annual_work_plan' AND EXISTS(SELECT 1 FROM private_isg.annual_work_plan_items WHERE plan_id=id_ AND NOT is_deleted) OR kind='board' AND EXISTS(SELECT 1 FROM private_isg.board_decisions WHERE meeting_id=id_ AND NOT is_deleted) OR kind='site_visit' AND EXISTS(SELECT 1 FROM private_isg.site_visit_observations WHERE visit_id=id_ AND NOT is_deleted) OR kind='contractor' AND (EXISTS(SELECT 1 FROM private_isg.contractor_engagements WHERE organization_id=id_ AND NOT is_deleted) OR EXISTS(SELECT 1 FROM private_isg.employees WHERE employer_org_id=id_ AND NOT is_archived)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPENDENT_RECORDS'; END IF;
 EXECUTE format('UPDATE private_isg.%I SET %I=true WHERE %I=$1',spec->>'table',CASE WHEN kind='contractor' THEN 'is_archived' ELSE 'is_deleted' END,spec->>'id') USING id_;
 result:=jsonb_build_object('deleted',true);
ELSIF p_action='export' THEN
 child_kind_:=CASE kind WHEN 'annual_work_plan' THEN 'annual_work_item' WHEN 'board' THEN 'board_decision' WHEN 'site_visit' THEN 'site_observation' END;
 IF child_kind_ IS NOT NULL THEN
  child_spec_:=private_isg.process_spec(child_kind_);
  FOR child_id_ IN EXECUTE format('SELECT %I FROM private_isg.%I WHERE %I=$1 AND NOT is_deleted ORDER BY %I FOR SHARE',child_spec_->>'id',child_spec_->>'table',child_spec_->>'parent',child_spec_->>'id') USING id_ LOOP
   children_:=children_||jsonb_build_array(private_isg.process_row(child_kind_,child_id_));
  END LOOP;
 END IF;
 result:=row_||jsonb_build_object('children',children_,'child_kind',child_kind_,'source','expert_record');
 source_hash_:=md5(result::text); template_:='process_'||kind;
 INSERT INTO private_isg.document_templates(template_code,source_domain,title) VALUES(template_,'module',kind) ON CONFLICT DO NOTHING;
 INSERT INTO private_isg.document_template_versions(template_code,version,status,approved_by,approval_note,published_at) VALUES(template_,1,'published',actor,'Expert-requested record export; blank signatures, no regulatory approval claim',now()) ON CONFLICT DO NOTHING;
 INSERT INTO private_isg.documents(company_id,owner_id,workplace_id,source_domain,source_ref,template_code) VALUES(p_company,actor,(row_->'values'->>'workplace_id')::uuid,'module',kind||':'||id_::text,template_) ON CONFLICT(company_id,source_domain,source_ref,template_code) DO NOTHING;
 SELECT * INTO document_ FROM private_isg.documents WHERE company_id=p_company AND source_domain='module' AND source_ref=kind||':'||id_::text AND template_code=template_ FOR UPDATE;
 SELECT * INTO stored_ FROM private_isg.document_versions WHERE document_id=document_.document_id AND version=document_.current_version;
 IF FOUND AND stored_.snapshot->>'source_hash'=source_hash_ THEN result:=stored_.snapshot;
 ELSE
  INSERT INTO private_isg.education_document_counters(scope,year,next_value) VALUES('MOD',extract(year FROM today)::int,1) ON CONFLICT DO NOTHING;
  UPDATE private_isg.education_document_counters SET next_value=next_value+1 WHERE scope='MOD' AND year=extract(year FROM today)::int RETURNING next_value-1 INTO serial_;
  version_:=document_.current_version+1;
  result:=result||jsonb_build_object('document_id',document_.document_id,'number','MOD-'||extract(year FROM today)::int||'-'||serial_,'revision',version_,'source_hash',source_hash_,'exported_on',today);
  INSERT INTO private_isg.document_versions(document_id,version,template_version,document_no,source_kind,snapshot,snapshot_sha256,finalized_by,finalized_at,mutation_id) VALUES(document_.document_id,version_,1,result->>'number','structured',result,sha256(convert_to(result::text,'UTF8')),actor,now(),p_mutation);
  UPDATE private_isg.documents SET current_version=version_ WHERE document_id=document_.document_id;
 END IF;

ELSE
 IF jsonb_typeof(vals) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(vals) k WHERE NOT (spec->'fields' ? k)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
 IF kind='board' AND vals ? 'initial_decisions' THEN
  decisions_:=vals->'initial_decisions'; vals:=vals-'initial_decisions';
  IF decisions_='null'::jsonb THEN decisions_:='[]'; END IF;
  IF jsonb_typeof(decisions_)<>'array' OR jsonb_array_length(decisions_)>100 OR (id_ IS NOT NULL AND jsonb_array_length(decisions_)>0) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(decisions_) d WHERE jsonb_typeof(d)<>'string' OR length(btrim(d#>>'{}')) NOT BETWEEN 1 AND 2000) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 END IF;
 IF spec ? 'parent' THEN
  parent:=private_isg.process_row(spec->>'parent_kind',(vals->>(spec->>'parent'))::uuid);
  IF (parent->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF vals ? 'workplace_id' THEN
  PERFORM 1 FROM private_isg.workplaces WHERE id=(vals->>'workplace_id')::uuid AND company_id=p_company AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF kind='annual_work_item' THEN
  IF extract(year FROM (vals->>'planned_on')::date)<>(parent->'values'->>'plan_year')::integer THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_YEAR_MISMATCH'; END IF;
  IF parent->'values'->>'state'<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_CLOSED'; END IF;
  IF (vals->>'performed_on')::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
 END IF;
 IF kind='board' THEN
  vals:=vals||jsonb_build_object('counts_towards_legal_score',vals->>'applicability'='mandatory');
  IF (vals->>'held_on')::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
  IF jsonb_typeof(vals->'agenda')<>'array' OR jsonb_array_length(vals->'agenda')=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 END IF;
 IF kind='site_visit' THEN
  IF (coalesce(vals->>'visited_on',old_->>'visited_on'))::date>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_DATE'; END IF;
  PERFORM private_isg.text_value(coalesce(vals->>'expert_note',old_->>'expert_note'),16000);
  IF vals->>'duration_minutes' IS NOT NULL AND (vals->>'duration_minutes' !~ '^[0-9]+$' OR (vals->>'duration_minutes')::numeric NOT BETWEEN 1 AND 1440) THEN
   RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 END IF;
 IF kind='approved_notebook' THEN
  IF (vals ? 'title') OR id_ IS NULL THEN PERFORM private_isg.text_value(vals->>'title',160); END IF;
  IF (vals ? 'asset_id') OR id_ IS NULL THEN
   IF vals->>'asset_id' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  END IF;
 END IF;
 IF kind='work_permit' THEN
  IF vals->>'template_code' NOT IN ('general','hot_work','work_at_height','confined_space','electrical') OR (vals->>'ends_at')::timestamptz<=(vals->>'starts_at')::timestamptz THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  vals:=vals||'{"template_version":1}'::jsonb;
 END IF;
 IF kind IN ('board','work_permit') THEN
  key_:=CASE WHEN kind='board' THEN 'attendance' ELSE 'parties' END;
  IF vals->key_ IS NOT NULL AND vals->key_<>'null'::jsonb THEN
   IF jsonb_typeof(vals->key_)<>'array' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(vals->key_) person WHERE NOT EXISTS(SELECT 1 FROM private_isg.employees e WHERE e.id=(person->>'id')::uuid AND e.company_id=p_company AND NOT e.is_archived)) OR (SELECT count(*)<>count(DISTINCT person->>'id') FROM jsonb_array_elements(vals->key_) person) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
   vals:=jsonb_set(vals,ARRAY[key_],(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'name',e.full_name) ORDER BY ord),'[]') FROM jsonb_array_elements(vals->key_) WITH ORDINALITY x(person,ord) JOIN private_isg.employees e ON e.id=(person->>'id')::uuid));
  END IF;
 END IF;
 IF kind='contractor_engagement' THEN
  PERFORM 1 FROM private_isg.contractor_organizations WHERE id=(vals->>'organization_id')::uuid AND company_id=p_company AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 FOREACH key_ IN ARRAY ARRAY['asset_id','minutes_asset_id','visit_asset_id'] LOOP
  IF vals->>key_ IS NOT NULL THEN
   PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
     WHERE fa.asset_id=(vals->>key_)::uuid AND fa.scan_status='clean' AND private_isg.expert_company_visible(fa.owner_id,fa.company_id,actor)
       AND (fa.company_id=p_company OR private_isg.p05_pilot_account_enabled(actor,true)) AND fle.company_id=p_company AND private_isg.expert_company_visible(fle.owner_id,fle.company_id,actor) AND NOT fle.is_archived
       AND ((key_<>'visit_asset_id' AND kind<>'approved_notebook') OR fa.detected_type LIKE 'image/%');
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
 END LOOP;
 doc:=(p_payload->>'document_id')::uuid;
 IF doc IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.document_obligations WHERE obligation_id=doc AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF p_payload->>'related_id' IS NOT NULL THEN
  other:=private_isg.process_references(p_payload->>'related_kind',p_company,(p_payload->>'related_id')::uuid,NULL,0)->'rows'->0;
  IF (other->>'company_id')::uuid<>p_company THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 IF id_ IS NULL THEN
  id_:=gen_random_uuid();vals:=vals||jsonb_build_object(spec->>'id',id_);
  IF NOT (spec ? 'parent') THEN vals:=vals||jsonb_build_object('company_id',p_company,'owner_id',actor); END IF;
  SELECT string_agg(format('%I',k),',' ORDER BY k),string_agg(format('r.%I',k),',' ORDER BY k) INTO cols,expr FROM jsonb_object_keys(vals) k;
  EXECUTE format('INSERT INTO private_isg.%I(%s) SELECT %s FROM jsonb_populate_record(NULL::private_isg.%I,$1) r',spec->>'table',cols,expr,spec->>'table') USING vals;
 ELSE
  SELECT string_agg(format('%I=r.%I',k,k),',' ORDER BY k) INTO cols FROM jsonb_object_keys(vals) k;
  IF kind IN ('contractor','contractor_engagement') THEN cols:=cols||',version=t.version+1'; END IF;
  EXECUTE format('UPDATE private_isg.%I t SET %s FROM jsonb_populate_record(NULL::private_isg.%I,$1) r WHERE t.%I=$2',spec->>'table',cols,spec->>'table',spec->>'id') USING vals,id_;
 END IF;
 IF kind='board' AND decisions_ IS NOT NULL THEN
  FOR decision_ IN SELECT value FROM jsonb_array_elements(decisions_) LOOP
   decision_no_:=decision_no_+1;
   INSERT INTO private_isg.board_decisions(meeting_id,decision_no,decision_text,state) VALUES(id_,decision_no_,btrim(decision_#>>'{}'),'open');
  END LOOP;
 END IF;
 INSERT INTO private_isg.process_record_meta(kind,record_id,company_id,document_id,related_kind,related_id) VALUES(kind,id_,p_company,doc,p_payload->>'related_kind',(p_payload->>'related_id')::uuid) ON CONFLICT ON CONSTRAINT process_record_meta_pkey DO UPDATE SET document_id=EXCLUDED.document_id,related_kind=EXCLUDED.related_kind,related_id=EXCLUDED.related_id;
 result:=private_isg.process_row(kind,id_);
END IF;
IF old_ IS NOT NULL THEN INSERT INTO private_isg.process_record_history(kind,record_id,company_id,actor_id,before_snapshot) VALUES(kind,id_,p_company,actor,old_); END IF;
INSERT INTO private_isg.module_edit_receipts(actor_id,mutation_id,request_hash,response) VALUES(actor,p_mutation,hash_,result);
RETURN result;
END $function$
;

CREATE OR REPLACE FUNCTION private_isg.module_scope(p_module text, p_company uuid, p_workplace uuid, p_write boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE owner uuid;
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.expert_require_company(p_company,p_write,NULL);
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace AND workspace_id=private_isg.expert_workspace() AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
    RETURN private_isg.active_actor();
  END IF;
  PERFORM private_isg.module_gate(p_module,p_write);
  IF p_company IS NULL OR p_workplace IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT owner_id INTO owner FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF owner IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN owner;
END $function$
;

-- Domain operations retain the organization rollout switches in expert context.
CREATE OR REPLACE FUNCTION private_isg.nonconformity_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('risk_nonconformity',p_write);
    RETURN;
  END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='nonconformity' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.risk_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('risk_nonconformity',p_write);
    RETURN;
  END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='risk' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.checklist_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('risk_nonconformity',p_write);
    RETURN;
  END IF;
  PERFORM private_isg.nonconformity_gate(p_write);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.document_tracking_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('files',p_write);
    RETURN;
  END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='document_tracking' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.file_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('files',p_write);
    RETURN;
  END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='file_core' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.file_library_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('files',p_write);
    RETURN;
  END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='file_library' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.appointment_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('emergency_ppe',p_write);
    RETURN;
  END IF;
  PERFORM private_isg.module_gate('appointment',p_write);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.drill_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('emergency_ppe',p_write);
    RETURN;
  END IF;
  PERFORM private_isg.module_gate('drill',p_write);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.emergency_plan_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('emergency_ppe',p_write);
    RETURN;
  END IF;
  PERFORM private_isg.module_gate('emergency_plan',p_write);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.equipment_check_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('equipment',p_write);
    RETURN;
  END IF;
  PERFORM private_isg.module_gate('equipment',p_write);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.ppe_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(private_isg.expert_workspace(),ARRAY['owner','admin','expert'],p_write);
    PERFORM private_isg.workspace_domain_gate('emergency_ppe',p_write);
    RETURN;
  END IF;
  PERFORM private_isg.module_gate('ppe',p_write);
END $function$
;

-- The shared file UI keeps the existing quarantine/inspection pipeline.
-- Organization assets have no personal owner; uploader is provenance only.
DO $schema$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['upload_intents','file_assets','file_library_entries'] LOOP
  EXECUTE format('ALTER TABLE private_isg.%I ADD COLUMN workspace_id uuid REFERENCES private_isg.workspaces(id)',t);
  EXECUTE format('ALTER TABLE private_isg.%I ADD COLUMN uploaded_by_user_id uuid REFERENCES auth.users(id)',t);
  EXECUTE format('ALTER TABLE private_isg.%I ALTER COLUMN owner_id DROP NOT NULL',t);
  EXECUTE format('ALTER TABLE private_isg.%I ADD CHECK ((workspace_id IS NULL AND owner_id IS NOT NULL) OR (workspace_id IS NOT NULL AND owner_id IS NULL AND company_id IS NOT NULL))',t);
  EXECUTE format('ALTER TABLE private_isg.%I ADD FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id)',t);
 END LOOP;
END $schema$;

CREATE FUNCTION private_isg.expert_file_stamp() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE workspace uuid:=private_isg.expert_workspace();
BEGIN
 IF workspace IS NULL THEN RETURN NEW; END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.workspace_id IS NOT NULL AND NEW.workspace_id<>workspace THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.companies WHERE id=NEW.company_id AND workspace_id=workspace) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  NEW.workspace_id:=workspace; NEW.uploaded_by_user_id:=NEW.owner_id;
  IF TG_TABLE_NAME='file_assets' THEN
   SELECT uploaded_by_user_id INTO NEW.uploaded_by_user_id FROM private_isg.upload_intents WHERE intent_id=NEW.source_intent_id AND workspace_id=workspace;
  END IF;
  NEW.owner_id:=NULL;
 ELSE
  IF OLD.workspace_id IS DISTINCT FROM workspace OR NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
   OR NEW.company_id IS DISTINCT FROM OLD.company_id OR NEW.owner_id IS DISTINCT FROM OLD.owner_id
   OR NEW.uploaded_by_user_id IS DISTINCT FROM OLD.uploaded_by_user_id THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.expert_file_stamp() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER expert_file_scope BEFORE INSERT OR UPDATE ON private_isg.upload_intents FOR EACH ROW EXECUTE FUNCTION private_isg.expert_file_stamp();
CREATE TRIGGER expert_file_scope BEFORE INSERT OR UPDATE ON private_isg.file_assets FOR EACH ROW EXECUTE FUNCTION private_isg.expert_file_stamp();
CREATE TRIGGER expert_file_scope BEFORE INSERT OR UPDATE ON private_isg.file_library_entries FOR EACH ROW EXECUTE FUNCTION private_isg.expert_file_stamp();
CREATE OR REPLACE FUNCTION private_isg.file_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN
  PERFORM private_isg.workspace_domain_gate('files',p_write); RETURN;
 END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='file_core' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.file_library_gate(p_write boolean)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
 IF private_isg.expert_workspace() IS NOT NULL THEN
  PERFORM private_isg.workspace_domain_gate('files',p_write); RETURN;
 END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='file_library' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.pilot_mutate_file_library(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.file_library_receipts;
  result jsonb; target uuid; expected bigint; entry private_isg.file_library_entries;
  purpose text; extension text; intent jsonb; stamp timestamptz:=clock_timestamp();
BEGIN
  actor:=private_isg.pilot_file_owner(p_company,true);
  IF NOT private_isg.p05_pilot_account_enabled(actor,true) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  IF p_payload ? 'tags' AND (jsonb_typeof(p_payload->'tags') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'tags')>12) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF p_payload ? 'tags' AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'tags') x WHERE jsonb_typeof(x)<>'string' OR length(btrim(x#>>'{}')) NOT BETWEEN 1 AND 40) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  allowed:=CASE p_action
    WHEN 'open_upload' THEN ARRAY['title','category','file_name','note','tags','extension','bytes','sha256']
    WHEN 'rename_entry' THEN ARRAY['entry_id','expected_version','title','category','note','tags']
    WHEN 'archive_entry' THEN ARRAY['entry_id','expected_version']
    WHEN 'cancel_upload' THEN ARRAY['entry_id','expected_version']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-file-library:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.file_library_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='open_upload' THEN
    IF p_payload->>'title' IS NULL OR p_payload->>'category' IS NULL OR p_payload->>'file_name' IS NULL OR
       p_payload->>'extension' IS NULL OR p_payload->>'bytes' IS NULL OR p_payload->>'sha256' IS NULL OR
       (p_payload->>'sha256') !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF NOT EXISTS(SELECT 1 FROM private_isg.file_library_categories
        WHERE category=p_payload->>'category') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    extension:=lower(btrim(p_payload->>'extension'));
    purpose:=private_isg.file_library_purpose(extension);
    IF purpose IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UNSUPPORTED_FORMAT'; END IF;
    intent:=private_isg.open_upload_intent(actor,p_company,purpose,extension,
      (p_payload->>'bytes')::bigint,decode(p_payload->>'sha256','hex'),p_operation,p_mutation,
      NULL,true,3600,stamp);
    INSERT INTO private_isg.file_library_entries(company_id,owner_id,intent_id,category,title,file_name,note,tags)
      VALUES(p_company,actor,(intent->>'intent_id')::uuid,p_payload->>'category',
        btrim(p_payload->>'title'),btrim(p_payload->>'file_name'),
        nullif(btrim(coalesce(p_payload->>'note','')),''),ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(coalesce(p_payload->'tags','[]')) x ORDER BY btrim(x)))
      RETURNING entry_id INTO target;
  ELSE
    target:=(p_payload->>'entry_id')::uuid;
    expected:=(p_payload->>'expected_version')::bigint;
    SELECT * INTO entry FROM private_isg.file_library_entries
      WHERE entry_id=target AND company_id IS NOT DISTINCT FROM p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF expected IS NULL OR entry.version<>expected THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF p_action='rename_entry' THEN
      IF p_payload->>'title' IS NOT NULL AND btrim(p_payload->>'title')='' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF p_payload->>'category' IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM private_isg.file_library_categories WHERE category=p_payload->>'category') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      UPDATE private_isg.file_library_entries SET
        title=coalesce(nullif(btrim(coalesce(p_payload->>'title','')),''),title),
        category=coalesce(p_payload->>'category',category),
        note=CASE WHEN p_payload ? 'note' THEN nullif(btrim(coalesce(p_payload->>'note','')),'') ELSE note END,
        tags=CASE WHEN p_payload ? 'tags' THEN ARRAY(SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(p_payload->'tags') x ORDER BY btrim(x)) ELSE tags END,
        version=version+1,updated_at=stamp WHERE entry_id=target;
    ELSIF p_action='archive_entry' THEN
      UPDATE private_isg.file_library_entries SET is_archived=true,version=version+1,updated_at=stamp
        WHERE entry_id=target;
    ELSE
      PERFORM 1 FROM private_isg.upload_intents
        WHERE intent_id=entry.intent_id AND state IN ('pending','uploaded','scanning','clean');
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UPLOAD_NOT_CANCELLABLE'; END IF;
      PERFORM private_isg.reject_upload_intent(entry.intent_id,'EXPIRED',stamp);
      UPDATE private_isg.file_library_entries SET is_archived=true,version=version+1,updated_at=stamp
        WHERE entry_id=target;
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'entry_id',target,
    'row',private_isg.file_library_entry_row(target));
  INSERT INTO private_isg.file_library_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.open_upload_intent(p_owner uuid, p_company uuid, p_purpose text, p_extension text, p_bytes bigint, p_sha256 bytea, p_operation uuid, p_mutation uuid, p_storage_limit bigint, p_storage_unlimited boolean, p_ttl_seconds integer, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE prior private_isg.upload_intents; verdict jsonb; fingerprint bytea; intent uuid:=gen_random_uuid();
  reservation uuid; denied boolean:=false; ledger_open boolean;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_owner IS NULL OR p_purpose IS NULL OR p_extension IS NULL OR p_bytes IS NULL OR p_sha256 IS NULL OR
     octet_length(p_sha256)<>32 OR p_operation IS NULL OR p_mutation IS NULL OR p_now IS NULL OR
     p_ttl_seconds IS NULL OR p_ttl_seconds NOT BETWEEN 60 AND 86400 OR p_storage_unlimited IS NULL OR
     (p_storage_unlimited AND p_storage_limit IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_owner,p_company,p_purpose,lower(btrim(p_extension)),p_bytes,encode(p_sha256,'hex'),p_operation)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(p_owner::text||':isg-upload:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.upload_intents WHERE mutation_id=p_mutation AND
   ((private_isg.expert_workspace() IS NULL AND owner_id=p_owner AND workspace_id IS NULL) OR
    (workspace_id=private_isg.expert_workspace() AND uploaded_by_user_id=p_owner));
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'intent_id',prior.intent_id,'state',prior.state,
      'quarantine_path',prior.quarantine_path,'replayed',true);
  END IF;
  verdict:=private_isg.file_acceptance(p_purpose,p_extension,p_bytes);
  IF NOT (verdict->>'accepted')::boolean THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE=verdict->>'reason'; END IF;
  -- The ledger is still shadow: a storage disagreement is recorded, not enforced.
  ledger_open:=private_isg.expert_workspace() IS NULL AND private_isg.quota_ledger_open();
  IF ledger_open THEN
    BEGIN
      reservation:=(private_isg.reserve_quota(p_owner,p_company,'storage_bytes','lifetime',p_bytes,'plan',
        p_operation,p_mutation,p_storage_limit,p_storage_unlimited,p_ttl_seconds,p_now)->>'reservation_id')::uuid;
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM<>'CAPACITY_EXCEEDED' THEN RAISE; END IF;
      denied:=true;
    END;
  END IF;
  INSERT INTO private_isg.upload_intents(intent_id,owner_id,company_id,purpose,declared_extension,declared_bytes,
      declared_sha256,quarantine_path,reservation_id,storage_shadow_denied,operation_id,mutation_id,request_hash,
      expires_at,created_at,updated_at)
    VALUES(intent,p_owner,p_company,p_purpose,lower(btrim(p_extension)),p_bytes,p_sha256,
      'quarantine/'||coalesce(private_isg.expert_workspace(),p_owner)::text||'/'||intent::text,reservation,denied,p_operation,p_mutation,fingerprint,
      p_now+make_interval(secs=>p_ttl_seconds),p_now,p_now);
  RETURN jsonb_build_object('schema_version',1,'intent_id',intent,'state','pending',
    'quarantine_path','quarantine/'||coalesce(private_isg.expert_workspace(),p_owner)::text||'/'||intent::text,'reservation_id',reservation,
    'storage_shadow_denied',denied,'storage_authority','legacy','replayed',false);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.promote_clean_upload(p_intent uuid, p_bucket text, p_final_sha256 bytea, p_final_bytes bigint, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE entry private_isg.upload_intents; scan private_isg.file_scan_results; asset uuid; path text;
BEGIN
  PERFORM private_isg.file_gate(true);
  IF p_intent IS NULL OR p_bucket IS NULL OR p_final_sha256 IS NULL OR octet_length(p_final_sha256)<>32 OR
     p_final_bytes IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.upload_intents WHERE intent_id=p_intent FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='promoted' THEN
    SELECT asset_id,immutable_path INTO asset,path FROM private_isg.file_assets WHERE source_intent_id=p_intent;
    RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'asset_id',asset,'immutable_path',path,'replayed',true);
  END IF;
  IF entry.state<>'clean' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF entry.expires_at<=p_now THEN RETURN private_isg.reject_upload_intent(p_intent,'EXPIRED',p_now); END IF;
  SELECT * INTO scan FROM private_isg.file_scan_results WHERE intent_id=p_intent FOR SHARE;
  IF NOT FOUND OR scan.verdict<>'clean' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- Anti-TOCTOU: the bytes promoted must still be the bytes that were scanned.
  IF p_final_sha256<>scan.scanned_sha256 OR p_final_bytes<>entry.received_bytes THEN
    RETURN private_isg.reject_upload_intent(p_intent,'HASH_MISMATCH',p_now); END IF;
  asset:=gen_random_uuid(); path:='assets/'||(CASE WHEN entry.workspace_id IS NULL THEN entry.owner_id ELSE entry.company_id END)::text||'/'||encode(p_final_sha256,'hex');
  INSERT INTO private_isg.file_assets(asset_id,owner_id,company_id,purpose,bucket,immutable_path,extension,
      detected_type,sha256,bytes,scan_version,source_intent_id,created_at)
    VALUES(asset,entry.owner_id,entry.company_id,entry.purpose,p_bucket,path,entry.declared_extension,
      entry.detected_type,p_final_sha256,p_final_bytes,scan.scan_version,p_intent,p_now);
  UPDATE private_isg.upload_intents SET state='promoted',updated_at=p_now WHERE intent_id=p_intent;
  IF entry.reservation_id IS NOT NULL AND private_isg.quota_ledger_open() THEN
    PERFORM private_isg.settle_quota(entry.reservation_id,jsonb_build_object('asset_id',asset,'bytes',p_final_bytes),p_now);
  END IF;
  RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'asset_id',asset,'immutable_path',path,
    'bucket',p_bucket,'scan_version',scan.scan_version,'replayed',false);
END $function$
;
CREATE OR REPLACE FUNCTION private_isg.inspect_file_upload(p_intent uuid, p_stage text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE intent private_isg.upload_intents; answer jsonb; stamp timestamptz:=clock_timestamp();
  registered boolean; existing uuid;
BEGIN
  PERFORM private_isg.file_library_gate(true);
  IF p_intent IS NULL OR p_stage IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR
     octet_length(p_payload::text)>4096 OR
     p_stage NOT IN ('claim','received','scanned','promoted') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent FROM private_isg.upload_intents WHERE intent_id=p_intent;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Only an upload this module opened is inspected here.
  PERFORM 1 FROM private_isg.file_library_entries WHERE intent_id=p_intent;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

  IF p_stage='claim' THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state',intent.state,
      'owner_id',intent.owner_id,'storage_scope',CASE WHEN intent.workspace_id IS NULL THEN intent.owner_id ELSE intent.company_id END,'purpose',intent.purpose,'extension',intent.declared_extension,
      'declared_bytes',intent.declared_bytes,'declared_sha256',encode(intent.declared_sha256,'hex'),
      'quarantine_path',intent.quarantine_path,'expires_at',intent.expires_at);
  ELSIF p_stage='received' THEN
    answer:=private_isg.mark_upload_received(p_intent,(p_payload->>'bytes')::bigint,
      decode(p_payload->>'sha256','hex'),p_payload->>'detected_type',stamp);
  ELSIF p_stage='scanned' THEN
    -- A scanner the registry does not know can still record a verdict, but it
    -- will never be reported as a malware scan by the read.
    SELECT EXISTS(SELECT 1 FROM private_isg.file_scanners WHERE scanner=p_payload->>'scanner') INTO registered;
    answer:=private_isg.record_scan_result(p_intent,p_payload->>'scanner',p_payload->>'scan_version',
      p_payload->>'verdict',nullif(p_payload->>'finding_code',''),decode(p_payload->>'sha256','hex'),
      coalesce(p_payload->'evidence','{}'::jsonb)||jsonb_build_object('scanner_registered',registered),stamp);
  ELSE
    -- The final path is the owner plus the digest, so filing the same document a
    -- second time cannot create a second object. The entry is linked to the
    -- asset that is already there rather than overwriting anything.
    SELECT asset_id INTO existing FROM private_isg.file_assets
      WHERE owner_id IS NOT DISTINCT FROM intent.owner_id AND workspace_id IS NOT DISTINCT FROM intent.workspace_id AND (intent.workspace_id IS NULL OR company_id=intent.company_id) AND sha256=decode(p_payload->>'sha256','hex');
    IF existing IS NOT NULL THEN
      UPDATE private_isg.file_library_entries SET asset_id=existing,version=version+1,updated_at=stamp
        WHERE intent_id=p_intent AND asset_id IS NULL;
      answer:=jsonb_build_object('asset_id',existing,'duplicate_of_existing_asset',true);
    ELSE
      answer:=private_isg.promote_clean_upload(p_intent,'isg-documents',
        decode(p_payload->>'sha256','hex'),(p_payload->>'bytes')::bigint,stamp);
      IF answer->>'asset_id' IS NOT NULL THEN
        UPDATE private_isg.file_library_entries SET asset_id=(answer->>'asset_id')::uuid,
          version=version+1,updated_at=stamp WHERE intent_id=p_intent AND asset_id IS NULL;
      END IF;
    END IF;
  END IF;
  RETURN answer||jsonb_build_object('schema_version',1,'intent_id',p_intent,
    'row',(SELECT private_isg.file_library_entry_row(e.entry_id)
      FROM private_isg.file_library_entries e WHERE e.intent_id=p_intent));
END $function$
;

CREATE FUNCTION private_isg.expert_file_inspect(p_intent uuid,p_stage text,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace uuid; previous text:=current_setting('private_isg.expert_workspace',true); result jsonb;
BEGIN
 SELECT workspace_id INTO workspace FROM private_isg.upload_intents WHERE intent_id=p_intent;
 IF workspace IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 PERFORM set_config('private_isg.expert_workspace',workspace::text,true);
 result:=private_isg.inspect_file_upload(p_intent,p_stage,p_payload);
 PERFORM set_config('private_isg.expert_workspace',coalesce(previous,''),true);
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('private_isg.expert_workspace',coalesce(previous,''),true); RAISE;
END $$;
CREATE FUNCTION public.isg_expert_file_inspection_v1(p_intent uuid,p_stage text,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.expert_file_inspect(p_intent,p_stage,p_payload) $$;
REVOKE ALL ON FUNCTION private_isg.expert_file_inspect(uuid,text,jsonb),public.isg_expert_file_inspection_v1(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private_isg.expert_file_inspect(uuid,text,jsonb),public.isg_expert_file_inspection_v1(uuid,text,jsonb) TO service_role;

CREATE FUNCTION private_isg.expert_storage_allowed(p_bucket text,p_path text,p_write boolean) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace uuid; company uuid;
BEGIN
 IF p_write AND p_bucket='isg-quarantine' THEN
  SELECT i.workspace_id,i.company_id INTO workspace,company FROM private_isg.upload_intents i
   WHERE i.quarantine_path=p_path AND i.workspace_id IS NOT NULL AND i.state='pending'
    AND i.expires_at>clock_timestamp() AND i.uploaded_by_user_id=private_isg.active_actor();
 ELSIF NOT p_write AND p_bucket='isg-documents' THEN
  SELECT a.workspace_id,a.company_id INTO workspace,company FROM private_isg.file_assets a
   WHERE a.bucket=p_bucket AND a.immutable_path=p_path AND a.workspace_id IS NOT NULL AND a.scan_status='clean';
 END IF;
 IF workspace IS NULL OR company IS NULL THEN RETURN false; END IF;
 PERFORM private_isg.workspace_domain_gate('files',p_write);
 PERFORM private_isg.workspace_require_company(workspace,company,p_write);
 RETURN true;
EXCEPTION WHEN SQLSTATE 'P0001' OR SQLSTATE '28000' THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION private_isg.expert_storage_allowed(text,text,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION private_isg.expert_storage_allowed(text,text,boolean) TO authenticated;
CREATE POLICY expert_quarantine_insert ON storage.objects FOR INSERT TO authenticated
 WITH CHECK (private_isg.expert_storage_allowed(bucket_id,name,true));
CREATE POLICY expert_documents_select ON storage.objects FOR SELECT TO authenticated
 USING (private_isg.expert_storage_allowed(bucket_id,name,false));
