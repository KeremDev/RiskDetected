-- P11 first client slice: the document obligation tracker behind "Evrak Takibi".
-- Additive. The rollout row is NOT opened here: switching a feature on stays a
-- separate, human decision, exactly as it is for personnel and nonconformity.
--
-- Three things are made structurally impossible rather than merely discouraged:
--   1. A health record cannot be tracked here. The kind catalogue is a fixed
--      set in the schema, so no insert can add one without a new migration.
--   2. A status is never stored. Missing, due soon and expired are computed
--      from the dates at read time, so no row can carry a stale claim.
--   3. No file is attached. There is no asset column at all, because P04 will
--      not promote an upload without a clean scan verdict and no scanner runs.
--      What is kept is the expert's own reference to where the original is.
-- The product never asserts a legal duty of its own: an obligation is the
-- expert's declaration, and calling one 'legal' demands the reference the
-- expert is relying on.
BEGIN;
SET LOCAL lock_timeout='5s';

ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports','notifications','personal_notes','billing_lifecycle',
    'campaigns','observability','score','document_tracking'));
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

CREATE FUNCTION private_isg.require_document_tracking_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.document_tracking_gate(p_write);
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
NOTIFY pgrst,'reload schema';
COMMIT;
