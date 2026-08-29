-- Seed the standards registry from the assurance playbook.
--
-- The four registry tables have existed since the result-hub migration and have
-- carried zero rows the whole time. So `analysis_item_standard_links` was never
-- populated, `reference_text_generated` was null on every notebook draft, and
-- the reference lines readers actually see came from string literals inside
-- assurance-playbook.ts. Two reference paths, one of them dead.
--
-- This moves the 46 distinct references out of the code and into the registry
-- where they can carry a status, a rights position and a verification date.
--
-- EVERYTHING LANDS AS status='draft', source_rights='unverified',
-- last_verified_at=null, and every applicability rule is is_active=false.
--
-- That is deliberate and it is the honest state. Phase 0 of the approved-book
-- plan -- a specialist confirming each source's scope and currency -- has not
-- happened, and this migration is not that review. A resolver must treat draft
-- and unverified as unrenderable, so seeding these rows changes no output
-- today; it only gives the review something to act on. Marking them active
-- would be exactly the unearned claim the feature exists to prevent.
--
-- Regenerate rather than hand-edit: the id slugs are derived from the titles.
-- generated: do not hand-edit; regenerate from assurance-playbook.ts
insert into private.standards_registry
  (id, source_family, title, jurisdiction_profile_id, source_rights, status, metadata)
select s.id, s.fam, s.title, 'tr-current', 'unverified', 'draft',
       jsonb_build_object('imported_from', 'assurance-playbook.ts')
from (values
  ('api-510', 'api_standard', 'API 510 — Basınçlı kaplarda muayene'),
  ('api-570', 'api_standard', 'API 570 — Proses borulamasında muayene ve değerlendirme'),
  ('api-653', 'api_standard', 'API 653 — Atmosferik depolama tanklarında muayene, onarım ve değiştirme'),
  ('basincli-ekipmanlar-yonetmeligi', 'tr_regulation', 'Basınçlı Ekipmanlar Yönetmeliği (2014/68/AB)'),
  ('binalarin-yangindan-korunmasi-hakkinda-yonetmelik', 'tr_regulation', 'Binaların Yangından Korunması Hakkında Yönetmelik'),
  ('biyolojik-etkenlere-maruziyet-risklerinin-onlenmesi-hakkinda', 'tr_regulation', 'Biyolojik Etkenlere Maruziyet Risklerinin Önlenmesi Hakkında Yönetmelik'),
  ('elektrik-kuvvetli-akim-tesisleri-yonetmeligi', 'tr_regulation', 'Elektrik Kuvvetli Akım Tesisleri Yönetmeliği'),
  ('elektrik-tesislerinde-topraklamalar-yonetmeligi', 'tr_regulation', 'Elektrik Tesislerinde Topraklamalar Yönetmeliği'),
  ('elektrik-ic-tesisleri-yonetmeligi', 'tr_regulation', 'Elektrik İç Tesisleri Yönetmeliği'),
  ('kimyasal-maddelerle-calismalarda-saglik-ve-guvenlik-onlemler', 'tr_regulation', 'Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik'),
  ('kisisel-koruyucu-donanimlarin-isyerlerinde-kullanilmasi-hakk', 'tr_regulation', 'Kişisel Koruyucu Donanımların İşyerlerinde Kullanılması Hakkında Yönetmelik'),
  ('maddelerin-ve-karisimlarin-siniflandirilmasi-etiketlenmesi-v', 'tr_regulation', 'Maddelerin ve Karışımların Sınıflandırılması, Etiketlenmesi ve Ambalajlanması Hakkında Yönetmelik (SEA)'),
  ('makina-emniyeti-yonetmeligi', 'tr_regulation', 'Makina Emniyeti Yönetmeliği (2006/42/AT)'),
  ('nfpa-652', 'nfpa_standard', 'NFPA 652 — Yanıcı toz tehlikelerinin temel esasları'),
  ('ts-8853', 'ts_standard', 'TS 8853 — Zemin işleri ve iksa uygulamaları'),
  ('ts-en-1037', 'ts_standard', 'TS EN 1037 — Makinelerde beklenmeyen çalışmaya karşı önlemler'),
  ('ts-en-12811-1', 'ts_standard', 'TS EN 12811-1 — Geçici iş donanımı: iş iskeleleri'),
  ('ts-en-13155', 'ts_standard', 'TS EN 13155 — Vinçler: ayrılabilir yük kaldırma donanımı'),
  ('ts-en-13374', 'ts_standard', 'TS EN 13374 — Geçici kenar koruma sistemleri'),
  ('ts-en-1677', 'ts_standard', 'TS EN 1677 — Kaldırma aksesuarları: dövme çelik parçalar ve kancalar'),
  ('ts-en-3', 'ts_standard', 'TS EN 3 — Taşınabilir yangın söndürücüler'),
  ('ts-en-60079-10-2', 'ts_standard', 'TS EN 60079-10-2 — Patlayıcı ortamlar: yanıcı toz ortamlarının sınıflandırılması'),
  ('ts-en-60204-1', 'ts_standard', 'TS EN 60204-1 — Makinelerde elektrik donanımı'),
  ('ts-en-795', 'ts_standard', 'TS EN 795 — Ankraj cihazları'),
  ('ts-en-853-ts-en-856', 'ts_standard', 'TS EN 853 / TS EN 856 — Kauçuk hortumlar: tel örgülü ve tel sarımlı hidrolik hortumlar'),
  ('ts-en-iso-12100', 'ts_standard', 'TS EN ISO 12100 — Makinelerde risk değerlendirmesi ve risk azaltma'),
  ('ts-en-iso-13850', 'ts_standard', 'TS EN ISO 13850 — Acil durdurma işlevi'),
  ('ts-en-iso-14118', 'ts_standard', 'TS EN ISO 14118 — Beklenmeyen çalıştırmanın önlenmesi'),
  ('ts-en-iso-14119', 'ts_standard', 'TS EN ISO 14119 — Koruyucularla ilgili kilitleme tertibatları'),
  ('ts-en-iso-14120', 'ts_standard', 'TS EN ISO 14120 — Koruyucular: sabit ve hareketli koruyucuların tasarımı'),
  ('ts-en-iso-4413', 'ts_standard', 'TS EN ISO 4413 — Hidrolik akışkan gücü: sistemler için genel kurallar'),
  ('ts-en-iso-4414', 'ts_standard', 'TS EN ISO 4414 — Pnömatik akışkan gücü: sistemler için genel kurallar'),
  ('ts-iso-12480-1', 'ts_standard', 'TS ISO 12480-1 — Vinçlerin güvenli kullanımı'),
  ('ts-iso-3691', 'ts_standard', 'TS ISO 3691 — Endüstriyel araçlar: güvenlik kuralları'),
  ('yapi-islerinde-is-sagligi-ve-guvenligi-yonetmeligi', 'tr_regulation', 'Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği — kazı işleri'),
  ('yapi-islerinde-is-sagligi-ve-guvenligi-yonetmeligi-2', 'tr_regulation', 'Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği — yüksekte çalışma ve kenar koruması'),
  ('zararli-maddeler-ve-karisimlara-iliskin-guvenlik-bilgi-forml', 'tr_regulation', 'Zararlı Maddeler ve Karışımlara İlişkin Güvenlik Bilgi Formları Hakkında Yönetmelik'),
  ('calisanlarin-patlayici-ortamlarin-tehlikelerinden-korunmasi-', 'tr_regulation', 'Çalışanların Patlayıcı Ortamların Tehlikelerinden Korunması Hakkında Yönetmelik'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y', 'tr_regulation', 'İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-2', 'tr_regulation', 'İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — bakım ve onarım güvenliği'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-3', 'tr_regulation', 'İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — basınçlı ekipman periyodik kontrolleri'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-4', 'tr_regulation', 'İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — elektrik tesisatı periyodik kontrolü'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-5', 'tr_regulation', 'İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — kaldırma ekipmanlarında periyodik kontrol'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-6', 'tr_regulation', 'İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği — periyodik kontroller'),
  ('isyeri-bina-ve-eklentilerinde-alinacak-saglik-ve-guvenlik-on', 'tr_regulation', 'İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik — geçiş yolları'),
  ('isyerlerinde-acil-durumlar-hakkinda-yonetmelik', 'tr_regulation', 'İşyerlerinde Acil Durumlar Hakkında Yönetmelik')
) as s(id, fam, title)
on conflict (id) do nothing;

insert into private.standard_applicability_rules
  (standard_id, module_id, condition_codes, item_classes, rule, is_active)
select r.sid, r.mod, '{}'::text[],
       array['assurance_requirement', 'verification_request'],
       jsonb_build_object('assurance_topic_id', r.topic), false
from (values
  ('api-510', 'process_integrity', 'process_containment_integrity'),
  ('api-570', 'process_integrity', 'process_containment_integrity'),
  ('api-653', 'process_integrity', 'process_containment_integrity'),
  ('basincli-ekipmanlar-yonetmeligi', 'process_integrity', 'hose_assembly_integrity'),
  ('basincli-ekipmanlar-yonetmeligi', 'process_integrity', 'process_containment_integrity'),
  ('binalarin-yangindan-korunmasi-hakkinda-yonetmelik', 'fire_explosion_release', 'fire_emergency_readiness'),
  ('binalarin-yangindan-korunmasi-hakkinda-yonetmelik', 'hot_work', 'hot_work_controls'),
  ('biyolojik-etkenlere-maruziyet-risklerinin-onlenmesi-hakkinda', 'biosecurity', 'biosecurity_controls'),
  ('elektrik-kuvvetli-akim-tesisleri-yonetmeligi', 'electrical', 'electrical_internal_integrity'),
  ('elektrik-tesislerinde-topraklamalar-yonetmeligi', 'electrical', 'electrical_internal_integrity'),
  ('elektrik-ic-tesisleri-yonetmeligi', 'electrical', 'electrical_internal_integrity'),
  ('kimyasal-maddelerle-calismalarda-saglik-ve-guvenlik-onlemler', 'chemical', 'chemical_identity_and_exposure'),
  ('kisisel-koruyucu-donanimlarin-isyerlerinde-kullanilmasi-hakk', 'biosecurity', 'biosecurity_controls'),
  ('kisisel-koruyucu-donanimlarin-isyerlerinde-kullanilmasi-hakk', 'confined_space', 'confined_space_controls'),
  ('kisisel-koruyucu-donanimlarin-isyerlerinde-kullanilmasi-hakk', 'falls_falling_objects', 'working_at_height_access'),
  ('kisisel-koruyucu-donanimlarin-isyerlerinde-kullanilmasi-hakk', 'work_at_height', 'working_at_height_access'),
  ('maddelerin-ve-karisimlarin-siniflandirilmasi-etiketlenmesi-v', 'chemical', 'chemical_identity_and_exposure'),
  ('makina-emniyeti-yonetmeligi', 'machinery', 'machine_protective_systems'),
  ('nfpa-652', 'combustible_dust', 'combustible_dust_controls'),
  ('ts-8853', 'excavation', 'excavation_stability_controls'),
  ('ts-en-1037', 'energy', 'energy_isolation_controls'),
  ('ts-en-12811-1', 'falls_falling_objects', 'working_at_height_access'),
  ('ts-en-12811-1', 'work_at_height', 'working_at_height_access'),
  ('ts-en-13155', 'lifting', 'lifting_inspection'),
  ('ts-en-13374', 'falls_falling_objects', 'working_at_height_access'),
  ('ts-en-13374', 'work_at_height', 'working_at_height_access'),
  ('ts-en-1677', 'lifting', 'lifting_inspection'),
  ('ts-en-3', 'fire_explosion_release', 'fire_emergency_readiness'),
  ('ts-en-60079-10-2', 'combustible_dust', 'combustible_dust_controls'),
  ('ts-en-60204-1', 'electrical', 'electrical_internal_integrity'),
  ('ts-en-60204-1', 'machinery', 'machine_protective_systems'),
  ('ts-en-795', 'falls_falling_objects', 'working_at_height_access'),
  ('ts-en-795', 'work_at_height', 'working_at_height_access'),
  ('ts-en-853-ts-en-856', 'process_integrity', 'hose_assembly_integrity'),
  ('ts-en-iso-12100', 'machinery', 'machine_protective_systems'),
  ('ts-en-iso-13850', 'machinery', 'machine_protective_systems'),
  ('ts-en-iso-14118', 'energy', 'energy_isolation_controls'),
  ('ts-en-iso-14119', 'machinery', 'machine_protective_systems'),
  ('ts-en-iso-14120', 'machinery', 'machine_protective_systems'),
  ('ts-en-iso-4413', 'process_integrity', 'hose_assembly_integrity'),
  ('ts-en-iso-4414', 'process_integrity', 'hose_assembly_integrity'),
  ('ts-iso-12480-1', 'lifting', 'lifting_inspection'),
  ('ts-iso-3691', 'logistics', 'mobile_equipment_controls'),
  ('ts-iso-3691', 'vehicles_mobile_equipment', 'mobile_equipment_controls'),
  ('yapi-islerinde-is-sagligi-ve-guvenligi-yonetmeligi', 'excavation', 'excavation_stability_controls'),
  ('yapi-islerinde-is-sagligi-ve-guvenligi-yonetmeligi-2', 'falls_falling_objects', 'working_at_height_access'),
  ('yapi-islerinde-is-sagligi-ve-guvenligi-yonetmeligi-2', 'work_at_height', 'working_at_height_access'),
  ('zararli-maddeler-ve-karisimlara-iliskin-guvenlik-bilgi-forml', 'chemical', 'chemical_identity_and_exposure'),
  ('calisanlarin-patlayici-ortamlarin-tehlikelerinden-korunmasi-', 'combustible_dust', 'combustible_dust_controls'),
  ('calisanlarin-patlayici-ortamlarin-tehlikelerinden-korunmasi-', 'confined_space', 'confined_space_controls'),
  ('calisanlarin-patlayici-ortamlarin-tehlikelerinden-korunmasi-', 'hot_work', 'hot_work_controls'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y', null, 'asset_assurance_generic'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y', 'confined_space', 'confined_space_controls'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y', 'logistics', 'mobile_equipment_controls'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y', 'vehicles_mobile_equipment', 'mobile_equipment_controls'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-2', 'energy', 'energy_isolation_controls'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-3', 'process_integrity', 'hose_assembly_integrity'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-4', 'electrical', 'electrical_internal_integrity'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-5', 'lifting', 'lifting_inspection'),
  ('is-ekipmanlarinin-kullaniminda-saglik-ve-guvenlik-sartlari-y-6', 'process_integrity', 'process_containment_integrity'),
  ('isyeri-bina-ve-eklentilerinde-alinacak-saglik-ve-guvenlik-on', 'logistics', 'mobile_equipment_controls'),
  ('isyeri-bina-ve-eklentilerinde-alinacak-saglik-ve-guvenlik-on', 'vehicles_mobile_equipment', 'mobile_equipment_controls'),
  ('isyerlerinde-acil-durumlar-hakkinda-yonetmelik', 'fire_explosion_release', 'fire_emergency_readiness'),
  ('isyerlerinde-acil-durumlar-hakkinda-yonetmelik', 'hot_work', 'hot_work_controls')
) as r(sid, mod, topic);

do $$
declare
  v_standards integer;
  v_rules integer;
  v_active integer;
begin
  select count(*) into v_standards from private.standards_registry;
  select count(*) into v_rules from private.standard_applicability_rules;
  select count(*) into v_active from private.standards_registry
    where status <> 'draft' or source_rights <> 'unverified';

  if v_standards < 40 then
    raise exception 'standards registry seed did not land: % rows', v_standards;
  end if;
  if v_rules < 40 then
    raise exception 'applicability rule seed did not land: % rows', v_rules;
  end if;
  -- Nothing here may present itself as verified before a specialist says so.
  if v_active <> 0 then
    raise exception '% standard rows claim a status this migration cannot grant', v_active;
  end if;
end $$;
