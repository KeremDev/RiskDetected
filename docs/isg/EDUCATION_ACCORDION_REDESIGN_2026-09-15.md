# Eğitim ekleme sayfası: popup'tan akordion sayfaya

Tarih: 2026-09-15 · Dal: `codex/isg-transition-foundation`

## İstek

"Eğitim ekleme sayfası çok karışık oldu... popup kısmında çıkartalım yeni bir
sayfa olarak tasarlayalım... akordion sistemiyle... yukarısında tamamlanmayı
takip eden progress bar... kartların bazılarında ciddi fazla bilgi varsa
popup kullanabiliriz." Referans: Elle Uygunsuzluk sayfası
(`NovaManualNonconformityScreen.swift`).

## Ne yapıldı

`App/DesignSystem/ISG/NovaEducationEditor.swift` (başka bir eşzamanlı
oturumun bu hafta eklediği, henüz commit'lenmemiş dosya) baştan yazıldı.
Yazma/servis mantığına **hiç dokunulmadı** — `initialize`, `save`, `retry`,
`saveCurriculum`, `loadPeople`, `add`, `refreshRecord` fonksiyonları birebir
aynı; değişen yalnız görünüm katmanı.

**Öncesi:** `NovaPopup` içinde tek bir uzun `ScrollView`, `GroupBox`/`Label`/
`Text`/`.bold()`/`.tint()` ile (Nova tasarım bileşenleri kullanılmıyordu):
başlık/düzenleyici/not alanları, eğiticiler listesi, kapsamlar listesi (her
kapsam `NovaEducationScopeEditor`'ün TÜM içeriğiyle — konular, dersler,
katılımcılar, müfredat — satır içinde açık), kapsam ekleme menüsü, sertifika
bölümü — hepsi tek sayfada üst üste.

**Sonrası:** Elle Uygunsuzluk'un aynı deseni:

- Sayfa artık `NovaPageSurface` + `NovaBackButton` ile tam sayfa; çağıran
  taraf (`NovaTrainingScreens.swift`) artık `NovaPopup` sarmıyor.
- `NovaEducationStep` (info/trainers/scopes) — `NovaEducationModels.swift`'e
  eklendi, `NovaManualStep`'in birebir aynı deseniyle: `isComplete`,
  `completedCount`, `progress`, `nextIncomplete(after:)`.
- Üstte aynı ilerleme çubuğu (`GeometryReader` + `Capsule`), `NovaCompanyAccordion`
  ile üç adım, her biten adım bir sonrakini öneriyor ("Sıradaki: …").
- **Kapsamlar adımı**: her kapsam artık kompakt bir özet kart (firma ·
  işyeri · görev · katılımcı sayısı · dakika) + "Düzenle" düğmesi. Konular/
  dersler/katılımcılar/müfredat gibi ağır içerik artık **kendi popup'ında**
  açılıyor (`NovaEducationScopeEditor`'ün kendisi değişmedi — yalnız nerede
  ve nasıl açıldığı değişti). Yeni eklenen bir kapsam otomatik olarak bu
  popup'ı açıyor, boş kart bırakmıyor.
- Ön-katalog (legacy, basit) akış — `NovaTrainingSessionEditor` — kapsam
  dışında bırakıldı; kendi küçük kart görünümünde kaldı, hâlâ `NovaPopup`
  içinde.

38 yeni katalog anahtarı eklendi (tr + en, `isg_education_editor` comment'i
ile).

## Doğrulama

| Ne | Sonuç |
|---|---|
| `scripts/isg/nova_education_accordion.test.mjs` (yeni) | **8/8 geçti** |
| `swift -frontend -parse` (değiştirilen 3 dosya) | sözdizimi hatasız |
| `nova_localization.test.mjs` | aynı 2 önceden var olan kırmızı (drawer anahtarları + ilgisiz 3 ham literal) — benim dosyam sıfır katkı |
| Tam Xcode derlemesi | **YAPILAMADI** |

### iOS derlemesi neden yapılamadı

Host'ta gerçek bir araç zinciri sorunu var, bu değişiklikten bağımsız:

```
CoreSimulator is out of date. Current version (1051.55.0) is older than
build version (1171.7.0).
...
DVTPlugInDYLDErrorMessageErrorKey=dlopen(.../DVTCoreDeviceCore, 0x0000):
Symbol not found: _$s10CoreDevice17DetailedOperationC7metricsSDySSAA12CodableValueOGvg
```

Bu, Xcode 27'nin CoreSimulator/CoreDevice bileşenleriyle senkron olmadığını
gösteriyor — muhtemelen ara katmanda bir Xcode sürüm güncellemesi yarım kaldı.
Belirti olarak proje hedefindeki hiçbir dosya derlenmeden önce, ilgisiz bir
üçüncü parti paket (RevenueCat `PaywallColor.swift`) "invalid redeclaration"
hatası veriyor — bu SwiftUI/derleyici durumunun bozulduğunun tipik işareti,
gerçek bir kod hatası değil. Muhtemel düzeltme: Xcode.app'i açıp ilk kurulum
bileşenlerinin tamamlanmasını beklemek, veya:

```bash
sudo xcodebuild -runFirstLaunch
```

Bu komut `sudo` istiyor, benim çalıştıramayacağım bir adım.

## Bekleyenler

- iOS derlemesi doğrulanamadı (host sorunu).
- `NovaEducationScopeEditor`'ün kendi iç akordionu (native `DisclosureGroup`,
  198 satır: konular/dersler/katılımcılar/müfredat) hiç yeniden yazılmadı —
  yalnız nereden açıldığı değişti. İstenirse o da Nova bileşenleriyle ayrı
  bir turda yenilenebilir.
- Legacy/basit eğitim formu (`NovaTrainingSessionEditor`) hâlâ eski
  `GroupBox`/`Label` görünümünde; kapsam dışı bırakıldı.
