# Analiz sonuç ekranları — dördüncü tur

14 Eylül 2026. Native (migration yok). Sunucu değişmedi; rollout hâlâ kapalı.
Önceki turlar: [fotoğraf akışı](P09_ANALYSIS_FLOW_2026-09-14.md),
[pano ve analiz detayı](P09_RECORD_BOARD_2026-09-14.md),
[menü ayrımı](P09_MENU_AND_BOARD_2026-09-14.md).

Kullanıcı dokuz referans görsel gönderdi. Görsellerin renkleri ve header'ları
referans alınmadı; yalnız yerleşim alındı ve NOVA token'larıyla kuruldu.

## 1. Analizlerim

Sayfa üç parça: bilgilendirme kartı, arama + filtre, kart listesi.

- **Bilgilendirme kartı** (`NovaAnalysisOverviewCard`): ikon, başlık, açıklama,
  sağda koyu sayaç; altında üç koyu çip — Bu hafta · Kritik · Bulgu.
- **Sayılar sayfanın okuduğu satırlardan sayılıyor.** `NovaAnalysisListStats`
  eline verilen listeyi sayar; hesabın toplamını iddia eden bir çağrı yok.
  Liste penceresi 30'dan 50'ye çıkarıldı.
- **Arama** başlık, firma, sektör, odak ve tarih üzerinde çalışıyor.
  Yanında firma açılır listesi (`Menu`), altında dört çip: Tümü · Bu hafta ·
  Kritik · Firmasız.
- **Kart** kompakt: küçük fotoğraf (kamera rozetiyle), başlık, sağda en yüksek
  bant rozeti, ikonlu satır (tarih · bulgu · fotoğraf), sonra firma/sektör/
  **İncelendi** etiketleri.
- `İncelendi` satırın kendi durumundan geliyor (`status == "completed"`),
  tahmin değil.

## 2. Analiz Raporları

Yeni sayfa: `NovaAnalysisReportsScreen`. Analizlerim başlığındaki belge
düğmesinden açılıyor; ayrı bir menü girişi **eklenmedi**, çünkü sayfa
Analizlerim'in arşivi.

- Aynı bilgilendirme kartı: toplam dosya, PDF, Excel, Firma.
- Liste ürünün kendi arşivinden geliyor: `listReports(photoAnalysesOnly: true)`.
  Yani yalnız fotoğraflı analizlerden üretilmiş raporlar.
- Pilot listesi bir firmayı adlandıramazsa arşivin kendi `company_snapshot`'ı
  kullanılıyor; satır "firmasız" gibi gösterilmiyor.
- Analizi hâlâ duran satır o analizin detayına gidiyor. Analizi silinmiş satır
  listelenmeye devam ediyor, sadece açılmıyor — soluklaştırılmıyor.

## 3. Analiz Sonucu sayfası

### Alt bar sabit, sekme çubuğu yok

Sayfa artık kabuğun içine itilmiyor, **kabuğun üstünde** açılıyor
(`fullScreenCover`). Böylece alt sekme çubuğu görünmüyor ve sayfanın kendi
barı gerçek ekran altına oturuyor (`safeAreaInset(edge: .bottom)`).

Bar iki parça: **Geri Dön** ve geniş koyu düğme. Seçili kayıt varsa geniş düğme
**Firmaya Aktar**, yoksa **Rapor oluştur**. Altında `n/m seçili` yazıyor.

Analiz bittiğinde detay, bekleme ekranının kendi kapanışından açılıyor
(`onDismiss`), böylece iki sunum aynı yuva için yarışmıyor.

### Üst bilgi kartı

Küçük fotoğraf (dokun → büyük hâli popup'ta), başlık, firma/sektör/tarih/
fotoğraf etiketleri. Firma yoksa kartın içinde **Firmaya ata** satırı.

### Klasör sekmeleri

Dört bölüm; seçili sekme beyaz, alt kenarı yok, altındaki panelle tek yüzey.
Başlangıçta **Risk Analizi** seçili. Sekme altında bölümün kendi sayısı yazıyor
(3 Bulgu · 2 Görüş · 1 Öneri · 1 Kayıt).

### Her bölümün kendi başlık kartı

`NovaAnalysisSectionHeader`: ikon, ad, sayı ve bölümün ne olduğu. Her bölüm tek
bir tonla ayrılıyor — Risk Analizi `danger`, Uzman Görüşü `warning`,
Eğitim `info`, Onaylı Defter `neutral`. Bölüme özel palet yok.

### Risk Analizi

- **İstatistik kartı**: Toplam bulgu ve En yüksek skor iki koyu çipte, altında
  dört bantlı dağılım. Dağılım o bölümün kendi satırlarından, okunan metoda
  göre sayılıyor.
- **Metot toggle'ı**: Fine-Kinney (`R = O × F × Ş`) ve 5×5 Matris (`R = O × Ş`).
  Seçim **yalnız hangi skorun okunduğunu** değiştiriyor; kaydedileni değil.
  Bir metodun skoru diğerinden hesaplanmıyor: `NovaAnalysisItem` iki metodun
  kendi bandını ve sayısını ayrı taşıyor.
- **Bulgu kartı**: sıra rozeti, bant, skor, başlık, açıklamanın üç satırı,
  düzeltici önlem kutusu, etiketler (Kök neden · Önleyici · Mevzuat · Foto),
  altta düzenle/sil/faydalı/faydasız + **Devamını incele**.
- Üstte `n/m seçili` ve **Tümünü seç / Tümünü bırak`.

### Uzman Görüşü ve Eğitim Önerileri

`NovaAnalysisAdviceCard`. Skorsuz geldikleri için **hiçbir bant gösterilmiyor**
— sunucu da bu bölümler için skor üretmiyor, istemci de uydurmuyor.
Eğitim kartında ayrıca kim için ve süre bilgisi var.

### Onaylı Defter

`NovaNotebookPanel`: çizgili defter zemini (`NovaNotebookRules` — yatay satır
çizgileri ve sol kenar payı), numaralı maddeler. Zemin token'lardan çiziliyor;
dışarıdan görsel yok.

## 4. Bulgu detay popup'ı

Yeni sayfa değil, popup. `NovaAnalysisItemSheet`:

- **Kapak**: bulgunun okunduğu fotoğraf (`source_photo_indices`, 1 tabanlı;
  indeks indirilen fotoğrafların dışına düşerse ilkine düşülüyor), üzerinde
  bant rozeti, kayıt numarası, skor, başlık ve firma/analiz/tarih satırı.
  Sağ üstte faydalı/faydasız.
- **Risk skor kartı**: büyük skor, metot adı ve `O 6 × F 6 × Ş 40 = 1.440`
  çarpanları. Çarpanlar **analiz hepsini kaydettiyse** yazılıyor; eksikse
  yalnız skor ve bant görünüyor.
- Altında alan kartları: Açıklama, Kök neden, Düzeltici/Önleyici önlemler,
  Mevzuat, süre.
- Düzenle ve sil **kendi popup'larına** ayrıldı (`NovaAnalysisEditSheet`,
  `NovaAnalysisDeleteSheet`); okuma görünümü forma dönüşmüyor.
- Düzenle ve sil yalnız Risk Analizi'nde. Diğer üç bölümün arkasında
  düzenlenecek bir bulgu kaydı yok.

## 5. Rapor popup'ı

Sayfa değil popup. İki seçenek kart olarak: **Standart Rapor** (PDF) ve
**Risk Analizi Tablosu** (Excel). Altında metot toggle'ı ve firmaya işleme
anahtarı. Tür seçilene kadar düğme "Rapor türü seçin" yazıyor ve kapalı.

## 6. Fonksiyonlar aynen duruyor

| İşlev | Nereden |
|---|---|
| Bulgu seç → firmaya aktar | Alt bar · madde kimliğiyle anahtarlı |
| Skorsuz maddeyi uygunsuzluk **veya** geliştirme önerisi olarak aktar | Aktarma popup'ı |
| Analizi firmaya ata | Üst kart · liste |
| Bulguyu düzenle / sil | Bulgu popup'ı |
| Faydalı / Faydasız | Kart ve popup |
| Rapor oluştur | Alt bar |

**Aktarılan bant, uzmanın o an okuduğu metodun bandı.** `NovaAnalysisFileRequest`
artık bandı kendisi taşıyor; madde tek başına bir banda cevap vermiyor.

## 7. Sunucu

Değişmedi. Migration yok. Analiz motoru yine `runPhotoAnalysis`, bölümler yine
`AnalysisResultHubService.loadWhenReady`, raporlar yine `storeReport` ve
`generate-excel-report`.

## 8. Onarılan eski kırıklar

Bu turda üç tanesi bulundu ve düzeltildi:

1. **`localization_catalog_tests.mjs` L10N-001 kırıktı.** Localizable
   kataloğundaki 427 NOVA kaydının açıklamasında `placeholders:` bilgisi yoktu;
   dosya ilk teste düşüp duruyordu, yani L10N-002…L10N-017B hiç çalışmıyordu.
   427 açıklamaya kaydın kendi değerinden hesaplanan yer tutucu listesi eklendi.
   Hiçbir tr/en değeri değişmedi.
2. **L10N-004 kırıktı.** `NovaDirectoryScreens.swift:75` tarih aralığını
   `"\(start) → \(end)"` diye kurup ekrana yazıyordu. Yer tutuculu bir anahtara
   çevrildi (`localizable.nova.directory.engagement.range`). Sabit metin borcu
   15'ten 14'e indi.
3. **L10N-013 kırıktı.** `localizable.nova.manual.progress.hint` kod tarafında
   fotoğraf adımını da sayıyordu, katalog eski cümlede kalmıştı. Katalog koda
   getirildi.

## 9. Açık kalan

- **Rollout kapalı.** `UPDATE private_isg.rollout SET read_enabled=true,
  write_enabled=true WHERE feature='nonconformity';` — ayrı bir insan kararı.
- **L10N-018 kırık ve bu turda düzeltilmedi.** "Approved Turkish catalog source
  remains locked" kilidi 2.387 Türkçe birime sabitlenmiş; katalogda şu an 3.086
  var. Kayma bu turdan çok önce başlamış (NOVA fazlarının tamamı). Kilit,
  Türkçe metnin sahibi tarafından gözden geçirilsin diye var; 699 birimi
  görmediğim hâlde yeniden mühürlemedim. Yeni hash'i basmak sahibin kararı.
- Elle giriş kanıt fotoğrafı hâlâ kaydedilmiyor (P04 ikinci dilim).
- Android'de yalnız navigasyon modeli var; bu ekranların Kotlin karşılığı yok.
- Analiz Raporları sayfası ilk 50 kaydı okuyor; sayfalama yok.
- Rapor satırından dosyayı indirme/paylaşma bu sayfada yok; rapor arşivi
  ekranı ayrı duruyor.
