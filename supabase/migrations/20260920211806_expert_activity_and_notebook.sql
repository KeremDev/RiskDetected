-- Forward-only activity foundation. No historical usage is inferred.
CREATE TABLE private_isg.usage_sessions (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  workspace_id uuid REFERENCES private_isg.workspaces(id) ON DELETE SET NULL,
  running boolean NOT NULL DEFAULT false,
  active_seconds numeric NOT NULL DEFAULT 0 CHECK(active_seconds >= 0)
);
CREATE INDEX usage_sessions_owner ON private_isg.usage_sessions(user_id,started_at DESC);
CREATE TABLE private_isg.usage_intervals (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES private_isg.usage_sessions(session_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workspace_id uuid REFERENCES private_isg.workspaces(id) ON DELETE SET NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  CHECK(ends_at > starts_at AND ends_at <= starts_at + interval '90 seconds')
);
CREATE INDEX usage_intervals_owner ON private_isg.usage_intervals(user_id,ends_at DESC);
CREATE TABLE private_isg.usage_totals (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope text NOT NULL,
  active_seconds numeric NOT NULL DEFAULT 0 CHECK(active_seconds >= 0),
  PRIMARY KEY(user_id,scope)
);
CREATE TABLE private_isg.usage_membership_totals (
  membership_id uuid PRIMARY KEY REFERENCES private_isg.workspace_memberships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  active_seconds numeric NOT NULL DEFAULT 0,
  workspace_seconds numeric NOT NULL DEFAULT 0
);
ALTER TABLE private_isg.usage_membership_totals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.usage_membership_totals FROM PUBLIC,anon,authenticated;
ALTER TABLE private_isg.usage_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.usage_intervals ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.usage_totals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.usage_sessions,private_isg.usage_intervals,private_isg.usage_totals FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.isg_usage_presence_v1(p_action text,p_workspace uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid := private_isg.active_actor();
  sid uuid := (auth.jwt()->>'session_id')::uuid;
  t timestamptz := clock_timestamp(); s private_isg.usage_sessions;
  since timestamptz; seconds numeric := 0;
BEGIN
  IF p_action IS NULL OR p_action NOT IN ('start','heartbeat','stop') OR sid IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  IF p_workspace IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  END IF;
  -- Serialize all devices for an owner: overlapping foreground ranges count once.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text,8271));
  INSERT INTO private_isg.usage_sessions(session_id,user_id)
    VALUES(sid,actor) ON CONFLICT DO NOTHING;
  SELECT * INTO STRICT s FROM private_isg.usage_sessions WHERE session_id=sid AND user_id=actor FOR UPDATE;
  -- A late heartbeat after a crash/offline gap establishes a new baseline, not time credit.
  IF s.running AND p_action <> 'start' AND s.workspace_id IS NOT DISTINCT FROM p_workspace
     AND t-s.last_seen_at <= interval '90 seconds' THEN
    since := s.last_seen_at;
    SELECT greatest(since,coalesce(max(ends_at),since)) INTO since
      FROM private_isg.usage_intervals WHERE user_id=actor AND ends_at>since;
    seconds := greatest(0,least(90,extract(epoch FROM t-since)));
    IF seconds>0 THEN
      INSERT INTO private_isg.usage_intervals(session_id,user_id,workspace_id,starts_at,ends_at)
        VALUES(sid,actor,p_workspace,since,t);
      INSERT INTO private_isg.usage_totals(user_id,scope,active_seconds) VALUES(actor,'all',seconds)
        ON CONFLICT(user_id,scope) DO UPDATE SET active_seconds=private_isg.usage_totals.active_seconds+excluded.active_seconds;
      INSERT INTO private_isg.usage_totals(user_id,scope,active_seconds) VALUES(actor,coalesce(p_workspace::text,'personal'),seconds)
        ON CONFLICT(user_id,scope) DO UPDATE SET active_seconds=private_isg.usage_totals.active_seconds+excluded.active_seconds;
      INSERT INTO private_isg.usage_membership_totals(membership_id,user_id,active_seconds,workspace_seconds)
        SELECT id,actor,least(seconds,greatest(0,extract(epoch FROM t-greatest(since,joined_at)))),
          CASE WHEN workspace_id=p_workspace THEN least(seconds,greatest(0,extract(epoch FROM t-greatest(since,joined_at)))) ELSE 0 END
        FROM private_isg.workspace_memberships WHERE user_id=actor AND status='active' AND joined_at<t
        ON CONFLICT(membership_id) DO UPDATE SET
          active_seconds=private_isg.usage_membership_totals.active_seconds+excluded.active_seconds,
          workspace_seconds=private_isg.usage_membership_totals.workspace_seconds+excluded.workspace_seconds;
    END IF;
  END IF;
  UPDATE private_isg.usage_sessions SET last_seen_at=t,workspace_id=p_workspace,
    running=p_action<>'stop',active_seconds=active_seconds+seconds WHERE session_id=sid;
  RETURN jsonb_build_object('schema_version',1,'accepted_seconds',seconds,'last_active_at',t);
END $$;
REVOKE ALL ON FUNCTION public.isg_usage_presence_v1(text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.isg_usage_presence_v1(text,uuid) TO authenticated;

CREATE FUNCTION private_isg.usage_summary(p_user uuid,p_since timestamptz DEFAULT '-infinity',p_until timestamptz DEFAULT 'infinity',p_workspace uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH ranges AS (
   SELECT greatest(starts_at,p_since) a,least(ends_at,p_until) b,workspace_id
   FROM private_isg.usage_intervals WHERE user_id=p_user AND ends_at>p_since AND starts_at<p_until
 ), durations AS (
   SELECT coalesce(sum(extract(epoch FROM b-a)),0) period,
     coalesce(sum(greatest(0,extract(epoch FROM b-greatest(a,date_trunc('day',now() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul')))),0) today,
     coalesce(sum(greatest(0,extract(epoch FROM b-greatest(a,now()-interval '7 days')))),0) week,
     coalesce(sum(greatest(0,extract(epoch FROM b-greatest(a,now()-interval '30 days')))),0) month_seconds,
     coalesce(sum(extract(epoch FROM b-a)) FILTER(WHERE workspace_id=p_workspace),0) workspace
   FROM ranges
 ), sessions AS (
   SELECT max(started_at) last_login,max(least(last_seen_at,p_until)) last_active,count(*) logins
   FROM private_isg.usage_sessions WHERE user_id=p_user AND started_at>=p_since AND started_at<=p_until
 ) SELECT jsonb_build_object('today_seconds',today,'week_seconds',week,'month_seconds',month_seconds,
   'total_seconds',CASE WHEN p_since='-infinity'::timestamptz THEN
     coalesce((SELECT active_seconds FROM private_isg.usage_totals WHERE user_id=p_user AND scope='all'),0)
     ELSE coalesce((SELECT t.active_seconds FROM private_isg.usage_membership_totals t JOIN private_isg.workspace_memberships m ON m.id=t.membership_id WHERE m.workspace_id=p_workspace AND m.user_id=p_user AND m.joined_at=p_since),period) END,
   'workspace_seconds',coalesce((SELECT t.workspace_seconds FROM private_isg.usage_membership_totals t JOIN private_isg.workspace_memberships m ON m.id=t.membership_id WHERE m.workspace_id=p_workspace AND m.user_id=p_user AND m.joined_at=p_since),workspace),
   'last_login_at',last_login,'last_active_at',last_active,'login_count',logins,
   'session_seconds',coalesce((SELECT CASE WHEN p_since='-infinity'::timestamptz THEN s.active_seconds ELSE coalesce((SELECT sum(extract(epoch FROM least(i.ends_at,p_until)-greatest(i.starts_at,p_since))) FROM private_isg.usage_intervals i WHERE i.session_id=s.session_id AND i.ends_at>p_since AND i.starts_at<p_until),0) END
     FROM private_isg.usage_sessions s WHERE s.user_id=p_user AND s.started_at>=p_since AND s.started_at<=p_until ORDER BY s.last_seen_at DESC LIMIT 1),0))
 FROM durations CROSS JOIN sessions;
$$;
REVOKE ALL ON FUNCTION private_isg.usage_summary(uuid,timestamptz,timestamptz,uuid) FROM PUBLIC,anon,authenticated;

CREATE TABLE private_isg.business_activity_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_key text NOT NULL UNIQUE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  workspace_id uuid REFERENCES private_isg.workspaces(id) ON DELETE SET NULL,
  company_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  correlation_id uuid,
  changes jsonb NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(changes)='array'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX business_activity_self ON private_isg.business_activity_events(actor_user_id,id DESC);
CREATE INDEX business_activity_workspace ON private_isg.business_activity_events(workspace_id,actor_user_id,id DESC);
ALTER TABLE private_isg.business_activity_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.business_activity_events FROM PUBLIC,anon,authenticated;

-- Strict structural allowlist. Free text (including titles and reasons) never leaves the journal.
CREATE FUNCTION private_isg.activity_safe_changes(p_before jsonb,p_after jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('field',k,'before',p_before->k,'after',p_after->k)),'[]'::jsonb)
 FROM unnest(ARRAY['status','state','version','hazard_class','role','is_primary','starts_on','ends_on','due_on','completed_at','employee_count']) k
 WHERE (p_before->k IS DISTINCT FROM p_after->k)
 AND (p_before->k IS NULL OR jsonb_typeof(p_before->k) IN ('string','number','boolean','null'))
 AND (p_after->k IS NULL OR jsonb_typeof(p_after->k) IN ('string','number','boolean','null'));
$$;
REVOKE ALL ON FUNCTION private_isg.activity_safe_changes(jsonb,jsonb) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private_isg.activity_from_workspace_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.action ~ '(read|search|filter|autosave|draft|notice.mark)' THEN RETURN NEW; END IF;
  INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,company_id,action,entity_type,entity_id,correlation_id,changes,created_at)
  VALUES('workspace_audit:'||NEW.id,NEW.actor_user_id,NEW.workspace_id,
    CASE WHEN NEW.entity_type='company' THEN NEW.entity_id ELSE nullif(NEW.after_state->>'company_id','')::uuid END,
    NEW.action,NEW.entity_type,NEW.entity_id,NEW.correlation_id,
    private_isg.activity_safe_changes(NEW.before_state,NEW.after_state),NEW.created_at)
  ON CONFLICT(source_key) DO NOTHING;
  RETURN NEW;
END $$;
-- Maintenance never touches lifetime totals or the authentication-session count.
CREATE FUNCTION private_isg.prune_expert_activity() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 DELETE FROM private_isg.usage_intervals WHERE ends_at<clock_timestamp()-interval '24 months';
 DELETE FROM private_isg.business_activity_events WHERE created_at<clock_timestamp()-interval '5 years';
END $$;
REVOKE ALL ON FUNCTION private_isg.prune_expert_activity() FROM PUBLIC,anon,authenticated;
ALTER TABLE private_isg.workspace_audit ALTER COLUMN actor_user_id DROP NOT NULL;
CREATE FUNCTION private_isg.erase_activity_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 DELETE FROM private_isg.business_activity_events WHERE actor_user_id=OLD.id AND workspace_id IS NULL;
 UPDATE private_isg.business_activity_events SET actor_user_id=NULL,
   entity_id=CASE WHEN entity_id=OLD.id THEN NULL ELSE entity_id END WHERE actor_user_id=OLD.id;
 UPDATE private_isg.workspace_audit SET actor_user_id=NULL,before_state=NULL,after_state='{"actor_deleted":true}'::jsonb
   WHERE actor_user_id=OLD.id;
 RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION private_isg.erase_activity_identity() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER expert_activity_account_erasure BEFORE DELETE ON auth.users FOR EACH ROW EXECUTE FUNCTION private_isg.erase_activity_identity();
REVOKE ALL ON FUNCTION private_isg.activity_from_workspace_audit() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER business_activity_workspace AFTER INSERT ON private_isg.workspace_audit
FOR EACH ROW EXECUTE FUNCTION private_isg.activity_from_workspace_audit();
INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,company_id,action,entity_type,entity_id,correlation_id,changes,created_at)
 SELECT 'workspace_audit:'||a.id,u.id,a.workspace_id,
   CASE WHEN a.entity_type='company' THEN a.entity_id ELSE nullif(a.after_state->>'company_id','')::uuid END,
   a.action,a.entity_type,a.entity_id,a.correlation_id,private_isg.activity_safe_changes(a.before_state,a.after_state),a.created_at
 FROM private_isg.workspace_audit a LEFT JOIN auth.users u ON u.id=a.actor_user_id
 WHERE a.action !~ '(read|search|filter|autosave|draft|notice.mark)' AND a.created_at>=now()-interval '5 years'
 ON CONFLICT(source_key) DO NOTHING;

CREATE FUNCTION private_isg.activity_page(p_user uuid,p_workspace uuid,p_after bigint,p_from timestamptz,p_to timestamptz,p_action text,p_company uuid,p_manager boolean)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH page AS (
 SELECT e.id,e.action,e.entity_type,e.entity_id,e.company_id,e.correlation_id,e.created_at,
   CASE WHEN e.workspace_id IS NOT NULL THEN
     (SELECT c.name FROM private_isg.workspace_companies c WHERE c.workspace_id=e.workspace_id AND (c.id=e.company_id OR c.legacy_company_id=e.company_id) LIMIT 1)
     ELSE (SELECT c.name FROM public.companies c WHERE c.id=e.company_id AND c.user_id=p_user) END company_name
 FROM private_isg.business_activity_events e WHERE e.actor_user_id=p_user
 AND (NOT p_manager OR (e.workspace_id=p_workspace AND e.entity_type<>'personal_note'))
 AND (p_after IS NULL OR e.id<p_after) AND e.created_at>=p_from AND e.created_at<=p_to
 AND (p_action IS NULL OR e.action=p_action) AND (p_company IS NULL OR e.company_id=p_company)
 ORDER BY e.id DESC LIMIT 31
 ), shown AS (SELECT * FROM page ORDER BY id DESC LIMIT 30)
 SELECT jsonb_build_object('items',coalesce((SELECT jsonb_agg(to_jsonb(shown) ORDER BY id DESC) FROM shown),'[]'::jsonb),
 'next_cursor',CASE WHEN (SELECT count(*) FROM page)>30 THEN (SELECT min(id) FROM shown) ELSE NULL END);
$$;
REVOKE ALL ON FUNCTION private_isg.activity_page(uuid,uuid,bigint,timestamptz,timestamptz,text,uuid,boolean) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.isg_activity_self_v1(p_after bigint DEFAULT NULL,p_from timestamptz DEFAULT '-infinity',p_to timestamptz DEFAULT 'infinity',p_action text DEFAULT NULL,p_company uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
 RETURN jsonb_build_object('schema_version',1,'summary',private_isg.usage_summary(actor)) ||
 private_isg.activity_page(actor,NULL,p_after,p_from,p_to,p_action,p_company,false);
END $$;
CREATE FUNCTION public.isg_workspace_member_activity_v1(p_workspace uuid,p_user uuid,p_after bigint DEFAULT NULL,p_from timestamptz DEFAULT '-infinity',p_to timestamptz DEFAULT 'infinity',p_action text DEFAULT NULL,p_company uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships;
BEGIN
 PERFORM private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
 SELECT * INTO member FROM private_isg.workspace_memberships WHERE workspace_id=p_workspace AND user_id=p_user;
 IF member.id IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 RETURN jsonb_build_object('schema_version',1,'summary',private_isg.usage_summary(p_user,member.joined_at,coalesce(member.ended_at,member.suspended_at,'infinity'),p_workspace)) ||
 private_isg.activity_page(p_user,p_workspace,p_after,greatest(p_from,member.joined_at),least(p_to,coalesce(member.ended_at,member.suspended_at,'infinity')),p_action,p_company,true);
END $$;
CREATE FUNCTION public.isg_activity_event_detail_v1(p_event bigint,p_workspace uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); e private_isg.business_activity_events;
BEGIN
 SELECT * INTO e FROM private_isg.business_activity_events WHERE id=p_event;
 IF e.id IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF e.actor_user_id IS DISTINCT FROM actor OR p_workspace IS NOT NULL THEN
   IF p_workspace IS NULL OR e.workspace_id IS DISTINCT FROM p_workspace OR e.entity_type='personal_note' THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
   PERFORM private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
   IF e.actor_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.workspace_memberships m WHERE m.workspace_id=p_workspace AND m.user_id=e.actor_user_id
     AND e.created_at>=m.joined_at AND e.created_at<=coalesce(m.ended_at,m.suspended_at,'infinity')) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 END IF;
 RETURN jsonb_build_object('id',e.id,'action',e.action,'entity_type',e.entity_type,'entity_id',e.entity_id,
   'company_id',e.company_id,'correlation_id',e.correlation_id,'created_at',e.created_at,'changes',e.changes);
END $$;
REVOKE ALL ON FUNCTION public.isg_activity_self_v1(bigint,timestamptz,timestamptz,text,uuid),public.isg_workspace_member_activity_v1(uuid,uuid,bigint,timestamptz,timestamptz,text,uuid),public.isg_activity_event_detail_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.isg_activity_self_v1(bigint,timestamptz,timestamptz,text,uuid),public.isg_workspace_member_activity_v1(uuid,uuid,bigint,timestamptz,timestamptz,text,uuid),public.isg_activity_event_detail_v1(bigint,uuid) TO authenticated;

-- Successful mutation receipts are inserted once, in the business transaction.
-- Replays return the old receipt without inserting and therefore cannot log twice.
CREATE FUNCTION private_isg.activity_from_receipt() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE row jsonb:=to_jsonb(NEW); answer jsonb:=row->'response'; actor uuid;
 company uuid; workspace uuid; action text; entity uuid; payload jsonb;
BEGIN
 actor:=coalesce(row->>'actor_id',row->>'owner_id')::uuid;
 IF actor IS NULL THEN RETURN NEW; END IF;
 action:=coalesce(answer->>'action',answer->>'state','save');
 IF action ~ '(draft|autosave|read|search|filter|conflict)' OR coalesce((answer->>'replayed')::boolean,false) THEN RETURN NEW; END IF;
 payload:=coalesce(answer->'row',answer->'answer',answer->'result',answer);
 company:=coalesce(row->>'company_id',answer->>'company_id',payload->>'company_id')::uuid;
 workspace:=nullif(current_setting('private_isg.expert_workspace',true),'')::uuid;
 IF workspace IS NULL AND company IS NOT NULL THEN
   SELECT workspace_id INTO workspace FROM private_isg.workspace_companies WHERE legacy_company_id=company OR id=company LIMIT 1;
 END IF;
 entity:=coalesce(payload->>TG_ARGV[1],payload->>'id',answer->>TG_ARGV[1])::uuid;
 IF TG_ARGV[0]='personnel' THEN
   SELECT a.action INTO action FROM private_isg.personnel_audit a
     WHERE a.actor_id=actor AND a.operation_id=(row->>'operation_id')::uuid ORDER BY created_at DESC LIMIT 1;
 END IF;
 INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,company_id,action,entity_type,entity_id,correlation_id,changes)
 VALUES(TG_TABLE_NAME||':'||encode(sha256(convert_to(actor::text||':'||(row->>'mutation_id'),'UTF8')),'hex'),actor,workspace,company,TG_ARGV[0]||'.'||coalesce(action,'save'),TG_ARGV[0],entity,
   coalesce(row->>'operation_id',row->>'mutation_id')::uuid,private_isg.activity_safe_changes(NULL,payload))
 ON CONFLICT(source_key) DO NOTHING;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.activity_from_receipt() FROM PUBLIC,anon,authenticated;
DO $$ DECLARE mapping text[]; BEGIN
 FOREACH mapping SLICE 1 IN ARRAY ARRAY[
   ['appointment_receipts','assignment','appointment_id'],['checklist_receipts','checklist','template_id'],
   ['document_tracking_receipts','document','record_id'],['drill_receipts','drill','drill_id'],
   ['education_receipts','training','training_id'],['emergency_plan_receipts','emergency','plan_id'],
   ['equipment_check_receipts','equipment','equipment_id'],['file_library_receipts','file','file_id'],
   ['module_edit_receipts','module','entity_id'],['nonconformity_receipts','nonconformity','nonconformity_id'],
   ['personnel_receipts','personnel','employee_id'],['pilot_training_receipts','training','training_id'],
   ['pilot_training_session_receipts','training','session_id'],['ppe_receipts','ppe','handover_id'],
   ['risk_version_receipts','risk','assessment_id']
 ] LOOP
   EXECUTE format('CREATE TRIGGER business_activity_receipt AFTER INSERT ON private_isg.%I FOR EACH ROW EXECUTE FUNCTION private_isg.activity_from_receipt(%L,%L)',mapping[1],mapping[2],mapping[3]);
 END LOOP;
END $$;
