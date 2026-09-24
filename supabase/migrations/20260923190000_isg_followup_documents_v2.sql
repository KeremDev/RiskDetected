-- A company-wide document timeline with source dates and a server-side type filter.
-- The old RPC remains available while both mobile clients move to v2.
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '30s';

CREATE FUNCTION public.isg_pilot_followup_v2(
  p_company uuid DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_kind text DEFAULT NULL,
  p_query text DEFAULT '',
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  actor uuid := private_isg.active_actor();
  today date := (now() AT TIME ZONE 'Europe/Istanbul')::date;
  answer jsonb;
BEGIN
  IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor, false) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED';
  END IF;
  IF p_company IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id = p_company AND NOT c.is_archived
      AND private_isg.expert_company_visible(c.user_id, c.id, actor)
      AND private_isg.p05_pilot_can_read(actor, c.id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED';
  END IF;
  IF p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000
     OR length(coalesce(p_query, '')) > 200
     OR (p_status IS NOT NULL AND p_status NOT IN ('current', 'soon', 'expired', 'undated'))
     OR (p_kind IS NOT NULL AND (length(p_kind) > 64 OR p_kind !~ '^[a-z_]+$')) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'VALIDATION_ERROR';
  END IF;

  WITH scoped AS MATERIALIZED (
    SELECT c.id, c.name FROM public.companies c
    WHERE NOT c.is_archived AND (p_company IS NULL OR c.id = p_company)
      AND private_isg.expert_company_visible(c.user_id, c.id, actor)
      AND private_isg.p05_pilot_can_read(actor, c.id)
  ),
  base AS MATERIALIZED (
    SELECT r.kind, r.company_id, r.company_name, r.record_id, r.title,
           r.due_on, r.window_days
    FROM private_isg.pilot_followup_rows(actor, p_company) r
    UNION ALL
    -- Records without an expiry still belong in the timeline. Only the latest
    -- inspection/copy is relevant to a current validity decision.
    SELECT 'katip_contract', c.id, c.name, k.contract_id, k.counterparty,
           NULL::date, private_isg.notice_window('katip_contract')
    FROM private_isg.katip_contracts k JOIN scoped c ON c.id = k.company_id
    WHERE NOT k.is_deleted AND k.state = 'active' AND k.ends_before IS NULL
      AND private_isg.notice_kind_available('katip_contract')
    UNION ALL
    SELECT 'appointment', c.id, c.name, a.appointment_id, e.full_name,
           NULL::date, private_isg.notice_window('appointment')
    FROM private_isg.appointments a JOIN scoped c ON c.id = a.company_id
    JOIN private_isg.employees e ON e.id = a.employee_id
    WHERE NOT a.is_deleted AND a.ends_before IS NULL
      AND private_isg.notice_kind_available('appointment')
    UNION ALL
    SELECT 'risk_assessment', c.id, c.name, a.assessment_id,
           coalesce(w.name, 'Risk değerlendirmesi'), NULL::date,
           private_isg.notice_window('risk_assessment')
    FROM private_isg.risk_assessments a JOIN scoped c ON c.id = a.company_id
    LEFT JOIN private_isg.workplaces w ON w.id = a.workplace_id
    WHERE a.valid_until IS NULL AND private_isg.notice_kind_available('risk_assessment')
    UNION ALL
    SELECT 'equipment', c.id, c.name, e.equipment_id, e.serial_tag,
           NULL::date, private_isg.notice_window('equipment')
    FROM private_isg.equipment_items e JOIN scoped c ON c.id = e.company_id
    LEFT JOIN LATERAL (
      SELECT i.next_due_on FROM private_isg.equipment_inspections i
      WHERE i.equipment_id = e.equipment_id
      ORDER BY i.performed_on DESC, i.inspection_id DESC LIMIT 1
    ) latest ON true
    WHERE NOT e.is_archived AND latest.next_due_on IS NULL
      AND private_isg.notice_kind_available('equipment')
    UNION ALL
    SELECT 'training', c.id, c.name, (scope->>'id')::uuid,
           s.title || ' · ' || coalesce(scope->>'group_name', ''), NULL::date, 30
    FROM private_isg.pilot_training_sessions s
    CROSS JOIN LATERAL jsonb_array_elements(s.education->'scopes') scope
    JOIN scoped c ON c.id = (scope->>'company_id')::uuid
    WHERE private_isg.expert_session_visible(s.owner_id, s.id, actor)
      AND s.deleted_at IS NULL AND scope->>'valid_until' IS NULL
      AND private_isg.notice_kind_available('training')
    UNION ALL
    SELECT 'emergency_plan', c.id, c.name, v.plan_id,
           coalesce(w.name, v.scope), NULL::date,
           private_isg.notice_window('emergency_plan')
    FROM private_isg.emergency_plan_versions v JOIN scoped c ON c.id = v.company_id
    LEFT JOIN private_isg.workplaces w ON w.id = v.workplace_id
    WHERE NOT v.is_deleted AND v.state = 'active' AND v.valid_until IS NULL
      AND private_isg.notice_kind_available('emergency_plan')
    UNION ALL
    SELECT 'document', c.id, c.name, o.obligation_id, o.title,
           NULL::date, o.notice_days
    FROM private_isg.document_obligations o JOIN scoped c ON c.id = o.company_id
    LEFT JOIN LATERAL (
      SELECT x.valid_until FROM private_isg.document_obligation_records x
      WHERE x.obligation_id = o.obligation_id
      ORDER BY x.issued_on DESC, x.record_id DESC LIMIT 1
    ) latest ON true
    WHERE NOT o.is_archived AND latest.valid_until IS NULL
      AND private_isg.notice_kind_available('document')
  ),
  enriched AS MATERIALIZED (
    SELECT b.*,
      CASE b.kind
        WHEN 'katip_contract' THEN (SELECT k.starts_on FROM private_isg.katip_contracts k
                                    WHERE k.contract_id = b.record_id)
        WHEN 'appointment' THEN (SELECT a.starts_on FROM private_isg.appointments a
                                 WHERE a.appointment_id = b.record_id)
        WHEN 'completed_drill' THEN (SELECT d.held_on FROM private_isg.pilot_completed_drills d
                                     WHERE d.record_id = b.record_id)
        WHEN 'personnel_certificate' THEN (SELECT p.issued_on FROM private_isg.pilot_personnel_certificates p
                                           WHERE p.record_id = b.record_id)
        WHEN 'file' THEN (SELECT (f.created_at AT TIME ZONE 'Europe/Istanbul')::date
                          FROM private_isg.file_library_entries f WHERE f.entry_id = b.record_id)
        WHEN 'risk_assessment' THEN (SELECT coalesce(a.base_assessment_on, (a.created_at AT TIME ZONE 'Europe/Istanbul')::date)
                                     FROM private_isg.risk_assessments a WHERE a.assessment_id = b.record_id)
        WHEN 'equipment' THEN (SELECT coalesce(
                                  (SELECT i.performed_on FROM private_isg.equipment_inspections i
                                   WHERE i.equipment_id = e.equipment_id
                                   ORDER BY i.performed_on DESC, i.inspection_id DESC LIMIT 1),
                                  (e.created_at AT TIME ZONE 'Europe/Istanbul')::date)
                                FROM private_isg.equipment_items e WHERE e.equipment_id = b.record_id)
        WHEN 'emergency_plan' THEN (SELECT v.prepared_on FROM private_isg.emergency_plan_versions v
                                    WHERE v.plan_id = b.record_id AND v.state = 'active' LIMIT 1)
        WHEN 'document' THEN (SELECT coalesce(
                                (SELECT x.issued_on FROM private_isg.document_obligation_records x
                                 WHERE x.obligation_id = o.obligation_id
                                 ORDER BY x.issued_on DESC, x.record_id DESC LIMIT 1),
                                (o.created_at AT TIME ZONE 'Europe/Istanbul')::date)
                              FROM private_isg.document_obligations o WHERE o.obligation_id = b.record_id)
        WHEN 'training' THEN (SELECT s.held_on FROM private_isg.pilot_training_sessions s
                              WHERE private_isg.expert_session_visible(s.owner_id, s.id, actor)
                                AND s.deleted_at IS NULL
                                AND EXISTS (SELECT 1 FROM jsonb_array_elements(s.education->'scopes') scope
                                            WHERE scope->>'id' = b.record_id::text) LIMIT 1)
        ELSE NULL::date
      END AS recorded_on,
      CASE WHEN b.kind = 'file' THEN
        (SELECT f.category FROM private_isg.file_library_entries f WHERE f.entry_id = b.record_id)
      END AS file_category,
      CASE WHEN b.kind = 'training' THEN (
        SELECT s.id FROM private_isg.pilot_training_sessions s
        WHERE private_isg.expert_session_visible(s.owner_id, s.id, actor)
          AND s.deleted_at IS NULL
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(s.education->'scopes') scope
                      WHERE scope->>'id' = b.record_id::text) LIMIT 1
      ) ELSE b.record_id END AS source_id
    FROM base b
  ),
  classified AS MATERIALIZED (
    SELECT e.*, CASE
      WHEN e.due_on IS NULL THEN 'undated'
      WHEN e.due_on < today THEN 'expired'
      WHEN e.due_on <= today + coalesce(e.window_days, 30) THEN 'soon'
      ELSE 'current' END AS status
    FROM enriched e
  ),
  typed AS (
    SELECT * FROM classified r
    WHERE (p_kind IS NULL OR r.kind = p_kind OR (r.kind = 'file' AND CASE p_kind
        WHEN 'risk_assessment' THEN r.file_category = 'risk_assessment'
        WHEN 'training' THEN r.file_category = 'training_material'
        WHEN 'equipment' THEN r.file_category IN ('inspection_report', 'measurement_report')
        WHEN 'emergency_plan' THEN r.file_category = 'emergency_plan'
        WHEN 'personnel_certificate' THEN r.file_category = 'personnel_document'
        WHEN 'katip_contract' THEN r.file_category = 'contract'
        ELSE false END))
      AND (coalesce(p_query, '') = '' OR r.title ILIKE '%' || p_query || '%'
           OR r.company_name ILIKE '%' || p_query || '%')
  ),
  filtered AS (
    SELECT * FROM typed WHERE p_status IS NULL OR status = p_status
  ),
  selected AS (
    SELECT * FROM filtered
    ORDER BY due_on NULLS LAST, recorded_on DESC NULLS LAST, company_name, kind, record_id
    OFFSET p_offset LIMIT 30
  )
  SELECT jsonb_build_object(
    'schema_version', 2, 'owner_id', actor, 'company_id', p_company, 'today', today,
    'current', (SELECT count(*) FROM typed WHERE status = 'current'),
    'soon', (SELECT count(*) FROM typed WHERE status = 'soon'),
    'expired', (SELECT count(*) FROM typed WHERE status = 'expired'),
    'undated', (SELECT count(*) FROM typed WHERE status = 'undated'),
    'has_more', (SELECT count(*) FROM filtered) > p_offset + 30,
    'rows', coalesce((SELECT jsonb_agg(to_jsonb(s)
      ORDER BY s.due_on NULLS LAST, s.recorded_on DESC NULLS LAST,
               s.company_name, s.kind, s.record_id) FROM selected s), '[]'::jsonb)
  ) INTO answer;
  RETURN answer;
END $$;

REVOKE ALL ON FUNCTION public.isg_pilot_followup_v2(uuid, text, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.isg_pilot_followup_v2(uuid, text, text, text, integer) TO authenticated;

-- Organization sessions go through the expert RPC's fixed allowlist. Keep its
-- current routing body (which other migrations may have extended) and add only
-- this read endpoint.
DO $$
DECLARE definition text;
BEGIN
  definition := pg_catalog.pg_get_functiondef(
    'private_isg.expert_rpc(uuid,text,jsonb)'::pg_catalog.regprocedure);
  IF definition NOT LIKE '%''isg_pilot_followup_v1''%' THEN
    RAISE EXCEPTION 'EXPERT_RPC_ALLOWLIST_CHANGED';
  END IF;
  EXECUTE replace(definition,
    '''isg_pilot_followup_v1''',
    '''isg_pilot_followup_v1'',''isg_pilot_followup_v2''');
END $$;

NOTIFY pgrst, 'reload schema';
