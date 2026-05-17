# App Store Privacy Nutrition - Final Entry Draft - 2026-05-16

Bu dosya RiskDetected için App Store Connect > App Privacy ekranına girilecek veri beyanı taslağıdır. Amaç eksik beyan yüzünden App Review riski almamak; uygulama, Supabase backend, Google Sign-In, RevenueCat ve Google Gemini/AI akışlarıyla tutarlı, muhafazakar ve savunulabilir cevap vermektir.

Resmi Apple referansları:

- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Privacy Manifest Files: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- Required Reason APIs: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api

## Kabul Stratejisi

- Eksik beyan verme. Apple, üçüncü taraf SDK'lar ve backend servisleri dahil toplanan verilerin açıklanmasını ister.
- "Tracking" ile "app functionality/analytics" ayrıdır. RiskDetected'te reklam takibi veya data broker paylaşımı yok, bu yüzden tracking cevabı "No" olmalı.
- Apple ödeme kartı bilgisini RiskDetected'e vermez. Bu yüzden "Payment Info / Credit Info" seçilmemeli; ama RevenueCat/App Store abonelik geçmişi için "Purchase History" seçilmeli.
- Fotoğraf ve metin analizi kullanıcı içeriğidir. EXIF temizliği yapılsa bile fotoğrafın görsel içeriği analiz/saklama/rapor için işlendiğinden "Photos or Videos" ve "Other User Content" seçilmeli.
- Uygulama cihaz konumu istemiyor. Ancak gizlilik metni IP/güvenlik kayıtlarını içeriyor. Bu yüzden App Store Connect'te "Coarse Location" seçmek daha güvenli.
- Seçilen tüm veri tipleri "Linked to User" olmalı. Şu an ayrı, geri bağlanamaz anonim analytics hattı yok.

## App Store Connect Cevapları

### Tracking

| Soru | Cevap |
| --- | --- |
| Do you or your third-party partners use data from this app to track users? | No |
| App Tracking Transparency required? | No |

Gerekçe: IDFA yok, reklam SDK yok, üçüncü taraf siteler/uygulamalar arasında reklam veya data broker takibi yok.

### Privacy Policy

| Alan | Değer |
| --- | --- |
| Privacy Policy URL | `https://riskdetected.com/gizlilik` |
| Privacy Choices URL | Boş bırakılabilir. Zorunlu alan gibi gelirse geçici olarak `https://riskdetected.com/gizlilik` kullanılabilir. |

### Data Linked To The User

App Store Connect'te aşağıdaki veri türlerini "Collected" ve "Linked to the user" olarak gir.

| Kategori | Veri türü | Amaçlar | Neden |
| --- | --- | --- | --- |
| Contact Info | Name | App Functionality, Product Personalization | Profil adı, rapor hazırlayan adı, Apple/Google profil bilgisi. |
| Contact Info | Email Address | App Functionality | Email OTP, Apple/Google auth e-postası, destek ve hesap işlemleri. |
| Contact Info | Phone Number | App Functionality, Product Personalization | Kullanıcı isteğe bağlı profil/rapor firma bilgisi olarak telefon girebiliyor. |
| Contact Info | Other User Contact Info | App Functionality | Destek veya rapor/firma alanlarında kullanıcı başka iletişim bilgisi girebilir. |
| Sensitive Info | Sensitive Info | App Functionality | İş güvenliği fotoğrafları yaralanma, sağlık/güvenlik durumu, yüz, PPE/KKD gibi hassas bağlam içerebilir. Uygulama bunu reklam/takip için kullanmaz. |
| User Content | Photos or Videos | App Functionality, Product Personalization | Kamera/galeri fotoğrafları, analiz görselleri, profil/firma logosu, destek eki. |
| User Content | Customer Support | App Functionality | Destek konusu, mesaj, destek kodu ve isteğe bağlı ekler. |
| User Content | Other User Content | App Functionality, Product Personalization | Metin analizi girdisi, saha/firma bilgileri, rapor başlığı/notları, AI analiz/rapor içeriği. |
| Identifiers | User ID | App Functionality, Analytics | Supabase user UUID, RevenueCat app user id, analiz/rapor sahipliği. |
| Identifiers | Device ID | App Functionality | APNs device token ve consent audit için identifierForVendor. IDFA değildir. |
| Purchases | Purchase History | App Functionality | RevenueCat/App Store abonelik durumu, ürün id, entitlement, yenileme/iptal eventleri. |
| Usage Data | Product Interaction | App Functionality, Analytics | Analiz sayısı, kota kullanımı, rapor oluşturma/indirme/silme, özellik erişimi. |
| Usage Data | Other Usage Data | App Functionality, Analytics | AI usage logs, token/latency/error metadata, request/support id, retry/fallback bilgileri. |
| Diagnostics | Performance Data | App Functionality, Analytics | AI/report akışlarında süre/latency/performans kayıtları. |
| Diagnostics | Other Diagnostic Data | App Functionality, Analytics | Hata kodları, HTTP status, support id, servis fallback/retry logları. |
| Location | Coarse Location | App Functionality | Uygulama konum izni istemez; ancak IP/security logları yaklaşık konum sayılabileceği için muhafazakar şekilde seç. |

### Conditional / Formda Görürsen

| Veri türü | Ne yapmalı |
| --- | --- |
| Environment Scanning / Surroundings | App Store Connect bu kategoriyi açıkça sunar ve "uploaded scene/workplace photos analyzed for surroundings" kapsamına sokarsa seçilebilir. Formda yoksa ayrıca bir şey seçme; mevcut beyan "Photos or Videos" + "Other User Content" ile kapsıyor. |
| Crash Data | Şu an üçüncü taraf crash SDK yok. App'e Sentry/Firebase Crashlytics vb. eklenirse seç. |
| Advertising Data | Seçme. Reklam SDK yok. |
| Other Data Types | Sadece App Store Connect'te yukarıdaki alanların karşılamadığı yeni bir veri alanı görürsen seç. Şu an gerek yok. |

### Data Not Collected

Mevcut release için seçme:

- Contact Info > Physical Address
- Health & Fitness
- Financial Info > Payment Info
- Financial Info > Credit Info
- Contacts
- Browsing History
- Search History
- Advertising Data
- Audio Data
- Precise Location
- Fitness
- Hands
- Head

Not: Apple'ın kategori adları App Store Connect ekranında değişirse isimleri bire bir değil anlamlarına göre eşleştir.

### Purposes To Avoid

Şu an seçme:

- Third-Party Advertising
- Developer's Advertising or Marketing
- Other Purposes

Marketing notification preference alanı kodda scaffold olarak var; aktif kampanya/marketing gönderimi yok. Pazarlama bildirimi veya e-posta kampanyası başlarsa App Privacy ve KVKK/Gizlilik metinleri yeniden güncellenmeli.

## Privacy Manifest / Binary Kontrolü

Projeye `App/PrivacyInfo.xcprivacy` eklendi.

- `NSPrivacyTracking = false`
- Required Reason API:
  - `NSPrivacyAccessedAPICategoryUserDefaults`
  - Reason: `CA92.1`

Gerekçe: Uygulama `UserDefaults` ile onboarding tamamlandı bilgisi, tema ve dil tercihlerini saklıyor. Bu sadece uygulama içi tercih/app functionality amaçlı.

Üçüncü taraf SDK manifestleri build çıktısında ayrıca kontrol edilmeli:

- GoogleSignIn bundle privacy manifest mevcut.
- RevenueCat bundle privacy manifest mevcut.
- Supabase Swift için final arşivde privacy report kontrol edilmeli.

## Final Submission Checklist

1. Done: Legal sayfaların URL'leri canlı:
   - `https://riskdetected.com/gizlilik`
   - `https://riskdetected.com/kullanim-kosullari`
   - `https://riskdetected.com/kvkk`
2. App Store Connect > App Privacy ekranında yukarıdaki "Data Linked To The User" tablosu girilmeli.
3. Tracking cevabı "No" olmalı.
4. Payment/Credit Info seçilmemeli; Purchase History seçilmeli.
5. Xcode Organizer privacy report final archive için kontrol edilmeli.
6. App Store submission öncesi üçüncü taraf SDK listesi tekrar kontrol edilmeli:
   - Supabase
   - GoogleSignIn
   - RevenueCat
7. Yeni analytics/crash/ads/location/audio/contacts SDK'sı eklenirse bu dosya ve App Store Connect cevapları güncellenmeli.

## Review Notu

Bu taslak App Review riskini azaltmak için muhafazakar hazırlanmıştır. Kullanıcıya App Store'da biraz daha geniş veri etiketi gösterir; buna karşılık eksik/yanlış beyan nedeniyle red veya metadata correction riskini azaltır.
