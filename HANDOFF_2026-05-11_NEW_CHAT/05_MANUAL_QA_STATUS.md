# 05 - Manual Simulator QA Durumu

Manual QA başlatıldı. 2026-05-11 devam oturumunda Auth, Email OTP, rapor upload retry ve Free limit dolu senaryosu test edildi.

## QA Sırasında Yapılanlar

### Build

- `build_run_sim` başarılı çalıştı.
- App iPhone 17 Pro simulator'da açıldı.

### Orta `Tara` Butonu

Kontrol:

- Raporlar sekmesindeyken `Tara` butonuna basıldı.
- Ana sayfaya fırlamak yerine mevcut Raporlar sayfasının üzerinde kaynak seçim sheet'i açıldı.

Sonuç:

- Geçti.

### Foto Kaynak Sheet

Kontrol:

- Sheet açıldı.
- Tasarım doğru göründü:
  - `Saha fotoğrafı`
  - `Kamera ile çek`
  - `Galeriden seç`
  - X kapatma

İlk denemede:

- `Galeriden seç` accessibility label ile bulunamadı.
- Koordinatla dokununca yanlışlıkla kamera picker açıldı.

Sonra düzeltme yapıldı:

- `PhotoSourceSheet.sourceButton` içine:
  - `.accessibilityElement(children: .combine)`
  - `.accessibilityLabel(title)`

Tekrar test:

- `Galeriden seç` label ile çalıştı.
- iOS Photos picker açıldı.

Sonuç:

- Düzeltme sonrası geçti.
- Commit alındı: `48c26e6 Fix quick scan sheet accessibility labels`

### Galeri -> Annotate

Kontrol:

- Galeriden bir görsel seçildi.
- Annotate ekranı açıldı.
- Toolbar görünür:
  - Kutu
  - Daire
  - Ok
  - Çiz
  - renkler
- `İşaretli alanları analiz et` görünür.

Sonuç:

- Geçti.

### Annotate -> Canvas Sheet

Kontrol:

- `İşaretli alanları analiz et` butonuna basıldı.
- `AI Odaklı Analiz` sheet'i açıldı.
- Canvas kartları ve Pro kilitleri görünür.

Sonuç:

- Geçti.

Pürüz:

- Canvas sheet X butonu accessibility label ile yakalanmadı.
- Label `Pencereyi kapat` idi; `Kapat` olarak düzeltildi.
- Commit alındı: `48c26e6 Fix quick scan sheet accessibility labels`

### Auth / Email OTP

Kontrol:

- Resend + Supabase SMTP sonrası Email OTP akışı canlı denendi.
- OTP uzunluğu Supabase Dashboard'da 6 haneye indirildi.
- App tarafında OTP verify sırası ve invalid/expired fallback akışı düzeltildi.
- OTP kutuları tek hidden input ile otomatik ilerleyen, caret/glow gösteren yapıya taşındı.
- 6 hane tamamlanınca otomatik doğrulama çalışıyor.
- Hata durumunda tekrar kod gönderme linki gösteriliyor.
- Google OAuth `Vazgeç` sonrası teknik `WebAuthenticationSession` hatası kullanıcıya gösterilmiyor.

Sonuç:

- Geçti.

Commitler:

- `53094d2 Improve email OTP entry and errors`
- `336d40b Fix email OTP verification flow`
- `79253dd Polish email OTP input experience`
- `92e47cc Polish email placeholder copy`
- `e903268 Polish email field prompt`
- `8829c0b Ignore cancelled OAuth sign-ins`

### Result / Reports

Kontrol:

- Result ekranından PDF rapor oluşturma denendi.
- İlk denemede Storage upload sırasında transient `network connection was lost` hatası görüldü.
- Rapor upload için 3 denemeli retry eklendi.
- Tekrar testte PDF preview açıldı ve Reports tabında yeni standart rapor göründü.

Sonuç:

- Retry sonrası geçti.

Commit:

- `cc76b9b Retry transient report uploads`

### Free Limit Dolu Senaryosu

Kontrol:

- Free demo kullanıcıyla `RISKDETECTED_ENABLE_DATA_TEST_SIMULATION=true` ve `SIMULATE_DATA_ERROR=quota_exceeded` kullanılarak günlük limit dolu senaryosu çalıştırıldı.
- Home upload alanında `Günlük free limit doldu` durumu ve `0/2` quota bilgisi göründü.
- `Taramayı Başlat` ile destek kodlu Pro ekranı açıldı.
- Orta `Tara` butonu `Günlük limit doldu` uyarısını gösterdi.
- Uyarıda `Tamam` ve `Pro'ya geç` aksiyonları göründü.

Sonuç:

- Geçti.

### Free Kullanıcı Pro Canvas Kilidi

Kontrol:

- Quota simülasyonu kapalı Free demo kullanıcıyla galeri -> annotate -> Canvas sheet akışı çalıştırıldı.
- Pro canvas kartlarında `PRO` ve `KİLİTLİ` badge'leri göründü.
- `Makine, PRO, KİLİTLİ` kartına basınca ilk denemede Pro ekranı açılmadı.
- Sebep: Canvas sheet açıkken aynı anda `fullScreenCover` tetikleniyordu.
- `onUpgradeRequested` akışında önce Canvas sheet kapatılıp kısa gecikmeyle Pro ekranı açılacak şekilde düzeltildi.
- Tekrar testte kilitli Pro canvas'a basınca Pro ekranı açıldı.

Sonuç:

- Düzeltme sonrası geçti.

### Canvas Sheet Max 2 Seçim

Kontrol:

- Free kullanıcıyla Canvas sheet içinde `Genel` seçili durumdayken `Elektrik` seçildi.
- Üçüncü Free kart olarak `Uyarı levhaları` seçilmeye çalışıldı.
- Seçim sayısı 2'nin üzerine çıkmadı.

Sonuç:

- Geçti.

### Result İndirme / Paylaşma İkonları

Kontrol:

- Analizler tabından tamamlanmış bir analiz Result ekranında açıldı.
- Üstteki `Raporu indir` ikonu denendi.
- İlk denemede PDF oluşturulduğu halde arşiv kaydı hatası preview akışını kesiyordu.
- Result ve Reports PDF üretim akışında arşiv kaydı başarısız olsa bile üretilen dosyanın açılması/paylaşılması sağlandı.
- Tekrar testte `Raporu indir` PDF preview açtı.
- `Raporu paylaş` native paylaş panelini açtı.

Sonuç:

- Düzeltme sonrası geçti.

### Reports PDF Preview / İndirme

Kontrol:

- Reports tabında kayıtlı standart PDF raporu açıldı.
- `DocumentPreview` açıldı.
- Preview içinde `Önizlemeyi kapat` ve `Dosyayı indir veya paylaş` aksiyonları göründü.
- `Dosyayı indir veya paylaş` native paylaş/kaydet panelini açtı.

Sonuç:

- PDF için geçti.
- Kayıtlı XLSX dosyası olmadığı için XLSX preview canlı tıklaması bu turda yapılamadı; Excel üretim QA'sından sonra tekrar kontrol edilecek.

## Tamamlanmayan QA

Kullanıcı devamını sonraya bıraktığı için aşağıdaki QA maddeleri durdu:

- Rapor oluştur sheet Excel seçimi.
- Reports XLSX preview ve indirme akışı.
- Dark mode hızlı pass.
- Profil düzenleme/logo kaydı.
- Ana sayfa rapor preview X/indir.

## Yeni Sohbette QA'ya Nereden Devam Edilecek?

1. Rapor oluştur sheet Excel seçimini test et.
2. Excel dosyası oluşunca Reports XLSX preview ve indirme akışını test et.
3. Ana sayfa rapor preview X/indir akışını tekrar kontrol et.
4. Dark mode hızlı pass'i tamamla.
5. Profil bilgi kaydetme, logo seçimi ve geçmiş analiz/rapor routing'i test et.
