# Google Play Data Safety çalışma kâğıdı

Bu belge Play Console'a kopyalanacak nihai beyan değildir. Beyan, Internal Testing AAB'sinin
SDK ve ağ envanteri tekrar tarandıktan sonra owner tarafından onaylanır.

| Veri sınıfı | Kullanım | Aktarım/işleyici | Beyan notu |
| --- | --- | --- | --- |
| E-posta ve hesap kimliği | Auth, profil, destek, hesap silme | Supabase; gerekirse Resend | hesap yönetimi için |
| Kullanıcı fotoğrafları | yapay zekâ analizi ve saklama | Supabase Storage/Edge Function, AI sağlayıcı | kullanıcı tarafından yüklenir |
| Analiz ve rapor içeriği | sonuç, PDF/XLSX, arşiv | Supabase ve cihaz dosya alanı | kullanıcı içeriği |
| Şirket bilgileri/logo | rapor kişiselleştirme | Supabase | kullanıcı tarafından girilir |
| Satın alma/abonelik durumu | plan yetkisi ve restore | Google Play, RevenueCat, Supabase | ödeme kartı uygulamaya gelmez |
| Push token/device bilgisi | bildirim teslimi | Firebase Cloud Messaging, Supabase | bildirim izni sonrası |
| Crash/diagnostic | hata düzeltme | Firebase Crashlytics | debug kapalı; QA/release açık |
| Install referrer | first-party attribution | Google Play Install Referrer, RevenueCat | AD_ID yok |
| Uygulama etkinliği | kota, analiz/rapor kullanımı | Supabase | ürün işlevi ve güvenlik |

## Uygulanan veri minimizasyonu

- Manifestte `com.google.android.gms.permission.AD_ID` bulunmaz.
- Firebase Analytics SDK'sı eklenmez.
- Crashlytics custom key'leri yalnız platform, versionCode/versionName, build SHA ve güvenli hata
  sınıfıdır.
- Crashlytics'e e-posta, Supabase UID, token, fotoğraf yolu, ham analiz/FCM içeriği veya server
  error body gönderilmez.
- FCM payload'ı tip ve kayıt ID'leriyle sınırlıdır.
- İletim HTTPS üzerinden yapılır; uygulama ağ güvenliği cleartext trafiği kapatır.
- Uygulama veri satışı yapmaz.

## Play Console öncesi doğrulama

- Dependency tree ve merged manifest, Internal AAB ile yeniden çıkarılır.
- Google Play SDK Index uyarıları kontrol edilir.
- Her SDK için “collected/shared”, amaç, zorunlu/opsiyonel ve ephemeral alanları owner ile
  doğrulanır.
- Privacy URL `https://riskdetected.com/gizlilik`, hesap silme URL'si
  `https://riskdetected.com/hesap-silme` olarak canlı ve mobil uyumlu doğrulanır.
- Hesap silme bağlantısı login gerektirmeden açıklama/OTP başlangıç ekranını açar.
- Veri saklama süreleri Free 7 gün, Plus 30 gün, Pro süresiz backend gerçekliğiyle yeniden
  karşılaştırılır.
