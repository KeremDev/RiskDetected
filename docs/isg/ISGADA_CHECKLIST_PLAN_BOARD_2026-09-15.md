# Kontrol listeleri, çalışma planı ve kurul bağlantıları — 15 Eylül 2026

## Teslim edilen davranış

- Kontrol başlat düğmesi firma araması, firma seçimi, işyeri, yayımlanmış liste ve tarih alanlarını aynı dinamik popup içinde açar. Firma içinden açılışta firma sabittir. Başlatma tamamlandığında kontrol cevap ekranı açılır.
- Listelerim üzerinden mevcut soru ekleme/düzenleme/silme ve uzman yayımlama akışı korunur. Yayımlanmamış liste kontrol başlatmada sunulmaz. Ürün adına hazır veya yasal uygunluğu doğrulanmış bir liste üretilmez.
- Tamamlanan kontrol aynı firmanın çalışma planı faaliyetine, kurul kararına veya saha gözlemine ilgili kayıt olarak bağlanabilir. Açık kontrol tamamlanmış kaynak seçicisinde görünmez.
- Plan ve toplantı kartlarında alt kayıtların toplam/açık/gecikmiş sayıları gösterilir. Faaliyet veya karar değişikliğinin ardından ana kart yeniden okunur.
- Kontrol listeleri firma/ana sayfa/istatistik modül takibine eklendi: toplam ve açık kontrol sayısı. Kontrollerin son tarihi olmadığından yapay gecikme tarihi üretilmez.
- Başarılı kayıt işlemleri mevcut hesap kapsamlı değişiklik bildirimiyle takip kartlarını yeniler. Kayıt bağlantısı faaliyet veya kararı otomatik tamamlamaz; bildirim planlayıcısı/push servisi değildir.
- Mevcut plan/kurul ekleme, düzenleme, silme, firma evrakı bağlama ve PDF/Excel çıktısı servisleri korunmuştur. Pilot ana menü süreç ekranları yazma yetkisini üst denetleyiciden alır.

## Doğrulama

- `node scripts/modules/run_pilot.mjs`: PASS. Mevcut modül CRUD, çıktı, tekrar gönderim, sahiplik, çapraz kaynak ve risk regresyonları ile yeni kontrol → plan/kurul bağlantısı ve alt kayıt sayaçları.
- Yeni `scripts/modules/checklist_plan_board_check.sql`: kontrol başlat/cevapla/tamamla, açık kontrolü kaynak listesinden çıkarma, tamamlanan kontrolü bağlama, faaliyet durumunu değiştirmeme, gerçekleşmenin sayaca yansıması, kurul gecikmesi, 13 takip kategorisi ve başka firma reddi.
- Canlı yetkili pilot firma kapsamında salt okunur kontrol: kontrol referansları, plan ve kurul okumaları, 13 takip kategorisi PASS. İlk genel firma seçimi pilot kapsamı dışında olduğundan ACCESS_DENIED verdi; pilot kapsamındaki firma ile tekrar doğrulandı. Yetki gevşetilmedi.
- Değişen Swift dosyaları `swiftc -frontend -parse`: PASS; `git diff --check`: PASS. Bunlar tam derleme değildir.
- Tam iOS derlemesi ve cihaz kabulü bekliyor: makinede Xcode lisans onayı gerekiyor. Bu teslim için telefona yeni build yüklenmiş değildir.

## Canlı migration

- Aday: `supabase/migrations/20260915090002_isg_pilot_checklist_plan_board.sql`
- Canlı ledger ve aynası: `supabase/pilot-release/supabase/migrations/20260914230601_isg_pilot_checklist_plan_board.sql`
- SHA-256: `b771ed085274d036f0801036b3948fab16a98d8e7e4f155b072e814f7373d0aa`
- Dar migration uygulandı; ana migration klasörü topluca uygulanmadı.
- `annual_work_plan`, `board`, `modules`, `nonconformity` okuma/yazma bayrakları canlıda açık.
