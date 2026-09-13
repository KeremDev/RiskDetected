-- CLI-generated timestamp precedes the existing future-dated notebook migrations.
-- PL/pgSQL RECORDs deliberately defer table binding until invocation; no calls or
-- table changes occur here. Deploy the complete migration set before enabling notes.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE FUNCTION private_isg.organize_notebook(p_mutation uuid,p_note uuid,p_expected bigint,p_items jsonb,p_tags jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); entry record; receipt record; item jsonb; tag_label text;
  fingerprint bytea; result jsonb; stamp timestamptz:=clock_timestamp(); tag uuid;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_mutation IS NULL OR p_note IS NULL OR p_expected IS NULL OR p_expected NOT BETWEEN 1 AND 9007199254740990
    OR p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR p_tags IS NULL OR jsonb_typeof(p_tags)<>'array'
    OR octet_length(p_items::text)>1000000 OR octet_length(p_tags::text)>10000 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF jsonb_array_length(p_items)>500 OR jsonb_array_length(p_tags)>30 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF jsonb_typeof(item)<>'object' OR item - ARRAY['item_id','text','done'] <> '{}'::jsonb
      OR jsonb_typeof(item->'item_id') IS DISTINCT FROM 'string' OR (item->>'item_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR jsonb_typeof(item->'text') IS DISTINCT FROM 'string' OR length(btrim(item->>'text'))=0 OR length(item->>'text')>1000
      OR jsonb_typeof(item->'done') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  END LOOP;
  IF (SELECT count(DISTINCT (value->>'item_id')::uuid) FROM jsonb_array_elements(p_items))<>jsonb_array_length(p_items) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_tags) LOOP
    IF jsonb_typeof(item)<>'string' OR length(btrim(item#>>'{}'))=0 OR length(item#>>'{}')>60 THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  END LOOP;
  IF (SELECT count(DISTINCT lower(btrim(value#>>'{}'))) FROM jsonb_array_elements(p_tags))<>jsonb_array_length(p_tags) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array('organize_v1',p_note,p_expected,p_items,p_tags)::text,'UTF8'));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text||p_mutation::text,7313));
  SELECT * INTO receipt FROM private_isg.note_mutation_receipts WHERE owner_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF receipt.request_hash<>fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN receipt.response||jsonb_build_object('replayed',true);
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_note::text,7314));
  SELECT * INTO entry FROM private_isg.personal_notes WHERE note_id=p_note FOR UPDATE;
  IF NOT FOUND OR entry.owner_id<>actor THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.tombstone THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='NOTE_TOMBSTONED'; END IF;
  IF entry.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  IF EXISTS(SELECT 1 FROM private_isg.note_items i JOIN jsonb_array_elements(p_items) j ON i.item_id=(j.value->>'item_id')::uuid WHERE i.note_id<>p_note) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  DELETE FROM private_isg.note_items WHERE note_id=p_note;
  INSERT INTO private_isg.note_items(item_id,note_id,position,text,done,updated_at)
    SELECT (value->>'item_id')::uuid,p_note,ordinality::integer,value->>'text',(value->>'done')::boolean,stamp
    FROM jsonb_array_elements(p_items) WITH ORDINALITY;
  DELETE FROM private_isg.note_tag_links WHERE note_id=p_note;
  -- Deterministic lock order across notes avoids tag-upsert deadlocks.
  FOR tag_label IN SELECT btrim(value#>>'{}') FROM jsonb_array_elements(p_tags) ORDER BY lower(btrim(value#>>'{}')) LOOP
    INSERT INTO private_isg.note_tags(owner_id,label,label_key) VALUES(actor,tag_label,lower(tag_label)) ON CONFLICT(owner_id,label_key) DO NOTHING;
    SELECT tag_id INTO tag FROM private_isg.note_tags WHERE owner_id=actor AND label_key=lower(tag_label);
    INSERT INTO private_isg.note_tag_links(note_id,tag_id) VALUES(p_note,tag);
  END LOOP;
  UPDATE private_isg.personal_notes SET version=version+1,updated_at=stamp WHERE note_id=p_note;
  result:=jsonb_build_object('schema_version',1,'mutation_id',p_mutation,'note_id',p_note,'state','organized','version',p_expected+1,
    'item_count',jsonb_array_length(p_items),'tag_count',jsonb_array_length(p_tags),'replayed',false);
  INSERT INTO private_isg.note_mutation_receipts(owner_id,mutation_id,request_hash,response) VALUES(actor,p_mutation,fingerprint,result);
  RETURN result;
END $$;

CREATE FUNCTION private_isg.read_notebook_organization(p_note uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); entry record; items jsonb:='[]'; tags jsonb:='[]';
BEGIN
  PERFORM private_isg.notes_gate(false);
  SELECT * INTO entry FROM private_isg.personal_notes WHERE note_id=p_note AND owner_id=actor FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF NOT entry.tombstone THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('item_id',item_id,'text',text,'done',done) ORDER BY position),'[]') INTO items FROM private_isg.note_items WHERE note_id=p_note;
    SELECT coalesce(jsonb_agg(t.label ORDER BY t.label_key),'[]') INTO tags FROM private_isg.note_tags t
      JOIN private_isg.note_tag_links l USING(tag_id) WHERE l.note_id=p_note AND t.owner_id=actor;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'note_id',p_note,'version',entry.version,'tombstone',entry.tombstone,'items',items,'tags',tags);
END $$;
CREATE FUNCTION public.isg_notebook_organize_v1(p_mutation uuid,p_note uuid,p_expected bigint,p_items jsonb,p_tags jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.organize_notebook(p_mutation,p_note,p_expected,p_items,p_tags) $$;
CREATE FUNCTION public.isg_notebook_organization_v1(p_note uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.read_notebook_organization(p_note) $$;
REVOKE ALL ON FUNCTION private_isg.organize_notebook(uuid,uuid,bigint,jsonb,jsonb),private_isg.read_notebook_organization(uuid),
  public.isg_notebook_organize_v1(uuid,uuid,bigint,jsonb,jsonb),public.isg_notebook_organization_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.organize_notebook(uuid,uuid,bigint,jsonb,jsonb),private_isg.read_notebook_organization(uuid),
  public.isg_notebook_organize_v1(uuid,uuid,bigint,jsonb,jsonb),public.isg_notebook_organization_v1(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
