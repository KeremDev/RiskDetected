# NOVA — beş referans ekran QA kaydı

Tarih: 13 Eylül 2026, Europe/Istanbul. Kapsam: yeni native sunum katmanının kullanıcı ekranlarına uyarlanması. Canlı uygulama entegrasyonu veya bütün geçiş planının kabulü değildir.

Bu dosyanın önceki feedback ve diğer tasarım QA kayıtları içerik değiştirilmeden [tarihsel arşivde](docs/isg/evidence/DESIGN_QA_BEFORE_P18_2026-09-13.md) korunmuştur; bu tur onların sonuçlarını yeniden doğrulamış sayılmaz.

## Kaynak ve karşılaştırma

Görsel gerçeklik: `docs/isg/design-reference-20260913/{home,drawer,quick-add,notifications,companies}.png`. Kullanıcının IMG_1432/1433/1434/1435/1436 dosyalarının değiştirilmemiş kopyaları. Her biri 1320×2868 px, 440×956 pt @3×. SwiftUI uygulama kanıtları aynı adlarla `ios-implementation/` altında, aynı piksel boyutunda; iPhone 17 Pro Max / iOS 26.5, açık tema, standart yazı boyutu, sentetik uzman hesabı.

Compose uygulama kanıtları aynı adlarla `android-device/` altında: API33, 440×956 px/mdpi, 440×956 dp; CSS viewport yok, native uygulama. Orijinaller `sips -z 956 440` ile yalnız karşılaştırma kopyalarına normalize edildi (`output/isg/reference-redesign-20260913/normalized-source/`); kaynak PNG'ler değiştirilmedi. Beş normalize kaynak ve karşılık gelen beş gerçek Android görüntüsü aynı karşılaştırma girdisinde açıldı. Beş iOS ekranı da kaynaklarıyla aynı karşılaştırma girdilerinde incelendi; son ana sayfa/Ekle/bildirim görüntüleri son turda yeniden karşılaştırıldı.

Durumlar: ana sayfa başlangıcı, sol menü açık, iki okunmamış bildirim, dört eylemli Ekle, bir firmalı liste. Ekle kaynak görüntüsü arkadaki sayfada farklı scroll konumundadır; popup geometrisi/karartma/blur karşılaştırıldı, arkadaki metin konumunda piksel eşitliği iddia edilmez. Android OS güvenli alanı ve alt sistem alanı iOS'tan farklıdır; içerik yukarıdan yaklaşık 30–38 dp daha erken başlar ve alt sekmeler daha aşağıdadır. OS saat/batarya/hücre simgeleri uygulama tasarımı değildir.

Tam görünüm karşılaştırmaları kart hiyerarşisi, başlıklar, alan oranları, satır ritmi ve popup durumlarını kapsar. 1320 px iOS görüntülerinde ve normalize Android çiftlerinde etiketler/ikonlar okunabildiği için ek kırpma gerekmedi. Vektörlerin kesinliği ayrıca path eşitliği testleriyle denetlendi; yalnız test sonucundan görsel kabul çıkarılmadı.

## Bulgular ve düzeltme geçmişi

| Öncelik / konum | Önceki bulgu ve etkisi | Uygulanan düzeltme | Son kanıt |
|---|---|---|---|
| P1 / shell ve Ekle | Yaklaşık sheet geometrisi, ikon kutuları ve farklı yerleşim kaynak görünümünü bozuyordu | Ortak içeriğe göre boyutlanan NovaPopupSurface; merkez Ekle, üst bildirim, tam boy sol drawer; kullanıcının talebiyle ikon zeminleri kaldırıldı | Her iki platformun beş final PNG'si |
| P2 / ikon ve fotoğraf alanı | Sistem simgesi ikameleri kaynak çizgileriyle aynı değildi | OSGB'nin 48 orijinal vektörü + Feather fontundan mekanik çıkarılmış 2 motif; lisans ve path testleri | home/quick-add PNG'leri; nova-design 16/16 |
| P1 / iOS modal sonrası dokunma | İlk turlarda dekoratif görüntü düğümü modal kapanınca hedef tıklamasını bozuyordu | Dekoratif ikon accessibilityHidden, ebeveyn Button etiketi ve 44 pt alan; alt katmanın modal etkileşim kapısı | Tam 10/10 UI turu, sonraki 2/2 ve 1/1 tekrar |
| P2 / iOS Ekle arka planı | Denenen material örtüsü gereğinden opak görünüyordu | İçerikte 7 pt blur + ayrı 0.34 karartma; Reduce Transparency desteği | ios-implementation/quick-add.png |
| P2 / ana sayfa dikey ritmi | Eğitim kartı boşlukları ve yeni kayıt bölümü referans yerleşiminden sapıyordu | Eğitim kartı padding/gap, fotoğraf alanı, CTA ve iOS yeşil gölge düzeltildi | Son ios-implementation/home.png; Android home.png |
| P2 / Android Dialog | JVM görüntüsü gerçek pencere dim'ini kanıtlamadı; ilk emülatör görüntüsünde varsayılan 0.6 fazla koyuydu | Dialog window dimAmount açıkça Ekle 0.34 / diğer scrim token olarak ayarlandı | android-device/quick-add.png ve notifications.png |
| P1 / Android bildirim kapat | Bileşen testi geçse de gerçek UI ağacında komşu metin düğmesi kapat alanını 36–40 dp'ye kırpıyordu | 48 dp başlık hedefi ve alttaki eylemlerden 8 dp ayırma; gerçek ağaçta 48×48 zorunlu kontrol | android-device/result.json; notification-popup-and-close-target PASS |

Önceki deneme ekranları ve XCTest sonuçları `output/isg/reference-redesign-20260913/` ile XcodeBuildMCP sonuç dizininde tutuldu; başarısız denemeler son başarı olarak sunulmadı. Son görsel karşılaştırmada kapsam içi açık P0/P1/P2 bulgusu kalmadı. Aşağıdaki kasıtlı/platform farkları nedeniyle piksel piksel aynılık iddiası yoktur.

## Zorunlu beş yüzey

- **Font / tipografi:** kaynak Plus Jakarta Sans ailesi ve beş lisanslı ağırlık iki native istemcide; Türkçe glif testi var. NOVA/ana başlık, 15 pt popup satırları ve yaklaşık 11–12 pt yardımcı metin hiyerarşisi kontrol edildi. Uzun bildirim detayı, Türkçe firma alt satırı ve metin taşması incelendi. Native antialias/line-height küçük farkları beklenir; Canlı Akış ilk ifadesinin kısmi kalınlığı P3 düzeyinde farklıdır.
- **Boşluk / yerleşim:** beyaz kartlar, yatay 86 genişlikli özet, yeni kayıt fotoğraf alanı, CTA, eğitim, son kayıtlar ve alt bar sırası korundu. Ekle yaklaşık 400 pt/dp yüksekliğinde, 14 yan boşluk, 30 radius. Drawer 290 genişlik. Bildirim iOS yaklaşık 240, Android 270 yüksekliğinde; Android'in 48 dp hedefleri kaynak 234 pt panelden daha yüksek alan gerektirir. Bu fark native dokunma hedefi uyarlamasıdır; ekran dışına taşma yoktur.
- **Renk / token:** açık gri #F0F0F0 tuval, beyaz kartlar, gri yardımcı yazılar ve yeşil ana eylem; mor/kırmızı/amber ikon çizgileri. İkon arka planlarının kaldırılması kullanıcının açık isteğidir. Android notification yüzeyi iOS material'ından daha opaktır; platform yüzey uygulamasıdır. Ekle blur/karartma gerçek pencere görüntülerinde doğrulandı.
- **Görüntü / varlık:** orijinal çizgiler native template SVG/vector kaynaklarına mekanik taşındı, yeniden tasarlanmadı; fotoğraf motifleri orijinal font outlines. Kaynak ekran raster olarak arayüze yapıştırılmadı. Referanstaki özel saha fotoğrafı fixture'a taşınmadı; iOS kayıt küçük resminde ikonlu yedek görünüm, Android offline örneğinde boş son kayıt listesi vardır. Bu veriye bağlı farktır; gerçek host fotoğraf/veri sağlamalıdır.
- **Metin / içerik:** beş ekranın ana etiketleri, dört Ekle eylemi, 13 menü hedefi, firma açıklaması ve bildirim eylemleri korundu. Android preview bağlantısı özellikle “Çevrimdışı test” yazar; sahte çevrimiçi durum üretilmez. Örnek ad/firma yalnız test host'larında; ürün katmanında sabit müşteri veya sahte başarılı ağ işlemi yoktur.

## Etkileşim ve teknik kanıt

- iOS tam hostlu UI 10/10; 34 menü yönlendirmesi, hesap değişimi/availability/native stack, küçük ekran ve AX3 kaydırma, 44 pt hedef, bildirim okuma/silme, arama ve CTA. Tam turdan sonraki varlık/CTA değişimleri 2/2; son ritim/gölge değişimi beş ekranı yakalayan 1/1 hedefli tekrar ile doğrulandı. Hostless 18/18 ve ana iOS simülatör build PASS.
- Android design system JUnit XML: 219 test, 0 failure/error/skip. İlgili lint görevleri, ana debug APK ve ayrı offline preview APK PASS. Gerçek API33 penceresinde 8 smoke kontrolü; arayüz ağacından dokunma, 48 dp kapat alanı, read/clear, dört hızlı eylemin görünürlüğü, arama/temizleme ve firma yönlendirmesi. Son QA PID crash buffer'ında FATAL EXCEPTION yok. Bu sekiz kontrol sekiz tam domain E2E senaryosu değildir.
- Ortak gezinme 78 fixture / 198 geçiş; kaynak/tasarım 16/16 ve foundation 111/111. Kimlik kontrolü PASS; imzalı binary/mağaza sürekliliği bu kaynak testiyle kanıtlanmaz.
- Android API26/37 üzerinde bu yeni pencere akışı, fiziksel cihazlar, TalkBack/VoiceOver bütünlüğü ve gerçek Auth/billing/notification/kamera servisleri bu turda doğrulanmadı. Uzak CI çalıştırılmadı.

## Açık sorular ve takip

Yeni görünümler legacy uygulama köküne henüz bağlanmadı. Domain verisi/hesap kapsamı, yükleme-hata davranışı ve gerçek kamera/çıkış/bildirim işlemleri güvenilir host entegrasyonunda tamamlanmalı; bu görsel QA onların yerine geçmez. Kullanıcının beş ekranı dışında kalan bütün eski popup'ların otomatik olarak değiştiği iddia edilmez: yeni popup'lar için ortak bileşen ve standardı kaydedildi.

P3 takip: Canlı Akış başındaki kısmi kalın yazı, platformlar arası gölge/materyal ve antialias farklarının ince ayarı. Bunlar etkileşim veya yerleşimi engellemiyor.

## Uygulama kontrol listesi

- [x] Beş kaynak ekranı ve iki native uygulama görüntülerini sakla.
- [x] İkon zeminlerini kaldır; orijinal çizimleri/lisansı koru.
- [x] Ortak popup/drawer/bildirim konumlarını ve modal dokunma alanlarını doğrula.
- [x] iOS UI, Android JVM/gerçek pencere smoke ve ana build kontrollerini çalıştır.
- [x] Android QA paketini kaldır, çözünürlüğü geri yükle, yalnız QA emülatörünü kapat.
- [ ] Ayrı geçiş işi: yeni sunumu canlı uygulama/domain servislerine bağla ve canlı olmayan uçtan uca entegrasyon ortamında doğrula.

final result: passed
