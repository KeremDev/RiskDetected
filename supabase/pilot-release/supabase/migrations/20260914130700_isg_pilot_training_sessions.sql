-- Completed, owner-attested sessions; no automatic legal qualification.
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='30s';
CREATE TABLE private_isg.pilot_training_catalog (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
 code text NOT NULL, title text NOT NULL CHECK(length(btrim(title)) BETWEEN 1 AND 200),
 rules jsonb NOT NULL, source_url text, content_approved boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX pilot_training_catalog_builtin ON private_isg.pilot_training_catalog(code) WHERE owner_id IS NULL;
CREATE INDEX pilot_training_catalog_owner ON private_isg.pilot_training_catalog(owner_id);
INSERT INTO private_isg.pilot_training_catalog(code,title,rules,source_url) VALUES
 ('basic','Temel İSG Eğitimi','{"low":{"minutes":480,"months":36},"medium":{"minutes":720,"months":24},"high":{"minutes":960,"months":12}}','https://www.csgb.gov.tr/tr/sikca-sorulan-sorular/is-sagligi-ve-guvenligi-genel-mudurlugu/'),
 ('renewal','Yenileme Eğitimi (Temel Eğitimin Tekrarı)','{"low":{"minutes":480,"months":36},"medium":{"minutes":480,"months":24},"high":{"minutes":480,"months":12}}','https://guvenliinsaat.csgb.gov.tr/haberler/yuksekte-calismaya-yonelik-temel-egitime-dair-bilinmesi-gerekenler/'),
 ('onboarding','İşe Başlama Eğitimi','{"low":{"minutes":120,"months":0},"medium":{"minutes":120,"months":0},"high":{"minutes":120,"months":0}}','https://www.csgb.gov.tr/tr/sikca-sorulan-sorular/is-sagligi-ve-guvenligi-genel-mudurlugu/');
CREATE TABLE private_isg.pilot_training_sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 catalog_id uuid REFERENCES private_isg.pilot_training_catalog(id), catalog_snapshot jsonb,
 title text NOT NULL, trainer text NOT NULL, method text NOT NULL DEFAULT 'face_to_face' CHECK(method IN ('face_to_face','online','mixed')),
 held_on date NOT NULL, location text NOT NULL DEFAULT '', notes text NOT NULL DEFAULT '',
 version bigint NOT NULL DEFAULT 1, deleted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX pilot_training_sessions_owner ON private_isg.pilot_training_sessions(owner_id,id);
CREATE INDEX pilot_training_sessions_catalog ON private_isg.pilot_training_sessions(catalog_id);
ALTER TABLE private_isg.pilot_training_records ADD COLUMN session_id uuid REFERENCES private_isg.pilot_training_sessions(id);
ALTER TABLE private_isg.pilot_training_records ADD COLUMN company_snapshot jsonb;
UPDATE private_isg.pilot_training_records r SET company_snapshot=jsonb_build_object('company_name',c.name,'hazard_class',c.hazard_class) FROM public.companies c WHERE c.id=r.company_id;
CREATE UNIQUE INDEX pilot_training_record_session_company ON private_isg.pilot_training_records(session_id,company_id);
-- Preserve old states, dates and attendance. Do not auto-complete old plans.
INSERT INTO private_isg.pilot_training_sessions(id,owner_id,title,trainer,held_on,location,notes)
 SELECT id,owner_id,title,trainer,(starts_at AT TIME ZONE 'Europe/Istanbul')::date,location,notes FROM private_isg.pilot_training_records;
UPDATE private_isg.pilot_training_records SET session_id=id;
CREATE TABLE private_isg.pilot_training_session_revisions (
 session_id uuid NOT NULL REFERENCES private_isg.pilot_training_sessions(id) ON DELETE CASCADE, version bigint NOT NULL,
 snapshot jsonb NOT NULL, changed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(session_id,version)
);
CREATE TABLE private_isg.pilot_training_session_receipts (
 owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, mutation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(owner_id,mutation_id)
);
ALTER TABLE private_isg.pilot_training_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.pilot_training_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.pilot_training_session_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.pilot_training_session_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.pilot_training_catalog,private_isg.pilot_training_sessions,
 private_isg.pilot_training_session_revisions,private_isg.pilot_training_session_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.pilot_training_session_row(p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT to_jsonb(s)||jsonb_build_object('companies',coalesce((SELECT jsonb_agg(
  private_isg.pilot_training_row(r.company_id,r.id)||coalesce(r.company_snapshot,jsonb_build_object('company_name',c.name,'hazard_class',c.hazard_class))
  ORDER BY r.company_id) FROM private_isg.pilot_training_records r JOIN public.companies c ON c.id=r.company_id
  WHERE r.session_id=s.id),'[]'::jsonb)) FROM private_isg.pilot_training_sessions s WHERE s.id=p_id
$$;

CREATE FUNCTION private_isg.pilot_training_sessions_read(p_company uuid,p_after uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); rows jsonb; next_id uuid; company uuid; writable uuid[]:='{}';
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_company IS NOT NULL THEN PERFORM private_isg.require_company(p_company,false); END IF;
 FOR company IN SELECT c.id FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id) ORDER BY c.id LOOP
  BEGIN
   PERFORM private_isg.require_company(company,true); writable:=array_append(writable,company);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
   IF SQLERRM NOT IN ('FEATURE_UNAVAILABLE','PAID_PLAN_REQUIRED','ACCESS_DENIED') THEN RAISE; END IF;
  END;
 END LOOP;
 SELECT coalesce(jsonb_agg(private_isg.pilot_training_session_row(q.id) ORDER BY q.id DESC),'[]') INTO rows FROM (
  SELECT s.id FROM private_isg.pilot_training_sessions s WHERE s.owner_id=actor AND s.deleted_at IS NULL
   AND (p_after IS NULL OR s.id<p_after)
   AND EXISTS(SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id=s.id AND (p_company IS NULL OR r.company_id=p_company))
   AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id=s.id AND NOT private_isg.p05_pilot_can_read(actor,r.company_id))
   ORDER BY s.id DESC LIMIT 30) q;
 IF jsonb_array_length(rows)=30 THEN next_id:=(rows->29->>'id')::uuid; END IF;
 RETURN jsonb_build_object('schema_version',2,'owner_id',actor,'rows',rows,'next_id',next_id,'writable_companies',writable,'catalog',
  (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.created_at,c.title),'[]') FROM private_isg.pilot_training_catalog c WHERE c.owner_id IS NULL OR c.owner_id=actor));
END $$;

CREATE FUNCTION private_isg.pilot_training_sessions_save(p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); sid uuid; old private_isg.pilot_training_sessions;
 cat private_isg.pilot_training_catalog; prior private_isg.pilot_training_session_receipts;
 action text; fingerprint bytea; result jsonb; before_row jsonb; company uuid; person uuid; record_id uuid; nm text; hazard text;
 companies uuid[]; ids uuid[]; entry jsonb; rule jsonb; minutes integer; months integer; held date; validity date;
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,true) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>131072
  THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 action:=p_payload->>'action'; sid:=(p_payload->>'id')::uuid;
 IF action IS NULL OR action NOT IN ('save','delete','catalog') THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':training-v2',0));
 IF action='catalog' THEN
  company:=(p_payload->>'company_id')::uuid; PERFORM private_isg.require_company(company,true);
 ELSE
  IF sid IS NOT NULL THEN
   SELECT * INTO old FROM private_isg.pilot_training_sessions WHERE id=sid AND owner_id=actor FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  END IF;
  IF action='save' AND (jsonb_typeof(p_payload->'companies') IS DISTINCT FROM 'array'
    OR jsonb_array_length(p_payload->'companies') NOT BETWEEN 1 AND 30) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  SELECT array_agg(DISTINCT x ORDER BY x) INTO companies FROM (
   SELECT r.company_id x FROM private_isg.pilot_training_records r WHERE r.session_id=sid
   UNION SELECT (v->>'id')::uuid FROM jsonb_array_elements(coalesce(p_payload->'companies','[]')) v) a;
  IF companies IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  FOREACH company IN ARRAY companies LOOP PERFORM private_isg.require_company(company,true); END LOOP;
 END IF;
 fingerprint:=sha256(convert_to(p_payload::text,'UTF8'));
 SELECT * INTO prior FROM private_isg.pilot_training_session_receipts WHERE owner_id=actor AND mutation_id=p_mutation;
 IF FOUND THEN
  IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  RETURN prior.response;
 END IF;
 IF action='catalog' THEN
  minutes:=(p_payload->>'minutes')::integer; months:=(p_payload->>'months')::integer;
  IF minutes IS NULL OR minutes NOT BETWEEN 1 AND 1440 OR months IS NULL OR months NOT BETWEEN 0 AND 120
   OR length(btrim(coalesce(p_payload->>'title',''))) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  rule:=jsonb_build_object('minutes',minutes,'months',months);
  INSERT INTO private_isg.pilot_training_catalog(owner_id,code,title,rules) VALUES(actor,'custom',btrim(p_payload->>'title'),
   jsonb_build_object('low',rule,'medium',rule,'high',rule)) RETURNING * INTO cat;
  result:=jsonb_build_object('schema_version',2,'owner_id',actor,'mutation_id',p_mutation,'catalog',to_jsonb(cat));
 ELSE
  IF sid IS NOT NULL AND (old.version IS DISTINCT FROM (p_payload->>'expected_version')::bigint OR old.deleted_at IS NOT NULL) THEN RAISE EXCEPTION 'VERSION_CONFLICT'; END IF;
  IF sid IS NULL AND action='delete' THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF sid IS NOT NULL THEN
   before_row:=private_isg.pilot_training_session_row(sid);
   INSERT INTO private_isg.pilot_training_session_revisions VALUES(sid,old.version,before_row,now());
  END IF;
  IF action='delete' THEN
   UPDATE private_isg.pilot_training_sessions SET deleted_at=now(),version=version+1 WHERE id=sid;
   UPDATE private_isg.pilot_training_records SET state='cancelled',version=version+1 WHERE session_id=sid;
  ELSE
   SELECT * INTO cat FROM private_isg.pilot_training_catalog WHERE id=(p_payload->>'catalog_id')::uuid AND (owner_id IS NULL OR owner_id=actor);
   IF NOT FOUND THEN RAISE EXCEPTION 'CATALOG_REQUIRED'; END IF;
   held:=(p_payload->>'held_on')::date;
   IF cat.code<>'custom' AND held<'2026-04-02'::date THEN RAISE EXCEPTION 'RULE_DATE_UNSUPPORTED'; END IF;
   IF held IS NULL OR NOT isfinite(held) OR held>(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date
    OR length(btrim(coalesce(p_payload->>'trainer',''))) NOT BETWEEN 1 AND 200
    OR length(coalesce(p_payload->>'location',''))>300 OR length(coalesce(p_payload->>'notes',''))>2000
    OR p_payload->>'method' IS NULL OR p_payload->>'method' NOT IN ('face_to_face','online','mixed')
    OR p_payload->>'confirmed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
   IF cat.code='onboarding' AND p_payload->>'method'<>'face_to_face' THEN RAISE EXCEPTION 'FACE_TO_FACE_REQUIRED'; END IF;
   IF sid IS NULL THEN
    INSERT INTO private_isg.pilot_training_sessions(owner_id,title,trainer,held_on) VALUES(actor,cat.title,btrim(p_payload->>'trainer'),held) RETURNING id INTO sid;
   ELSE
    UPDATE private_isg.pilot_training_sessions SET version=version+1 WHERE id=sid;
   END IF;
   UPDATE private_isg.pilot_training_sessions SET catalog_id=cat.id,catalog_snapshot=to_jsonb(cat),title=cat.title,
    trainer=btrim(p_payload->>'trainer'),held_on=held,method=p_payload->>'method',location=coalesce(p_payload->>'location',''),notes=coalesce(p_payload->>'notes','') WHERE id=sid;
   -- Rebuild per-company projections atomically; previous snapshots stay in revisions.
   DELETE FROM private_isg.pilot_training_records WHERE session_id=sid;
   companies:='{}';
   FOR entry IN SELECT value FROM jsonb_array_elements(p_payload->'companies') LOOP
    company:=(entry->>'id')::uuid;
    IF company IS NULL OR company=ANY(companies) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
    companies:=array_append(companies,company);
    SELECT hazard_class INTO hazard FROM public.companies WHERE id=company AND user_id=actor;
    rule:=cat.rules->hazard; minutes:=(rule->>'minutes')::integer; months:=(rule->>'months')::integer;
    IF minutes IS NULL THEN RAISE EXCEPTION 'HAZARD_REQUIRED'; END IF;
    IF cat.code IN ('basic','renewal') AND hazard<>'low' AND p_payload->>'method'='online' THEN RAISE EXCEPTION 'WORKPLACE_FACE_TO_FACE_REQUIRED'; END IF;
    validity:=CASE WHEN months=0 THEN NULL ELSE (held+make_interval(months=>months))::date END;
    INSERT INTO private_isg.pilot_training_records(company_id,owner_id,title,trainer,starts_at,duration_minutes,valid_until,state,completed_at,location,notes,session_id)
     VALUES(company,actor,cat.title,btrim(p_payload->>'trainer'),held::timestamp AT TIME ZONE 'Europe/Istanbul',minutes,validity,'completed',now(),coalesce(p_payload->>'location',''),coalesce(p_payload->>'notes',''),sid) RETURNING id INTO record_id;
    UPDATE private_isg.pilot_training_records SET company_snapshot=(SELECT jsonb_build_object('company_name',c.name,'hazard_class',c.hazard_class) FROM public.companies c WHERE c.id=company) WHERE id=record_id;
    IF jsonb_typeof(entry->'participants') IS DISTINCT FROM 'array' OR jsonb_array_length(entry->'participants') NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'PARTICIPANT_REQUIRED'; END IF;
    ids:='{}';
    FOR person IN SELECT value::text::uuid FROM jsonb_array_elements_text(entry->'participants') LOOP
     IF person IS NULL OR person=ANY(ids) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
     SELECT full_name INTO nm FROM private_isg.employees WHERE id=person AND company_id=company AND owner_id=actor AND NOT is_archived FOR SHARE;
     IF NOT FOUND THEN
      -- Retain an existing archived participant when correcting a historical record.
      SELECT p->>'name' INTO nm FROM jsonb_array_elements(before_row->'companies') c,
       LATERAL jsonb_array_elements(c->'participants') p WHERE c->>'company_id'=company::text AND p->>'id'=person::text;
      IF nm IS NULL THEN RAISE EXCEPTION 'PARTICIPANT_UNAVAILABLE'; END IF;
     END IF;
     ids:=array_append(ids,person);
     INSERT INTO private_isg.pilot_training_participants VALUES(company,record_id,person,nm,true);
    END LOOP;
   END LOOP;
  END IF;
  result:=jsonb_build_object('schema_version',2,'owner_id',actor,'mutation_id',p_mutation,'row',private_isg.pilot_training_session_row(sid));
 END IF;
 INSERT INTO private_isg.pilot_training_session_receipts VALUES(actor,p_mutation,fingerprint,result,now());
 RETURN result;
END $$;
CREATE FUNCTION public.isg_pilot_training_sessions_v2(p_company uuid DEFAULT NULL,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.pilot_training_sessions_read(p_company,p_after) $$;
CREATE FUNCTION public.isg_pilot_training_record_v2(p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.pilot_training_sessions_save(p_mutation,p_payload) $$;
REVOKE ALL ON FUNCTION private_isg.pilot_training_session_row(uuid),private_isg.pilot_training_sessions_read(uuid,uuid),
 private_isg.pilot_training_sessions_save(uuid,jsonb),public.isg_pilot_training_sessions_v2(uuid,uuid),public.isg_pilot_training_record_v2(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.pilot_training_sessions_read(uuid,uuid),private_isg.pilot_training_sessions_save(uuid,jsonb),
 public.isg_pilot_training_sessions_v2(uuid,uuid),public.isg_pilot_training_record_v2(uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';

-- Old clients may resolve a committed receipt, but must upgrade to write again.
CREATE OR REPLACE FUNCTION private_isg.pilot_training_save(p_company uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.require_company(p_company,true); prior private_isg.pilot_training_receipts;
BEGIN
 SELECT * INTO prior FROM private_isg.pilot_training_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
 IF FOUND AND prior.request_hash=sha256(convert_to(jsonb_build_array(p_company,p_payload)::text,'UTF8')) THEN RETURN prior.response; END IF;
 RAISE EXCEPTION 'UPGRADE_REQUIRED';
END $$;
