# Google Play Data Safety owner onay paketi

> **8 Eylül 2026 Meta App Events farkı:** Bu belgedeki 11 Ağustos Play Console taslak
> durumu, Meta Android SDK eklenmeden önceki beyandır ve artık yeni SDK içeren bir build için
> tek başına geçerli değildir. Play incelemesine göndermeden önce Uygulama işlemleri, İşlem geçmişi
> ve Cihaz veya diğer kimlikler veri türlerine **Analiz** ile **Reklam veya pazarlama** amaçları
> eklenmelidir. Meta'ya aktarımın Google'ın hizmet sağlayıcı istisnasına girip girmediği, hesapta
> kabul edilen güncel Meta Business Tools/Data Processing şartlarıyla teyit edilmelidir; teyit
> edilene kadar `shared=yes` daha korumacı beyandır. Klasik ve Privacy Sandbox reklam kimliği
> izinleri, Topics ve Custom Audience izinleri birleşmiş manifestten çıkarılmıştır; yalnız
> toplulaştırılmış Attribution Reporting izni korunur. Teknik kanıt ve release kapısı için
> `docs/META_ANDROID_INTEGRATION_2026-09-08.md` esas alınır.

İmzalı release AAB'nin SDK, merged manifest ve ağ envanteri tarandı. Aşağıdaki kapsam Play
Console formuna girilecek owner onay paketidir; form gönderimi ve Google'ın güncel soru akışındaki
son seçimler Play Console'da ayrıca kaydedilecektir.

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

## Tamamlanan doğrulama

- Release dependency tree, merged manifest ve AAB secret/PII/`AD_ID` taraması geçti.
- Google Play SDK Index uyarıları AAB yüklendikten sonra Pre-launch aşamasında tekrar kontrol edilir.
- Her SDK için “collected/shared”, amaç, zorunlu/opsiyonel ve ephemeral alanları owner ile
  doğrulanır.
- Privacy URL `https://riskdetected.com/gizlilik`, hesap silme URL'si
  `https://riskdetected.com/hesap-silme` olarak canlı ve mobil uyumlu doğrulandı.
- Hesap silme bağlantısının login gerektirmeden açıklama/OTP başlangıç ekranını açtığı doğrulandı.
- Veri saklama süreleri Free 7 gün, Plus 30 gün, Pro süresiz backend sözleşmesiyle eşleşiyor.

## Play Console taslak durumu — 2026-08-11

Play Console Veri Güvenliği taslağına aşağıdaki 15 veri türü kaydedildi:

- Ad, e-posta adresi, kullanıcı kimliği, adres, telefon numarası ve diğer kişisel bilgiler.
- İşlem geçmişi.
- Fotoğraflar ile dosya ve dokümanlar.
- Kilitlenme günlükleri ve performans teşhisleri.
- Uygulama işlemleri, kullanıcı tarafından oluşturulan içerik ve diğer uygulama etkinliği.
- Cihaz veya diğer kimlikler.

Supabase, Resend, Google/Firebase, RevenueCat, Crashlytics ve AI sağlayıcısı; veriyi geliştirici
talimatıyla işleyen hizmet sağlayıcılar olduğundan Google Play'in hizmet sağlayıcı istisnasına göre
bu aktarım “toplandı” olarak, “paylaşıldı” olmadan beyan edildi. Reklam veya pazarlama amacı
işaretlenmedi. Seçimler, amaçlar, zorunlu/opsiyonel durumlar ve `ephemeral=false` yanıtları Play'den
yeniden dışa aktarılan CSV ile doğrulandı.

Tek açık Play Console blokajı hesap silme URL doğrulayıcısıdır. Taslakta doğru URL
`https://riskdetected.com/hesap-silme` kayıtlıdır ve URL; normal istemci, Googlebot, IPv4 ve IPv6
isteklerinde HTTP 200 döndürmektedir. Buna rağmen Play Console doğrulayıcısı aynı oturumda bu URL,
Vercel production alias'ı ve kontrol amacıyla denenen bağımsız çalışan URL'ler için HTTP 403
bildirmiştir. Yanlış URL veya hesap silme beyanını kaldırarak bu kontrol atlanmayacaktır.

Tekrar üretilebilir içe aktarma dosyası şu komutla hazırlanır:

```sh
node scripts/generate_play_data_safety_csv.mjs \
  ~/Downloads/data_safety_export.csv \
  ~/Downloads/riskdetected_data_safety_ready.csv
```

## Kalan owner gönderimi

- Play URL doğrulayıcısı düzeldiğinde “İleri” ile önizlemeye geç.
- Önizlemeyi bu belge ve yeniden dışa aktarılan CSV ile karşılaştır.
- Son gönderim/ilan işlemini owner hesabından tamamla.
