# P18 — tüm NOVA sayfalarında gri tuval / beyaz kart

13 Eylül 2026, Europe/Istanbul. Kullanıcının son düzeltmesi: Firmalar yalnız bir örnektir; uygunsuzluk, ekleme, rapor, takip ve diğer sayfalar da aynı yüzey dilini kullanmalıdır.

## Kalıcı kural

- Açık tema: başlık, sayfa gövdesi, boş kalan alan ve alt bar çevresi kesintisiz `canvas = #F0F0F0`.
- Beyaz `surface` yalnız yuvarlatılmış içerik kartlarında, arama ve uygun kontrol yüzeylerinde kullanılır. Sayfa gövdesine tam ekran beyaz arka plan verilmez.
- İçerikler `NovaCard` ile gruplanır; var olan radius/shadow token'ları korunur. Yeni örnek alt sayfalarda 20 pt/dp dış boşluk, 16 bölüm arası boşluk ve 20 kart iç boşluğu kullanıldı.
- Başlık sola hizalıdır. Renkli ikon çizimi kullanılır, ikonun çevresine renkli kutu eklenmez. Mevcut avatar ve Ekle ana düğmesi ayrı kontrol yüzeyleridir.
- iOS'ta tek geri kontrolünün sahibi NOVA üst barıdır. Pushed destination kendi varsayılan navigation bar'ını açmaz.
- Koyu tema var olan koyu canvas/surface token'larını korur; açık tema rengi zorla koyu temaya uygulanmaz.

## Neden ve uygulama

Önce `NavigationStack` içindeki root görünüm navigation bar'ı gizliyordu; `.navigationDestination(..., destination: content)` ile açılan görünüm aynı kuralı taşımıyordu. Dış ZStack'in gri zemini içteki sistem beyazını kapatamıyordu. Kullanıcının ekranında ikinci geri düğmesi ve beyaz gövde bu alt hedefte görünüyordu.

`NovaPageSurface` SwiftUI'da hem dört tab köküne hem her pushed destination'a yerleştirildi: tam genişlik/yükseklik, opak tema tuvali, gizlenmiş scroll-content background, gizlenmiş sistem navigation/tab bar. Android shell'in bütün hedefleri de aynı isimli ortak Compose yüzeyinden geçiyor. Bu bir global UIKit/Material tema değişikliği değildir.

iOS `HarnessDestination` ve Android offline preview'nin kalan örnek hedefleri artık sola hizalı ikonlu başlık ve beyaz kart içeriyor. Android başlığı `NovaPageTitle` ile mevcut hedef ikon eşlemesini kullanıyor. Font dosyaları, ikon asset'leri ve token değerleri değiştirilmedi.

## Kapsanan hedefler

Ana Sayfa, Yeni Uygunsuzluk, Uygunsuzluklar, Firmalar, İşletme Hafızası, Evrak Takibi, Diğer Dosyalar, Ziyaretler, İstatistikler, Eğitim ve Takip, Rapor Oluştur, Rapor Arşivi, Bildirim Merkezi, Profil, Dosya Ekle, Ziyaret Ekle, Eğitim Ekle. Ortak wrapper bu 17 hedefin tümünde kullanılır; gerçek domain içerikleri geldiğinde içlerine yeniden opak beyaz tam ekran eklenmemelidir.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| iOS hostlu tam UI turu | 11/11 PASS, 0 fail/skip; açık/koyu menü, Ekle, arama, modal, hesap/izin değişimi, native back, 320 pt AX3 |
| iOS yeni yüzey regresyonu | 17 benzersiz hedef; y=200/350/500/650 pt kenar örneklerinde RGB 240 ±2; kartta RGB 255 ±2; sistem navigation bar yok |
| iOS önceki hedefli tekrar | 1/1 PASS; ardından yukarıdaki tam tur tekrar PASS |
| Android design system | 309/309 JVM PASS; iki yeni native-Skia testi ×17 hedef, açık/koyu tuval ve ayrı kart pikselleri |
| Android build/lint | design system lint, offline preview debug APK, ana debug APK PASS |
| iOS derleme | offline QA ve ana RiskDetected simulator Debug/no signing PASS |
| Tasarım kaynak testi | nova-design 20/20 PASS |
| Mağaza kimliği kaynak kontrolü | iOS bundle, Android application/namespace, callback, entitlement PASS; kimlikler değiştirilmedi |

Başarısız denemeler de kayıtlıdır: ilk derleme yanlış `NovaIcon(color:)` parametresi yüzünden durdu, doğru foregroundStyle ile düzeltildi. İlk test çağrısında hedef adı yanlış yazılmıştı, test çalışmadı. Sonraki iki testlik turda beş referans ekran testi geçti; tüm menü turu XCUI `memory` hittability hatası verdi (son ağaç `reports` gösteriyordu). Kod/test beklentisi gevşetilmeden aynı testin tekrarı ve tam 11 test turu geçti. Bu tekil otomasyon/gezinme anomalisi tekrar üretilemedi; kalıcı bir kök neden çözüldü iddiası yoktur.

Son tam XCTest sonucu:
`/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-09-12T22-59-51-162Z_pid70458_304a85f4.xcresult`

İlk kısmi başarısız tur: aynı dizinde `test_sim_2026-09-12T22-56-20-774Z_pid70458_439ab319.xcresult`; hedefli başarılı tekrar `test_sim_2026-09-12T22-58-13-769Z_pid70458_8c93a991.xcresult`.

Android XML: `android/core/designsystem/build/test-results/testDebugUnitTest/`. Kalıcı görseller [page-surfaces-20260913](page-surfaces-20260913/); ayrıntılı görsel kabul [design-qa.md](../../design-qa.md).

## Sınırlar ve devam noktası

Kullanıcının gösterdiği Sayaç / Sentetik test ekranı, ayrı `com.riskdetected.isgshellharness` QA uygulamasıdır. Bu tur gerçek ziyaret/uygunsuzluk formu veya canlı veri bağlantısı tamamlamaz. Ana legacy root'lar hâlâ bu NOVA shell'ine bağlanmış değildir. Yeni native sunumun tüm mevcut hedefleri aynı yüzey standardını aldı; eski üretim uygulamasının bütün ekranlarının yenilendiği söylenemez.

Android bu tur JVM native-Skia ve derleme ile doğrulandı; gerçek emülatör/cihaz turu tekrarlanmadı. iOS fiziksel cihaz, gerçek Auth/billing/kamera, erişilebilirlik okuyucusunun tam akışı ve uzak CI bu turun kanıtı değildir. Supabase, canlı müşteri verisi, mağaza kimlikleri, abonelikler ve checkpoint etiketi değiştirilmedi; push/deploy yok.

Sonraki geçiş diliminde gerçek domain ekranları ve scoped servis adaptörleri bu ortak gri sayfa + beyaz kart sözleşmesine bağlanmalıdır. P02/P18 bütünü kapanmış değildir.
