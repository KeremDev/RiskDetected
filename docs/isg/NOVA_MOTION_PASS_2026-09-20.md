# NOVA hareket ve dokunma geri bildirimi denetimi — 20 Eylül 2026

Emil Kowalski animasyon skill'leri (`animate`, `review-animations`,
`improve-animations`, `find-animation-opportunities`) ve `apple-design`,
`write-swift`, `mobile-native` skill'lerinin NOVA'nın tamamına uygulanması.
Kapsam yalnız onboarding değil; paylaşılan tasarım sistemi, uzman kabuğu, tüm
modül ekranları, onboarding ve giriş ekranı.

Commit'ler: `022b4fe4`, `18dbb466`, `0835701d`, `01235fc3`, `31b3e62e`,
`f40c2ae2` (branch `codex/isg-transition-foundation`).

**21 Eylül eki:** ilk turda gerekçeli olarak ertelenen dört maddenin dördü de
yapıldı. Aşağıdaki "Bilerek yapılmayanlar" bölümü, her maddenin nasıl
çözüldüğüyle birlikte güncellendi.

## Başlangıç durumu

NOVA yüzeyinde ~100 ekran vardı ve hareket dağarcığı neredeyse yoktu:

| Ölçüm | Değer |
| --- | --- |
| `withAnimation` / `.animation(` / `.transition(` toplam | 33 |
| Basma (press) geri bildirimi olan kontrol | 0 |
| `.buttonStyle(.plain)` — yani hiçbir geri bildirimi olmayan kontrol | 188 |
| Elle yazılmış, birbirine yakın ama aynı olmayan eğri | 6 |
| Hareket token'ı barındıran dosya | yok |

Bu sayıların anlamı: kullanıcı bir satıra dokunduğunda ekran değişene kadar
uygulama hiçbir şey söylemiyordu. Yavaş bağlantıda bu, "dokunuşum gitti mi?"
sorusuna cevapsız kalmak demek.

İyi haber: `.easeIn` hiçbir yerde yoktu (skill'lerin otomatik bulgusu), süreler
zaten 300 ms altındaydı ve `NovaTokens` tipografisi boyuta göre tracking
kullanıyordu (`screenTitle -0.5`, `body 0.0`, `overline +0.5`) — `apple-design`
§15'in istediği şey zaten yapılmıştı. Kabuğun sekme çubuğu da
`matchedGeometryEffect` + seçim haptiği + Reduce Motion ile zaten doğruydu.

## Yapılanlar

### 1. Tek hareket ölçeği — `App/DesignSystem/ISG/NovaMotion.swift` (yeni)

`NovaTokens.swift` üretilmiş bir dosya ("elle düzenlemeyin"), renk/tip/ölçü
taşıyor. Hareket bu yüzden ayrı bir dosyada isimlendirildi:

- **Süre bütçeleri**: `press .16` · `popover .18` · `dropdown .22` ·
  `progress .28` · `modal .32` · `reduced .12`.
- **Eğriler**: güçlü `easeOut` (`cubic-bezier(.23, 1, .32, 1)`), güçlü
  `easeInOut` (`.77, 0, .175, 1`), iOS `drawer` eğrisi (`.32, .72, 0, 1`).
  SwiftUI'nin yerleşik `.easeOut`'u bu sürelerde kasıtlı görünmeyecek kadar
  zayıf.
- **Yaylar**: `move` (response .4 / damping 1.0), `press` (.22 / 1.0),
  `momentum` (.34 / 0.8), `sheet` (.3 / 0.8), `celebrate` (.35 / 0.72).
  SwiftUI'nin response+dampingFraction ikilisi Apple'ın kendi iki parametreli
  modeliyle aynı olduğu için bunlar yaklaşık değil, birebir değerler.
  Sıçrama (damping < 1) yalnız hareketin gerçekten "fırlatıldığı" yerde.
- **Reduce Motion**: `gated()` yer değiştirmeyi düşürüp kısa bir cross-fade
  bırakır, `stopped()` anlamlı azaltılmış hali olmayan sonsuz döngüleri
  tamamen durdurur. Skill'in kuralı: "daha az ve daha yumuşak, sıfır değil."
- **`NovaHaptics`**: `selection` / `impact` / `success` / `warning` / `failure`.
  Haptik ancak nadir kaldığı sürece işe yarar; her dokunuşta titreyen bir
  uygulama kullanıcıya hepsini yok saymayı öğretir.

### 2. Basma geri bildirimi — sistemin tamamı

İki paylaşılan stil:

- `NovaPressStyle` — 0.97'ye küçülür + %85 opaklık. Küçük kontroller: butonlar,
  44 pt ikon hedefleri, çipler.
- `NovaRowPressStyle` — yalnız sönükleşir, küçülmez. Satır ve kartlar: bir liste
  satırını küçültmek onu komşularından koparır.

İkisi de Reduce Motion'da ölçeklemeyi bırakır, opaklığı korur. Uygulandığı yer:

| Yüzey | Kontrol sayısı |
| --- | --- |
| Uzman kabuğu (üst bar, çekmece, hızlı ekle, bildirimler, ana sayfa kartları) | 21 |
| Paylaşılan primitifler (`NovaButton`, `NovaBackButton`, `NovaCompactActionButton`, `NovaListStat`, popup kapatma) | 5 |
| Onboarding + giriş ekranı buton primitifleri ve seçim kartları | 26 |
| Kalan 50 NOVA modül ekranı | 167 |

Toplam **219 kontrol**. Kabuğun kendi `NovaGlassPressStyle`'ı ve popup kapatma
butonunun kendi yayı token'lara devredildi.

**Scroll koruması.** Scroll'a dönüşen bir dokunuş birkaç kare içinde basılıp
iptal edilir. İlk karede sönükleşmek, her kaydırmada parmağın başladığı satırı
yakıp söndürürdü. `NovaRowPressStyle` bu yüzden sönükleşmeyi 50 ms geciktiriyor —
UIKit tablolarındaki `delaysContentTouches` davranışının aynısı. Kasıtlı bir
basış bu süreyi aşar ve yine anında hissedilir; bırakma hiç geciktirilmez.

### 3. Işınlanan durum değişimleri

- **Filtre paneli** (`NovaFilterField`): açılır panel tek karede belirip altındaki
  satırları zıplatıyordu. Artık ait olduğu butondan büyüyor, aynı yoldan
  kapanıyor (`scale .97 anchor: .top` + opaklık, 220 ms).
- **Çekmece grupları** (`NovaExpertShell`): chevron zaten dönüyordu ama satırlar
  tek karede beliriyordu. Aynı ilkeyle başlığın içinden açılıyor.
- **Başarı katmanı** (`NovaSuccessOverlay`): yay ile geliyor, 2,5 sn sonra tek
  karede yok oluyordu. Artık geldiği gibi gidiyor (180 ms) ve görselle **aynı
  karede** başarı haptiği veriyor — `await`'ten önce, skill'in "harmony" kuralı.
- **Bölüm sekmeleri** (`NovaFolderTabs`): seçili sekme yalnız VoiceOver için
  işaretliydi, ekranda hepsi birebir aynı görünüyordu — "hangisindeyim?"
  sorusunun cevabı yoktu. `NovaListStat`'ın kullandığı çerçeve + seçim haptiği
  eklendi.

### 4. Haptik — hak eden dört an

| An | Haptik |
| --- | --- |
| Onboarding'de bir cevap seçmek | selection |
| Bölüm sekmesi değiştirmek | selection |
| Doğrulama kodunun kabul edilmesi | success |
| Bir kaydın kaydedilmesi (başarı katmanı) | success |
| Giriş / kayıt / OTP hatası, geçersiz e-posta, kısa parola | failure |

Kasıtlı olarak **eklenmeyen** yer: birincil butona basmak. Her dokunuşa haptik
koymak, gerçekten önemli olanların fark edilmemesine yol açar.

### 5. Onboarding eğrileri — bilerek dokunulmadı

Onboarding ve giriş ekranı `İSGADA Onboarding.dc.html` / `İSGADA Giriş.dc.html`
handoff'undan birebir çıkarıldı. Oradaki `timingCurve` değerleri prototipin
kendi değerleri; token'a çevirmek kullanıcının onayladığı hissi değiştirirdi.
Bu yüzden yerinde bırakıldı.

Tek istisna: prototipte olup portta eksik kalan seçim geçişi. Handoff
`transition: background 140ms ease, border-color 140ms ease` diyor, SwiftUI portu
ikisini de tek karede çeviriyordu. Geri kondu.

## İlk turda ertelenip sonra yapılanlar

### Merkezî popup'ın aşağıdan kayması — `01235fc3`

`fullScreenCover` sunum olarak kalıyor; klavye, odak ve kapanma semantiğini
tutan o, yerine hiyerarşi içi bir overlay koymak hepsini elle yeniden yazmak
demek. Ama tek bir geçişi var ve tüm cover'ı alt kenardan yukarı kaydırıyor.
Ekranın ortasındaki bir kart için bu yanlış yol; üstelik blur ve kararmayı da
beraberinde sürüklüyor, yani arka plan kartın arkasına yerleşmek yerine
hareketli bir panel gibi geliyordu.

Çözüm: cover'ın kendi kayması bastırılıyor — sunum binding'i
`disablesAnimations` açık bir transaction içinde yazılıyor — ve kart kendi
hareketini yapıyor. Arka plan sönümleniyor, kart 0.94'ten ölçekleniyor (240 ms).
Çıkışta kapanma isteği, kartın geldiği yoldan gitmesi için çıkış süresi kadar
(160 ms) tutuluyor, sonra cover sökülüyor. Üst üste gelen kapanma istekleri
(X'e iki kez basmak, formun kendini kapatırken kullanıcının da X'e dokunması)
ilkinde birleşiyor.

`novaPopup` bunu kendiliğinden alıyor. Doğrudan `NovaPopup` render eden **30
cover** `novaPopupCover`'a taşındı; tam sayfa, kamera ya da koşullu içerik sunan
24 cover kaydırmayı koruyor — bir sayfa gerçekten aşağıdan gelir.

Başka bir yolla sunulan bir `NovaPopup` yine normal render ediliyor: ortam
değişkeni varsayılan olarak görünür, yani kart ilk kareden itibaren ekranda.

### Yükleniyor → içerik geçişi — `31b3e62e`

Faz enum'u yerine her sayfanın zaten daldığı bayrağı alan bir
`novaAsyncContent(isLoading:)` yazıldı; böylece ekranlar mevcut yapılarını
koruyup yalnız geçişi kazandı. **14 dal noktasına** uygulandı (analiz listesi ve
raporlar, istatistikler, analiz detayı, çalışma alanı dizin/personel/atama/
eğitim ekranları, parity editörleri) ve paylaşılan `NovaPilotMainGate`'te 5
noktaya daha.

### Liste satırlarına kademeli giriş — `31b3e62e`

İlk turdaki itiraz hâlâ geçerli: her çekmede, her kayıtta ve arka plandan her
dönüşte yenilenen bir listeyi tekrar tekrar dağıtmak, kullanıcının okumaya
geldiği veriyi süs için oynatmak olur. Bu yüzden giriş **iki kez** kapılandı:

- `novaListEntrance` ekran açıldıktan sonraki **ilk** kayıt grubunda bir pencere
  açar ve 600 ms sonra kapatır. Sonraki her yenileme hareketsiz.
- Pencere zamanla kapandığı için `LazyVStack` scroll ederken satırları
  canlandırmıyor — kullanıcı bir yere kaydırdığında satırlar zaten oradadır.
- Yalnız ilk 8 satır, 45 ms arayla. Reduce Motion sönümlemeyi koruyup yükselmeyi
  düşürür.

Analiz listesi, rapor listesi, çalışma alanı dizini ve personel ekranına
uygulandı.

### Eşzamanlı oturumun beş dosyası — `f40c2ae2`

`NovaFileSourceLinks`, `NovaModuleTracking`, `NovaFollowupScreen`,
`NovaPilotMainGate`, `NovaCompanyManagementGate`. **36 kontrol** basma geri
bildirimi aldı, NovaPopup sunan **5 cover** `novaPopupCover`'a taşındı.

Commit, çalışma ağacından değil **HEAD'den yeniden üretilerek** hazırlandı ve
yalnız iki kural uygulandı: `.buttonStyle(.plain)` → paylaşılan satır stili, ve
içeriği `NovaPopup` ile başlayan cover → `novaPopupCover`. Diff'te başka tek
satır yok; diğer oturumun yarım işi commit'e girmedi (doğrulandı).

O dosyaların yükleniyor/içerik geçişleri de çalışma ağacında duruyor ama
commit'e alınmadı: yerleşimleri şu anda yeniden yazdıkları yapıya dayanıyor,
artık eşleşmeyen bir HEAD'e sabitlemek doğru olmazdı. O oturum bitince kendi
commit'leriyle birlikte gelir.

## Hâlâ yapılmayanlar

- **`NovaPilotMainGate`'in kök dal noktası** (çalışma alanı kökü ↔ yükleniyor).
  Geçiş uygulanmadı: diğer oturumun o anda en yoğun çalıştığı yer ve ayak izini
  küçük tutmak daha akıllıca.
- **Basma hissinin cihazda doğrulanması** — aşağıya bakın.

## Doğrulama

| Kontrol | Sonuç |
| --- | --- |
| `xcodebuild` Debug (simülatör, pilot bayrağı olmadan) | SUCCEEDED |
| `xcodebuild` Debug + `NOVA_PILOT_BUILD` | SUCCEEDED |
| Simülatörde onboarding intro 1–3 + sosyal kanıt | render doğru, yerleşim bozulmadı |
| Soru ekranı 6/11 (3'lü sektör ızgarası), seçim | seçim geçişi ve kart yerleşimi doğru |
| Giriş ekranı | render doğru |
| Deneme (trial) ekranı | render doğru |
| Eşzamanlı oturum dosyası commit'e girdi mi | hayır, diff satır satır doğrulandı |
| `xcodebuild` + `NOVA_PILOT_BUILD` (popup + yükleniyor + giriş turu) | SUCCEEDED |
| Simülatörde gerçek NovaPopup: açılış, X ile kapanış, yeniden açılış | üçü de doğru |
| Analiz listesi (kademeli giriş açık) | satırlar tam opaklıkta, takılı kalan yok |
| Risk değerlendirmesi listesi | render doğru |

Derlemeler ana çalışma ağacı yerine ayrı bir `git worktree` üzerinde alındı;
ana ağaçta eşzamanlı oturumun yarım bıraktığı dosyalar var.

**Elde denenmesi gereken:** basma hissi statik ekran görüntüsünden
değerlendirilemez. Cihazda bakılacak iki şey — (1) uzun bir listede hızlı
kaydırırken satırların yanıp sönmediği, (2) 50 ms'lik gecikmenin kasıtlı bir
basışta fark edilmediği. Gerekirse `NovaRowPressStyle.pressDelay` tek yerden
ayarlanır.

## Kullanım

Yeni bir NOVA ekranı yazarken:

```swift
// Buton, ikon hedefi, çip
.buttonStyle(NovaPressStyle())

// Satır, kart, liste öğesi
.buttonStyle(NovaRowPressStyle())

// Yer değiştiren/ölçeklenen bir animasyon
.animation(NovaMotion.gated(NovaMotion.easeOut(), reduceMotion: reduceMotion), value: x)

// Kaydedildi / hata
NovaHaptics.success()
NovaHaptics.failure()
```

Yeni bir eğri veya süre elle yazmak gerekiyorsa, önce `NovaMotion`'a isimli bir
değer olarak eklenir. Yedinci el yazması `timingCurve` bir hata olarak sayılır.
