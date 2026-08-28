# Android Profile + Analysis Sector Picker — Design QA

## Evidence

- iOS profile runtime reference: `/tmp/ios-profile-reference.png`
- iOS sector reference: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/analysis-sector-picker-screenshot/analysis_sector_picker_unselected.png`
- Android profile golden: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.profile_ios_parity_light.png`
- Android sector golden: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.analysis_sector_picker_three_column_light.png`
- Combined comparison: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/android-ios-profile-sector-parity/comparison.png`
- Android viewport: `393 × 852 dp`, `xxhdpi`, Turkish, light theme.
- iOS profile reference was captured from the existing UI-test fixture on an iPhone 16 Pro simulator; no `App/` source was changed.

## Findings and resolutions

1. P1 — Android profile used a plain centered identity card and a large “Profil” header; iOS uses a cover-led hero without a tab-page title. Resolved with the 148-point sky cover, 96-point overlapping avatar, tier/camera badges, left-aligned identity, professional-title capsule and four stat cells.
2. P1 — Android collapsed all professional progress content into one oversized card. Resolved by matching the iOS sequence: MDP showcase, weekly tracking, competency preview, then tier status.
3. P1 — Android profile actions were separate oversized cards and the floating tab bar obscured content. Resolved with iOS-style HESAP/AYARLAR grouped rows, inset dividers, 32-point icon tiles and 112 dp bottom content clearance.
4. P1 — Account rows were missing Geçmiş analizler/Raporlarım navigation. Resolved; both rows now show live progress counts and switch to their corresponding tabs.
5. P1 — Analysis sector choices were a one-column descriptive list and selection immediately advanced. Resolved with the iOS 74 dp card geometry, 3 columns on phones/4 on tablets, sector colors, badge priority, selected onyx state and explicit “Devam et”.
6. P2 — Android sector title/copy and close-button treatment differed. Resolved with “Analiz kapsamını seç”, the live iOS explanatory copy and platform back/swipe dismissal instead of an extra close control.
7. P2 — Plus/Pro identity was visually neutral. Resolved with Plus yellow and Pro green across avatar badge and subscription status card.

## Fidelity review

- Typography uses the existing iOS-derived Android optical scale and platform sans metrics; SF Pro is not redistributed.
- Profile cover proportions, 30 dp hero radius, 96 dp avatar, 54 dp stat strip, 14/16 dp card radii, menu inset and content rhythm follow the Swift source.
- The iOS runtime fixture has no professional-progress summary, while the Android golden intentionally includes one to validate the live-data branch. The MDP, weekly and competency components were checked against their corresponding Swift sources.
- Sector cards match the iOS three-column phone grid and selected-card behavior. Android system sheet motion/back handling remains platform-native.
- No actionable P0/P1/P2 finding remains.

## Interaction and regression checks

- Sector tap only selects; “Devam et” invokes the callback with the selected sector.
- Geçmiş analizler and Raporlarım switch tabs through `MainShell` callbacks.
- Profile bottom clearance prevents the floating navigation bar from covering rows.
- Roborazzi exact-pixel goldens recorded for both surfaces.
- `testDebugUnitTest`, `lintDebug`, and `assembleDebug` pass.
- Debug APK installed on API 36 emulator; cold launch succeeds and filtered crash buffer is clean.
- `git diff --check` passes and `App/` source diff is empty.

final result: passed

---

# iOS Sonuç Merkezi — Analiz Bilgi Kartı ve Fotoğraf Sayısı QA (2026-08-28)

## Kaynak ve çalışma zamanı kanıtı

- Kullanıcı referansı: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/TemporaryItems/NSIRD_screencaptureui_a8X6Uk/Ekran Resmi 2026-08-28 20.58.12.png`
- Uygulama görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-analysis-card-qa/test-attachments/50FEC20B-9059-4808-89F2-A1D262F15F8D.png`
- PLUS/PRO konum kanıtı: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-analysis-card-qa/test-attachments/8045AF8D-B9AC-4489-883D-A12D1DE89653.png`
- Birleşik karşılaştırma: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-analysis-card-qa/reference-vs-implementation.png`

## Karşılaştırma ve düzeltmeler

1. P1 — Analiz başlığı ve sektör bilgisi beyaz içerik üzerinde kayboluyor, fotoğraf alanı gerçek yüklemeler yerine genel yer tutucu ikonlar gösteriyordu. Başlık, sektör ve görseller tek bir `#F3F7F1` bilgi kartında toplandı; ince `#D8E4D6` sınır ile içerikten ayrıldı.
2. P1 — Fotoğraf sayısı sabit/temsili görünüyordu. Kart artık yetkili analiz fotoğraf satırlarından en fazla üç gerçek görseli alıyor; bir, iki veya üç yükleme durumunda yalnız mevcut yüklemeler gösteriliyor ve sıfır yüklemede sentetik görsel üretilmiyor.
3. P2 — Küçük görseller yalnız dekoratif değildi; gerçek yüklenen görsel, mevcut önbellekli fotoğraf yükleyicisiyle çiziliyor ve dokunulduğunda tam ekran önizleme açılıyor.
4. P1 — PLUS/PRO tanıtım şeridi analiz meta bilgisinin hemen altında sayfayı kalabalıklaştırıyordu. Şerit ikinci bulgu kartından sonra, üçüncü bulgudan önce taşındı. Tek bulgulu uç durumda ilk bulgudan sonra güvenli biçimde gösteriliyor.
5. Tipografi, risk özeti, yöntem seçimi, bulgu kartı ve sabit rapor alanı değiştirilmedi.

## Doğrulama

- `testResultHubGroupsAnalysisMetadataShowsActualPhotosAndPlacesPremiumAfterSecondFinding` geçti.
- `testResultHubReferenceVisualStates` geçti.
- `testResultHubPaidFixtureShowsThreeSectionsAndSelectableReport` geçti.
- Toplam: `3 passed, 0 failed`.
- Runtime kanıtında üç gerçek fixture fotoğrafı mevcut; dördüncü görsel yok.
- UI geometri doğrulamasında PLUS/PRO şeridi ikinci bulgunun altı ile üçüncü bulgunun üstü arasında.
- Simulator derlemesi başarılı; `git diff --check` temiz.
- Açık P0/P1/P2 bulgu kalmadı.

final result: passed

---

# iOS Sonuç Merkezi — Sabit Uygulama Header'ı QA (2026-08-28)

## Kaynak ve karşılaştırma

- Sorun kaynağı: `/Users/keremkayalar/Downloads/IMG_1199.PNG`
- Düzeltilmiş gerçek runtime görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-header-qa/test-attachments/7B201E7E-E076-4D42-BBD7-A86C400174F3.png`
- Aynı `1320 × 2868 px` viewport'ta önce/sonra karşılaştırması: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-header-qa/before-after-header-comparison.png`
- Durum: iPhone 17 Pro Max simulator, açık tema, Free fixture, liste aşağı kaydırılmış ve bölüm seçicisi sabitlenmiş.

## Düzeltmeler

1. P1 — Bölüm seçicisi güvenli alanın altında sabitlenirken üstte kalan alan opak bir uygulama yüzeyi tarafından sahiplenilmiyordu; kayan analiz başlığı, sektör ve premium şeridi durum çubuğunun arkasından görünüyordu.
2. Düzeltme — Sonuç listesi, diğer ana uygulama sayfalarında kullanılan logo, Free hesap için Yükselt CTA'sı ve profil menüsünü içeren sabit/katı `rdPaper` header'a bağlandı.
3. P1 — Header yalnız görsel ek olamazdı: logo artık sonuç tam ekranını kapatıp Ana Sayfa'ya döndürüyor; Yükselt ve profil menüsü mevcut ortak bileşenlerle çalışıyor.
4. Bölüm seçicisi ayrı scroll yüzeyinde sabit kalıyor ve `header.maxY == selector.minY` geometrisiyle birleşiyor; arada içerik gösteren boşluk veya yarı saydam katman kalmıyor.
5. Bulgu detay ekranı ayrı full-screen yüzey olarak korunuyor; talep doğrultusunda bu yeni uygulama header'ını göstermiyor.

## Regresyon doğrulaması

- `testResultHubHeaderStaysAbovePinnedSectionSelectorWithoutGap` geçti; kaydırma sonrasında header ve selector arasındaki fark en fazla `2 pt` olarak sınırlandı.
- `testResultHubPaidFixtureShowsThreeSectionsAndSelectableReport` geçti.
- `testResultHubReferenceVisualStates` geçti ve bulgu detayının headersız kalması dahil beş görünür durumu yeniden doğruladı.
- Toplam hedefli sonuç: `3 passed, 0 failed`.
- Result bundle: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-08-28T18-23-09-045Z_pid80643_02f0a848.xcresult`
- Açık P0/P1/P2 fark kalmadı.

final result: passed

---

# iOS Risk Analizi Tablosu — İçeriğe Oturan Sheet QA (2026-08-28)

## Kanıt ve normalizasyon

- Sorun kaynağı: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-report-sheet-expanded-qa/source-current.png`
- Düzeltilmiş gerçek uygulama görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-report-sheet-expanded-qa/implementation-after.png`
- Aynı `1320 × 2868 px` viewport'ta tek karşılaştırma yüzeyi: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-report-sheet-expanded-qa/comparison.png`
- Durum: iPhone 17 Pro Max simulator, açık tema, Türkçe, ücretli fixture, Risk Analizi Tablosu + Fine-Kinney + PDF seçili.

## Karşılaştırma geçmişi

1. P1 — Rapor türü değişince tek detent kümesi yeniden kuruluyor ve sistem geniş sheet'e düşüyordu; format kontrolleri ile alt eylem arasında büyük, işlevsiz boşluk kalıyordu.
2. Düzeltme — Kompakt ve geniş detent'ler sheet ömrü boyunca birlikte kayıtlı tutuldu; seçim yalnız detent binding'i üzerinden değiştirildi. Kompakt seçim ekranı `360 pt`, Risk Analizi Tablosu ekranı `535 pt` içerik yüksekliğine sabitlendi.
3. P2 — Başlık, yardımcı metin, kartlar, ikonlar, seçim halkaları ve yöntem/format segmentleri fiziksel cihazda küçük görünüyordu.
4. Düzeltme — Tipografi, kart min-height'ları, ikon kutuları, radio alanları, segment dolguları ve alt rapor eylemi birlikte büyütüldü; bilgi hiyerarşisi ve mevcut renk dili korunarak okunabilirlik artırıldı.
5. Son kanıt — Risk tablosu ekranı çıktı biçiminden hemen sonra alt eyleme geçiyor; büyük boş bölge yok. Kompakt ekranda da kartlar ile alt eylem arasında yalnız kontrollü yerleşim aralığı bulunuyor.

## Regresyon doğrulaması

- UI testi standart kartın en az `58 pt`, vurgulu Risk Analizi Tablosu kartının en az `90 pt` olduğunu doğruluyor.
- UI testi hem kompakt hem geniş durumda son içerik ile alt eylem arasındaki boşluğu `52 pt` altında tutuyor.
- `testResultHubRiskReportSheetIsCompactAndEmphasizesRiskTable` geçti.
- Görsel karşılaştırma sonrasında açık P0/P1/P2 bulgu kalmadı.

final result: passed

---

# iOS Risk Raporu Sheet — Kompakt Yerleşim QA (2026-08-28)

## Kanıt ve normalizasyon

- Kaynak görsel: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-report-sheet-qa/source-reference.png`
- Kompakt uygulama görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-report-sheet-qa/implementation-compact.png`
- Risk tablosu seçili uygulama görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-report-sheet-qa/implementation-expanded.png`
- Tek karşılaştırma yüzeyi: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-report-sheet-qa/reference-comparison.png`
- Kaynak boyutu `896 × 652 px`; uygulama görüntüsü `1320 × 2868 px`, iPhone 17 Pro Max simulator, `440 × 956 pt`, `@3x`, Türkçe, açık tema, ücretli fixture.
- Aynı açık/rapor türü seçilmemiş durum için uygulamanın sheet bölgesi `1320 × 1003 px` olarak kırpıldı ve kaynak yoğunluğuna `896 × 652 px` normalize edildi.

## Karşılaştırma geçmişi

1. P1 — Risk raporu sheet'i ekran yüksekliğinin büyük bölümünü sabit detent ile kaplıyor, iki seçenekten sonra geniş ve işlevsiz bir boşluk bırakıyordu.
2. Düzeltme — Seçilmemiş/Standart durum kompakt `275 pt`, Risk Analizi Tablosu seçenekleri açıldığında `455 pt` dinamik detent kullanacak şekilde ayrıldı. Alt eylem alanı içerikten hemen sonra geliyor; yalnız sistem home-indicator güvenlik alanı korunuyor.
3. P2 — Standart Rapor ve Risk Analizi Tablosu kartları aynı ağırlıktaydı. Standart kart `50 pt`, Risk Analizi Tablosu en az `78 pt` yapıldı; risk kartı kaynak görseldeki iki satırlı açıklama hiyerarşisine kavuştu.
4. P2 — Risk tablosu açıklaması kaynak metinden kısa, ikon ise görsel olarak nötrdü. Kaynaktaki tam açıklama ve altı çizili `Fine-Kinney`, `5x5 Matris`, `PDF`, `Excel` vurguları eklendi; tablo ikonu sarı-yeşil/teal renkli yüzeye geçirildi.
5. Son kanıt — Kompakt durumda seçenekler ve alt buton arasında işlevsiz boşluk kalmadı. Risk tablosu seçildiğinde sheet genişliyor; yöntem ve çıktı biçimi kontrolleri kesilmeden görünür kalıyor.

## Zorunlu yüzey kontrolü

- Tipografi: Başlık ağırlığı, iki seviyeli alt metin ve altı çizili vurgu hiyerarşisi kaynakla eşleşiyor; metin kırpılmıyor.
- Boşluk ve yerleşim: Sheet yüksekliği içerikle uyumlu; risk kartı Standart karta göre belirgin biçimde büyük; alt güvenlik boşluğu yalnız iOS home indicator için bırakılıyor.
- Renkler: Beyaz yüzey, açık gri sınırlar ve pasif CTA korunuyor; paylaş başlığı ile risk tablosu ikonu kaynak paletine uygun renk vurgusu alıyor.
- İkon/varlık: Kaynakta ayrı raster varlık gerektiren içerik yok; mevcut SF Symbols keskin ve doğru ölçekte kullanılıyor.
- Metin: Standart Rapor alt metni ve Risk Analizi Tablosu açıklaması kaynak görselle aynı anlam ve kapsamda.

## Etkileşim ve regresyon

- Sheet açılışı, rapor türü seçimi, Risk Analizi Tablosu kartının daha büyük olması ve yöntem alanının açılması gerçek UI testiyle doğrulandı.
- `testResultHubRiskReportSheetIsCompactAndEmphasizesRiskTable` geçti.
- Kompakt ve genişletilmiş durumların kalıcı test ekran görüntüleri alındı.
- Açık P0/P1/P2 fark kalmadı.

final result: passed

---

# iOS Sonuç Merkezi — Seçili Sekme Alt Rayı QA (2026-08-28)

## Kanıt ve normalizasyon

- Kaynak görsel: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-tab-rail-qa/reference-risk-selected.png`
- Risk seçili uygulama görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-tab-rail-qa/implementation-risk-selected.jpg`
- Uzman Görüşü seçili uygulama görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-tab-rail-qa/implementation-expert-selected.jpg`
- Kaynak piksel boyutu: `362 × 232`; uygulama görüntüleri: `368 × 800`; iPhone 17 Pro Max simulator, açık tema, Türkçe, ücretli fixture.
- Odak karşılaştırması üst sekme alanında yapıldı. Kaynak daha dar bir kırpım olduğu için tam ekran içerik yoğunluğu değil, seçili/pasif sekme sınır davranışı karşılaştırıldı.

## Karşılaştırma geçmişi

1. P1 — Ortak yeşil ray ön planda çizildiği için seçili sekmenin beyaz alt maskesinin üzerinden geçiyor ve kartı içerikten ayırıyordu.
2. Düzeltme — Ortak ray sekmelerin arka plan katmanına alındı; seçili sekmenin beyaz yüzeyi ve alt maskesi rayı yalnız kendi genişliği boyunca kesiyor.
3. Son kanıt — Risk Analizi seçiliyken çizgi Risk sekmesi altında görünmüyor; Uzman Görüşü seçildiğinde kesinti Uzman sekmesine taşınıyor ve pasif sekmeler altında ray kesintisiz sürüyor.

## Zorunlu yüzey kontrolü

- Tipografi, metin ve ikonlar değişmedi.
- Sekme ölçüleri, boşluk ritmi, renkler ve köşe yarıçapları değişmedi.
- Yeni görsel varlık eklenmedi; mevcut SF Symbols korunuyor.
- Etkileşim durumu iki ayrı sekmede gerçek runtime görüntüsüyle doğrulandı.
- `testResultHubReferenceVisualStates` geçti; `git diff --check` temiz.
- Açık P0/P1/P2 bulgu kalmadı.

final result: passed

---

# iOS Analiz Sonuç Merkezi — HTML Birebir Eşleme QA (2026-08-28)

## Kaynak ve kanıt

- Yetkili tasarım/etkileşim kaynağı: `/Users/keremkayalar/Downloads/iOS Tarif Tasarımı Yeniden Oluşturma/Box Week.dc.html`
- Free durum kaynağı: `/Users/keremkayalar/Downloads/iOS Tarif Tasarımı Yeniden Oluşturma/Box Week Free.dc.html`
- Aynı 440 × 956 viewport ana ekran karşılaştırması: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-html-reference/paid-risk-comparison.png`
- Aynı 440 × 956 viewport detay karşılaştırması: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-html-reference/paid-detail-comparison.png`
- Son iOS görsel durumları: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-html-reference/final-status-attachments/`

## Uygulanan eşleme

1. Üç bağlı sekmenin 96 pt alanı, seçili 84 pt beyaz yüzeyi, 72 pt lime pasif yüzeyi, 1.5 pt yeşil bağlantı çizgisi ve sayıları HTML ölçüleriyle eşlendi.
2. Risk özeti, yöntem seçimi, analiz başlığı/sektör, fotoğraf sayısı göstergeleri, PLUS/PRO şeridi, seçim durumu ve sabit alt rapor eylemi aynı hiyerarşiye taşındı.
3. Liste kartlarından fotoğraf tamamen kaldırıldı. Yükseltilmiş sıra ikonu, risk/skor/seçim satırı, özellik etiketleri ve koyu yeşil eylem şeridi referansla eşlendi.
4. Uzman Görüşü özet/kart/önlem blokları ve Onaylı Defter çizgili kâğıt görünümü aynı yerleşim diline geçirildi.
5. Defter görselindeki resmî onay iddiası güvenlik gereği `TASLAK · UZMAN ONAYI` olarak korunurken kâğıt ve damga geometrisi değişmedi.
6. Bulgu detayı 252 pt görünür fotoğraf kahraman alanı, üst reaksiyonları, yüzen rapor/düzenle/sil/paylaş eylemleri, skor bandı ve renkli içerik bloklarıyla HTML akışına eşlendi.
7. Rapor bottom sheet'i rapor türü, yöntem, PDF/Excel ve premium durumlarıyla kaynak davranışına bağlandı.

## Etkileşim ve regresyon

- Ücretli Risk/Uzman/Defter sekmeleri, Free teaser/paywall, İngilizce Safety Log terminolojisi, bulgu detayı ve rapor sheet'i doğrulandı.
- `testResultHubReferenceVisualStates` beş gerçek ekran durumunu kalıcı fixture olarak yakalıyor.
- Beş hedefli iOS UI testi birlikte geçti.
- iOS simulator derlemesi geçti; yeni ekran iOS 16 deployment hedefiyle uyumlu.
- Ana ekran ve bulgu detayı referans/uygulama görüntüleri tek karşılaştırma yüzeyinde incelendi; açık P0/P1/P2 görsel fark kalmadı.

final result: passed

---

# Üç Bölümlü Analiz Sonuç Merkezi — Referans Eşleme QA

## Kanıt

- Üst seçici referansı: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-f74509a5-2e9d-4eed-be83-bf082e41fc34.png`
- Kart referansı: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-efe44f63-6f2f-4552-a013-76d53c1f42d1.png`
- iOS uygulama görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-design-qa/ios-result-hub.png`
- Tek yüzeyde referans/uygulama karşılaştırması: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-design-qa/reference-comparison.png`
- Uygulama viewport'u: `1170 × 2532 px`, iPhone 16 Pro simulator, Türkçe, açık tema, Plus/Pro test verisi.
- Karşılaştırma yüzeyi: `3600 × 3800 px`; kaynak seçici, kaynak kart ve aynı durumdaki gerçek uygulama ekranını birlikte içerir.

## Görsel karşılaştırma ve düzeltmeler

1. P1 — Eski üç bölüm seçicisi birbirinden kopuk üç genel kart gibi görünüyordu. Seçili sekme beyaz, üst köşeleri yuvarlak, yan/üst yeşil konturlu ve alt içerik çizgisine fiziksel olarak bağlı hale getirildi. Seçili olmayan sekmeler referanstaki açık lime yüzeye geçirildi.
2. P1 — Eski bulgu kartının büyük fotoğraf alanı bilgi hiyerarşisini bastırıyordu. Kullanıcı kararı doğrultusunda fotoğraf tamamen kaldırıldı; kart referanstaki beyaz içerik gövdesi, ince yeşil kontur, güçlü başlık ve kesintisiz koyu yeşil eylem şeridi oranlarına uyarlandı.
3. P1 — Kritik/Yüksek/Orta/Düşük için dört küçük sayaç yetersiz görsel öncelik oluşturuyordu. Tek bir “Risk Dağılımı” yüzeyi; halka grafik, toplam, iki satırlı risk lejandı ve oransal renk şeridiyle değiştirildi.
4. P2 — Seçim, risk etiketi ve kart türü görsel olarak birbirine karışıyordu. Seçim kutusu, kart türü etiketi ve risk rozeti ayrı hiyerarşilere alındı.
5. P2 — Alt eylemler karttan kopuk ve zayıf görünüyordu. Referans oranına yakın 58 pt koyu yeşil şerit, beyaz platform ikonları ve sağa hizalı “Ayrıntıları Gör” eylemi kullanıldı.
6. P2 — iOS/Android görsel davranışı ayrışıyordu. Android Compose yüzeyi aynı sekme geometrisi, fotoğrafsız kart, risk dağılımı ve eylem şeridiyle eşlendi.

## Etkileşim ve regresyon doğrulaması

- iOS sonuç merkezi dört hedefli UI testi geçti: ücretli üç bölüm/seçim, İngilizce terimler, Free teaser/paywall ve üç rapor kapsamı/PDF.
- Android `:app:compileDebugKotlin` ve bütün `testDebugUnitTest` paketi geçti.
- Bölüm seçimi, rapor seçimi, like/dislike, düzenleme, silme ve detay erişilebilirlik etiketleri korunuyor.
- Free teaser alanlarında tam metin, seçim ve geri bildirim hâlâ kapalı; Plus/Pro kartlarında tam eylemler açık.
- Kartların hiçbiri kaynak fotoğraf indirmiyor veya göstermiyor.
- Referansın yemek fotoğrafı, kullanıcının açık kararı nedeniyle bilinçli istisnadır; kart yüzeyi ve alt eylem şeridi referans alınmıştır.
- Görsel karşılaştırma sonrasında açık P0/P1/P2 bulgu kalmadı.

final result: passed

---

# iOS Sonuç Merkezi — Alt Rapor Alanı QA (2026-08-28)

## Kanıt ve normalizasyon

- Kaynak alt alan: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-bottom-bar-qa/reference-bottom-bar.png`
- Uygulama görüntüsü: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-bottom-bar-qa/implementation-bottom-bar.jpg`
- Kaynak piksel boyutu: `574 × 242`; uygulama görüntüsü: `368 × 800`; iPhone 17 Pro Max simulator, açık tema, Türkçe, ücretli fixture.
- Kaynak odak kırpımı ve uygulamanın alt bölgesi aynı karşılaştırma girdisinde incelendi; farklı yoğunluk nedeniyle yalnız alt eylem geometrisi ve boşluk ritmi değerlendirildi.

## Karşılaştırma geçmişi

1. P2 — Rapor eylemi normal safe-area sınırının üstünde kalıyor; kendi 12 pt alt dolgusu ile sistem alt boşluğu birleşerek butonun altında gereksiz beyaz alan oluşturuyordu.
2. Düzeltme — Sonuç merkezi yalnız alt kenarda ekran sınırına uzatıldı; rapor alanı sistem hareket göstergesi için kontrollü 18 pt koruma bırakacak şekilde yeniden yerleştirildi.
3. Son kanıt — Buton, seçim sayacı ve ekran altı arasındaki ritim referansla eşlendi; gereksiz ikinci boşluk kaldırıldı ve sistem hareket alanıyla çakışma oluşmadı.

## Zorunlu yüzey kontrolü

- Tipografi, buton yüksekliği, ikonlar, renkler, gölge ve metin değişmedi.
- Yalnız alt yerleşim/safe-area davranışı değişti; içerik ve rapor etkileşimi korunuyor.
- Yeni görsel varlık eklenmedi.
- `testResultHubReferenceVisualStates` ve alt boşluk sınırını doğrulayan `testResultHubPaidFixtureShowsThreeSectionsAndSelectableReport` geçti.
- `git diff --check` temiz; açık P0/P1/P2 bulgu kalmadı.

final result: passed
---

# iOS Sonuç Merkezi — Mulish Tipografi Eşleme QA (2026-08-28)

## Kaynak ve tipografi sözleşmesi

- Yetkili tasarım kaynağı: `/Users/keremkayalar/Downloads/iOS Tarif Tasarımı Yeniden Oluşturma/Box Week.dc.html`
- Free durum kaynağı: `/Users/keremkayalar/Downloads/iOS Tarif Tasarımı Yeniden Oluşturma/Box Week Free.dc.html`
- Kaynaktaki aile: `Mulish, -apple-system, sans-serif`.
- Kaynak ağırlıkları: `400`, `600`, `700`, `800`, `900`; kullanılan `500` ağırlığı için gerçek `Mulish-Medium` dosyası eklendi.
- Uygulamaya gömülen aileler: `Mulish-Regular`, `Mulish-Medium`, `Mulish-SemiBold`, `Mulish-Bold`, `Mulish-ExtraBold`, `Mulish-Black`.
- Aynı yüzeyde HTML/iOS karşılaştırması: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-mulish-qa/mulish-reference-comparison.png`
- Uygulama kanıtları: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/result-hub-mulish-qa/test-attachments/`

## Uygulanan düzeltmeler

1. P1 — Sonuç merkezi bazı metinleri sistemin rounded yazı karakteriyle çizdiği için HTML referansındaki harf oranları, yoğunluk ve satır kırılımları farklıydı. Sonuç merkezi, detay ekranı ve rapor sheet'i tek bir `ResultHubTypography` eşlemesine geçirildi.
2. P1 — Font dosyaları yalnız kodda adlandırılmak yerine uygulama bundle'ına eklendi ve `UIAppFonts` altında kaydedildi. Derlenmiş uygulamada bütün altı dosyanın ve PostScript adlarının bulunduğu doğrulandı.
3. P2 — Rapor seçim ekranındaki başlık, açıklama, alan etiketi ve eylem boyutları HTML'deki `15/14/12.5/11.5/10/9 pt` ölçeğine ve `500–900` ağırlıklarına eşlendi.
4. P2 — Kaynak boyutlara dönüşten sonra genişletilmiş rapor sheet'inde oluşabilecek dikey boşluk, detent yüksekliği `535` yerine `510 pt` yapılarak giderildi; kart ve ikonların daha önce büyütülen dokunma geometrisi korunuyor.
5. Sonuç ekranında daha önce kararlaştırılan risk adı etiketleri (`Tolerans Dışı`, `Önemli Risk` vb.), seçili sekme rayı ve alt rapor alanı davranışı değişmedi.

## Doğrulama

- `testResultHubReferenceVisualStates` geçti.
- `testResultHubRiskReportSheetIsCompactAndEmphasizesRiskTable` geçti.
- Toplam: `2 passed, 0 failed`.
- Test sonucu: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-08-28T18-17-22-411Z_pid80643_1bb5d2d5.xcresult`
- Ana sonuç, bulgu detayı, kompakt rapor ve genişletilmiş Risk Analizi raporu gerçek runtime görüntüleriyle incelendi.
- Açık P0/P1/P2 tipografi farkı kalmadı.

final result: passed
