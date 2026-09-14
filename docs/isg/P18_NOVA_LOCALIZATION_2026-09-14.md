# P18 — NOVA yüzeyinin TR/EN kataloğu ve erişilebilir kontrol adları

14 Eylül 2026 · dal `codex/isg-transition-foundation`

P18'in kapanış koşullarından biri "tüm ekran TR/EN/accessibility kabulü"ydü. Bu dilim onun dil ayağını kapatıyor: yeni native yüzeyin (NOVA kabuğu, rehber/personel ekranları, kişisel defter hedefi) kullanıcıya görünen **bütün** metni artık katalogdan geliyor ve İngilizce karşılığı var. Mağaza kimlikleri, tasarım token'ları, font dosyaları, ikonlar ve ekran yerleşimi değişmedi.

## Neden gerekliydi: kapı zaten kırmızıydı

P05/P13/P18 native işleri sırasında yüzeyde **230 sabit Türkçe metin** birikmişti ve `scripts/check_localization_hardcoded.mjs` bunları "yeni borç" olarak sayıp kapıyı düşürüyordu. Envanter `ios_ui=216` gösteriyordu. Yani depo, farkına varılmadan, İngilizce diline geçildiğinde Türkçe konuşan bir arayüzle çalışıyordu.

## Ne yapıldı?

| Adım | Sonuç |
|---|---|
| Envanter yenilendi | `localization/content-inventory/app-content.csv` NOVA satırlarını içeriyor |
| 214 dizge çevrildi | İSG terminolojisiyle elle: İSG→OHS, uygunsuzluk→nonconformity, işyeri→workplace, görevlendirme→assignment, tehlike sınıfı→hazard class, mevzuat bölgesi→jurisdiction |
| Otomatik taşıma iki turda çalıştırıldı | 184 + 30 = **214 literal** anahtara bağlandı |
| Aracın göremediği 47 literal elle taşındı | ternary dalları, `??` varsayılanları, `self.error =` atamaları ve string interpolasyonları |
| 7 interpolasyon format dizgesine çevrildi | `"Bugün \($0) açık uygunsuzluk var."` → `%@` format + `String(format:)` |
| 3 ikon-only kontrole konuşulan ad verildi | geri, aramayı temizle, personel geri |
| `NotebookReminderRecurrence.label` modelden çıkarıldı | izole sözleşme testi bağımsız derlenmeye devam ediyor |

Katalog `Localizable.xcstrings` 679 → **940** anahtar. Hepsi `tr` + `en` çiftiyle.

## Bu dilimde bulunan gerçek hatalar

### 1. Migration aracı mevcut çevirileri siliyor (P0)

`node scripts/migrate_swift_localization_catalogs.mjs --apply` çalıştırıldığında kataloglar **yeniden yazılıyor** ve yalnız güncel envanterdeki girdiler korunuyor. Zaten taşınmış anahtarlar artık literal olmadığı için envanterde görünmüyor; dolayısıyla katalogdan **siliniyorlar**.

Ölçülen kayıp: `Analysis` 777→557, `Paywall` 161→101, `Onboarding` 313→294, `Reports` 176→175 — toplam **300 anahtar**, bunların **216'sı hâlâ Swift kaynağında referans veriliyordu**. Çalıştırıp commit etmek, mevcut İngilizce çevirilerin üçte birini sessizce yok edecekti.

Bu dilimde çözüm: `--apply` çıktısındaki **yeni** anahtarlar yakalanıp kataloglar `git checkout` ile geri alındı, sonra yalnız yeni anahtarlar **eklemeli** olarak birleştirildi. Son durumda hiçbir katalog küçülmedi (doğrulama aşağıda).

**Aracın kendisi düzeltilmedi.** Bir sonraki geliştirici `--apply` çalıştırırsa aynı kayıp tekrar olur. Kalıcı düzeltme `writeCatalogs`'un mevcut katalogla birleşmesi olmalı; bu ayrı bir iş olarak açık.

### 2. Envanter tarayıcısının kör noktaları

Tarayıcı yalnız belirli sözdizimi kalıplarını görüyor. Görmedikleri: ternary dalları (`x ? "A" : "B"`), `??` varsayılanları, `self.error = "..."` atamaları, string interpolasyonu içindeki literaller. Envanter `ios_ui=2` derken yüzeyde hâlâ **47** kullanıcıya görünen Türkçe literal vardı.

Ayrıca tarayıcı Türkçe'yi **diakritikle** tanıyor; "Aktif", "Kaydet", "Kapat" gibi diakritiksiz kelimeler hiç sayılmıyor. Bunlar elle bulundu ve taşındı.

### 3. İzole sözleşme testi kırıldı

`NotebookReminder.swift` `swiftc` ile **tek başına** derlenen bir model. Otomatik taşıma oraya `RDLocalization` çağrısı yazınca `notebook_native.test.mjs` `cannot find 'RDLocalization' in scope` verdi — ana uygulama derlenmesine rağmen. Sunum metni modelden çıkarılıp görünüm katmanına alındı; model bağımsızlığını koruyor.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| iOS ana uygulama Debug build (imzasız) | **BUILD SUCCEEDED** |
| `run_suite.mjs foundation` | **412 PASS**, 0 fail (önce 408; +4 yeni NOVA guard'ı) |
| `run_suite.mjs nova-design` | **24 PASS** |
| `migrate_swift_localization_catalogs.mjs --check` | PASS, bekleyen 0 çeviri |
| `check_localization_hardcoded.mjs` | 230 → **15** ek |
| Katalog anahtar sayıları | Analysis 777, Paywall 161, Onboarding 313, Reports 176, Auth 96 — **hiçbiri küçülmedi**; Localizable 679→940 |
| tr/en pariteliği | 11 katalogda eksik parite **0** |
| Kaynak→katalog çözünürlüğü | 1802 benzersiz referansın tamamı çözülüyor, yetim anahtar 0 |
| `verify_identity.mjs` | `ok: true`; bundle/package/callback/entitlement değişmedi |

Kalan 15 kapı bulgusu **bu dilimin işi değildir**: 14'ü 8 Eylül 2026 hukuk dokümanı güncellemesinden gelen eski borçtur (`Privacy-Policy.md`, `Gizlilik-Politikasi.md`, `RiskDetectedInfo.plist`), 1'i satır tabanlı tarayıcının iç içe tırnak içeren bir interpolasyonu ayrıştıramamasıdır — o satır tamamen yerelleştirilmiştir. **Borç taban dosyası tazelenmedi**; kapının kendi uyarısı bunu özellikle yasaklıyor.

## Yeni kalıcı guard

`scripts/isg/nova_localization.test.mjs` (foundation paketinde, 4 test):

1. NOVA'nın referans verdiği her anahtar bir katalogda var, `tr` ve `en` taşıyor ve **`en` ≠ `tr`** (çevrilmemiş kopya yakalanır).
2. `#if DEBUG` dışındaki hiçbir satırda ham Türkçe kopya kalmamış.
3. Yalnız ikondan oluşan hiçbir kontrol konuşulan ad olmadan gönderilmiyor.
4. Kataloglar küçülmemiş — Analysis/Paywall/Onboarding/Reports/Auth için alt sınır kontrolü, yani **1 numaralı hata tekrar ederse test kırmızı olur**.

## Açık kalanlar

1. **Takip paketinde writer düzeltildi:** mevcut anahtar/locale/metadata koruyan merge ve gerçek writer çift çalıştırma testi eklendi. Bu belgedeki kayıp anlatımı tarihsel hatadır; [güncel düzeltme ve sınırlar](REVIEW_FIXES_UI_ITERATION_2026-09-13.md). Literal tarayıcı kapsamı ve içerik kalite incelemesi ayrıca açıktır.
2. **Android tarafı bu dilimde değişmedi.** NOVA Compose yüzeyinin `strings.xml` TR/EN kabulü açık.
3. **Dil kalite incelemesi yapılmadı.** 261 yeni anahtarın hepsi `language_review: not_started`; İSG terminolojisi için uzman gözden geçirmesi gerekiyor.
4. **Gerçek cihazda EN turu yok.** Uygulama İngilizce dilde açılıp ekran ekran gezilmedi; VoiceOver tam akışı, Dynamic Type AX3 ve RTL dışı metin taşması kabulü açık.
5. **Hukuk dokümanı borcu (14 kalem)** kendi iş akışında ele alınmalı.
6. P18'in diğer kapanış koşulları — ana uygulamanın yeni köke geçişi, modüllerin gerçek servisleri, final marka/asset — **bu dilimde ele alınmadı**. **P18 kapanmadı.**
