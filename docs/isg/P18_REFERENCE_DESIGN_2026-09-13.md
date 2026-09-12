# P18 — Kullanıcının beş ekranına göre NOVA düzeltmesi

## Görsel sözleşme

13 Eylül 2026. Önceki yaklaşık native shell tasarımı yerine kullanıcının gönderdiği beş ekran esas alındı. Orijinaller değiştirilmeden `design-reference-20260913/` altında saklandı. Her biri 1320×2868 px; karşılaştırma hedefi 440×956 pt, 3× iPhone ekranıdır. Saat, batarya, Dynamic Island ve home indicator işletim sistemine aittir; uygulama içinde taklit edilmez.

| Ekran | Orijinal | Saklanan kaynak |
|---|---|---|
| Ana sayfa | IMG_1432.PNG | `design-reference-20260913/home.png` |
| Sol menü | IMG_1433.PNG | `design-reference-20260913/drawer.png` |
| Ekle popup | IMG_1434.PNG | `design-reference-20260913/quick-add.png` |
| Bildirim paneli | IMG_1435.PNG | `design-reference-20260913/notifications.png` |
| Firma listesi | IMG_1436.PNG | `design-reference-20260913/companies.png` |

**Son kullanıcı kuralı ekran görüntüsüne üstün gelir:** ikonların arkasında renkli kutu/rozet zemini yoktur; sadece çizim renklidir. Yeşil Ekle eylem düğmesi, metinli buton yüzeyleri ve kişi/firma baş harfli avatarlar korunur. Koyu mod ve büyük yazı desteği korunur; görsel referans açık temadır.

## Kalıcı popup standardı

- `NovaPopupSurface` SwiftUI ve Compose tarafında tekrar kullanılabilir ortak yüzeydir. Yeni aksiyon popup'ları bu bileşeni kullanmalıdır; rastgele tam boy sheet yapılmaz.
- Aksiyon popup'ı: ekranın ortası, yatay 14 pt/dp boşluk, maksimum 440 genişlik, 30 köşe yarıçapı, 16 iç boşluk. İçeriğe göre yükseklik; yalnız sığmadığında kaydırma. Başlık yaklaşık 14–15/800, satır başlığı 15/600, açıklama 11.5/600. Satır 64 minimum yükseklik, 20 köşe, 8 aralık. 4 işlem: Uygunsuzluk, Dosya, Ziyaret, Eğitim. Alt Vazgeç satırı; sistem geri/dışarı dokunma kapatır.
- Aksiyonların ikonları 19–21, ayrılmış hizalama alanı 38; **alanın zemini yok**. Yeşil, mor ve amber çizgiler orijinal semantik renklere bağlıdır.
- Bildirim paneli ayrı bir konum varyantıdır: güvenli alanın altında 56, yatay 16 boşluk; kompakt başlık, okuma/silme, bildirim satırları ve merkez bağlantısı. Zil artık doğrudan merkez sayfasına gitmez.
- Sol menü popup değildir: 290 genişlik, ekran yüksekliği kadar düz yüzey, sol kenara bitişik; sağda karartma. Küçük/erişilebilir ekranlarda genişlik ekrana sığdırılır, liste kayar. Profil, rol, bağlantı metni, 13 sade satır ve çıkış eylemi vardır.
- Aynı anda tek `NovaOverlay`: `drawer`, `quickAdd` veya `notifications`. Ekle açmak mevcut sekmeyi değiştirmez. Panelden hedef seçmek paneli kapatıp mevcut gezinme kurallarını uygular.
- iOS en az 44×44, Android en az 48×48 üst kontrol hedefi korunur. Bu yüzden bazı kontroller kaynak görselden birkaç nokta daha geniş/yüksektir. Dokunma alanı görünmezdir; ikon zemini olarak çizilmez.
- Ekle açıldığında iOS arka içerik 7 pt bulanır; Reduce Transparency etkinse blur kullanılmaz. Panel karartması ayrıca çizilir. Dekoratif ikonlar erişilebilirlik ağacından gizlidir; eylemin etiketi ve 44 pt hedefi üst Button'a aittir. Böylece modal kapandıktan sonra erişilebilirlikte görsel alt düğüme takılma regresyonu kontrol edilir.

## Ana sayfa ve şirket listesi

Ana sayfa sırası: NOVA/Saha denetim asistanı üst başlık → karşılama/AI Asistan → 86 genişlikli yatay özet → Canlı Akış → Yeni kayıt etiketi ve kamera/galeri alanı → yeşil Uygunsuzluk Ekle → Eğitim ve Takip → Son Uygunsuzluklar → yüzen alt sekmeler. Tuval açık temada #F0F0F0, kartlar beyaz, gri yardımcı metin, Plus Jakarta Sans ailesi.

Firma ekranı başlık/geri, atanmış firma sayısı, arama, baş harfli firma satırı ve Panele dön bağlantısından oluşur. Arama Türkçe büyük/küçük harfe göre firma adı ve alt bilgide yapılır. Yükleme, hata/tekrar dene, boş liste ve eşleşmeyen arama durumları ayrı gösterilir; hata durumunda eski satırlar çizilmez.

## Orijinal ikon varlıkları

OSGBTakip `apps/mobile/src/components/nova/Icon.tsx` içindeki **48 orijinal çizim**, koordinatları ve stroke değerleri değiştirilmeden aktarıldı. OSGBTakip kaynaklarına yazılmadı.

- Sabit kaynak: `contracts/isg/v1/design/nova-icon-paths.json`.
- iOS: `App/Resources/NovaIcons.xcassets`, template SVG vektör varlıkları.
- Android: `android/core/designsystem/src/main/res/drawable/nova_*.xml`, native vektör kaynakları.
- `nova_icons.test.mjs` viewport/path/template ve harness kaynaklarını doğrular; `nova-design` paketine ve CI tetiklerine eklendi.
- Kamera arka planı, kaynak `PhotoBackdrop.tsx` motif yerleşiminden gelir. İki Feather çizimi kaynak `Feather.ttf` içinden CoreText ile mekanik olarak çıkarıldı (`ExtractFeatherPaths.swift`); yeniden çizilmedi. `nova-photo-paths.json`, 24 birim görünüm ve MIT lisansı saklandı. Toplam 48 NOVA + 2 dekoratif kaynak çizim vardır; bir ekran görüntüsü arka plana yapıştırılmadı.

## Veri ve entegrasyon sınırı

Bu değişiklik yeni native sunum katmanındadır. Eski `MainTabView`/Android uygulama kökü bu katmana geçirilmedi. Canlı domain, Auth, abonelik, bildirim silme, çıkış ve kamera işlemleri burada uygulanmaz; güvenilir host tarafından enjekte edilir. Tasarım düzeltmesi tüm geçiş planının veya canlı entegrasyonun tamamlandığı anlamına gelmez.

`NovaDashboardData`, `NovaMetricItem`, `NovaRecentFinding`, `NovaCompanyItem`, `NovaNotice` sunum girdileridir. Sayılar şirket/hesap kapsamında host'tan gelmelidir. Son uygunsuzluk küçük resmi host'tan gelir; fotoğraf yoksa ikonlu yedek görünüm kullanılır. Referanstaki özel saha fotoğrafı test verisi olarak kopyalanmadı.

iOS callback'leri hesap epoch'u ile korunur. Android olay/okuma/silme/çıkış callback'leri epoch taşır; host bunu güncel hesapla karşılaştırmalıdır. `available` sunucu yetkilendirmesi değildir. Bildirim okunma/silme sonucu host'un verdiği güncel listeden çizilir; UI sahte başarılı ağ işlemi üretmez.

Referanstaki Kerem/Koza Altın ve örnek sayılar yalnız ayrı, simülatöre özel `ISGShellHarness` ve Android test fixture'larında vardır. Gerçek uygulamada sabit müşteri kaydı yoktur. `--design` iOS tasarım önizlemesini açar; `--companies`, `--drawer`, `--add`, `--notices` hedef durumu seçer.

Android emülatör penceresi için `:isg-design-preview` ayrı offline QA host'udur (`com.riskdetectedan.isg.designpreview`). `:app` bağımlılığı değildir, release varyantı kapalıdır, internet izni manifest'ten çıkarılır ve fiziksel cihazda Activity kapanır. Auth/RevenueCat/Supabase veya gerçek kayıt içermez. Ana Android mağaza uygulaması bu paket değildir. `:isg-design-preview:assembleDebug` ile derlenir; yalnız doğrulanmış QA emülatörüne kurulmalıdır.

## Doğrulama

Kalıcı ekran kanıtları `design-reference-20260913/ios-implementation/` ve `design-reference-20260913/android-device/` altındadır. Android `android-implementation/` klasörü ek JVM/Skia render'ıdır; şeffaf dialog yakalamaları pencere karartması kanıtı değildir. Gerçek API33 ekranlarında Ekle blur'u ve pencere dim'i ayrıca incelendi. Android varsayılan Dialog karartması yerine Ekle için 0.34, diğer paneller için scrim token'ı kullanılır. Blur API31+ üzerinde 7 dp; eski Android'de karartma kalır.

Android tekrar komutu: önce ayrılmış `ISG_Contract_API33_20260912` emülatörüne debug QA APK'sını kur, viewport'u 440×956/mdpi yap; sonra depo kökünde `node scripts/isg/nova_android_smoke.mjs --serial emulator-5554`. Seri numarası o çalıştırmada doğrulanmalıdır. Script AVD/API/paket/çözünürlük kapıları ve UI ağacından türetilen dokunmalar kullanır; derleme/kurulum veya canlı hesap işlemi yapmaz. 8 kontrol, 5 PNG, arayüz XML'leri ve yalnız QA PID'sine ait crash buffer kaydı üretir. Bildirim kapatma hedefi gerçek UI ağacında en az 48×48 doğrulanır.

Bu tur sonunda QA paketi kaldırıldı, emülatörün özgün 320×640 çözünürlüğü geri yüklendi ve yalnız açılan QA emülatörü kapatıldı. Ana uygulamalar/verileri ve AVD silinmedi. QA paketi kaynak koddan yeniden kurulabilir.

Sonuç ve kalan farkların yetkili kaydı kökteki `design-qa.md` dosyasıdır. Görsel testler servis entegrasyonu/E2E veya mağaza kabulü yerine geçmez. Bundle/package kimlikleri, callback, entitlements, ürün kimlikleri ve canlı veritabanı değiştirilmedi. Mağazaya yükleme, deploy veya push yapılmadı.
