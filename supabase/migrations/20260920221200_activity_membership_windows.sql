-- Preserve actual active membership windows across suspension/reactivation.
CREATE TABLE private_isg.usage_membership_windows (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 membership_id uuid NOT NULL REFERENCES private_isg.workspace_memberships(id) ON DELETE CASCADE,
 starts_at timestamptz NOT NULL, ends_at timestamptz,
 CHECK(ends_at IS NULL OR ends_at>=starts_at)
);
CREATE INDEX usage_membership_windows_member ON private_isg.usage_membership_windows(membership_id,starts_at);
ALTER TABLE private_isg.usage_membership_windows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.usage_membership_windows FROM PUBLIC,anon,authenticated;
INSERT INTO private_isg.usage_membership_windows(membership_id,starts_at,ends_at)
SELECT id,joined_at,coalesce(ended_at,suspended_at) FROM private_isg.workspace_memberships
WHERE joined_at IS NOT NULL;
CREATE FUNCTION private_isg.track_usage_membership_window() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='INSERT' THEN
   IF NEW.status='active' THEN INSERT INTO private_isg.usage_membership_windows(membership_id,starts_at) VALUES(NEW.id,NEW.joined_at); END IF;
 ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
   IF OLD.status='active' THEN UPDATE private_isg.usage_membership_windows SET ends_at=greatest(starts_at,clock_timestamp()) WHERE membership_id=NEW.id AND ends_at IS NULL; END IF;
   IF NEW.status='active' THEN INSERT INTO private_isg.usage_membership_windows(membership_id,starts_at) VALUES(NEW.id,clock_timestamp()); END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.track_usage_membership_window() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER usage_membership_window AFTER INSERT OR UPDATE ON private_isg.workspace_memberships
FOR EACH ROW EXECUTE FUNCTION private_isg.track_usage_membership_window();

CREATE OR REPLACE FUNCTION private_isg.usage_summary(p_user uuid,p_since timestamptz DEFAULT '-infinity',p_until timestamptz DEFAULT 'infinity',p_workspace uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH windows AS (
 SELECT '-infinity'::timestamptz a,'infinity'::timestamptz b WHERE p_workspace IS NULL
 UNION ALL
 SELECT greatest(w.starts_at,p_since),least(coalesce(w.ends_at,'infinity'),p_until)
 FROM private_isg.usage_membership_windows w JOIN private_isg.workspace_memberships m ON m.id=w.membership_id
 WHERE m.workspace_id=p_workspace AND m.user_id=p_user
 ), ranges AS (
 SELECT greatest(i.starts_at,w.a,p_since) a,least(i.ends_at,w.b,p_until) b,i.workspace_id,i.session_id
 FROM private_isg.usage_intervals i JOIN windows w ON i.ends_at>w.a AND i.starts_at<w.b
 WHERE i.user_id=p_user AND i.ends_at>p_since AND i.starts_at<p_until
 ), durations AS (
 SELECT coalesce(sum(extract(epoch FROM b-a)),0) period,
 coalesce(sum(greatest(0,extract(epoch FROM b-greatest(a,date_trunc('day',now() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul')))),0) today,
 coalesce(sum(greatest(0,extract(epoch FROM b-greatest(a,now()-interval '7 days')))),0) week,
 coalesce(sum(greatest(0,extract(epoch FROM b-greatest(a,now()-interval '30 days')))),0) month_seconds,
 coalesce(sum(extract(epoch FROM b-a)) FILTER(WHERE workspace_id=p_workspace),0) workspace
 FROM ranges WHERE b>a
 ), sessions AS (
 SELECT max(s.started_at) FILTER(WHERE EXISTS(SELECT 1 FROM windows WHERE s.started_at>=a AND s.started_at<=b)) last_login,
 count(*) FILTER(WHERE EXISTS(SELECT 1 FROM windows WHERE s.started_at>=a AND s.started_at<=b)) logins
 FROM private_isg.usage_sessions s WHERE s.user_id=p_user AND s.started_at>=p_since AND s.started_at<=p_until
 )
 SELECT jsonb_build_object('today_seconds',today,'week_seconds',week,'month_seconds',month_seconds,
 'total_seconds',CASE WHEN p_workspace IS NULL THEN coalesce((SELECT active_seconds FROM private_isg.usage_totals WHERE user_id=p_user AND scope='all'),0)
 ELSE coalesce((SELECT t.active_seconds FROM private_isg.usage_membership_totals t JOIN private_isg.workspace_memberships m ON m.id=t.membership_id WHERE m.workspace_id=p_workspace AND m.user_id=p_user),period) END,
 'workspace_seconds',CASE WHEN p_workspace IS NULL THEN 0 ELSE coalesce((SELECT t.workspace_seconds FROM private_isg.usage_membership_totals t JOIN private_isg.workspace_memberships m ON m.id=t.membership_id WHERE m.workspace_id=p_workspace AND m.user_id=p_user),workspace) END,
 'last_login_at',last_login,'login_count',logins,
 'last_active_at',CASE WHEN p_workspace IS NULL THEN (SELECT max(last_seen_at) FROM private_isg.usage_sessions WHERE user_id=p_user)
 ELSE (SELECT max(b) FROM ranges WHERE b>a) END,
 'session_seconds',coalesce((SELECT CASE WHEN p_workspace IS NULL THEN s.active_seconds
 ELSE coalesce((SELECT sum(extract(epoch FROM r.b-r.a)) FROM ranges r WHERE r.session_id=s.session_id AND r.b>r.a),0) END
 FROM private_isg.usage_sessions s WHERE s.user_id=p_user AND s.last_seen_at>=p_since AND s.started_at<=p_until
 ORDER BY s.last_seen_at DESC LIMIT 1),0)) FROM durations CROSS JOIN sessions;
$$;

CREATE OR REPLACE FUNCTION private_isg.erase_activity_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 DELETE FROM private_isg.business_activity_events WHERE actor_user_id=OLD.id AND workspace_id IS NULL;
 UPDATE private_isg.business_activity_events SET actor_user_id=NULL,
 source_key='erased:'||encode(sha256(convert_to(source_key,'UTF8')),'hex'),
 entity_id=CASE WHEN entity_id=OLD.id THEN NULL ELSE entity_id END,
 correlation_id=CASE WHEN correlation_id=OLD.id THEN NULL ELSE correlation_id END
 WHERE actor_user_id=OLD.id;
 UPDATE private_isg.business_activity_events SET entity_id=NULL WHERE entity_id=OLD.id;
 UPDATE private_isg.workspace_audit SET actor_user_id=NULL,before_state=NULL,after_state='{"actor_deleted":true}'::jsonb
 WHERE actor_user_id=OLD.id;
 RETURN OLD;
END $$;
