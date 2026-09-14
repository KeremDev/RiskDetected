-- EDU v3: additive pilot integration; no attendance, assessment, signed files or rollout activation.
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='60s';

CREATE TABLE IF NOT EXISTS private_isg.training_catalogs (
  catalog_code text PRIMARY KEY CHECK(catalog_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  namespace text NOT NULL CHECK(namespace IN ('official','special')),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private_isg.training_catalogs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.training_catalogs FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.training_catalog_versions (
  catalog_code text NOT NULL REFERENCES private_isg.training_catalogs(catalog_code) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  source_id uuid,
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','superseded')),
  -- The V5 figures are fixtures until the official text is reviewed, so a
  -- version says out loud whether its content was ever approved.
  content_approved boolean NOT NULL DEFAULT false,
  approved_by uuid REFERENCES public.profiles(id), approval_note text, published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(catalog_code,version),
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))
);
ALTER TABLE private_isg.training_catalog_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.training_catalog_versions FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.company_curriculum_versions (
  curriculum_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  catalog_code text NOT NULL, catalog_version integer NOT NULL,
  version integer NOT NULL CHECK(version>=1),
  hazard_class text NOT NULL CHECK(hazard_class IN ('low','medium','high')),
  g4_topics jsonb NOT NULL, g4_lessons integer NOT NULL CHECK(g4_lessons BETWEEN 0 AND 200),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','active','superseded')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,workplace_id,catalog_code,version),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(catalog_code,catalog_version) REFERENCES private_isg.training_catalog_versions(catalog_code,version)
);
ALTER TABLE private_isg.company_curriculum_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.company_curriculum_versions FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.document_templates (
  template_code text PRIMARY KEY CHECK(template_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  source_domain text NOT NULL CHECK(source_domain IN ('training','risk','nonconformity','module','personnel')),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private_isg.document_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.document_templates FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.document_template_versions (
  template_code text NOT NULL REFERENCES private_isg.document_templates(template_code) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','superseded')),
  approved_by uuid REFERENCES public.profiles(id), approval_note text, published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(template_code,version),
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))
);
ALTER TABLE private_isg.document_template_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.document_template_versions FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.documents (
  document_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid,
  source_domain text NOT NULL CHECK(source_domain IN ('training','risk','nonconformity','module','personnel')),
  source_ref text NOT NULL CHECK(btrim(source_ref)<>'' AND length(source_ref)<=200),
  template_code text NOT NULL REFERENCES private_isg.document_templates(template_code),
  current_version integer NOT NULL DEFAULT 0 CHECK(current_version BETWEEN 0 AND 10000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,source_domain,source_ref,template_code),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
ALTER TABLE private_isg.documents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.documents FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.document_number_sequences (
  company_id uuid NOT NULL, scope text NOT NULL CHECK(scope ~ '^[a-z][a-z0-9_]{1,19}$'),
  year integer NOT NULL CHECK(year BETWEEN 2000 AND 2100),
  next_value bigint NOT NULL DEFAULT 1 CHECK(next_value>=1),
  PRIMARY KEY(company_id,scope,year)
);
ALTER TABLE private_isg.document_number_sequences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.document_number_sequences FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE IF NOT EXISTS private_isg.document_versions (
  document_id uuid NOT NULL REFERENCES private_isg.documents(document_id) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 10000),
  template_version integer NOT NULL,
  document_no text NOT NULL CHECK(document_no ~ '^[A-Z0-9_]{2,20}-[0-9]{4}-[0-9]{1,9}$'),
  source_kind text NOT NULL CHECK(source_kind IN ('structured','scanned')),
  snapshot jsonb NOT NULL, snapshot_sha256 bytea NOT NULL CHECK(octet_length(snapshot_sha256)=32),
  finalized_by uuid NOT NULL REFERENCES public.profiles(id), finalized_at timestamptz NOT NULL,
  mutation_id uuid NOT NULL,
  PRIMARY KEY(document_id,version),
  UNIQUE(document_id,mutation_id)
);
ALTER TABLE private_isg.document_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.document_versions FROM PUBLIC,anon,authenticated,service_role;


CREATE UNIQUE INDEX IF NOT EXISTS document_no_idx ON private_isg.document_versions(document_no);
ALTER TABLE private_isg.training_catalog_versions ADD COLUMN IF NOT EXISTS content_package jsonb;
ALTER TABLE private_isg.training_catalog_versions ADD COLUMN IF NOT EXISTS content_checksum text;
ALTER TABLE private_isg.company_curriculum_versions ADD COLUMN IF NOT EXISTS education jsonb;
ALTER TABLE private_isg.company_curriculum_versions ADD COLUMN IF NOT EXISTS scope_key text NOT NULL DEFAULT 'legacy';
DROP INDEX IF EXISTS private_isg.curriculum_single_active_idx;
CREATE UNIQUE INDEX curriculum_single_active_idx ON private_isg.company_curriculum_versions(company_id,workplace_id,catalog_code,scope_key) WHERE state='active';
ALTER TABLE private_isg.pilot_training_sessions ADD COLUMN education jsonb;
ALTER TABLE private_isg.pilot_training_records DROP CONSTRAINT pilot_training_records_duration_minutes_check;
ALTER TABLE private_isg.pilot_training_records ADD CONSTRAINT pilot_training_records_duration_minutes_check CHECK(duration_minutes BETWEEN 1 AND 100000);
CREATE TABLE private_isg.education_controls(key text PRIMARY KEY,enabled boolean NOT NULL DEFAULT false);
INSERT INTO private_isg.education_controls VALUES('catalog_v1',false),('certificate_v1',false);
CREATE TABLE private_isg.education_document_counters(scope text NOT NULL,year integer NOT NULL,next_value bigint NOT NULL DEFAULT 1,PRIMARY KEY(scope,year));
CREATE TABLE private_isg.education_receipts(owner_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,mutation_id uuid,request_hash bytea NOT NULL,response jsonb NOT NULL,PRIMARY KEY(owner_id,mutation_id));
ALTER TABLE private_isg.education_controls ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.education_document_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.education_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.education_controls,private_isg.education_document_counters,private_isg.education_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.education_install_package(p_package jsonb) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE fingerprint text:=encode(sha256(convert_to(p_package::text,'UTF8')),'hex'); existing text; profile jsonb; topic_total integer; g4_total integer;
BEGIN
 IF p_package->>'package_key'<>'tr_isg_basic_2026_education_v1' OR (p_package->>'content_version')::integer<>1
   OR jsonb_array_length(p_package->'topics')<>21 OR jsonb_array_length(p_package->'presets')<>6 THEN RAISE EXCEPTION 'CONTENT_INVALID'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('education-catalog-install',0));
 IF (SELECT count(DISTINCT value->>'code') FROM jsonb_array_elements(p_package->'topics'))<>21
 OR (SELECT count(*) FROM jsonb_array_elements(p_package->'topics') WHERE value->>'group_code'='G1')<>4
 OR (SELECT count(*) FROM jsonb_array_elements(p_package->'topics') WHERE value->>'group_code'='G2')<>5
 OR (SELECT count(*) FROM jsonb_array_elements(p_package->'topics') WHERE value->>'group_code'='G3')<>12
 OR (SELECT count(DISTINCT (value->>'cycle')||':'||(value->>'hazard_class')) FROM jsonb_array_elements(p_package->'presets'))<>6 THEN RAISE EXCEPTION 'CONTENT_INVALID'; END IF;
 FOR profile IN SELECT value FROM jsonb_array_elements(p_package->'presets') LOOP
  SELECT sum(value::integer) INTO topic_total FROM jsonb_each_text(profile->'topic_instruction_minutes');
  SELECT sum((value->>'instruction_minutes')::integer) INTO g4_total FROM jsonb_array_elements(profile->'group4'->'topics');
  IF topic_total+g4_total IS DISTINCT FROM (profile->>'default_instruction_minutes')::int
   OR g4_total IS DISTINCT FROM (profile->'group4'->>'budget_instruction_minutes')::int
   OR (profile->>'default_instruction_minutes')::int+(profile->>'default_break_minutes')::int IS DISTINCT FROM (profile->>'default_scheduled_minutes')::int
   OR (profile->>'default_break_minutes')::int IS DISTINCT FROM (profile->>'minimum_lesson_units')::int*15 THEN RAISE EXCEPTION 'CONTENT_INVALID'; END IF;
 END LOOP;
 INSERT INTO private_isg.training_catalogs(catalog_code,namespace,title) VALUES('tr_isg_basic_2026','official','Temel İSG Eğitimi') ON CONFLICT DO NOTHING;
 SELECT content_checksum INTO existing FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1 FOR UPDATE;
 IF FOUND THEN
  IF existing IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION 'CONTENT_VERSION_CONFLICT'; END IF;
  RETURN;
 END IF;
 INSERT INTO private_isg.training_catalog_versions(catalog_code,version,status,content_package,content_checksum)
 VALUES('tr_isg_basic_2026',1,'draft',p_package,fingerprint);
END $$;

SELECT private_isg.education_install_package($education${"schema_version":"training-content-package-v1","package_key":"tr_isg_basic_2026_education_v1","content_version":1,"status":"review_required","locale":"tr-TR","jurisdiction":"TR","source":{"id":"G1","title":"Çalışanların İş Sağlığı ve Güvenliği Eğitimleri Uygulama Rehberi","edition":"Nisan 2026","sha256":"7cdb9ffcbeff806b81e2682cb38d67171ed0170712eaef25370ea49a409aba2e","topic_pdf_page":17,"certificate_pdf_page":18,"example_pdf_pages":[19,20,21]},"training_type_code":"TR-ISG-BASIC-2026","training_cycles":["initial","periodic_repeat"],"lesson_policy":{"minimum_instruction_minutes":45,"break_minutes":15,"topic_minutes_exclude_breaks":true,"round_up_credits":false,"exam_minutes_count_as_instruction":false},"assessment_policy":{"minimum_score":60,"score_scale":100,"maximum_attempts_per_course":3,"source":"G1 PDF 13 / basılı 9"},"first_training_due":{"unit":"calendar_month","value":3,"anchor":"employment_start_date","source":"G1 PDF 9 / basılı 5"},"groups":[{"code":"G1","order":1,"legal_label":"Genel konular","source":"Ek-1 / 1"},{"code":"G2","order":2,"legal_label":"Sağlık konuları","source":"Ek-1 / 2"},{"code":"G3","order":3,"legal_label":"Teknik konular","source":"Ek-1 / 3"},{"code":"G4","order":4,"ui_label":"İşyerine Özgü Riskler","source":"Ek-1 / 4","custom_topics_required":true,"legal_label_by_hazard":{"low":"Faaliyetin Genel Tehlike ve Riskleri","hazardous":"İşe ve işyerine özgü riskler ve risk değerlendirmesine dayalı konular","very_hazardous":"İşe ve işyerine özgü riskler ve risk değerlendirmesine dayalı konular"},"branch_by_hazard":{"low":"4-b","hazardous":"4-a","very_hazardous":"4-a"},"source_label_variants":[{"location":"Ek-2 / G4 düşük sınıf etiketi","label":"Faaliyetin Genel Riskleri"},{"location":"Ek-2 / G4 birleşik üst başlık","label":"İşe ve işyerine özgü riskler ve risk değerlendirmesine dayalı konular (Tehlikeli ve Çok Tehlikeli Sınıf)/ Faaliyetin Genel Riskleri (Az Tehlikeli Sınıf)"}]}],"topics":[{"code":"G1-A","group_code":"G1","sort_order":1,"legal_item":"a","legal_label":"Çalışma mevzuatı ile ilgili bilgiler","source_ref":"Ek-1 / 1-a","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G1-B","group_code":"G1","sort_order":2,"legal_item":"b","legal_label":"Çalışanların yasal hak ve sorumlulukları","source_ref":"Ek-1 / 1-b","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G1-C","group_code":"G1","sort_order":3,"legal_item":"c","legal_label":"İşyeri temizliği ve düzeni","source_ref":"Ek-1 / 1-c","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G1-D","group_code":"G1","sort_order":4,"legal_item":"ç","legal_label":"İş kazası ve meslek hastalığından doğan hukuki sonuçlar","source_ref":"Ek-1 / 1-ç","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G2-A","group_code":"G2","sort_order":5,"legal_item":"a","legal_label":"Meslek hastalıklarının sebepleri","source_ref":"Ek-1 / 2-a","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G2-B","group_code":"G2","sort_order":6,"legal_item":"b","legal_label":"Hastalıktan korunma prensipleri ve korunma tekniklerinin uygulanması","source_ref":"Ek-1 / 2-b","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G2-C","group_code":"G2","sort_order":7,"legal_item":"c","legal_label":"Biyolojik ve psikososyal risk etmenleri","source_ref":"Ek-1 / 2-c","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G2-D","group_code":"G2","sort_order":8,"legal_item":"ç","legal_label":"İlkyardım","source_ref":"Ek-1 / 2-ç","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G2-E","group_code":"G2","sort_order":9,"legal_item":"d","legal_label":"Bağımlılık yapıcı maddelerin zararları ve teknoloji bağımlılığı","source_ref":"Ek-1 / 2-d","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-A","group_code":"G3","sort_order":10,"legal_item":"a","legal_label":"Kimyasal, fiziksel ve ergonomik risk etmenleri","source_ref":"Ek-1 / 3-a","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-B","group_code":"G3","sort_order":11,"legal_item":"b","legal_label":"Elle kaldırma ve taşıma","source_ref":"Ek-1 / 3-b","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-C","group_code":"G3","sort_order":12,"legal_item":"c","legal_label":"Parlama ve patlama","source_ref":"Ek-1 / 3-c","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null,"source_label_variants":[{"location":"Ek-2 / 3-c","label":"Parlama, patlama"}]},{"code":"G3-D","group_code":"G3","sort_order":13,"legal_item":"ç","legal_label":"Yangın ve yangından korunma","source_ref":"Ek-1 / 3-ç","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-E","group_code":"G3","sort_order":14,"legal_item":"d","legal_label":"İş ekipmanlarının güvenli kullanımı","source_ref":"Ek-1 / 3-d","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-F","group_code":"G3","sort_order":15,"legal_item":"e","legal_label":"Ekranlı araçlarla çalışma","source_ref":"Ek-1 / 3-e","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-G","group_code":"G3","sort_order":16,"legal_item":"f","legal_label":"Elektrik, tehlikeleri, riskleri ve önlemleri","source_ref":"Ek-1 / 3-f","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-H","group_code":"G3","sort_order":17,"legal_item":"g","legal_label":"İş kazalarının sebepleri ve korunma prensipleri ile tekniklerinin uygulanması","source_ref":"Ek-1 / 3-g","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-I","group_code":"G3","sort_order":18,"legal_item":"ğ","legal_label":"Sağlık ve güvenlik işaretleri","source_ref":"Ek-1 / 3-ğ","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-J","group_code":"G3","sort_order":19,"legal_item":"h","legal_label":"Kişisel koruyucu donanım kullanımı","source_ref":"Ek-1 / 3-h","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-K","group_code":"G3","sort_order":20,"legal_item":"ı","legal_label":"İş sağlığı ve güvenliği genel kuralları ve güvenlik kültürü","source_ref":"Ek-1 / 3-ı","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null},{"code":"G3-L","group_code":"G3","sort_order":21,"legal_item":"i","legal_label":"Acil durumlar, tahliye ve kurtarma","source_ref":"Ek-1 / 3-i","required":true,"default_duration_origin":"preset","minimum_legal_topic_minutes":null}],"presets":[{"code":"initial_low","label":"İlk Temel Eğitim — Az Tehlikeli","cycle":"initial","hazard_class":"low","minimum_lesson_units":8,"minimum_group4_lesson_units":2,"renewal_interval_months":36,"default_instruction_minutes":360,"default_break_minutes":120,"default_scheduled_minutes":480,"default_minutes_by_group":{"G1":80,"G2":80,"G3":110,"G4":90},"minutes_origin":"guide_example_first_training","source_example_page":19,"default_delivery":"face_to_face","allowed_delivery_groups_1_to_3":["face_to_face","external_distance","hybrid"],"allowed_delivery_group4":["face_to_face","external_distance","hybrid"],"topic_instruction_minutes":{"G1-A":20,"G1-B":20,"G1-C":20,"G1-D":20,"G2-A":20,"G2-B":20,"G2-C":20,"G2-D":10,"G2-E":10,"G3-A":10,"G3-B":10,"G3-C":10,"G3-D":10,"G3-E":10,"G3-F":10,"G3-G":10,"G3-H":10,"G3-I":10,"G3-J":5,"G3-K":5,"G3-L":10},"group4":{"budget_instruction_minutes":90,"origin":"product_contextualization_starter_not_legal_list","requires_company_customization":true,"topics":[{"local_key":"G4-S1","title":"İşyerinin risk değerlendirmesinde belirlenen öncelikli riskler ve alınacak önlemler","instruction_minutes":25,"requires_context":true},{"local_key":"G4-S2","title":"İşyerinin acil durum planı, tahliye yolları ve toplanma alanları","instruction_minutes":25,"requires_context":true},{"local_key":"G4-S3","title":"Göreve, departmana ve kullanılan ekipmana özgü güvenli çalışma uygulamaları","instruction_minutes":20,"requires_context":true},{"local_key":"G4-S4","title":"Faaliyete özgü talimatlar ve sahadaki uygulama örnekleri","instruction_minutes":20,"requires_context":true}]},"ready_for_completion_without_review":false,"common_groups_review_guard":{"reference_instruction_minutes":270,"when_below":"requires_content_rule_review","source":"W1 SSS 135; separate supplementary check","do_not_silently_reduce_when_increasing_g4":true}},{"code":"initial_hazardous","label":"İlk Temel Eğitim — Tehlikeli","cycle":"initial","hazard_class":"hazardous","minimum_lesson_units":12,"minimum_group4_lesson_units":3,"renewal_interval_months":24,"default_instruction_minutes":540,"default_break_minutes":180,"default_scheduled_minutes":720,"default_minutes_by_group":{"G1":80,"G2":90,"G3":235,"G4":135},"minutes_origin":"guide_example_first_training","source_example_page":20,"default_delivery":"face_to_face","allowed_delivery_groups_1_to_3":["face_to_face","external_distance","hybrid"],"allowed_delivery_group4":["face_to_face"],"topic_instruction_minutes":{"G1-A":20,"G1-B":20,"G1-C":20,"G1-D":20,"G2-A":20,"G2-B":20,"G2-C":20,"G2-D":20,"G2-E":10,"G3-A":25,"G3-B":20,"G3-C":20,"G3-D":30,"G3-E":30,"G3-F":10,"G3-G":20,"G3-H":10,"G3-I":10,"G3-J":40,"G3-K":10,"G3-L":10},"group4":{"budget_instruction_minutes":135,"origin":"product_contextualization_starter_not_legal_list","requires_company_customization":true,"topics":[{"local_key":"G4-S1","title":"İşyerinin risk değerlendirmesinde belirlenen öncelikli riskler ve alınacak önlemler","instruction_minutes":40,"requires_context":true},{"local_key":"G4-S2","title":"İşyerinin acil durum planı, tahliye yolları ve toplanma alanları","instruction_minutes":35,"requires_context":true},{"local_key":"G4-S3","title":"Göreve, departmana ve kullanılan ekipmana özgü güvenli çalışma uygulamaları","instruction_minutes":30,"requires_context":true},{"local_key":"G4-S4","title":"Faaliyete özgü talimatlar ve sahadaki uygulama örnekleri","instruction_minutes":30,"requires_context":true}]},"ready_for_completion_without_review":false,"common_groups_review_guard":{"reference_instruction_minutes":405,"when_below":"requires_content_rule_review","source":"W1 SSS 135; separate supplementary check","do_not_silently_reduce_when_increasing_g4":true}},{"code":"initial_very_hazardous","label":"İlk Temel Eğitim — Çok Tehlikeli","cycle":"initial","hazard_class":"very_hazardous","minimum_lesson_units":16,"minimum_group4_lesson_units":4,"renewal_interval_months":12,"default_instruction_minutes":720,"default_break_minutes":240,"default_scheduled_minutes":960,"default_minutes_by_group":{"G1":80,"G2":90,"G3":370,"G4":180},"minutes_origin":"guide_example_first_training","source_example_page":21,"default_delivery":"face_to_face","allowed_delivery_groups_1_to_3":["face_to_face","external_distance","hybrid"],"allowed_delivery_group4":["face_to_face"],"topic_instruction_minutes":{"G1-A":20,"G1-B":20,"G1-C":20,"G1-D":20,"G2-A":20,"G2-B":20,"G2-C":20,"G2-D":20,"G2-E":10,"G3-A":40,"G3-B":20,"G3-C":30,"G3-D":40,"G3-E":40,"G3-F":20,"G3-G":30,"G3-H":30,"G3-I":30,"G3-J":40,"G3-K":20,"G3-L":30},"group4":{"budget_instruction_minutes":180,"origin":"product_contextualization_starter_not_legal_list","requires_company_customization":true,"topics":[{"local_key":"G4-S1","title":"İşyerinin risk değerlendirmesinde belirlenen öncelikli riskler ve alınacak önlemler","instruction_minutes":50,"requires_context":true},{"local_key":"G4-S2","title":"İşyerinin acil durum planı, tahliye yolları ve toplanma alanları","instruction_minutes":50,"requires_context":true},{"local_key":"G4-S3","title":"Göreve, departmana ve kullanılan ekipmana özgü güvenli çalışma uygulamaları","instruction_minutes":40,"requires_context":true},{"local_key":"G4-S4","title":"Faaliyete özgü talimatlar ve sahadaki uygulama örnekleri","instruction_minutes":40,"requires_context":true}]},"ready_for_completion_without_review":false,"common_groups_review_guard":{"reference_instruction_minutes":540,"when_below":"requires_content_rule_review","source":"W1 SSS 135; separate supplementary check","do_not_silently_reduce_when_increasing_g4":true}},{"code":"repeat_low","label":"Tekrar Temel Eğitimi — Az Tehlikeli","cycle":"periodic_repeat","hazard_class":"low","minimum_lesson_units":8,"minimum_group4_lesson_units":2,"renewal_interval_months":36,"default_instruction_minutes":360,"default_break_minutes":120,"default_scheduled_minutes":480,"default_minutes_by_group":{"G1":80,"G2":80,"G3":110,"G4":90},"minutes_origin":"product_proposal_repeat_training","source_example_page":null,"default_delivery":"face_to_face","allowed_delivery_groups_1_to_3":["face_to_face","external_distance","hybrid"],"allowed_delivery_group4":["face_to_face","external_distance","hybrid"],"topic_instruction_minutes":{"G1-A":20,"G1-B":20,"G1-C":20,"G1-D":20,"G2-A":20,"G2-B":20,"G2-C":20,"G2-D":10,"G2-E":10,"G3-A":10,"G3-B":10,"G3-C":10,"G3-D":10,"G3-E":10,"G3-F":10,"G3-G":10,"G3-H":10,"G3-I":10,"G3-J":5,"G3-K":5,"G3-L":10},"group4":{"budget_instruction_minutes":90,"origin":"product_contextualization_starter_not_legal_list","requires_company_customization":true,"topics":[{"local_key":"G4-S1","title":"İşyerinin risk değerlendirmesinde belirlenen öncelikli riskler ve alınacak önlemler","instruction_minutes":25,"requires_context":true},{"local_key":"G4-S2","title":"İşyerinin acil durum planı, tahliye yolları ve toplanma alanları","instruction_minutes":25,"requires_context":true},{"local_key":"G4-S3","title":"Göreve, departmana ve kullanılan ekipmana özgü güvenli çalışma uygulamaları","instruction_minutes":20,"requires_context":true},{"local_key":"G4-S4","title":"Faaliyete özgü talimatlar ve sahadaki uygulama örnekleri","instruction_minutes":20,"requires_context":true}]},"ready_for_completion_without_review":false},{"code":"repeat_hazardous","label":"Tekrar Temel Eğitimi — Tehlikeli","cycle":"periodic_repeat","hazard_class":"hazardous","minimum_lesson_units":8,"minimum_group4_lesson_units":3,"renewal_interval_months":24,"default_instruction_minutes":360,"default_break_minutes":120,"default_scheduled_minutes":480,"default_minutes_by_group":{"G1":60,"G2":60,"G3":105,"G4":135},"minutes_origin":"product_proposal_repeat_training","source_example_page":null,"default_delivery":"face_to_face","allowed_delivery_groups_1_to_3":["face_to_face","external_distance","hybrid"],"allowed_delivery_group4":["face_to_face"],"topic_instruction_minutes":{"G1-A":15,"G1-B":15,"G1-C":15,"G1-D":15,"G2-A":15,"G2-B":15,"G2-C":15,"G2-D":10,"G2-E":5,"G3-A":10,"G3-B":10,"G3-C":10,"G3-D":10,"G3-E":10,"G3-F":5,"G3-G":10,"G3-H":10,"G3-I":5,"G3-J":10,"G3-K":5,"G3-L":10},"group4":{"budget_instruction_minutes":135,"origin":"product_contextualization_starter_not_legal_list","requires_company_customization":true,"topics":[{"local_key":"G4-S1","title":"İşyerinin risk değerlendirmesinde belirlenen öncelikli riskler ve alınacak önlemler","instruction_minutes":40,"requires_context":true},{"local_key":"G4-S2","title":"İşyerinin acil durum planı, tahliye yolları ve toplanma alanları","instruction_minutes":35,"requires_context":true},{"local_key":"G4-S3","title":"Göreve, departmana ve kullanılan ekipmana özgü güvenli çalışma uygulamaları","instruction_minutes":30,"requires_context":true},{"local_key":"G4-S4","title":"Faaliyete özgü talimatlar ve sahadaki uygulama örnekleri","instruction_minutes":30,"requires_context":true}]},"ready_for_completion_without_review":false},{"code":"repeat_very_hazardous","label":"Tekrar Temel Eğitimi — Çok Tehlikeli","cycle":"periodic_repeat","hazard_class":"very_hazardous","minimum_lesson_units":8,"minimum_group4_lesson_units":4,"renewal_interval_months":12,"default_instruction_minutes":360,"default_break_minutes":120,"default_scheduled_minutes":480,"default_minutes_by_group":{"G1":45,"G2":45,"G3":90,"G4":180},"minutes_origin":"product_proposal_repeat_training","source_example_page":null,"default_delivery":"face_to_face","allowed_delivery_groups_1_to_3":["face_to_face","external_distance","hybrid"],"allowed_delivery_group4":["face_to_face"],"topic_instruction_minutes":{"G1-A":10,"G1-B":10,"G1-C":10,"G1-D":15,"G2-A":10,"G2-B":10,"G2-C":10,"G2-D":10,"G2-E":5,"G3-A":10,"G3-B":5,"G3-C":10,"G3-D":10,"G3-E":10,"G3-F":5,"G3-G":10,"G3-H":5,"G3-I":5,"G3-J":10,"G3-K":5,"G3-L":5},"group4":{"budget_instruction_minutes":180,"origin":"product_contextualization_starter_not_legal_list","requires_company_customization":true,"topics":[{"local_key":"G4-S1","title":"İşyerinin risk değerlendirmesinde belirlenen öncelikli riskler ve alınacak önlemler","instruction_minutes":50,"requires_context":true},{"local_key":"G4-S2","title":"İşyerinin acil durum planı, tahliye yolları ve toplanma alanları","instruction_minutes":50,"requires_context":true},{"local_key":"G4-S3","title":"Göreve, departmana ve kullanılan ekipmana özgü güvenli çalışma uygulamaları","instruction_minutes":40,"requires_context":true},{"local_key":"G4-S4","title":"Faaliyete özgü talimatlar ve sahadaki uygulama örnekleri","instruction_minutes":40,"requires_context":true}]},"ready_for_completion_without_review":false}]}$education$::jsonb);

-- Each helper runs behind the private owner/session gateway. No direct table access.
CREATE FUNCTION private_isg.education_scope(p_scope jsonb,p_package jsonb,p_trainers jsonb,p_curriculum boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE company uuid:=(p_scope->>'company_id')::uuid; workplace uuid:=(p_scope->>'workplace_id')::uuid;
 actor uuid; hazard text; co public.companies; wp private_isg.workplaces;
 preset jsonb; topics jsonb:='[]'; people jsonb:='[]'; issues jsonb:='[]'; t jsonb; person jsonb; lesson jsonb; allocation jsonb;
 canonical jsonb; code text; groupcode text; label text; mins integer; total integer:=0; g4 integer:=0; common integer:=0;
 breaks integer:=0; taught integer:=0; lesson_count integer:=0; assigned integer; method text; ids uuid[]:='{}'; topic_ids text[]:='{}'; trainer_id text;
 start_time timestamptz; finish_time timestamptz; first_time timestamptz; last_time timestamptz; previous_end timestamptz;
 person_id uuid; name text; previous_name text; job text; dept text; jobdate date; renewal integer:=0; cycle text:=p_scope->>'cycle'; row_id uuid;
BEGIN
 actor:=private_isg.require_company(company,true);
 SELECT * INTO co FROM public.companies WHERE id=company AND user_id=actor;
 SELECT * INTO wp FROM private_isg.workplaces WHERE id=workplace AND company_id=company AND owner_id=actor;
 IF NOT FOUND THEN RAISE EXCEPTION 'WORKPLACE_REQUIRED'; END IF;
 IF p_scope->>'id' IS NULL OR length(coalesce(p_scope->>'group_name',''))>160 OR cycle IS NULL
 OR cycle NOT IN ('initial','periodic_repeat','onboarding','knowledge_refresh','additional','workplace_specific','custom')
 OR jsonb_typeof(p_scope->'topics') IS DISTINCT FROM 'array' OR jsonb_array_length(p_scope->'topics') NOT BETWEEN 1 AND 150
 OR jsonb_typeof(p_scope->'participants') IS DISTINCT FROM 'array' OR jsonb_array_length(p_scope->'participants') NOT BETWEEN (CASE WHEN p_curriculum THEN 0 ELSE 1 END) AND 500
 OR jsonb_typeof(p_scope->'lessons') IS DISTINCT FROM 'array' OR jsonb_array_length(p_scope->'lessons') NOT BETWEEN (CASE WHEN p_curriculum THEN 0 ELSE 1 END) AND 200
 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 row_id:=(p_scope->>'id')::uuid;
 SELECT min((x->>'starts_at')::timestamptz),max((x->>'starts_at')::timestamptz+make_interval(mins=>(x->>'instruction_minutes')::int+(x->>'break_minutes')::int))
 INTO first_time,last_time FROM jsonb_array_elements(p_scope->'lessons') x;
 IF p_curriculum AND first_time IS NULL THEN first_time:=clock_timestamp(); last_time:=first_time; END IF;
 IF first_time IS NULL OR NOT isfinite(first_time) OR NOT isfinite(last_time) OR last_time>clock_timestamp()
 OR last_time-first_time>interval '366 days' THEN RAISE EXCEPTION 'TRAINING_DATE_INVALID'; END IF;
 jobdate:=(first_time AT TIME ZONE 'Europe/Istanbul')::date;
 SELECT c.hazard_class INTO hazard FROM private_isg.workplace_context_versions c
 WHERE c.company_id=company AND c.workplace_id=workplace AND c.starts_on<=jobdate AND (c.ends_before IS NULL OR c.ends_before>jobdate)
 ORDER BY c.starts_on DESC LIMIT 1;
 hazard:=coalesce(hazard,wp.hazard_class,co.hazard_class);
 SELECT value INTO preset FROM jsonb_array_elements(p_package->'presets')
 WHERE value->>'cycle'=cycle AND value->>'hazard_class'=CASE hazard WHEN 'medium' THEN 'hazardous' WHEN 'high' THEN 'very_hazardous' ELSE hazard END;
 IF cycle IN ('initial','periodic_repeat') THEN
  IF preset IS NULL THEN RAISE EXCEPTION 'PROFILE_UNAVAILABLE'; END IF;
  IF jobdate<'2026-04-02' THEN RAISE EXCEPTION 'RULE_DATE_UNSUPPORTED'; END IF;
  renewal:=(preset->>'renewal_interval_months')::integer;
 ELSIF cycle='custom' THEN
  renewal:=coalesce((p_scope->>'renewal_months')::integer,0);
  IF renewal NOT BETWEEN 0 AND 120 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_scope->'topics') child JOIN jsonb_array_elements(p_scope->'topics') parent ON child->>'parent_code'=parent->>'code') THEN RAISE EXCEPTION 'TOPIC_HIERARCHY_INVALID'; END IF;
 FOR t IN SELECT value FROM jsonb_array_elements(p_scope->'topics') LOOP
  code:=t->>'code'; groupcode:=t->>'group'; method:=t->>'method';
  IF code IS NULL OR code !~ '^[A-Za-z0-9_-]{1,80}$' OR code=ANY(topic_ids) OR groupcode IS NULL OR groupcode NOT IN ('G1','G2','G3','G4')
   OR coalesce(t->>'instruction_minutes','') !~ '^[0-9]{1,5}$' OR method IS NULL OR method NOT IN ('face_to_face','online')
   OR jsonb_typeof(t->'trainer_ids') IS DISTINCT FROM 'array' OR jsonb_array_length(t->'trainer_ids')>20 THEN RAISE EXCEPTION 'TOPIC_INVALID'; END IF;
  topic_ids:=array_append(topic_ids,code); mins:=(t->>'instruction_minutes')::integer;
  IF mins>1440 THEN RAISE EXCEPTION 'TOPIC_INVALID'; END IF;
  canonical:=NULL;
  IF preset IS NOT NULL AND groupcode<>'G4' THEN
   SELECT value INTO canonical FROM jsonb_array_elements(p_package->'topics') WHERE value->>'code'=coalesce(nullif(t->>'parent_code',''),code);
   IF canonical IS NULL OR canonical->>'group_code' IS DISTINCT FROM groupcode THEN RAISE EXCEPTION 'TOPIC_INVALID'; END IF;
  END IF;
  label:=coalesce(canonical->>'legal_label',canonical->>'title',t->>'title');
  IF nullif(t->>'parent_code','') IS NOT NULL THEN label:=t->>'title'; END IF;
  IF label IS NULL OR length(btrim(label)) NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'TOPIC_INVALID'; END IF;
  IF mins=0 THEN issues:=issues||jsonb_build_array('TOPIC_MINUTES_MISSING'); END IF;
  IF jsonb_array_length(t->'trainer_ids')=0 THEN issues:=issues||jsonb_build_array('TRAINER_SCOPE_MISSING'); END IF;
  FOR trainer_id IN SELECT jsonb_array_elements_text(t->'trainer_ids') LOOP
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_trainers) z WHERE z->>'id'=trainer_id) THEN RAISE EXCEPTION 'TRAINER_INVALID'; END IF;
  END LOOP;
  IF (preset IS NOT NULL AND groupcode='G4' AND hazard<>'low' OR cycle='onboarding') AND method='online' THEN issues:=issues||jsonb_build_array('FACE_TO_FACE_REQUIRED'); END IF;
  total:=total+mins; IF groupcode='G4' THEN g4:=g4+mins; ELSE common:=common+mins; END IF;
  topics:=topics||jsonb_build_array(jsonb_build_object('code',code,'parent_code',nullif(t->>'parent_code',''),'group',groupcode,'title',label,
   'instruction_minutes',mins,'method',method,'trainer_ids',t->'trainer_ids','legal_title',canonical->>'legal_label'));
 END LOOP;
 IF preset IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_package->'topics') required WHERE NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(topics) actual WHERE coalesce(actual->>'parent_code',actual->>'code')=required->>'code' AND (actual->>'instruction_minutes')::int>0))
  THEN issues:=issues||jsonb_build_array('REQUIRED_TOPIC_MISSING'); END IF;
  IF total<(preset->>'default_instruction_minutes')::int THEN issues:=issues||jsonb_build_array('TOTAL_TOO_SHORT'); END IF;
  IF g4<(preset->'group4'->>'budget_instruction_minutes')::int THEN issues:=issues||jsonb_build_array('GROUP4_TOO_SHORT'); END IF;
  IF cycle='initial' AND common<(preset->'common_groups_review_guard'->>'reference_instruction_minutes')::int THEN issues:=issues||jsonb_build_array('COMMON_GROUPS_TOO_SHORT'); END IF;
  IF length(btrim(coalesce(p_scope->>'context_note','')))=0 THEN issues:=issues||jsonb_build_array('GROUP4_CONTEXT_MISSING'); END IF;
 END IF;
 IF cycle='onboarding' AND total<120 THEN issues:=issues||jsonb_build_array('TOTAL_TOO_SHORT'); END IF;
 IF total<1 OR total>100000 OR length(coalesce(p_scope->>'context_note',''))>4000 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 FOR lesson IN SELECT value FROM jsonb_array_elements(p_scope->'lessons') ORDER BY (value->>'starts_at')::timestamptz LOOP
  IF coalesce(lesson->>'instruction_minutes','') !~ '^[0-9]{1,4}$' OR coalesce(lesson->>'break_minutes','') !~ '^[0-9]{1,4}$'
    OR jsonb_typeof(lesson->'allocations') IS DISTINCT FROM 'array' OR jsonb_array_length(lesson->'allocations')>150 THEN RAISE EXCEPTION 'LESSON_INVALID'; END IF;
  mins:=(lesson->>'instruction_minutes')::int; assigned:=0;
  IF mins NOT BETWEEN 1 AND 1440 OR (lesson->>'break_minutes')::int NOT BETWEEN 0 AND 720 THEN RAISE EXCEPTION 'LESSON_INVALID'; END IF;
  start_time:=(lesson->>'starts_at')::timestamptz;
  finish_time:=start_time+make_interval(mins=>mins+(lesson->>'break_minutes')::int);
  IF start_time IS NULL OR NOT isfinite(start_time) OR finish_time>clock_timestamp() OR start_time<previous_end THEN RAISE EXCEPTION 'LESSON_OVERLAP_OR_FUTURE'; END IF;
  previous_end:=finish_time;
  FOR allocation IN SELECT value FROM jsonb_array_elements(lesson->'allocations') LOOP
   IF allocation->>'topic_code' IS NULL OR coalesce(allocation->>'minutes','') !~ '^[0-9]{1,4}$' OR NOT (allocation->>'topic_code'=ANY(topic_ids)) THEN RAISE EXCEPTION 'LESSON_ALLOCATION_INVALID'; END IF;
   assigned:=assigned+(allocation->>'minutes')::int;
  END LOOP;
  IF assigned<>mins THEN issues:=issues||jsonb_build_array('LESSON_TOPIC_MISMATCH'); END IF;
  IF preset IS NOT NULL AND (mins<45 OR (lesson->>'break_minutes')::int<15) THEN issues:=issues||jsonb_build_array('LESSON_BREAK_INVALID'); END IF;
  taught:=taught+mins; breaks:=breaks+(lesson->>'break_minutes')::int; lesson_count:=lesson_count+1;
 END LOOP;
 FOR t IN SELECT value FROM jsonb_array_elements(topics) LOOP
  SELECT coalesce(sum((a->>'minutes')::int),0) INTO assigned FROM jsonb_array_elements(p_scope->'lessons') l,
   LATERAL jsonb_array_elements(l->'allocations') a WHERE a->>'topic_code'=t->>'code';
  IF assigned<>(t->>'instruction_minutes')::int THEN issues:=issues||jsonb_build_array('LESSON_TOPIC_MISMATCH'); END IF;
 END LOOP;
 IF taught<>total THEN issues:=issues||jsonb_build_array('LESSON_TOPIC_MISMATCH'); END IF;
 IF length(btrim(coalesce(p_scope->>'employer_name','')))=0 THEN issues:=issues||jsonb_build_array('EMPLOYER_MISSING'); END IF;
 IF coalesce(p_scope->>'employer_capacity','') NOT IN ('employer','representative') THEN issues:=issues||jsonb_build_array('EMPLOYER_CAPACITY_MISSING'); END IF;
 IF length(coalesce(p_scope->>'employer_name',''))>200 OR length(coalesce(p_scope->>'legal_name',''))>1000 OR length(coalesce(p_scope->>'location',''))>300 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 FOR person IN SELECT value FROM jsonb_array_elements(p_scope->'participants') LOOP
  person_id:=(person->>'id')::uuid;
  IF person_id IS NULL OR person_id=ANY(ids) THEN RAISE EXCEPTION 'PARTICIPANT_INVALID'; END IF;
  SELECT full_name INTO name FROM private_isg.employees WHERE id=person_id AND company_id=company AND owner_id=actor FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PARTICIPANT_UNAVAILABLE'; END IF;
  SELECT p->>'name' INTO previous_name FROM private_isg.pilot_training_sessions session, LATERAL jsonb_array_elements(session.education->'scopes') old_scope, LATERAL jsonb_array_elements(old_scope->'participants') p WHERE session.owner_id=actor AND session.id=(p_scope->>'_session_id')::uuid AND old_scope->>'id'=p_scope->>'id' AND p->>'id'=person_id::text ORDER BY session.id DESC LIMIT 1;
  name:=coalesce(previous_name,name);
  ids:=array_append(ids,person_id); job:=NULL; dept:=NULL;
  SELECT job_title_snapshot,department_name_snapshot INTO job,dept FROM private_isg.employee_assignments a
   WHERE a.company_id=company AND a.employee_id=person_id AND a.starts_on<=jobdate AND (a.ends_before IS NULL OR a.ends_before>jobdate) ORDER BY a.starts_on DESC LIMIT 1;
  job:=coalesce(nullif(btrim(person->>'job_title'),''),job,'');
  IF length(job)>300 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  people:=people||jsonb_build_array(jsonb_build_object('id',person_id,'name',name,'job_title',job,'department',coalesce(dept,'')));
 END LOOP;
 SELECT coalesce(jsonb_agg(DISTINCT value),'[]') INTO issues FROM jsonb_array_elements(issues);
 RETURN jsonb_build_object('id',row_id,'company_id',company,'workplace_id',workplace,'company_name',co.name,'workplace_name',wp.name,
  'logo_path',to_jsonb(co)->>'logo_path','legal_name',coalesce(nullif(btrim(p_scope->>'legal_name'),''),co.name),'hazard_class',hazard,'cycle',cycle,'group_name',coalesce(p_scope->>'group_name',''),
  'preset_code',preset->>'code','package_version',1,'context_note',coalesce(p_scope->>'context_note',''),'topics',topics,'lessons',p_scope->'lessons',
  'participants',people,'instruction_minutes',total,'break_minutes',breaks,'lesson_units',lesson_count,'group4_minutes',g4,'issues',issues,
  'starts_at',first_time,'ends_at',last_time,'held_on',(last_time AT TIME ZONE 'Europe/Istanbul')::date,
  'valid_until',CASE WHEN renewal>0 THEN ((last_time AT TIME ZONE 'Europe/Istanbul')::date+make_interval(months=>renewal))::date ELSE NULL END,
  'renewal_months',renewal,'employer_name',coalesce(p_scope->>'employer_name',''),'employer_capacity',coalesce(p_scope->>'employer_capacity','representative'),
  'location',coalesce(p_scope->>'location',''));
END $$;

CREATE FUNCTION private_isg.education_detail(p_id uuid,p_company uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); result jsonb; co uuid;
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_id IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_sessions WHERE id=p_id AND owner_id=actor) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  FOR co IN SELECT company_id FROM private_isg.pilot_training_records WHERE session_id=p_id LOOP PERFORM private_isg.require_company(co,false); END LOOP;
  result:=private_isg.pilot_training_session_row(p_id);
 END IF;
 IF p_company IS NOT NULL THEN PERFORM private_isg.require_company(p_company,false); END IF;
 RETURN jsonb_build_object('schema_version',3,'owner_id',actor,'row',result,
 'package_checksum',(SELECT content_checksum FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1),
 'package',(SELECT content_package FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1),
 'certificates',(SELECT coalesce(jsonb_agg(jsonb_build_object('document_id',d.document_id,'revision',v.version,'scope_id',split_part(d.source_ref,':',2),'person_id',split_part(d.source_ref,':',3),'source_session_revision',v.snapshot->'source_session_revision') ORDER BY v.version DESC),'[]') FROM private_isg.documents d JOIN private_isg.document_versions v ON v.document_id=d.document_id WHERE d.owner_id=actor AND d.source_domain='training' AND d.template_code IN ('basic_training_certificate','training_record_certificate') AND split_part(d.source_ref,':',1)=p_id::text),
 'catalog_enabled',(SELECT enabled FROM private_isg.education_controls WHERE key='catalog_v1'),
 'certificate_enabled',(SELECT enabled FROM private_isg.education_controls WHERE key='certificate_v1'),
 'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'company_id',w.company_id,'company_name',(SELECT name FROM public.companies WHERE id=w.company_id),'name',w.name,'hazard_class',w.hazard_class) ORDER BY w.name),'[]')
 FROM private_isg.workplaces w WHERE w.owner_id=actor AND NOT w.is_archived AND (p_company IS NULL OR w.company_id=p_company) AND private_isg.p05_pilot_can_read(actor,w.company_id)),
 'curricula',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.curriculum_id,'company_id',c.company_id,'workplace_id',c.workplace_id,'scope_key',c.scope_key,'education',c.education)),'[]')
 FROM private_isg.company_curriculum_versions c WHERE c.owner_id=actor AND c.education IS NOT NULL AND c.state='active' AND (p_company IS NULL OR c.company_id=p_company) AND private_isg.p05_pilot_can_read(actor,c.company_id)));
END $$;

CREATE FUNCTION private_isg.education_save(p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); sid uuid:=(p_payload->>'id')::uuid; old private_isg.pilot_training_sessions;
 prior private_isg.education_receipts; fingerprint bytea; action text:=p_payload->>'action'; package jsonb; scopes jsonb:='[]'; trainers jsonb:=p_payload->'trainers';
 s jsonb; scope jsonb; person jsonb; co uuid; companies uuid[]:='{}'; scope_ids uuid[]:='{}'; person_ids uuid[]:='{}'; record_id uuid; version_no bigint;
 result jsonb; training_title text:=btrim(p_payload->>'title'); provider text:=btrim(p_payload->>'provider_name'); tr jsonb; curriculum_key text;
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,true) OR NOT coalesce((SELECT enabled FROM private_isg.education_controls WHERE key='catalog_v1'),false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_mutation IS NULL OR p_payload IS NULL OR octet_length(p_payload::text)>2097152 OR action IS NULL OR action NOT IN ('save','delete','curriculum') THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':training-v2',0));
 IF sid IS NOT NULL THEN
  SELECT * INTO old FROM private_isg.pilot_training_sessions WHERE id=sid AND owner_id=actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  FOR co IN SELECT company_id FROM private_isg.pilot_training_records WHERE session_id=sid ORDER BY company_id LOOP PERFORM private_isg.require_company(co,true); END LOOP;
 END IF;
 IF action<>'delete' THEN
  IF jsonb_typeof(p_payload->'scopes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'scopes') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  FOR co IN SELECT DISTINCT (value->>'company_id')::uuid FROM jsonb_array_elements(p_payload->'scopes') ORDER BY 1 LOOP PERFORM private_isg.require_company(co,true); companies:=array_append(companies,co); END LOOP;
  IF array_length(companies,1)>30 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 END IF;
 fingerprint:=sha256(convert_to(p_payload::text,'UTF8'));
 SELECT * INTO prior FROM private_isg.education_receipts WHERE owner_id=actor AND mutation_id=p_mutation;
 IF FOUND THEN IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF; RETURN prior.response; END IF;
 IF sid IS NOT NULL AND (old.deleted_at IS NOT NULL OR old.version IS DISTINCT FROM (p_payload->>'expected_version')::bigint) THEN RAISE EXCEPTION 'VERSION_CONFLICT'; END IF;
 IF action='delete' THEN
  IF sid IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.pilot_training_session_revisions VALUES(sid,old.version,private_isg.pilot_training_session_row(sid),now());
  UPDATE private_isg.pilot_training_sessions SET deleted_at=now(),version=version+1 WHERE id=sid;
  UPDATE private_isg.pilot_training_records SET state='cancelled',version=version+1 WHERE session_id=sid;
 ELSE
  IF training_title IS NULL OR length(training_title) NOT BETWEEN 1 AND 200 OR provider IS NULL OR length(provider)>300 OR jsonb_typeof(trainers) IS DISTINCT FROM 'array' OR jsonb_array_length(trainers) NOT BETWEEN 1 AND 20
   OR length(coalesce(p_payload->>'notes',''))>2000 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
  FOR tr IN SELECT value FROM jsonb_array_elements(trainers) LOOP
   IF tr->>'id' IS NULL OR length(btrim(coalesce(tr->>'name',''))) NOT BETWEEN 1 AND 200 OR length(coalesce(tr->>'title',''))>200 THEN RAISE EXCEPTION 'TRAINER_INVALID'; END IF;
  END LOOP;
  IF (SELECT count(*)<>count(DISTINCT value->>'id') FROM jsonb_array_elements(trainers)) THEN RAISE EXCEPTION 'TRAINER_INVALID'; END IF;
  SELECT content_package INTO package FROM private_isg.training_catalog_versions WHERE catalog_code='tr_isg_basic_2026' AND version=1;
  FOR s IN SELECT value FROM jsonb_array_elements(p_payload->'scopes') LOOP
   scope:=private_isg.education_scope(s||jsonb_build_object('_session_id',sid),package,trainers,action='curriculum');
   IF (scope->>'id')::uuid=ANY(scope_ids) THEN RAISE EXCEPTION 'SCOPE_INVALID'; END IF;
   scope_ids:=array_append(scope_ids,(scope->>'id')::uuid);
   FOR person IN SELECT value FROM jsonb_array_elements(scope->'participants') LOOP
    IF (person->>'id')::uuid=ANY(person_ids) THEN RAISE EXCEPTION 'PARTICIPANT_DUPLICATE'; END IF;
    person_ids:=array_append(person_ids,(person->>'id')::uuid);
   END LOOP;
   scopes:=scopes||jsonb_build_array(scope);
  END LOOP;
  IF action='curriculum' THEN
   IF jsonb_array_length(scopes)<>1 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
   scope:=scopes->0; co:=(scope->>'company_id')::uuid; curriculum_key:=(scope->>'cycle')||':'||(scope->>'group_name')||':'||(scope->>'hazard_class');
   PERFORM pg_advisory_xact_lock(hashtextextended(co::text||':'||(scope->>'workplace_id'),0));
   SELECT coalesce(max(version),0)+1 INTO version_no FROM private_isg.company_curriculum_versions WHERE company_id=co AND workplace_id=(scope->>'workplace_id')::uuid AND catalog_code='tr_isg_basic_2026';
   UPDATE private_isg.company_curriculum_versions SET state='superseded' WHERE company_id=co AND workplace_id=(scope->>'workplace_id')::uuid AND catalog_code='tr_isg_basic_2026' AND scope_key=curriculum_key AND state='active';
   INSERT INTO private_isg.company_curriculum_versions(company_id,owner_id,workplace_id,catalog_code,catalog_version,version,hazard_class,g4_topics,g4_lessons,state,education,scope_key)
   VALUES(co,actor,(scope->>'workplace_id')::uuid,'tr_isg_basic_2026',1,version_no,scope->>'hazard_class',scope->'topics',(scope->>'group4_minutes')::int/45,'active',scope-'participants'-'lessons',curriculum_key);
   result:=jsonb_build_object('schema_version',3,'owner_id',actor,'mutation_id',p_mutation,'curriculum_saved',true);
  ELSE
   IF sid IS NULL THEN
    INSERT INTO private_isg.pilot_training_sessions(owner_id,title,trainer,held_on) VALUES(actor,training_title,trainers->0->>'name',(scopes->0->>'held_on')::date) RETURNING id INTO sid;
   ELSE
    INSERT INTO private_isg.pilot_training_session_revisions VALUES(sid,old.version,private_isg.pilot_training_session_row(sid),now());
    UPDATE private_isg.pilot_training_sessions SET version=version+1 WHERE id=sid;
   END IF;
   UPDATE private_isg.pilot_training_sessions SET title=training_title,trainer=trainers->0->>'name',notes=coalesce(p_payload->>'notes',''),
    held_on=(SELECT max((x->>'held_on')::date) FROM jsonb_array_elements(scopes) x),
    method=CASE WHEN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(scopes) x,LATERAL jsonb_array_elements(x->'topics') t WHERE t->>'method'='online') THEN 'face_to_face'
     WHEN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(scopes) x,LATERAL jsonb_array_elements(x->'topics') t WHERE t->>'method'='face_to_face') THEN 'online' ELSE 'mixed' END,
    education=jsonb_build_object('schema_version',1,'completion_basis','expert_record','provider_name',provider,'trainers',trainers,'scopes',scopes) WHERE id=sid;
   UPDATE private_isg.pilot_training_records SET state='cancelled' WHERE session_id=sid AND NOT(company_id=ANY(companies));
   FOREACH co IN ARRAY companies LOOP
    SELECT id INTO record_id FROM private_isg.pilot_training_records WHERE session_id=sid AND company_id=co;
    IF record_id IS NULL THEN
     INSERT INTO private_isg.pilot_training_records(company_id,owner_id,title,trainer,starts_at,duration_minutes,state,completed_at,session_id)
     VALUES(co,actor,training_title,trainers->0->>'name',(scopes->0->>'starts_at')::timestamptz,1,'completed',now(),sid) RETURNING id INTO record_id;
    END IF;
    UPDATE private_isg.pilot_training_records SET title=training_title,trainer=trainers->0->>'name',state='completed',completed_at=now(),version=version+1,
     starts_at=(SELECT min((x->>'starts_at')::timestamptz) FROM jsonb_array_elements(scopes) x WHERE (x->>'company_id')::uuid=co),
     duration_minutes=(SELECT max((x->>'instruction_minutes')::int+(x->>'break_minutes')::int) FROM jsonb_array_elements(scopes) x WHERE (x->>'company_id')::uuid=co),
     valid_until=(SELECT min((x->>'valid_until')::date) FROM jsonb_array_elements(scopes) x WHERE (x->>'company_id')::uuid=co),
     company_snapshot=(SELECT jsonb_build_object('company_name',name,'hazard_class',hazard_class) FROM public.companies WHERE id=co) WHERE id=record_id;
    DELETE FROM private_isg.pilot_training_participants WHERE training_id=record_id AND NOT(employee_id=ANY(person_ids));
    FOR person IN SELECT p FROM jsonb_array_elements(scopes) x,LATERAL jsonb_array_elements(x->'participants') p WHERE (x->>'company_id')::uuid=co LOOP
     INSERT INTO private_isg.pilot_training_participants VALUES(co,record_id,(person->>'id')::uuid,person->>'name',true)
     ON CONFLICT(training_id,employee_id) DO UPDATE SET employee_name=excluded.employee_name;
    END LOOP;
   END LOOP;
  END IF;
 END IF;
 IF result IS NULL THEN result:=jsonb_build_object('schema_version',3,'owner_id',actor,'mutation_id',p_mutation,'row',private_isg.pilot_training_session_row(sid)); END IF;
 INSERT INTO private_isg.education_receipts VALUES(actor,p_mutation,fingerprint,result);
 RETURN result;
END $$;

CREATE FUNCTION private_isg.education_certificate(p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); sid uuid:=(p_payload->>'session_id')::uuid; scope_id uuid:=(p_payload->>'scope_id')::uuid;
 person_id uuid:=(p_payload->>'person_id')::uuid; mutation uuid:=(p_payload->>'mutation_id')::uuid; action text:=p_payload->>'action';
 session private_isg.pilot_training_sessions; scope jsonb; person jsonb; issues jsonb; snapshot jsonb; tr jsonb; doc private_isg.documents;
 stored private_isg.document_versions; fingerprint bytea; prior private_isg.education_receipts; issued date; serial bigint; year_no integer;
 result jsonb; template text; reference text; new_version integer; number text; relevant_trainers jsonb; logo text:=nullif(p_payload->>'logo_png_base64',''); logo_bytes bytea;
BEGIN
 IF p_payload IS NULL OR octet_length(p_payload::text)>1048576 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 IF action='read' THEN
  SELECT * INTO doc FROM private_isg.documents WHERE documents.document_id=(p_payload->>'document_id')::uuid AND owner_id=actor;
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  PERFORM private_isg.require_company(doc.company_id,false);
  SELECT * INTO stored FROM private_isg.document_versions WHERE document_versions.document_id=doc.document_id AND version=coalesce((p_payload->>'revision')::int,doc.current_version);
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'ready',true,'issues','[]'::jsonb,'document_id',doc.document_id,'revision',stored.version,'snapshot',stored.snapshot,'snapshot_hash',encode(stored.snapshot_sha256,'hex'));
 END IF;
 IF logo IS NOT NULL THEN
  IF length(logo)>350000 THEN RAISE EXCEPTION 'LOGO_INVALID'; END IF;
  BEGIN logo_bytes:=decode(logo,'base64'); EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'LOGO_INVALID'; END;
  IF octet_length(logo_bytes) NOT BETWEEN 33 AND 262144 OR substring(logo_bytes from 1 for 8) IS DISTINCT FROM decode('89504e470d0a1a0a','hex') THEN RAISE EXCEPTION 'LOGO_INVALID'; END IF;
 END IF;
 IF action IS NULL OR action NOT IN ('preview','issue') OR NOT private_isg.p05_pilot_account_enabled(actor,true) THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 SELECT * INTO session FROM private_isg.pilot_training_sessions WHERE id=sid AND owner_id=actor FOR UPDATE;
 IF NOT FOUND OR session.deleted_at IS NOT NULL OR session.education IS NULL THEN RAISE EXCEPTION 'EDUCATION_DETAILS_REQUIRED'; END IF;
 SELECT x INTO scope FROM jsonb_array_elements(session.education->'scopes') x WHERE (x->>'id')::uuid=scope_id;
 IF scope IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 PERFORM private_isg.require_company((scope->>'company_id')::uuid,true);
 SELECT x INTO person FROM jsonb_array_elements(scope->'participants') x WHERE (x->>'id')::uuid=person_id;
 IF person IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 IF action='issue' THEN
  IF mutation IS NULL OR NOT coalesce((SELECT enabled FROM private_isg.education_controls WHERE key='certificate_v1'),false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
  fingerprint:=sha256(convert_to(p_payload::text,'UTF8'));
  SELECT * INTO prior FROM private_isg.education_receipts WHERE owner_id=actor AND mutation_id=mutation;
  IF FOUND THEN IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF; RETURN prior.response; END IF;
 END IF;
 IF session.version IS DISTINCT FROM (p_payload->>'expected_version')::bigint THEN RAISE EXCEPTION 'VERSION_CONFLICT'; END IF;
 issued:=coalesce((p_payload->>'issued_on')::date,(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date);
 IF NOT isfinite(issued) OR issued<(scope->>'held_on')::date OR issued>(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date THEN RAISE EXCEPTION 'DOCUMENT_DATE_INVALID'; END IF;
 issues:=scope->'issues';
 IF btrim(coalesce(person->>'job_title',''))='' THEN issues:=issues||jsonb_build_array('JOB_TITLE_MISSING'); END IF;
 IF btrim(coalesce(session.education->>'provider_name',''))='' THEN issues:=issues||jsonb_build_array('PROVIDER_MISSING'); END IF;
 SELECT coalesce(jsonb_agg(t),'[]') INTO relevant_trainers FROM jsonb_array_elements(session.education->'trainers') t WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(scope->'topics') topic WHERE topic->'trainer_ids' ? (t->>'id'));
 FOR tr IN SELECT value FROM jsonb_array_elements(relevant_trainers) LOOP
  IF btrim(coalesce(tr->>'title',''))='' THEN issues:=issues||jsonb_build_array('TRAINER_TITLE_MISSING'); END IF;
 END LOOP;
 SELECT coalesce(jsonb_agg(DISTINCT value),'[]') INTO issues FROM jsonb_array_elements(issues);
 template:=CASE WHEN scope->>'cycle' IN ('initial','periodic_repeat') THEN 'basic_training_certificate' ELSE 'training_record_certificate' END;
 snapshot:=jsonb_build_object('schema_version',1,'template_version',1,'theme_version',1,'completion_basis','expert_record','signature_status','prepared_for_signature',
  'source_session_id',sid,'source_session_revision',session.version,'person',person,'scope',scope-'participants','trainers',relevant_trainers,
  'provider_name',session.education->>'provider_name','title',CASE WHEN template='basic_training_certificate' THEN 'TEMEL EĞİTİM BELGESİ' ELSE session.title END,
  'logo_png_base64',logo,'issued_on',issued,'is_draft',true,'number','','revision',0,'document_type',template);
 IF action='preview' AND jsonb_array_length(issues)=0 THEN
  SELECT v.* INTO stored FROM private_isg.documents d JOIN private_isg.document_versions v ON v.document_id=d.document_id AND v.version=d.current_version
   WHERE d.owner_id=actor AND d.company_id=(scope->>'company_id')::uuid AND d.source_domain='training' AND d.template_code=template
   AND d.source_ref=sid::text||':'||scope_id::text||':'||person_id::text AND (v.snapshot->>'source_session_revision')::bigint=session.version;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'ready',true,'issues','[]'::jsonb,'document_id',stored.document_id,'revision',stored.version,'snapshot',stored.snapshot,'snapshot_hash',encode(stored.snapshot_sha256,'hex')); END IF;
 END IF;
 IF action='preview' OR jsonb_array_length(issues)>0 THEN
  RETURN jsonb_build_object('schema_version',1,'owner_id',actor,'ready',false,'issues',issues,'snapshot',snapshot);
 END IF;
 reference:=sid::text||':'||scope_id::text||':'||person_id::text;
 INSERT INTO private_isg.document_templates(template_code,source_domain,title) VALUES(template,'training','Eğitim belgesi') ON CONFLICT DO NOTHING;
 -- This template is approved by the expert issuing it, never by a fabricated reviewer.
 INSERT INTO private_isg.document_template_versions(template_code,version,status,approved_by,approval_note,published_at)
 VALUES(template,1,'published',actor,'EDU-1.0 + user-approved expert-record scope; blank paper signatures',now()) ON CONFLICT DO NOTHING;
 INSERT INTO private_isg.documents(company_id,owner_id,workplace_id,source_domain,source_ref,template_code)
 VALUES((scope->>'company_id')::uuid,actor,(scope->>'workplace_id')::uuid,'training',reference,template)
 ON CONFLICT(company_id,source_domain,source_ref,template_code) DO NOTHING;
 SELECT * INTO doc FROM private_isg.documents WHERE company_id=(scope->>'company_id')::uuid AND source_domain='training' AND source_ref=reference AND template_code=template FOR UPDATE;
 SELECT * INTO stored FROM private_isg.document_versions v WHERE v.document_id=doc.document_id AND v.version=doc.current_version;
 IF FOUND AND (stored.snapshot->>'source_session_revision')::bigint=session.version THEN
  snapshot:=stored.snapshot; new_version:=stored.version;
 ELSE
  year_no:=extract(year FROM issued)::int;
  PERFORM pg_advisory_xact_lock(hashtextextended('education-certificate:'||year_no::text,0));
  INSERT INTO private_isg.education_document_counters(scope,year,next_value)
  SELECT 'EG',year_no,coalesce(max(split_part(document_no,'-',3)::bigint),0)+1 FROM private_isg.document_versions
   WHERE document_no ~ ('^EG-'||year_no::text||'-[0-9]+$') ON CONFLICT DO NOTHING;
  UPDATE private_isg.education_document_counters SET next_value=next_value+1 WHERE education_document_counters.scope='EG' AND year=year_no RETURNING next_value-1 INTO serial;
  number:='EG-'||year_no::text||'-'||serial::text; new_version:=doc.current_version+1;
  snapshot:=snapshot||jsonb_build_object('is_draft',false,'number',number,'revision',new_version);
  INSERT INTO private_isg.document_versions(document_id,version,template_version,document_no,source_kind,snapshot,snapshot_sha256,finalized_by,finalized_at,mutation_id)
  VALUES(doc.document_id,new_version,1,number,'structured',snapshot,sha256(convert_to(snapshot::text,'UTF8')),actor,now(),mutation);
  UPDATE private_isg.documents SET current_version=new_version WHERE documents.document_id=doc.document_id;
 END IF;
 result:=jsonb_build_object('schema_version',1,'owner_id',actor,'ready',true,'issues','[]'::jsonb,'document_id',doc.document_id,'revision',new_version,
  'snapshot',snapshot,'snapshot_hash',encode(sha256(convert_to(snapshot::text,'UTF8')),'hex'));
 INSERT INTO private_isg.education_receipts VALUES(actor,mutation,fingerprint,result);
 RETURN result;
END $$;

-- Keep v2 reads and receipt replay; older writers cannot erase a v3 curriculum.
ALTER FUNCTION private_isg.pilot_training_sessions_save(uuid,jsonb) RENAME TO pilot_training_sessions_save_legacy_v2;
CREATE FUNCTION private_isg.pilot_training_sessions_save(p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
 IF EXISTS(SELECT 1 FROM private_isg.pilot_training_sessions WHERE id=(p_payload->>'id')::uuid AND owner_id=actor AND education IS NOT NULL) THEN RAISE EXCEPTION 'UPGRADE_REQUIRED'; END IF;
 RETURN private_isg.pilot_training_sessions_save_legacy_v2(p_mutation,p_payload);
END $$;
CREATE OR REPLACE FUNCTION public.isg_pilot_training_record_v2(p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.pilot_training_sessions_save(p_mutation,p_payload) $$;
CREATE FUNCTION public.isg_pilot_training_sessions_v3(p_company uuid DEFAULT NULL,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.pilot_training_sessions_read(p_company,p_after)||jsonb_build_object('schema_version',3) $$;
CREATE FUNCTION public.isg_pilot_training_detail_v3(p_id uuid DEFAULT NULL,p_company uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.education_detail(p_id,p_company) $$;
CREATE FUNCTION public.isg_pilot_training_record_v3(p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.education_save(p_mutation,p_payload) $$;
CREATE FUNCTION public.isg_pilot_training_certificate_v1(p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.education_certificate(p_payload) $$;
REVOKE ALL ON FUNCTION private_isg.education_install_package(jsonb),private_isg.education_scope(jsonb,jsonb,jsonb,boolean),
 private_isg.education_detail(uuid,uuid),private_isg.education_save(uuid,jsonb),private_isg.education_certificate(jsonb),
 private_isg.pilot_training_sessions_save_legacy_v2(uuid,jsonb),private_isg.pilot_training_sessions_save(uuid,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.isg_pilot_training_sessions_v3(uuid,uuid),public.isg_pilot_training_detail_v3(uuid,uuid),
 public.isg_pilot_training_record_v3(uuid,jsonb),public.isg_pilot_training_certificate_v1(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION private_isg.education_detail(uuid,uuid),private_isg.education_save(uuid,jsonb),private_isg.education_certificate(jsonb),
 private_isg.pilot_training_sessions_save(uuid,jsonb),public.isg_pilot_training_sessions_v3(uuid,uuid),public.isg_pilot_training_detail_v3(uuid,uuid),
 public.isg_pilot_training_record_v3(uuid,jsonb),public.isg_pilot_training_certificate_v1(jsonb) TO authenticated;
