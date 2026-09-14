-- PILOT BUNDLE — Evrak Takibi (P11 document obligation tracker) for the live
-- P05 pilot account allowlist. This is NOT the development migration chain.
--
-- Development sources, in order:
--   supabase/migrations/20260914210000_isg_document_tracking.sql
--   supabase/migrations/20260914230000_isg_document_portfolio.sql
--
-- Both are reproduced verbatim except for the two changes named below. Unlike
-- the equipment bundle, nothing had to be dropped: this slice never touched
-- `file_assets` to begin with — it deliberately attaches no file at all and
-- keeps only the expert's own reference to where the original is.
--
-- DELIBERATE DIVERGENCES, both narrowing:
--   1. `require_document_tracking_company` carries the two P05 pilot gates, so
--      the module is reachable only by an allowlisted pilot account and only
--      for a company that account was granted.
--   2. `read_document_portfolio` gains the account-level pilot gate, so an
--      account with no enrolment gets the closed answer rather than an empty
--      portfolio.
-- The three guarantees the development header states are untouched: a health
-- record has no code to arrive under, no status is stored, and no file is
-- attached anywhere.
SET LOCAL lock_timeout='5s';

ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','modules','document_tracking'));
INSERT INTO private_isg.rollout(feature) VALUES('document_tracking');
-- The kinds an obligation can be about. The allowed set lives in the schema, so
-- a health record has no code to arrive under.
CREATE TABLE private_isg.document_obligation_kinds (
  kind_code text PRIMARY KEY CHECK(kind_code IN ('risk_assessment','emergency_plan','drill_record',
    'training_record','board_minutes','appointment_letter','ppe_handover','equipment_inspection',
    'measurement_report','service_contract','annual_work_plan','annual_training_plan','permit_form',
    'contractor_file','approved_notebook','other')),
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 999),
  -- The default period a copy stays good, in days, when the product has a
  -- customary one. NULL means the expert decides for this company.
  default_validity_days integer CHECK(default_validity_days IS NULL OR default_validity_days BETWEEN 1 AND 3650),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(ordinal)
);
INSERT INTO private_isg.document_obligation_kinds(kind_code,ordinal,default_validity_days) VALUES
  ('risk_assessment',1,NULL),('emergency_plan',2,NULL),('drill_record',3,365),
  ('training_record',4,NULL),('board_minutes',5,NULL),('appointment_letter',6,NULL),
  ('ppe_handover',7,NULL),('equipment_inspection',8,365),('measurement_report',9,NULL),
  ('service_contract',10,NULL),('annual_work_plan',11,365),('annual_training_plan',12,365),
  ('permit_form',13,NULL),('contractor_file',14,NULL),('approved_notebook',15,NULL),('other',16,NULL);

-- One tracked obligation. A NULL workplace means the whole company.
CREATE TABLE private_isg.document_obligations (
  obligation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL,
  workplace_id uuid,
  kind_code text NOT NULL REFERENCES private_isg.document_obligation_kinds(kind_code),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=160),
  -- Who says this document is owed. 'expert' is the expert's own decision and
  -- is the default; 'legal' additionally demands the reference relied upon.
  basis text NOT NULL DEFAULT 'expert' CHECK(basis IN ('expert','legal')),
  legal_ref text CHECK(legal_ref IS NULL OR length(legal_ref)<=300),
  CHECK(basis<>'legal' OR (legal_ref IS NOT NULL AND btrim(legal_ref)<>'')),
  -- How long one copy stays good. NULL means this obligation has no expiry of
  -- its own and a recorded copy simply stands.
  validity_days integer CHECK(validity_days IS NULL OR validity_days BETWEEN 1 AND 3650),
  -- How early the tracker starts calling a copy due.
  notice_days integer NOT NULL DEFAULT 30 CHECK(notice_days BETWEEN 0 AND 365),
  responsible_contact text CHECK(responsible_contact IS NULL OR length(responsible_contact)<=120),
  note text CHECK(note IS NULL OR length(note)<=1000),
  is_archived boolean NOT NULL DEFAULT false,
  version bigint NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  -- A NULL workplace is the whole company and the key simply does not apply.
  -- A workplace that is actually deleted takes its own scoped rows with it,
  -- the same way the nonconformity tables do.
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
-- NULL workplaces are distinct to a UNIQUE constraint, so the two scopes need
-- their own partial indexes for the duplicate to be refused in both.
CREATE UNIQUE INDEX document_obligation_company_scope_idx
  ON private_isg.document_obligations(company_id,kind_code,title) WHERE workplace_id IS NULL AND NOT is_archived;
CREATE UNIQUE INDEX document_obligation_workplace_scope_idx
  ON private_isg.document_obligations(company_id,workplace_id,kind_code,title) WHERE workplace_id IS NOT NULL AND NOT is_archived;
CREATE INDEX document_obligation_owner_idx ON private_isg.document_obligations(company_id,owner_id);
CREATE INDEX document_obligation_workplace_idx ON private_isg.document_obligations(company_id,workplace_id);
CREATE INDEX document_obligation_kind_idx ON private_isg.document_obligations(kind_code);

-- One copy the company actually holds. There is no asset column: the file is
-- not stored, and the row cannot pretend otherwise.
CREATE TABLE private_isg.document_obligation_records (
  record_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obligation_id uuid NOT NULL REFERENCES private_isg.document_obligations(obligation_id) ON DELETE CASCADE,
  company_id uuid NOT NULL, owner_id uuid NOT NULL,
  issued_on date NOT NULL,
  valid_until date,
  document_no text CHECK(document_no IS NULL OR length(document_no)<=80),
  -- Where the original is kept. The tracker holds a reference, never the file.
  location_note text CHECK(location_note IS NULL OR length(location_note)<=300),
  recorded_by uuid NOT NULL REFERENCES public.profiles(id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  mutation_id uuid NOT NULL,
  CHECK(valid_until IS NULL OR valid_until>=issued_on),
  UNIQUE(obligation_id,mutation_id),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX document_obligation_record_scope_idx
  ON private_isg.document_obligation_records(obligation_id,issued_on DESC,record_id);
CREATE INDEX document_obligation_record_owner_idx ON private_isg.document_obligation_records(company_id,owner_id);
CREATE INDEX document_obligation_record_author_idx ON private_isg.document_obligation_records(recorded_by);

CREATE TABLE private_isg.document_tracking_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX document_tracking_receipt_company_idx ON private_isg.document_tracking_receipts(company_id,actor_id);

ALTER TABLE private_isg.document_obligation_kinds ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.document_obligations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.document_obligation_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.document_tracking_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- Missing, expired, due soon or valid, worked out from the dates at read time.
-- Nothing is stored, so no row can carry yesterday's answer.
CREATE FUNCTION private_isg.document_obligation_status(p_valid_until date,p_has_record boolean,
  p_notice_days integer,p_today date) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF NOT p_has_record THEN RETURN 'missing'; END IF;
  IF p_valid_until IS NULL THEN RETURN 'valid'; END IF;
  IF p_valid_until<p_today THEN RETURN 'expired'; END IF;
  IF p_valid_until<=p_today+p_notice_days THEN RETURN 'due_soon'; END IF;
  RETURN 'valid';
END $$;

-- The switch on its own, in the same shape as every other slice's gate, so the
-- rehearsal can close every feature and ask each one the same question.
CREATE FUNCTION private_isg.document_tracking_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='document_tracking' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- PILOT DIVERGENCE 1: the development function plus the two P05 pilot gates
-- `require_company` already applies live. A non-pilot account gets
-- FEATURE_UNAVAILABLE before ownership is even considered.
CREATE FUNCTION private_isg.require_document_tracking_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
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
END $$;


-- One obligation with its copies and the status those copies produce today.
CREATE FUNCTION private_isg.document_obligation_row(p_company uuid,p_obligation uuid,p_today date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.document_obligations; latest private_isg.document_obligation_records;
BEGIN
  SELECT * INTO entry FROM private_isg.document_obligations
    WHERE obligation_id=p_obligation AND company_id=p_company;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO latest FROM private_isg.document_obligation_records
    WHERE obligation_id=p_obligation ORDER BY issued_on DESC,recorded_at DESC LIMIT 1;
  RETURN jsonb_build_object('id',entry.obligation_id,'workplace_id',entry.workplace_id,
    'kind_code',entry.kind_code,'title',entry.title,'basis',entry.basis,'legal_ref',entry.legal_ref,
    'validity_days',entry.validity_days,'notice_days',entry.notice_days,
    'responsible_contact',entry.responsible_contact,'note',entry.note,
    'is_archived',entry.is_archived,'version',entry.version,
    'status',private_isg.document_obligation_status(latest.valid_until,latest.record_id IS NOT NULL,
      entry.notice_days,p_today),
    'status_authority','computed_at_read',
    'latest_issued_on',latest.issued_on,'latest_valid_until',latest.valid_until,
    'records',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.record_id,'issued_on',r.issued_on,
        'valid_until',r.valid_until,'document_no',r.document_no,'location_note',r.location_note,
        'recorded_at',r.recorded_at) ORDER BY r.issued_on DESC,r.recorded_at DESC),'[]'::jsonb)
      FROM private_isg.document_obligation_records r WHERE r.obligation_id=entry.obligation_id),
    -- The tracker holds a reference, never a stored copy of the document.
    'file_stored',false);
END $$;

CREATE FUNCTION private_isg.read_document_tracking(p_company uuid,p_kind text,p_query text,p_status text,
  p_workplace uuid,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
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
      FROM private_isg.workplaces w WHERE w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived;
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
    WHERE o.company_id=p_company AND o.owner_id=actor AND NOT o.is_archived
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
END $$;

CREATE FUNCTION private_isg.mutate_document_tracking(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
        AND company_id=p_company AND owner_id=actor AND NOT is_archived;
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
      WHERE obligation_id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF expected IS NULL OR obligation.version<>expected THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF p_action='archive_obligation' THEN
      UPDATE private_isg.document_obligations SET is_archived=true,version=version+1,updated_at=stamp
        WHERE obligation_id=target;
    ELSE
      IF p_payload ? 'workplace_id' AND p_payload->>'workplace_id' IS NOT NULL THEN
        PERFORM 1 FROM private_isg.workplaces WHERE id=(p_payload->>'workplace_id')::uuid
          AND company_id=p_company AND owner_id=actor AND NOT is_archived;
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
      WHERE obligation_id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;
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
      WHERE obligation_id=target AND company_id=p_company AND owner_id=actor;
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
END $$;

CREATE FUNCTION public.isg_document_tracking_read_v1(p_company uuid,p_kind text,p_query text,p_status text,
  p_workplace uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_document_tracking(p_company,p_kind,p_query,p_status,p_workplace,p_id)
$$;
CREATE FUNCTION public.isg_document_tracking_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_document_tracking(p_company,p_action,p_operation,p_mutation,p_payload)
$$;
REVOKE ALL ON FUNCTION private_isg.document_obligation_status(date,boolean,integer,date),
  private_isg.document_tracking_gate(boolean),
  private_isg.require_document_tracking_company(uuid,boolean),
  private_isg.document_obligation_row(uuid,uuid,date),
  private_isg.read_document_tracking(uuid,text,text,text,uuid,uuid),
  private_isg.mutate_document_tracking(uuid,text,uuid,uuid,jsonb),
  public.isg_document_tracking_read_v1(uuid,text,text,text,uuid,uuid),
  public.isg_document_tracking_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_document_tracking(uuid,text,text,text,uuid,uuid),
  private_isg.mutate_document_tracking(uuid,text,uuid,uuid,jsonb),
  public.isg_document_tracking_read_v1(uuid,text,text,text,uuid,uuid),
  public.isg_document_tracking_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
CREATE FUNCTION private_isg.read_document_portfolio(p_query text,p_status text,p_company uuid,
  p_kinds text[],p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
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
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
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
    WHERE o.owner_id=actor AND NOT o.is_archived
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
END $$;

CREATE FUNCTION public.isg_document_portfolio_v1(p_query text,p_status text,p_company uuid,
  p_kinds text[],p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_document_portfolio(p_query,p_status,p_company,p_kinds,p_limit,p_offset)
$$;
REVOKE ALL ON FUNCTION private_isg.read_document_portfolio(text,text,uuid,text[],integer,integer),
  public.isg_document_portfolio_v1(text,text,uuid,text[],integer,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_document_portfolio(text,text,uuid,text[],integer,integer),
  public.isg_document_portfolio_v1(text,text,uuid,text[],integer,integer) TO authenticated;
-- The switch this bundle exists to open. The pilot allowlist is what keeps the
-- audience narrow; this only decides whether the module answers at all.
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='document_tracking';
