# Android Release Kalan İşler

Son güncelleme: 11 Ağustos 2026
Hedef sürüm: `1.5.0`
Package ID: `com.riskdetectedan.app`
Referans iOS sürümü: `app-store-live-1.3.1-build-81-baseline-2026-08-06`

Bu dosya Android production yayını öncesindeki açık işleri, bağımlılıklarını ve kabul ölçütlerini takip eder. `App/` altındaki iOS kaynakları değiştirilmeyecek; production Android runtime kapıları kontrollü canary başlayana kadar kapalı tutulacaktır.

## Mevcut doğrulanmış durum

- [x] Staging Firebase Android uygulamaları ve FCM servis hesabı yapılandırıldı.
- [x] FCM foreground, background ve killed durumlarında gerçek teslimat doğrulandı.
- [x] Bildirim deep-link'i ile Profil rotası doğrulandı.
- [x] Staging Google OAuth client ve provider yapılandırması tamamlandı.
- [x] Gerçek e-posta OTP giriş akışı doğrulandı.
- [x] Android v1 için Apple OAuth kullanıcı akışından çıkarıldı; iOS sistemi değiştirilmedi.
- [x] RevenueCat Android uygulaması, `default` offering ve `plus`/`pro` entitlement'ları doğrulandı.
- [x] Staging `qa_test_store` offering'i üzerinden Plus, Pro, restore ve webhook akışları doğrulandı.
- [x] RSA-4096 upload key ve GitHub CI signing secret'ları hazırlandı.
- [x] Bilinen production public değerleri CI environment'a eklendi.
- [x] Gerçek fotoğrafla standart analiz, sonuç ekranı ve bulgular doğrulandı.
- [x] Cihazda PDF ve sunucuda XLSX üretimi doğrulandı; gerçek PDF sayfa sayısı backend'e kaydedildi.
- [x] Android analiz insert yetki hatası ve platform/build telemetrisi düzeltildi.
- [x] Unit test, lint, environment isolation ve debug build kalite kapıları geçti.
- [x] Temiz kaynaklardan minified QA APK/AAB yeniden üretildi; `bundletool`, JAR imzası, 16 KB hizalama ve secret/PII taramaları geçti.
- [x] Temiz QA AAB içinde `.xcassets`, `AppIcon.appiconset` veya `Contents.json` bulunmadığı doğrulandı.
- [x] Yeni launcher ikonunu içeren temiz QA AAB (`SHA-256 a61cb977a909b53d7150080334a8ac9c5a6f8864b67e817fad10b12f38a228a7`) bundletool, JAR imzası, 16 KB/ELF ve QA Firebase allowlist doğrulamasından geçti; QA APK hash'i `011a57af4b4230ceecb7bd8e614e067073054d80fb86e2a4d28a853b970b4c34`, native symbol paketi hash'i `13f93498c65e6a23f7327b62e52b2c62e7c017a0ec0dc5f1aeac2d2fd8a798a1`.
- [x] Deno Edge Function paketi `316/316`, pgTAP/RLS/RPC paketi `485/485` geçti; local DB lint sonucu sıfır hata.
- [x] Android staging'e dört additive migration ve repo kaynaklı 20 Edge Function dağıtıldı; uzak hash/deploy kanıtı kaydedildi.
- [x] Bekleyen owner/hukuk onayının onaylanmış gibi yazılmasına yol açan legal migration düzeltildi; staging approval satırı sıfır ve gate kapalı.
- [x] Analiz telemetrisi trigger'ında Android platform alanı eklenirken düşen dil doğrulama alanları additive migration ile geri getirildi.
- [x] Auth e-posta/OTP/hata, fotoğraf tepsisi, Plus/Pro, analiz geçmişi, rapor arşivi, şirket ve hesap silme exact golden kapsamına eklendi.
- [x] iOS build-81 rapor mimarisi taşındı: Analizler yalnız analiz geçmişini, Raporlar ise özet, arşiv, kaynak analizi, PDF/XLSX seçimlerini ve üretim durumunu yönetiyor.
- [x] Free risk analizi raporu deneme hakkı `usage_events` üzerinden okunuyor; kullanılmamış hak bilgi bandı, kullanılmış hak Plus kilidi olarak gösteriliyor ve son karar backend'de kalıyor.
- [x] iOS'taki iki aşamalı rapor akışı taşındı: seçilen analizin gerçek bulgularıyla önizleme, ardından tip/şirket/yöntem/format/hazırlayan/unvan/belge no/dil ayarları açılıyor; şirket ID'si PDF ve XLSX isteklerine, kimlik override'ları cihaz PDF'ine aktarılıyor.
- [x] Rapor önizlemesi, kaynak ayarları, kullanılmış/kullanılmamış Free denemesi, Plus risk ayarları ve Excel üretim overlay'i exact golden kapsamına eklendi; toplam baseline sayısı 32 oldu.
- [x] API 36 emülatörde temiz QA APK; onboarding skip, bağımsız auth, cold relaunch, e-posta paneli ve font scale `1.3` ADB kanıtlarıyla geçti.
- [x] API 26 küçük, API 33 standart ve API 37 büyük AVD'leri kuruldu; final minified QA APK ile UI tree koordinatlı fresh-install/skip/auth/cold-relaunch smoke paketi yeniden üretildi ve üç kanıt aynı APK hash'ine bağlandı.
- [x] API 26'da yakalanan siyah sistem çubuğu, uygulama yüzeyinin inset arkasını boyamasıyla giderildi; etkileşim içeriği safe-area içinde kaldı.
- [x] Production değişiklikleri additive ve Android kapıları kapalı uygulandı; iOS `App/` kaynaklarına dokunulmadı.
- [x] Kullanıcı onaylı launcher icon paketi kapatıldı ve atomik commit'e alındı (`319c77ce`).
- [x] `/gizlilik` ve `/hesap-silme` production web sitesinde yayınlandı; OTP, enumeration koruması ve staging queue E2E geçti.
- [x] Gerçek saha fotoğraflarıyla 1, 2 ve 3 fotoğraflı analiz; sonuç, PDF ve XLSX zinciri doğrulandı.
- [x] Bildirim izni reddi/sonradan etkinleştirme, kayıt-ID deep-link'leri ve sign-out token temizliği doğrulandı.
- [x] Dokuz additive migration ve 20 kanonik Edge Function production'a Android kapıları kapalıyken dağıtıldı; son ek FCM token rotation migration'ı yeni schema warning/error üretmedi.
- [x] FCM token yenilemesinde aynı kurulum için eski/yeni token çoğalması giderildi; local test,
  staging ve production unique index doğrulaması tamamlandı.
- [x] İmzalı/minified release AAB üretildi; hash, signature, `bundletool`, 16 KB, R8/native symbols,
  secret/PII ve iOS asset kontrolleri release kanıtına kaydedildi.
- [x] Play Console'da `versionCode=1` kullanılarak Play App Signing etkinleştirildi ve Internal
  Testing release'i yayınlandı.
- [x] Play app-signing SHA-1/SHA-256 production Firebase'e eklendi; upload ve app-signing
  fingerprint'lerinin tamamı doğrulandı.
- [x] RevenueCat Google Play service-account credentials doğrulandı; Play RTDN test bildirimi
  Pub/Sub üzerinden RevenueCat'e ulaştı.
- [x] Play'de Plus/Pro aylık ve yıllık dört abonelik ürün kaydı oluşturuldu.
- [x] Türkçe listing metadata'sı, privacy URL, Business kategorisi ve temel uygulama beyanları
  Play Console taslağına kaydedildi.
- [x] IARC içerik derecelendirme anketi kaydedildi; Avrupa sonucu `PEGI 3`, dijital ürünler için
  uygulama içi satın alma etiketi etkin.
- [x] 512×512 ikon ve 1024×500 feature graphic hazırlandı, Play Console'a yüklendi ve mağaza
  taslağına kalıcı olarak kaydedildi.
- [x] Closed Alpha kanalı Türkiye, `RiskDetected Internal` test listesi ve destek URL'siyle
  yapılandırıldı; `1.5.0 (1) — Closed Alpha` sürümü taslak olarak kaydedildi.
- [x] Sekiz Türkçe 1080×1920 telefon mağaza görseli Play Console'a `01–08` sırasıyla
  yüklendi ve varsayılan Türkçe mağaza girişine kaydedildi.

## P0 — İlk Play Internal Testing yüklemesi

Bu bölüm sonraki Play ve RevenueCat testlerinin ön koşuludur.

- [x] İmzalı ve minified release AAB üret.
- [x] `bundletool validate` çalıştır.
- [x] AAB imzasını ve upload sertifikasını doğrula.
- [x] 16 KB native library/alignment kontrolünü çalıştır.
- [x] R8 mapping ve varsa native symbol artifact'larını sakla.
- [x] Secret/PII taramasını release artifact üzerinde çalıştır.
- [x] Play Console'da `versionCode=1` kullanılabilirliğini doğrula ve bu kodla ilk Internal
  Testing release'ini yayınla.
- [x] AAB'yi owner hesabıyla Internal Testing'e manuel yükle.
- [x] Play App Signing'i etkinleştir.
- [x] Play App Signing SHA-1/SHA-256 fingerprint'lerini kaydet.
- [x] App-signing fingerprint'lerini production Firebase Android uygulamasına ekle.
- [ ] Gerekliyse app-signing fingerprint'i için Google OAuth Android client oluştur/güncelle.
- [ ] Play tarafından yeniden imzalanmış uygulamayı Internal Testing üzerinden indirip temel smoke testi yap.

Kabul ölçütü: Play'den indirilen build açılıyor, backend environment kontrolü production gösteriyor ve auth ana ekranına güvenli biçimde ulaşılabiliyor.

## P0 — RevenueCat ve gerçek Play Billing

İlk AAB yüklemesinden sonra uygulanacaktır.

- [x] RevenueCat Google Play credentials uyarısının kalktığını doğrula.
- [ ] Google Play ürünlerinin ve base plan'ların RevenueCat tarafından eksiksiz okunduğunu doğrula.
- [x] RTDN/Pub/Sub topic bağlantısını tamamla ve test bildirimi doğrula.
- [ ] `default` offering içindeki dört paketin store fiyatlarını uygulamada doğrula:
  - [ ] `riskdetected_plus_monthly`
  - [ ] `riskdetected_plus_yearly`
  - [ ] `riskdetected_pro_monthly`
  - [ ] `riskdetected_pro_yearly`
- [ ] Plus aylık satın alma.
- [ ] Plus yıllık ve yedi günlük deneme.
- [ ] Pro aylık satın alma.
- [ ] Pro yıllık satın alma.
- [ ] Restore purchases.
- [ ] Pending ve kullanıcı tarafından iptal edilen satın alma.
- [ ] Renewal, cancel-at-period-end ve expiration.
- [ ] Grace period ve account hold.
- [ ] Refund/revoke.
- [ ] Receipt owner conflict ve duplicate ownership.
- [ ] Aynı Supabase hesabında iOS → Android entitlement tanıma.
- [ ] Aynı Supabase hesabında Android → iOS entitlement tanıma.
- [ ] Payment runtime gate kapalıyken tamamlanmış webhook'un üyeliği işlemeye devam ettiğini doğrula.

Kabul ölçütü: RevenueCat App User ID her durumda Supabase `auth.uid()` olur; store fiyatları tek kaynak olur; webhook ve profil planı tutarlı kalır.

Blokaj (11 Ağustos 2026): Dört ürün nesnesi Play'de oluşturuldu. Plus aylık ve Pro yıllık
temel planları; doğru aylık/yıllık dönem, yalnız Türkiye kullanılabilirliği ve KDV dahil hedef
fiyatlar doğrulanarak denendi. Play her iki denemede de ayrıntısız
`Değişiklikleriniz kaydedilemedi` yanıtı verdi. Ödeme profili mevcut ancak payout yöntemi yok.
Owner banka/payout yöntemini ekledikten veya Play bu hesap hatasını kaldırdıktan sonra temel
planlar, yedi günlük Plus yıllık deneme ve gerçek satın alma matrisi tamamlanabilir.

## P0 — Auth E2E

Owner kararı (11 Ağustos 2026): fiziksel cihaz Auth E2E bu teslimin dışında tutuldu ve sonraki
cihaz oturumuna ertelendi. Aşağıdaki maddeler bilinen ertelenmiş kapılardır.

- [ ] Google hesabı eklenmiş fiziksel Android cihazda Credential Manager girişini tamamla.
- [ ] Google callback sonrasında doğru Supabase session ve profil oluştuğunu doğrula.
- [ ] Duplicate identity/account linking senaryosunu test et.
- [ ] Giriş sırasında process death ve geri dönüşü test et.
- [ ] Fresh install, yedekten dönüş ve eski session senaryolarını test et.
- [x] Sign-out sonrası back stack temizliğini emülatör ve bildirim E2E kanıtıyla doğrula.
- [ ] E-posta OTP yanlış, süresi geçmiş ve tekrar gönderim durumlarını test et.
- [x] Android v1 ekranlarında Apple giriş CTA'sının bulunmadığını golden ve UI testleriyle sabitle.

Kabul ölçütü: Google ve OTP girişleri fiziksel cihazda tamamlanır; çıkıştan sonra korumalı ekranlara geri dönülemez.

## P0 — Analiz, sonuç ve rapor E2E

- [x] Kullanıcının belirlediği kapsamla gerçek fotoğraflı 1, 2 ve 3 fotoğraf analizlerini tamamla.
- [x] 1/2/3 fotoğraf analizlerinde waiting, polling/recovery ve sonuç ekranlarını doğrula.
- [x] Üç fotoğraflı sonuçtan gerçek 3 sayfalı PDF ve geçerli XLSX üret; backend snapshot'ını doğrula.
- [ ] İSG uzmanından kritik tehlike atlama, yanlış yüksek risk ve kontrol tedbiri kalitesi onayı al.
- [ ] Detaylı analiz akışını test et.
- [x] Üç fotoğraflı analiz ve fotoğraf sıralamasını test et.
- [x] Ağ/timeout sonrası submit recovery kararını otomatik test et: yalnız okunabilir ve `pending`
  dışı server durumu polling'e devam ediyor; terminal durumlar in-flight kaydını temizlerken
  timeout/in-progress süreç öldürme recovery kaydını koruyor.
- [x] Duplicate tap UI guard ve aynı submission ID owner-scoped unique/upsert sözleşmesini otomatik testlerle doğrula.
- [x] Process death sonrasında in-flight/pending kaydın store recreation ile devamını; süre aşımı,
  bozuk kayıt, farklı hesap ve fingerprint uyuşmazlığı negatif senaryolarını Robolectric ile test et.
- [x] Manuel bulgu ekleme fail-closed yetkisini, düzenleme/silme capability kapısını ve bulgu
  metin/FK/M5/önlem patch doğrulamasını plan sözleşmesine göre otomatik test et; gerçek backend
  mutation yetkisi mevcut pgTAP owner/cross-user negatif paketiyle korunuyor.
- [x] FK/M5 görünümünün server tarafından hesaplanan doğru skor ve band alanını seçmesini test et;
  remote capability fail-closed matrisiyle birlikte doğrula.
- [x] Free/Plus/Pro yerel kota sözleşmesini ve rapor dönem başlangıcını `Europe/Istanbul` gün/ay
  sınırında deterministik test et; backend son karar otoritesi olarak kaldı.
- [ ] Standart ve detaylı PDF içerik/sıra/renk semantiğini iOS raporuyla karşılaştır.
- [ ] XLSX bölüm, bulgu, risk skoru, şirket ve filtre verilerini iOS semantiğiyle karşılaştır.
- [ ] Rapor açma, paylaşma, snapshot ve silme cihaz akışlarını test et. Geçmiş analiz arama,
  hafta/risk/tür/şirket/focused-ID filtre birleşimi otomatik testle kapatıldı.

Kabul ölçütü: Corpus'ta kritik tehlike atlama yoktur; aynı submission ikinci analiz oluşturmaz; PDF/XLSX semantik paritesi sağlanır.

## P1 — Bildirimlerin kalan testleri

- [x] Android 13+ bildirim izni reddedilmiş durumda uygulama davranışını test et.
- [x] İzin daha sonra Profil'den etkinleştirildiğinde token kaydını doğrula.
- [x] Analiz ve rapor kayıt ID'li deep-link rotalarını foreground/background/killed durumlarında test et.
- [x] Sign-out sonrası yalnız mevcut kurulumun token temizliğini doğrula.
- [x] Payload ve loglarda PII/ham mesaj bulunmadığını doğrula.
- [ ] FCM token rotation (`onNewToken`) senaryosunu gerçek yenilenmiş token ile tekrar doğrula.

Not: istemci upsert kimliği düzeltildi; local pgTAP, staging ve production migration/index
doğrulaması geçti. Bu madde yalnız aktif oturumlu cihazda gerçek yenilenmiş token teslimini kapsar.

Kabul ölçütü: Reddedilmiş izin uygulamayı bozmaz; izin verildiğinde FCM kaydı ve tüm tipli rotalar çalışır.

## P1 — Cihaz ve UI parite matrisi

- [x] API 26 küçük ekran emülatörde fresh install, skip, auth ve cold-relaunch smoke testi.
- [x] API 33 standart ekran emülatörde fresh install, skip, auth ve cold-relaunch smoke testi.
- [x] API 37 büyük ekran emülatörde fresh install, skip, auth ve cold-relaunch smoke testi.
- [ ] API 26/33/37 üzerinde giriş yapılmış dört tab, analiz ve rapor cihaz akışlarını tamamla.
- [ ] Fiziksel Pixel testi.
- [ ] Fiziksel Samsung testi.
- [x] Font scale `1.0` ana kabul testini temiz debug APK ve UI tree kanıtıyla tamamla.
- [x] Font scale `1.3` erişilebilirlik smoke testini auth ekranında UI tree/crash buffer ile tamamla.
- [x] Desteklenen ekranlarda açık/koyu sistem teması smoke testi; auth yüzeyinin iOS paritesi için
  bilinçli açık tema kalması ve sistem barı adaptasyonu doğrulandı.
- [x] Analiz bekleme, sonuç, Pro bulgu detayı, PDF ve XLSX oluşturma durum golden'larını onayla.
- [ ] Recovery ve Android sistem paylaşım yüzeyini cihaz kanıtıyla onayla.
- [x] Free/Plus/Pro CTA, Plus sarı/Pro yeşil kimliği, kart, tablo, ikon ve risk renklerini iOS
  referansı ve threshold `0` golden paketiyle karşılaştır.

Kabul ölçütü: Android golden threshold `0`; platformlar arası geometri farkı en fazla ±2dp ve beklenmeyen görsel fark yoktur.

## P1 — Web, hukuk ve hesap silme

- [x] Production web sitesinde `/gizlilik` rotasını yayınla.
- [x] Production web sitesinde `/hesap-silme` rotasını yayınla.
- [x] E-posta OTP doğrulaması ve `shouldCreateUser=false` davranışını test et.
- [x] Account enumeration yapılmadığını doğrula.
- [x] `request_only` silme talebinin HTTP 202 ve takip bilgileri döndürdüğünü staging'de doğrula.
- [x] Saatlik worker'ın idempotent claim, retry ve en fazla 24 saat SLA davranışını staging'de test et.
- [x] DB, Storage ve Auth temizliğini; gerekli audit retention davranışını staging'de doğrula.
- [x] Resend talep ve tamamlanma e-postalarını staging'de doğrula.
- [x] Resend hatasının silme kuyruğunu durdurmadığını doğrula.
- [x] Production CORS allowlist, oturumsuz istek engeli, Vault ve saatlik cron'u doğrula.
- [x] Android hukuk metinleri owner tarafından nihai olarak onaylandı; approval record, uygulama manifesti ve additive registry migration'ı tamamlandı (2026-08-11).

Kabul ölçütü: Play'de kullanılabilecek herkese açık gizlilik ve hesap silme URL'leri çalışır; gerçek silme talebi 24 saat içinde tamamlanır.

## P1 — Backend ve otomatik kalite kapıları

- [x] Docker'da yalnız kullanılmayan, yeniden indirilebilir eski Supabase image cache'leri temizlendi; kullanıcı volume'leri korundu.
- [x] Yerel Supabase stack'i temiz migration replay ile tekrar başlatıldı.
- [x] Yeni Android/web/FCM rotation testleri dahil pgTAP paketi `485/485` geçti.
- [x] Deno Edge Function testleri `316/316` geçti.
- [x] Beş `SECURITY DEFINER` RPC için auth, sahiplik, sabit `search_path`, anon revoke ve çapraz kullanıcı negatif testleri geçti.
- [x] Local Supabase security/performance advisor sonucu sıfır uyarı.
- [x] Staging advisor değerlendirildi; beş istemci RPC'si test kanıtlı waiver'a alındı, deny-by-default INFO kayıtları belgelendi.
- [ ] Supabase leaked-password protection'ı plan erişimi sağlandığında staging'de aç, auth regresyonu sonrası production'a taşı.
- [x] Production Supabase DB lint/advisor warning'lerini tekrar değerlendir; yeni schema warning/error yok. Beş RPC testli waiver, leaked-password protection plan-tier blocker olarak kayıtlı.
- [x] Debug lint ve minified QA R8 build'i geçti.
- [x] Production public config ve signing secret'larıyla release lint/signed R8 build'i geçir.
- [x] Roborazzi golden paketi sabit JDK 17, Türkçe locale, İstanbul timezone ve threshold `0` ile geçti.
- [x] `App/` diff'inin build-81 baseline'a göre sıfır olduğu yerel fail-closed kontrolde doğrulandı; CI kapısı mevcut.
- [x] Production Android runtime gate'lerinin altı işlev kapısında kapalı olduğunu canlı policy çağrısıyla doğrula.

Kabul ölçütü: Unit, golden, lint, R8, Deno ve pgTAP testlerinin tamamı yeşildir; çözülmemiş kritik/yüksek güvenlik bulgusu yoktur.

Not: Docker kullanıcı volume'leri silinmedi. Temizlik yalnız kullanılmayan Supabase image cache sürümleriyle sınırlandı; gerekli sabit CLI sürümleri otomatik yeniden indirildi.

## P2 — Play Store hazırlığı

- [x] Türkçe kısa ve uzun açıklamaları son kez gözden geçir ve Play taslağına kaydet.
- [x] Kullanıcı onaylı full-bleed master'dan adaptive/round/monochrome kaynaklarını ve 512×512 Play ikonunu üret.
- [x] 1024×500 feature graphic'i hazırla.
- [x] Play 512×512 ikonunu ve 1024×500 feature graphic'i varsayılan Türkçe mağaza girişine
  yükle ve taslak olarak kaydet.
- [x] Owner tasarımından sekiz Türkçe, PII'siz telefon ekran görüntüsünü teslim al ve Play'e yükle.
- [ ] Business kategorisini kaydet; login-access adımı açıldıktan sonra 18+ profesyonel hedef kitleyi tamamla. (Kategori tamam, hedef kitle Play oturum açma beyanına bağımlı.)
- [x] Data Safety formunda gerçek SDK/veri envanterine göre 15 veri türünü ve veri işleme
  amaçlarını kaydet.
- [ ] Data Safety hesap silme URL doğrulamasını tamamla. (`/hesap-silme` doğrudan 200 döndüğü
  halde Play crawler 403 görüyor ve owner destek kaydı açık.)
- [x] Content rating beyanını tamamla.
- [x] Reklam Kimliği beyanını `Hayır` olarak kaydet; AAB'de `AD_ID` olmadığını doğrula.
- [ ] Review erişim bilgileri tamamlandıktan sonra 18+ hedef kitle, subscription ve
  restricted-access beyanlarını tamamla.
- [ ] Dedicated review hesabı ve inceleme adımlarını hazırla.
- [ ] Play Pre-launch Report'u çalıştır ve blocker'ları kapat.

Kabul ölçütü: Listing, Data Safety, hukuk URL'leri ve inceleme erişimi eksiksizdir; Pre-launch Report blocker içermez.

## P2 — Closed test ve production rollout

- [x] Closed Alpha kanalında Türkiye'yi, test listesini, geri bildirim URL'sini ve versionCode 1
  sürüm taslağını yapılandır.
- [ ] En az 12 test kullanıcısını Closed Testing'e dahil et.
- [ ] Kesintisiz 14 günlük opt-in şartını tamamla ve kayıt altına al.
- [ ] Closed test boyunca crash-free session oranını en az `%99,5` tut.
- [ ] Play Vitals, auth/analiz/rapor başarı oranı, webhook ve destek taleplerini izle.
- [x] Production'a additive migration ve Edge Function paketini Android gate'leri kapalıyken dağıt.
- [x] Dağıtım sonrası iOS build-81 release-policy fixture/smoke testini yeniden çalıştır.
- [ ] Review hesabı/version allowlist canary'sini aç.
- [ ] Özellikleri sırayla aç: client/auth → profil/okuma → PDF → tek fotoğraf → multi-photo → payments → notifications.
- [ ] Play rollout'u `%20 → %50 → %100` uygula; her kademeyi en az 24 saat izle.
- [ ] Rollback için gate, allowlist ve Play rollout halt prosedürünü prova et.

Kabul ölçütü: Closed test şartı tamamlanmış, sağlık metrikleri yeşil ve iOS build-81 regresyonu temizdir.

## Dış bağımlılıklar ve owner işlemleri

- [x] İlk AAB'yi Play Console Internal Testing'e yüklemek ve yayınlamak.
- [ ] Upload keystore'un şifreli yedeğini owner kasasına almak ve kurtarma prosedürünü kaydetmek.
- [x] Play App Signing fingerprint'lerini production Firebase kaydına eklemek.
- [ ] Google OAuth Android client'ta Play app-signing fingerprint'ini son kez doğrulamak.
- [ ] Geliştirici ödeme profiline payout/banka yöntemi eklemek; ardından dört base plan'ı kaydetmek.
- [ ] Dedicated Fastmail review mailbox parolasını doğrudan Play oturum açma beyanına girmek.
- [ ] Açık Google destek kaydında Data Safety hesap-silme URL doğrulayıcı 403 sonucunu takip etmek.
- [ ] Fiziksel Google hesaplı cihaz sağlamak.
- [ ] Play lisans test kullanıcılarını tanımlamak.
- [ ] En az 12 closed-test kullanıcısını yönetmek.
- [x] Hukuk metinlerine nihai owner onayı vermek.
- [ ] Data Safety ve mağaza içeriğine nihai owner onayı vermek.

## Release tamamlanma tanımı

Release aşağıdaki koşulların tamamı sağlanmadan hazır kabul edilmeyecektir:

- [ ] Play'den indirilen imzalı release kritik akışları geçiyor.
- [x] Otomatik kalite kapıları tamamen yeşil.
- [ ] Auth, analiz, PDF/XLSX, billing ve FCM E2E tamam.
- [ ] AI corpus'unda kritik tehlike atlama yok.
- [ ] Fiziksel Pixel ve Samsung testleri tamam.
- [x] Hesap silme ve gizlilik URL'leri yayında.
- [ ] 12 tester × 14 gün closed test tamam.
- [ ] Play Pre-launch Report blocker içermiyor.
- [ ] Closed test crash-free session oranı en az `%99,5`.
- [ ] Production gate'leri yalnız kontrollü canary için açılıyor.
- [x] iOS build-81 regresyonu temiz ve `App/` diff'i sıfır.
