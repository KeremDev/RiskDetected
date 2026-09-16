BEGIN;
SELECT set_config('request.jwt.claims',(SELECT jsonb_build_object('role','authenticated','sub',a.actor_id,'session_id',s.id,'exp',floor(extract(epoch FROM now()+interval '1 hour')))::text
FROM private_isg.p05_pilot_accounts a JOIN auth.sessions s ON s.user_id=a.actor_id WHERE a.revoked_at IS NULL AND a.expires_at>now() AND (s.not_after IS NULL OR s.not_after>now()) ORDER BY s.created_at DESC LIMIT 1),true);
UPDATE private_isg.education_controls SET enabled=true;
SET LOCAL ROLE authenticated;
DO $test$ DECLARE ctx jsonb; wp jsonb; employee jsonb; payload jsonb:=$payload${"action":"save","expected_version":0,"title":"Temel İSG Eğitimi","provider_name":"Test Uzman","notes":"","trainers":[{"id":"expert","name":"Test Eğitici","title":"İş Güvenliği Uzmanı"}],"scopes":[{"id":"50000000-0000-0000-0000-000000000001","company_id":"10000000-0000-0000-0000-000000000001","workplace_id":"40000000-0000-0000-0000-000000000001","group_name":"Atölye","cycle":"initial","context_note":"Bu atölyenin pres, forklift ve tahliye riskleri","legal_name":"Test Firma","employer_name":"Test İşveren","employer_capacity":"employer","location":"Atölye","topics":[{"code":"G1-A","group":"G1","title":"Çalışma mevzuatı ile ilgili bilgiler","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G1-B","group":"G1","title":"Çalışanların yasal hak ve sorumlulukları","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G1-C","group":"G1","title":"İşyeri temizliği ve düzeni","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G1-D","group":"G1","title":"İş kazası ve meslek hastalığından doğan hukuki sonuçlar","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G2-A","group":"G2","title":"Meslek hastalıklarının sebepleri","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G2-B","group":"G2","title":"Hastalıktan korunma prensipleri ve korunma tekniklerinin uygulanması","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G2-C","group":"G2","title":"Biyolojik ve psikososyal risk etmenleri","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G2-D","group":"G2","title":"İlkyardım","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G2-E","group":"G2","title":"Bağımlılık yapıcı maddelerin zararları ve teknoloji bağımlılığı","instruction_minutes":10,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-A","group":"G3","title":"Kimyasal, fiziksel ve ergonomik risk etmenleri","instruction_minutes":40,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-B","group":"G3","title":"Elle kaldırma ve taşıma","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-C","group":"G3","title":"Parlama ve patlama","instruction_minutes":30,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-D","group":"G3","title":"Yangın ve yangından korunma","instruction_minutes":40,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-E","group":"G3","title":"İş ekipmanlarının güvenli kullanımı","instruction_minutes":40,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-F","group":"G3","title":"Ekranlı araçlarla çalışma","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-G","group":"G3","title":"Elektrik, tehlikeleri, riskleri ve önlemleri","instruction_minutes":30,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-H","group":"G3","title":"İş kazalarının sebepleri ve korunma prensipleri ile tekniklerinin uygulanması","instruction_minutes":30,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-I","group":"G3","title":"Sağlık ve güvenlik işaretleri","instruction_minutes":30,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-J","group":"G3","title":"Kişisel koruyucu donanım kullanımı","instruction_minutes":40,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-K","group":"G3","title":"İş sağlığı ve güvenliği genel kuralları ve güvenlik kültürü","instruction_minutes":20,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G3-L","group":"G3","title":"Acil durumlar, tahliye ve kurtarma","instruction_minutes":30,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G4-S1","group":"G4","title":"İşyerinin risk değerlendirmesinde belirlenen öncelikli riskler ve alınacak önlemler","instruction_minutes":50,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G4-S2","group":"G4","title":"İşyerinin acil durum planı, tahliye yolları ve toplanma alanları","instruction_minutes":50,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G4-S3","group":"G4","title":"Göreve, departmana ve kullanılan ekipmana özgü güvenli çalışma uygulamaları","instruction_minutes":40,"method":"face_to_face","trainer_ids":["expert"]},{"code":"G4-S4","group":"G4","title":"Faaliyete özgü talimatlar ve sahadaki uygulama örnekleri","instruction_minutes":40,"method":"face_to_face","trainer_ids":["expert"]}],"lessons":[],"participants":[{"id":"30000000-0000-0000-0000-000000000001","job_title":"Bakım teknisyeni"}]}]}$payload$; scope jsonb; p jsonb; topics jsonb:='[]'; topic jsonb; lessons jsonb:='[]'; allocations jsonb; remaining int; left_minutes int; topic_index int:=0; amount int; n int; start_time timestamptz; r jsonb; cert jsonb; request jsonb; old_record text;
BEGIN
 ctx:=public.isg_pilot_training_detail_v3();
 FOR wp IN SELECT value FROM jsonb_array_elements(ctx->'workplaces') LOOP
  employee:=public.isg_personnel_read_v1((wp->>'company_id')::uuid,'employees','',false,null,null)->'rows'->0;
  EXIT WHEN employee IS NOT NULL;
 END LOOP;
 IF employee IS NULL THEN RAISE EXCEPTION 'NO_PILOT_EMPLOYEE_FOR_ROLLBACK_PROBE'; END IF;
 SELECT value INTO p FROM jsonb_array_elements(ctx->'package'->'presets') WHERE value->>'cycle'='initial' AND value->>'hazard_class'=CASE wp->>'hazard_class' WHEN 'high' THEN 'very_hazardous' WHEN 'medium' THEN 'hazardous' ELSE wp->>'hazard_class' END;
 FOR topic IN SELECT value FROM jsonb_array_elements(ctx->'package'->'topics') LOOP
  topics:=topics||jsonb_build_array(jsonb_build_object('code',topic->>'code','group',topic->>'group_code','title',topic->>'legal_label','instruction_minutes',p->'topic_instruction_minutes'->(topic->>'code'),'method','face_to_face','trainer_ids','["expert"]'::jsonb));
 END LOOP;
 FOR topic IN SELECT value FROM jsonb_array_elements(p->'group4'->'topics') LOOP
  topics:=topics||jsonb_build_array(jsonb_build_object('code',topic->>'local_key','group','G4','title',topic->>'title','instruction_minutes',topic->'instruction_minutes','method','face_to_face','trainer_ids','["expert"]'::jsonb));
 END LOOP;
 left_minutes:=(topics->0->>'instruction_minutes')::int;
 start_time:=((now() AT TIME ZONE 'Europe/Istanbul')::date-2+time '09:00') AT TIME ZONE 'Europe/Istanbul';
 FOR n IN 0..(p->>'minimum_lesson_units')::int-1 LOOP
  remaining:=45; allocations:='[]';
  WHILE remaining>0 LOOP
   amount:=least(remaining,left_minutes);
   allocations:=allocations||jsonb_build_array(jsonb_build_object('topic_code',topics->topic_index->>'code','minutes',amount));
   remaining:=remaining-amount;left_minutes:=left_minutes-amount;
   IF left_minutes=0 THEN topic_index:=topic_index+1;left_minutes:=(topics->topic_index->>'instruction_minutes')::int; END IF;
  END LOOP;
  lessons:=lessons||jsonb_build_array(jsonb_build_object('id','lesson-'||n::text,'starts_at',start_time+make_interval(mins=>n*60),'instruction_minutes',45,'break_minutes',15,'allocations',allocations));
 END LOOP;
 scope:=payload->'scopes'->0||jsonb_build_object('id',gen_random_uuid(),'company_id',wp->>'company_id','workplace_id',wp->>'id','topics',topics,'lessons',lessons,'participants',jsonb_build_array(jsonb_build_object('id',employee->>'id','job_title','EDU rollback test')));
 payload:=payload||jsonb_build_object('scopes',jsonb_build_array(scope),'title','EDU rollback acceptance — not retained');
 r:=public.isg_pilot_training_record_v3(gen_random_uuid(),payload);
 IF r->'row'->'education'->'scopes'->0->'issues'<>'[]'::jsonb THEN RAISE EXCEPTION 'CERTIFICATE_SCOPE_ISSUES: %',r->'row'->'education'->'scopes'->0->'issues'; END IF;
 old_record:=r->'row'->'companies'->0->>'id';
 request:=jsonb_build_object('action','issue','mutation_id',gen_random_uuid(),'session_id',r->'row'->>'id','expected_version',r->'row'->'version','scope_id',scope->>'id','person_id',employee->>'id');
 cert:=public.isg_pilot_training_certificate_v1(request);
 IF (cert->>'ready')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'CERTIFICATE_NOT_READY'; END IF;
 IF public.isg_pilot_training_certificate_v1(request)<>cert THEN RAISE EXCEPTION 'REPLAY_MISMATCH'; END IF;
 payload:=payload||jsonb_build_object('id',r->'row'->>'id','expected_version',r->'row'->'version','notes','stable id check');
 r:=public.isg_pilot_training_record_v3(gen_random_uuid(),payload);
 IF r->'row'->'companies'->0->>'id' IS DISTINCT FROM old_record THEN RAISE EXCEPTION 'UNSTABLE_COMPANY_RECORD'; END IF;
 IF public.isg_pilot_training_certificate_v1(jsonb_build_object('action','read','document_id',cert->>'document_id','revision',1))->'snapshot' IS DISTINCT FROM cert->'snapshot' THEN RAISE EXCEPTION 'MUTATED_CERTIFICATE'; END IF;
END $test$;
RESET ROLE;
ROLLBACK;
SELECT 'EDU authenticated role save / issue / replay / edit / old revision PASS — all writes rolled back' AS result;
