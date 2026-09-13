# §7.5 modülleri — v1 sunucu sözleşmesi (ilk dört modül paketi)

13 Eylül 2026. P10 çok modüllü bir fazdır; bu dilim **acil durum planı, tatbikat, ekipman/periyodik kontrol, görevlendirme ve KKD teslim/iade** modüllerini kapsar. Kalan on bir modül kendi dilimlerinde gelecek.

Migration: [20260913230000_isg_module_core.sql](../../../supabase/migrations/20260913230000_isg_module_core.sql).

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

## Henüz olmayanlar

Kalan modüller (ISG-KATİP sözleşme takibi, yıllık çalışma planı, yıllık eğitim planı, kurul/karar, onaylı defter arşivi, çalışma izni formu, taşeron paketi, saha ziyareti, evrak merkezi, portföy, ürün rehberliği), belge/PDF üretimi, task/bildirim tetikleyicileri, skor katkısı ve istemci/native yüzey bu dilimde yoktur. `modules` rollout satırı ve beş modül anahtarının tamamı kapalıdır; istemciye GRANT verilmemiştir.
