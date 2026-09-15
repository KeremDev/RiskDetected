-- Risk Analizi: "geçerlilik süresini elle yazmama gerek yok, firmanın
-- tehlike sınıfına göre kendin otomatik getirebilirsin" — the workplace
-- already carries hazard_class (low/medium/high, i.e. az/tehlikeli/çok
-- tehlikeli), and 6331 sayılı Kanun m.12 fixes the renewal period by that
-- class: 6/4/2 years. finalize_risk_version now falls back to that legal
-- period when the expert leaves both the rule and the number blank, instead
-- of hard-requiring a typed number. Typing one still overrides it, same as
-- before (kept as period_source='unapproved_fixture', needs_review=true) —
-- only the previously-mandatory case changes.
--
-- risk_assessment_row and the catalog read now also surface the workplace's
-- hazard_class and the years it implies, so the client can prefill the
-- finalize sheet's field before the expert ever has to touch it.

CREATE OR REPLACE FUNCTION private_isg.risk_period_years_for_hazard_class(p_hazard_class text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT CASE p_hazard_class WHEN 'low' THEN 6 WHEN 'medium' THEN 4 WHEN 'high' THEN 2 ELSE NULL END
$function$;

ALTER TABLE private_isg.risk_assessment_versions DROP CONSTRAINT risk_assessment_versions_period_source_check;
ALTER TABLE private_isg.risk_assessment_versions ADD CONSTRAINT risk_assessment_versions_period_source_check
  CHECK ((period_source IS NULL) OR (period_source = ANY (ARRAY['rule_version'::text, 'unapproved_fixture'::text, 'hazard_class'::text])));

CREATE OR REPLACE FUNCTION private_isg.finalize_risk_version(p_assessment uuid, p_version integer, p_expected_current integer, p_verified_by uuid, p_rule_code text, p_period_years integer, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE entry private_isg.risk_assessments; revision private_isg.risk_assessment_versions;
  years integer; source text; review boolean:=false; valid date; wclass text;
BEGIN
  PERFORM private_isg.risk_gate(true);
  IF p_assessment IS NULL OR p_version IS NULL OR p_expected_current IS NULL OR p_verified_by IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessments WHERE assessment_id=p_assessment FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO revision FROM private_isg.risk_assessment_versions AS r
    WHERE r.assessment_id=p_assessment AND r.version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF revision.state='final' THEN RETURN jsonb_build_object('schema_version',1,'assessment_id',p_assessment,
    'version',p_version,'state','final','valid_until',revision.valid_until,'replayed',true); END IF;
  IF entry.current_version<>p_expected_current THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  IF revision.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_FINALIZED'; END IF;
  IF revision.kind='full' THEN
    IF p_rule_code IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW';
    ELSIF p_period_years IS NOT NULL THEN
      IF p_period_years NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      years:=p_period_years; source:='unapproved_fixture'; review:=true;
    ELSE
      -- No number typed and no rule chosen: the workplace's own hazard class
      -- fixes the period by law, the same number the expert would have typed.
      SELECT w.hazard_class INTO wclass FROM private_isg.workplaces w WHERE w.id=entry.workplace_id;
      years:=private_isg.risk_period_years_for_hazard_class(wclass);
      IF years IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      source:='hazard_class'; review:=false;
    END IF;
    -- The period runs from the real assessment date, not from today.
    valid:=(revision.assessment_on+make_interval(years=>years))::date;
  ELSE
    -- A rescan, a metadata correction or a scoped revision never resets the
    -- whole workplace period.
    IF p_rule_code IS NOT NULL OR p_period_years IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    valid:=entry.valid_until;
    SELECT r.period_years,r.period_source,r.period_needs_review INTO years,source,review FROM private_isg.risk_assessment_versions r WHERE r.assessment_id=p_assessment AND r.version=entry.current_version;
  END IF;
  UPDATE private_isg.risk_assessment_versions AS r SET state='superseded',updated_at=p_now
    WHERE r.assessment_id=p_assessment AND r.state='final';
  UPDATE private_isg.risk_assessment_versions AS r SET state='final',verified_by=p_verified_by,finalized_at=p_now,
    period_years=years,period_source=source,period_needs_review=review,valid_until=valid,updated_at=p_now
    WHERE r.assessment_id=p_assessment AND r.version=p_version;
  UPDATE private_isg.risk_assessments SET current_version=p_version,updated_at=p_now,
    base_assessment_on=CASE WHEN revision.kind='full' THEN revision.assessment_on ELSE base_assessment_on END,
    valid_until=valid WHERE assessment_id=p_assessment;
  RETURN jsonb_build_object('schema_version',1,'assessment_id',p_assessment,'version',p_version,'kind',revision.kind,
    'state','final','assessment_on',revision.assessment_on,'valid_until',valid,'period_years',years,
    'period_source',source,'period_needs_review',review,'replayed',false);
END $function$;

CREATE OR REPLACE FUNCTION private_isg.risk_assessment_row(p_assessment uuid, p_today date, p_history boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE entry private_isg.risk_assessments; current private_isg.risk_assessment_versions;
  draft private_isg.risk_assessment_versions; notice integer:=private_isg.risk_notice_days();
  -- Prefixed so it can never be mistaken for the version column of the same
  -- name in the queries below.
  shown_state text; whazard text;
BEGIN
  SELECT * INTO entry FROM private_isg.risk_assessments WHERE assessment_id=p_assessment;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO current FROM private_isg.risk_assessment_versions
    WHERE assessment_id=p_assessment AND state='final' LIMIT 1;
  SELECT * INTO draft FROM private_isg.risk_assessment_versions
    WHERE assessment_id=p_assessment AND state='draft' LIMIT 1;
  SELECT w.hazard_class INTO whazard FROM private_isg.workplaces w WHERE w.id=entry.workplace_id;
  shown_state:=private_isg.risk_assessment_status(entry.current_version,current.version IS NOT NULL,
    entry.valid_until,notice,p_today);
  RETURN jsonb_build_object(
    'id',entry.assessment_id,'company_id',entry.company_id,'workplace_id',entry.workplace_id,
    'current_version',entry.current_version,'base_assessment_on',entry.base_assessment_on,
    'valid_until',entry.valid_until,'created_at',entry.created_at,
    'state',shown_state,'state_group',private_isg.risk_assessment_group(shown_state),
    'state_authority','computed_at_read','notice_days',notice,
    -- The document that stands today, and how its period was arrived at.
    'current_kind',current.kind,'current_assessment_on',current.assessment_on,
    'current_revision_on',current.revision_on,'current_finalized_at',current.finalized_at,
    'period_years',current.period_years,'period_source',current.period_source,
    'period_needs_review',CASE WHEN current.version IS NULL THEN NULL
      ELSE coalesce(current.period_needs_review,false) END,
    'date_needs_review',coalesce(current.date_needs_review,false),
    'source_drift',coalesce(current.source_drift,false),'drift_note',current.drift_note,
    'current_file_asset_id',current.file_asset_id,
    -- The workplace's own hazard class and the period it implies, so the
    -- client can offer that number before the expert ever types one.
    'workplace_hazard_class',whazard,
    'workplace_suggested_period_years',private_isg.risk_period_years_for_hazard_class(whazard),
    -- A draft is work in progress, never the document. It is reported beside
    -- the state rather than inside it.
    'has_open_draft',draft.version IS NOT NULL,'draft_version',draft.version,'draft_kind',draft.kind,
    'draft_assessment_on',draft.assessment_on,'draft_reason',draft.reason,
    'source_link_count',(SELECT count(*) FROM private_isg.risk_source_links l
      WHERE l.assessment_id=p_assessment AND l.version=coalesce(draft.version,current.version)),
    'versions',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('version',v.version,'edit_revision',v.edit_revision,'cancellation_note',v.cancellation_note,'kind',v.kind,
          'previous_version',v.previous_version,'assessment_on',v.assessment_on,'revision_on',v.revision_on,
          'scope',v.scope,'reason',v.reason,'state',v.state,'finalized_at',v.finalized_at,
          'period_years',v.period_years,'period_source',v.period_source,
          'period_needs_review',v.period_needs_review,'date_needs_review',v.date_needs_review,
          'valid_until',v.valid_until,'source_drift',v.source_drift,'drift_note',v.drift_note,
          'file_asset_id',v.file_asset_id,
          'sources',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',l.link_id,'analysis_id',l.analysis_id,
              'finding_id',l.finding_id,'source_version',l.source_version,'selected_at',l.selected_at)
              ORDER BY l.selected_at),'[]'::jsonb)
            FROM private_isg.risk_source_links l WHERE l.assessment_id=v.assessment_id AND l.version=v.version),
          'impacts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.impact_id,'target_kind',i.target_kind,
              'target_ref',i.target_ref,'action',i.action,'note',i.note) ORDER BY i.created_at),'[]'::jsonb)
            FROM private_isg.revision_impacts i WHERE i.assessment_id=v.assessment_id AND i.version=v.version))
          ORDER BY v.version DESC),'[]'::jsonb)
       FROM private_isg.risk_assessment_versions v WHERE v.assessment_id=p_assessment) END,
    -- The legacy photo analysis is a source, never a risk assessment of its own.
    'analysis_is_not_an_assessment',true,'legacy_analysis_written',false);
END $function$;

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
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
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
      JOIN public.companies c ON c.id=a.company_id AND c.user_id=actor AND private_isg.p05_pilot_can_read(actor,c.id)
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
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND private_isg.p05_pilot_can_read(actor,c.id) AND NOT c.is_archived
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
    WHERE a.owner_id=actor AND private_isg.p05_pilot_can_read(actor,a.company_id) AND NOT w.is_archived
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
END $function$;
