-- P13 authenticated notebook API. Additive, Free, no company scope, rollout OFF.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE TABLE private_isg.note_mutation_receipts (
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  mutation_id uuid NOT NULL,
  request_hash bytea NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(owner_id,mutation_id)
);
ALTER TABLE private_isg.note_mutation_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.note_mutation_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.mutate_notebook(p_mutation uuid,p_note uuid,p_action text,p_expected bigint,
  p_title text,p_body text,p_conflict uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); entry private_isg.personal_notes;
  receipt private_isg.note_mutation_receipts; conflict private_isg.note_conflicts;
  fingerprint bytea; result jsonb; stamp timestamptz;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_mutation IS NULL OR p_note IS NULL OR p_action IS NULL OR p_action NOT IN ('sync','delete','resolve') OR
    p_expected IS NULL OR p_expected NOT BETWEEN 0 AND 9007199254740990 OR
    length(p_title)>200 OR length(p_body)>20000 OR
    (p_action IN ('sync','resolve') AND p_title IS NULL AND p_body IS NULL) OR
    (p_action='delete' AND (p_title IS NOT NULL OR p_body IS NOT NULL)) OR
    (p_action='resolve') IS DISTINCT FROM (p_conflict IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_note,p_action,p_expected,p_title,p_body,p_conflict)::text,'UTF8'));
  -- Receipt and note creation are both serialized, including the first insert.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text||p_mutation::text,7313));
  SELECT * INTO receipt FROM private_isg.note_mutation_receipts WHERE owner_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF receipt.request_hash<>fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN receipt.response||jsonb_build_object('replayed',true);
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_note::text,7314));
  SELECT * INTO entry FROM private_isg.personal_notes WHERE note_id=p_note FOR UPDATE;
  IF FOUND AND entry.owner_id<>actor THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  stamp:=clock_timestamp();
  IF p_action='sync' THEN
    result:=private_isg.sync_personal_note(actor,p_note,p_title,p_body,p_expected,stamp,stamp);
  ELSIF p_action='delete' THEN
    result:=private_isg.delete_personal_note(actor,p_note,p_expected,stamp);
    SELECT version INTO p_expected FROM private_isg.personal_notes WHERE note_id=p_note;
    result:=result||jsonb_build_object('version',p_expected,'state','deleted');
  ELSE
    IF entry.note_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF entry.tombstone THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='NOTE_TOMBSTONED'; END IF;
    IF entry.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    SELECT * INTO conflict FROM private_isg.note_conflicts WHERE conflict_id=p_conflict AND note_id=p_note FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF conflict.resolved_at IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CONFLICT_ALREADY_RESOLVED'; END IF;
    result:=private_isg.resolve_note_conflict(p_conflict,actor,p_title,p_body,stamp);
    -- Do not echo note text in write receipts/loggable mutation metadata.
    result:=jsonb_build_object('schema_version',1,'note_id',p_note,'version',result->'resolved_version','state','resolved','conflict_id',p_conflict);
  END IF;
  result:=result||jsonb_build_object('mutation_id',p_mutation,'replayed',false);
  INSERT INTO private_isg.note_mutation_receipts(owner_id,mutation_id,request_hash,response)
    VALUES(actor,p_mutation,fingerprint,result);
  RETURN result;
END $$;

CREATE FUNCTION private_isg.read_notebook(p_note uuid,p_after uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); rows jsonb; result jsonb; last_id uuid; more boolean;
BEGIN
  PERFORM private_isg.notes_gate(false);
  IF p_note IS NOT NULL THEN
    PERFORM 1 FROM private_isg.personal_notes WHERE note_id=p_note AND owner_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    SELECT jsonb_build_object('note_id',n.note_id,'title',n.title,'body',n.body,'version',n.version,
      'tombstone',n.tombstone,'updated_at',n.updated_at)
    INTO result FROM private_isg.personal_notes n WHERE n.note_id=p_note AND n.owner_id=actor;
    SELECT coalesce(jsonb_agg(c.value ORDER BY c.conflict_id),'[]'::jsonb) INTO rows FROM (
      SELECT c.conflict_id,jsonb_build_object(
        'conflict_id',c.conflict_id,'base_version',c.base_version,'server_version',c.server_version,
        'incoming_title',c.incoming_title,'incoming_body',c.incoming_body,'server_title',c.server_title,'server_body',c.server_body) value
      FROM private_isg.note_conflicts c WHERE c.note_id=p_note AND c.resolved_at IS NULL
        AND NOT (result->>'tombstone')::boolean AND (p_after IS NULL OR c.conflict_id>p_after)
      ORDER BY c.conflict_id LIMIT 21
    ) c;
    more:=jsonb_array_length(rows)>20;
    IF more THEN rows:=rows-20; last_id:=(rows->19->>'conflict_id')::uuid; END IF;
    RETURN jsonb_build_object('schema_version',1,'note',result||jsonb_build_object('conflicts',rows),
      'has_more_conflicts',more,'next_conflict_after',last_id);
  END IF;
  SELECT coalesce(jsonb_agg(x.value ORDER BY x.note_id),'[]'::jsonb) INTO rows FROM (
    SELECT n.note_id,jsonb_build_object('note_id',n.note_id,'title',n.title,'body',n.body,'version',n.version,
      'tombstone',n.tombstone,'updated_at',n.updated_at) value
    FROM private_isg.personal_notes n WHERE n.owner_id=actor AND (p_after IS NULL OR n.note_id>p_after)
    ORDER BY n.note_id LIMIT 21
  ) x;
  more:=jsonb_array_length(rows)>20;
  IF more THEN rows:=rows-20; last_id:=(rows->19->>'note_id')::uuid; END IF;
  -- This is bounded full-scan pagination, not an incremental change cursor.
  -- Repeat from NULL on the next sync; absence is never a deletion signal.
  RETURN jsonb_build_object('schema_version',1,'notes',rows,'next_after',last_id,'has_more',more,'scan_mode','full_scan_restart');
END $$;

CREATE FUNCTION public.isg_notebook_mutate_v1(p_mutation uuid,p_note uuid,p_action text,p_expected bigint,p_title text,p_body text,p_conflict uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.mutate_notebook(p_mutation,p_note,p_action,p_expected,p_title,p_body,p_conflict) $$;
CREATE FUNCTION public.isg_notebook_read_v1(p_note uuid,p_after uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.read_notebook(p_note,p_after) $$;
REVOKE ALL ON FUNCTION private_isg.mutate_notebook(uuid,uuid,text,bigint,text,text,uuid),private_isg.read_notebook(uuid,uuid),
  public.isg_notebook_mutate_v1(uuid,uuid,text,bigint,text,text,uuid),public.isg_notebook_read_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.mutate_notebook(uuid,uuid,text,bigint,text,text,uuid),private_isg.read_notebook(uuid,uuid),
  public.isg_notebook_mutate_v1(uuid,uuid,text,bigint,text,text,uuid),public.isg_notebook_read_v1(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
