# RiskDetected - Güncel Durum ve Kalan İşler

Tarih: 2026-05-20

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
- Güncel production kuralı: Free 1 standart rapor/gün, Plus 150/ay, Pro 750/ay.
- Free kullanıcı yalnızca 1 canvas seçebiliyor; Plus sınırlı gelişmiş canvas, Pro tam gelişmiş canvas erişimine sahip.
- Free analizde backend tarafındaki sabit bulgu kırpma kaldırıldı; Free prompt kalite hedefi 6-9 bulgu olarak güncellendi.
- Plus/Pro analizlerde bulgu hedefi 11-14 aralığına çıkarıldı.
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
- Google Auth Platform Audience publishing status `In production` durumuna alındı.
- Google Auth Platform Data Access tarafında yalnızca non-sensitive `userinfo.email`, `userinfo.profile` ve `openid` scope'ları var; sensitive/restricted scope yok.
- Google Auth Platform Branding URL'leri `riskdetected.com` altında dolduruldu; authorized domains içinde `riskdetected.com` eklendi.
- Google Auth Platform developer contact listesine `info@riskdetected.com` eklendi; User support email hâlâ Google'ın seçilebilir hesap kuralı nedeniyle `kayalar.kerem21@gmail.com`.
- Sosyal/e-posta giriş sonrası profil yoksa güvenli şekilde default `free` profil oluşturuluyor.
- Profil bootstrap artık "profil yok" ile "profil okunamadı" hatasını ayırıyor.
- Firebase/telefon auth tamamen kaldırıldı:
  - Firebase iOS SDK kaldırıldı.
  - `FirebaseBootstrap`, `FirebasePhoneAuthService`, `GoogleService-Info` kaldırıldı.
  - Firebase URL scheme kaldırıldı.
  - `firebase-phone-bridge` Edge Function canlıdan silindi.
  - `firebase_phone_auth_links` tablosu canlı DB'den silindi.

### Onboarding

- Onboarding V2 akışı eklendi ve RootView üzerinden aktif edildi.
- İlk kullanımda onboarding tamamlanmadan auth/main akışına geçiş engelleniyor; tamamlanınca `rd.onboarding.completed` lokal saklanıyor.
- Onboarding sonunda Apple, Google ve Email OTP girişleri doğrudan onboarding ekranı içinde çalışıyor.
- Onboarding email/OTP giriş paneli ayrı floating layer olarak klavye üstüne yerleşiyor; ana sayfa aşağı kaydırılmıyor.
- Onboarding sonrası gösterilecek ayrı Paywall V2 ekranı eklendi; uygulama içi paywall'dan bağımsız yönetilebilir.
- Paywall V2 Plus öncelikli tasarıma taşındı; Pro "Pro'yu incele" bağlantısı ile mevcut paywall'a yönleniyor.

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
- Gemini key pool altyapısı eklendi ve Free/Paid olarak ayrıldı:
  - `GEMINI_API_KEY_PRIMARY`
  - `GEMINI_API_KEY_SECONDARY`
  - `GEMINI_API_KEY_TERTIARY`
  - `GEMINI_API_KEY_PAID`
  - `GEMINI_API_KEY_PAID_SECONDARY` (opsiyonel)
- Free kullanıcılar yalnızca Free Gemini havuzunu; Plus/Pro kullanıcılar yalnızca backend subscription doğrulaması sonrası Paid Gemini havuzunu kullanır. Subscription lookup veya Paid secret eksikse Plus/Pro analizi Free key'e düşmeden destek koduyla fail-closed olur.
- Free model sırası güncel:
  - `gemini_primary + gemini-2.5-flash`
  - `gemini_secondary + gemini-2.5-flash`
  - `gemini_primary + gemini-3.1-flash-lite`
  - `gemini_secondary + gemini-3.1-flash-lite`
  - tüm Free Gemini havuzu retryable hata/limit ile tükenirse `groq_free_primary`.
- Free `gemini-3.1-flash-lite` çağrıları `thinkingLevel: "medium"` ile çalışır.
- Plus/Pro model sırası güncel:
  - `gemini_paid_primary + gemini-2.5-flash`
  - `gemini_paid_primary + gemini-2.5-pro`
  - `gemini_paid_primary + gemini-3.1-flash-lite`
  - `gemini_paid_secondary + gemini-2.5-flash`
  - `gemini_paid_secondary + gemini-2.5-pro`
  - tüm Paid Gemini havuzu retryable hata/limit ile tükenirse `groq_plus_pro_primary`.
- Plus/Pro `gemini-3.1-flash-lite` çağrıları `thinkingLevel: "high"` ile çalışır.
- 2026-05-20 prompt mimarisi canlıda parçalandı:
  - sabit `CORE_ANALYSIS_PROMPT` korunuyor;
  - onboarding, company ve tier context ayrı küçük bloklar olarak modele gidiyor;
  - onboarding cevapları görsel kanıtı filtrelemiyor, yalnız öncelik/ton/derinlik etkiliyor;
  - bu yapı Gemini implicit cache ihtimalini güçlendiriyor.
- 2026-05-20 tier çıktısı güncel:
  - Free: ayrı references ve root cause yok; mevzuat kartı boş/kilitli kalır, ancak `recommended_action` içinde pratik fayda varsa standart/mevzuat adı geçebilir.
  - Plus: kısa references ve kısa root cause üretir.
  - Pro: daha kapsamlı references ve daha teknik kök neden üretir.
- `findings.root_cause_text` ve `ai_usage_logs` prompt/personalization/context/cache/thinking/token telemetry kolonları production DB'de doğrulandı.
- `analyze` Edge Function production deploy edildi: version 76.
- Remote migration listesi `20260520161706_add_root_cause_and_ai_usage_telemetry.sql` için local/remote eşit.

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
- Standart PDF bulgu detay kartlarında Risk/Kanıt ve öneri metinleri karakter uzunluğuna göre dinamik satır yüksekliği kullanıyor; kısa bulgularda minimum yükseklik korunuyor.
- Detaylı risk analizi PDF tablolarında uzun "tehlikeli durum / davranış" metinleri için satır yüksekliği değişken hesaplanıyor.
- Risk analizi PDF/XLSX çıktılarında V1 karar uygulandı: `Sorumlu` alanı kaldırıldı, `Termin` risk seviyesine göre otomatik öneriliyor.
- Rapor PDF başlıklarında şirket logosu tanımlıysa RiskDetected yerine şirket logosu kullanılıyor.
- PDF rapor başlıklarında sayfa numarası `Sayfa X/Y` formatında toplam sayfayı gösterecek şekilde güncellendi.
- Sonuç detayında, kartlarda, PDF ve Excel raporlarında `Kök neden` alanı gösteriliyor.
- Plus abonelikte kısa referans ve kök neden görünürlüğü aktif; Pro'da daha kapsamlı teknik içerik görünür.
- `generate-excel-report` Edge Function production deploy edildi: version 30.

### Çoklu Firma

- Çoklu firma backend'i production DB'de canlı:
  - `public.companies`
  - `analyses.company_id`
  - `reports.company_id`
  - `reports.company_snapshot`
- Firma kayıtları kullanıcıya bağlı; aynı firma adı farklı kullanıcılarda karışmaz.
- Firma yazma kuralları DB/RLS/trigger ile Plus/Pro üyeliğe ve aktif firma limitlerine bağlıdır.
- Aktif aynı firma adı aynı kullanıcı içinde engellenir.
- Firma silme yerine v1'de arşivleme kullanılır; eski analiz/rapor bağlantıları bozulmaz.
- `analyze` firma doğrulama ve prompt company context desteğiyle canlıda.
- `generate-excel-report` firma snapshot, logo ve analiz backfill desteğiyle canlıda.
- 2026-05-20 production RLS fix canlı:
  - `private.company_limit_for_user(uuid)` için `authenticated` execute izni eklendi;
  - Profil > Firmalarım ekranındaki `permission denied for function company_limit_for_user` kaynaklı "Firmalar yüklenemedi" hatası giderildi.
- iOS tarafında lokal build'de hazır:
  - Profil > Firmalarım,
  - firma ekle/düzenle/arşivle,
  - analiz öncesi firma seçimi,
  - rapor ayarlarında firma seçimi,
  - rapor sırasında seçilen firma ile analiz backfill,
  - analiz geçmişi ve rapor arşivinde firma filtresi.
- Not: kullanıcıların cihazında bu UI bölümleri ancak yeni TestFlight/App Store build'i dağıtılınca görünür.

### Profil, Tema ve UI

- Profil bilgisi kaydetme çalışıyor.
- Profil logosu seçme/kaydetme çalışıyor.
- Profilde geçmiş analizler ve raporlar routing'i çalışıyor.
- 2026-05-20 Profil dark tema polish yapıldı:
  - avatar dark modda açık/beyaz yüzeye dönmüyor;
  - istatistik kartları, hesap/ayar listeleri, satır ikonları ve Pro kart vurgusu daha koyu/mat yüzeylere çekildi.
- Profil > Destek formu eklendi; konu, mesaj ve isteğe bağlı fotoğraf/dosya ekiyle `info@riskdetected.com` adresine mail gönderir.
  - Canlı mail gönderimi `RESEND_API_KEY` ile doğrulandı.
  - Destek formunda birden fazla ek aynı anda gönderme desteği yapıldı.
- Dark mode foundation tamamlandı:
  - Sistem / Aydınlık / Karanlık seçenekleri.
  - Core renk tokenları dark/light uyumlu.
  - Home, Result, Report settings, Profile, Analyses, Reports hızlı dark pass geçti.
- Dil tercihi lokal olarak saklanıyor ve şimdilik yalnızca Türkçe seçenek gösteriliyor.
- Gerçek lokalizasyon altyapısı eklendi:
  - `RDLanguage` tek dil kaynağı olarak kullanılıyor;
  - eski Sistem/English tercihleri otomatik Türkçe'ye normalize ediliyor;
  - rapor seçenekleri `language` alanı taşıyor;
  - PDF tarih/başlık metinleri seçili rapor dili üzerinden hazırlanıyor;
  - Rapor Oluştur sheet'inde şimdilik yalnızca Türkçe rapor dili gösteriliyor.
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
- 2026-05-20 Onboarding V2 build + simulator run başarılı; email ve OTP paneli klavye üstünde test edildi.
- 2026-05-20 Onboarding email/OTP klavye davranışı gerçek cihazda tekrar doğrulandı.
- 2026-05-20 Onboarding `Atla` linkine üzgün yüz ikonlu onay ekranı eklendi; kullanıcı onaylarsa onboarding bitip auth/main akışına geçiyor.
- 2026-05-20 Destek formunda birden fazla ek aynı anda gönderme desteği tamamlandı.
- 2026-05-20 Onboarding V2 light color scheme'e kilitlendi; global dark mode ayarı onboarding ekranlarını değiştirmiyor.
- 2026-05-20 TestFlight clean install akışı tamamlandı: Onboarding V2 -> Email OTP/Apple/Google -> onboarding paywall -> çarpı ile ana sayfa.
- 2026-05-20 İlk üyelik hoş geldin maili backend/iOS entegrasyonu eklendi:
  - `send-welcome-email` Edge Function Resend ile gönderir;
  - onboarding cevaplarına göre kısa kişiselleştirme ekler;
  - `profiles.welcome_email_sent_at/status/error` alanlarıyla duplicate gönderim engellenir;
  - production DB migration ve Edge Function deploy tamamlandı.
- 2026-05-22 Hoş geldin maili TestFlight gerçek cihaz QA tamamlandı:
  - yeni kullanıcıda onboarding cevapları kaydoluyor;
  - welcome mail başarılı şekilde gidiyor;
  - tekrar girişte duplicate mail gönderimi engelleniyor.
- 2026-05-20 Plus satın alma sonrası Pro görünme hatası düzeltildi; RevenueCat webhook/sync ve iOS tier çözümü güncellendi.
- 2026-05-20 RevenueCat Plus/Pro plan yansıması ve Profil dark tema düzeltmeleri sonrası iOS Simulator Debug build/run başarılı.

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
   - Google Cloud OAuth consent screen production/publish adımı tamamlandı; Audience publishing status `In production`.
   - `/auth/v1/settings` kontrolünde Apple/Google enabled görünüyor.

2. Email OTP / SMTP son canlı teyit
   - Resend/Supabase SMTP ayarları canlıda doğrulandı.
   - 2026-05-17 canlı smoke testinde `POST /auth/v1/otp` `200 {}` döndürdü.
   - Kullanıcıya gelen gerçek OTP ile `/auth/v1/verify` `200` döndürdü ve Supabase session üretti.
   - Test edilen e-posta Google identity ile aynı kullanıcıya bağlı olduğu için OTP doğrulaması mevcut kullanıcı hesabına session üretti.
   - Email OTP ile kayıt geçti.
   - Email OTP ile giriş geçti.
   - TestFlight gerçek cihazda mail ve kod alanlarının klavye üstünde görünür kaldığı doğrulandı.
   - Release öncesi son smoke test olarak yeni kullanıcı + mevcut kullanıcı tekrar denenebilir.

3. RevenueCat / gerçek entitlement
   - RevenueCat SDK, Plus/Pro ürünleri ve webhook entegrasyonu tamamlandı.
   - App Store Connect subscription ürünleri RevenueCat ile bire bir eşleşiyor:
     - Plus monthly/yearly
     - Pro monthly/yearly
   - Done: App Store Connect abonelik ticari ayarları tamamlandı:
     - Yıllık Plus/Pro ürünlerinde 7 gün ücretsiz deneme var.
     - Yıllık fiyat aylık fiyat x 11 mantığıyla ayarlandı.
     - Aylık Plus/Pro ürünlerinde deneme veya indirim yok.
   - TestFlight sandbox Plus satın alma testi geçti:
     - `riskdetected_plus_monthly`
     - `entitlement_ids = [plus]`
     - Supabase `user_subscriptions.tier = plus`
     - Supabase `profiles.tier = plus`
   - Pro satın alma, restore purchase, iptal/expiration/downgrade kontrolleri tamamlandı.
   - Done: TestFlight paywall USD görünümü app tarafında ele alındı; StoreKit/RevenueCat Türkçe/Türkiye bağlamında USD döndürürse paywall TL fallback fiyatlarını gösteriyor.
   - Follow-up: Yeni App Store Connect deneme/fiyat ayarlarının RevenueCat packages ve app paywall tarafında doğru göründüğü test edilecek.

4. Son manuel QA
   - Done: 2026-05-16 simülatörde final manuel QA kapatıldı.
   - Ana sayfa rapor kartından preview, X kapatma ve indir/paylaş geçti.
   - Pro kullanıcı Pro canvas seçimi geçti.
   - Yeni prompt sistemiyle Free kota-dolu akış ve Pro canlı analiz kıyası geçti.
   - Yeni analizden standart PDF, Reports içinden Pro PDF ve XLSX üretimi, preview ve iOS share sheet geçti.
   - QA sırasında bulunan rapor oluşturma sorunları düzeltildi: kota dolu durumda transient hata yerine Yükselt yönlendirmesi, Storage için ASCII-safe dosya adı ve tekrar üretilen PDF'lerde benzersiz belge numarası.

5. Legal metin finali
   - Done: KVKK, Kullanım koşulları ve Gizlilik Politikası metinleri uygulama içine markdown belge olarak eklendi.
   - Done: Legal metinler Riskdetected, `info@riskdetected.com`, Eskişehir ve `https://riskdetected.com` bilgileriyle güncellendi.
   - Done: Public legal URL'ler canlı:
     - `https://riskdetected.com/gizlilik`
     - `https://riskdetected.com/kullanim-kosullari`
     - `https://riskdetected.com/kvkk`
   - Done: App Store privacy nutrition / veri kullanımı beyan taslağı `QA/App_Store_Privacy_Nutrition_2026-05-16.md` altında hazırlandı.

6. Supabase migration geçmişi
   - Done: remote base migration history repoya fetch edildi.
   - Done: kısa/bozuk timestamp'li lokal migration'lar temizlendi:
     - `20260504_ai_usage_logs.sql` duplicate olduğu için kaldırıldı.
     - `20260506_reports_storage.sql`, `20260506193000_reports_storage.sql` olarak geçerli timestamp'e taşındı.
   - Done: remote migration history schema değiştirmeden `repair` ile hizalandı; `supabase migration list` temiz.
   - Detay: `QA/Supabase_Migration_History_Repair_2026-05-15.md`.

### P1 - Güvenilirlik ve Operasyon

1. APNs gerçek push teslimatı
   - Done: Apple Developer'da APNs `.p8` key oluşturuldu.
   - Done: Supabase secrets girildi ve varlığı doğrulandı:
     - `APNS_KEY_ID`
     - `APNS_TEAM_ID`
     - `APNS_BUNDLE_ID`
     - `APNS_PRIVATE_KEY`
     - `APNS_ENV`
   - Done: `send-push-notification` production deploy edildi; son doğrulamada active version `21`.
   - Follow-up: TestFlight/gerçek cihaz push teslimatı test edilecek.
   - Follow-up: rapor hazır ve güvenlik/account eventleri için backend push triggerları ayrıca bağlanacak.

2. Bildirimler, üyelik e-postası ve asenkron analiz devamlılığı
   - Done: Kullanıcı üyeliği başarıyla oluştuğunda otomatik "RiskDetected'a hoş geldiniz" e-postası için backend/iOS tetikleyici eklendi.
   - Done: TestFlight gerçek cihazda yeni kullanıcı kaydı, onboarding cevapları, mail teslimi ve duplicate engelleme uçtan uca doğrulandı.
   - Done: Analiz akışı kuyruklu modele geçirildi; `analysis_jobs` kuyruğu, `queued` status, worker operasyon alanları ve cron fallback production DB'ye uygulandı.
   - Done: `analyze` enqueue modeline geçti; `process-analysis-jobs` worker eklendi ve production deploy edildi.
   - Done: Analiz tamamlanınca backend `analysis_complete` push event'i tetikliyor; push hedefi Analiz geçmişi.
   - Done: PDF/XLSX rapor hazır olduğunda `report_ready` push event'i tetikleniyor; push hedefi Raporlar.
   - Done: RevenueCat abonelik/sync ve hesap silme tamamlama akışlarında `account_updates` push event'i tetikleniyor; push hedefi Profil.
   - Done: iOS analiz ekranı backend status polling ile sonucu bekliyor; uygulama kapanırsa backend job devam ediyor.
   - Done: Uygulama foreground'dayken `analysis_complete` banner'ı bastırılıyor; push tap Analiz geçmişi/Raporlar/Profil sekmelerine yönlendiriyor.
   - Follow-up: TestFlight gerçek cihazda izin, token kaydı, uygulamadan çıkınca analiz devamı, analiz/rapor/account push teslimi ve sekme yönlendirmesi uçtan uca test edilecek.
   - Follow-up: Hata/timeout durumlarında kullanıcı mesajı ve destek kodu gerçek cihazda doğrulanacak.

3. AI maliyet ve quota operasyonu
   - Paid Gemini API key `GEMINI_API_KEY_PAID` olarak Supabase secrets'a girilmeli; opsiyonel yedek için `GEMINI_API_KEY_PAID_SECONDARY` kullanılabilir.
   - Plus/Pro fallback kuruldu: Paid Gemini havuzu yeni model sırasıyla denenir; tüm paid havuz retryable hata/limit ile tükenirse ayrı `GROQ_API_KEY_PLUS_PRO` fallback devreye alınır. Plus/Pro fallback hiçbir durumda Free Gemini key havuzuna düşmemeli.
   - Free havuz için ek Gemini API key'leri farklı Google Cloud projelerinden Supabase secrets'a girilmeli.
   - Free fallback: Gemini Free havuzu `gemini_primary/secondary + gemini-2.5-flash`, ardından `gemini_primary/secondary + gemini-3.1-flash-lite` sırasıyla denenir; tüm havuz retryable hata/limit ile tükenirse Groq vision fallback devreye girer. Secret adı `GROQ_API_KEY_FREE`; opsiyonel model override `GROQ_FREE_MODEL`. Varsayılan model `meta-llama/llama-4-scout-17b-16e-instruct`.
   - Plus/Pro continuity fallback: Paid Gemini havuzu retryable hata/limit ile tükenirse ayrı Groq fallback devreye alınabilir. Secret adı `GROQ_API_KEY_PLUS_PRO`; opsiyonel model override `GROQ_PLUS_PRO_MODEL`. Groq free tier key kullanılsa bile Free fallback secret'ından ayrı tutulmalı; log alias `groq_plus_pro_primary` olmalı.
   - Her Google Cloud projesinde budget/quota alert açılmalı.
   - `ai_usage_logs` üzerinden günlük token, latency, fallback, error rate ve maliyet dashboard'u hazırlanmalı.
   - Pro için ücretli/kuota artırılmış model stratejisi netleştirilmeli.
   - Later: Gemini Prompt/Context Caching değerlendirilecek.
     - Önce davranış değiştirmeden cache metrikleri izlenecek: `cachedContentTokenCount`, cache hit ratio, prompt version/hash, model ve api key alias.
     - Explicit cache yalnızca Plus/Pro paid Gemini havuzu için düşünülmeli; Free tarafı şimdilik implicit caching + log gözlemiyle kalabilir.
     - Cache'e kullanıcı fotoğrafı, metni, firma bilgisi veya özel kullanıcı prompt'u konmamalı; sadece statik RiskDetected İSG talimatları, metodoloji, mevzuat/checklist ve JSON kuralları konmalı.
     - `gemini-2.5-pro` ve fallback `gemini-2.5-flash` için ayrı cache gerekir; cache model bazlıdır.
     - Cache başarısız/expired olduğunda analiz cache'siz devam etmeli; hiçbir durumda Plus/Pro trafiği Free Gemini havuzuna düşmemeli.
     - Düşük hacimde storage maliyeti faydayı azaltabileceği için önce ölçüm, sonra 30-60 dk TTL ile kontrollü test önerilir.

4. Account deletion admin completion
   - Kullanıcının hesap silme talebi alınabiliyor.
   - Done: `account-deletion-complete` privileged Edge Function eklendi.
   - Done: request kaydı Auth user silindikten sonra audit için korunacak şekilde migration eklendi.
   - Done: function Storage `photos`/`reports`/`logos` prefix temizliği, Supabase Auth admin delete ve request completion kaydı yapıyor.
   - Follow-up: disposable TestFlight hesabıyla production spot-check yapılmalı; detaylar `QA/Account_Deletion_Completion_2026-05-16.md`.

5. Production hata ve log kontrolü
   - Done: iOS simulation flag'leri `#if DEBUG` ile release build'de kapalı.
   - Done: production Supabase secrets listesinde test simulation flag adı bulunmadı.
   - Done: Edge Function logları ham user id/path/provider detail yerine support/request id, hash ve bounded error summary kullanacak şekilde sıkılaştırıldı.
   - Done: support id ile DB/log lookup runbook'u `QA/Production_Log_Privacy_Support_Runbook_2026-05-16.md` altında hazırlandı.
   - Done: değişen Edge Function'lar deploy edildi: `analyze` v45, `generate-excel-report` v17, `support-contact` v4, `send-push-notification` v7, `retention-cleanup` v14, `account-deletion-complete` v3.

### P2 - Ürün Polish

1. Lokalizasyon
   - Done: gerçek dil modeli ve string lookup altyapısı eklendi.
   - Done: Profile > Tercihler yalnızca Türkçe seçenek gösteriyor; eski Sistem/English kayıtları Türkçe'ye normalize ediliyor.
   - Done: PDF/report options artık `language` taşıyor; Rapor Oluştur ekranında rapor dili alanı Türkçe olarak bağlı.
   - Follow-up: ikinci dil eklendiğinde ilk çeviri hedef ekranları:
     - Auth,
     - Home,
     - Analysis/Canvas,
     - Result,
     - Reports,
     - Profile.
   - Follow-up: PDF/XLSX tüm statik tablo etiketleri için ikinci dil çevirileri eklenecek.

2. Çoklu firma, analiz eşleştirme ve rapor filtreleri
   - Done: DB modeli, RLS, migration, firma limitleri, aynı kullanıcı duplicate engeli ve eski profil firma alanlarından ilk firma backfill eklendi.
   - Done: `companies`, `analyses.company_id`, `reports.company_id`, `reports.company_snapshot` production DB'de canlı.
   - Done: `analyze` ve `generate-excel-report` firma doğrulama, prompt context, snapshot ve analiz backfill desteğiyle deploy edildi.
   - Done: iOS lokal build'de Profil > Firmalarım, analiz öncesi firma seçimi, rapor firma seçimi, analiz/rapor firma filtreleri hazır.
   - Done: `Firmalarım` RLS helper execute grant hatası production DB'de düzeltildi; authenticated role ile boş liste sorgusu doğrulandı.
   - Follow-up: bu UI'nın kullanıcı cihazına görünmesi için yeni TestFlight/App Store build'i dağıtılmalı.
   - Follow-up: firma bazlı adres, sorumlu kişi, varsayılan termin/sorumlu gibi ek alanlar v2'de değerlendirilecek.

3. Termin tarihi ve sorumlu alanları
   - Done: V1 ürün kararı uygulandı ve çalışıyor.
   - Done: `Sorumlu` kolonu raporlardan kaldırıldı.
   - Done: `Termin` alanı risk seviyesine göre otomatik öneriliyor.
   - Later: firma/bölüm bazlı sorumlu şablonları V2'de ayrıca değerlendirilecek.

4. Pro report defaults
   - Done: profil logosu, şirket, uzman adı, unvan, belge no, firma bilgisi ve varsayılan metod otomatik rapor varsayılanı olarak kullanılıyor.
   - Done: PDF/XLSX default akışı kod QA + simülatör smoke ile doğrulandı; detaylar `QA/Reports_Defaults_Archive_QA_2026-05-15.md`.
   - Follow-up: TestFlight/gerçek cihazda uzun firma/unvan metniyle final görsel spot-check yapılmalı.

5. Reports archive gelişimi
   - Done: açılır kart yapısı, arama/filtre, durum label'ları, boş/error state ve load-more davranışı yapıldı.
   - Done: 247 kayıt sentetik yoğun veri QA ile pagination, filtre, arama ve duplicate merge doğrulandı; detaylar `QA/Reports_Defaults_Archive_QA_2026-05-15.md`.
   - Done: production telemetry/performance spot-check alındı; canlı `reports` indeksleri ve satır dağılımı kontrol edildi, duplicate `reports_user_id_idx` migration ile kaldırıldı, app tarafında PII'siz initial/load-more telemetry eklendi. Detay: `QA/Reports_Archive_Production_Spot_Check_2026-05-16.md`.

6. Profile ekranı içerik/tabs
   - Mevcut profil, tercihler, bildirimler, verilerim akışları var.
   - Done: Karanlık temada profil avatarı, kart yüzeyleri, ikon arka planları ve Pro kart vurgusu daha koyu/mat hale getirildi.
   - Daha net tab/section yapısı ve eksik içerik düzeni tasarlanabilir.

7. Onboarding cevapları, metin revizyonu ve prompt otomasyonu
   - Done: Onboardingde alınan uzmanlık sınıfı, sektör, denetim sıklığı ve çalışılan tehlike sınıfı analiz promptlarına kontrollü şekilde yansıtılıyor.
   - Done: Kullanıcıya özel prompt davranışı guardrail ile ayrıldı; görsel kanıt filtresi değil, öncelik/ton/derinlik bağlamı olarak kullanılıyor.
   - Done: Prompt/personalization/context/cache/thinking/token telemetry kolonları production DB'de canlı.
   - Done: Onboarding `Atla` linki onay ekranına bağlandı; "Sana özel sonuçlar veremeyeceğiz" mesajı ve üzgün yüz ikonu gösteriliyor.
   - Done: Onboarding V2 her zaman beyaz/light temaya kilitlendi; cihaz dark mode ayarı onboarding ekranlarını değiştirmiyor.
   - Done: Onboarding ve uygulama içi bazı metin/sloganlarda revizyon yapıldı. [TAMAMLANDI - 2026-06-02]

8. Sabit analiz prompt revizyonu
   - Done: Backend sabit prompt `CORE_ANALYSIS_PROMPT` olarak korundu; dynamic onboarding/company/tier context ayrı bloklara ayrıldı.
   - Done: Tekrar eden/gereksiz prompt parçaları system prompt ve audit çıktılarından uzaklaştırıldı.
   - Done: Free/Plus/Pro references ve root cause davranışı ayrıştırıldı.
   - Done: `deno check`, `deno fmt --check`, iOS build/run ve ilgili dosyalarda `git diff --check` temiz geçti.

9. Paywall sayfası yenileme
   - Done: Uygulama içi Paywall V1 ve Plus öncelikli Paywall V2 ayrıştırıldı.
   - Done: Free kota dolu / yükseltme girişleri Paywall V2'ye yönleniyor.
   - Done: Paywall V2'de seçilebilir Free kart kaldırıldı; düşük kontrastlı "Ücretsiz devam et" linki CTA altında kullanılıyor.
   - Done: Paywall V2 Plus kartı geniş, Pro ikincil inceleme linki olarak düzenlendi.
   - Follow-up: Onboarding sırasında alınan sektör/sınıf/frekans bilgilerine göre onboarding paywall metni kişiselleştirilecek.
   - Onboarding cevaplarına göre farklı paywall sayfaları veya paywall varyasyonları gösterilecek.
   - TestFlight gerçek cihazda satın alma, restore ve plan geçiş görünümüyle QA alınacak.
   - Done: Plus satın alma sonrası Pro görünme hatası backend webhook/sync ve iOS tier çözümünde düzeltildi.

10. Image privacy ileri adımlar
   - Yüz blur var.
   - Company logo blur ve cleaned-image-only storage policy daha sıkı hale getirilebilir.

11. Pro analiz kalitesi
   - Pro max 10 ve references var.
   - Daha sonra:
     - stronger model,
     - multi-pass validation,
     - sector/procedure checklist,
     - low-confidence recheck.

### P3 - App Store / Yayın Hazırlığı

1. Apple Developer capability kontrolü
   - Done: Sign in with Apple, Push Notifications/APNs, In-App Purchase, camera/photo izinleri, URL scheme ve privacy manifest kontrol edildi.
   - Done: İlk release için hedef cihaz ailesi iPhone-only yapıldı; iPad screenshot/UI QA yükü sonraki faza bırakıldı.
   - Done: Local archive privacy manifest kontrolü tamamlandı; app root, GoogleSignIn ve RevenueCat `PrivacyInfo.xcprivacy` dosyaları archive içine giriyor.
   - Done: Release build ayarı `APS_ENVIRONMENT=production` olacak şekilde netleştirildi; manual `CODE_SIGN_IDENTITY` override kaldırıldı ve Xcode automatic signing'e bırakıldı.
   - Done: Xcode Archive'daki "conflicting provisioning settings" hatası giderildi; `/tmp/RiskDetectedArchiveAfterSigningFix.xcarchive` başarıyla oluştu.
   - Done: Final Archive / Xcode Organizer kontrolü kullanıcı tarafından tamamlandı; embedded entitlements, APNs production, distribution signing, privacy report ve GoogleSignIn / RevenueCat privacy manifestleri kontrol edildi.

2. App Store metadata
   - Done: App adı, subtitle, açıklama, keyword, kategori, review notes, support/legal URL, screenshot/video çekim planı, privacy nutrition özet formu ve age rating cevapları hazırlandı.
   - Done: Detay doküman: `QA/App_Store_Submission_Preparation_2026-05-16.md`.
   - Done: public legal URL'ler canlı ve App Store Connect alanlarına girilmeye hazır.
   - Follow-up: clean demo data ile final iPhone screenshot seti üretilmeli.

3. TestFlight release checklist
   - Done: Clean install Onboarding V2.
   - Done: Email OTP.
   - Done: Apple/Google login.
   - Done: Onboarding paywall -> çarpı ile ana sayfa akışı.
   - Free günde 1 analiz limiti.
   - Done: Plus/Pro purchase/restore.
   - Done: Paywall USD fiyat görünümü için TL fallback uygulandı.
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

1. App Store privacy nutrition taslağını App Store Connect ekranında final soru setiyle bire bir kontrol edip girme.
2. APNs production secrets + real-device/TestFlight push testi.
3. TestFlight tam uçtan uca release pass.
4. Clean demo data ile final iPhone screenshot seti üretme.
5. App Review test hesabı ve OTP erişim planını hazırlama.
6. Opsiyonel: App Preview video hazırlama.
