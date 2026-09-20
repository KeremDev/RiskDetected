# NOVA hareket ve dokunma geri bildirimi denetimi — 20 Eylül 2026

Emil Kowalski animasyon skill'leri (`animate`, `review-animations`,
`improve-animations`, `find-animation-opportunities`) ve `apple-design`,
`write-swift`, `mobile-native` skill'lerinin NOVA'nın tamamına uygulanması.
Kapsam yalnız onboarding değil; paylaşılan tasarım sistemi, uzman kabuğu, tüm
modül ekranları, onboarding ve giriş ekranı.

Commit'ler: `022b4fe4`, `18dbb466`, `0835701d`
(branch `codex/isg-transition-foundation`).

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

## Bilerek yapılmayanlar

- **Merkezî popup'ın aşağıdan kayması.** `NovaPopup` `fullScreenCover` ile
  sunuluyor; iOS bunu alttan yukarı kaydırır, oysa kart ekranın ortasında.
  Mekânsal tutarlılık açısından kart tetikleyiciden büyümeli. Ama bunu düzeltmek
  sunum animasyonunu binding üzerinden bastırıp çıkış animasyonunu elle
  yönetmeyi gerektirir; NOVA'daki her form bu yoldan açılıyor ve `dismiss()`
  çağrıları her yere dağılmış durumda. Risk/kazanç oranı kötü, ayrıca alttan
  kayma iOS'un tanıdık davranışı. Ayrı bir iş olarak bırakıldı.
- **Yükleniyor → içerik cross-fade'i.** 13 ekranın her biri
  `if error / else if loading / else content` yapısını kendi içinde kuruyor;
  paylaşılan bir sarmalayıcı yok. Doğru çözüm önce bir `NovaAsyncContent`
  primitifi yazmak — bu bir hareket işi değil, yapısal refactor.
- **Liste satırlarına kademeli giriş (stagger).** Skill 30–80 ms stagger önerir
  ama yalnız *nadir* görülen grup girişleri için. NOVA listeleri her sahne
  etkinleştiğinde yenileniyor; burada stagger, kullanıcının okumaya çalıştığı
  veriyi süs için oynatmak olurdu. Reddedildi.
- **Eşzamanlı oturumun dosyaları.** `NovaModuleTracking`, `NovaFollowupScreen`,
  `NovaFileSourceLinks`, `NovaPilotMainGate`, `NovaCompanyManagementGate` başka
  bir oturum tarafından değiştirilmiş durumda; hiçbirine dokunulmadı. Bu beş
  dosyada toplam ~40 kontrol hâlâ geri bildirimsiz — o oturum bittiğinde aynı
  iki satırlık değişiklikle kapatılabilir.

## Doğrulama

| Kontrol | Sonuç |
| --- | --- |
| `xcodebuild` Debug (simülatör, pilot bayrağı olmadan) | SUCCEEDED |
| `xcodebuild` Debug + `NOVA_PILOT_BUILD` | SUCCEEDED |
| Simülatörde onboarding intro 1–3 + sosyal kanıt | render doğru, yerleşim bozulmadı |
| Soru ekranı 6/11 (3'lü sektör ızgarası), seçim | seçim geçişi ve kart yerleşimi doğru |
| Giriş ekranı | render doğru |
| Deneme (trial) ekranı | render doğru |
| Eşzamanlı oturum dosyası commit'e girdi mi | hayır, doğrulandı |

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
