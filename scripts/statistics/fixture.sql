CREATE TABLE public.analyses(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid,company_id uuid,kind text,status text,completed_at timestamptz,created_at timestamptz);
CREATE FUNCTION public.isg_pilot_overview_v1(uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('companies',coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'is_archived',is_archived,'personnel_count',2,'workplace_count',1,'hazard_class',hazard_class)),'[]'))
 FROM public.companies WHERE user_id=private_isg.active_actor() $$;
INSERT INTO public.companies VALUES ('10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001',false,'İkinci Firma','low');
INSERT INTO public.analyses(user_id,company_id,kind,status,completed_at,created_at)
 SELECT '20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','photo','completed',now()-interval '1 hour',now()-interval '1 hour' FROM generate_series(1,251);
INSERT INTO public.analyses(user_id,company_id,kind,status,completed_at,created_at) VALUES
 ('20000000-0000-0000-0000-000000000001',NULL,'photo','completed',now(),now()),
 ('20000000-0000-0000-0000-000000000001',NULL,'text','completed',now(),now()),
 ('20000000-0000-0000-0000-000000000002',NULL,'photo','completed',now(),now()),
 ('20000000-0000-0000-0000-000000000001',NULL,'photo','failed',now(),now()),
 ('20000000-0000-0000-0000-000000000001',NULL,'photo','completed',now()-interval '2 years',now()-interval '2 years'),
 ('20000000-0000-0000-0000-000000000001',NULL,'photo','completed',now()+interval '1 year',now()+interval '1 year');
INSERT INTO private_isg.pilot_training_sessions(id,owner_id,title,trainer,method,held_on)
 VALUES('50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Temel Eğitim','Uzman','face_to_face',current_date);
INSERT INTO private_isg.pilot_training_records(id,company_id,owner_id,title,trainer,starts_at,duration_minutes,state,session_id) VALUES
 ('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Eğitim','Uzman',now(),360,'completed','50000000-0000-0000-0000-000000000001'),
 ('60000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','Eğitim','Uzman',now(),360,'completed','50000000-0000-0000-0000-000000000001'),
 ('60000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Plan','Uzman',now(),360,'planned',NULL);
INSERT INTO private_isg.pilot_training_participants VALUES ('10000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Kişi',true);
