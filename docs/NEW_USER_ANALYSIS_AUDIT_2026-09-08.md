# Yeni kullanıcı / ilk analiz incelemesi — 8 Eylül 2026

İnceleme: üretim Supabase SQL + kimliği eşleştirilmiş API istekleri, App Store
Connect tanı kayıtları, Google Play Console ve Firebase Crashlytics, kaynak kodu.
Son kontrol yaklaşık 15:55 Türkiye saati. Salt okunur inceleme; uygulama/sunucu
değişikliği, yeni kullanıcı oluşturma, ücretli AI isteği veya build yapılmadı.

## Sonuç

Son 5 hesabın 1'i analiz tamamlamış. Diğer 4 hesap için analiz oluşturma POST'u,
fotoğraf yükleme isteği ve analyze çağrısı incelenen kayıt günlerinde yok.
Bu, analiz motorunun bu dört isteği reddettiği anlamına gelmiyor: isteğin
sunucuya ulaştığına dair kanıt yok. Cihaz içi fotoğraf hazırlama/izin/UI hatası
veya kullanıcının kendiliğinden ayrılması mevcut ölçümle birbirinden ayrılamıyor.

## Beş hesap, yenilik sırasıyla (kişisel bilgi olmadan)

| Kayıt (TR) | Sürüm | Gözlenen akış | Analiz |
| --- | --- | --- | --- |
| 8 Eyl 13:38 | iOS 2.0.2 / 90, Free | Ana ekran/profil verileri başarılı; 13:39:49 profil yükseltme kartı → paywall; 8 saniye sonra kapatma | Yok |
| 7 Eyl 15:07 | iOS 2.0.1 / 89, Plus | Onboarding → satın alma başarılı → fotoğraf yükleme → analyze 202 → sonuç/veri okumaları 200 | 1 başarılı, 26.2 sn |
| 7 Eyl 11:29 | Android 2.0.0 / 12, Free | Onboarding paywall'ı açma/seçim/kapatma; ardından ana ekran verileri 200 | Yok |
| 7 Eyl 10:22 | iOS 2.0.1 / 89, Free | Trial daveti → onboarding cevap kaydı → ana ekran verileri 200 | Yok |
| 5 Eyl 13:45 | Android 2.0.0 / 12, Free, EN | Ana ekran/profil/kota/abonelik/policy okumaları başarılı; onboarding cevap kaydı yok | Yok |

Dört Free hesapta usage_events yok; kota sorguları başarılı, kullanım sıfır.
Kota kaynaklı paywall giriş kaydı yok. Son iOS hesabının paywall kaynağı analiz
butonu değil, profile_upsell_card. Tüm hesapların güvenlik profili atanmış.
Onboarding cevabının bulunmaması tek başına onboarding ekranında takılma kanıtı değil.

## Sunucu ve sürümler

- iOS canlı 2.0.2 / 90; 2.0.3 / 91 WAITING_FOR_REVIEW. Meta entegrasyonu bu
  kullanıcıların kullandığı sürümlerde bulunmuyor.
- Android kullanıcıların kayıt anındaki sürümü 12; inceleme sırasında Play Console
  en yeni üretim sürümünü 2.0.1 / 13 gösteriyor. Crashlytics de build 13 için ilk
  etkinliği 8 Eylül 14:00 itibarıyla gösteriyor. Bu yüzden son beş kaybını build 13'e
  bağlamak doğru değil.
- Android client ve submit kapıları min_version=2, kill_switch=false: 12/13 açık.
- iOS v4/result-hub 89/90 açık. Minimum desteklenen iOS build 88.
- Kuyrukta mesaj ve son 7 günde pending/queued/analyzing kayıt yok; worker cron aktif.
- İnceleme başlangıcındaki 7 günlük analiz tablosu: 20 completed, 2 failed.
  Bunların tamamının gerçek kullanıcı/test ayrımı bu raporda doğrulanmış değildir.
  Son 5 kullanıcıyla eşleşen başarısız kayıt yok.
- Başarılı Free analizler iOS 88 ve Android 11 üzerinde mevcut. iOS 90 / Android
  12 Free yeni-kullanıcı yolunun uçtan uca başarılı olduğunu bu örnekler tek başına
  kanıtlamaz. Bu incelemede yeni fiziksel cihaz analizi oluşturulmadı.

## Bulunan ayrı teknik sorunlar / riskler

1. Android ödeme ekranında gerçek çökme kaydı: Firebase Crashlytics son 7 günde
   1 olay / 1 cihaz, build 12, OnePlus8Pro / Android 11, 5 Eylül 13:50:45.
   `ProxyBillingActivity.onCreate`, Billing 8.3.0: null PendingIntent üzerinden
   getIntentSender çağrısı. Sorun kimliği dae7cb84b3499727c650a64570d882a8.
   Son beş kullanıcıyla kesin eşleştirme yok; son Android/TR hesabı Samsung SM-A525F.
   Kodda RevenueCat çağrısı try/catch içinde olsa da ayrı Activity yaşam döngüsü
   çökmesinin bununla yakalandığı varsayılamaz. Kök tetikleyici henüz yeniden üretilmedi.
2. 4 Eylül Free analizinde provider_unavailable / Gemini 503 ve tek başarısız
   provider attempt var. Mevcut V5 politika kodu yalnız doğrulanmış ücretli Plus/Pro
   yoluna aynı modelde ikinci denemeyi veriyor; Free için otomatik retry yok.
   Bu bir dayanıklılık açığı / bilinçli maliyet politikası ayrımı gerektiriyor;
   değişiklik yapılmadı, yeni kullanıcı kaybının nedeni olarak sunulmuyor.
3. 4 Eylül Pro çoklu fotoğraf analizinde üç provider çağrısı 200/persisted olmasına
   rağmen v5_finalize_failed var. Çıktı kaydetme/finalizasyon katmanı ayrıca
   incelenmeli; model arızası olarak sınıflandırılmamalı.
4. İngilizce uzaktan legal manifest için global loglarda 400 ve consents tekrar
   insertlerinde 409 var. Bunlar son dört kişinin analiz isteğini engelleyen hata
   olarak doğrulanmadı. iOS bundled belge fallback'i var; Android legal policy
   devre dışı ve EN belgeler bundled. Bir EN yeni hesapta welcome-email 422 ardından
   200 var; ana ekran istekleri devam etmiş.

## Ölçüm açığı ve ürün akışı

Fotoğraf butonu, picker açılışı/iptali, izin reddi, JPEG hazırlama hatası,
odak seçimi, analyze CTA ve sunucu öncesi hata adımları kalıcı ve ortak bir
analitik akışta yok. Paywall ve sunucu kayıtları var; aradaki adımlar yok.
Android `RdCrashReporter.recordSafe` tanımlı ama çağıran uygulama kodu bulunmadı;
yakalanıp ekranda gösterilen non-fatal analiz hataları böylece Crashlytics'e
gitmeyebilir. iOS 89/90 ASC diagnostic signatures boş; bu sıfır çökme garantisi değil.
Google Play Vitals son 28 gün için metrikleri 'Veri kullanılamıyor' gösteriyor.

Kaynakta Free başlangıç yolu açık: kota dolu değilse fotoğraf seçimi/odak ekranı.
iOS trial davetinde ücretsiz devam butonu var ancak ikincil, küçük ve soluk.
Analiz öncesinde fotoğraf → işaretleme → sektör/odak → onay gibi çoklu adımlar var.
Bunlar terk sebebi için hipotezdir; kullanıcı davranışı kanıtı değildir.

Ham 31 Ağu–6 Eyl kayıt kohortunda iOS 19/28, Android 3/13 hesap analiz yapmış.
Bu ölçüm test hesapları/edinim kaynağı/yaş eşitlenmeden çıkarıldı; resmi dönüşüm
KPI'ı değil. Yine de Android ilk kullanım yolunun ayrıca ölçülmesine işaret ediyor.

## Doğrulama ve önerilen sonraki iş

22 yerel test geçti: 8 release/runtime gate, 14 V5 retry/routing/checkpoint.
Testler üretimde yeni analiz oluşturmadı; mağaza buildlerinin fiziksel cihaz
UI/E2E doğrulamasının yerine geçmez.

Öncelik: (1) ödeme çökmesini yeniden üretip düzeltme, (2) iki platforma kişisel
verisiz ilk analiz adım/hata ölçümü, (3) temiz Free hesapla mevcut mağaza sürümü
gerçek cihaz testi, (4) ölçülen kopuşa göre ilk analiz akışını sadeleştirme,
(5) provider 503 ve finalizasyon hatalarının ayrı dayanıklılık incelemesi.
Yeni veri yokken dört kullanıcının 'vazgeçme sebebi' kesinleştirilmemeli.

Log sorgulaması resmi Supabase ClickHouse alanlarıyla yapıldı:
https://supabase.com/docs/guides/observability/advanced-log-filtering
# Follow-up clarification

The payment-related Crashlytics record must not be treated as proof of a real customer's failed checkout. Subsequent vendor-documentation review found an exact error/device match for suspected automated-test launches of ProxyBillingActivity. Safeguards, measurement changes and verification limits are recorded in `PAYMENT_AND_FLOW_DIAGNOSTICS_2026-09-08.md`.
