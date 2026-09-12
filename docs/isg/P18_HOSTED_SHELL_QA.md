# P18 — gerçek iOS pencere/etkileşim test katmanı

13 Eylül 2026 Türkiye saati (test kayıtlarında12 Eylül UTC). Önceki shell commit'i `c6e33fbe`. Bu dilim yeni uzman kabuğunu gerçek iOS Simulator uygulama penceresinde çalıştırır; önceki hostless ImageRenderer testinden farklıdır. **Asıl RiskDetected uygulaması veya gerçek domain servisleri çalıştırılmaz.**

## Ayrı test uygulaması

`tests/isg/shell-ios/ISGShellHarness.xcodeproj` iki hedef içerir:

- `ISGShellHarness`: `com.riskdetected.isgshellharness`; uygulamadaki aynı dört NOVA Swift dosyası ve beş yerel font, sentetik test içeriği.
- `ISGShellUITests`: XCTest UI test paketi; ayrı `com.riskdetected.isgshelluitests.xctrunner` çalıştırıcısı.

Yeni bir mağaza uygulaması veya yeniden markalanmış production binary değildir. Ana iOS `com.riskdetected.app` ve Android `com.riskdetectedan.app` kimlikleri korunur. Projede `SUPPORTED_PLATFORMS=iphonesimulator`, `SKIP_INSTALL=YES`, signing kapalı; host kaynak dosyası fiziksel cihaz hedefinde derlemeyi `#error` ile durdurur. Paket, production proje/SDK/Auth/Keychain/URL callback/DB veya kalıcı kullanıcı verisi içermez. iOS Simulator'ın genel ağını kapattığımız iddia edilmez; test uygulamasının kaynakları ağ işlemi yapmaz.

Proje XcodeGen2.45.4 ile `project.yml` dosyasından üretildi. Üretilmiş proje/scheme de kaydedilir; CI'da XcodeGen kurulumu gerekmez. Ana projenin build graph'ına test host'u eklenmedi. Node testleri kaynak allowlist'ini ve ayrı bundle kimliğini kontrol eder.

Host'taki sarı QA araçları sadece sentetik hesabı değiştirmek, izinleri kaldırmak ve eski callback'i yeniden teslim etmek içindir. Production kabuğuna eklenmez. Her hedefte gerçek SwiftUI içerik düğümü ve yerel sayaç vardır. UI testleri sadece `selected/current` durumunu değil, hedef içeriğinin varlığını ve dokunulabilirliğini de kontrol eder. Font adlarının runtime kaydı da her launch'ta zorunludur.

```text
Gerçek NOVA Swift kaynakları + sabit yerel fontlar
  └─ ayrı sentetik SwiftUI App/WindowGroup
       └─ NovaExpertShell
            ├─ gerçek TabView + her sekmede NavigationStack
            ├─ gerçek drawer / hızlı işlem overlay
            └─ hesap kapsamlı test içeriği + yerel sayaç
                 ↑
        XCUIApplication → gerçek tap/scroll/dismiss → görünen içerik kontrolü
                 ↓
         xcresult + tam pencere screenshot + kaynak/binary hash kanıtı
```

## Otomatik senaryolar

1. Sekme geçmişi korunumu, aynı sekmeye yeniden dokunmada köke dönüş; Ekle'nin mevcut sekmeyi değiştirmemesi; hızlı işlem seçimi ve geri dönüş.
2. 13 drawer ve4 hızlı işlem hedefinin açık temada gerçek dokunmayla açılması.
3. Aynı17 yönlendirmenin koyu temada çalışması; toplam34 menü yönlendirme varyasyonu.
4. Kapalı bildirim, Firmalar/Uygunsuzluk sekmeleri ve dört hızlı işlem seçeneğinin disabled olması.
5. Açık panel ve native ekran varken hesap reset: panel kapanır, kök değişir, yerel sayaç sıfırlanır. Eski epoch callback'i yeni hesabı başka ekrana götüremez.
6. Başlangıçta iki öğeli gerçek NavigationStack; Geri ile bir öğe çıkarma, izin kaldırılınca Ana Sayfa'ya dönme.
7. 320pt host genişliğinde AX3/koyu tema; uzun drawer kaydırması ve yatay sekme alanından Profil'e erişim. Bu ayrı320pt fiziksel cihaz değildir;402pt Simulator penceresinin içindeki daraltılmış host'tur.
8. iOS sekme/üst menü/kapat kontrollerinin gerçek UI frame'inde en az44pt olması; drawer dışındaki alana dokunarak kapatma.

## Bu dilimde yapılan düzeltmeler

- **Font kaydı:** Xcode build setting üzerinden verilen font dizisi ilk host Info.plist'ine girmedi. Explicit `HarnessInfo.plist` kullanıldı; beş `UIAppFonts` girdisi build ürününde ve `UIFont` runtime sorgusunda kontrol edilir. İlk sistem-fontlu ekran kabul kanıtı değildir.
- **Dokunma alanı:** SwiftUI plain Button'ın görünmeyen frame'i tek başına bütün alanı hit target yapmıyordu. İlk runtime ağacında kapat simgesi yaklaşık13pt, bazı sekme frame'leri44pt'den dardı. Etiketlere `contentShape(Rectangle())` ve sekmelere minimum44pt genişlik eklendi. Hostlu boyut testi bunu denetler.
- **Modal sınırı:** Alt bar safeAreaInset'ine açık `allowsHitTesting` ve `accessibilityHidden` gate eklendi. XCTest'te gizlenmiş yapısal öğeler `exists` sorgusunda kalabildiğinden, bu sorgu VoiceOver odak testi yerine kullanılmaz. Otomatik kabul `isHittable=false` ve doğru panel/rota davranışıdır; VoiceOver/TalkBack sırası hâlâ ayrıca açık.
- **Test hedefi seçimi:** Drawer ve yatay sekme scroll alanlarına sabit accessibility identifier eklendi. Kaydırma, rastgele ilk ScrollView yerine tam hedefe gider.
- **Android hedef boyutu:** Üst menü/bildirim/hesap/kapat kontrolleri48dp oldu.320dp Compose testinde tüm sekme ve ikon kontrolleri ile iki panelin kapat düğmesi en az48dp olarak denetlenir. İkon çizimi ile dokunma alanı aynı şey değildir.

## Test çalıştırıcısında yakalanan tutarsızlık

Yerel tekrar koşularından birinde üretilmiş `.xctestproducts` ve Simulator'a kurulu test binary'si yeni assertion metnini içerdiği hâlde çalışma kaydı eski assertion metnini verdi. Bu koşu güncel kaynak için güvenilir kabul edilmedi. Kesin kök neden kanıtlanmadı; işletim sistemi veya araç cache'i hakkında kesin hüküm yok.

Yalnız bu dilimin iki sentetik bundle'ı Simulator'dan kaldırılıp yeniden kuruldu; asıl uygulama ve gerçek veri silinmedi. Geçici test içerikleri yeniden üretilebilir. Temiz kurulum sonrasındaki yeni test envanteri ve sonuç bundle'ı ayrı kanıttır. Yerel source değişikliği sonrası tekrar için aynı dar test-bundle temizliği önerilir; Simulator erase veya production uninstall yapılmaz. CI yeni runner'da tek tam koşu çalıştırır.

## Kapsam dışı kalanlar

- Production session/actor/company adapter, veri/servis mutasyonları, ödeme, bildirim teslimi ve gerçek domain E2E.
- iOS16 minimum runtime, diğer iPhone/iPad boyutları ve native edge-swipe geri hareketi; mevcut koşu iPhone17Pro/iOS26.5 üzerinde.
- VoiceOver/TalkBack odak geçişi, klavye, tüm erişilebilirlik denetimi ve Android API26/33/37 emülatör shell UI testleri.
- Kaynak OSGB ekranıyla screenshot-golden/piksel eşitliği; orijinal ikon/animasyon/blur. Hızlı işlem panelinin referansla birebir kompakt yüksekliği de henüz kabul edilmedi.
- Tüm P18 veya263 domain kabul maddesinin tamamlanması. Bu UI testleri domain kabul maddelerini kendiliğinden PASS yapmaz.

## Doğrulanmış sonuçlar

| Kontrol | Sonuç |
|---|---|
| Gerçek iOS pencere testi |8/8 PASS,0 fail/skip;34 menü yönlendirmesi;9 tam pencere PNG'si |
| Native UI test süresi |Sonuç paketinde368,8 saniye; araç300 saniyede timeout verdi ancak Xcode tamamlandı, log ve xcresult summary ayrıca doğrulandı |
| Eski hostless iOS tasarım/regresyon |18/18 PASS; yeni pencere testleriyle karıştırılmadı |
| Android design system |210/210 PASS;9 shell,75 navigation,123 token,3 component; yeni48dp hedef testi dahil |
| Android lint / APK |Görevler PASS; NOVA dışı eski lint bulguları bu dilimde ele alınmadı |
| Node tasarım / foundation |12/12 ve111/111 PASS; teknik kimlik kontrolü PASS |
| Test binary/font tutarlılığı |Immutable test ürünleri ile kurulu host executable/debug dylib/test binary SHA'ları eşit;5 font kaynak hash'i eşit |

Koyu drawer, açık hızlı işlem ve AX3 Profil görselleri açılıp incelendi. Hızlı işlem paneli halen gereğinden yüksek; bu tasarım farkı kabul edilmiş sayılmadı. AX3 ekranında sekmeler gerçekten yatay kaydırılarak Profil'e erişildi; önceki hostless yalnız strip başını çizen görüntü bunun yerine kullanılmadı.

Test sonunda yalnız iki sentetik bundle kaldırıldı ve kaldırıldığı doğrulandı; test dosyaları ve sonuç paketleri yerelde duruyor, host yeniden derlenip kurulabilir. Simulator açık bırakıldı; asıl uygulama ve kullanıcı verileri korunur. Araç profili ana projeye geri alındı.

CI'a ayrı `ios-shell-integration` işi ve xcresult artifact'ı eklendi. PASS sayısı kaynakta tanımlı test sayısına eşit olmak zorunda; fail/skip kabul edilmez. Uzak CI koşusu **yapılmadı**. [Tarih/sources/binary ve runtime kanıtı](evidence/P18_HOSTED_SHELL_2026-09-13.json).

Teknik referanslar: [Apple XCUIApplication](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication), [launchArguments](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launcharguments), [isHittable](https://developer.apple.com/documentation/xcuiautomation/xcuielement/ishittable). Bir öğenin bulunması, görünür/dokunulabilir veya VoiceOver odak sırasının doğru olduğu anlamına gelmez.
