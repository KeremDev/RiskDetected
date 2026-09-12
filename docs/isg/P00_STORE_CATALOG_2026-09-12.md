# P00 — mağaza / RevenueCat salt okunur katalog

Gözlem tarihi: 12 Eylül 2026, Europe/Istanbul. Bu envanter migration, mağaza güncellemesi, fiyat onayı veya satın alma testi değildir. Mevcut yönetim oturumları kullanıldı; anahtar oluşturulmadı, yetki genişletilmedi, hiçbir ayar kaydedilmedi. Kullanıcı ve transaction satırları bu belgeye aktarılmadı.

## Değişmeyecek kimlikler

| Katman | Mevcut kayıt |
|---|---|
| App Store | App `6769498181`, bundle `com.riskdetected.app`, SKU `riskdetected-ios` |
| Google Play | App `4974055657729042996`, package `com.riskdetectedan.app` |
| RevenueCat | Project `398f9795`, mevcut adı `Riskdetected` |
| Üretim offering | `default` / `ofrngebb4d41883` |
| Paid entitlement | `plus` / `entlc35d7e474e`; `pro` / `entl207210a27e` |

Play uygulaması üretimde, son güncelleme 8 Eylül 2026; dashboard %100 rollout ve yayınlanmamış değişiklik yok gösterdi. Bu gözlem binary imza/yerinde update testi yerine geçmez.

## Default offering: iki mağazaya bire bir eşleme

| Paket kimliği | App Store ürün kimliği | Google subscription:base-plan | Entitlement |
|---|---|---|---|
| `plus_monthly` | `riskdetected_plus_monthly` | `riskdetected_plus_monthly:monthly` | `plus` |
| `plus_yearly` | `riskdetected_plus_yearly` | `riskdetected_plus_yearly:yearly` | `plus` |
| `pro_monthly` | `riskdetected_pro_monthly` | `riskdetected_pro_monthly:monthly` | `pro` |
| `pro_yearly` | `riskdetected_pro_yearly` | `riskdetected_pro_yearly:yearly` | `pro` |

Kaynak: [default offering](https://app.revenuecat.com/projects/398f9795/product-catalog/offerings/ofrngebb4d41883), [Plus](https://app.revenuecat.com/projects/398f9795/product-catalog/entitlements/entlc35d7e474e), [Pro](https://app.revenuecat.com/projects/398f9795/product-catalog/entitlements/entl207210a27e). Bunlar erişim gerektiren yönetim bağlantılarıdır.

Her paid entitlement toplam sekiz ürüne bağlı: iki App Store, iki Play Store, iki Test Store, iki QA StoreKit. Üretim default offering yalnız gerçek iki mağazanın dört paketini içeriyor. Ayrı aktif `qa_test_store` ve `qa_storekit` offering'leri de dörder paket gösteriyor; bu tur onların paket detayları tek tek açılmadı.

Eski `Riskdetected Pro` entitlement'ı (`entl0284dff9bd`) yalnız Test Store `monthly` ve `yearly` ürünlerine bağlı. Bu legacy kayıt silinmedi veya yeni paid yetki kaynağı yapılmadı. [Legacy detay](https://app.revenuecat.com/projects/398f9795/product-catalog/entitlements/entl0284dff9bd).

RevenueCat Targeting ekranı **No rules yet**, Experiments ekranı **No experiments yet** gösteriyor. Default offering detayında **Add Paywall** var; mevcut native paywall tasarımının RevenueCat-hosted paywall olarak kayıtlı olduğu sonucu çıkarılamaz. Bu, backend veya uygulama içi başka A/B mekanizmalarının yokluğunu ispatlamaz.

## Google Play mevcut teklif

[Abonelik listesi](https://play.google.com/console/u/0/developers/8386568735420808034/app/4974055657729042996/subscriptions) dört abonelik ve her biri için bir etkin base plan gösterdi. Yalnız Plus yıllıkta bir teklif var; diğer üçünde teklif listelenmiyor. Son güncelleme her dördünde 14 Ağustos 2026.

`riskdetected_plus_yearly / yearly / trial-7d-v1`: etkin, Türkiye, eski sürümlerle uyumlu; **7 gün ücretsiz deneme**; yeni müşteri edinme, seçili kural **uygulamada daha önce hiçbir abonelik edinmemiş**. Yalnız bu ürünü daha önce almamış olma seçeneği seçili değil. Etiket alanı boş. [Teklif detayı](https://play.google.com/console/u/0/developers/8386568735420808034/app/4974055657729042996/subscriptions/s/riskdetected_plus_yearly/base-plans/b/yearly/offers/o/trial-7d-v1).

Plus yıllık base plan: yıllık otomatik yenileme, Türkiye **2.499,99 TRY**, ek süre **14 gün**, otomatik hesaplanan hesap askısı **46 gün**, plan/teklif değişikliği **bir sonraki fatura tarihinde ücretlendir**, Play Store'dan yeniden aboneliğe izin ver. Fiyat hücresi %20 vergi gösteriyor. Bunlar bu planın gözlenen ayarlarıdır; diğer planlara veya mağazaya varsayım olarak uygulanmaz. [Base plan](https://play.google.com/console/u/0/developers/8386568735420808034/app/4974055657729042996/subscriptions/s/riskdetected_plus_yearly/base-plans/b/yearly).

Diğer üç planın detayları da ayrı ayrı açılarak doğrulandı:

| Google ürünü | Base plan | Türkiye liste fiyatı TRY | Ek süre | Otomatik hesap askısı |
|---|---|---:|---:|---:|
| `riskdetected_plus_monthly` | `monthly` | 249,99 | 7 gün | 53 gün |
| `riskdetected_plus_yearly` | `yearly` | 2.499,99 | 14 gün | 46 gün |
| `riskdetected_pro_monthly` | `monthly` | 499,99 | 7 gün | 53 gün |
| `riskdetected_pro_yearly` | `yearly` | 4.999,99 | 14 gün | 46 gün |

Her dört plan etkin, otomatik yenilemeli, Türkiye ile sınırlı ve eski sürümlerle uyumlu görünüyor. Dördünde de plan/teklif değişimi sonraki fatura tarihinde ücretlendirilir; yeniden aboneliğe izin verilir; etiket alanı boş ve vergi hücresi %20. [Plus aylık](https://play.google.com/console/u/0/developers/8386568735420808034/app/4974055657729042996/subscriptions/s/riskdetected_plus_monthly/base-plans/b/monthly), [Pro aylık](https://play.google.com/console/u/0/developers/8386568735420808034/app/4974055657729042996/subscriptions/s/riskdetected_pro_monthly/base-plans/b/monthly), [Pro yıllık](https://play.google.com/console/u/0/developers/8386568735420808034/app/4974055657729042996/subscriptions/s/riskdetected_pro_yearly/base-plans/b/yearly). Mevcut abonenin korunan eski fiyatı bu tablodan çıkarılamaz. Grace ile account hold aynı erişim durumu değildir; sayısal toplam paid hak süresi olarak kullanılmaz.

## Kod ile eşleme ve açık riskler

`App/Services/RDConfig.swift` default offering `default`, entitlement `plus`/`pro` olarak sabit. `SubscriptionManager.swift:231` dolu configured offering bulunamazsa boş paket listesi üretir. Android `BillingRepository.kt:173` ise dolu configured offering bulunamazsa `offerings.current`'a düşer. Bu mevcut platform farkı, yeni hedefleme/QA offering'leri açılmadan önce P14 regresyonuna alınmalı; bu envanter turunda runtime davranışı değiştirilmedi.

`supabase/functions/_shared/subscription-tier.ts` ürün kimliğiyle tier çıkarımını entitlement listesinden önce kullanır. Google `:monthly`/`:yearly` biçimleri token fallback yoluna girer. Ürün eşlemesi billing'in gerçekten aktif olduğuna ilişkin kanıt değildir; mevcut server lifecycle/receipt doğrulaması ve sahiplik kontrolleri ayrıca gereklidir.

Mevcut Keychain anahtarı ile RevenueCat v2 `GET /projects` 403 `authorization_error` döndü. Tekrar denenmedi, anahtar değiştirilmedi. Açık dashboard hesabıyla normal read-only envanter elde edildi. V2 proje kataloğu okuması ayrı API izinleri gerektirir; 403 tek başına hangi iznin eksik olduğunu kanıtlamaz. [RevenueCat v2](https://www.revenuecat.com/docs/api-v2), [project read API](https://www.revenuecat.com/docs/api-v2/project).

## Kapanmayan kapılar

- App Store intro/promotional/win-back tekliflerinin tam envanteri ve legacy fiyat kohortları.
- Play gerçek eski fiyat kohortları ve mağaza checkout'unda hesaba özgü teklif uygunluğu.
- Aynı monthly üründe yeni kampanya indirimi ve sonraki normal renewal'ın gerçek sandbox/lisans tester kanıtı; yeni teklif konfigürasyonu için ayrı onay.
- RC tüm uygulama ayarları, webhook teslim politikası, QA offering detayları, restore transfer politikası ve SDK checkout kanıtı.
- İki mağazada signed binary/yerinde güncelleme, prod/sandbox ayrımı ve tam restore E2E.

`subscription-lifecycle` becerisi trial, aktif ama iptal edilmiş abonelik, ödeme sorunu, expiry ve geri kazanımı ayrı kontrol noktaları olarak ele almamıza yardımcı oldu. Becerideki genel süre/benchmark/indirim önerileri ticari karar veya gerçek mağaza ayarı sayılmadı; mevcut kayıtlar ve V5 kapıları önceliklidir. Atıf yapılan ek `revenuecat.md` kurulu beceride yok; bunun yerine resmi API dokümanı kullanıldı.
