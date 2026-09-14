# Firma kartı ve merkez popup — 14 Eylül

Build 93 telefon geri bildirimlerine göre yerel revizyon. Yeni telefon kurulumu veya canlı backend dağıtımı değildir.

## Uygulanan

- Çalışan Temsilcisi ve Destek Elemanları, Firma Bilgileri dışına bağımsız başlık olarak taşındı. Firma Bilgileri logo/personel ve kompakt dizin girişlerini korur.
- Dizin girişleri 9 pt padding / 30 pt içerik yüksekliğine küçültüldü; dokunma alanı toplam 48 pt.
- Accordion başlıklarında doğrudan SF Symbols çizgi ikonları siyah/temaya uygun metin renginde; eski ikon eşleme tablosunun dolu ikon eşleşmeleri kullanılmıyor.
- Durum başlık altından sağ tarafa, chevron sonrasına taşındı. Yalnız kırmızı X Eksik / yeşil tik Tamamlandı görsel durumu var. Bilinmeyen/kontrol gerekli dahili durumları korunur; bunlardan sahte sayısal skor üretilmez. Buradaki Eksik, tamamlanmanın doğrulanmadığı anlamındadır.
- Ayrı skor kartı kaldırıldı; 76 pt halka firma kartının sağında. Mavi/mor ton, doğrulanmış skor 80 ve üzerindeyken yeşil. Firma adı büyütüldü, istatistikler 11 pt'ye sıkıştırıldı; tekrar eden tamamlanma istatistiği ve istenmeyen iki servis açıklaması kaldırıldı.
- Firma oluşturma, firma içi personel/dizin ve personel oluşturma sunumları merkez popup'a çevrildi. X kapatma, karartma, material bulanıklık, klavyeye göre kullanılabilir yükseklik. iOS 16.4+ saydam native presentation; eski sürümde opak zemin fallback.

## Tamamlanmayan istekler

- Personel oluştururken opsiyonel görev: mevcut intake sözleşmesi yalnız context/full_name/department kabul ediyor; görev alanı sunucu ve dayanıklı mutation sürümüyle genişletilmeli. Kaydedilmeyen bir giriş alanı eklenmedi.
- Firma Güncelle/Sil: mevcut pilot API listesi create/overview içeriyor; scoped update/archive endpoint'i yok. Legacy CompanyService doğrudan public tabloya yazdığı için pilot işlemin yerine bağlanmadı. İşlevsiz ikonlar tamamlandı diye sunulmadı.
- Önceki dosya/logo/atama/modül bağlantıları hâlâ açık. Kullanıcının beş maddelik talebi tamamen tamamlanmış değildir.

Beceri: SwiftUI UI Patterns; yerel popup/state ve bileşen tasarımı.

## Son doğrulama

- 25 Node testi PASS; son popup değişikliği sonrası 4 yerelleştirme testi tekrar PASS.
- Tam Xcode simülatör build ve 6 XCUI PASS: merkez popup X ile kapatma/açık accordion koruma, personel klavye ve doğrulama, firma oluşturma/kutlama, dizin arama ve legacy pilot izolasyonu.
- Popup görsel incelemesi sonrası maksimum yükseklik 560 pt'ye indirildi; aynı 6 test tekrar PASS.
- Son XCResult: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-09-13T22-43-55-064Z_pid84322_34a12f3e.xcresult`.
- Son görseller: `output/isg/pilot/centered-popup-final/`.
- Telefon build 93 değişmedi; bu tur cihaz kurulumu yapılmadı.
