# Menü ayrımı, pano ve klasör sekmeleri — üçüncü tur

14 Eylül 2026. Native (migration yok). Sunucu değişmedi; rollout hâlâ kapalı.
Önceki turlar: [fotoğraf akışı](P09_ANALYSIS_FLOW_2026-09-14.md),
[pano ve analiz detayı](P09_RECORD_BOARD_2026-09-14.md).

Kullanıcı geri bildirimi yedi maddeydi; hepsi uygulandı.

## 1. Menü: dört giriş, dört sayfa

Sol menüde artık **Uygunsuzluklar**, **Analizlerim**, **Analiz Yap**, **Uygunsuzluk Ekle** var.
Her biri tek bir sayfaya iniyor; "nasıl başlamak istersiniz" ara sayfası kaldırıldı.

| Menü | Açılan sayfa |
|---|---|
| Uygunsuzluklar | Yalnız kayıt panosu |
| Analizlerim | Yalnız analiz listesi |
| Analiz Yap | Fotoğraf alanı + **Analizi başlat**, başka hiçbir şey |
| Uygunsuzluk Ekle | Analiz bulgularından seç · kendim gireceğim · yeni analiz |

Ana sayfadaki fotoğraf kartı doğrudan **Analiz Yap**'a gidiyor.

### Bunun için yapılan sözleşme onarımı

`analyses` ve `newAnalysis` iki yeni destination. Eklerken üç eski kayma da düzeltildi:

- `newCompany` Swift'te vardı, katalogda ve Kotlin'de yoktu.
- `quickAdd` Swift'te dört, katalogda ve Kotlin'de üç öğeydi.
- **Dört izole `swiftc` sözleşme testi P18 dil taşımasından beri derlenmiyordu**
  (`RDLocalization` bağımsız modellere yazılmıştı): `NovaNavigationCheck`,
  `NovaSessionHostCorpus`, `NovaCompanyListCheck`, `NovaDirectoryCheck`.
  Her birine, yazılı fallback'i döndüren bir test stub'ı eklendi; üretim kodu değişmedi.

Katalog 21 destination, drawer 14, quickAdd 4. Fixture'lar üç yeni destination için
elle yazılmış kalıbın aynısıyla dolduruldu: navigasyon 94 senaryo, oturum host'u 104 vaka / 467 geçiş.

## 2. Pano

- Filtreler **yan yana üç açılır liste**: Firma · Durum · Kayıt türü. Basınca kendi listesi açılıyor.
- Kart kompakt: **küçük fotoğraf**, başlık, önem ve durum rozeti, sonra cümle yerine **ikon**
  (firma, işyeri, açılış, termin, analizden geldi). Termini geçen tarih kırmızı.
- Fotoğraf yalnız analiz bulgusundan doğmuş kayıtta var: bulgu → analiz → ilk fotoğraf.
  Elle açılmış kayıtta fotoğraf yerine kalem ikonu; uydurma görsel yok.

## 3. Kayıt detayı artık popup

Ayrı sayfa kaldırıldı. Popup içinde:

- İki sütunlu **künye ızgarası** (firma, işyeri, açılış, termin, kapanış, sorumlu, kaynak)
- Kayıt detayı ve **Düzenle** (yerinde açılıyor, üstüne ikinci popup açmıyor)
- **Durum · Aksiyon · Doğrula** üç düğme; seçilen kendi alanını aynı popup içinde açıyor
- Altta düzeltici aksiyon ve doğrulama geçmişi

Durum geçişleri yine migration'ın kenar tablosuyla iki yönlü test ediliyor; beş karakterden
kısa gerekçe ve kabul edilmiş doğrulaması olmayan kapatma burada da reddediliyor.

## 4. Analiz detayı

- Üstte **küçük kart**: fotoğraf, analiz adı, firma rozeti, tarih, metot, sektör.
  Fotoğrafa dokununca popup'ta büyük hâli.
- Dört bölüm **klasör sekmesi**: ikon + isim + sayı. Seçilen sekme beyaz, üst ve yan çerçevesi var,
  **alt kenarı yok** ve alttaki panelle tek yüzey gibi birleşiyor; seçilmeyenler açık yeşil.
  Çerçeveli kutu yerleşimi kaldırıldı. Başlangıçta Risk Analizi seçili.
- Bulgu kartı: başlık, bant, skor, açıklamanın iki satırı ve **Devamını incele**.

## 5. Elle giriş

- **Fotoğraf adımı açık başlıyor** ve birinci sırada.
- İkinci adım artık "İşyeri" değil **Firma**. Firma seçilince o firmanın işyeri/departmanları
  listeleniyor; seçmek isteğe bağlı.
- Kayıt sunucuda bir işyerine bağlanmak zorunda olduğu için, seçim yapılmazsa firmanın ilk
  işyeri kullanılıyor ve ekran **hangisine açılacağını yazıyor**.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| `run_suite.mjs foundation` | **470 / 470 PASS** |
| `run_suite.mjs nova-design` | **36 / 36 PASS** |
| `NovaNavigationCheck` | PASS · katalog + 94 senaryo / 230 geçiş |
| `NovaSessionHostCheck` | PASS · 104 vaka / 467 geçiş |
| `NovaCompanyListCheck` · `NovaDirectoryCheck` | PASS (yeniden derleniyor) |
| Dil kapıları | `--check` PASS, sabit metin borcu 15 (değişmedi) |
| iOS Debug + `NOVA_PILOT_BUILD` | SUCCEEDED |

Simülatörde doğrulandı: drawer'daki dört yeni giriş, açılır listeli pano, fotoğraflı kompakt
kartlar, popup kayıt detayı, klasör sekmeli analiz detayı, yalnız fotoğraf alanı olan Analiz Yap.

## Açık kalanlar

- **Rollout kapalı.** Pano canlı veri göstermeden önce:
  `UPDATE private_isg.rollout SET read_enabled=true, write_enabled=true WHERE feature='nonconformity';`
- Elle girişteki fotoğraf hâlâ kayda eklenmiyor (P04 temiz tarama olmadan dosya kalıcı yapmıyor).
- Android tarafında yalnız `NovaNavigation.kt` güncellendi; yeni ekranların Kotlin karşılığı yok.
- Pano firma başına ayrı okuma yapıyor; çok-firmalı okuma sunucuya taşınmalı.
- `tests/isg/shell-ios` harness'ı hâlâ derlenmiyor — orada gereken gerçek `RDLocalization`,
  stub değil; ayrı iş.
