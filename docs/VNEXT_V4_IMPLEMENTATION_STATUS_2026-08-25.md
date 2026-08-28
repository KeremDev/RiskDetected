# Routing-First v4 — Uygulama Durumu

## İzolasyon

- Engine `vnext-v4`, mevcut `vnext-v3` ile yan yana çalışır.
- Rota üçlü kapıdır: private allowlist + API v3 capability + kill-switch/config.
- Genel yayın onayı `false`; rollout yalnız `user_allowlist`.
- V3 promptu, provider sözleşmesi ve skor motoru değiştirilmedi.
- Başarısız v4 koşusu kısmi public finding yazmaz ve terminal hata durumuna geçer.

## Domain ve projeksiyon

Kanonik kaynak `private.analysis_items_v4` tablosudur. Beş sınıf saklanır:

- `observed_finding`: public listede skorlu.
- `assurance_requirement`: aynı kartta, skorsuz, saha teyitli.
- `verification_request`: aynı kartta, skorsuz, saha teyitli.
- `positive_control`: private.
- `not_assessable`: private.

Public `findings` yalnız uyumluluk projeksiyonudur. Skorsuz kayıtların P/F/S,
üretilmiş skor ve risk bandı yoktur. Analiz rollup'ı yalnız observed kayıtları
toplar; `finding_count` üç görünür sınıfı sayar.

## Motor

- Fotoğraf başına bir kompakt Gemini primary çağrısı.
- Core-7 ve görünür varlık/sektörle etkinleşen dinamik modüller.
- E0–E5 evidence normalizer ve dört kollu absence router.
- Kritik kader invariant'ı ve ayrı routing/hard-rejection ledger'ları.
- Premium en fazla 2, Economy en fazla 1 hedefli bölge.
- Belge/ölçüm/iç bütünlük hedefli provider çağrısı açmaz.
- Kontrol metni deterministik katalogdan gelir.
- P/S mevcut semantik tavanlarla, F mevcut sektör prior sırasıyla sunucuda
  hesaplanır. Sektör priorı kullanılan observed kayıt saha teyidi taşır.
- Standart serbest metni kapalıdır; doğrulanmış aktif registry kaydı yoksa
  referans boş kalır.

## Assurance ve standartlar

- 14 deterministik assurance topic'i 15 kanonik sektörü kapsar.
- Registry; jurisdiction, edition, source rights, applicability, supersession
  ve active/draft/withdrawn durumlarını saklar.
- Doğrulanmamış standart metadata'sı active yapılmadı; bu nedenle uydurma veya
  geri çekilmiş bir kaynak kullanıcı metnine giremez.

## Doğrulama

- Tüm Edge Function Deno paketi: 735/735.
- V4 odaklı semantik/telemetri testleri: 22/22.
- pgTAP V4 şema/izin/rota paketi: 33 kontrol.
- iOS simulator Debug build: başarılı.
- Android `:app:compileDebugKotlin`: başarılı.
- Canlı `analyze-v4` Edge Function: sürüm 4, `ACTIVE`.
- Yetkisiz `analyze-v4` çağrısı: HTTP 401.
- Atomik finalizer, skorlu + skorsuz projeksiyonla canlı DB transaction içinde
  çalıştırılıp rollback ile doğrulandı.
- 85 photo-run / 230 aday shadow replay: 0 provider çağrısı, 0 kritik sessiz
  düşme.

## Pilot ve yayın kapısı

Pilot yalnız doğrulanmış sahip hesabına açıktır. Yeni build
`safety_claim_v4_scoreless=true` gönderir; eski build aynı hesapta v3'te kalır.
Her gerçek pilot koşusu için `admin_analysis_v4_pilot_report_v1` token, thinking,
maliyet, süre, aday kaderi, sınıf sayıları ve aynı fotoğraf sayısındaki son iki
v3 baseline'ı döndürür.

Genel canary veya yayın otomatik açılmaz. Kullanıcı pilot değerlendirmesi ve
açık onay olmadan `general_release_approved=false` kalır.

## İlk gerçek pilot düzeltmesi

İlk tek fotoğraflı inşaat pilotunda Gemini'nin coverage dizisi zorunlu
modüllerin tamamını kapatmadığı için iki çağrı da
`provider_critical_coverage_incomplete` ile reddedildi. `v4-vision-core-v2` ve
`critical-coverage-v2` ile teknik retry artık eksik modül reason-code'larını
alır. İkinci yanıt yalnız coverage bakımından eksik kalırsa, mevcut adaylar
değiştirilmeden eksik satırlar sunucuda `not_assessable_due_to_image` olarak
tamamlanır; yeni tehlike uydurulmaz. Provider attempt v5 telemetrisi başarısız
çağrılarda da token, thinking, maliyet, prompt SHA ve çıktı bütçesini zorunlu
olarak kaydeder.
