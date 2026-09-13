# §7.5 modülleri — v1 sunucu sözleşmesi (ilk dört modül paketi)

13–14 Eylül 2026. P10 çok modüllü bir fazdır. İlk paket: **acil durum planı, tatbikat, ekipman/periyodik kontrol, görevlendirme, KKD teslim/iade**. İkinci paket: **ISG-KATİP sözleşme takibi, yıllık çalışma planı, yıllık eğitim planı, kurul/karar, çalışma izni formu, saha ziyareti, onaylı defter arşivi**. Kalan dört başlık (evrak merkezi, taşeron paketi, portföy, ürün rehberliği) P11/P17/P18 kapsamındadır.

Migration'lar: [ilk paket](../../../supabase/migrations/20260913230000_isg_module_core.sql), [ikinci paket](../../../supabase/migrations/20260914010000_isg_module_core_second.sql).

## İki katmanlı anahtar

`modules` rollout satırı **ve** modül başına `module_registry` anahtarı. Bir modülü durdurmak diğerini durdurmaz; `read_enabled` açık, `write_enabled` kapalı ayrı bir salt-okunur durumdur. Kapalı modül `MODULE_UNAVAILABLE`, kapalı faz `FEATURE_UNAVAILABLE` verir.

## Modül kuralları

| Modül | Kural |
|---|---|
| Acil durum planı | Yenileme **yeni sürümdür**: önceki satırın kapsamı, tarihi, ekip snapshot'ı ve dosyası aynen kalır, yalnız `active` işareti devreder. Gerekçe/kaynak notu yoksa kayıt `needs_review` olur |
| Tatbikat | **Planlamak gerçekleştirmek değildir**: planlı kayıtta gerçekleşme tarihi ve katılımcı yoktur. Katılımcılar yalnız o firmanın çalışanları olabilir (`PARTICIPANT_OUT_OF_SCOPE`); sonuç bir kez yazılır |
| Ekipman | Periyot **ekipman türüne** aittir; bütün envantere tek sabit yıl uygulanmaz. Tür kuralı yoksa vade **uydurulmaz** (null) ve inceleme işaretiyle döner. İstisna notu kayıtta görünür; başarısız kontrol yeni dönem açmaz |
| Görevlendirme | Aynı kişi, aynı tür ve aynı kapsamda çakışan iki görevlendirme alamaz (`APPOINTMENT_OVERLAP`, GiST exclusion). Görevin bitişi dönemi serbest bırakır |
| KKD | Miktar pozitif olmak zorunda; teslimden önce iade (`RETURN_BEFORE_HANDOVER`) ve teslim edilenden fazla iade (`RETURN_EXCEEDS_HANDOVER`) reddedilir. **İmzalı kopya varsayılmaz**: `signed_copy` ancak temiz bir belge varsa işaretlenir |

Her modül kendi kanıt dosyasını P04'ün `file_assets` tablosundan alır ve yalnız `scan_status='clean'` bir orijinali kabul eder.

## İkinci paket modülleri

| Modül | Kural |
|---|---|
| ISG-KATİP sözleşme takibi | Resmî entegrasyon iddiası **yapısal olarak imkânsız**: `official_integration` sütunu CHECK ile yalnız `false` olabilir. Boş bitiş tarihi bilinmeyen değil, ayrı bir durumdur (`term_state='open_ended'`) |
| Yıllık çalışma planı | İşyeri+yıl başına tek plan; faaliyetin planlanan tarihi planın **takvim yılında** olmak zorunda (`PLAN_YEAR_MISMATCH`); kayan faaliyet gerekçeli ve **sonraki yıla** taşınır (`CARRY_OVER_INVALID`); planı kapatmak hiçbir maddeyi gerçekleşmiş yapmaz (`items_marked_performed_by_closing: 0`) |
| Yıllık eğitim planı | Bir ihtiyaçtır, tamamlanma değildir (`is_training_completion:false`); mükerrer plan tekil anahtarla engellenir; gerçekleşme P07 eğitim planına **bağlanır**, completion kayıtları oraya ait kalır |
| Kurul/toplantı/karar | `counts_towards_legal_score` yalnız `mandatory` için doğrudur; gönüllü kullanım yasal skora girmez. Katılım bir snapshot'tır: hesap, rol veya portal açılmaz (`creates_account_or_role:false`). Planlı toplantıda katılım/karar yoktur |
| Çalışma izni formu | Bir belgedir; `authorises_work` CHECK ile yalnız `false` olabilir ve tabloda `approved_by`/`approved_at`/`work_started_at` gibi bir sütun yoktur. Durumlar yalnız `draft → rendered → archived` |
| Saha ziyareti/gözlem | Firma kapsamlıdır, kişisel not defteriyle birleşmez; hiçbir sağlık/klinik sütunu yoktur; seçilen gözlem tek bir uygunsuzluk açar |
| Onaylı defter arşivi | Yalnız taranmış imzalı kopya kayıttır (`SIGNED_COPY_REQUIRED`); AI taslağı yalnız köken referansıdır ve `ai_text_is_official_record` CHECK ile yalnız `false` olabilir |

## Henüz olmayanlar

Kalan başlıklar (evrak merkezi P11, taşeron paketi P05/P11, portföy P17, ürün rehberliği P18), belge/PDF üretimi, task/bildirim tetikleyicileri, skor katkısı ve istemci/native yüzey bu dilimde yoktur. `modules` rollout satırı ve **on iki** modül anahtarının tamamı kapalıdır; istemciye GRANT verilmemiştir.
