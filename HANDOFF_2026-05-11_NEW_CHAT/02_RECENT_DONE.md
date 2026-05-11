# 02 - Son Yapılanlar

Bu bölüm özellikle son büyük çalışma turunu anlatır.

## Son Büyük Commit

- Commit: `ba58afa Polish mobile reporting and analysis flows`
- Öncesindeki kısa commitler:
  - `fa00b0e Polish dark mode CTA contrast`
  - `76c1e77 Polish theme and header menu UI`
  - `1e82afa Add profile, notification, and AI reliability updates`
  - `8248430 Update auth handoff and plan`
  - `7944c14 Fix report sheet flow and disable phone bridge`
  - `ef44224 Update auth flow and report UI`
  - `83f7f80 test: add report failure simulation coverage`

## UI/UX Son Durum

### Ana Sayfa

- Logo + Pro CTA + profil avatar üstte.
- Fotoğraf/metin segmented selector var.
- Foto yükleme alanı sadeleştirildi.
- `Taramayı Başlat` butonu siyah/yeşil stilinden modern sağ icon kapsüllü hale geldi.
- Free kullanıcı için günlük deneme hakkı kapsülü var.
- `Son Uygunsuzluklar` bölümü story/circle görünümünde.
- `Oluşturulan Raporlar` bölümü eklendi; son raporlar ana sayfada görünüyor.
- Text-only analizlerde boş görsel yerine standart `Metin Analizi` artwork kullanılıyor.

### Alt Menü

- Ortada dikkat çekici `Tara` butonu eklendi.
- Tab bar oyuk/oval tasarımı yapıldı.
- `Tara` butonu artık hangi sayfadaysa orada kaynak seçim sheet'i açıyor.
- Kamera/Galeri seçilince analiz akışı ana sayfa altyapısına aktarılıyor.
- Free limit doluysa uyarı gösteriliyor.

### Foto Kaynak Sheet

- Eski sistem alert yerine modern bottom sheet var.
- `Kamera ile çek`
- `Galeriden seç`
- Kapatma X ikonu var.
- En son QA sonrası accessibility label düzeltmesi yapıldı, henüz commitlenmedi.

### AI Canvas Sheet

- 16 analiz odağı eklendi:
  - Genel
  - KKD
  - Makine
  - Uyarı levhaları
  - Elektrik
  - Sektör
  - Yangın
  - Ergonomi
  - Ortam Ölçümü
  - Patlama
  - Çevre
  - Mevzuat
  - Yüksekte Çalışma
  - Hareketli Ekipman
  - Genel Premium
  - İş Makineleri
- Max 2 seçim kuralı var.
- Pro canvaslar Free kullanıcıda kilitli.
- Kullanıcının 100 karakterlik özel analiz notu var.
- Prompt routing backend tarafında genişletildi ama kullanıcı sabit promptları daha sonra verecek.

### Bekleme/Analiz Ekranı

- Foto üzerindeki yeşil scan animasyonu korundu.
- AI sinyal kapsülleri eklendi: `KKD`, `Risk`, `Kontrol`.
- Alt adımlar kartlı, animasyonlu hale getirildi.
- Kullanıcının bekleme toleransını artıracak profesyonel görünüm hedeflendi.

### Analizler Sayfası

- Header ana sayfa ile uyumlandı.
- Modern analiz merkezi paneli var.
- Arama ve filtre yüzeyi yenilendi.
- Kartlar görsel/text ayrımını düzgün gösteriyor.
- Başlıkta tekrar eden tarih kaldırıldı.
- Tarih alt satırda görünüyor.
- Eski `mark` gibi teknik canvas id'leri kullanıcı diline çevrildi.
- Çoklu canvas başlıktan türetilerek `Genel + Sektör` gibi gösteriliyor.
- Görseller fixed box'a sığdırıldı, yazı üstüne binmiyor.

### Raporlar Sayfası

- Modern rapor merkezi paneli var.
- Kaydedilmiş rapor kartları yenilendi.
- `Excel tablo`, `Standart rapor`, `Risk analizi` etiket renkleri ayrıldı.
- Ana sayfadan rapor önizleme açılabiliyor.
- Document preview içine X kapatma ve indirme/paylaşma aksiyonları eklendi.

### Sonuç Ekranı

- Sağ üstte indirme ve paylaşma ikonları ayrıldı.
- Free sonuçlarda soft Pro mesajı var:
  - Pro ile 10 bulguya kadar ve en az %90 AI güveni.
- Method selector aktif seçimi yeşil check ile gösteriyor.
- Risk dağılım başlığı eklendi.
- Free kullanıcıda gerçek bulgular arasına kilitli Pro teaser bulguları ekleniyor.
- Ayrıca alt tarafta 10'a tamamlayan kilitli Pro bulgu kartları var.
- Bu kilitli kartlar sadece ekranda görünür; rapor/PDF/Excel'e dahil edilmez.
- `Fine-Kinney metodu · risk değerlendirme şablonu` gibi alt footnote kaldırıldı.

### Risk Detay Ekranı

- X kapatma ikonu var.
- Foto üstü skor kartı yeniden düzenlendi.
- `R = ...` formülü metod başlığının altına taşındı.
- Yöntem karşılaştırmasında Fine-Kinney / 5x5 geçişi çalışır.
- Seçili yöntemde check gösterilir.
- Standart referans başlığı:
  - `Mevzuat-Standart Referansları Pro'da Açıktır`

### Profil Sayfası

- İstatistikler var: Analiz, Rapor, Bu hafta.
- `Bu hafta` artık takvim haftası yerine son 7 gün mantığına çekildi.
- Free kullanıcı Pro kart metni güncellendi.
- Dark mode Pro kart uyumsuzluğu düzeltildi.
- Profil bilgileri sheet'i modern ikonlu input kartlarına dönüştürüldü.
- Üstteki `Raporlarda kullanılacak bilgiler` kartı kaldırıldı.
- Profil > Geçmiş analizler ve Raporlarım ilgili tablara gider.

### Karanlık Mod

- Core renkler dark/light adapte oluyor.
- Ana CTA'lar dark mode'da yeşil arka plan + beyaz yazı/ikon.
- Rapor oluştur sheet'indeki kilitli risk analizi kartının dark mode renkleri düzeltildi.
- Profil Pro kart dark mode'da daha belirgin.

## Excel Export

- `generate-excel-report` Edge Function eklendi.
- XLSX üretir:
  - `Özet`
  - `Risk Analiz Tablosu`
  - `Aksiyon Planı`
  - `Rapor Bilgileri`
- Pro kullanıcı kontrolü server-side yapılır.
- `reports` bucket ve metadata `xlsx` destekliyor.
- iOS rapor akışından Excel üretme entegre.
- Backend smoke test yapıldı; full in-app Pro flow manuel QA hâlâ bekliyor.

## Plan Dokümanları

- First-launch onboarding planlandı.
- APNs push secrets yapılacaklar listesine eklendi.
- Gemini multi-key backend yapıldı, API key eklenince test edilecek.

