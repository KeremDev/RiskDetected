# Android staging gerçek E2E kanıtı — 11 Ağustos 2026

Bu klasör yalnız PII içermeyen saha fotoğraflarıyla yapılan Android staging doğrulamasını
saklar. Kullanıcı, analiz, rapor, token ve submission UUID'leri kanıta yazılmamıştır.

## Analiz matrisi

| Akış | Sonuç | Android UI | Backend sonucu |
|---|---|---|---|
| 1 fotoğraf | Başarılı | Waiting, recovery ve sonuç; 2 bulgu / 1 fotoğraf | `completed` |
| 2 fotoğraf | Başarılı | Waiting ve sonuç; 4 bulgu / 2 fotoğraf | `completed`, Android/Pro |
| 3 fotoğraf | Başarılı | Waiting, sonuç ve rapor overlay'leri; 5 bulgu / 3 fotoğraf | `completed`, Android/Pro |

İlk iki-fotoğraf denemesi kanıt olarak başarılı sayılmadı: AI güvenlik doğrulayıcısı
`PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY` ile fail-safe davrandı. Farklı gerçek fotoğraf çiftiyle
Android istemcisinden tekrarlanan çalışma başarıyla tamamlandı ve `two-photo-retry/` altında
saklandı.

İlk tek-fotoğraf çalışmasında Edge Function'ın hata gövdesinin Android'de genel ağ hatasına
dönüştüğü tespit edildi. `supabase-kt` `RestException` sınıflandırması düzeltildikten sonra iki ve
üç fotoğraf gönderimleri doğrudan Android istemcisinden tamamlandı; tek-fotoğraf taslağı exact
submit + Android polling/recovery ile sonuç ekranına taşındı.

## Rapor kanıtı

- PDF: 3 gerçek sayfa, 915.412 byte, SHA-256
  `9bc9f8932a3808d5d5f69871d62fb894a973c871853d08017f8b0ee355d80c43`
- XLSX: geçerli Office Open XML, 85.799 byte, SHA-256
  `18093a50b918da00168c69c9436253a9aaf44ad82e38137ee2817e6a8568ffaa`
- Backend snapshot: 3 kaynak fotoğraf, 5 bulgu, `tr` / `tr-TR`; PDF `page_count=3`.

## Bildirim uç senaryoları

- Android 13+ izin reddi uygulamayı bozmadı.
- Profil'den daha sonra izin verildiğinde FCM kaydı `notifications_enabled=true` oldu.
- Gerçek analiz ve rapor kayıtları foreground, background ve process-killed durumda doğru
  sekmelere yönlendirildi.
- Çıkıştan önce mevcut installation'a ait FCM satırı silindi (`1 → 0`) ve back stack bağımsız
  giriş ekranına temizlendi.
- Filtrelenmiş loglarda ham payload, kayıt UUID'si, token, e-posta veya mesaj gövdesi yoktur.

## Kapsam sınırı

Bu çalışma üç gerçek analizle sınırlandırıldı. Uzman kalite onayı, ağ kesintisi/idempotency,
detaylı analiz ve Free/Plus/Pro kota sınırı ayrı release kapıları olarak açık kalır.
