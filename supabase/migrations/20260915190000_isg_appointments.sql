-- P10 client slice: the surface behind "Atama ve Temsilciler".
-- Additive. No rollout row is added and none is opened: this rides on the
-- `modules` feature and the `appointment` module switch P10 already created.
--
-- The P10 core built the appointment, its ending, and the one rule that matters:
-- the same person cannot hold two overlapping appointments of the same kind in
-- the same scope, enforced by an exclusion constraint rather than by a check
-- anyone can forget. Two things were missing rather than merely unreachable:
--
--   1. No client boundary, and no ownership check. `module_scope` proves the
--      workplace belongs to the company, never that the company belongs to the
--      caller.
--   2. The plan lists the basis of an appointment among its fields — a worker
--      representative is elected, support staff are appointed — and there was
--      no column for it, nor for where the appointment letter is kept.
--
-- Five things this slice makes structurally impossible:
--   1. Another owner's appointment, employee or workplace cannot be reached.
--   2. The same person cannot hold two overlapping appointments of the same
--      kind in the same scope. The constraint owns that rule; correcting an
--      end date is guarded by the same constraint rather than by a second
--      check written beside it.
--   3. Nobody is ever labelled qualified for a role. There is no field for it,
--      the schema has nowhere to put one, and every read says so.
--   4. The product never says how many representatives or support staff a
--      workplace needs. No approved count catalogue exists, so the read
--      reports that the required number is unknown rather than implying zero
--      or enough.
--   5. An appointment cannot end before it began, and ending it is a change to
--      that appointment, never a new one. Correcting an end date goes through
--      the same exclusion constraint, so it cannot be stretched over the
--      person's next appointment in the same role.
BEGIN;
SET LOCAL lock_timeout='5s';

-- Why this person holds the role, and where the letter is. A representative is
-- elected by the workers; support staff are appointed by the employer. Saying
-- which is the point of the field, so the boundary demands it.
ALTER TABLE private_isg.appointments
  ADD COLUMN basis text CHECK(basis IS NULL OR basis IN ('elected','appointed')),
  ADD COLUMN basis_note text CHECK(basis_note IS NULL OR length(basis_note)<=500),
  -- The tracker holds a reference, never the letter itself.
  ADD COLUMN letter_location text CHECK(letter_location IS NULL OR length(letter_location)<=300);

CREATE TABLE private_isg.appointment_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX appointment_receipt_company_idx ON private_isg.appointment_receipts(company_id,actor_id);
ALTER TABLE private_isg.appointment_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- The kinds an appointment can be, as the schema already fixes them. A table so
-- the client is offered exactly what the server accepts.
CREATE TABLE private_isg.appointment_kinds (
  kind text PRIMARY KEY CHECK(kind IN ('representative','support_staff','team_member','first_aid','fire_team')),
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 99),
  -- Which basis the product expects for this kind. A suggestion for the form,
  -- never a rule: the expert states what actually happened.
  usual_basis text NOT NULL CHECK(usual_basis IN ('elected','appointed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(ordinal)
);
INSERT INTO private_isg.appointment_kinds(kind,ordinal,usual_basis) VALUES
  ('representative',1,'elected'),('support_staff',2,'appointed'),('team_member',3,'appointed'),
  ('first_aid',4,'appointed'),('fire_team',5,'appointed');
ALTER TABLE private_isg.appointment_kinds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- Where an appointment stands today. Nothing is stored: the answer comes from
-- its own dates at read time, so no row can carry yesterday's answer.
CREATE FUNCTION private_isg.appointment_status(p_starts_on date,p_ends_before date,p_today date) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_starts_on>p_today THEN RETURN 'upcoming'; END IF;
  IF p_ends_before IS NOT NULL AND p_ends_before<=p_today THEN RETURN 'ended'; END IF;
  RETURN 'active';
END $$;

CREATE FUNCTION private_isg.appointment_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.module_gate('appointment',p_write);
END $$;

CREATE FUNCTION private_isg.require_appointment_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
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
END $$;

-- One appointment as the board sees it.
CREATE FUNCTION private_isg.appointment_row(p_appointment uuid,p_today date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.appointments; person private_isg.employees;
  place private_isg.workplaces; usual text; shown_state text;
BEGIN
  SELECT * INTO entry FROM private_isg.appointments WHERE appointment_id=p_appointment;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO person FROM private_isg.employees
    WHERE company_id=entry.company_id AND id=entry.employee_id;
  SELECT * INTO place FROM private_isg.workplaces
    WHERE company_id=entry.company_id AND id=entry.scope_workplace_id;
  SELECT usual_basis INTO usual FROM private_isg.appointment_kinds WHERE kind=entry.kind;
  shown_state:=private_isg.appointment_status(entry.starts_on,entry.ends_before,p_today);
  RETURN jsonb_build_object(
    'id',entry.appointment_id,'company_id',entry.company_id,
    'employee_id',entry.employee_id,'employee_name',person.full_name,
    'employee_archived',coalesce(person.is_archived,false),
    'workplace_id',entry.scope_workplace_id,'workplace_name',place.name,
    'kind',entry.kind,'usual_basis',usual,
    'starts_on',entry.starts_on,'ends_before',entry.ends_before,
    'state',shown_state,'state_authority','computed_at_read',
    'basis',entry.basis,'basis_note',entry.basis_note,
    -- The product holds no letter, only a note of where it is.
    'letter_location',entry.letter_location,'letter_stored',false,
    -- No legal condition was checked, and there is nowhere to record that one
    -- was. Holding a role is not the same as being qualified for it.
    'qualification_verified',false,
    -- No approved catalogue says how many a workplace needs.
    'required_count_known',false,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.read_appointments(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_role text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date;
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_appointment_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog',
      'kinds',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',k.kind,'ordinal',k.ordinal,
          'usual_basis',k.usual_basis) ORDER BY k.ordinal),'[]'::jsonb)
        FROM private_isg.appointment_kinds k),
      'bases',jsonb_build_array('elected','appointed'),
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name)
          ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
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
    PERFORM 1 FROM private_isg.appointments a
      JOIN public.companies c ON c.id=a.company_id AND c.user_id=actor
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
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), page AS (
    SELECT a.appointment_id,a.company_id,s.name AS company_name,a.employee_id,e.full_name AS employee_name,
      a.scope_workplace_id,w.name AS workplace_name,a.kind AS role_kind,a.starts_on,
      private_isg.appointment_status(a.starts_on,a.ends_before,today) AS entry_state,
      -- Active first, then what is about to begin, then what is over.
      row_number() OVER (ORDER BY
        CASE private_isg.appointment_status(a.starts_on,a.ends_before,today)
          WHEN 'active' THEN 0 WHEN 'upcoming' THEN 1 ELSE 2 END,
        a.starts_on DESC,s.name,w.name,e.full_name,a.appointment_id) AS ordinal
    FROM private_isg.appointments a
    JOIN scope s ON s.id=a.company_id
    JOIN private_isg.employees e ON e.company_id=a.company_id AND e.id=a.employee_id
    JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.scope_workplace_id
    WHERE w.owner_id=actor AND NOT w.is_archived
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
END $$;

CREATE FUNCTION private_isg.mutate_appointments(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.appointment_receipts;
  result jsonb; answer jsonb; appointment uuid; entry private_isg.appointments;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_appointment_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    -- No qualification field of any kind: holding a role is not being
    -- qualified for it, and nothing here may say otherwise.
    WHEN 'record_appointment' THEN ARRAY['employee_id','kind','workplace_id','starts_on','ends_before',
      'basis','basis_note','letter_location']
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
      AND id=(p_payload->>'workplace_id')::uuid AND owner_id=actor AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    answer:=private_isg.record_appointment(p_company,(p_payload->>'employee_id')::uuid,
      p_payload->>'kind',(p_payload->>'workplace_id')::uuid,
      (p_payload->>'starts_on')::date,(p_payload->>'ends_before')::date,NULL,stamp);
    appointment:=(answer->>'appointment_id')::uuid;
    UPDATE private_isg.appointments SET basis=p_payload->>'basis',
      basis_note=nullif(btrim(coalesce(p_payload->>'basis_note','')),''),
      letter_location=nullif(btrim(coalesce(p_payload->>'letter_location','')),'')
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
END $$;

CREATE FUNCTION public.isg_appointments_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_role text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_appointments(p_company,p_kind,p_query,p_state,p_workplace,p_role,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_appointments_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_appointments(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.appointment_status(date,date,date),
  private_isg.appointment_gate(boolean),
  private_isg.require_appointment_company(uuid,boolean),
  private_isg.appointment_row(uuid,date),
  private_isg.read_appointments(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_appointments(uuid,text,uuid,uuid,jsonb),
  public.isg_appointments_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_appointments_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_appointments(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_appointments(uuid,text,uuid,uuid,jsonb),
  public.isg_appointments_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_appointments_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
