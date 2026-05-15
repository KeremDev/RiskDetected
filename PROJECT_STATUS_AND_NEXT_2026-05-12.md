# RiskDetected - Güncel Durum ve Kalan İşler

Tarih: 2026-05-15

Bu dosya `IMPLEMENTATION_PLAN.md`, `PROJECT_HANDOFF.md`, `HANDOFF_2026-05-11_NEW_CHAT/*`,
`AUTH_SETUP.md`, `PROMPT_SYSTEM_REVAMP_PLAN_2026-05-11.md` ve `QA/P1_5_Error_Test_Matrix.md`
dosyaları taranarak oluşturulan güncel tek yapılacaklar özetidir.

## Yapıldı

### Çekirdek MVP

- SwiftUI uygulama iskeleti, splash/onboarding/auth/main tab akışı çalışıyor.
- Ana sekmeler hazır: Ana Sayfa, Analizler, Raporlar, Profil.
- Supabase Auth, PostgreSQL, Storage ve Edge Functions bağlantıları aktif.
- Fotoğraf ve metin analizi canlı veriyle çalışıyor.
- Analizler `analyses`, `findings`, `photos`, `ai_usage_logs` tablolarına yazılıyor.
- Fine-Kinney ve 5x5 ham girdileri AI'dan alınıyor; skorlar DB/sistem tarafında hesaplanıyor.
- Free standart analiz limiti günde 1 olarak uygulanıyor.
- Plus standart analiz limiti günde 10, Pro standart analiz limiti günde 40 olarak uygulanıyor.
- Rapor kotası Free 3/ay, Plus 150/ay, Pro 750/ay olarak uygulanıyor.
- Free kullanıcı yalnızca 1 canvas seçebiliyor; Plus sınırlı gelişmiş canvas, Pro tam gelişmiş canvas erişimine sahip.
- Pro bulgu limiti 10 olarak güncellendi.
- Free limit dolu senaryosunda Home ve orta Tara butonu yükseltme uyarısına yönlendiriyor.

### Auth

- Email OTP ana şifresiz giriş akışı olarak çalışıyor.
- OTP girişi tek hidden input mantığıyla otomatik ilerliyor, caret/glow geri bildirimi var.
- 6 hane tamamlanınca otomatik doğrulama çalışıyor.
- Hata durumunda tekrar kod gönderme linki gösteriliyor.
- Yeni kullanıcı ve mevcut kullanıcı için Supabase Email OTP doğrulama akışı düzeltildi.
- OTP hata mesajları Türkçe ve kullanıcı dostu hale getirildi.
- Google OAuth "Vazgeç" durumunda teknik WebAuthenticationSession hatası kullanıcıya gösterilmiyor.
- Apple Sign In iOS tarafında gerçek Apple identity token + nonce ile Supabase akışına bağlı.
- Apple Sign In gerçek Apple hesabıyla TestFlight cihazda doğrulandı; Supabase `apple` identity ve otomatik `profiles` satırı oluştu.
- Google Sign In native Google SDK ile bağlı; Supabase'e Google `idToken` ile oturum açılıyor.
- Sosyal/e-posta giriş sonrası profil yoksa güvenli şekilde default `free` profil oluşturuluyor.
- Profil bootstrap artık "profil yok" ile "profil okunamadı" hatasını ayırıyor.
- Firebase/telefon auth tamamen kaldırıldı:
  - Firebase iOS SDK kaldırıldı.
  - `FirebaseBootstrap`, `FirebasePhoneAuthService`, `GoogleService-Info` kaldırıldı.
  - Firebase URL scheme kaldırıldı.
  - `firebase-phone-bridge` Edge Function canlıdan silindi.
  - `firebase_phone_auth_links` tablosu canlı DB'den silindi.

### Onboarding

- İlk kurulum onboarding akışı eklendi.
- Kullanıcı onboarding'i tamamlayınca `rd.onboarding.completed` ile lokal saklanıyor.
- Onboarding görselleri ve kısa eğitim metinleri mevcut.
- Auth ekranından önce sadece ilk kullanımda gösteriliyor.

### AI Canvas ve Prompt Sistemi

- Canvas kartlarında kullanıcıya yalnızca başlık gösteriliyor.
- Canvas seçimi UI tarafında tek seçime indirildi.
- Backend birden fazla canvas payload gelse bile ilk geçerli canvas'a normalize ediyor.
- Yeni ortak prompt canlı:
  - Türkiye İSG mevzuatı perspektifi.
  - Sadece görüntüde görülen bulgular.
  - Emin olunmayan noktalar için "kontrol edilmeli".
- Yeni canvas promptları backend `CANVAS_FOCUS` içinde işleniyor.
- Pro kullanıcı için references/mevzuat alanı isteniyor.
- Free kullanıcı için references schema'ya eklenmiyor ve AI'dan istenmiyor.
- Prompt audit bilgileri `raw_analysis_input` içinde izlenebilir:
  - seçilen canvas id'leri,
  - canvas prompt metni,
  - ortak prompt,
  - Pro references promptu,
  - AI'a gönderilen system prompt.
- AI maliyet/süre için token, model, key alias, attempt count ve destek kodu logları genişletildi.
- Gemini key pool altyapısı eklendi:
  - `GEMINI_API_KEY_PRIMARY`
  - `GEMINI_API_KEY_SECONDARY`
  - `GEMINI_API_KEY_TERTIARY`

### Raporlar, PDF ve Excel

- Standart PDF rapor üretimi çalışıyor.
- Pro Fine-Kinney ve 5x5 detaylı risk analizi PDF çıktıları çalışıyor.
- PDF landscape tablo çıktılarında metin taşması düzeltildi.
- Mevzuat/references bilgisi Pro sonuç ve rapor görünümlerine dahil edildi.
- Free kullanıcıda mevzuat alanı kilitli/Pro'da açık olarak gösteriliyor; Free analizde AI'a mevzuat sorgusu gitmiyor.
- PDF Storage upload ve `reports` metadata kaydı yapılıyor.
- Rapor arşivinde PDF/XLSX satırları ayrışıyor.
- Rapor upload transient network hatalarında retry eklendi.
- Arşiv kaydı başarısız olsa bile oluşturulan PDF preview/paylaşım akışı kesilmiyor.
- Pro XLSX export Edge Function eklendi ve backend smoke test geçti.
- Reports sayfasında `Kayıtlı Rapor Dosyaları` ve `Rapora Dönüştür` bölümleri açılır/kapanır kart yapısına taşındı.
- Reports arşivine arama/filtre, PDF/XLSX/metot/durum label'ları, boş/error state ve filtreli load-more davranışı eklendi.
- Reports archive yoğun veri QA eklendi:
  - simülatörde 21 kayıtlı raporla smoke test alındı;
  - 247 sentetik kayıtla ilk 100 kayıt fetch, +5 local load-more, remote continuation, filtre/search ve duplicate merge doğrulandı;
  - Türkçe diacritic-insensitive arama için `İş Güvenliği` -> `is guvenligi` normalizasyonu düzeltildi.
- Pro/Plus rapor varsayılanları profilden geliyor:
  - profil logosu rapor logosu olarak otomatik yükleniyor;
  - hazırlayan adı, unvan, belge no, firma adı/bilgisi ve varsayılan metod PDF ayarlarına otomatik doluyor;
  - standart PDF, detaylı PDF ve XLSX metadata alanları aynı profil varsayılanlarını kullanıyor.

### Profil, Tema ve UI

- Profil bilgisi kaydetme çalışıyor.
- Profil logosu seçme/kaydetme çalışıyor.
- Profilde geçmiş analizler ve raporlar routing'i çalışıyor.
- Profil > Destek formu eklendi; konu, mesaj ve isteğe bağlı fotoğraf/dosya ekiyle `info@riskdetected.com` adresine mail gönderir.
  - Canlı mail gönderimi için Supabase Edge Function secret'ına `RESEND_API_KEY` eklenmeli.
- Dark mode foundation tamamlandı:
  - Sistem / Aydınlık / Karanlık seçenekleri.
  - Core renk tokenları dark/light uyumlu.
  - Home, Result, Report settings, Profile, Analyses, Reports hızlı dark pass geçti.
- Dil tercihi lokal olarak saklanıyor: Sistem / Türkçe / English.
- Header profil menüsü var:
  - Analizlerim,
  - Raporlarım,
  - Pro durum/upgrade,
  - çıkış,
  - hızlı tema değiştirme.
- Auth ekranı güncellendi:
  - E-posta ile giriş en üstte ve daha görünür.
  - Apple/Google aşağıda.
  - Email placeholder gri ve sade.
  - Arka plan geçişleri/logo görünürlüğü iyileştirildi.
- Analizler sayfasındaki taşan kart/tarih problemi düzeltildi.
- Özel analiz notu kaldırıldı.

### Gizlilik, KVKK ve Veri Yönetimi

- Login ekranında hukuki kabul metni ve bağlantıları var.
- Legal center eklendi:
  - KVKK,
  - Kullanım koşulları,
  - Gizlilik Politikası.
- Legal metinler `Riskdetected`, `info@riskdetected.com`, Eskişehir ve `https://riskdetected.com` bilgileriyle güncellendi.
- App içi yasal ekran artık madde kartları yerine doğrudan uzun metin dokümanını scroll edilen pencere içinde gösteriyor.
- `consents` tablosu ve RLS var.
- Login/session arka planda consent audit row oluşturuyor.
- Client fotoğraf preprocessing EXIF/location/camera metadata'yı temizliyor.
- Edge Function JPEG/PNG metadata temizliyor.
- Client-side yüz blur uygulanıyor.
- Result/detail ekranları temiz Storage görselini tercih ediyor.
- Retention policy tanımlandı:
  - Free fotoğraflar 30 gün,
  - Pro fotoğraflar 365 gün,
  - raw AI response 30 gün,
  - raporlar kullanıcı silene kadar.
- `retention-cleanup` Edge Function ve günlük Supabase Cron eklendi.
- Reports tekil silme, Analyses tekil silme, Profile > Verilerim export/bulk delete/account deletion request akışları var.

### Hata Yönetimi ve QA

- `AppErrorMessage` merkezi hata mesaj sistemi eklendi.
- Kullanıcıya ham RLS/HTTP/Gemini/JSON detayları gösterilmemesi için ana akışlar normalize edildi.
- Analysis ve report akışlarında `request_id` / `support_id` taşınıyor.
- AI 429/503/invalid JSON simülasyonları test edildi.
- PDF render/storage/metadata/download/delete simülasyonları test edildi.
- Data action simülasyonları test edildi.
- `QA/P1_5_Error_Test_Matrix.md` içindeki E01-E18 satırları geçti olarak işaretli.
- Xcode build + simulator run son durumda başarılı ve warning yok.

## Kalan İşler

### P0 - Release Öncesi Kapanması Gerekenler

1. Auth provider canlı doğrulama
   - 2026-05-12 kontrolü: canlı Supabase'de Apple ve Google provider açık.
   - Detay: `AUTH_LIVE_VERIFICATION_2026-05-12.md`.
   - Supabase Apple provider credentials girildi.
   - Apple kodlandı ve gerekli Apple/Supabase ayarları yapıldı.
   - 2026-05-15 TestFlight gerçek cihazda Apple Sign In geçti.
   - Apple provider `Client IDs` alanında native iOS bundle id `com.riskdetected.app` ve Services ID birlikte tanımlandı.
   - Canlı DB'de `auth.identities.provider = apple`, auth user ve `profiles` satırı doğrulandı.
   - Supabase Google provider credentials girildi.
   - Google native SDK ile mevcut kullanıcı girişi geçti.
   - Google native SDK ile yeni kullanıcı kaydı geçti.
   - Google Cloud OAuth consent screen şu an test modunda; release öncesi production/publish adımı tamamlanmalı.
   - `/auth/v1/settings` kontrolünde Apple/Google enabled görünüyor.

2. Email OTP / SMTP son canlı teyit
   - Resend/Supabase SMTP ayarları canlıda doğrulandı.
   - Email OTP ile kayıt geçti.
   - Email OTP ile giriş geçti.
   - TestFlight gerçek cihazda mail ve kod alanlarının klavye üstünde görünür kaldığı doğrulandı.
   - Release öncesi son smoke test olarak yeni kullanıcı + mevcut kullanıcı tekrar denenebilir.

3. RevenueCat / gerçek entitlement
   - RevenueCat SDK, Plus/Pro ürünleri ve webhook entegrasyonu tamamlandı.
   - TestFlight sandbox Plus satın alma testi geçti:
     - `riskdetected_plus_monthly`
     - `entitlement_ids = [plus]`
     - Supabase `user_subscriptions.tier = plus`
     - Supabase `profiles.tier = plus`
   - Kalan: Pro satın alma, restore purchase, iptal/expiration/downgrade eventleri test edilmeli.

4. Son manuel QA
   - Reports archive 21 kayıt simülatör smoke + 247 sentetik yoğun veri QA geçti.
   - Reports XLSX backend check geçti; TestFlight/gerçek cihaz share sheet final spot-check kalır.
   - Ana sayfa rapor kartından preview, X kapatma ve indir/paylaş test edilmeli.
   - Pro kullanıcı Pro canvas seçimi bir kez daha net pass alınmalı.
   - Yeni prompt sistemiyle Free ve Pro canlı analiz kıyas testi yapılmalı.
   - PDF, Pro PDF ve XLSX yeni bir analizden baştan sona üretilmeli.

5. Legal metin finali
   - KVKK, Kullanım koşulları ve Gizlilik Politikası metinleri uygulama içine markdown belge olarak eklendi.
   - Website yayını için hedef URL'ler:
     - `https://riskdetected.com/kvkk-aydinlatma-ve-acik-riza-metni`
     - `https://riskdetected.com/kullanim-kosullari`
     - `https://riskdetected.com/gizlilik-politikasi`
   - App Store privacy nutrition / veri kullanımı beyanları bu metinlerle tutarlı hale getirilmeli.

6. Supabase migration geçmişi
   - Done: remote base migration history repoya fetch edildi.
   - Done: kısa/bozuk timestamp'li lokal migration'lar temizlendi:
     - `20260504_ai_usage_logs.sql` duplicate olduğu için kaldırıldı.
     - `20260506_reports_storage.sql`, `20260506193000_reports_storage.sql` olarak geçerli timestamp'e taşındı.
   - Done: remote migration history schema değiştirmeden `repair` ile hizalandı; `supabase migration list` temiz.
   - Detay: `QA/Supabase_Migration_History_Repair_2026-05-15.md`.

### P1 - Güvenilirlik ve Operasyon

1. APNs gerçek push teslimatı
   - Apple Developer'da APNs `.p8` key oluşturulmalı.
   - Supabase secrets girilmeli:
     - `APNS_KEY_ID`
     - `APNS_TEAM_ID`
     - `APNS_BUNDLE_ID`
     - `APNS_PRIVATE_KEY`
     - `APNS_ENV`
   - TestFlight/gerçek cihaz push testi yapılmalı.
   - Analiz tamamlandı, rapor hazır ve güvenlik/account eventleri backend'den tetiklenmeli.

2. AI maliyet ve quota operasyonu
   - Ek Gemini API key'leri farklı Google Cloud projelerinden Supabase secrets'a girilmeli.
   - Her Google Cloud projesinde budget/quota alert açılmalı.
   - `ai_usage_logs` üzerinden günlük token, latency, fallback, error rate ve maliyet dashboard'u hazırlanmalı.
   - Pro için ücretli/kuota artırılmış model stratejisi netleştirilmeli.

3. Account deletion admin completion
   - Kullanıcının hesap silme talebi alınabiliyor.
   - Talebi gerçekten tamamlayacak privileged backend/admin akışı henüz yapılmalı.
   - Silme sonrası Storage, Auth user, analiz/rapor/veri ilişkileri uçtan uca doğrulanmalı.

4. Production hata ve log kontrolü
   - Test simulation env flag'leri production'da kapalı olmalı.
   - Edge Function loglarında kişisel veri/raw key sızıntısı olmadığı doğrulanmalı.
   - Support id ile DB/log lookup akışı dokümante edilmeli.

### P2 - Ürün Polish

1. Lokalizasyon
   - Dil tercihi saklanıyor ama gerçek string localization sistemi henüz bağlı değil.
   - İlk hedef ekranlar:
     - Auth,
     - Home,
     - Analysis/Canvas,
     - Result,
     - Reports,
     - Profile.
   - PDF/report output language ayrıca değerlendirilmeli.

2. Pro report defaults
   - Done: profil logosu, şirket, uzman adı, unvan, belge no, firma bilgisi ve varsayılan metod otomatik rapor varsayılanı olarak kullanılıyor.
   - Done: PDF/XLSX default akışı kod QA + simülatör smoke ile doğrulandı; detaylar `QA/Reports_Defaults_Archive_QA_2026-05-15.md`.
   - Follow-up: TestFlight/gerçek cihazda uzun firma/unvan metniyle final görsel spot-check yapılmalı.

3. Reports archive gelişimi
   - Done: açılır kart yapısı, arama/filtre, durum label'ları, boş/error state ve load-more davranışı yapıldı.
   - Done: 247 kayıt sentetik yoğun veri QA ile pagination, filtre, arama ve duplicate merge doğrulandı; detaylar `QA/Reports_Defaults_Archive_QA_2026-05-15.md`.
   - Follow-up: Production verisi oluştukça telemetry/performance spot-check alınmalı.

4. Profile ekranı içerik/tabs
   - Mevcut profil, tercihler, bildirimler, verilerim akışları var.
   - Daha net tab/section yapısı ve eksik içerik düzeni tasarlanabilir.

5. Paywall sayfası yenileme
   - Plus ve Pro plan kartları yeni limitlerle uyumlu olacak:
     - Plus: 10 standart analiz/gün, 2 detaylı analiz/gün, 150 rapor/ay.
     - Pro: 40 standart analiz/gün, 10 detaylı analiz/gün, 750 rapor/ay.
   - RevenueCat paketleri, restore purchase ve mevcut plan durumları daha net gösterilecek.
   - Limit dolu/free upgrade girişleriyle aynı görsel dilde, daha modern ve güven veren bir tasarım yapılacak.
   - TestFlight gerçek cihazda satın alma, restore ve plan geçiş görünümüyle QA alınacak.

6. Image privacy ileri adımlar
   - Yüz blur var.
   - Company logo blur ve cleaned-image-only storage policy daha sıkı hale getirilebilir.

7. Pro analiz kalitesi
   - Pro max 10 ve references var.
   - Daha sonra:
     - stronger model,
     - multi-pass validation,
     - sector/procedure checklist,
     - low-confidence recheck.

### P3 - App Store / Yayın Hazırlığı

1. Apple Developer capability kontrolü
   - Sign in with Apple entitlement.
   - Push notification entitlement.
   - Bundle id ve URL scheme.
   - Release signing/provisioning.

2. App Store metadata
   - App adı, açıklama, keyword, kategori.
   - Screenshot/video seti.
   - Support URL: `https://riskdetected.com`
   - Privacy Policy URL: `https://riskdetected.com/gizlilik-politikasi`
   - Terms URL: `https://riskdetected.com/kullanim-kosullari`
   - Privacy nutrition form.
   - Age rating.

3. TestFlight release checklist
   - Clean install onboarding.
   - Email OTP.
   - Apple/Google login.
   - Free günde 1 analiz limiti.
   - Plus/Pro purchase/restore.
   - Photo permission / gallery / camera.
   - Analysis -> Result -> PDF/XLSX -> share.
   - Dark mode.
   - Account deletion request.

## Eski Dosyalardan Arşivlenen / Güncelliğini Kaybeden Maddeler

- "Onboarding yapılacak" maddesi artık yapıldı; sadece final görsel/metin polish kalabilir.
- "AI canvas promptları kullanıcıdan alınacak" maddesi büyük ölçüde yapıldı; promptlar backend'e işlendi.
- "Max 2 canvas" eski davranıştı; yeni karar tek canvas ve uygulandı.
- "Free günlük analiz limiti 2" eski kuraldı; yeni kural Free günde 1 standart analiz.
- "Pro max 14" eski kuraldı; yeni kural Pro max 10.
- "Firebase phone bridge paused/deferred" eski durumdu; artık tamamen kaldırıldı.
- "P1.5 QA kalan satırlar" eski durumdu; matris E01-E18 geçti.
- "Reports sayfası tasarım refresh yapılacak" eski durumdu; açılır kartlı yeni yapı eklendi.
- "Reports archive arama/filtre/status/empty/load-more yapılacak" eski durumdu; uygulandı.
- "Pro report defaults profilden otomatik gelsin" eski durumdu; PDF/XLSX akışlarına bağlandı.
- "Supabase migration history temizlik kararı" eski durumdu; remote/local history eşitlendi.

## Önerilen Sıradaki Uygulama Sırası

1. Paywall sayfası yenileme ve Plus/Pro plan limit metinlerini UI'da netleştirme.
2. RevenueCat Pro satın alma + restore purchase + expiration/downgrade testi.
3. Legal final metinler ve App Store privacy hazırlığı.
4. APNs real-device/TestFlight push testi.
5. TestFlight tam uçtan uca release pass.
