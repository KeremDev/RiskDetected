-- Home feed ("Senin İçin") checks. Actors:
--   A1 personal, growing   A2 personal, other owner   A3 personal, new
--   A4 personal, no company but real use
--   E1/E2 organization experts   O1 organization owner
CREATE FUNCTION pg_temp.ids(p jsonb, p_list text DEFAULT 'cards') RETURNS text[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(x->>'id' ORDER BY n), '{}') FROM jsonb_array_elements(p->p_list) WITH ORDINALITY e(x, n) $$;
CREATE FUNCTION pg_temp.card(p jsonb, p_id text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT x FROM jsonb_array_elements(p->'cards') x WHERE x->>'id' = p_id
  UNION ALL SELECT x FROM jsonb_array_elements(p->'more') x WHERE x->>'id' = p_id LIMIT 1 $$;
CREATE FUNCTION pg_temp.istanbul_day(p_offset integer) RETURNS timestamptz LANGUAGE sql AS $$
  SELECT (((now() AT TIME ZONE 'Europe/Istanbul')::date + p_offset)::timestamp AT TIME ZONE 'Europe/Istanbul') $$;

INSERT INTO public.profiles VALUES
  ('20000000-0000-0000-0000-000000000001', now() - interval '60 days'),
  ('20000000-0000-0000-0000-000000000002', now() - interval '90 days'),
  ('20000000-0000-0000-0000-000000000003', now() - interval '1 day'),
  ('20000000-0000-0000-0000-000000000004', now() - interval '30 days'),
  ('20000000-0000-0000-0000-000000000005', now() - interval '30 days'),
  ('20000000-0000-0000-0000-000000000006', now() - interval '30 days'),
  ('20000000-0000-0000-0000-000000000007', now() - interval '200 days');
INSERT INTO public.companies(id, user_id, name, is_archived, workspace_id) VALUES
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Deneme Firması', false, NULL),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'Arşiv Firma', true, NULL),
  ('10000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001', 'Grant revoked firma', false, NULL),
  ('10000000-0000-0000-0000-000000000009', '20000000-0000-0000-0000-000000000002', 'Başka Firma', false, NULL),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000006', 'OSGB Firma', false, '40000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000006', 'Atanmamış Firma', false, '40000000-0000-0000-0000-000000000001');
INSERT INTO private_isg.workspace_memberships(workspace_id, user_id, role) VALUES
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000004', 'expert'),
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000005', 'expert'),
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000006', 'owner');
INSERT INTO private_isg.test_assignments VALUES
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000004'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000005'),
  ('10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000005');

-- A1: six photo analyses in the pilot company (three a month ago, two this
-- week, one the week before), two filed under an archived and a revoked
-- company (the analyses list shows every finished photo analysis of the
-- account, so they count too) and rows that must never count.
INSERT INTO public.analyses(user_id, company_id, kind, status, completed_at, created_at)
SELECT '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'photo', 'completed', t, t
  FROM unnest(ARRAY[now() - interval '40 days', now() - interval '41 days', now() - interval '42 days',
                    now() - interval '1 hour', now() - interval '2 days', now() - interval '9 days']) t;
INSERT INTO public.analyses(user_id, company_id, kind, status, completed_at, created_at) VALUES
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'photo', 'completed', now(), now()),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000005', 'photo', 'completed', now(), now()),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'photo', 'failed', now(), now()),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'text', 'completed', now(), now()),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'photo', 'completed', now() + interval '2 days', now() + interval '2 days'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000009', 'photo', 'completed', now(), now());
INSERT INTO private_isg.employees(company_id, created_by_user_id) VALUES
  ('10000000-0000-0000-0000-000000000001', NULL), ('10000000-0000-0000-0000-000000000001', NULL);
INSERT INTO private_isg.nonconformities(nonconformity_id, company_id, state, record_kind, title, due_on, updated_at) VALUES
  ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'draft', 'nonconformity',
   'Taslak iskele bulgusu', NULL, now() - interval '1 hour');
INSERT INTO private_isg.pilot_training_sessions(id, owner_id, held_on, deleted_at) VALUES
  ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Europe/Istanbul')::date - 2, NULL),
  ('50000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Europe/Istanbul')::date - 2, now());
INSERT INTO private_isg.pilot_training_records(id, company_id, owner_id, session_id, state, starts_at) VALUES
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
   '50000000-0000-0000-0000-000000000001', 'completed', now() - interval '2 days'),
  ('60000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
   '50000000-0000-0000-0000-000000000002', 'completed', now() - interval '2 days');
INSERT INTO private_isg.pilot_training_participants VALUES
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', true),
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', true),
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003', false),
  ('60000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000004', true);
INSERT INTO private_isg.test_followup VALUES
  ('20000000-0000-0000-0000-000000000001', 'equipment', '10000000-0000-0000-0000-000000000001', 'Deneme Firması',
   '80000000-0000-0000-0000-000000000001', 'Forklift', current_date - 3, 30),
  ('20000000-0000-0000-0000-000000000001', 'training', '10000000-0000-0000-0000-000000000001', 'Deneme Firması',
   '80000000-0000-0000-0000-000000000002', 'Temel eğitim', current_date + 3, 30),
  ('20000000-0000-0000-0000-000000000001', 'document', '10000000-0000-0000-0000-000000000001', 'Deneme Firması',
   '80000000-0000-0000-0000-000000000003', 'Ölçüm raporu', current_date + 20, 30),
  ('20000000-0000-0000-0000-000000000001', 'document', '10000000-0000-0000-0000-000000000001', 'Deneme Firması',
   '80000000-0000-0000-0000-000000000004', 'Uzak belge', current_date + 90, 30),
  ('20000000-0000-0000-0000-000000000002', 'equipment', '10000000-0000-0000-0000-000000000009', 'Başka Firma',
   '80000000-0000-0000-0000-000000000009', 'Başkasının', current_date - 3, 30);

-- Organization data: E1 has six analyses (two this week) in its company, E2
-- works in the same company, and an overdue finding belongs to the scope.
INSERT INTO private_isg.workspace_analyses(workspace_id, company_id, kind, status, created_by_user_id, created_at)
SELECT '40000000-0000-0000-0000-000000000001', c, 'photo', 'ready', u, t FROM (VALUES
  ('10000000-0000-0000-0000-000000000003'::uuid, '20000000-0000-0000-0000-000000000004'::uuid, now() - interval '1 hour'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000004', now() - interval '3 days'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000004', now() - interval '40 days'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000004', now() - interval '41 days'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000004', now() - interval '42 days'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000004', now() - interval '43 days'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000005', now() - interval '1 hour'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000005', now() - interval '2 hours'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000005', now() - interval '3 hours'),
  ('10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000004', now() - interval '1 hour')) v(c, u, t);
INSERT INTO private_isg.nonconformities(nonconformity_id, company_id, state, record_kind, title, due_on, created_by_user_id) VALUES
  ('70000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003', 'open', 'nonconformity',
   'Korkuluk eksik', current_date - 2, '20000000-0000-0000-0000-000000000005'),
  ('70000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000003', 'draft', 'nonconformity',
   'E2 taslağı', NULL, '20000000-0000-0000-0000-000000000005'),
  ('70000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000003', 'draft', 'nonconformity',
   'E1 taslağı', NULL, '20000000-0000-0000-0000-000000000004'),
  ('70000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000004', 'open', 'nonconformity',
   'Görünmeyen', current_date - 2, '20000000-0000-0000-0000-000000000005');

-- A4 works without companies: six completed photo analyses, none linked.
INSERT INTO public.analyses(user_id, company_id, kind, status, completed_at, created_at)
SELECT '20000000-0000-0000-0000-000000000007', NULL, 'photo', 'completed', now() - (i || ' days')::interval, now() - (i || ' days')::interval
  FROM generate_series(1, 6) i;

-- 1. A personal account with a lapsed record, work in progress and records
-- coming due: the lapsed record takes the main card, then the draft, then
-- the upcoming card whose count is the board's "Yaklaşan" count.
SET test.actor = '20000000-0000-0000-0000-000000000001';
DO $$ DECLARE r jsonb; c jsonb; BEGIN
  r := public.isg_home_feed_v1();
  ASSERT r->>'role' = 'personal' AND r->>'segment' = 'growing' AND (r#>>'{signals,can_write}')::boolean, r::text;
  ASSERT (r#>>'{signals,companies}')::int = 1 AND (r#>>'{signals,personnel}')::int = 2, 'archived and revoked companies stay out';
  ASSERT (r#>>'{signals,analyses,total}')::int = 8, 'every finished photo analysis of the account, none from the future: ' || (r#>>'{signals,analyses}');
  ASSERT (r#>>'{signals,analyses,last7}')::int = 4 AND (r#>>'{signals,analyses,prev7}')::int = 1;
  ASSERT (r#>>'{signals,trainings,people_last7}')::int = 2, 'attendees only, deleted session ignored';
  ASSERT (r#>>'{signals,deadlines,expired}')::int = 1 AND (r#>>'{signals,deadlines,soon}')::int = 2, 'board classification';
  ASSERT pg_temp.ids(r) = ARRAY['critical.expired', 'continue.nonconformity_draft:70000000-0000-0000-0000-000000000001',
    'critical.soon'], pg_temp.ids(r)::text;
  c := r->'cards'->0;
  ASSERT c->>'tone' = 'danger' AND NOT (c->>'dismissible')::boolean AND c#>>'{params,count}' = '1'
     AND c#>>'{target,route}' = 'followup_record' AND c#>>'{target,id}' = '80000000-0000-0000-0000-000000000001'
     AND c#>>'{target,status}' = 'expired' AND c#>>'{params,title}' = 'Forklift' AND NOT c ? 'priority', c::text;
  c := r->'cards'->1;
  ASSERT c->>'kind' = 'continue' AND c#>>'{params,title}' = 'Taslak iskele bulgusu'
     AND c#>>'{params,company_name}' = 'Deneme Firması' AND c#>>'{target,route}' = 'nonconformity'
     AND (c->>'dismissible')::boolean AND NOT c ? 'sort', c::text;
  c := r->'cards'->2;
  ASSERT c->>'tone' = 'warning' AND c#>>'{params,count}' = '2' AND c#>>'{params,title}' = 'Temel eğitim'
     AND c#>>'{target,route}' = 'followup' AND c#>>'{target,status}' = 'soon', 'same count as the list it opens: ' || c::text;
  c := pg_temp.card(r, 'performance.analyses_7d');
  ASSERT c#>>'{params,count}' = '4' AND c#>>'{params,delta}' = '3' AND c#>>'{target,route}' = 'analyses'
     AND c#>>'{target,status}' = 'completed' AND (c#>>'{target,from}')::date = (r->>'today')::date - 6
     AND (c#>>'{target,to}')::date = (r->>'today')::date AND c#>>'{target,mine}' = 'false',
     'the list opens on the same seven days: ' || coalesce(c::text, 'missing');
  c := pg_temp.card(r, 'performance.trained_people_7d');
  ASSERT c#>>'{params,count}' = '2' AND c#>>'{params,sessions}' = '1' AND c#>>'{target,status}' = 'completed'
     AND (c#>>'{target,from}')::date = (r->>'today')::date - 6, coalesce(c::text, 'missing');
  ASSERT pg_temp.card(r, 'performance.records_7d') IS NULL, 'no card without a list of exactly what it counts';
  ASSERT pg_temp.card(r, 'discover.photo_analysis') IS NULL, 'a used feature is not suggested';
  ASSERT pg_temp.card(r, 'discover.nonconformity') IS NULL, 'a draft means the module was tried';
  ASSERT pg_temp.card(r, 'discover.training') IS NULL, 'a training record means the module was tried';
  ASSERT (SELECT count(*) FROM jsonb_array_elements(r->'more') x WHERE x->>'kind' = 'discover') = 3
     AND pg_temp.ids(r, 'more') @> ARRAY['discover.risk_wizard', 'discover.equipment', 'discover.emergency_wizard'],
     'the next three suggestions, in order: ' || pg_temp.ids(r, 'more')::text;
  ASSERT (r->>'more_total')::int = jsonb_array_length(r->'more') AND NOT (r->>'has_more')::boolean, r::text;
  ASSERT position('Başka' IN r::text) = 0 AND position('Başkasının' IN r::text) = 0, 'no other owner data';
END $$;

-- 2. A record stamped later today is not counted yet; the first moment of the
-- 7-day window is, the moment before it belongs to the previous week.
DO $$ DECLARE r jsonb; before jsonb; BEGIN
  before := public.isg_home_feed_v1();
  INSERT INTO public.analyses(user_id, company_id, kind, status, completed_at, created_at) VALUES
    ('20000000-0000-0000-0000-000000000001', NULL, 'photo', 'completed', now() + interval '1 minute', now() + interval '1 minute');
  r := public.isg_home_feed_v1();
  ASSERT r#>'{signals,analyses}' = before#>'{signals,analyses}', 'future stamp counted: ' || (r#>>'{signals,analyses}');
  DELETE FROM public.analyses WHERE user_id = '20000000-0000-0000-0000-000000000001' AND completed_at > now();
END $$;
SET test.actor = '20000000-0000-0000-0000-000000000002';
DO $$ DECLARE r jsonb; BEGIN
  INSERT INTO public.analyses(user_id, company_id, kind, status, completed_at, created_at) VALUES
    ('20000000-0000-0000-0000-000000000002', NULL, 'photo', 'completed', pg_temp.istanbul_day(-6), pg_temp.istanbul_day(-6)),
    ('20000000-0000-0000-0000-000000000002', NULL, 'photo', 'completed', pg_temp.istanbul_day(-6) - interval '1 second',
     pg_temp.istanbul_day(-6) - interval '1 second');
  r := public.isg_home_feed_v1();
  ASSERT (r#>>'{signals,analyses,last7}')::int = 2 AND (r#>>'{signals,analyses,prev7}')::int = 1, r#>>'{signals,analyses}';
  ASSERT (r#>>'{signals,companies}')::int = 1 AND (r#>>'{signals,deadlines,expired}')::int = 1, 'own scope only';
  ASSERT position('Deneme' IN r::text) = 0 AND position('Forklift' IN r::text) = 0;
END $$;

-- 3. Dismissing: unfinished work waits three days, critical cards cannot be
-- dismissed, and the next card moves up. The state is kept for this scope.
SET test.actor = '20000000-0000-0000-0000-000000000001';
DO $$ DECLARE r jsonb; a jsonb; BEGIN
  a := public.isg_home_card_action_v1('dismiss', ARRAY['continue.nonconformity_draft:70000000-0000-0000-0000-000000000001'], gen_random_uuid(), clock_timestamp());
  ASSERT (a->>'applied')::int = 1 AND (SELECT dismissed_until FROM private_isg.home_card_states
           WHERE owner_id = '20000000-0000-0000-0000-000000000001'
             AND card_id = 'continue.nonconformity_draft:70000000-0000-0000-0000-000000000001')
         BETWEEN now() + interval '71 hours' AND now() + interval '73 hours', a::text;
  ASSERT (SELECT scope_key FROM private_isg.home_card_states WHERE owner_id = '20000000-0000-0000-0000-000000000001'
           AND card_id = 'continue.nonconformity_draft:70000000-0000-0000-0000-000000000001') = 'personal';
  BEGIN PERFORM public.isg_home_card_action_v1('dismiss', ARRAY['critical.expired'], gen_random_uuid(), clock_timestamp()); RAISE EXCEPTION 'critical dismissed';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  BEGIN PERFORM public.isg_home_card_action_v1('hide', ARRAY['discover.risk_wizard'], gen_random_uuid(), clock_timestamp()); RAISE EXCEPTION 'unknown action';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  BEGIN PERFORM public.isg_home_card_action_v1('dismiss', ARRAY['discover.risk wizard'], gen_random_uuid(), clock_timestamp()); RAISE EXCEPTION 'bad id';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  BEGIN PERFORM public.isg_home_card_action_v1('dismiss', ARRAY['discover.risk_wizard', 'discover.equipment'], gen_random_uuid(), clock_timestamp()); RAISE EXCEPTION 'batch dismiss';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  r := public.isg_home_feed_v1();
  ASSERT pg_temp.ids(r) = ARRAY['critical.expired', 'critical.soon', 'performance.analyses_7d'], pg_temp.ids(r)::text;
  ASSERT NOT 'continue.nonconformity_draft:70000000-0000-0000-0000-000000000001' = ANY(pg_temp.ids(r, 'more'));
  PERFORM public.isg_home_card_action_v1('restore', ARRAY['continue.nonconformity_draft:70000000-0000-0000-0000-000000000001'], gen_random_uuid(), clock_timestamp());
  r := public.isg_home_feed_v1();
  ASSERT (pg_temp.ids(r))[2] = 'continue.nonconformity_draft:70000000-0000-0000-0000-000000000001', 'restored';
END $$;

-- 4. Many drafts: the three latest, and one card for the rest that opens the
-- module list. Nothing is cut silently.
DO $$ DECLARE r jsonb; c jsonb; BEGIN
  INSERT INTO private_isg.nonconformities(company_id, state, record_kind, title, updated_at)
  SELECT '10000000-0000-0000-0000-000000000001', 'draft', 'nonconformity', 'Taslak ' || i, now() - (i || ' hours')::interval
    FROM generate_series(2, 5) i;
  r := public.isg_home_feed_v1();
  ASSERT (SELECT count(*) FROM (SELECT x FROM jsonb_array_elements(r->'cards') x UNION ALL SELECT x FROM jsonb_array_elements(r->'more') x) y
           WHERE y.x->>'key' = 'continue.nonconformity_draft') = 3, 'three latest drafts';
  c := pg_temp.card(r, 'continue.nonconformity_drafts');
  ASSERT c#>>'{params,count}' = '2' AND c#>>'{params,total}' = '5' AND c#>>'{target,route}' = 'nonconformities'
     AND c#>>'{target,status}' = 'draft' AND c#>>'{target,mine}' = 'false', coalesce(c::text, 'missing');
  ASSERT (r->>'more_total')::int = jsonb_array_length(r->'more') AND NOT (r->>'has_more')::boolean;
  DELETE FROM private_isg.nonconformities WHERE title LIKE 'Taslak _';
END $$;

-- 5. What the client can open decides what it gets; the next card fills the
-- place, so the section has no gap. Malformed client descriptions are refused.
DO $$ DECLARE r jsonb; BEGIN
  r := public.isg_home_feed_v1('[]', '{"contract": 1, "routes": ["nonconformity", "analyses", "trainings", "statistics", "risk_wizard"]}');
  ASSERT pg_temp.ids(r) = ARRAY['continue.nonconformity_draft:70000000-0000-0000-0000-000000000001',
    'performance.analyses_7d', 'performance.trained_people_7d'], pg_temp.ids(r)::text;
  ASSERT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'more') x
    WHERE x#>>'{target,route}' NOT IN ('nonconformity', 'analyses', 'trainings', 'statistics', 'risk_wizard')), r->>'more';
  r := public.isg_home_feed_v1('[]', '{"contract": 7}');
  ASSERT (pg_temp.ids(r))[1] = 'critical.expired', 'a newer contract still receives contract 1 cards';
  BEGIN PERFORM public.isg_home_feed_v1('[]', '{"contract": 0}'); RAISE EXCEPTION 'contract 0 accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  BEGIN PERFORM public.isg_home_feed_v1('[]', '{"routes": ["Bad Route"]}'); RAISE EXCEPTION 'bad route accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  BEGIN PERFORM public.isg_home_feed_v1('[]', '[]'); RAISE EXCEPTION 'array client accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
END $$;

-- 6. A read-only session gets no card that creates or finishes a record.
DO $$ DECLARE r jsonb; BEGIN
  PERFORM set_config('test.read_only', 'true', true);
  r := public.isg_home_feed_v1();
  ASSERT NOT (r#>>'{signals,can_write}')::boolean;
  ASSERT pg_temp.ids(r) = ARRAY['critical.expired', 'critical.soon', 'performance.analyses_7d'], pg_temp.ids(r)::text;
  ASSERT NOT EXISTS (SELECT 1 FROM (SELECT x FROM jsonb_array_elements(r->'cards') x UNION ALL SELECT x FROM jsonb_array_elements(r->'more') x) y
    WHERE y.x->>'kind' = 'continue' OR y.x#>>'{target,route}' IN ('photo_analysis', 'nonconformity_create', 'training_create', 'equipment', 'checklists', 'company_create', 'personnel')),
    'write targets offered to a read-only session';
  ASSERT pg_temp.card(r, 'discover.risk_wizard') IS NOT NULL, 'the on-device wizard needs no write access';
  PERFORM set_config('test.read_only', 'false', true);
END $$;

-- 7. A new personal account: first steps, one suggestion, and a company draft
-- that replaces "add your first company".
SET test.actor = '20000000-0000-0000-0000-000000000003';
DO $$ DECLARE r jsonb; BEGIN
  r := public.isg_home_feed_v1('[]');
  ASSERT r->>'segment' = 'new' AND (r#>>'{signals,account_days}')::int = 1, r::text;
  ASSERT pg_temp.ids(r) = ARRAY['motivation.first_company', 'motivation.first_analysis', 'discover.risk_wizard'], pg_temp.ids(r)::text;
  ASSERT pg_temp.card(r, 'performance.analyses_7d') IS NULL AND pg_temp.card(r, 'discover.photo_analysis') IS NULL;
  r := public.isg_home_feed_v1(jsonb_build_array(
    jsonb_build_object('kind', 'company_create', 'ref', 'c9b5b0d4-6d7e-4b53-9d9e-2f64e1a3b001', 'updated_at', now() - interval '1 hour'),
    jsonb_build_object('kind', 'company_create', 'ref', 'c9b5b0d4-6d7e-4b53-9d9e-2f64e1a3b001', 'updated_at', now() - interval '1 hour'),
    jsonb_build_object('kind', 'unknown', 'ref', 'x', 'updated_at', now()),
    jsonb_build_object('kind', 'risk_wizard', 'ref', 'bad ref!', 'updated_at', now()),
    jsonb_build_object('kind', 'risk_wizard', 'ref', 'old', 'updated_at', now() - interval '40 days'),
    jsonb_build_object('kind', 'risk_wizard', 'ref', 'foreign', 'company_id', '10000000-0000-0000-0000-000000000009', 'updated_at', now()),
    jsonb_build_object('kind', 'risk_wizard', 'ref', 'bad-date', 'updated_at', '2026-13-45T99:99:00Z'),
    jsonb_build_object('kind', 'emergency_wizard', 'ref', 'future', 'updated_at', now() + interval '3 days'),
    '"not an object"'::jsonb));
  ASSERT pg_temp.ids(r) = ARRAY['continue.emergency_wizard:future', 'continue.company_create:c9b5b0d4-6d7e-4b53-9d9e-2f64e1a3b001',
    'motivation.first_analysis'], pg_temp.ids(r)::text;
  ASSERT (r->'cards'->0)#>>'{target,route}' = 'emergency_wizard' AND (r->'cards'->0)#>>'{target,ref}' = 'future'
     AND ((r->'cards'->0)#>>'{params,updated_at}')::timestamptz <= clock_timestamp(), 'future edits are clamped';
  ASSERT (r->'cards'->1)#>>'{target,route}' = 'company_create';
  ASSERT pg_temp.card(r, 'motivation.first_company') IS NULL, 'the draft replaces the first-company card';
  BEGIN PERFORM public.isg_home_feed_v1('{}'); RAISE EXCEPTION 'object accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  BEGIN PERFORM public.isg_home_feed_v1((SELECT jsonb_agg(jsonb_build_object('kind', 'risk_wizard', 'ref', 'r' || i, 'updated_at', now()))
    FROM generate_series(1, 21) i)); RAISE EXCEPTION 'too many accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
END $$;

-- 8. One suggestion a day. The server remembers only what the client reports
-- as shown; today's pick stays, tomorrow the next one comes. Using or opening
-- a feature retires its suggestion account-wide.
DO $$ DECLARE r jsonb; BEGIN
  r := public.isg_home_feed_v1('[]');
  ASSERT NOT EXISTS (SELECT 1 FROM private_isg.home_card_states WHERE owner_id = '20000000-0000-0000-0000-000000000003'
                      AND card_id = 'discover.risk_wizard'), 'reading the feed records nothing';
  PERFORM public.isg_home_card_action_v1('shown', ARRAY['motivation.first_company', 'motivation.first_analysis', 'discover.risk_wizard', 'critical.expired'], gen_random_uuid(), clock_timestamp());
  ASSERT (SELECT scope_key FROM private_isg.home_card_states WHERE owner_id = '20000000-0000-0000-0000-000000000003'
           AND card_id = 'discover.risk_wizard') = 'account', 'suggestions are account-wide';
  ASSERT NOT EXISTS (SELECT 1 FROM private_isg.home_card_states WHERE owner_id = '20000000-0000-0000-0000-000000000003'
                      AND card_id = 'critical.expired'), 'critical impressions are not kept';
  r := public.isg_home_feed_v1('[]');
  ASSERT (pg_temp.ids(r))[3] = 'discover.risk_wizard', 'stable within the day';
  UPDATE private_isg.home_card_states SET shown_on = current_date - 1
   WHERE owner_id = '20000000-0000-0000-0000-000000000003' AND card_id = 'discover.risk_wizard';
  r := public.isg_home_feed_v1('[]');
  ASSERT (pg_temp.ids(r))[3] = 'discover.emergency_wizard', pg_temp.ids(r)::text;
  PERFORM public.isg_home_card_action_v1('shown', ARRAY['discover.emergency_wizard'], gen_random_uuid(), clock_timestamp());
  r := public.isg_home_feed_v1('[]');
  ASSERT (pg_temp.ids(r))[3] = 'discover.emergency_wizard', 'the new pick holds for the day';
  PERFORM public.isg_feature_usage_v1('emergency_wizard', now() - interval '2 hours');
  PERFORM public.isg_feature_usage_v1('emergency_wizard', now() - interval '1 day');
  PERFORM public.isg_feature_usage_v1('emergency_wizard', now() - interval '2 hours');
  ASSERT (SELECT first_used_at = now() - interval '1 day' AND last_used_at = now() - interval '2 hours'
            FROM private_isg.feature_usage WHERE owner_id = '20000000-0000-0000-0000-000000000003' AND feature = 'emergency_wizard'),
    'late and repeated deliveries only widen first/last use';
  r := public.isg_home_feed_v1('[]');
  ASSERT pg_temp.card(r, 'discover.emergency_wizard') IS NULL AND (pg_temp.ids(r))[3] = 'discover.work_permit_forms', pg_temp.ids(r)::text;
  PERFORM public.isg_home_card_action_v1('act', ARRAY['discover.work_permit_forms'], gen_random_uuid(), clock_timestamp());
  r := public.isg_home_feed_v1('[]');
  ASSERT pg_temp.card(r, 'discover.work_permit_forms') IS NULL, 'opened suggestion rests for 30 days';
  BEGIN PERFORM public.isg_feature_usage_v1('anything'); RAISE EXCEPTION 'unknown feature';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
END $$;

-- 9. Working without a company is real use: the group follows the records,
-- and adding a company is only a suggestion further down.
SET test.actor = '20000000-0000-0000-0000-000000000007';
DO $$ DECLARE r jsonb; BEGIN
  r := public.isg_home_feed_v1();
  ASSERT r->>'segment' = 'growing' AND (r#>>'{signals,companies}')::int = 0 AND (r#>>'{signals,analyses,total}')::int = 6, r::text;
  ASSERT (pg_temp.ids(r))[1] = 'performance.analyses_7d', pg_temp.ids(r)::text;
  ASSERT 'motivation.first_company' = ANY(pg_temp.ids(r) || pg_temp.ids(r, 'more')), 'still suggested';
  ASSERT (pg_temp.ids(r))[1] <> 'motivation.first_company';
END $$;

-- 10. An organization expert: only visible companies, only the expert's own
-- work as "mine", the scope's overdue findings first, and state kept apart
-- from the personal scope.
SET test.actor = '20000000-0000-0000-0000-000000000004';
DO $$ DECLARE r jsonb; c jsonb; BEGIN
  r := private_isg.expert_rpc('40000000-0000-0000-0000-000000000001', 'isg_home_feed_v1', '{"p_local": []}')->'payload';
  ASSERT r->>'role' = 'expert' AND r->>'segment' = 'growing' AND (r#>>'{signals,companies}')::int = 1, r::text;
  ASSERT (r#>>'{signals,analyses,total}')::int = 6 AND (r#>>'{signals,analyses,last7}')::int = 2, r#>>'{signals,analyses}';
  ASSERT pg_temp.ids(r) = ARRAY['critical.nonconformity_overdue',
    'continue.nonconformity_draft:70000000-0000-0000-0000-000000000005', 'performance.analyses_7d'], pg_temp.ids(r)::text;
  c := r->'cards'->0;
  ASSERT c#>>'{params,count}' = '1' AND c#>>'{target,route}' = 'nonconformity'
     AND c#>>'{target,id}' = '70000000-0000-0000-0000-000000000003' AND c#>>'{params,company_name}' = 'OSGB Firma', c::text;
  ASSERT position('Görünmeyen' IN r::text) = 0 AND position('E2 taslağı' IN r::text) = 0, 'no other member drafts or hidden companies';
  ASSERT (r->'cards'->2)#>>'{target,mine}' = 'true', 'an organization list opens on the member''s own records';
  r := private_isg.expert_rpc('40000000-0000-0000-0000-000000000001', 'isg_home_feed_v1',
    jsonb_build_object('p_local', jsonb_build_array(jsonb_build_object('kind', 'company_create', 'ref', 'c1', 'updated_at', now()))))->'payload';
  ASSERT pg_temp.card(r, 'continue.company_create:c1') IS NULL, 'experts do not create companies';
  PERFORM private_isg.expert_rpc('40000000-0000-0000-0000-000000000001', 'isg_home_card_action_v1',
    jsonb_build_object('p_action', 'dismiss', 'p_cards', jsonb_build_array('continue.nonconformity_draft:70000000-0000-0000-0000-000000000005'),
      'p_event', gen_random_uuid(), 'p_occurred_at', clock_timestamp()));
  ASSERT (SELECT scope_key FROM private_isg.home_card_states WHERE owner_id = '20000000-0000-0000-0000-000000000004'
           AND card_id = 'continue.nonconformity_draft:70000000-0000-0000-0000-000000000005') = '40000000-0000-0000-0000-000000000001';
  PERFORM set_config('test.read_only', 'true', true);
  r := private_isg.expert_rpc('40000000-0000-0000-0000-000000000001', 'isg_home_feed_v1', '{}')->'payload';
  ASSERT NOT (r#>>'{signals,can_write}')::boolean AND pg_temp.card(r, 'discover.nonconformity') IS NULL, 'a refused write is read-only';
  PERFORM set_config('test.read_only', 'false', true);
END $$;
SET test.actor = '20000000-0000-0000-0000-000000000006';
DO $$ DECLARE r jsonb; BEGIN
  r := private_isg.expert_rpc('40000000-0000-0000-0000-000000000001', 'isg_home_feed_v1', '{}')->'payload';
  ASSERT r->>'role' = 'manager' AND (r#>>'{signals,companies}')::int = 2 AND (r#>>'{signals,analyses,total}')::int = 0, r::text;
  ASSERT (pg_temp.card(r, 'critical.nonconformity_overdue'))#>>'{params,count}' = '2', 'the whole organization';
END $$;

-- 11. The client queue may deliver late or twice. A repeated dismiss does not
-- extend the rest, an old dismiss does not undo a later restore, a late
-- impression keeps its own day, and month-old events are ignored.
SET test.actor = '20000000-0000-0000-0000-000000000001';
DO $$ DECLARE e1 uuid := gen_random_uuid(); e2 uuid := gen_random_uuid(); t1 timestamptz := clock_timestamp() - interval '2 hours';
  first_until timestamptz; r jsonb; a jsonb; BEGIN
  PERFORM public.isg_home_card_action_v1('dismiss', ARRAY['discover.equipment'], e1, t1);
  SELECT dismissed_until INTO first_until FROM private_isg.home_card_states
   WHERE owner_id = '20000000-0000-0000-0000-000000000001' AND card_id = 'discover.equipment';
  ASSERT first_until = t1 + interval '7 days', 'the rest counts from the moment it happened';
  a := public.isg_home_card_action_v1('dismiss', ARRAY['discover.equipment'], e1, t1);
  ASSERT (a->>'applied')::int = 0 AND (SELECT dismissed_until FROM private_isg.home_card_states
           WHERE owner_id = '20000000-0000-0000-0000-000000000001' AND card_id = 'discover.equipment') = first_until,
    'a repeated delivery changes nothing';
  PERFORM public.isg_home_card_action_v1('restore', ARRAY['discover.equipment'], e2, clock_timestamp() - interval '1 hour');
  PERFORM public.isg_home_card_action_v1('dismiss', ARRAY['discover.equipment'], gen_random_uuid(), t1 + interval '1 minute');
  ASSERT (SELECT dismissed_until IS NULL FROM private_isg.home_card_states
           WHERE owner_id = '20000000-0000-0000-0000-000000000001' AND card_id = 'discover.equipment'),
    'a dismiss that happened before the restore does not hide the card again';
  PERFORM public.isg_home_card_action_v1('shown', ARRAY['discover.checklist'], gen_random_uuid(), clock_timestamp());
  PERFORM public.isg_home_card_action_v1('shown', ARRAY['discover.checklist'], gen_random_uuid(), clock_timestamp() - interval '2 days');
  ASSERT (SELECT shown_on FROM private_isg.home_card_states WHERE owner_id = '20000000-0000-0000-0000-000000000001'
           AND card_id = 'discover.checklist') = (clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date, 'the day only moves forward';
  PERFORM public.isg_home_card_action_v1('shown', ARRAY['discover.statistics'], gen_random_uuid(), clock_timestamp() - interval '1 day');
  ASSERT (SELECT shown_on FROM private_isg.home_card_states WHERE owner_id = '20000000-0000-0000-0000-000000000001'
           AND card_id = 'discover.statistics') = ((clock_timestamp() - interval '1 day') AT TIME ZONE 'Europe/Istanbul')::date,
    'a late impression keeps its own day';
  a := public.isg_home_card_action_v1('dismiss', ARRAY['discover.ppe_form'], gen_random_uuid(), clock_timestamp() - interval '31 days');
  ASSERT (a->>'applied')::int = 0 AND NOT EXISTS (SELECT 1 FROM private_isg.home_card_states
           WHERE owner_id = '20000000-0000-0000-0000-000000000001' AND card_id = 'discover.ppe_form'), 'month-old events are ignored';
  a := public.isg_home_card_action_v1('dismiss', ARRAY['discover.ppe_form'], gen_random_uuid(), clock_timestamp() + interval '2 days');
  ASSERT (SELECT dismissed_until <= clock_timestamp() + interval '7 days' FROM private_isg.home_card_states
           WHERE owner_id = '20000000-0000-0000-0000-000000000001' AND card_id = 'discover.ppe_form'), 'a fast device clock is capped';
  BEGIN PERFORM public.isg_home_card_action_v1('dismiss', ARRAY['discover.ppe_form'], NULL, clock_timestamp()); RAISE EXCEPTION 'event id missing';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  DELETE FROM private_isg.home_card_states WHERE owner_id = '20000000-0000-0000-0000-000000000001' AND card_id LIKE 'discover.%';
END $$;

-- 12. A module open only for reading gets no card that creates or finishes a
-- record in it; its critical and progress cards stay.
DO $$ DECLARE r jsonb; BEGIN
  UPDATE private_isg.rollout SET write_enabled = false WHERE feature = 'nonconformity';
  r := public.isg_home_feed_v1();
  ASSERT pg_temp.card(r, 'continue.nonconformity_draft:70000000-0000-0000-0000-000000000001') IS NULL, 'draft offered in a read-only module';
  ASSERT pg_temp.card(r, 'discover.nonconformity') IS NULL;
  ASSERT (pg_temp.ids(r))[1] = 'critical.expired' AND (r#>>'{signals,can_write}')::boolean;
  UPDATE private_isg.rollout SET write_enabled = true WHERE feature = 'nonconformity';
  UPDATE private_isg.module_registry SET write_enabled = false WHERE module = 'equipment';
  r := public.isg_home_feed_v1();
  ASSERT pg_temp.card(r, 'discover.equipment') IS NULL, 'equipment suggested while its module is read-only';
  UPDATE private_isg.module_registry SET write_enabled = true WHERE module = 'equipment';
  r := public.isg_home_feed_v1();
  ASSERT pg_temp.card(r, 'discover.equipment') IS NOT NULL
     AND pg_temp.card(r, 'continue.nonconformity_draft:70000000-0000-0000-0000-000000000001') IS NOT NULL;
END $$;

-- 13. Each card counts exactly the records of the list it opens: the checks
-- list also holds the actor's own runs without a company, the training
-- register lists sessions by the day they were held and hides a session with
-- a company the pilot cannot read, and the nonconformity list rows carry what
-- the "recorded in these days" and "mine" filters need.
SET test.actor = '20000000-0000-0000-0000-000000000001';
DO $$ DECLARE r jsonb; c jsonb; row_ jsonb; BEGIN
  INSERT INTO private_isg.checklist_runs(run_id, company_id, owner_id, workspace_id, state, area_label, updated_at, created_by_user_id) VALUES
    ('90000000-0000-0000-0000-000000000001', NULL, '20000000-0000-0000-0000-000000000001', NULL, 'open', 'Depo turu',
     now() - interval '30 minutes', '20000000-0000-0000-0000-000000000001'),
    ('90000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', NULL, 'open',
     'Kazan dairesi', now() - interval '2 hours', '20000000-0000-0000-0000-000000000001'),
    ('90000000-0000-0000-0000-000000000003', NULL, '20000000-0000-0000-0000-000000000002', NULL, 'open', 'Başkasının turu',
     now(), '20000000-0000-0000-0000-000000000002'),
    ('90000000-0000-0000-0000-000000000004', NULL, '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'open',
     'Kurum turu', now(), '20000000-0000-0000-0000-000000000001');
  INSERT INTO private_isg.pilot_training_sessions(id, owner_id, held_on) VALUES
    ('50000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Europe/Istanbul')::date - 1),
    ('50000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Europe/Istanbul')::date - 1);
  INSERT INTO private_isg.pilot_training_records(id, company_id, owner_id, session_id, state, starts_at) VALUES
    ('60000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
     '50000000-0000-0000-0000-000000000003', 'completed', now() - interval '20 days'),
    ('60000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001',
     '50000000-0000-0000-0000-000000000004', 'completed', now() - interval '1 day');
  INSERT INTO private_isg.pilot_training_participants VALUES
    ('60000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000005', true),
    ('60000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', true),
    ('60000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000005', '30000000-0000-0000-0000-000000000006', true);
  r := public.isg_home_feed_v1();
  ASSERT (r#>>'{signals,checklists,open}')::int = 2, 'own runs with and without a company, nobody else''s: ' || (r#>>'{signals,checklists}');
  c := pg_temp.card(r, 'continue.checklist_open:90000000-0000-0000-0000-000000000001');
  ASSERT c#>>'{target,route}' = 'checklist_run' AND c#>>'{params,title}' = 'Depo turu' AND NOT c->'params' ? 'company_name'
     AND NOT c->'target' ? 'company_id', coalesce(c::text, 'missing');
  ASSERT pg_temp.card(r, 'continue.checklist_open:90000000-0000-0000-0000-000000000004') IS NULL, 'an organization run in a personal session';
  ASSERT (r#>>'{signals,trainings,last7}')::int = 2 AND (r#>>'{signals,trainings,people_last7}')::int = 3,
    'sessions by the day they were held, the unreadable one left out: ' || (r#>>'{signals,trainings}');
  c := pg_temp.card(r, 'performance.trained_people_7d');
  ASSERT c#>>'{params,count}' = '3' AND c#>>'{params,sessions}' = '2', coalesce(c::text, 'missing');
  INSERT INTO private_isg.nonconformities(nonconformity_id, company_id, owner_id, state, record_kind, title, created_at, created_by_user_id) VALUES
    ('70000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
     'open', 'nonconformity', 'Kayıtlı bulgu', now() - interval '3 days', '20000000-0000-0000-0000-000000000001');
  row_ := (SELECT x FROM jsonb_array_elements(private_isg.read_nonconformities('10000000-0000-0000-0000-000000000001', 'list',
            NULL, NULL, NULL, NULL)->'rows') x WHERE x->>'id' = '70000000-0000-0000-0000-000000000009');
  ASSERT (row_->>'created_at')::timestamptz BETWEEN now() - interval '3 days 1 minute' AND now() - interval '3 days' + interval '1 minute'
     AND row_->>'created_by_user_id' = '20000000-0000-0000-0000-000000000001' AND row_->>'state' = 'open', coalesce(row_::text, 'missing');
  DELETE FROM private_isg.nonconformities WHERE nonconformity_id = '70000000-0000-0000-0000-000000000009';
  DELETE FROM private_isg.pilot_training_participants WHERE training_id IN ('60000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-000000000004');
  DELETE FROM private_isg.pilot_training_records WHERE id IN ('60000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-000000000004');
  DELETE FROM private_isg.pilot_training_sessions WHERE id IN ('50000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000004');
  DELETE FROM private_isg.checklist_runs WHERE run_id::text LIKE '90000000-%';
END $$;

-- 14. Gates and grants.
SET test.actor = '20000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  PERFORM set_config('test.expired', 'true', true);
  BEGIN PERFORM public.isg_home_feed_v1(); RAISE EXCEPTION 'expired pilot accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'FEATURE_UNAVAILABLE' THEN RAISE; END IF; END;
  BEGIN PERFORM public.isg_feature_usage_v1('statistics'); RAISE EXCEPTION 'expired pilot accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'FEATURE_UNAVAILABLE' THEN RAISE; END IF; END;
  BEGIN PERFORM public.isg_home_card_action_v1('shown', ARRAY['discover.statistics'], gen_random_uuid(), clock_timestamp()); RAISE EXCEPTION 'expired pilot accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'FEATURE_UNAVAILABLE' THEN RAISE; END IF; END;
  PERFORM set_config('test.expired', 'false', true);
  ASSERT NOT has_function_privilege('anon', 'public.isg_home_feed_v1(jsonb,jsonb)', 'execute');
  ASSERT NOT has_function_privilege('anon', 'public.isg_home_card_action_v1(text,text[],uuid,timestamptz)', 'execute');
  ASSERT NOT has_function_privilege('anon', 'public.isg_feature_usage_v1(text,timestamptz)', 'execute');
  ASSERT has_function_privilege('authenticated', 'public.isg_home_feed_v1(jsonb,jsonb)', 'execute');
  ASSERT NOT has_function_privilege('authenticated', 'private_isg.home_feed(jsonb,jsonb)', 'execute');
  ASSERT NOT has_table_privilege('authenticated', 'private_isg.home_card_states', 'select');
  ASSERT NOT has_table_privilege('authenticated', 'private_isg.feature_usage', 'select');
  ASSERT (SELECT count(*) FROM regexp_matches(pg_get_functiondef('private_isg.expert_rpc(uuid,text,jsonb)'::regprocedure),
    '''isg_home_feed_v1''|''isg_home_card_action_v1''|''isg_feature_usage_v1''', 'g')) = 3, 'allowlist extended once';
END $$;
-- 15. Progress is always there once there is work to show: it cannot be
-- dismissed, an earlier dismissal no longer hides it, and a quiet month shows
-- the whole record to contract-2 clients only.
SET test.actor = '20000000-0000-0000-0000-000000000001';
DO $$ DECLARE r jsonb; c jsonb; BEGIN
  r := public.isg_home_feed_v1();
  c := pg_temp.card(r, 'performance.analyses_7d');
  ASSERT c IS NOT NULL AND NOT (c->>'dismissible')::boolean, coalesce(c::text, 'missing');
  BEGIN PERFORM public.isg_home_card_action_v1('dismiss', ARRAY['performance.analyses_7d'], gen_random_uuid(), clock_timestamp()); RAISE EXCEPTION 'progress dismissed';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'VALIDATION_ERROR' THEN RAISE; END IF; END;
  INSERT INTO private_isg.home_card_states(owner_id, scope_key, card_id, dismissed_until, decided_at, decision_event)
  VALUES ('20000000-0000-0000-0000-000000000001', 'personal', 'performance.analyses_7d', now() + interval '6 days', now(), gen_random_uuid())
  ON CONFLICT (owner_id, scope_key, card_id) DO UPDATE SET dismissed_until = excluded.dismissed_until;
  ASSERT pg_temp.card(public.isg_home_feed_v1(), 'performance.analyses_7d') IS NOT NULL, 'a dismissal from before still hid progress';
  DELETE FROM private_isg.home_card_states WHERE card_id = 'performance.analyses_7d';
  ASSERT pg_temp.card(public.isg_home_feed_v1('[]', '{"contract": 2}'), 'performance.analyses_total') IS NULL, 'recent progress comes first';

  BEGIN
    UPDATE public.analyses SET created_at = created_at - interval '60 days' WHERE user_id = '20000000-0000-0000-0000-000000000001';
    UPDATE private_isg.pilot_training_sessions SET held_on = held_on - 60 WHERE owner_id = '20000000-0000-0000-0000-000000000001';
    UPDATE private_isg.nonconformities SET created_at = created_at - interval '60 days' WHERE company_id = '10000000-0000-0000-0000-000000000001';
    r := public.isg_home_feed_v1();
    ASSERT NOT EXISTS (SELECT 1 FROM (SELECT x FROM jsonb_array_elements(r->'cards') x UNION ALL SELECT x FROM jsonb_array_elements(r->'more') x) y
      WHERE y.x->>'kind' = 'performance'), 'a contract-1 client gets no card it cannot word: ' || pg_temp.ids(r, 'more')::text;
    r := public.isg_home_feed_v1('[]', '{"contract": 2}');
    c := pg_temp.card(r, 'performance.analyses_total');
    ASSERT c#>>'{params,count}' = (r#>>'{signals,analyses,total}') AND c#>>'{target,route}' = 'analyses'
       AND c#>>'{target,status}' = 'completed' AND NOT c#>'{target}' ? 'from' AND NOT c#>'{target}' ? 'to'
       AND c#>>'{target,mine}' = 'false' AND NOT (c->>'dismissible')::boolean AND NOT c ? 'since',
       'the whole record, its list without a date range: ' || coalesce(c::text, 'missing');
    UPDATE public.analyses SET status = 'failed' WHERE user_id = '20000000-0000-0000-0000-000000000001';
    r := public.isg_home_feed_v1('[]', '{"contract": 2}');
    c := pg_temp.card(r, 'performance.trainings_total');
    ASSERT c#>>'{params,count}' = (r#>>'{signals,trainings,total}') AND c#>>'{target,route}' = 'trainings'
       AND pg_temp.card(r, 'performance.analyses_total') IS NULL, 'trainings when there are no analyses: ' || coalesce(c::text, 'missing');
    RAISE EXCEPTION 'UNDO_15';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM <> 'UNDO_15' THEN RAISE; END IF;
  END;
  ASSERT pg_temp.card(public.isg_home_feed_v1(), 'performance.analyses_7d') IS NOT NULL, 'the quiet month was undone';
END $$;
SELECT 'PASS home feed SQL assertions';
