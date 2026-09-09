# Yayın öncesi denetim — 6 Eylül 2026

## Düzeltme güncellemesi

Aşağıdaki ilk denetim tarihsel bulguları korur. Kullanıcının düzeltme talebi sonrasında:

- Yıllık fiyat sunumu kullanıcının açık isteğiyle aynen korundu.
- Android kalıcı paywall kuyruğu aktif kullanıcıya göre seçiliyor; diğer hesabın kayıtları silinmiyor veya yeniden sahiplenilmiyor. Oturum değişimi gönderimi tetikliyor; retry ve boş-kuyruk kontrolleri de aynı kullanıcı kapsamını kullanıyor. Hesap değişimi, logout, bilinmeyen hesap, sıra ve tekrar gönderim için üç regresyon testi eklendi.
- `20260905225918_failed_analysis_usage_totals.sql` üretime uygulandı. Hata kapanışı çağrı/token/maliyet toplamlarını mevcut attempt kayıtlarından hesaplıyor; eski başarısız özetler de düzeltildi. Son doğrulamada çağrı toplamı uyuşmayan başarısız run sayısı **0**. İşlem model çağırmadı ve kota/abonelik değiştirmedi.
- SQL önce BEGIN/ROLLBACK içinde sınandı. Tekrar çalıştırmada hata/tamamlanma zamanı korunuyor, yanlış kullanıcı kabul edilmiyor, anon/authenticated erişimi kapalı. Güvenlik advisor karşılaştırmasında yeni bulgu yok.
- Üç iOS UI başarısızlığı test akışlarından kaynaklandı: eski başlık, sabit ana sayfa koordinatı ve sticky header arkasına düşen tıklama. Güncel fixture/kimlikler ve küçük kaydırma adımlarıyla üçü ayrı regresyon koşularında geçti. Hediye tüketiminden sonra standart PDF oluşturma kontrolü de eklendi ve geçti.
- Backend **977/977**, Android **138/138** test geçti. iPhone 13'te aynı 10 senaryonun son toplu koşusu **10/10 geçti**, başarısız/atlanmış test yok (`/tmp/rd-fixes-ios13-final.xcresult`). Swift paywall sahiplik/olay politika testi de tekrar geçti.
- Model/Free API/retry dosyalarının önceki yerel değişiklikleri korundu; bu düzeltmeyle yeni model flag'leri açılmadı veya analiz worker deploy edilmedi. Gerçek Free credential billing/veri uygunluğu ve hosted canary hâlâ yayın ön koşulu. Kod testinin geçmesi bunu karşılamaz.
- Commit/push yapılmadı. Android düzeltmesinin kullanıcılara ulaşması için yeni uygulama sürümü gerekir.

Çıktılar: `/tmp/rd-fixes-backend.log`, `/tmp/rd-fixes-android-all.log`, `/tmp/rd-fixes-ios13-1.xcresult`, `/tmp/rd-fixes-ios13-3.xcresult`.

## Karar

Henüz koşulsuz yayın onayı yok. Android paywall olay kuyruğu ve başarısız analizlerin AI özet sayaçları için doğrulanmış sorunlar var. iOS sonuç/rapor akışında üç UI testi başarısız; bunlar çözülmeden ilgili akışlar doğrulanmış sayılmaz. Yeni Free API yönlendirmesi ve kalıcı retry henüz canlıda etkin değil.

Bu çalışma salt-okunur üretim denetimi ve yerel testlerden oluşur. Üretim verisi/ayarları değiştirilmedi; gerçek analiz, satın alma veya müşteri kotası tüketimi başlatılmadı. Uygulama kodu değiştirilmedi. Önceden mevcut çalışma ağacı değişiklikleri korundu. Commit/push yapılmadı.

## Doğrulanmış bulgular

### P1 — Android: başka hesabın bekleyen olayı kuyruğu durdurabilir

- Kaynak: `android/core/data/src/main/kotlin/com/riskdetectedan/core/data/paywall/PaywallEventRepository.kt:185`.
- `flushPending()` her zaman kuyruğun ilk kaydını seçiyor. Aktif kullanıcıya ait kayıtları ayırmıyor. İlk gönderim hatasında döngü bitiyor ve aynı kayıt tekrar deneniyor.
- Üretimde doğrulanan `paywall_events_insert_own` RLS koşulu: `auth.uid() = user_id`.
- Senaryo: A hesabında çevrimdışı olay birikir → B hesabına geçilir → A'nın kaydı B oturumuyla reddedilir → B'nin arkasındaki kayıtları da gönderilemez. Bu, kod ve canlı RLS üzerinden doğrulanmış bir hata yoludur; Android cihazında hesap değişimli uçtan uca test yapılmadı.
- Düzeltme: kayıt sahipliğini koruyarak sadece aktif hesabın kuyruğunu gönder; başka hesabın kaydını yeni hesaba atama veya silme. Retry/boş-kuyruk kontrolünü de aynı hesap filtresine göre yap.
- Kabul testi: A/B karma kuyruk, çıkış/giriş, çevrimdışı yeniden başlatma, RLS reddi, mükerrer `client_event_id` ve ağ geri dönüşü.
- iOS'un sahiplik/karma kuyruk politika testi geçiyor; Android'in mevcut testleri bu vakayı yakalamıyor.

### P1 — Başarısız analizde AI özet sayaçları eksik

- Kaynak: `supabase/migrations/20260823185104_analysis_engine_vnext_v3.sql:684`; çağıran: `supabase/functions/analyze-v4/index.ts:1832`.
- Üretimdeki `fail_analysis_engine_run_v3` tanımı da okundu: yalnız status/error/tarih alanlarını güncelliyor; çağrı, token ve maliyet toplamlarını hesaplamıyor.
- Son 7 günlük iki başarısız engine run: `v5_finalize_failed` için ayrıntı tablosunda 3 çağrı, özette 0; `Gemini HTTP 503` için ayrıntıda 1, özette 0.
- Bu kayıtlar 4 Eylül tarihli. Çağrı ayrıntıları tamamen kaybolmuş değil; özet ile ayrıntı uyuşmuyor. Bu bulgu tek başına eski tüm kullanıcı ekranlarındaki sıfırların aynı nedenden kaynaklandığını kanıtlamaz.
- Düzeltme: terminal başarısızlık yolunda ilgili provider attempt toplamlarını da idempotent olarak hesapla. Token verisi bulunmayan istek ile sıfır maliyeti birbirine karıştırma. Geçmiş kayıtları sadece mevcut ayrıntılardan geri doldur.
- Kabul testi: HTTP hata, parse hata, DB finalize hata, çok fotoğrafta kısmi başarı ve retry sonunda başarısızlık için ayrıntı/özet eşitliği.

### P1 / mağaza inceleme riski — Yıllık ücretin görsel önceliği

- Kaynak: `App/Views/Paywall/Design/PaywallDesignFlowView.swift:260`; fiyat bileşeni: `PaywallDesignKit.swift:1154`.
- Yıllık seçimde aylık karşılık ana fiyat, yıllık toplam daha küçük/soluk. iPhone 13 test ekran görüntüsünde de doğrulandı.
- Bu, daha önce talep edilen tasarım tercihi; bu denetimde değiştirilmedi.
- Apple, fiilen tahsil edilecek toplamın satın alma akışındaki en belirgin fiyat olmasını; yıllığın aylık karşılığının ikincil kalmasını istiyor. CTA altındaki yıllık açıklama bu hiyerarşi riskini tek başına ortadan kaldırmıyor. Kesin ret öngörüsü değildir.
- Kaynak: https://developer.apple.com/app-store/subscriptions/

## Geçen testler

| Grup | Sonuç | Sınır |
| --- | --- | --- |
| Deno backend suite | 977 geçti, 0 başarısız | Yerel testler; ağ izni verilmedi |
| Android 5 modül unit testleri | 135 geçti, 0 başarısız/atlanmış | 29 XML suite; `--offline --rerun-tasks`, 168 görev yeniden çalıştı |
| Swift paywall takip politikası | Geçti | Sahiplik, hesap değişimi, anonim bağlama, eski kayıt izolasyonu, karma kuyruk, pending/cancel/fail, variant |
| iPhone 13 UI | 7 geçti, 3 başarısız | iOS 26.5, izole UI test verileri; gerçek StoreKit işlemi değil |

Android modülleri: core/data, feature/paywall, feature/analysis, feature/onboarding, feature/profile. JDK 17 açıkça seçilerek çalıştırıldı.

iPhone 13'te geçenler:

- PLUS/PRO, aylık/yıllık fiyat ve plan geçişleri, karşılaştırma ekranı.
- Denemeye uygun olmayan kullanıcıda trial vaadi gösterilmemesi.
- Mağaza fiyatı yokken satın alma yerine yeniden deneme.
- En büyük erişilebilirlik yazısında plan/CTA/hukuki bağlantılara erişim.
- Free eğitim detaylarının kilitlenmesi ve PLUS yönlendirmesi.
- Onboarding kişisel plan → auth.
- Trial daveti / timeline paywall sunumu.

## Başarısız UI testleri — yayın kapısı açık

1. `testAnalyzingProgressCompletesIntoResult`: `Analiz Sonucu` öğesi bulunamadı.
2. `testFreeRiskAnalysisTrialDoesNotLockStandardReport`: aynı başlık bulunamadığı için kota/PDF adımlarına ulaşamadı. Test ana sayfada sabit koordinatla tıklıyor; mevcut ekran düzeniyle güvenilirliği ayrıca incelenmeli.
3. `testFreeRiskDetailLocksRealRegulatoryContentWithPremiumOverlay`: ilk sonuç öğesi kaydırma sonrasında dokunulabilir bulunmadı; mevzuat kilidi kontrolüne ulaşamadı.

Bu üç sonuçtan analiz motorunun veya kotanın bozuk olduğu çıkarılamaz. Test beklentisi/fixture/navigasyon sorunu ile gerçek UI erişim problemi ayrılmalı; sabit kimlikli güncel testlerle yeniden geçmeden onay verilmemeli. Testleri sırf yeşile çevirmek için beklentiler kaldırılmadı.

Derleme ayrıca PaywallDesignKit.swift 631–641 arasında 11 actor-isolation uyarısı üretti. Derleme hatası olmadı; Swift concurrency temizliği için takip edilmeli.

## Canlı veri kontrolü — son 7 gün

- Analizler: 82 tamamlandı, 5 başarısız. Bu sorguda 20 dakikadan eski kuyrukta/işleniyor durumda analiz yok.
- İki engine failure: Gemini 503 ve finalize hatası. İkisinin özet sayaç tutarsızlığı yukarıda.
- Abonelik olayları: 6 ilk satın alma, 2 yenileme, 3 iptal; 11'inin tamamında `processed_at` var. Bu, cihaz teslimatı veya yeni release'in bütün abonelik geçişlerinin test edildiği anlamına gelmez.
- `usage_events`: aynı kullanıcı/feature/source için mükerrer tamamlanmış kayıt grubu yok. Kaynaksız kayıtlar ve diğer event tipleri bu kontrolün kapsamında değil.
- Canlı rapor-kota wrapper'ı `risk_analysis` kapsamındaki `standard`/`standardReport` türünü risk tablosuna çevirmiyor; standart rapor ayrımı mevcut. Gerçek PDF uçtan uca testi yukarıdaki UI engeli nedeniyle bu turda doğrulanamadı.

## Paywall kaynak takibi

- iOS giriş noktası kataloğu, kalıcı olay kimliği, kullanıcı sahipliği ve anonim yolculuk bağlama politikası incelendi; politika testi geçti.
- Android güncel navigation kodu analiz kimliği, bölüm, giriş noktası, öğe kimliği, placement ve promotion variant alanlarını paywall'a taşıyor. Event helper bu bağlamı aksiyonlara ekliyor.
- Ancak Android kalıcı kuyrukta hesap izolasyonu eksiği var (P1).
- Son 7 günlük eski Android varyantında sonuç yüzeyine ait 12 olayın analiz kimliği eksik; ayrıca 19 olayın entry bilgisi eksik. Örnek kaynaklar `result_header_upgrade` ve `result_locked_report_options`. Son eksik kayıtlar 3 Eylül tarihli: bunları yerel yeni kodun halen ürettiği varsayılmadı.
- Onboarding'in ayrı personal-plan/trial-invite olaylarında entry alanının boş olması tek başına kayıp olay kanıtı değil; bunlar kendi olay/funnel sözleşmeleriyle değerlendirilmeli.
- Üretimde `claude_dark_paywall_v2` olayı henüz görülmedi. Yeni iOS sürümünün cihaz → kuyruk → DB → admin raporu zinciri canlıda bu nedenle doğrulanmış değil.
- UI fiyat fixture'ı satın alma aksiyonunu erken kesiyor. Görüntü testinin geçmesi gerçek satın alma veya sunucuya olay teslimatını kanıtlamaz.

## Modeller ve fallback — yerel/canlı ayrımı

- Free ilk analizin mevcut ücretli rotası korunuyor.
- Tekrarlayan Free için Gemini 3.5 Flash Lite / legacy free credential ve PLUS/PRO için aynı model/ayarlarla bir tekrar deneme yerel değişikliklerde var.
- Yeni flag'ler üretimde etkin değil; geçiş tamamlanmış sayılmaz.
- Yerel retry testleri geçiyor; gerçek hosted timeout/yeniden teslim/çok fotoğraf kısmi başarı testi yapılmadı.
- Free projenin model erişimi, gerçekten ücretsiz billing/quota durumu ve veri/bölge uygunluğu doğrulanmadan genel trafik açılmamalı. Paid canary anahtarının erişimi free hesabın çalıştığının kanıtı değil.
- Ayrıntı ve güvenli deployment sırası: `docs/ANALYSIS_V5_FREE_REPEAT_ROLLOUT.md`.

## Yayından önce kalan kabul kapıları

1. Android hesap değiştirme kuyruğu düzeltmesi ve regresyon testi.
2. Başarısız analizlerde AI sayaç/maliyet toplamlarının düzeltilmesi ve eşitlik testi.
3. Üç başarısız iOS UI testinin nedeninin ayrılması; sonuç detayları, ücretsiz rapor ve hediye tüketiminden sonra standart PDF üretiminin geçmesi.
4. Yıllık fiyat hiyerarşisi için mağaza uyum kararı.
5. Yeni app build ile her entry ID için ayrı tıklama → view → billing/plan → close/purchase zincirinin admin ekranında doğrulanması. Ağ kesilmesi, app yeniden başlatma, hesap A/B geçişi dahil.
6. RevenueCat sandbox'ta gerçek satın alma/restore/pending/cancel/expiration/renewal ve hesap sahipliği testleri. Bu turda gerçek satın alma yapılmadı.
7. Free/retry backend rollout ayrı kapı: credential/veri uygunluğu + staging hosted canary + doğru deploy sırası.
8. Fiziksel cihaz ve diğer iPhone/Android ekran matrisi. Bu tur yalnız iPhone 13 simülatöründe seçili UI senaryolarını çalıştırdı; tüm cihazlarda eksiksizlik iddiası yok.

## Test çıktıları

- `/tmp/rd-release-backend-audit.log`
- `/tmp/rd-release-android-audit-rerun.log`
- `/tmp/rd-release-audit-iphone13.xcresult`
- `/tmp/rd-release-audit-all-attachments/manifest.json` (paywall ekran görüntüleri ve başarısız test kayıtları)

Geçici dosyalar kalıcı arşiv değildir. Raporda müşteri kişisel verisi veya API anahtarı yoktur.
