# P18 — uzman paneli native gezinme dilimi

12 Eylül 2026. OSGBTakip uzman panelinin üst menü, alt sekmeler, çekmece ve hızlı işlem yapısı iOS/Android için taşındı. **Bu bir sunum ve gezinme katmanıdır; yeni domain ekranları veya tüm geçiş tamamlanmış değildir.** Mevcut uygulama kökü bu kabuğa bağlanmadı. Preview içeriği açıkça sentetiktir; canlı kayıt gibi gösterilmez.

## Yapı ve bağımlılıklar

| Katman | iOS | Android | Bağımlılık |
|---|---|---|---|
| Rota/kural durumu | `NovaNavigation.swift` | `NovaNavigation.kt` | Foundation / Kotlin; ağ veya SDK yok |
| Native kabuk | `NovaExpertShell.swift` | `NovaExpertShell.kt` | NOVA bileşen/token/font; SwiftUI / Compose + Activity BackHandler |
| İçerik sahibi | `Binding<NovaNavigationState>` ve content closure | Son state ve `(event, epoch)` callback, content lambda | Gerçek session/capability/domain adapter henüz bağlanmadı |
| Ortak kayıt | `contracts/isg/v1/design/nova-navigation.json` | Aynı dosya | 4 sekme,17 hedef,13 drawer satırı,4 hızlı işlem |
| Ortak test | `NovaNavigationCheck.swift` | `NovaNavigationTest.kt` | `fixtures/nova-navigation.json`;75 senaryo,185 geçiş |

Android Activity Compose mevcut katalog sürümüyle runtime dependency oldu; daha önce yalnız debug bağımlılığıydı. Sürüm yükseltilmedi. Uygulama bundle/package ID'leri, callback, entitlement, mağaza ürünleri ve eski root ekranları aynı kaldı. OSGBTakip klasörüne yazılmadı.

```text
Gelecekteki güvenilir hesap/session sahibi (henüz bağlanmadı)
  ├─ benzersiz epoch + kullanılabilir hedefler → NovaNavigationState
  └─ gerçek, hesap kapsamlı content(destination) → native ekran

Üst menü / sekme / drawer / hızlı işlem / geri
  └─ event + ekranda yakalanmış epoch
       └─ EN GÜNCEL state.apply(event, epoch)
            ├─ eski epoch → hiçbir değişiklik yok
            ├─ kapalı hedef/kapalı ana sekme → hiçbir değişiklik yok
            └─ kabul → selected + sekmeye ait path + tek overlay
                         └─ native kabuk yeniden çizilir

Hesap değişimi → yeni epoch → tüm path/overlay/yerel child state sıfırlanır
Kullanılabilirlik değişimi → overlay kapanır → geçersiz path ve altları atılır
```

`available` **sunucu yetkilendirmesi değildir**. Auth/session ve veritabanı RLS/RPC denetimlerinin yerine geçmez. Mevcut UI izinlerinden paid hak, rol veya şirket sahipliği türetilmez. `resetAccount` güvenilir host çağrısıdır; harici URL veya kullanıcı alanından epoch üretilmez. Swift state güncel Binding üzerinde değiştirilir; Compose host'u `state = state.apply(event, epoch)` yapmalıdır. Eski callback'in yakaladığı bütün state'i geri atamak yasaktır.

## Gezinme kuralları

- Dört sekme: Ana Sayfa, Uygunsuzluk, Firmalar, Profil. Ortadaki **Ekle bir sekme değildir**; mevcut sekme ve geçmiş korunarak hızlı işlem açılır.
- Drawer: Ana Sayfa, Yeni Uygunsuzluk, Uygunsuzluklar, Firmalar, İşletme Hafızası, Evrak Takibi, Diğer Dosyalar, Ziyaretler, İstatistikler, Eğitim ve Takip, Rapor Oluştur, Rapor Arşivi, Bildirim Merkezi.
- Hızlı işlem: Yeni Uygunsuzluk, Dosya Ekle, Ziyaret Ekle, Eğitim Ekle. Bu hedef kimlikleri gerçek form/işlem değildir. Kaynakta dosya/ziyaret mevcut listeye yönlenebiliyor; yeni form/liste seçimi domain adapter aşamasında açıkça eşlenecek.
- `newFinding` Uygunsuzluk sekmesine; diğer yardımcı hedefler Ana Sayfa geçmişine aittir. Şirket/kayıt ID'si veya detay modeli henüz rota tipine eklenmedi.
- Sekmelerin geçmişi ayrıdır. Başka sekmeye geçip dönünce korunur. Aynı sekmeye yeniden dokunmak yalnız o sekmenin köküne döner. Aynı üst hedefe tekrar gitmek path'e kopya eklemez.
- Tek `overlay` vardır: drawer veya quickAdd. Bir panel diğerini değiştirir; üst üste iki panel oluşmaz. Geri önce paneli kapatır, sonra path'ten bir öğe çıkarır, sonra Ana Sayfa'ya döner. Android kökte sistem geri davranışını tüketmez.
- `home` ve `profile` sunum kökleri daima mevcuttur. Diğer hedefler açıkça izin listesinde olmalıdır; alt hedef tek başına yeterli değildir, bağlı sekmenin kökü de açık olmalıdır. Kullanılamayan menü satırı açıklamalı ve disabled; bildirim düğmesi de aynı gate'e bağlıdır.
- Kullanılabilirlik kaldırılınca bir path'teki ilk geçersiz öğe ve tüm ardılları atılır; seçili sekmenin kökü kapanırsa Ana Sayfa'ya dönülür. Eski epoch'tan gelen availability güncellemesi yok sayılır.
- iOS NavigationStack binding'i yalnız mevcut path'in bir prefix'ine geri dönmeyi kabul eder. Yeni rota ekleme, sıra değiştirme, başka sekmenin path'ini değiştirme ve stale callback reddedilir.
- Yeni epoch tüm sekme geçmişlerini ve paneli sıfırlar. Swift `.id(epoch)`, Compose `key(epoch)` child yerel state'i ayırır. Aynı epoch ile reset çağrısı no-op; bilinçli yenileme ayrı availability güncellemesidir.

## Tasarım ve erişilebilirlik uyarlamaları

Mevcut NOVA token/fontları kullanılır. Menü/bildirim/hesap düğmeleri44 birim, satırlar en az48, alt bar en az66; küçük kaynaktaki42 birim kontroller genişletildi. Bu Android için tüm48dp hedeflerin kabul edildiği anlamına gelmez; ikon kontrollerini48dp'ye uyarlama ayrıca açık. Sistem ikonları geçici eşlemedir; orijinal ikon seti, animasyon, ripple/gölge, avatar gradient ve blur tam eşit değildir. Android bar şimdilik opak yüzeydir; iOS Material kullanır ve Reduce Transparency için opak alternatifi vardır.

Görüntü incelemesi320pt normal yazıda uzun sekme adının bölündüğünü ve AX3'te başlığın sıkıştığını yakaladı. Normal iOS sekme etiketi tek satır ve en fazla%25 küçültme kullanır. Erişilebilirlik boyutlarında iOS, Android'de fontScale≥1.5 iken üst başlık ayrı satıra geçer; avatar harfleri yerine kişi simgesi gösterilir. Sekmeler metni küçültmeden yatay kaydırılır, seçili sekme görünür alana alınır. Bu onaylı referanstan bilinçli erişilebilirlik farkıdır; nihai görsel kabul açık.

iOS modal arkasındaki içerik hit-test ve accessibility ağacından çıkarılır, escape kapatır. Android native Dialog dismiss/back kullanır. Kapat kontrolü uzun menünün scroll alanı dışındadır. Tam VoiceOver/TalkBack odak sırası, klavye, dış tıklama ve erişilebilirlik denetimi henüz kabul edilmedi.

## Çalıştırılmış testler ve sınırları

| Kontrol | Sonuç |
|---|---|
| Ortak Swift durum corpus'u |75/75 senaryo;185 adım;17 hedef×açık/kapalı×fresh/stale=68 matris +7 çok adımlı senaryo; rota/başlık/sıra katalog eşlemesi |
| Aynı Kotlin corpus'u |75/75 ayrı JUnit;aynı185 beklenen state; Swift reducer'dan üretilmiş oracle değil |
| Android Compose shell |8/8 Robolectric SDK33;13 drawer+4 hızlı hedefin her iki temada tıklanması=34 yönlendirme; sekme geçmişi/geri, panel, kapalı alan, hesap reset,320dp/2×fontScale menü ve yatay sekme scroll |
| Android design system toplam |209/209:123 token+75 navigation+3 eski bileşen+8 shell;0 fail/error/skip |
| iOS Simulator XCTest toplam |18/18;12 eski galeri testi+4 shell durum testi+2 render grubu. Render grupları8 normal header/tab görüntüsü ve2 AX3 header/strip içerik görüntüsü üretir |
| Node tasarım suite |10/10; ek katalog kapsamı, corpus input takibi ve servissiz shell/hostless hedef kontrolleri |
| Mevcut foundation |111/111; teknik kimlik doğrulaması PASS |
| Ana uygulamalar |iOS Debug/no-signing compile-only ve Android Debug APK build PASS; canlı uygulama/hesap açılmadı |

Android design system lint görevi PASS; NOVA dosyalarında bulgu yok. Diğer mevcut tasarım/resource dosyalarındaki lint bulguları değişmedi ve bu dilimde düzeltilmedi; PASS sıfır uyarı iddiası değildir.

iOS ImageRenderer **pencere, NavigationStack, modal veya yatay scroll etkileşimini test etmez**. Normal header/bar saf içerik olarak çizilir. AX3 testinde aynı genişleyen strip'in yalnız baş kısmı sabit çerçevede çizilir; devamı kesiktir, bu tüm sekmelerin ekranda görüldüğü iddiası değildir. Yatay scroll/auto-reveal iOS hostlu UI testinde açık; Android'de Compose etkileşimiyle denendi. Boş görüntü reddi korunur. Görseller screenshot-golden veya tam OSGB piksel karşılaştırması değildir.

İlk yeni iOS harness derlemesi read-only `accessibilityReduceTransparency` environment değerini yazmaya çalıştığı için durdu; testteki geçersiz override kaldırıldı. Sistem ayarı değiştirilmedi. İlk başarılı render'ın sıkışık yazısı gözle görülerek düzeltildi; nihai kanıt ayrı result bundle'a bağlıdır.

CI'a Swift ortak gezinme koşusu eklendi. Android Gradle fixture dosyasını ayrıca task input olarak izler; yalnız JSON değişiminde eski yeşil test önbelleği kullanılamaz. Mevcut iOS hostless işi yeni kaynak/testleri içerir. Uzak CI **çalıştırılmadı**.

## Devam sırası / henüz bağlanmayacak noktalar

1. Ayrı sentetik host ile iOS NavigationStack, gerçek TabView seçimi, panel dismiss/focus ve AX yatay bar etkileşimi; Android API26/33/37 emülatör UI kapsamı.
2. P02 session/actor/company scope sahibi ile epoch/availability adapter; domain router'a şirket/kayıt kimlikleri, güvenli deeplink ve typed payload ekleme.
3. Şirket/uygunsuzluk/form/liste/search/boş/yükleniyor/hata/offline görünümleri ve gerçek domain state/effect sözleşmeleri. Eksik handler demo metniyle üretime açılmayacak.
4. P12 bildirim ve presentation önceliği, P14 abonelik/paywall, P13 offline coordinator'ın tek root sahibiyle bağlanması; yeni overlay bu sistemlerin izin mekanizması değildir.
5. TR/EN, son ikon/animasyon/blur, kaynak ile aynı sentetik veri üzerinden görsel karşılaştırma, ekran okuyucu testi ve kontrollü rollout/fallback.

263 domain kabul maddesinin durumu bu testlerle otomatik PASS yapılmadı. Production migration, push, deploy, mağaza yazımı ve eski veri/UI kökü değişimi yok. Bu dilim P18'i veya tüm planı kapatmaz.

## Tekrarlama

```sh
swiftc App/DesignSystem/ISG/NovaNavigation.swift scripts/isg/NovaNavigationCheck.swift -o /tmp/isg-nova-navigation-check
/tmp/isg-nova-navigation-check contracts/isg/v1
node scripts/isg/run_suite.mjs nova-design
node scripts/isg/run_suite.mjs foundation
# android/ içinde, JDK17 ile:
./gradlew :core:designsystem:testDebugUnitTest :app:assembleDebug --offline --console=plain
```

iOS hedef: `tests/isg/design-ios/ISGDesignTests.xcodeproj`, scheme `ISGDesignTests`; mevcut seçili iPhone Simulator, signing kapalı. Kaynak/runtime hash'leri [kanıt dosyasında](evidence/P18_EXPERT_SHELL_2026-09-12.json).
