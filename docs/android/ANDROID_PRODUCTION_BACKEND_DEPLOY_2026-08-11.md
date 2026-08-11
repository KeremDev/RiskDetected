# Android production backend hazırlığı — 11 Ağustos 2026

Production Supabase proje ref'i: `ppcrzemgiztzcgddbins`.

## Uygulanan paket

Production'a aşağıdaki additive migration'lar uygulandı:

1. Android multi-photo kalite override alanları (varsayılan inert)
2. Android analysis submission idempotency
3. Android legal policy (`enabled=false`)
4. Web account-deletion queue metadata ve worker schedule altyapısı
5. Profiles RLS policy konsolidasyonu
6. Analysis client-platform telemetrisi
7. Tam localization telemetry trigger sözleşmesinin restorasyonu
8. Account-deletion cron reconciliation
9. Owner onaylı Android hukuk belge registry kaydı (gate kapalı)
10. Android FCM token rotation için kurulum kimliği unique index'i

Repository'deki 20 kanonik Edge Function aynı production projesine dağıtıldı. Yeni
`process-account-deletion-queue` worker'ı `ACTIVE` durumundadır.

## Güvenlik ve kapılar

- `ACCOUNT_DELETION_ALLOWED_ORIGINS=https://riskdetected.com`
- Edge worker secret ile Vault secret aynı owner kontrollü rastgele değerle eşlendi; değer hiçbir
  belgeye, loga veya artefakta yazılmadı.
- Vault `project_url` ve queue secret doğrulaması: `2/2`.
- `riskdetected-account-deletion-hourly` cron doğrulaması: `1/1`, saatlik `:12`.
- Vault secret ile doğrudan production worker smoke çağrısı: HTTP `200`, `ok=true`, boş kuyrukta
  `processed=0`.
- Android `client`, `auth`, `analysis_submit`, `payments`, `notifications` ve `pdf_reports`
  kapılarının tamamı kapalıdır.
- Android legal policy kapalıdır; owner onayı registry'ye kaydedilmiş olsa da acknowledgement canary kapısı açılmadan zorlanmaz.
- iOS build-81 policy çağrısı başarılıdır ve iOS yanıtına `android_runtime_gates` eklenmemiştir.
- Production DB lint: yeni schema warning/error üretmedi. Beş istemci `SECURITY DEFINER` RPC'si
  test kanıtlı waiver kapsamındadır; leaked-password protection Supabase Free plan sınırı nedeniyle
  açılamadı.
- CORS: production site origin `200`; bilinmeyen origin `403`; oturumsuz silme isteği `401`.

## Yerel regresyon paketi

- Deno: `316/316`
- pgTAP/RLS/RPC: `485/485`
- Local DB lint: sıfır warning/error
- iOS `App/` source diff: sıfır

## Açık operasyon kapıları

- Owner nihai onayı `ANDROID_LEGAL_APPROVAL_RECORD_2026-08-09.json` dosyasına ve Android legal registry migration'ına 2026-08-11 tarihinde kaydedildi; bağımsız hukuk danışmanlığı iddiası yoktur.
- Play listing oluştuğunda Android release policy'deki `pending-play-listing` gerçek URL ve policy
  sürümüyle değiştirilecektir.
- Android kapıları yalnız review hesabı/version allowlist canary sırasında sırayla açılacaktır.
- Production'da gerçek web silme kuyruğu staging'deki tam E2E ile aynı kodu kullanır; sentetik
  production kullanıcı yaratılmadan yalnız CORS/auth negatif kontrolleri yapılmıştır.
