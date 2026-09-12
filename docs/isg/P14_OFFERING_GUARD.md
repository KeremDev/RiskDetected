# P14 ilk regresyon düzeltmesi — pinned offering

12 Eylül 2026. Katalog incelemesi sırasında Android ve iOS arasında bulunan fark giderildi. Bu P14 lifecycle/indirim uygulamasının tamamlandığı anlamına gelmez.

Önce Android, dolu bir configured offering kimliği bulunamadığında `offerings.current`'a düşüyordu. Bu, örneğin QA offering eksikken üretim paketlerinin veya üretim offering eksikken farklı hedeflenmiş paketlerin gösterilmesine yol açabilirdi. iOS zaten dolu configured kimlik için fallback yapmıyordu.

Yeni `selectBillingOffering` saf helper'ı `BillingRepository.fetchPackages` içine bağlandı:

| Yapılandırma | Bulunan offering | Sonuç |
|---|---|---|
| Boş / yalnız whitespace | current mevcut | current |
| Boş | current yok | Paket yok |
| Dolu | Tam kimlik mevcut | Yalnız belirtilen offering |
| Dolu | Kimlik yok | Paket yok; current'a fallback yok |

Çevreleyen whitespace temizlenir; kimliğin büyük/küçük harfi veya içeriği değiştirilmez. Kaynak katalogdaki `default` ve dört paket değiştirilmedi; normal purchase/restore/same-product guard veya paid hak hesaplama koduna dokunulmadı. iOS kaynak kodu değişmedi. Android ekranı paket yokken mevcut `rd_paywall_design_package_missing` açıklamasını kullanıyor; satın alma seçili paket bulunmasını gerektiriyor. UI davranışı bu tur source incelemesidir, emulator checkout testi değildir.

10 JUnit: default > targeted-current, production→QA fallback reddi, QA→production fallback reddi, empty, blank, trim, case-sensitive missing, ikisi de yok, current yokken pinned var, pinned/current ikisi de yok. Yeni testler dahil `core:data` 27 sınıfta **151/151**, 0 fail/error/skip. `:app:assembleDebug --offline` PASS. Foundation45, capacity-shadow17 ve teknik kimlik kontrolü tekrar PASS. Mevcut Android CI tüm Android dosyalarını izler ve `testDebugUnitTest` çalıştırır; uzak CI bu tur çalıştırılmadı.

[Kaynak/hash/test kanıtı](evidence/P14_ANDROID_OFFERING_GUARD_2026-09-12.json). Bu binding, P01'in yalnız üç transport dosyasını tarayan dar function-map'ine dahil değildir; P14 için burada ayrı kaydedildi. Tam uygulama fonksiyon/acceptance envanteri ve store E2E kapıları hâlâ açık.

Yerel düzeltme henüz yayınlanmadı. Geri dönüş gerekiyorsa bu ayrı düzeltme commit'i incelenerek geri alınabilir; global reset veya eski abone haklarının geri alınması gerekmez. Yeni mağaza teklifi/A-B deneyi oluşturulmadı.
