-- Operational, owner-entered training register for the existing scoped pilot.
-- This does not publish a legal catalogue or mint P07 completion certificates.
-- Authentication, paid writes, pilot membership and expiry use the existing P05 gate.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';

CREATE TABLE private_isg.pilot_training_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL,
  title text NOT NULL CHECK(length(btrim(title)) BETWEEN 1 AND 200),
  trainer text NOT NULL CHECK(length(btrim(trainer)) BETWEEN 1 AND 200),
  location text NOT NULL DEFAULT '' CHECK(length(location)<=300),
  notes text NOT NULL DEFAULT '' CHECK(length(notes)<=2000),
  starts_at timestamptz NOT NULL CHECK(isfinite(starts_at)),
  duration_minutes integer NOT NULL CHECK(duration_minutes BETWEEN 1 AND 1440),
  valid_until date CHECK(valid_until IS NULL OR isfinite(valid_until)),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','completed','cancelled')),
  version bigint NOT NULL DEFAULT 1,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(company_id,id),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX pilot_training_company_idx ON private_isg.pilot_training_records(company_id,id);
CREATE INDEX pilot_training_owner_idx ON private_isg.pilot_training_records(owner_id);
CREATE TABLE private_isg.pilot_training_participants (
  company_id uuid NOT NULL, training_id uuid NOT NULL, employee_id uuid NOT NULL,
  employee_name text NOT NULL,
  attended boolean NOT NULL DEFAULT false,
  PRIMARY KEY(training_id,employee_id),
  FOREIGN KEY(company_id,training_id) REFERENCES private_isg.pilot_training_records(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id)
);
CREATE INDEX pilot_training_person_idx ON private_isg.pilot_training_participants(company_id,employee_id);
CREATE INDEX pilot_training_parent_idx ON private_isg.pilot_training_participants(company_id,training_id);
CREATE TABLE private_isg.pilot_training_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX pilot_training_receipt_company_idx ON private_isg.pilot_training_receipts(company_id,actor_id);
ALTER TABLE private_isg.pilot_training_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.pilot_training_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.pilot_training_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.pilot_training_records,private_isg.pilot_training_participants,
  private_isg.pilot_training_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.pilot_training_row(p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT to_jsonb(t)||jsonb_build_object('participants',coalesce((
    SELECT jsonb_agg(jsonb_build_object('id',p.employee_id,'name',p.employee_name,'attended',p.attended)
      ORDER BY p.employee_name,p.employee_id)
    FROM private_isg.pilot_training_participants p WHERE p.training_id=t.id AND p.company_id=t.company_id),'[]'::jsonb))
  FROM private_isg.pilot_training_records t WHERE t.company_id=p_company AND t.id=p_id
$$;

CREATE FUNCTION private_isg.pilot_training_read(p_company uuid,p_id uuid,p_after uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; rows jsonb; next_id uuid; total integer; completed integer;
BEGIN
  actor:=private_isg.require_company(p_company,false);
  IF p_id IS NOT NULL THEN
    rows:=private_isg.pilot_training_row(p_company,p_id);
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'rows',jsonb_build_array(rows));
  END IF;
  SELECT coalesce(jsonb_agg(private_isg.pilot_training_row(p_company,page.id) ORDER BY page.id DESC),'[]') INTO rows
    FROM (SELECT id FROM private_isg.pilot_training_records WHERE company_id=p_company AND owner_id=actor
      AND (p_after IS NULL OR id<p_after) ORDER BY id DESC LIMIT 50) page;
  IF jsonb_array_length(rows)=50 THEN next_id:=(rows->49->>'id')::uuid; END IF;
  SELECT count(*),count(*) FILTER(WHERE state='completed') INTO total,completed
    FROM private_isg.pilot_training_records WHERE company_id=p_company AND owner_id=actor;
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'rows',rows,
    'next_id',next_id,'total',total,'completed',completed);
END $$;

CREATE FUNCTION private_isg.pilot_training_save(p_company uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; prior private_isg.pilot_training_receipts; fingerprint bytea;
  t private_isg.pilot_training_records; target uuid; action text; result jsonb;
  people jsonb; person jsonb; person_id uuid; person_name text; selected_ids uuid[]:='{}';
  start_time timestamptz; until_date date; minutes integer;
BEGIN
  actor:=private_isg.require_company(p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
     OR octet_length(p_payload::text)>65536 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
    ('action','id','expected_version','title','trainer','location','notes','starts_at','duration_minutes','valid_until','participants')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action';
  IF action IS NULL OR action NOT IN ('save','complete','cancel') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':training:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.pilot_training_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response;
  END IF;
  target:=(p_payload->>'id')::uuid;
  IF target IS NOT NULL THEN
    SELECT * INTO t FROM private_isg.pilot_training_records WHERE id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF t.version IS DISTINCT FROM (p_payload->>'expected_version')::bigint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF t.state<>'planned' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TRAINING_LOCKED'; END IF;
  ELSIF action<>'save' OR coalesce((p_payload->>'expected_version')::bigint,0)<>0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  IF action='save' THEN
    start_time:=(p_payload->>'starts_at')::timestamptz;
    minutes:=(p_payload->>'duration_minutes')::integer;
    until_date:=(p_payload->>'valid_until')::date;
    IF start_time IS NULL OR NOT isfinite(start_time) OR minutes IS NULL OR minutes NOT BETWEEN 1 AND 1440
      OR length(btrim(coalesce(p_payload->>'title',''))) NOT BETWEEN 1 AND 200
      OR length(btrim(coalesce(p_payload->>'trainer',''))) NOT BETWEEN 1 AND 200
      OR length(coalesce(p_payload->>'location',''))>300 OR length(coalesce(p_payload->>'notes',''))>2000
      OR (until_date IS NOT NULL AND (NOT isfinite(until_date) OR until_date<(start_time AT TIME ZONE 'Europe/Istanbul')::date)) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    people:=p_payload->'participants';
    IF people IS NULL OR jsonb_typeof(people)<>'array' OR jsonb_array_length(people)>500 THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF target IS NULL THEN
      INSERT INTO private_isg.pilot_training_records(company_id,owner_id,title,trainer,location,notes,starts_at,duration_minutes,valid_until)
      VALUES(p_company,actor,btrim(p_payload->>'title'),btrim(p_payload->>'trainer'),coalesce(p_payload->>'location',''),
        coalesce(p_payload->>'notes',''),start_time,minutes,until_date) RETURNING id INTO target;
    ELSE
      UPDATE private_isg.pilot_training_records SET title=btrim(p_payload->>'title'),trainer=btrim(p_payload->>'trainer'),
        location=coalesce(p_payload->>'location',''),notes=coalesce(p_payload->>'notes',''),starts_at=start_time,
        duration_minutes=minutes,valid_until=until_date,version=version+1,updated_at=clock_timestamp() WHERE id=target;
    END IF;
    DELETE FROM private_isg.pilot_training_participants WHERE training_id=target;
    FOR person IN SELECT value FROM jsonb_array_elements(people) LOOP
      IF jsonb_typeof(person)<>'object' OR jsonb_typeof(person->'attended') IS DISTINCT FROM 'boolean'
        OR EXISTS(SELECT 1 FROM jsonb_object_keys(person) k WHERE k NOT IN ('id','attended')) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      person_id:=(person->>'id')::uuid;
      IF person_id IS NULL OR person_id=ANY(selected_ids) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT full_name INTO person_name FROM private_isg.employees WHERE company_id=p_company AND owner_id=actor AND id=person_id AND NOT is_archived FOR SHARE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_UNAVAILABLE'; END IF;
      IF (person->>'attended')::boolean AND start_time>clock_timestamp() THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_ATTENDANCE'; END IF;
      selected_ids:=array_append(selected_ids,person_id);
      INSERT INTO private_isg.pilot_training_participants VALUES(p_company,target,person_id,person_name,(person->>'attended')::boolean);
    END LOOP;
  ELSIF action='complete' THEN
    IF t.starts_at+make_interval(mins=>t.duration_minutes)>clock_timestamp() THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TRAINING_NOT_ENDED'; END IF;
    IF NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_participants WHERE training_id=target AND attended) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ATTENDANCE_REQUIRED'; END IF;
    UPDATE private_isg.pilot_training_records SET state='completed',completed_at=clock_timestamp(),version=version+1,updated_at=clock_timestamp() WHERE id=target;
  ELSE
    UPDATE private_isg.pilot_training_records SET state='cancelled',version=version+1,updated_at=clock_timestamp() WHERE id=target;
  END IF;
  result:=jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,
    'mutation_id',p_mutation,'row',private_isg.pilot_training_row(p_company,target));
  INSERT INTO private_isg.pilot_training_receipts(actor_id,mutation_id,company_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,fingerprint,result);
  RETURN result;
END $$;

CREATE FUNCTION public.isg_pilot_training_read_v1(p_company uuid,p_id uuid DEFAULT NULL,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.pilot_training_read(p_company,p_id,p_after) $$;
CREATE FUNCTION public.isg_pilot_training_save_v1(p_company uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.pilot_training_save(p_company,p_mutation,p_payload) $$;
REVOKE ALL ON FUNCTION private_isg.pilot_training_row(uuid,uuid),private_isg.pilot_training_read(uuid,uuid,uuid),
  private_isg.pilot_training_save(uuid,uuid,jsonb),public.isg_pilot_training_read_v1(uuid,uuid,uuid),
  public.isg_pilot_training_save_v1(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.pilot_training_read(uuid,uuid,uuid),private_isg.pilot_training_save(uuid,uuid,jsonb),
  public.isg_pilot_training_read_v1(uuid,uuid,uuid),public.isg_pilot_training_save_v1(uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
