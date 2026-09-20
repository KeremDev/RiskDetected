# OSGB staging kabul ve gerçek sağlayıcı raporu — 17 Eylül 2026

## Sonuç

OSGB operasyon paketi izole staging projesinde (`qlymhrrlhklcudveknih`) migration `20260917173000` seviyesine taşındı. Üretim projesine (`ppcrzemgiztzcgddbins`) migration, veri veya rollout yazımı yapılmadı. Admin migration'ı ve admin arayüzü, kararlaştırıldığı gibi UI kit sonrasına bırakıldı.

Üretim migration ledger'ı salt okunur sorguda `20260916090922` seviyesindedir ve `20260917090000` sonrası OSGB migration sayısı `0` olarak doğrulandı.

Staging kabul koşusu gerçek bir Auth kullanıcısı, OSGB workspace'i ve firma oluşturdu. D1–D9 okuma sınırları, D1/D2 ileri tenant modülleri, dashboard, özel object storage, gerçek Gemini çağrısı, analiz commit'i ve gerçek PDF/XLSX üretimi aynı tenant kapsamında başarıyla tamamlandı. Tekrarlanabilir koşu [run_osgb_staging_acceptance.mjs](../../scripts/isg/run_osgb_staging_acceptance.mjs) içindedir; üretim ref'ini açıkça reddeder.

## Uygulanan düzeltmeler

- AI, export ve bildirim kuyrukları lease/token kontrollü service-role worker'a bağlandı.
- Fotoğraf/belge kaynağı bulunmayan AI işi sağlayıcı başlamadan `SOURCE_NOT_FOUND` ile kapanır ve rezervasyon serbest bırakılır.
- Gemini JSON'u finansal settlement ve analiz commit'inden önce sunucu sözleşmesine normalize edilir. Enum, sayı, metin sınırı ve kaynak-bulgu bağlantıları doğrulanır.
- Deno'daki `xlsx-js-style` CommonJS aktarımı düzeltildi; PDF ve XLSX staging'de gerçek object olarak üretildi.
- Storage finalize/download worker wrapper'ları private şemaya güvenli geçiş için owner-executing hale getirildi; çağrı hakkı yalnız service role'dedir.
- RevenueCat OSGB webhook'u purchase-intent bağını doğrular; mismatch durumunda personal abonelik akışına düşmez.
- OSGB bildirim türleri gerçek push sağlayıcısı sözleşmesine eklendi.
- Worker her dakika `pg_cron` ile çağrılır; staging'de başarılı cron çalışmaları doğrulandı.

## Staging kanıtı

| Kontrol | Sonuç |
|---|---|
| Migration | `20260917173000` |
| Rollout | 12 operasyon özelliği ve 9 domain staging'de açık; `workspace_admin` kapalı |
| Tenant | QA OSGB workspace + firma oluşturuldu ve geri okundu |
| D1–D9 | Personel, eğitim, risk, uygunsuzluk, checklist, acil durum/KKD, ekipman, operasyon, dosya, analiz/export ve dashboard geçti |
| D1/D2 ileri | Görev/dış firma/atama ve müfredat/plan/sınav/sertifika uçları geçti |
| Storage | Kullanıcı upload intent → private object → byte/hash inceleme → finalize → token download; SHA-256 eşleşti |
| AI | `gemini-2.5-flash` gerçek çağrı; job `succeeded`, analiz görünür |
| Export | PDF ve XLSX job'ları `succeeded`; iki çıktı private bucket'ta active asset |
| Worker | Secret-auth Edge Function aktif; cron kaydı tek ve başarılı çalışma geçmişi var |
| Android gate | QA `versionCode=14` altı runtime kapısında yalnız staging allowlist'ine alındı; policy yanıtında 6/6 kapı açık |
| Android cihaz | API 33 emülatöründe cold launch, onboarding, e-posta OTP, gerçek staging oturumu, OSGB workspace/firma/D1–D9/D1–D2 ve analiz detayı geçti; crash/ANR yok |
| Android export | Analiz detayından PDF isteği kuyruğa alındı ve gerçek worker sonrasında `succeeded` oldu |

Son başarılı sentetik kabul workspace'i `012f720c-c1e9-448d-b4f1-bb70e33324e4`, firması `e72de7a5-b9a0-4172-baa5-5c4cf9fb986d` kimliğindedir. QA hesap bilgileri yalnız yerel `/tmp/isg-staging-qa-credentials.json` dosyasında `0600` izniyle tutulur; repoya veya bu rapora parola/token yazılmadı.

## Android ürün arayüzü

Android ürün kökü profil menüsünden yalnız kullanıcının aktif OSGB üyeliği varsa görünür. Workspace ve firma seçimi, firma dashboard'u, standart istatistik kartları, tüm operasyon başlıkları, D1/D2 ileri kayıtları, boş/hata durumları ve kayıt detayları Nova tasarım sistemiyle bağlandı. Analiz detayında risk/uzman/eğitim sayaçları ile PDF ve Excel raporu hazırlama eylemleri bulunur. Personal kullanıcı OSGB üyeliği yoksa yeni kökü görmez ve eski akışını kullanır.

`assembleQa`, `core:data` testleri, `feature:profile` testleri ve uygulama Kotlin derlemesi geçti. QA APK API 33 emülatörüne kuruldu. İlk açılışta staging runtime allowlist'inin yalnız eski build 2/3'ü kabul ettiği saptandı; kabul koşusu güvenlik önkoşullarını denetleyerek yalnız build 14'ü altı kapıya ekleyecek şekilde düzeltildi. Sonrasında uygulama cold launch, onboarding, e-posta OTP, gerçek staging oturumu, OSGB alanı, firma operasyon listeleri, D1/D2 ileri kayıtları ve gerçek Gemini analiz detayıyla açıldı. Analiz detayı 2 risk, 1 uzman görüşü ve 2 eğitim önerisini gösterdi; Android'den oluşturulan PDF işi worker sonrasında `succeeded` oldu. Logcat'te crash veya ANR yoktur.

## Sağlayıcı durumu

Gemini, Supabase Storage, PDF, XLSX ve cron worker staging üzerinde gerçek çağrıyla doğrulandı. FCM/APNs adaptörü gerçek staging kimliğiyle deploy edildi, ancak bağlı bir cihaz token'ı bulunmadığından gerçek cihaza teslim kanıtı üretilemedi. RevenueCat webhook'u ve purchase-intent doğrulaması deploy/test edildi; gerçek Apple/Google sandbox satın alması kullanıcı hesabı, mağaza ürünü ve fiziksel cihaz işlemi gerektirdiği için bu koşuda satın alma yapılmadı. Bu iki satır kod eksiği değildir; dış cihaz/mağaza kabul adımıdır.

## Yayın kararı

Staging operasyon ve gerçek AI/object/export kabulü **geçti**. Üretim rollout'u hâlâ kapalı tutulmalıdır. Üretim kabulünden önce kalan dış adımlar:

1. QA APK ile fiziksel Android cihazda giriş, OSGB gezinme ve özellikle dosya paylaşımı/indirme davranışı.
2. Test cihaz token'ıyla FCM/APNs teslimi.
3. Apple/Google sandbox ürünüyle RevenueCat purchase, restore, refund/revoke senaryosu.
4. Kullanıcının sağlayacağı UI kit ile admin frontend ve admin migration kabulü.

Bu adımlar staging kanıtını geçersiz kılmaz; üretim mağaza/cihaz kanıtı olmadan “production canlı kabulü tamamlandı” denmez.
