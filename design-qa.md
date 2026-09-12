# NOVA — tüm sayfalarda gri tuval / beyaz kart QA

Tarih: 13 Eylül 2026. Kapsam: kullanıcının gri başlık / beyaz gövde itirazı; yeni native NOVA shell'inin bütün mevcut hedeflerinde ortak yüzey kuralı. Canlı uygulamanın veya bütün geçiş planının kabulü değildir.

Önceki beş ekran raporu içerik değiştirilmeden [arşivlendi](docs/isg/evidence/DESIGN_QA_BEFORE_PAGE_SURFACES_2026-09-13.md).

## Kaynak, viewport ve son görünüm

Kaynaklar: [önceki hatalı görünüm](docs/isg/page-surfaces-20260913/before.png), [kullanıcının Firmalar referansı](docs/isg/page-surfaces-20260913/reference-companies.png). Bunlar kullanıcı dosyalarının değiştirilmemiş kopyalarıdır. Firmalar referansı 1320×2868 px, 440×956 pt @3; iOS final görüntüler aynı boyutta iPhone 17 Pro Max / iOS 26.5, açık tema, standart yazı boyutunda alındı.

Son [Firmalar](docs/isg/page-surfaces-20260913/ios/companies.png) ve [Ziyaret Ekle](docs/isg/page-surfaces-20260913/ios/newVisit.png) karşılaştırıldı. Ziyaret Ekle finali test araç çubuğu olmadan, gerçek Ekle popup'ındaki eyleme dokunularak açıldı. Kaynak, önceki hata ve son iOS/Android görüntüleri aynı görsel inceleme girdilerinde açıldı. Başlık, kart, zemin ve alt barın tam görünümü değerlendirildi.

Hatalı kaynak 838×576 px, cihaz çerçeveli ve alttan kesilmiş masaüstü görüntüsüdür; onunla piksel geometrisi eşitliği iddia edilmez. Firmalar kaynak ve uygulama aynı viewport'tadır; Ziyaret Ekle başka içeriğe sahip olduğundan karşılaştırma sayfa yüzey standardına ilişkindir. [Uygunsuzluklar kanıtı](docs/isg/page-surfaces-20260913/ios/findings-qa.png) ile newVisit-qa.png otomatik testin sarı araç çubuğunu içerir; bu çubuk ürün tasarımı değildir.

Android [açık](docs/isg/page-surfaces-20260913/android-jvm/newVisit-light.png) / [koyu](docs/isg/page-surfaces-20260913/android-jvm/newVisit-dark.png) görüntüler gerçek Compose görünüm ağacının native Skia/JVM çıktısıdır, cihaz ekranı değildir. 440×956 dp/mdpi; iOS güvenli alanı ve OS barlarıyla eşitlik iddiası yoktur. Bu turda yeni Android cihaz görüntüsü alınmadı.

## Bulgular ve kapanış

| Öncelik | Bulgu | Düzeltme ve son kanıt |
|---|---|---|
| P1 | Pushed iOS hedefinin varsayılan beyaz gövdesi gri tuvali bölüyordu | Her root ve alt hedefte NovaPageSurface; 17 hedefte üst/orta/alt kenar RGB240 ölçümü, final newVisit.png |
| P2 | iOS sistem navigation bar'ı ikinci geri düğmesi gösteriyordu | Her hedefte sistem barları gizli; tek NOVA geri kontrolü, UI ağaç testi ve final görüntü |
| P2 | Örnek alt sayfa içeriği ortalanmış ve beyaz karta ayrılmamıştı | Sola hizalı ikonlu başlık, 20 dış/iç boşluk, 16 bölüm aralığı, beyaz NovaCard; iOS/Android final çıktıları |

Son incelemede bu yüzey düzeltmesi kapsamında açık P0/P1/P2 görsel bulgu kalmadı. Genel uygulamanın tamamı bu raporla onaylanmış değildir.

## Zorunlu karşılaştırma alanları

- Font/tipografi: mevcut Plus Jakarta Sans ailesi ve beş ağırlık değiştirilmedi; title/body/meta hiyerarşisi korundu. Başlık artık sola hizalı. Türkçe yardımcı metin kart içinde okunaklı; iOS 320 pt AX3 gezinme testi de geçti.
- Boşluk/yerleşim: tek gri sayfa, bağımsız yuvarlak beyaz içerik, başlık ve kart arasında boşluk, alt bar çevresinde gri alan doğrulandı. Firma arama/kart düzeni korundu. Referansın tam kart geometrisini ziyaret formuna zorlamadık: kaynak Firma listesidir, ziyaret içeriği hâlâ test fixture'ıdır.
- Renk/token: canvas #F0F0F0 ve surface #FFFFFF; iOS 4 dikey kenar noktası ve beyaz kart pikseli her benzersiz hedefte denetlendi. Android 17 hedef ×2 tema. Koyu tema mevcut token'ları koruyor.
- Görüntü/ikon: yeni raster veya çizim üretilmedi. Mevcut orijinal NOVA ikonları ve fontlar tekrar kullanıldı; alt sayfa başlığında renkli glyph var, ikon kutusu yok. Kullanıcının ikon zeminlerini kaldırma talebi, referanstaki zeminli menü/bildirim düğmelerinden kasıtlı farktır. Avatarlar veri/fixture içeriğidir.
- Metin/içerik: sentetik test açıklaması ve Sayaç korunarak QA ekranı gerçek işlem gibi sunulmadı. Şirket/ziyaret alanlarının domain verisi bu görsel düzeltmenin parçası değildir. Butonlar ve Türkçe başlıklar okunaklı, sahte kayıt başarısı gösterilmiyor.

## Etkileşim ve testler

- iOS tam tur 11/11 PASS: tüm menü/Ekle yolları açık/koyu, sekme geçmişi, izin iptali, hesap değişimi, stale callback, arama, bildirim eylemleri, dış alana dokunarak kapatma, küçük ekran/AX3 ve dokunma hedefleri.
- Yeni iOS regresyonu 17 benzersiz hedefin piksel zemini/kartı ve sistem navigation bar yokluğunu kontrol ediyor. Araç çubuğu olmadan Ekle → Ziyaret Ekle ayrıca açılıp kaydedildi.
- Android 309/309 JVM PASS; iki yeni yüzey testi her 17 hedefi açık/koyu durumda dolaşıyor. Lint, preview APK ve ana APK başarılı.
- iOS QA/ana uygulama simulator build PASS. nova-design 20/20, mağaza kimliği kaynak kontrolü PASS.
- İlk hedefli iOS turunda tekil XCUI hittability anomalisi görüldü; beklentiler değiştirilmeden birebir test tekrarı 1/1 ve tam tur 11/11 geçti. Tekil anomalinin kalıcı kök nedeni çözülmüş sayılmıyor; [ayrıntılı kayıt](docs/isg/P18_PAGE_SURFACES_2026-09-13.md) başarısız sonucu da koruyor.

## Sınırlar / takip

NOVA shell henüz legacy üretim root'una bağlı değil. Kullanıcının gördüğü ekran ayrı offline QA uygulamasıdır. Bu düzeltme yeni shell'in tüm mevcut hedeflerini kapsar; gerçek ziyaret/uygunsuzluk ekranları ve domain servisi entegrasyonu ayrıca tamamlanacak. Yeni domain ekranları gri tuvali opak tam ekran beyazla kapatmamalı ve içerik kartlarını ortak bileşenden üretmelidir.

Android cihaz koşusu, fiziksel iOS, VoiceOver/TalkBack tam akışı ve gerçek Auth/billing/kamera bu turda test edilmedi. Native gölge/antialias ve OS güvenli alan farkları piksel aynılığı değildir. Eski beş ekran raporundaki kapsam dışı P3 farklar bu turda yeniden tasarlanmadı. Uzak CI/deploy/push yapılmadı.

## Kontrol listesi

- [x] Root ve bütün alt hedeflere ortak gri sayfa katmanını uygula.
- [x] Örnek hedef içeriklerini beyaz yuvarlak karta al; ikinci sistem geri düğmesini kaldır.
- [x] Kaynak ve gerçek render'ları birlikte karşılaştır; önceki hata görüntüsünü koru.
- [x] 17 hedef için piksel ve gezinme regresyonlarını çalıştır.
- [x] iOS/Android derleme ve tasarım kaynak kontrollerini doğrula.
- [ ] Ayrı geçiş işi: gerçek domain ekranları, veri adaptörleri ve üretim root entegrasyonu.

final result: passed
