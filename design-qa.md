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

---

# Design QA — Firma, işyeri ve rapor akışları

Tarih: 21 Eylül 2026. Cihaz: RD QA iPhone 16 Pro simulator, iOS 26.5, açık tema.

## Karşılaştırma ve bulgular

- Kullanıcının Rapor Merkezi ekranı `design-qa-captures/report-center.png` ile; eski rapor türü ekranı yeni `design-qa-captures/report-content.png` ile yan yana incelendi.
- Bir rapor kartı artık “Kapsam ve dönem” adımına açılıyor; tekrar rapor türü seçtirmiyor.
- Sonraki ekran varsayılan seçili modül başlıkları, tümünü seç/temizle ve özel alan ekleme sunuyor.
- Firma detayında özet kartının hemen altında görünür “Logo seç” eylemi bulunuyor.
- Ana/ikincil eylemler güvenli alan üzerinde, uzun içerik kaydırılabilir ve hedefler en az 44 pt.
- Kontrol listesi filtreleri aynı kompakt filtre sistemini ve okunur loading/empty durumlarını koruyor.

## Otomatik kanıt

- `NovaPilotUITests/testWizardExpansionVisualAudit`: passed.
- `NovaPilotUITests/testCompanyCardExposesDirectLogoPickerAndLargePopupCloseTarget`: passed.
- `scripts/isg/run_suite.mjs nova-design`: 217/217 passed.
- Simulator build ve fiziksel OSGB pilot build 138: passed.

final result: passed

---

# Design QA — Analiz yoğunluğu ve işlem akışları

Tarih: 22 Eylül 2026. Cihaz: RD QA iPhone 16 Pro simulator, iOS 26.5, açık tema.

## Kaynak ve son görünüm

- Kaynaklar: kullanıcının analiz listesi, analiz sonucu, bulgu detayı, firma aktarımı ve rapor seçim ekranı görselleri (`codex-clipboard-e429f3f5-df84-4cc4-bc3f-21188663e57c.png` ile başlayan altı ekran).
- Son render'lar: `/Users/keremkayalar/.codex/visualizations/2026/09/21/01a0c3a6-6b69-7020-9efe-d00259cdb702/xcresult-analysis-final/` içindeki `01-analysis-list`, `02-analysis-result-risk`, `02b-analysis-report-options`, `04-analysis-finding-detail` ve `04b-analysis-filing-company` isimli test ekleri.
- Kaynak ve son ekranlar aynı görsel inceleme turunda açıldı. Kaynak canlı verili 440×956 pt ekran, final sentetik fixture verili 402×874 pt ekran olduğundan içerik/piksel eşitliği değil; yoğunluk, tipografi, tekrar, eylem sırası ve geri dönüş davranışı karşılaştırıldı.

## Bulgular ve kapanış

- Liste kartlarında yalnız başlık kalın; tarih, firma, sektör ve sayaçlar normal ağırlıkta. Saat ve ikinci tarih tekrarı kaldırıldı; “İncelenmedi” satır içi etiketi kaldırılarak firma/sektör alanı açıldı.
- Sonuç bağlam kartındaki renkli etiket yüzeyleri kaldırıldı. Fotoğraf küçültüldü; firma atama ve tarih sakin, tek renkli satırlar olarak gösteriliyor. Öncelikli bulgu alanı nötr yüzeye çekildi.
- Bulgu detayında analiz başlığı içindeki tarih/saat temizleniyor ve tarih yalnız bir kez gösteriliyor.
- `Uygunsuzluk oluştur` artık bulgu detayını geri kapatmıyor. Tam sayfa firma seçimi görünür geri düğmesiyle açılıyor; tek işyeri varsa ikinci onay istemeden kaydı açıp bulgu detayına dönüyor. İşyeri olmayan kişisel firmalar için yetkili varsayılan işyeri hazırlama yolu eklendi.
- `Rapor oluştur` seçim modunu ve “Seçilenlerle devam” ara adımını kaldırdı; doğrudan PDF/Excel seçeneklerine açılıyor ve PDF varsayılan seçili geliyor.

## Otomatik doğrulama

- Simulator build: passed.
- `scripts/isg/nova_analysis_flow.test.mjs`: 25/25 passed.
- `NovaDesignAuditUITests/testAnalysisResultAndSectionSurfaces`: passed; liste, sonuç, doğrudan rapor seçenekleri, bulgu detayı, tam sayfa firma seçimi ve başarılı kayıt sonrası bulgu detayına dönüş doğrulandı.
- Görsel turda açık P0/P1/P2 bulgu kalmadı.

final result: passed

---

# Design QA — Analiz listesi, sonuç ve bulgu detayı

Tarih: 22 Eylül 2026. Kaynak: `ISGADA_Analiz_Ekranlari_UX_UI_Yeniden_Tasarim_2026.md`. Cihaz: RD QA iPhone 16 Pro simulator, açık tema.

## Uygulanan hiyerarşi

- Analiz listesi kompakt toplam/kritik/bulgu metrikleri, tek arama, tek filtre girişi, sıralama ve bütün satırı açan kayıt kartlarına dönüştürüldü.
- Analiz sonucu global başlıktan ayrıldı; bağlam kartını bulgu/kritik/yüksek/en yüksek skor özeti ve öncelikli bulgu takip ediyor.
- Risk, uzman görüşü ve eğitim sekmeleri sayaçlı kompakt pill yapısında; normal okumada checkbox ve satır içi düzenle/sil/geri bildirim eylemleri yok.
- `Rapor oluştur` bulgu seçim ara adımı olmadan doğrudan PDF/Excel seçeneklerini açıyor; PDF varsayılan seçili geliyor.
- Bulgu ayrıntısı tam ekran geri navigasyonu, ayrı fotoğraf, semantik seviye, katlanmış skor formülü, overflow işlemleri ve tek `Uygunsuzluk oluştur` eylemi kullanıyor.

## Doğrulama

- `NovaDesignAuditUITests`: önceki 3/3 turuna ek olarak güncel hedefli tur geçti; analiz listesi, sonuç, doğrudan rapor seçenekleri, uzman/eğitim sekmeleri, bulgu detayı ve tam sayfa uygunsuzluk akışı doğrulandı.
- `scripts/isg/pilot_native.test.mjs`: 6/6 geçti.
- Simulator derleme ve çalıştırma: geçti (`com.riskdetected.app.osgbpilot`).
- `git diff --check`: geçti.

final result: passed

---

# Design QA — Firma ilerleme halkası

Tarih: 21 Eylül 2026.

## Kaynak ve uygulama kanıtı

- Görsel doğruluk kaynağı: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-c77a386c-a2c0-4883-ad1f-152c53b2351a.png`.
- Uygulama görüntüsü: `/Users/keremkayalar/.codex/visualizations/2026/09/21/01a0c3a6-6b69-7020-9efe-d00259cdb702/company-progress/177B5E33-51A3-4A15-ACB1-BB6B0627184F.png`.
- Kaynak 1320×1051 px bağımsız yatay karttır. Uygulama 1178×2556 px, iPhone 14 Pro 393×852 pt @3 açık tema ekran görüntüsüdür.
- Durum: Firma Detayı, Risk Analizi segmenti seçili; iki tamamlanan, bir kontrol gereken ve yedi veri bekleyen sentetik QA kaydı.
- Kaynak kart ile uygulama kartı aynı karşılaştırma girdisinde birlikte açıldı. Kaynak bağımsız yatay bileşen, uygulama ise gerçek mobil sayfa içinde olduğundan piksel eşitliği iddia edilmedi; bilgi mimarisi, halka/legend oranı, tooltip, özet alanı ve yüzey dili karşılaştırıldı.
- Odaklı ayrı kırpma gerekmedi: kaynak yalnızca karttan oluşuyor ve uygulama görüntüsündeki kart bütün tipografi ile segmentleri okunur ölçekte gösteriyor.

## Bulgular ve karşılaştırma geçmişi

- İlk uygulamada başlık, sağ üst kapsam kapsülü, siyah seçim balonu, 10 ayrı halka parçası, merkezde tamamlanma sayısı, sağda renkli durum sayımları ve altta özet alanı aynı hiyerarşide kuruldu.
- P0/P1/P2 fark bulunmadı. Mobil sütun genişliği nedeniyle kaynakta üst üste binen seçim balonu uygulamada halka satırının hemen üstünde konumlanıyor; bu, metnin kırpılmasını önleyen kabul edilebilir responsive uyarlamadır.
- P3: Kaynaktaki balonun küçük üçgen kuyruğu uygulanmadı. Balonun seçili segmenti metin ve renk noktasıyla açıkça belirtmesi nedeniyle kullanım etkilenmiyor.

## Zorunlu yüzey kontrolü

- Font/tipografi: Plus Jakarta Sans; başlık, merkez sayı, legend ve yardımcı metin ağırlıkları kaynak hiyerarşisiyle uyumlu ve kırpılmıyor.
- Boşluk/yerleşim: 10 parçalı halka ile legend tek satır düzeninde; 393 pt genişlikte taşma yok. Bilgi alanı ve mevcut firma kartı ayrı yüzeyler olarak okunuyor.
- Renk/token: Kaynak yeşil/lavanta/turuncu ayrımı uygulamanın marka yeşili, erişilebilir lavanta, turuncu ve nötr gri durum renkleriyle korunuyor.
- Görüntü/ikon: Kaynakta raster içerik yok. Uygulama sistem ikonlarını ve native SwiftUI şekillerini keskin, çözünürlük bağımsız olarak kullanıyor.
- Metin/içerik: Kullanıcının belirttiği 10 başlık gerçek durum verisinden hesaplanıyor; tarihli modüllerde süresi geçen, yaklaşan veya takipsiz kayıt “Kontrol gerekli” sayılıyor.

## Etkileşim ve doğrulama

- Her halka parçası ayrı 44 pt üzeri erişilebilir düğmedir; telefonda dokunma, işaretçi bulunan cihazlarda hover seçimi değiştirir.
- `NovaPilotUITests/testCompanyDetailShowsCompactSectionsWithoutTrackingCard`: passed; 10 segment ve Risk Analizi dokunma durumu doğrulandı.
- Simulator build ve `scripts/isg/nova_wizard_expansion.test.mjs` (9/9): passed.

final result: passed
