-- D2 workspace training slice. NOT DEPLOYED and default OFF.
-- Existing personal endpoints keep their owner-only contract. OSGB callers use
-- only the workspace endpoints below; no direct table privilege is added.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check
  CHECK(entity_type IN ('workspace','membership','invitation','company','assignment','seat','subscription',
    'wallet','asset','handover','workplace','department','employee','domain','training'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check
  CHECK(aggregate_type IN ('workspace','membership','invitation','company','assignment','seat','subscription',
    'wallet','asset','handover','workplace','department','employee','domain','training'));

ALTER TABLE private_isg.pilot_training_sessions ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.pilot_training_sessions ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.pilot_training_sessions ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.pilot_training_sessions ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.pilot_training_sessions ADD CONSTRAINT pilot_training_sessions_workspace_fk
  FOREIGN KEY(workspace_id) REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT;
ALTER TABLE private_isg.pilot_training_sessions ADD CONSTRAINT pilot_training_sessions_workspace_identity_unique
  UNIQUE(workspace_id,id);

ALTER TABLE private_isg.pilot_training_records ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.pilot_training_records ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.pilot_training_records ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.pilot_training_records ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.pilot_training_records ADD CONSTRAINT pilot_training_records_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.pilot_training_records ADD CONSTRAINT pilot_training_records_workspace_session_fk
  FOREIGN KEY(workspace_id,session_id)
  REFERENCES private_isg.pilot_training_sessions(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.pilot_training_records ADD CONSTRAINT pilot_training_records_workspace_identity_unique
  UNIQUE(workspace_id,company_id,id);

ALTER TABLE private_isg.pilot_training_participants ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.pilot_training_participants ADD CONSTRAINT pilot_training_participants_workspace_training_fk
  FOREIGN KEY(workspace_id,company_id,training_id)
  REFERENCES private_isg.pilot_training_records(workspace_id,company_id,id) ON DELETE CASCADE;
ALTER TABLE private_isg.pilot_training_participants ADD CONSTRAINT pilot_training_participants_workspace_employee_fk
  FOREIGN KEY(workspace_id,company_id,employee_id)
  REFERENCES private_isg.employees(workspace_id,company_id,id) ON DELETE RESTRICT;

ALTER TABLE private_isg.pilot_training_session_revisions ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.pilot_training_session_revisions ADD CONSTRAINT pilot_training_revisions_workspace_session_fk
  FOREIGN KEY(workspace_id,session_id)
  REFERENCES private_isg.pilot_training_sessions(workspace_id,id) ON DELETE RESTRICT;

UPDATE private_isg.pilot_training_records r
SET workspace_id=c.workspace_id,created_by_user_id=r.owner_id,updated_by_user_id=r.owner_id
FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.pilot_training_sessions s
SET workspace_id=q.workspace_id,created_by_user_id=s.owner_id,updated_by_user_id=s.owner_id
FROM (
  SELECT session_id,min(workspace_id::text)::uuid workspace_id
  FROM private_isg.pilot_training_records
  WHERE session_id IS NOT NULL AND workspace_id IS NOT NULL
  GROUP BY session_id HAVING count(DISTINCT workspace_id)=1
) q WHERE q.session_id=s.id;
UPDATE private_isg.pilot_training_sessions s
SET workspace_id=w.id,created_by_user_id=s.owner_id,updated_by_user_id=s.owner_id
FROM private_isg.workspaces w
WHERE s.workspace_id IS NULL AND s.owner_id IS NOT NULL AND w.kind='personal'
  AND w.personal_owner_user_id=s.owner_id;
UPDATE private_isg.pilot_training_participants p SET workspace_id=r.workspace_id
FROM private_isg.pilot_training_records r
WHERE r.id=p.training_id AND r.company_id=p.company_id AND r.workspace_id IS NOT NULL;
UPDATE private_isg.pilot_training_session_revisions v SET workspace_id=s.workspace_id
FROM private_isg.pilot_training_sessions s WHERE s.id=v.session_id AND s.workspace_id IS NOT NULL;

CREATE INDEX pilot_training_sessions_workspace_page
  ON private_isg.pilot_training_sessions(workspace_id,deleted_at,id);
CREATE INDEX pilot_training_records_workspace_page
  ON private_isg.pilot_training_records(workspace_id,company_id,state,id);
CREATE INDEX pilot_training_participants_workspace_person
  ON private_isg.pilot_training_participants(workspace_id,company_id,employee_id);

CREATE FUNCTION private_isg.workspace_training_session_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace private_isg.workspaces;
BEGIN
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='WORKSPACE_NOT_FOUND'; END IF;
  IF workspace.kind='osgb' AND NEW.owner_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_FORBIDDEN'; END IF;
  IF workspace.kind='personal' AND NEW.owner_id IS DISTINCT FROM workspace.personal_owner_user_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_MISMATCH'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.owner_id,NEW.created_by_user_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.owner_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pilot_training_sessions_workspace_scope_before
BEFORE INSERT OR UPDATE ON private_isg.pilot_training_sessions
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_training_session_invariant();

CREATE FUNCTION private_isg.workspace_training_record_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company public.companies; session private_isg.pilot_training_sessions; workspace private_isg.workspaces;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='COMPANY_NOT_FOUND'; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF NEW.workspace_id IS DISTINCT FROM company.workspace_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_SCOPE_CONFLICT'; END IF;
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.kind='osgb' AND NEW.owner_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_FORBIDDEN'; END IF;
  IF workspace.kind='personal' AND NEW.owner_id IS DISTINCT FROM company.user_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_MISMATCH'; END IF;
  SELECT * INTO session FROM private_isg.pilot_training_sessions
    WHERE id=NEW.session_id AND workspace_id=NEW.workspace_id FOR SHARE;
  IF session.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SESSION_SCOPE_CONFLICT'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.owner_id,NEW.session_id,NEW.created_by_user_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.owner_id,OLD.session_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pilot_training_records_workspace_scope_before
BEFORE INSERT OR UPDATE ON private_isg.pilot_training_records
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_training_record_invariant();

CREATE FUNCTION private_isg.workspace_training_participant_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  IF NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_records r
      WHERE r.workspace_id=NEW.workspace_id AND r.company_id=NEW.company_id AND r.id=NEW.training_id)
    OR NOT EXISTS(SELECT 1 FROM private_isg.employees e
      WHERE e.workspace_id=NEW.workspace_id AND e.company_id=NEW.company_id AND e.id=NEW.employee_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_SCOPE_CONFLICT'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.training_id,NEW.employee_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.training_id,OLD.employee_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pilot_training_participants_workspace_scope_before
BEFORE INSERT OR UPDATE ON private_isg.pilot_training_participants
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_training_participant_invariant();

CREATE FUNCTION private_isg.workspace_training_row(p_workspace uuid,p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object(
    'training_id',r.id,'session_id',r.session_id,'company_id',r.company_id,'title',r.title,
    'trainer',r.trainer,'method',s.method,'location',r.location,'notes',r.notes,
    'starts_at',r.starts_at,'duration_minutes',r.duration_minutes,'valid_until',r.valid_until,
    'state',r.state,'version',r.version,'completed_at',r.completed_at,
    'created_by_user_id',r.created_by_user_id,
    'participants',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'employee_id',p.employee_id,'name',p.employee_name,'attended',p.attended)
      ORDER BY p.employee_name,p.employee_id)
      FROM private_isg.pilot_training_participants p
      WHERE p.workspace_id=p_workspace AND p.company_id=p_company AND p.training_id=r.id),'[]'::jsonb))
  FROM private_isg.pilot_training_records r
  JOIN private_isg.pilot_training_sessions s
    ON s.workspace_id=r.workspace_id AND s.id=r.session_id
  WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.id=p_id
$$;

CREATE FUNCTION private_isg.workspace_training_read(p_workspace uuid,p_company uuid,p_id uuid,
  p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_domain_gate('training',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_limit NOT BETWEEN 1 AND 100 OR (p_id IS NOT NULL AND p_after IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_id IS NOT NULL THEN
    SELECT private_isg.workspace_training_row(p_workspace,p_company,p_id) INTO rows;
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'row',rows);
  END IF;
  WITH visible AS (
    SELECT r.id FROM private_isg.pilot_training_records r
    WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND (p_after IS NULL OR r.id<p_after)
    ORDER BY r.id DESC LIMIT p_limit+1
  ), page AS (SELECT id FROM visible ORDER BY id DESC LIMIT p_limit)
  SELECT coalesce(jsonb_agg(private_isg.workspace_training_row(p_workspace,p_company,id) ORDER BY id DESC),'[]'::jsonb),
    CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id LIMIT 1) END
    INTO rows,next_id FROM page;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_training_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); action text; target uuid; expected bigint;
  record private_isg.pilot_training_records; session private_isg.pilot_training_sessions;
  fingerprint bytea; replay jsonb; before_state jsonb; result jsonb; people jsonb; person jsonb;
  person_id uuid; person_name text; selected_ids uuid[]:='{}'; start_time timestamptz;
  until_date date; minutes integer; clean_title text; clean_trainer text; clean_location text; clean_notes text;
  clean_method text; workspace private_isg.workspaces;
BEGIN
  PERFORM private_isg.workspace_domain_gate('training',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
     OR octet_length(p_payload::text)>65536 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
       ('action','id','expected_version','title','trainer','method','starts_at','duration_minutes',
        'valid_until','location','notes','participants')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action'; target:=(p_payload->>'id')::uuid;
  expected:=coalesce((p_payload->>'expected_version')::bigint,0);
  IF action NOT IN ('save','complete','cancel') OR expected<0 OR
     ((target IS NULL)<>(action='save' AND expected=0)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'training.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  IF target IS NOT NULL THEN
    SELECT * INTO record FROM private_isg.pilot_training_records
      WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
    IF record.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF record.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF record.state<>'planned' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TRAINING_LOCKED'; END IF;
    SELECT * INTO STRICT session FROM private_isg.pilot_training_sessions
      WHERE workspace_id=p_workspace AND id=record.session_id FOR UPDATE;
    before_state:=private_isg.workspace_training_row(p_workspace,p_company,target);
  END IF;
  IF action='save' THEN
    clean_title:=private_isg.workspace_text(p_payload->>'title',200);
    clean_trainer:=private_isg.workspace_text(p_payload->>'trainer',200);
    clean_method:=coalesce(p_payload->>'method','face_to_face');
    start_time:=(p_payload->>'starts_at')::timestamptz;
    minutes:=(p_payload->>'duration_minutes')::integer;
    until_date:=(p_payload->>'valid_until')::date;
    clean_location:=normalize(btrim(coalesce(p_payload->>'location','')),NFC);
    clean_notes:=normalize(btrim(coalesce(p_payload->>'notes','')),NFC);
    people:=p_payload->'participants';
    IF clean_method NOT IN ('face_to_face','online','mixed') OR start_time IS NULL OR NOT isfinite(start_time)
      OR minutes NOT BETWEEN 1 AND 100000 OR octet_length(clean_location)>300 OR octet_length(clean_notes)>2000
      OR (until_date IS NOT NULL AND (NOT isfinite(until_date) OR until_date<(start_time AT TIME ZONE 'Europe/Istanbul')::date))
      OR jsonb_typeof(people) IS DISTINCT FROM 'array' OR jsonb_array_length(people)>500 THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO STRICT workspace FROM private_isg.workspaces WHERE id=p_workspace;
    IF target IS NULL THEN
      INSERT INTO private_isg.pilot_training_sessions(workspace_id,owner_id,title,trainer,method,held_on,
        location,notes,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,NULL,clean_title,clean_trainer,clean_method,(start_time AT TIME ZONE workspace.timezone)::date,
        clean_location,clean_notes,actor,actor) RETURNING * INTO session;
      INSERT INTO private_isg.pilot_training_records(workspace_id,company_id,owner_id,title,trainer,location,
        notes,starts_at,duration_minutes,valid_until,session_id,company_snapshot,created_by_user_id,updated_by_user_id)
      SELECT p_workspace,p_company,NULL,clean_title,clean_trainer,clean_location,clean_notes,start_time,minutes,
        until_date,session.id,jsonb_build_object('company_name',c.name,'hazard_class',c.hazard_class),actor,actor
      FROM private_isg.workspace_companies c WHERE c.workspace_id=p_workspace AND c.id=p_company
      RETURNING * INTO record;
      target:=record.id;
    ELSE
      INSERT INTO private_isg.pilot_training_session_revisions(workspace_id,session_id,version,snapshot)
        VALUES(p_workspace,session.id,session.version,before_state);
      UPDATE private_isg.pilot_training_sessions SET title=clean_title,trainer=clean_trainer,method=clean_method,
        held_on=(start_time AT TIME ZONE workspace.timezone)::date,location=clean_location,notes=clean_notes,
        version=version+1,updated_by_user_id=actor WHERE id=session.id RETURNING * INTO session;
      UPDATE private_isg.pilot_training_records SET title=clean_title,trainer=clean_trainer,
        location=clean_location,notes=clean_notes,starts_at=start_time,duration_minutes=minutes,
        valid_until=until_date,version=version+1,updated_at=clock_timestamp(),updated_by_user_id=actor
        WHERE id=record.id RETURNING * INTO record;
      DELETE FROM private_isg.pilot_training_participants
        WHERE workspace_id=p_workspace AND company_id=p_company AND training_id=target;
    END IF;
    FOR person IN SELECT value FROM jsonb_array_elements(people) LOOP
      IF jsonb_typeof(person)<>'object' OR jsonb_typeof(person->'attended') IS DISTINCT FROM 'boolean'
        OR EXISTS(SELECT 1 FROM jsonb_object_keys(person) k WHERE k NOT IN ('id','attended')) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      person_id:=(person->>'id')::uuid;
      IF person_id IS NULL OR person_id=ANY(selected_ids) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT full_name INTO person_name FROM private_isg.employees
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=person_id AND NOT is_archived FOR SHARE;
      IF person_name IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_UNAVAILABLE'; END IF;
      IF (person->>'attended')::boolean AND start_time>clock_timestamp() THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FUTURE_ATTENDANCE'; END IF;
      selected_ids:=array_append(selected_ids,person_id);
      INSERT INTO private_isg.pilot_training_participants(workspace_id,company_id,training_id,
        employee_id,employee_name,attended)
      VALUES(p_workspace,p_company,target,person_id,person_name,(person->>'attended')::boolean);
    END LOOP;
  ELSIF action='complete' THEN
    IF record.starts_at+make_interval(mins=>record.duration_minutes)>clock_timestamp() THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TRAINING_NOT_ENDED'; END IF;
    people:=p_payload->'participants';
    IF people IS NOT NULL THEN
      IF jsonb_typeof(people) IS DISTINCT FROM 'array' OR jsonb_array_length(people) NOT BETWEEN 1 AND 500 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      selected_ids:='{}';
      FOR person IN SELECT value FROM jsonb_array_elements(people) LOOP
        IF jsonb_typeof(person)<>'object' OR jsonb_typeof(person->'attended') IS DISTINCT FROM 'boolean'
          OR EXISTS(SELECT 1 FROM jsonb_object_keys(person) k WHERE k NOT IN ('id','attended')) THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
        person_id:=(person->>'id')::uuid;
        IF person_id IS NULL OR person_id=ANY(selected_ids) OR NOT EXISTS(
          SELECT 1 FROM private_isg.pilot_training_participants p WHERE p.workspace_id=p_workspace
            AND p.company_id=p_company AND p.training_id=target AND p.employee_id=person_id) THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_UNAVAILABLE'; END IF;
        selected_ids:=array_append(selected_ids,person_id);
        UPDATE private_isg.pilot_training_participants SET attended=(person->>'attended')::boolean
          WHERE workspace_id=p_workspace AND company_id=p_company AND training_id=target AND employee_id=person_id;
      END LOOP;
      IF (SELECT count(*) FROM private_isg.pilot_training_participants p WHERE p.workspace_id=p_workspace
        AND p.company_id=p_company AND p.training_id=target)<>coalesce(array_length(selected_ids,1),0) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_SET_MISMATCH'; END IF;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_participants
      WHERE workspace_id=p_workspace AND company_id=p_company AND training_id=target AND attended) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ATTENDANCE_REQUIRED'; END IF;
    INSERT INTO private_isg.pilot_training_session_revisions(workspace_id,session_id,version,snapshot)
      VALUES(p_workspace,session.id,session.version,before_state);
    UPDATE private_isg.pilot_training_sessions SET version=version+1,updated_by_user_id=actor
      WHERE id=session.id RETURNING * INTO session;
    UPDATE private_isg.pilot_training_records SET state='completed',completed_at=clock_timestamp(),
      version=version+1,updated_at=clock_timestamp(),updated_by_user_id=actor
      WHERE id=target RETURNING * INTO record;
  ELSE
    INSERT INTO private_isg.pilot_training_session_revisions(workspace_id,session_id,version,snapshot)
      VALUES(p_workspace,session.id,session.version,before_state);
    UPDATE private_isg.pilot_training_sessions SET deleted_at=clock_timestamp(),version=version+1,
      updated_by_user_id=actor WHERE id=session.id RETURNING * INTO session;
    UPDATE private_isg.pilot_training_records SET state='cancelled',version=version+1,
      updated_at=clock_timestamp(),updated_by_user_id=actor WHERE id=target RETURNING * INTO record;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'row',private_isg.workspace_training_row(p_workspace,p_company,target));
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'training.'||action,fingerprint,p_workspace,
    'training',target,record.version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_training_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('training',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'measured',true,'records',jsonb_build_object(
      'total',(SELECT count(*) FROM private_isg.pilot_training_records r
        WHERE r.workspace_id=p_workspace AND r.company_id=p_company),
      'planned',(SELECT count(*) FROM private_isg.pilot_training_records r
        WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.state='planned'),
      'completed',(SELECT count(*) FROM private_isg.pilot_training_records r
        WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.state='completed'),
      'cancelled',(SELECT count(*) FROM private_isg.pilot_training_records r
        WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.state='cancelled')),
    'completed_minutes',(SELECT coalesce(sum(r.duration_minutes),0) FROM private_isg.pilot_training_records r
      WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.state='completed'),
    'trained_people',(SELECT count(DISTINCT p.employee_id) FROM private_isg.pilot_training_participants p
      JOIN private_isg.pilot_training_records r ON r.workspace_id=p.workspace_id
        AND r.company_id=p.company_id AND r.id=p.training_id
      WHERE p.workspace_id=p_workspace AND p.company_id=p_company AND p.attended AND r.state='completed'),
    'person_minutes',(SELECT coalesce(sum(r.duration_minutes),0) FROM private_isg.pilot_training_participants p
      JOIN private_isg.pilot_training_records r ON r.workspace_id=p.workspace_id
        AND r.company_id=p.company_id AND r.id=p.training_id
      WHERE p.workspace_id=p_workspace AND p.company_id=p_company AND p.attended AND r.state='completed'),
    'people_without_completed_training',(SELECT count(*) FROM private_isg.employees e
      WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND NOT e.is_archived
        AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_participants px
          JOIN private_isg.pilot_training_records rx ON rx.workspace_id=px.workspace_id
            AND rx.company_id=px.company_id AND rx.id=px.training_id
          WHERE px.workspace_id=e.workspace_id AND px.company_id=e.company_id AND px.employee_id=e.id
            AND px.attended AND rx.state='completed'))) INTO result;
  RETURN result;
END $$;

CREATE FUNCTION public.isg_workspace_training_read_v1(p_workspace uuid,p_company uuid,p_id uuid DEFAULT NULL,
  p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_training_read(p_workspace,p_company,p_id,p_after,p_limit)
$$;
CREATE FUNCTION public.isg_workspace_training_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_training_mutate(p_mutation,p_workspace,p_company,p_payload)
$$;
CREATE FUNCTION public.isg_workspace_training_metrics_v1(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_training_metrics(p_workspace,p_company)
$$;

REVOKE ALL ON FUNCTION private_isg.workspace_training_session_invariant(),
  private_isg.workspace_training_record_invariant(),private_isg.workspace_training_participant_invariant(),
  private_isg.workspace_training_row(uuid,uuid,uuid),
  private_isg.workspace_training_read(uuid,uuid,uuid,uuid,integer),
  private_isg.workspace_training_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_training_metrics(uuid,uuid),
  public.isg_workspace_training_read_v1(uuid,uuid,uuid,uuid,integer),
  public.isg_workspace_training_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_training_metrics_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_training_read(uuid,uuid,uuid,uuid,integer),
  private_isg.workspace_training_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_training_metrics(uuid,uuid),
  public.isg_workspace_training_read_v1(uuid,uuid,uuid,uuid,integer),
  public.isg_workspace_training_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_training_metrics_v1(uuid,uuid)
  TO authenticated;
NOTIFY pgrst,'reload schema';
