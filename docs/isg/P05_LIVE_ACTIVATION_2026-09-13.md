# P05 canlı pilot açılışı — 13 Eylül 2026

## Son durum

Kullanıcının telefon build’i tesliminden sonra verdiği **“evet” canlı pilot onayı** üzerine P05 dar paketi canlıya kuruldu. Daha önce doğrulanan tek hesabın okuma/yazma erişimi **20 Eylül 2026 23:11:47 Türkiye saati** sonuna kadar açıldı (7 gün). Süre bitince sunucu erişimi kendisi reddeder; uzatma veya genel dağıtım yapılmadı.

Telefondaki **2.0.3 (91) özel NOVA build’i** değişmedi. Uygulama tekrar öne getirildiğinde veya “Pilot erişimini tekrar kontrol et” kullanıldığında yeni erişimi alabilir. **Firmalar → Yeni pilot firma** yolunda kullanıcı firma adını ve tehlike sınıfını kendisi girecek. Mevcut iki firması otomatik pilota alınmadı. Yeni firma mevcut normal kotayı kullanır: açılış kontrolünde Plus / 5 aktif firma limiti / 2 aktif firma.

## Tamamlanan işlemler

1. Güncel üretim durumu yeniden okundu: İSG şeması yok, migration head `20260908134026`, toplam 8 firma. Hesap onaylı/banlı veya anonim değil; plan ve daha sonra paid write subscription uygunluğu doğrulandı.
2. Yeni **read-only tutarlı veritabanı arşivi** alındı: `backups/isg-p05-predeploy-gnaPHU/predeploy.dump`. `public/private/auth/storage/supabase_migrations` şema ve verileri; klasör 0700, dosyalar 0600. SHA256 `1b9e3b568ce51e174a0a49cb5e988dd8c84e23cbef30ff95b2c7949b0b4b6e99`. Arşivin tamamı pg_restore ile SQL çalıştırılmadan okunup doğrulandı. **Bu yeni arşivle tam restore testi yapılmadı; Storage dosyaları ve tüm yönetilen proje ayarlarını kapsamaz.** Önceki tam checkpoint/izole restore kanıtları korunur. Arşiv kişisel veri/gizli function ayarları içerebilir; paylaşma/commit etme.
3. İncelenmiş altı kaynaklı paket izole legacy klonda yeniden sınandı. Canlıya gönderilecek birebir release SQL’i de aynı klonda transaction içinde uygulanıp **ROLLBACK** edildi. 29 kontrol PASS; eski kaynak/veriler korunmuş ve disposable cleanup PASS. Kanıt: `backups/isg-auth-service-restore-20260912-G56sDA/REPORT.json`. Release transport testleri dahil ilgili 10 Node testi PASS.
4. `scripts/isg/p05_pilot_release.mjs` ile hazırlanan payload migration servisi üzerinden kapalı kuruldu. Kaynak bundle hash’i pinlidir; yalnız dış transaction migration servisine devredilir, deployment lock timeout 1s/statement timeout 15s yapılır, baseline ve postflight koşulları eklenir. Yeni global firma hook’u transaction bitmeden kaldırılır; eski firmalara başlangıç kaydı eklenmez.
5. Canlı migration ledger: **`20260913201043_isg_p05_scoped_pilot_bundle`**. Kaydedilen SQL SHA256 `ec13ed26fbc180e44a8b59c39488b80592b45280d6771830361059d8166d9a3d`; yerel audit mirror ile birebir eşleşti: `supabase/pilot-release/supabase/migrations/20260913201043_isg_p05_scoped_pilot_bundle.sql`.
6. Kapalı kurulum doğrulandıktan sonra tek account kaydı 7 günlük **read-only** açıldı; public availability RPC’si mevcut geçerli Auth session kullanılarak authenticated SQL rolünde çalıştırılıp transaction geri alındı. Bu test gerçek telefon JWT/gateway testi değildir; session/token dışarı çıkarılmadı ve yeni oturum üretilmedi.
7. Ayrı guarded transaction ile yalnız bu hesabın `write_enabled` alanı ve `personnel` global read/write kapısı açıldı. Global kapı **tek başına erişim sağlamaz**: hesap, süre, yeni firma origin/grant, owner, güncel session, arşiv, plan/kota kontrolleri ayrıca zorunludur. `approved_reference=user-approved-p05-20260913-20260913201043`.

## Canlı son kontroller

- 18 private tablo, tamamında RLS; `PUBLIC/anon/authenticated/service_role` doğrudan tablo DML grant’i **0**.
- İzinli hesap **1**, eski firma grant’i **0**, oluşturulmuş pilot firma origin’i **0**. Bu koşum kullanıcı adına gerçek firma/personel oluşturmadı.
- Mevcut 8 firmanın tüm satırlarının sıralı MD5 özeti **kurulum öncesi ve sonrası aynı**: `72a4f382d384701a5b2ddb45e99a1e12`.
- Legacy plan/kota/write-trigger function özeti aynı: `e61b8d817d8917fdb99d2f44364b8414`; yeni global company hook **0**.
- Hesabın mevcut firmaları pilot read kontrolünden geçmiyor; pilot dışı kimlik write gate’den geçmiyor.
- Gerçek gateway: Auth health **200**; oturumsuz availability ve create RPC çağrıları **401 / 42501**. Create negatif çağrısında null parametreler kullanıldı, firma oluşturulmadı.
- Son gözlemde DB’de bekleyen lock **0**. Bu tek gözlem kesintisizlik/SLA veya mutlak sıfır etki garantisi değildir.
- Güvenlik advisor farkı: **yeni ERROR 0, yeni WARN 0**, yeni private RLS tabloları için 18 INFO (policy yok; erişim bilerek checked RPC üzerinden, tablo grant’i yok). Önceden mevcut 8 public SECURITY DEFINER çağrı uyarısı ve leaked-password protection uyarısı korunuyor; bu pilot kapsamında değiştirilmedi.
- P06+ worker/kampanya/bildirim/ödeme rollout’u ve genel UI dağıtımı açılmadı. Paylaşılan DB/DDL/yük sebebiyle mutlak sıfır etki garantisi verilmez; kapsam/timeout/expiry/kapalı kurulum bunu sınırlar.

## Geri kapatma ve migration disiplini

`supabase/pilot-release/disable_pilot.sql` manuel acil geri kapatma dosyasıdır; **çalıştırılmadı**. Account read/write kapatılır ve revoked_at set edilir; başka etkin pilot yoksa personnel global kapısı da kapanır. Firma/personel verilerini veya şemayı silmez. SQL timeout/lock nedeniyle başarısız olursa sonucu kontrol etmeden kapandı deme.

**Ana migration klasörünü canlıya toplu push etme.** Altı orijinal P05 candidate dosyası hâlâ geliştirme/test kaynaklarıdır; tek birleşik canlı migration’ın yerine ledger’da uygulanmış gibi işaretlenmediler. Ana klasörde P06+ uygulanmamış adaylar da vardır. Sonraki production release öncesi bu canlı baseline’dan migration zinciri açıkça uzlaştırılmalı ve prova edilmelidir. Audit mirror klasörü otomatik deployment projesi değildir.

## Açık kalan kullanıcı kabulü

- Kullanıcının telefonda normal giriş → yeni firma oluşturma → liste → personel/işyeri kaydı akışını denemesi. Bu tur gerçek telefon oturumuyla başarılı create yapılmış gibi kabul verilmedi.
- Gerçek legacy writer ile eşzamanlı kota yarışı ve fault testi; uzun/arşivli listede dedicated pilot-list RPC/pagination; plan düşüşünde legacy liste RLS davranışı.
- Firma ek alanları/düzenleme/arşivleme sözleşmesi, yeni pilot metinlerinin EN kataloğu, fiziksel form/klavye/erişilebilirlik ve diğer fazların gerçek UI bağlantıları.

UI iterasyonu devam eder. Pilot açılışı P19 yayın kapısını kapatmaz; `release_ready=false`, App Store/TestFlight yayını yapılmadı.
