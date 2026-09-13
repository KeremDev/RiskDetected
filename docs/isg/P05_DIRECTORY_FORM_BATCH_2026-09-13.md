# P05 — tarihli rehber form paketi

13 Eylül 2026. İki native platform birlikte değiştirildi; küçük düzenlemelerde test çalıştırılmadı, paket sonunda toplu test/düzeltme yapıldı. Bu kayıt P05'in bütünüyle kapandığı anlamına gelmez.

## Tamamlananlar

- Gerçek Gregoryen tarih denetimi: artık yıl/yüzyıl, ayın gün sayısı, sıfır yıl, Unicode rakam ve otomatik tarih normalleştirmesi koruması; yalnız `YYYY-AA-GG`.
- Dış firma işyeri ilişkisi için boş bitiş serbest; dolu bitiş başlangıçtan kesin sonra. Aralık `[başlangıç, bitiş)`.
- Context/görevlendirmede seçilen önceki dönem içinde bölme: başlangıcına eşit/önce veya bitişine eşit/sonra tarih reddi. Kapanmış dönem içinde geriye dönük geçerli bölme korunur.
- Üst departman seçicisinde kendisi, yüklenmiş alt/torun departmanları, arşivli ve farklı işyerinin departmanları elenir. Döngülü gelen veri sonsuz döngü oluşturmaz. Sayfalanmış listenin bilinmeyen atalarını ve yarışları yine sunucu denetler.
- Aynı işyerini yeniden seçmek departmanı silmez; gerçekten farklı işyeri seçmek yalnız bağlı departman alanlarını sıfırlar.
- Mevcut dış firma işyeri ilişkisinde firma/işyeri/başlangıç salt okunur; bitiş/açıklama düzenlenebilir. Sunucunun değişmezlik kuralıyla uyumlu.
- Seçenek yüklemesi sürerken veya başarısızken yeni gönderim kapalı. Yeniden yükleme form taslağını korur; sayfa birleştirme aynı kaydı çoğaltmaz.
- Liste yenilemesinde eski ilk sayfa temizlenir; hata/yükleme sırasında eski karttan düzenleme başlatılamaz. Bekleyen işlemli editörden geri dönüşte liste/journal yeniden okunur.
- iOS form klavyesi Bitti ile veya etkileşimli kaydırmayla kapanır. Otomasyon için alan/seçenek/kaydet kimlikleri iki platformda eklendi.
- Gri sayfa, beyaz yuvarlak kartlar ve NOVA yazı/ikon bileşenleri korundu. Basit personel girişine tarih veya zorunlu departman eklenmedi.

## Toplu doğrulama

| Katman | Sonuç | Kapsam sınırı |
|---|---|---|
| Android | Designsystem 373 + data 615 + profile 11 = 999 başarılı; Debug APK build başarılı | Data görevi değişmediği için Gradle UP-TO-DATE; Compose testleri Robolectric, cihaz/SDK/DB birleşik E2E değil |
| Swift kurallar | 46 kontrol başarılı; CI'a eklendi | Üretim form kuralları, saf yerel test |
| iOS Simulator | 5/5 başarılı; 3 yeni rehber, 2 mevcut personel/history/read-only testi | Gerçek üretim ekranları, sentetik repository; tam UI suite bu tur yeniden çalıştırılmadı |
| Ana iOS | Debug Simulator build başarılı | İmzalı mağaza/cihaz build'i değil |
| Node | 206/206 başarılı | NOVA kaynak/font testleri bu sayıya dahil; ayrı toplanmaz |

İlk iOS koşusunda 4/5 geçti; klavye açıkken genel ekran kaydırması kaydet düğmesine ulaşamadı. Üretim formuna klavye kapatma desteği ve teste hedefli scroll eklendi. Aynı beşli tekrar koşusu 5/5 geçti. Başarısız ilk koşu tam geçiş olarak sayılmadı.

[Çalıştırma yolları, sonuçlar ve kaynak hash'leri](evidence/P05_DIRECTORY_FORM_BATCH_2026-09-13.json).

## P05'te hâlâ açık

Gerçek native yönetim sahibi → SDK → izole Auth/DB zincirinde iki platform CRUD/receipt/event, hesap ve firma değişimi, foreground entitlement/rollout kaybı, commit-sonrası yanıt kaybı ve yeniden başlatma birleşik kabulü. Bütün tarihli/hiyerarşik ekran matrisi de bitmiş değil: çoklu sayfa/reparent, context/assignment çakışması ve işveren akışlarının tamamı gerekir. Backend testleri veya bu ekran alt kümesi bunların yerine geçmez. P06 ve sonraki fazlar bu tur tamamlanmış sayılmadı.

Canlı migration, rollout, abonelik, uygulama kimliği veya müşteri verisi değişmedi. Önceki kanıt dosyası tarihsel olarak korundu.
