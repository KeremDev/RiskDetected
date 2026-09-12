# P18 — native NOVA tasarım katmanı

12 Eylül 2026. Kullanıcının seçtiği OSGBTakip uzman tasarımının ilk native dilimi. **P18 veya tüm İSG geçişi tamamlanmadı.** Mevcut root navigation, paywall, Auth, abonelik, veritabanı ve canlı ekranlar bu katmana geçirilmedi. Bundle/paket/callback/entitlement kimlikleri aynı.

## Taşınan kapsam

- Sabit kaynak: `contracts/isg/v1/design/osgb-nova-reference.json`, commit `838d40e4`. Başka rol veya OSGB iş kuralları taşınmaz.
- Her temada40 renk,17 tipografi rolü,26 ölçü: `scripts/isg/nova_tokens.mjs` aynı kayıttan Swift/Kotlin kaynaklarını ve native test corpus'unu üretir. CLI `--check` yalnız doğrular, dosya yazmaz. Kaynak değiştiğinde üretilmiş dosya/test corpus farklılığı testte yakalanır.
- Plus Jakarta Sans400/500/600/700/800 iki uygulamaya değiştirilmeden gömüldü; SIL OFL1.1 lisansı her iki pakette bulunur. Fontlar internetten yüklenmez. iOS UIAppFonts kayıtları mevcut Mulish'e eklendi; eski tipografi değiştirilmedi. PostScript adları ve Türkçe glyph'ler CoreText ile doğrulandı.
- SwiftUI: `App/DesignSystem/ISG/NovaTokens.swift`, `NovaComponents.swift`.
- Compose: `android/core/designsystem/.../isg/NovaTokens.kt`, `NovaComponents.kt`.
- İlk bileşenler: metin, kart, beş durum tonu, primary/surface/muted/danger buton, loading/disabled davranışı. Callback dışarıdan verilir; bu bileşenler backend veya billing çağırmaz.
- SwiftUI Dynamic Type ve Compose fontScale açık. Sabit yükseklik yerine büyüyebilen buton/kart; durum yalnız renk ile aktarılmaz, metin/semantics korunur. iOS spinner Reduce Motion'a uyar. Native testler tam erişilebilirlik denetimi değildir.
- Yerel, sentetik bileşen galerisi/preview: gerçek firma/personel bilgisi, Auth veya telemetry içermez. Kullanıcıya açık route'a eklenmedi.

```text
Sabit uzman kaynak manifesti
  └─ nova_tokens.mjs
       ├─ Swift tokenları → SwiftUI bileşenleri → sentetik galeri
       ├─ Kotlin tokenları → Compose bileşenleri → sentetik galeri
       └─ Ortak değer corpus'u → Swift / Kotlin testleri
Font kaynak hash'leri → iki native resource paketi → font/paket kontrolleri
```

## Bilinçli farklar ve açık işler

Referanstaki beyaz/yeşil buton yazısı yaklaşık **2.01:1**, yeni koyu `#111111`/yeşil yazı **9.41:1** kontrast verir. Kaynak `onAccent` beyaz değeri değiştirilmeden saklandı; native primary bileşeni açıkça koyu yazı/ikon kullanır. Danger buton da beyaz/kırmızı dolgu yerine kaynak danger bg/ink çiftini kullanır. Bunlar kullanıcıya bildirilen/ayrıca görsel kabul gerektiren erişilebilirlik adaptasyonlarıdır; piksel eşitliği iddiası yok.

SwiftUI metin leading'i RN `lineHeight` ile tam aynı değildir; fontlar ölçeklenir, tracking/lineSpacing uygulanır ama referans metriklerin görsel eşitliği açık. Pill uzun metinde sarabilir. İkon seti henüz aktarılmadı; iOS galeride SF Symbol, Android galeride metin kullanıyor. Kart gölgesi platforma özgü; iOS yalnız yüzeye uygulanır. Primary gölge, press/ripple, tüm animasyonlar ve loader şekli henüz tam eşlenmedi. Bunlar tasarım değişikliği tamamlandı diye sunulmaz.

Tab bar/drawer ve hızlı işlem panelinin ilk bağımsız native dilimi daha sonra [uzman shell kaydında](P18_EXPERT_NATIVE_SHELL.md) eklendi. Form/input, arama, liste, şirket çalışma alanı, uygunsuzluk ve diğer domain ekranları açık. Canlı root'a bağlama, gerçek state/effect coordinator, kamera/klavye, VoiceOver/TalkBack, cihaz/emülatör üzerinde tüm eylemler ve kaynak OSGB ile aynı veri üzerinden screenshot-golden karşılaştırması **açık**. Kayıt envanterindeki263 domain kabul senaryosu bu görsel altyapı testleriyle tamamlanmış sayılmaz.

## Test kapsamı

| Kontrol | Yerel sonuç ve sınır |
|---|---|
| Tasarım Node suite | 8/8; deterministik üretim, değişim/başka rol, RGBA, font hash/registration/lisans, fixture input takibi, kontrast adaptasyonu, test izolasyon envanteri |
| Native Swift/CoreText | 128/128:80 renk+17 tipografi+26 ölçü+5 font PS/Türkçe glyph; macOS native yürütme, mobil UI testi değil |
| Android token JVM | 123/123 aynı değer corpus'u |
| Android Compose/Robolectric | 3/3; açık/koyu4variant×3state=24buton kombinasyonu, loading/disabled dokunmanın callback çağırmaması;320dp/2×fontScale galeride scroll ve tıklama. SDK33 host JVM, gerçek emülatör değil |
| iOS native render | Ayrı hostless XCTest hedefi;320/393/440 genişlik×light/dark×normal/AX3=12 ortak **içerik** render'ı; font kayıt ve boş/tek-renk görüntü reddi. Aynı iPhone17Pro/iOS26.5 simulator runtime'ı; üç cihaz veya pencere/scroll testi değil |
| Ana uygulamalar | iOS Debug simulator compile-only ve Android Debug APK build; canlı uygulama açılışı/yayını yok |
| Font paketleri | İki build ürünündeki toplam10 font binary SHA'sı kaynakla eşleşir |
| Önceki altyapı | Foundation111/111; identity PASS, altı transport function-map PASS |

CI'a Node tasarım suite, Swift font/token kontrolü ve ayrı iOS içerik render hedefi eklendi. Android mevcut tüm-modül unit test işi yeni designsystem testlerini kapsar. **Uzak CI çalıştırılmadı.** Ayrıntı ve son kaynak fingerprint'leri [kanıt dosyasında](evidence/P18_NATIVE_DESIGN_2026-09-12.json).

### Yakalanan test düzeneği sorunları

İlk ImageRenderer+ScrollView turu yalnız arka plan PNG'si üretti; boyut/dosya büyüklüğü kontrolü bunu yanlışlıkla geçirdi. Bu12PASS görsel kanıt sayılmadı. Boş görüntü reddi eklendikten sonra hostless UIWindow/drawHierarchy alternatifi de12FAIL verdi; gerçek UIApplication scene'i olmayan bu hedefte pencere testi iddia edilmez. Son düzenek aynı galeri içerik bileşenini kaydırma kabı olmadan render eder, boş sonuç reddini korur. Normal görseller açılıp incelendi; AX3 çıktılarında viewport altı kesilmesi tüm içeriğin görünür olduğu anlamına gelmez.

ProgressView'ın ImageRenderer çıktısında desteklenmeyen-view işareti görülünce saf SwiftUI/Reduce Motion uyumlu halka bileşenine geçildi; koyu tema ikon rengi ve çocuklara yayılan kart gölgesi de görüntü kontrolünde düzeltildi. Bu capture iyileştirmeleri hareket/etkileşim kabulünün yerine geçmez.

Android'in ayrı test modülü eski transitive Activity/Espresso/JUnit sürümlerini offline cache'de bulamadı. Projedeki mevcut katalog sürümleri debug/test scope'a açık bağlandı; yeni sürüm indirme/yükseltme yapılmadı. Bir yanlış katalog alias'ı derleme aşamasında yakalanıp kaldırıldı. Test kaynak corpus'u Gradle input olduğundan yalnız fixture değişmesi eski yeşil sonucu tekrar kullanamaz.

## Tekrarlama

```sh
node scripts/isg/nova_tokens.mjs --check
node scripts/isg/run_suite.mjs nova-design
swiftc App/DesignSystem/ISG/NovaTokens.swift scripts/isg/NovaTokenCheck.swift -o /tmp/isg-nova-check
/tmp/isg-nova-check contracts/isg/v1/design/nova-native-values.json App/Resources/Fonts
# android/ içinde; JDK17:
./gradlew :core:designsystem:testDebugUnitTest :app:assembleDebug --offline --console=plain
```

iOS render hedefi: `tests/isg/design-ios/ISGDesignTests.xcodeproj`, scheme `ISGDesignTests`, Debug, seçilmiş iPhone Simulator, signing kapalı. Test hedefi main app'i import/launch etmez ve servis/SDK paketi içermez. Testler yalnız kendi fontlarını process scope'a kaydeder.

SwiftUI becerisi bu dilimde iOS16 uyumlu yerel state, composable bileşenler, ölçeklenen fontlar ve servissiz preview yaklaşımını belirledi. [Apple custom relative font](https://developer.apple.com/documentation/swiftui/font/custom(_:size:relativeto:)) ve [Compose yerel font ailesi](https://developer.android.com/develop/ui/compose/text/fonts) referansları kontrol edildi.
