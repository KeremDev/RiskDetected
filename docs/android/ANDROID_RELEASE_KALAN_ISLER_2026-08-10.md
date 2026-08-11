# Android Release Kalan İşler

Tarih: 10 Ağustos 2026
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
- [x] Deno Edge Function paketi `316/316`, pgTAP/RLS/RPC paketi `478/478` geçti; local DB lint sonucu sıfır hata.
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
- [x] Production ortamına ve iOS `App/` kaynaklarına dokunulmadı.

## P0 — İlk Play Internal Testing yüklemesi

Bu bölüm sonraki Play ve RevenueCat testlerinin ön koşuludur.

- [ ] İmzalı ve minified release AAB üret.
- [ ] `bundletool validate` çalıştır.
- [ ] AAB imzasını ve upload sertifikasını doğrula.
- [ ] 16 KB native library/alignment kontrolünü çalıştır.
- [ ] R8 mapping ve varsa native symbol artifact'larını sakla.
- [ ] Secret/PII taramasını release artifact üzerinde çalıştır.
- [ ] Play Console'da `versionCode=1` kullanılabilirliğini doğrula; kullanılmışsa bir sonraki boş code'a yükselt.
- [ ] AAB'yi owner hesabıyla Internal Testing'e manuel yükle.
- [ ] Play App Signing'i etkinleştir.
- [ ] Play App Signing SHA-1/SHA-256 fingerprint'lerini kaydet.
- [ ] App-signing fingerprint'lerini production Firebase Android uygulamasına ekle.
- [ ] Gerekliyse app-signing fingerprint'i için Google OAuth Android client oluştur/güncelle.
- [ ] Play tarafından yeniden imzalanmış uygulamayı Internal Testing üzerinden indirip temel smoke testi yap.

Kabul ölçütü: Play'den indirilen build açılıyor, backend environment kontrolü production gösteriyor ve auth ana ekranına güvenli biçimde ulaşılabiliyor.

## P0 — RevenueCat ve gerçek Play Billing

İlk AAB yüklemesinden sonra uygulanacaktır.

- [ ] RevenueCat Google Play credentials uyarısının kalktığını doğrula.
- [ ] Google Play ürünlerinin ve base plan'ların RevenueCat tarafından eksiksiz okunduğunu doğrula.
- [ ] RTDN/Pub/Sub topic bağlantısını tamamla ve test bildirimi doğrula.
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

## P0 — Auth E2E

- [ ] Google hesabı eklenmiş fiziksel Android cihazda Credential Manager girişini tamamla.
- [ ] Google callback sonrasında doğru Supabase session ve profil oluştuğunu doğrula.
- [ ] Duplicate identity/account linking senaryosunu test et.
- [ ] Giriş sırasında process death ve geri dönüşü test et.
- [ ] Fresh install, yedekten dönüş ve eski session senaryolarını test et.
- [ ] Sign-out sonrası back stack temizliğini doğrula.
- [ ] E-posta OTP yanlış, süresi geçmiş ve tekrar gönderim durumlarını test et.
- [ ] Android v1 ekranlarında Apple giriş CTA'sının bulunmadığını golden ve UI testleriyle sabitle.

Kabul ölçütü: Google ve OTP girişleri fiziksel cihazda tamamlanır; çıkıştan sonra korumalı ekranlara geri dönülemez.

## P0 — Analiz, sonuç ve rapor E2E

- [ ] Sabit 10 gerçek saha fotoğrafından oluşan AI kalite corpus'unu tamamla.
- [ ] Kalan 9 corpus fotoğrafını Android ve iOS ile aynı backend/prompt capability üzerinden analiz et.
- [ ] İSG uzmanından kritik tehlike atlama, yanlış yüksek risk ve kontrol tedbiri kalitesi onayı al.
- [ ] Detaylı analiz akışını test et.
- [ ] Üç fotoğraflı analiz, fotoğraf sıralaması ve işaretlemeyi test et.
- [ ] Ağ kesintisi ve polling recovery akışını test et.
- [ ] Duplicate tap ve aynı submission ID ile idempotency testini tamamla.
- [ ] Process death sonrasında bekleyen analize geri dönüşü test et.
- [ ] Bulgu ekleme yetkisi, düzenleme ve silme akışlarını planlara göre test et.
- [ ] FK/M5 görünümü ve remote capability davranışını test et.
- [ ] Free/Plus/Pro kota sınırlarını `Europe/Istanbul` gün sınırında doğrula.
- [ ] Standart ve detaylı PDF içerik/sıra/renk semantiğini iOS raporuyla karşılaştır.
- [ ] XLSX bölüm, bulgu, risk skoru, şirket ve filtre verilerini iOS semantiğiyle karşılaştır.
- [ ] Rapor açma, paylaşma, snapshot, filtreleme ve silme akışlarını test et.

Kabul ölçütü: Corpus'ta kritik tehlike atlama yoktur; aynı submission ikinci analiz oluşturmaz; PDF/XLSX semantik paritesi sağlanır.

## P1 — Bildirimlerin kalan testleri

- [ ] Android 13+ bildirim izni reddedilmiş durumda uygulama davranışını test et.
- [ ] İzin daha sonra Profil'den etkinleştirildiğinde token kaydını doğrula.
- [ ] Analiz ve rapor kayıt ID'li deep-link rotalarını foreground/background/killed durumlarında test et.
- [ ] Token refresh ve sign-out sonrası token temizliğini doğrula.
- [ ] Payload ve loglarda PII/ham mesaj bulunmadığını doğrula.

Kabul ölçütü: Reddedilmiş izin uygulamayı bozmaz; izin verildiğinde FCM kaydı ve tüm tipli rotalar çalışır.

## P1 — Cihaz ve UI parite matrisi

- [x] API 26 küçük ekran emülatörde fresh install, skip, auth ve cold-relaunch smoke testi.
- [x] API 33 standart ekran emülatörde fresh install, skip, auth ve cold-relaunch smoke testi.
- [x] API 37 büyük ekran emülatörde fresh install, skip, auth ve cold-relaunch smoke testi.
- [ ] API 26/33/37 üzerinde giriş yapılmış dört tab, analiz ve rapor cihaz akışlarını tamamla.
- [ ] Fiziksel Pixel testi.
- [ ] Fiziksel Samsung testi.
- [ ] Font scale `1.0` ana kabul testi.
- [ ] Font scale `1.3` erişilebilirlik smoke testi.
- [ ] Desteklenen ekranlarda açık/koyu tema testi.
- [x] Analiz bekleme, sonuç, Pro bulgu detayı, PDF ve XLSX oluşturma durum golden'larını onayla.
- [ ] Recovery ve Android sistem paylaşım yüzeyini cihaz kanıtıyla onayla.
- [ ] Free/Plus/Pro CTA, sarı/yeşil kimlik, kart, tablo, ikon ve risk renklerini iOS referansıyla karşılaştır.

Kabul ölçütü: Android golden threshold `0`; platformlar arası geometri farkı en fazla ±2dp ve beklenmeyen görsel fark yoktur.

## P1 — Web, hukuk ve hesap silme

- [ ] Production web sitesinde `/gizlilik` rotasını yayınla.
- [ ] Production ve staging web sitelerinde `/hesap-silme` rotasını yayınla.
- [ ] E-posta OTP doğrulaması ve `shouldCreateUser=false` davranışını test et.
- [ ] Account enumeration yapılmadığını doğrula.
- [ ] `request_only` silme talebinin HTTP 202 ve takip bilgileri döndürdüğünü doğrula.
- [ ] Saatlik worker'ın idempotent claim, retry ve en fazla 24 saat SLA davranışını test et.
- [ ] DB, Storage ve Auth temizliğini; gerekli audit retention davranışını doğrula.
- [ ] Resend talep ve tamamlanma e-postalarını doğrula.
- [ ] Resend hatasının silme kuyruğunu durdurmadığını doğrula.
- [ ] Android hukuk metinlerini owner onayına sun ve approval record'u tamamla.

Kabul ölçütü: Play'de kullanılabilecek herkese açık gizlilik ve hesap silme URL'leri çalışır; gerçek silme talebi 24 saat içinde tamamlanır.

## P1 — Backend ve otomatik kalite kapıları

- [x] Docker'da yalnız kullanılmayan, yeniden indirilebilir eski Supabase image cache'leri temizlendi; kullanıcı volume'leri korundu.
- [x] Yerel Supabase stack'i temiz migration replay ile tekrar başlatıldı.
- [x] Yeni Android platform telemetry testleri dahil pgTAP paketi `478/478` geçti.
- [x] Deno Edge Function testleri `316/316` geçti.
- [x] Beş `SECURITY DEFINER` RPC için auth, sahiplik, sabit `search_path`, anon revoke ve çapraz kullanıcı negatif testleri geçti.
- [x] Local Supabase security/performance advisor sonucu sıfır uyarı.
- [x] Staging advisor değerlendirildi; beş istemci RPC'si test kanıtlı waiver'a alındı, deny-by-default INFO kayıtları belgelendi.
- [ ] Staging leaked-password protection'ı auth regresyonundan sonra aç.
- [ ] Production Supabase advisor warning'lerini production deploy öncesi tekrar değerlendir.
- [x] Debug lint ve minified QA R8 build'i geçti.
- [ ] Production public config ve signing secret'larıyla release lint/signed R8 build'i geçir.
- [x] Roborazzi golden paketi sabit JDK 17, Türkçe locale, İstanbul timezone ve threshold `0` ile geçti.
- [x] `App/` diff'inin build-81 baseline'a göre sıfır olduğu yerel fail-closed kontrolde doğrulandı; CI kapısı mevcut.
- [ ] Production Android runtime gate'lerinin kapalı olduğunu CI'de doğrula.

Kabul ölçütü: Unit, golden, lint, R8, Deno ve pgTAP testlerinin tamamı yeşildir; çözülmemiş kritik/yüksek güvenlik bulgusu yoktur.

Not: Docker kullanıcı volume'leri silinmedi. Temizlik yalnız kullanılmayan Supabase image cache sürümleriyle sınırlandı; gerekli sabit CLI sürümleri otomatik yeniden indirildi.

## P2 — Play Store hazırlığı

- [ ] Türkçe kısa ve uzun açıklamaları son kez gözden geçir.
- [x] Kullanıcı onaylı full-bleed master'dan adaptive/round/monochrome kaynaklarını ve 512×512 Play ikonunu üret.
- [ ] 1024×500 feature graphic'i yükle.
- [ ] Küçük/standart/büyük telefonlardan sekiz Türkçe ekran görüntüsü hazırla.
- [ ] Business kategorisi ve 18+ profesyonel hedef kitle ayarlarını tamamla.
- [ ] Data Safety formunu gerçek SDK/veri envanterine göre doldur.
- [ ] Content rating, target audience, subscription ve restricted-access beyanlarını tamamla.
- [ ] Dedicated review hesabı ve inceleme adımlarını hazırla.
- [ ] Play Pre-launch Report'u çalıştır ve blocker'ları kapat.

Kabul ölçütü: Listing, Data Safety, hukuk URL'leri ve inceleme erişimi eksiksizdir; Pre-launch Report blocker içermez.

## P2 — Closed test ve production rollout

- [ ] En az 12 test kullanıcısını Closed Testing'e dahil et.
- [ ] Kesintisiz 14 günlük opt-in şartını tamamla ve kayıt altına al.
- [ ] Closed test boyunca crash-free session oranını en az `%99,5` tut.
- [ ] Play Vitals, auth/analiz/rapor başarı oranı, webhook ve destek taleplerini izle.
- [ ] Production'a additive migration ve Edge Function paketini Android gate'leri kapalıyken dağıt.
- [ ] Dağıtım sonrası iOS build-81 fixture ve smoke testlerini yeniden çalıştır.
- [ ] Review hesabı/version allowlist canary'sini aç.
- [ ] Özellikleri sırayla aç: client/auth → profil/okuma → PDF → tek fotoğraf → multi-photo → payments → notifications.
- [ ] Play rollout'u `%20 → %50 → %100` uygula; her kademeyi en az 24 saat izle.
- [ ] Rollback için gate, allowlist ve Play rollout halt prosedürünü prova et.

Kabul ölçütü: Closed test şartı tamamlanmış, sağlık metrikleri yeşil ve iOS build-81 regresyonu temizdir.

## Dış bağımlılıklar ve owner işlemleri

- [ ] İlk AAB'yi Play Console'a owner hesabıyla yüklemek.
- [ ] Upload keystore'un şifreli yedeğini owner kasasına almak ve kurtarma prosedürünü kaydetmek.
- [ ] Play App Signing fingerprint'lerini ilgili Firebase/OAuth kayıtlarına onaylamak.
- [ ] Fiziksel Google hesaplı cihaz sağlamak.
- [ ] Play lisans test kullanıcılarını tanımlamak.
- [ ] En az 12 closed-test kullanıcısını yönetmek.
- [ ] Docker disk temizliği/genişletmesi için owner onayı vermek.
- [ ] Hukuk metinleri, Data Safety ve mağaza içeriğine nihai owner onayı vermek.

## Release tamamlanma tanımı

Release aşağıdaki koşulların tamamı sağlanmadan hazır kabul edilmeyecektir:

- [ ] Play'den indirilen imzalı release kritik akışları geçiyor.
- [ ] Otomatik kalite kapıları tamamen yeşil.
- [ ] Auth, analiz, PDF/XLSX, billing ve FCM E2E tamam.
- [ ] AI corpus'unda kritik tehlike atlama yok.
- [ ] Fiziksel Pixel ve Samsung testleri tamam.
- [ ] Hesap silme ve gizlilik URL'leri yayında.
- [ ] 12 tester × 14 gün closed test tamam.
- [ ] Play Pre-launch Report blocker içermiyor.
- [ ] Closed test crash-free session oranı en az `%99,5`.
- [ ] Production gate'leri yalnız kontrollü canary için açılıyor.
- [ ] iOS build-81 regresyonu temiz ve `App/` diff'i sıfır.
