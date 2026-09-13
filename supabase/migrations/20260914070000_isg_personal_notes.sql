-- P13/D13: the private notebook and its reminders. Owner scoped, Free, and
-- deliberately disconnected from every company domain: no company, workplace,
-- employee or entity column exists at any level, and no attachment endpoint.
-- Additive; rollout OFF; no client grant.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports','notifications','personal_notes'));
INSERT INTO private_isg.rollout(feature) VALUES('personal_notes');

CREATE TABLE private_isg.personal_notes (
  note_id uuid PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title text CHECK(title IS NULL OR length(title)<=200),
  body text CHECK(body IS NULL OR length(body)<=20000),
  version bigint NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 9007199254740991),
  tombstone boolean NOT NULL DEFAULT false,
  client_updated_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CHECK(tombstone=(deleted_at IS NOT NULL)),
  -- A tombstoned note keeps no text: the record exists only to stop a stale
  -- device from resurrecting it.
  CHECK(NOT tombstone OR (title IS NULL AND body IS NULL))
);
-- A version clash keeps both texts. Nothing is overwritten in silence.
CREATE TABLE private_isg.note_conflicts (
  conflict_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id uuid NOT NULL REFERENCES private_isg.personal_notes(note_id) ON DELETE CASCADE,
  base_version bigint NOT NULL, server_version bigint NOT NULL,
  incoming_title text, incoming_body text,
  server_title text, server_body text,
  resolved_version bigint, resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK((resolved_version IS NULL)=(resolved_at IS NULL))
);
CREATE TABLE private_isg.note_items (
  item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id uuid NOT NULL REFERENCES private_isg.personal_notes(note_id) ON DELETE CASCADE,
  position integer NOT NULL CHECK(position BETWEEN 1 AND 500),
  text text NOT NULL CHECK(btrim(text)<>'' AND length(text)<=1000),
  done boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(note_id,position)
);
CREATE TABLE private_isg.note_tags (
  tag_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  label text NOT NULL CHECK(btrim(label)<>'' AND length(label)<=60),
  label_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_id,label_key)
);
CREATE TABLE private_isg.note_tag_links (
  note_id uuid NOT NULL REFERENCES private_isg.personal_notes(note_id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES private_isg.note_tags(tag_id) ON DELETE CASCADE,
  PRIMARY KEY(note_id,tag_id)
);
CREATE TABLE private_isg.personal_reminders (
  reminder_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  note_id uuid REFERENCES private_isg.personal_notes(note_id) ON DELETE CASCADE,
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  recurrence text NOT NULL CHECK(recurrence IN ('once','daily','weekly','monthly')),
  local_time time NOT NULL, starts_on date NOT NULL CHECK(isfinite(starts_on)),
  timezone text NOT NULL,
  series_version bigint NOT NULL DEFAULT 1 CHECK(series_version>=1),
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','cancelled')),
  cancelled_reason text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK((state='cancelled')=(cancelled_reason IS NOT NULL))
);
-- An occurrence has its own identity. Snoozing or completing one never closes
-- the series.
CREATE TABLE private_isg.reminder_occurrences (
  occurrence_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reminder_id uuid NOT NULL REFERENCES private_isg.personal_reminders(reminder_id) ON DELETE CASCADE,
  occurrence_no integer NOT NULL CHECK(occurrence_no BETWEEN 1 AND 100000),
  series_version bigint NOT NULL,
  due_at timestamptz NOT NULL, local_due_at timestamp NOT NULL,
  state text NOT NULL DEFAULT 'scheduled' CHECK(state IN ('scheduled','snoozed','completed','cancelled','missed')),
  snoozed_until timestamptz, settled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(reminder_id,occurrence_no),
  CHECK((state='snoozed')=(snoozed_until IS NOT NULL)),
  CHECK((state IN ('completed','cancelled','missed'))=(settled_at IS NOT NULL))
);
-- Exactly one delivery owner per reminder: a named installation delivering
-- locally, or the server push path. Never both at once.
CREATE TABLE private_isg.device_delivery_claims (
  reminder_id uuid PRIMARY KEY REFERENCES private_isg.personal_reminders(reminder_id) ON DELETE CASCADE,
  installation_id uuid NOT NULL,
  strategy text NOT NULL CHECK(strategy IN ('local','server_push')),
  claimed_at timestamptz NOT NULL,
  previous_installation_id uuid,
  delivery_guarantee text NOT NULL DEFAULT 'at_most_once_per_installation'
    CHECK(delivery_guarantee='at_most_once_per_installation')
);
CREATE INDEX note_owner_idx ON private_isg.personal_notes(owner_id,tombstone,updated_at);
CREATE INDEX note_conflict_idx ON private_isg.note_conflicts(note_id,resolved_at);
CREATE INDEX note_item_idx ON private_isg.note_items(note_id);
CREATE INDEX note_tag_owner_idx ON private_isg.note_tags(owner_id);
CREATE INDEX note_tag_link_idx ON private_isg.note_tag_links(tag_id);
CREATE INDEX reminder_owner_idx ON private_isg.personal_reminders(owner_id,state);
CREATE INDEX reminder_note_idx ON private_isg.personal_reminders(note_id);
CREATE INDEX occurrence_due_idx ON private_isg.reminder_occurrences(state,due_at);
ALTER TABLE private_isg.personal_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.note_conflicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.note_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.note_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.note_tag_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.personal_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.reminder_occurrences ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.device_delivery_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.notes_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='personal_notes' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- The notebook is Free and owner scoped: no plan check and no company scope.
CREATE FUNCTION private_isg.sync_personal_note(p_owner uuid,p_note uuid,p_title text,p_body text,
  p_expected_version bigint,p_client_updated_at timestamptz,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.personal_notes; conflict uuid; next_version bigint;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_owner IS NULL OR p_note IS NULL OR p_expected_version IS NULL OR p_expected_version<0 OR
     p_client_updated_at IS NULL OR p_now IS NULL OR
     (p_title IS NULL AND p_body IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.personal_notes WHERE note_id=p_note FOR UPDATE;
  IF NOT FOUND THEN
    IF p_expected_version<>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    INSERT INTO private_isg.personal_notes(note_id,owner_id,title,body,version,client_updated_at,created_at,updated_at)
      VALUES(p_note,p_owner,p_title,p_body,1,p_client_updated_at,p_now,p_now);
    RETURN jsonb_build_object('schema_version',1,'note_id',p_note,'version',1,'state','created');
  END IF;
  IF entry.owner_id<>p_owner THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- A tombstone wins over a stale device: the note is not resurrected.
  IF entry.tombstone THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='NOTE_TOMBSTONED'; END IF;
  IF entry.version=p_expected_version AND entry.title IS NOT DISTINCT FROM p_title AND
     entry.body IS NOT DISTINCT FROM p_body THEN
    RETURN jsonb_build_object('schema_version',1,'note_id',p_note,'version',entry.version,'state','unchanged'); END IF;
  IF entry.version<>p_expected_version THEN
    -- Both texts are kept. Last writer never silently wins.
    INSERT INTO private_isg.note_conflicts(note_id,base_version,server_version,incoming_title,incoming_body,
        server_title,server_body,created_at)
      VALUES(p_note,p_expected_version,entry.version,p_title,p_body,entry.title,entry.body,p_now)
      RETURNING conflict_id INTO conflict;
    RETURN jsonb_build_object('schema_version',1,'note_id',p_note,'state','conflict','conflict_id',conflict,
      'server_version',entry.version,'both_texts_preserved',true);
  END IF;
  next_version:=entry.version+1;
  UPDATE private_isg.personal_notes SET title=p_title,body=p_body,version=next_version,
    client_updated_at=p_client_updated_at,updated_at=p_now WHERE note_id=p_note;
  RETURN jsonb_build_object('schema_version',1,'note_id',p_note,'version',next_version,'state','updated');
END $$;
CREATE FUNCTION private_isg.resolve_note_conflict(p_conflict uuid,p_owner uuid,p_title text,p_body text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.note_conflicts; note private_isg.personal_notes; next_version bigint;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_conflict IS NULL OR p_owner IS NULL OR p_now IS NULL OR (p_title IS NULL AND p_body IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.note_conflicts WHERE conflict_id=p_conflict FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO note FROM private_isg.personal_notes WHERE note_id=entry.note_id FOR UPDATE;
  IF note.owner_id<>p_owner THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.resolved_at IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'conflict_id',p_conflict,'resolved_version',entry.resolved_version,'replayed',true); END IF;
  next_version:=note.version+1;
  UPDATE private_isg.personal_notes SET title=p_title,body=p_body,version=next_version,updated_at=p_now
    WHERE note_id=note.note_id;
  UPDATE private_isg.note_conflicts SET resolved_version=next_version,resolved_at=p_now WHERE conflict_id=p_conflict;
  RETURN jsonb_build_object('schema_version',1,'conflict_id',p_conflict,'resolved_version',next_version,
    'kept_incoming',entry.incoming_body,'kept_server',entry.server_body,'replayed',false);
END $$;
-- Deleting a note cancels its future reminders. Completed history is kept.
CREATE FUNCTION private_isg.delete_personal_note(p_owner uuid,p_note uuid,p_expected_version bigint,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.personal_notes; cancelled integer:=0; kept integer:=0;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_owner IS NULL OR p_note IS NULL OR p_expected_version IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.personal_notes WHERE note_id=p_note FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.owner_id<>p_owner THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.tombstone THEN
    RETURN jsonb_build_object('schema_version',1,'note_id',p_note,'tombstone',true,'replayed',true); END IF;
  IF entry.version<>p_expected_version THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  WITH stopped AS (
    UPDATE private_isg.reminder_occurrences o SET state='cancelled',settled_at=p_now,snoozed_until=NULL
      FROM private_isg.personal_reminders r
      WHERE r.reminder_id=o.reminder_id AND r.note_id=p_note AND o.state IN ('scheduled','snoozed')
      RETURNING o.occurrence_id)
  SELECT count(*) INTO cancelled FROM stopped;
  SELECT count(*) INTO kept FROM private_isg.reminder_occurrences o JOIN private_isg.personal_reminders r
    USING(reminder_id) WHERE r.note_id=p_note AND o.state='completed';
  UPDATE private_isg.personal_reminders SET state='cancelled',cancelled_reason='NOTE_DELETED',updated_at=p_now
    WHERE note_id=p_note AND state='active';
  UPDATE private_isg.personal_notes SET tombstone=true,title=NULL,body=NULL,version=version+1,
    deleted_at=p_now,updated_at=p_now WHERE note_id=p_note;
  RETURN jsonb_build_object('schema_version',1,'note_id',p_note,'tombstone',true,
    'cancelled_future_occurrences',cancelled,'kept_completed_occurrences',kept,'replayed',false);
END $$;
CREATE FUNCTION private_isg.create_personal_reminder(p_owner uuid,p_note uuid,p_title text,p_recurrence text,
  p_local_time time,p_starts_on date,p_timezone text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE reminder uuid; note private_isg.personal_notes;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_owner IS NULL OR p_title IS NULL OR p_recurrence IS NULL OR p_local_time IS NULL OR p_starts_on IS NULL OR
     NOT isfinite(p_starts_on) OR p_timezone IS NULL OR p_now IS NULL OR
     p_recurrence NOT IN ('once','daily','weekly','monthly') OR
     NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_timezone) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_note IS NOT NULL THEN
    SELECT * INTO note FROM private_isg.personal_notes WHERE note_id=p_note FOR SHARE;
    IF NOT FOUND OR note.owner_id<>p_owner OR note.tombstone THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  INSERT INTO private_isg.personal_reminders(owner_id,note_id,title,recurrence,local_time,starts_on,timezone,created_at,updated_at)
    VALUES(p_owner,p_note,private_isg.text_value(p_title,200),p_recurrence,p_local_time,p_starts_on,p_timezone,p_now,p_now)
    RETURNING reminder_id INTO reminder;
  RETURN jsonb_build_object('schema_version',1,'reminder_id',reminder,'series_version',1,'state','active');
END $$;
-- Occurrences keep the same wall clock time in the reminder's own zone, so a
-- daylight saving change moves the UTC instant, not the local time.
CREATE FUNCTION private_isg.project_reminder_occurrences(p_reminder uuid,p_count integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.personal_reminders; step interval; slot integer; local_stamp timestamp;
  existing integer; created integer:=0; first_local timestamp; last_local timestamp;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_reminder IS NULL OR p_count IS NULL OR p_count NOT BETWEEN 1 AND 100 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.personal_reminders WHERE reminder_id=p_reminder FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SERIES_CANCELLED'; END IF;
  step:=CASE entry.recurrence WHEN 'daily' THEN interval '1 day' WHEN 'weekly' THEN interval '7 days'
    WHEN 'monthly' THEN interval '1 month' ELSE interval '0' END;
  SELECT count(*) INTO existing FROM private_isg.reminder_occurrences
    WHERE reminder_id=p_reminder AND series_version=entry.series_version;
  FOR slot IN 1..p_count LOOP
    EXIT WHEN entry.recurrence='once' AND existing+slot>1;
    local_stamp:=(entry.starts_on+entry.local_time)+step*(existing+slot-1);
    IF first_local IS NULL THEN first_local:=local_stamp; END IF;
    last_local:=local_stamp;
    INSERT INTO private_isg.reminder_occurrences(reminder_id,occurrence_no,series_version,due_at,local_due_at,created_at)
      VALUES(p_reminder,existing+slot,entry.series_version,local_stamp AT TIME ZONE entry.timezone,local_stamp,p_now)
    ON CONFLICT(reminder_id,occurrence_no) DO NOTHING;
    created:=created+1;
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'reminder_id',p_reminder,'series_version',entry.series_version,
    'created',created,'first_local',first_local,'last_local',last_local,'timezone',entry.timezone);
END $$;
-- One occurrence settles on its own. The series keeps running.
CREATE FUNCTION private_isg.settle_reminder_occurrence(p_occurrence uuid,p_action text,p_until timestamptz,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.reminder_occurrences; series private_isg.personal_reminders; remaining integer;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_occurrence IS NULL OR p_action IS NULL OR p_now IS NULL OR
     p_action NOT IN ('snooze','complete','cancel','miss') OR (p_action='snooze')<>(p_until IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.reminder_occurrences WHERE occurrence_id=p_occurrence FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state IN ('completed','cancelled') THEN
    RETURN jsonb_build_object('schema_version',1,'occurrence_id',p_occurrence,'state',entry.state,'replayed',true); END IF;
  IF p_action='snooze' AND p_until<=entry.due_at THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.reminder_occurrences SET
    state=CASE p_action WHEN 'snooze' THEN 'snoozed' WHEN 'complete' THEN 'completed'
      WHEN 'cancel' THEN 'cancelled' ELSE 'missed' END,
    snoozed_until=CASE WHEN p_action='snooze' THEN p_until ELSE NULL END,
    settled_at=CASE WHEN p_action='snooze' THEN NULL ELSE p_now END
    WHERE occurrence_id=p_occurrence;
  SELECT * INTO series FROM private_isg.personal_reminders WHERE reminder_id=entry.reminder_id FOR SHARE;
  SELECT count(*) INTO remaining FROM private_isg.reminder_occurrences
    WHERE reminder_id=entry.reminder_id AND state IN ('scheduled','snoozed');
  RETURN jsonb_build_object('schema_version',1,'occurrence_id',p_occurrence,'occurrence_no',entry.occurrence_no,
    'state',CASE p_action WHEN 'snooze' THEN 'snoozed' WHEN 'complete' THEN 'completed'
      WHEN 'cancel' THEN 'cancelled' ELSE 'missed' END,
    'series_state',series.state,'remaining_open_occurrences',remaining,'series_closed',false);
END $$;
CREATE FUNCTION private_isg.cancel_reminder_series(p_reminder uuid,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.personal_reminders; cancelled integer:=0; completed integer;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_reminder IS NULL OR p_now IS NULL OR p_reason IS NULL OR p_reason !~ '^[A-Z][A-Z0-9_]{2,49}$' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.personal_reminders WHERE reminder_id=p_reminder FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='cancelled' THEN
    RETURN jsonb_build_object('schema_version',1,'reminder_id',p_reminder,'state','cancelled','replayed',true); END IF;
  WITH stopped AS (
    UPDATE private_isg.reminder_occurrences SET state='cancelled',settled_at=p_now,snoozed_until=NULL
      WHERE reminder_id=p_reminder AND state IN ('scheduled','snoozed') RETURNING occurrence_id)
  SELECT count(*) INTO cancelled FROM stopped;
  SELECT count(*) INTO completed FROM private_isg.reminder_occurrences
    WHERE reminder_id=p_reminder AND state='completed';
  UPDATE private_isg.personal_reminders SET state='cancelled',cancelled_reason=p_reason,updated_at=p_now
    WHERE reminder_id=p_reminder;
  RETURN jsonb_build_object('schema_version',1,'reminder_id',p_reminder,'state','cancelled',
    'cancelled_future',cancelled,'kept_completed',completed);
END $$;
-- Exactly one delivery owner. Claiming from another installation replaces the
-- previous one; two installations never hold the same reminder.
CREATE FUNCTION private_isg.claim_reminder_delivery(p_reminder uuid,p_installation uuid,p_strategy text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prior private_isg.device_delivery_claims;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_reminder IS NULL OR p_installation IS NULL OR p_strategy IS NULL OR p_now IS NULL OR
     p_strategy NOT IN ('local','server_push') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.personal_reminders WHERE reminder_id=p_reminder FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO prior FROM private_isg.device_delivery_claims WHERE reminder_id=p_reminder FOR UPDATE;
  IF FOUND AND prior.installation_id=p_installation AND prior.strategy=p_strategy THEN
    RETURN jsonb_build_object('schema_version',1,'reminder_id',p_reminder,'installation_id',p_installation,
      'strategy',p_strategy,'replayed',true); END IF;
  INSERT INTO private_isg.device_delivery_claims(reminder_id,installation_id,strategy,claimed_at,previous_installation_id)
    VALUES(p_reminder,p_installation,p_strategy,p_now,prior.installation_id)
  ON CONFLICT(reminder_id) DO UPDATE SET installation_id=excluded.installation_id,strategy=excluded.strategy,
    claimed_at=excluded.claimed_at,previous_installation_id=excluded.previous_installation_id;
  RETURN jsonb_build_object('schema_version',1,'reminder_id',p_reminder,'installation_id',p_installation,
    'strategy',p_strategy,'previous_installation_id',prior.installation_id,
    'delivery_guarantee','at_most_once_per_installation','exactly_once_promised',false,'replayed',false);
END $$;
REVOKE ALL ON FUNCTION private_isg.notes_gate(boolean),
  private_isg.sync_personal_note(uuid,uuid,text,text,bigint,timestamptz,timestamptz),
  private_isg.resolve_note_conflict(uuid,uuid,text,text,timestamptz),
  private_isg.delete_personal_note(uuid,uuid,bigint,timestamptz),
  private_isg.create_personal_reminder(uuid,uuid,text,text,time,date,text,timestamptz),
  private_isg.project_reminder_occurrences(uuid,integer,timestamptz),
  private_isg.settle_reminder_occurrence(uuid,text,timestamptz,timestamptz),
  private_isg.cancel_reminder_series(uuid,text,timestamptz),
  private_isg.claim_reminder_delivery(uuid,uuid,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
