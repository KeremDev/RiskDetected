# İSGADA — Seçim alanı standardı

Güncelleme: **25.09.2026**
Durum: Uygulandı (iOS ve Android). Liste filtreleri bilerek dışarıda bırakıldı (3. bölüm).

Bir kayıt ya da form alanı için tek bir değer seçtiren her yer aynı bileşeni kullanır: `NovaChoiceField`.
- iOS: `App/DesignSystem/ISG/NovaChoiceField.swift`
- Android: `core/designsystem/.../isg/NovaChoiceField.kt`

Menü tarzı `Picker`, açılır panel (`NovaChooserButton` + `NovaChooserPanel`) ve segmentli tehlike sınıfı seçimleri bu bileşene taşındı.

## 1. Kurallar

- **Hiçbir değer kullanıcı seçmeden seçili gelmez.** Alan "… seçin" yazısıyla (placeholder) başlar. Seçim yapıldıktan sonra satırın üstünde alanın adı, altında seçilen değer görünür. Örnek: yeni firmada tehlike sınıfı artık "Tehlikeli" ile başlamaz.
- **Seçim alttan açılan bir sayfada yapılır.** Sayfa başlığı ve varsa tek satırlık bir açıklama taşır; seçenekler büyük kartlardır. Dokununca işaret belirir, cihaz hafifçe titrer ve sayfa 0,22 saniye sonra kendiliğinden kapanır.
- **Açıklamalı seçenekler kart olarak çizilir:** solda renkli bir kutucuk (tehlike sınıfında 1–3 seviye çubuğu), ortada başlık ve açıklama, sağda işaret dairesi. Kişi, işyeri gibi açıklamasız seçenekler sade satır olarak çizilir (52 pt).
- **Uzun listelerde arama vardır.** Seçenek sayısı 8'i geçince ya da liste büyüyebiliyorsa (`searchable`) sayfa tam ekran açılır ve üstte arama kutusu olur. Liste yalnızca ekranda görünen satırları çizer (tembel liste).
- **İsteğe bağlı alanlarda "yok" satırı vardır (`noneTitle`).** Sayfanın ilk satırı seçimi boşaltır. Metin alanın kendi eski metnidir ("Firma seçmeden devam et", "Kişisel dosya", "Tüm firma"); yoksa ortak "Seçilmedi" (`NovaChoiceText.none`).
- **İki görünüm vardır.** Bölücülü bir kartın içinde sade satır, çerçeveli kutulardan oluşan bir formda kutulu satır (`boxed`). Kutulu satır diğer form kutularıyla aynı arka planı kullanır.
- **Seçim zorunluysa adım ilerlemez.** Hata mesajı alanı adıyla söyler. Seçim yapılınca mesaj kalkar.
- **Kimlikler:** satır `identifier`, seçenekler `<identifier>.option.<sıra>`, yok satırı `<identifier>.none`, arama `<identifier>.search`.
- **Metinler:** bileşenin kendi metinleri `localizable.nova.choice.{none,search,empty}`. Tehlike sınıfı seçenekleri `NovaHazardChoice`'ta toplanır, anahtarlar `localizable.nova.hazard.choice.*`. Açıklamalar mevzuattaki karşılıklardır:
  - Risk değerlendirmesinin yenilenmesi 6/4/2 yıl (Risk Değerlendirmesi Yönetmeliği md. 12).
  - Uzman sınıfı en az C/B, çok tehlikelide A.

## 2. Nerelere uygulandı

| Platform | Kapsam |
|---|---|
| iOS | 60 kadar alan. Firma ekleme sihirbazı (tehlike sınıfı, işyeri tehlike sınıfı, görevi). OSGB firma düzenleyicisi (yeni firmada tehlike sınıfı boş başlar ve zorunludur). Firma düzenleme formları. Dizin (tehlike sınıfı, ilişki türü). OSGB çalışma alanı düzenleyicileri (atama, kayıt oluşturma, acil durum planı, dosya, uygunsuzluk/risk/ekipman, eğitim). Modül düzenleyici. Eğitim oturumu. Randevu, tatbikat, acil durum, ekipman, dosya kütüphanesi, Katip, KKD ve risk sayfaları. Analiz önem derecesi. Kontrol listesi iptal nedeni ve işyeri. Evrak kapsamı. Risk ve evrak sihirbazlarının firma/işyeri alanları. Rapor merkezinin firma alanı. |
| Android | 27 OSGB formu alanı: `OsgbPicker` artık bu bileşeni çiziyor. Buna ek olarak 34 alan eski açılır panelden taşındı ve 7 form alanı eski filtre bileşeninden. Tehlike sınıfı: firma ekleme, işyeri, OSGB firma düzenleyicisi, firma düzenleme ve dizin. Firma sihirbazının görevi alanı. |

## 3. Dokunulmayanlar (bilerek)

- **Liste filtreleri:** firma, durum, tür ve sıralama filtreleri. Bunlar form alanı değil; ayrı bir tasarım kararı gerektirir.
- **Segmentli seçimler ve sekmeler:** 2–4 seçenekli yöntem, kabul/ret, sekmeler gibi.
- **Menüler ve özel seçiciler:**
  - İşlem menüleri.
  - Çoklu seçimler.
  - Sihirbaz içindeki satır içi cevap seçenekleri: risk skor çubukları, KKD birimi, ekipman sonucu, acil durum rol çipleri.
  - Tam ekran seçiciler (`CompanyPickerSheet`, `NovaCompanyCreateFlow`, eğitim türü seçimi).
- **Android'deki satır içi radyo listeleri:** analiz işyeri, elle uygunsuzluk firma/işyeri, randevu görev/dayanak.
- **Sayfalanan ya da yazarak aranan seçiciler:**
  - OSGB uzman seçimi.
  - Dizin ilişki alanlarının sayfalanan listesi ("Diğer kayıtlar").
  - Departman yazarak arama.

## 4. Sonradan dönüştürülen dosyalar

25.09.2026'da başka bir oturum bu dört iOS dosyasını düzenlediği için ilk turda atlanmıştı; aynı gün, o oturumun değişikliklerine dokunmadan dönüştürüldü:

| Dosya | Alanlar |
|---|---|
| `IsgWorkspaceDomainScreen.swift` | Kontrol maddesi, Önem, İşyeri, Süre kaynağı, Sonuç/Durum (`picker()` yardımcısı) |
| `IsgWorkspacePersonnelScreen.swift` | İşyeri, Departman ("Departman yok"), İlişki, Dış firma / İşyeri / Personel, Departman / Görev / Dış firma sözleşmesi ("Seçilmedi") |
| `NovaPilotProcessGate.swift` | Süreç alanlarının seçenekli alanları, işyeri / dış firma ("Seçilmedi"), ilgili kayıt penceresindeki kayıt türü |
| `NotebookDestination.swift` | Hatırlatma tekrarı |

İlişki türü önceden ham kodlarla ("subcontractor") görünüyordu; artık dizindeki adlarla ("Alt işveren", "Yüklenici", "Tedarikçi", "Diğer") görünür.
