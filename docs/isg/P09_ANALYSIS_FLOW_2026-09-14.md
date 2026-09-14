# Fotoğraf analizi akışı — firma/sektör/odak, analiz detayı ve elle giriş

14 Eylül 2026. Native (migration yok). Sunucu tarafı:
[P09 ikinci dilim](P09_NONCONFORMITY_DETAIL_2026-09-14.md) (`20260914190000`).

Analiz motoru, rapor üreteci ve uygunsuzluk sınırı **zaten çalışan sistemin kendisi**.
Bu dilim onları birbirine bağlar; hiçbirini yeniden yazmaz.

## 1. Fotoğraf → Firma → Sektör → Odak

`NovaAnalysisIntakeScreen` üç adım, her adım geri dönülebilir.

| Adım | Davranış |
|---|---|
| Firma | Ekli pilot firmalar + **"Firmasız devam et"**. Firmasız, eksik veri değil listelenmiş bir cevaptır. |
| Sektör | Firma sektörü tanınıyorsa **otomatik seçilir**, üstünde firmanın adıyla bir not durur. |
| Odak | Çoklu seçim. Planın kapsamadığı odak gizlenmez; görünür ama seçilemez ve rozetiyle söyler. |

### Sektör eşleşmesi neye göre?

Firma kaydındaki sektör **serbest metin**; analiz motorunun sektörü ise 15 kanonik kimlikten biri.
`NovaSectorMatch` normalize edip (diakritik katlama, noktalama temizliği, `ı`→`i`) **birebir**
karşılaştırır; iki parçalı etiketin her iki yarısı ve kimliğin kendisi de cevap verir.

- Tanınmayan bir sektör **hiçbir şey seçtirmez**; yanlış ön seçim, hiç seçim yapmamaktan kötüdür.
- İki sektör aynı kelimeyi iddia ediyorsa yine seçim yapılmaz.
- Firma kartı, sektörü tanınmadıysa bunu satırında yazar (`sektör tanınmadı`), böylece bir sonraki
  adımdaki not sürpriz olmaz.
- Uzman sektörü değiştirdiği anda not kaybolur: not, artık doğru olmayan bir cümleyi taşımaz.

Katlamanın locale'i sabit (`en_US_POSIX`): Türkçe locale ile katlarsak `İ` → `ı` olur ve
`İnşaat` ile `insaat` eşleşmeyi bırakır. 31 kontrol `scripts/isg/NovaAnalysisIntakeCheck.swift`.

## 2. Analiz detay ekranı (NOVA)

Ürünün hâlihazırda ürettiği dört bölüm, yeni tasarımda: **Risk Analizi**, **Uzman Görüşü**,
**Eğitim Önerileri**, **Onaylı Defter**. Kaynak `analysis-result-sections`; projeksiyon hazır
değilse ekran bunu söyler, dört boş bölüm göstermez.

- Skorlu bulgu bandını ve skorunu uzmanın **kendi metoduyla** gösterir.
- Bulgunun **tüm detayları** düzenlenebilir (başlık, kategori, açıklama, önlem, mevzuat) ve skor
  yayımlanmış ölçeklerden yeniden girilebilir. Yarım bırakılan skor **hiç gönderilmez**, yani
  analizin ürettiği sayıların üstüne yazamaz.
- **Rapor oluştur**: PDF veya Excel, uzmanın metoduyla; firma seçiliyse o firmaya Analiz Raporu
  olarak işlenir. Rapor kotası sunucunundur; reddi olduğu gibi gösterilir.
- Seçilen maddeler firmaya aktarılır. Madde kimliği mutation anahtarıdır: aynı maddeye ikinci kez
  basmak ikinci kayıt açmaz, replay eder.

### Skorsuz bölümler

Uzman Görüşü ve Eğitim Önerileri **skorsuz** gelir. Bu yüzden:

- Bandı olmayan bir madde için önem derecesini **kişi seçer**; sunucunun eşleyecek bir bandı yoktur
  ve `open_from_expert_item` payload'ında `risk_band` anahtarı **hiç yoktur**.
- Aynı maddeler **geliştirme önerisi** olarak da kaydedilebilir; kayıt türü listede ayrı rozetle
  görünür ve uygunsuzluk sayılmaz.
- Onaylı Defter aktarılamaz: orası bir kayıt kaynağı değil, defter metnidir.

## 3. Firmasız analiz ve sonradan atama

Analiz firmasız çalıştırılabilir, hesapta durur. **Analizlerim** ekranı hepsini listeler ve
"Firmasız" filtresi bekleyenleri ayırır. Atama hem listeden hem analizin kendi ekranından yapılır;
atandığında çalışma alanı da o firmaya geçer, böylece açılacak kayıtlar doğru firmaya düşer.

## 4. Elle giriş (yapay zekâsız)

`NovaManualNonconformityScreen`, mevcut `NovaCompanyAccordion` ile:

**İşyeri → Uygunsuzluk (tehlike başlığı, açıklama, önlem, önem, kayıt türü) → Risk metodu ve
skorlama → Mevzuat bilgisi → Firma sorumlusu**

- İlerleme çubuğu **tamamlanan** başlığı sayar; açılan başlığı değil.
- Tamamlanan başlık yeşil tik alır ve bir sonraki eksik başlığı önerir; istenen başlığa dönmek serbest.
- Zorunlu olan yalnız ilk iki başlıktır. Mevzuat, sorumlu ve skorlama isteğe bağlıdır ve bu ekranda
  açıkça öyle yazar.
- Skor ekranda önizlenir ama **kaydedilen bandı sunucu hesaplar**; ekran bunu her seferinde söyler.
  İstemcideki eşikler `nova_analysis_flow.test.mjs` ile migration'daki eşiklere karşı kilitlidir.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| `run_suite.mjs foundation` | **470 / 470 PASS** |
| `run_suite.mjs nova-design` | **32 / 32 PASS** (8 yeni davranış testi) |
| `NovaAnalysisIntakeCheck` (izole swiftc) | **31 / 31 PASS** |
| `migrate_swift_localization_catalogs.mjs --check` | PASS, bekleyen 0 |
| `check_localization_hardcoded.mjs` | 15 (değişmedi; 14 hukuk + 1 tarayıcı artefaktı) |
| iOS Debug build | SUCCEEDED |
| `NOVA_PILOT_BUILD` simülatör build | SUCCEEDED |

110 yeni dil anahtarı TR/EN olarak `Localizable.xcstrings`'e **eklemeli** birleştirildi;
hiçbir katalog küçülmedi (P18'deki `--apply` tuzağına girilmedi).

Simülatörde `RD_UI_TEST_MAIN RD_UI_TEST_NOVA_REVIEW` ile görsel kontrol yapıldı: firma adımı,
otomatik sektör notu, analiz detayı, bandı okunamayan bulgunun önem derecesi sorusu, merkez popup
ve elle giriş akordiyonu (6×3×15 = 270 → Yüksek) ekranda doğrulandı.

## Bu turda yakalanan iki düzeltme

1. **Alttan açılan sayfa yerine merkez popup.** Yeni sayfalar `.sheet` kullanıyordu; tasarım kuralı
   merkez popup diyor. `.fullScreenCover` + `NovaPopup`'a geçirildi.
2. **Popup yüksekliği içerikten ölçülmeliydi.** `novaPopupContentSize()` `ScrollView`'a takılınca
   kapsayıcının yüksekliğini bildiriyor ve popup ekranı kaplıyordu; ölçüm içerik `VStack`'ine alındı.
   Ayrıca kayan sayfalara alt gezinme çubuğu için `novaTabBarInset` payı eklendi.

## Açık kalanlar

- **Rollout hâlâ kapalı.** Ekranlar canlı veri göstermeden önce:
  `UPDATE private_isg.rollout SET read_enabled=true, write_enabled=true WHERE feature='nonconformity';`
- **Elle girişte kanıt fotoğrafı yok.** İstenen adımlar arasında fotoğraf da vardı; ancak yeni şemada
  bir uygunsuzluğa dosya bağlayacak açık bir istemci sınırı yok (P04 dosya çekirdeği kapalı ve
  istemciye açılmamış). Sahte bir adım koymak yerine adım hiç eklenmedi. Açılması ayrı bir dilimdir.
- **Uygunsuzluk detay ekranı** (durum geçişi, düzeltici aksiyon, doğrulama) hâlâ yok. Servis
  metotları (`transition`, `addAction`, `verify`, `setDetail`) yazıldı ve derleniyor; ekran yok.
- **`record_kind` sunucu tarafında filtrelenmiyor**; istemci 200 satırlık listeyi kendi ayırıyor.
- **Hostless shell harness (`tests/isg/shell-ios`) derlenmiyor.** P18 dil taşımasından kalma bir
  kırılma (`RDLocalization` hedefte yok); bu turda dokunulmadı, görsel kontrol pilot build üzerinden
  yapıldı.
- Analizin firma seçimi **çalışma alanı seçimini de değiştirir**; pilotta tek firma kapsamı olduğu
  için bilinçli, ama Firmalar sekmesindeki seçimi de kaydırır.
