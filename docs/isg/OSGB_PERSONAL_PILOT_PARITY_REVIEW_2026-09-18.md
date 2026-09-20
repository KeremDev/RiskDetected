# OSGB – Bireysel Pilot Nova Eşitlik İncelemesi

Tarih: 18 Eylül 2026
Kapsam: iOS Nova arayüzü, tenant servisleri, staging veritabanı ve fiziksel iPhone paketi

## Sonuç

OSGB yöneticisi ve OSGB uzmanı için operasyonel kayıt akışları, bireysel Pilot Canlı hesabındaki Nova davranışlarıyla aynı ürün modeline taşındı. Ayrı veri servisleri kullanılmaya devam ediyor: bireysel hesap sahibi sınırı korunurken OSGB kayıtları workspace, firma, üyelik sürümü ve firma ataması üzerinden yetkilendiriliyor.

Üretim projesinde migration, veri veya rollout değişikliği yapılmadı. Bu çalışmanın sunucu değişikliği yalnızca izole staging projesi `qlymhrrlhklcudveknih` üzerinde uygulandı.

## Eğitim eşitliği

- Eğitim ekleme dört akordiyon başlığına ayrıldı: eğitim bilgisi, tarih/yöntem, eğitici ve katılımcılar.
- Kullanıcı yayımlanmış kayıtlı eğitimlerden seçim yapıyor.
- Eğitim konuları ve konu süreleri seçilen kayıttan otomatik geliyor; toplam dakika otomatik dolduruluyor.
- Firma personeli aranıp çoklu seçilebiliyor.
- Kaydetme, plan kaydı üretmeden gerçekleşen eğitimi ve katılımı tek işlem olarak tamamlıyor.
- Kullanıcıya standart başarı sunumu gösteriliyor.
- OSGB operasyon ekranında yıllık eğitim planlama akışı gösterilmiyor. Müfredatın tenant tarafındaki yönetim altyapısı kayıtlı eğitim kaynağı olarak korunuyor; operasyonel eğitim ekleme akışı planlama ekranına yönlenmiyor.

## Risk değerlendirmesi eşitliği

- İlk değerlendirme, tam yenileme, kısmi revizyon ve bilgi düzeltmesi ayrıldı.
- Kısmi revizyon ve bilgi düzeltmesinde ilk değerlendirme tarihi korunuyor.
- Tehlike sınıfına göre 2/4/6 yıllık süre hesabı kesinleştirme sırasında uygulanıyor.
- Açık taslak düzenlenebiliyor veya gerekçe ile iptal edilebiliyor.
- Taslak düzenlemeleri `edit_revision` ile iyimser kilit kullanıyor; eski ekrandan kaydetme sürüm çatışması veriyor.
- Kayıt ayrıntısı açılırken liste özeti kullanılmıyor; yetkili tenant detay çağrısıyla tüm sürüm geçmişi yeniden yükleniyor.
- İptal edilen taslak, kesinleşmiş değerlendirmenin durumunu yanlışlıkla “iptal” olarak göstermiyor.

## Periyodik kontrol eşitliği

- Ekipman ekleme katalog, ekipman bilgisi ve ilk kontrol/rapor olmak üzere üç akordiyon adımına ayrıldı.
- Kayıtlı ekipman türü ve varsayılan kontrol süresi katalogdan geliyor.
- Kontrol tarihi, sonuç, sonraki kontrol tarihi, kontrolü yapan, rapor numarası, İSG-KATİP beyanı, not ve arşiv raporu aynı akışta kaydediliyor.
- Firma özel kontrol süresi ve uzman istisna notu düzenlenebiliyor.
- Ekipman bilgisi düzenleme ve envanterden arşivleme ayrıntı ekranından yapılabiliyor.
- Ayrıntı ekranı kontrol ve rapor geçmişini tenant detay çağrısından yüklüyor.
- Süresi geçen, olumsuz, takipsiz, yaklaşan ve güncel istatistikleri Nova istatistik kartı biçiminde gösteriliyor.

## Diğer operasyonel ekranlar

- Acil durum planı, atamalar, kurul toplantıları ve risk değerlendirmesi listelerinde bireysel Nova başlık, yardım metni, boş durum ve istatistik düzeni kullanılıyor.
- Eğitim, risk ve periyodik kontrol için genel metin formu kaldırıldı; her modül kendi iş kurallarını taşıyan Nova editörüne yönleniyor.
- Liste satırına dokunulduğunda ağır geçmiş dizileri içeren yetkili ayrıntı yükleniyor.
- Ekrandaki durum, alan ve metrik kodları kullanıcıya Türkçe gösteriliyor.
- Firma personeli, işyerleri ve kayıt ilişkileri workspace servislerinden alınıyor; bireysel `Nova*Service` veya eski sahip tablosuna kaçış bulunmuyor.

## Bilinçli OSGB farkları

- Yönetici bütün workspace firmalarını görebilir; uzman yalnızca aktif ataması olan firmaları görebilir.
- Firma oluşturma, işyeri/departman yönetimi, uzman atama ve firma profili gibi yönetim işlemleri rol denetimine tabidir.
- Her istek workspace, firma, üyelik ve yetki sürümü ile sunucuda yeniden denetlenir.
- OSGB uzmanı bireysel pilotla aynı kayıt ekranlarını görür; yazma yetkisi olmayan rolde ekleme/düzenleme eylemleri sunulmaz.
- Bireysel kullanıcıların servisleri, tabloları ve mevcut canlı çalışma şekli değiştirilmedi.

## Staging veritabanı doğrulaması

`20260918020000_osgb_personal_pilot_parity.sql` staging'e uygulandı. Önce aynı aday `BEGIN/ROLLBACK` içinde sözdizimi ve şema uyumu açısından doğrulandı.

Gerçek OSGB pilot oturumuyla şu zincir çalıştırıldı:

1. QA işyeri oluşturma.
2. Tam değerlendirme taslağı oluşturma.
3. Taslağı düzenleme ve `edit_revision` artışını doğrulama.
4. Taslağı gerekçe ile iptal etme.
5. Yeni tam değerlendirmeyi 2 yıllık süreyle kesinleştirme.
6. Kısmi revizyon açma, düzenleme ve iptal etme.
7. Yetkili ayrıntı çağrısında kesin ve iptal edilmiş sürümleri birlikte doğrulama.
8. QA işyeri ve risk kayıtlarını temizleme.

Sonuç: tüm adımlar geçti; üretim hedefi kullanılmadı.

## Otomatik doğrulama

- iPhone 17 Pro simülatör derlemesi: başarılı.
- Fiziksel iPhone arm64 derlemesi: başarılı.
- Hedefli workspace/API/eşitlik testleri: 23/23 geçti.
- Tam ISG Node regresyonu: 1002/1002 geçti.
- Function-test-map kaynak parmak izleri: güncel ve geçerli.
- Candidate manifest: staging seviyesi `20260918020000`; admin UI adayı kararlaştırıldığı gibi hariç.
- `git diff --check`: temiz.

## Fiziksel iPhone teslimi

- Uygulama: İSGADA
- Sürüm: `2.0.3 (122)`
- Bundle kimliği: `com.riskdetected.app.osgbpilot`
- Ortam: `https://qlymhrrlhklcudveknih.supabase.co`
- Derleme koşulu: `DEBUG NOVA_PILOT_BUILD`
- Kurulum: aynı bundle kimliğiyle mevcut OSGB pilot uygulamasının üzerine
- Başlatma: başarılı; cihazdaki build 122 süreci çalışıyor

## Deneme odağı

Telefon denemesinde önce Eğitim > Eğitim Ekle, Risk Değerlendirmesi > Kayıt Ekle ve Periyodik Kontroller > Ekipman Ekle akışları kontrol edilmelidir. Ardından aynı firmada yönetici ve atanmış uzman oturumları karşılaştırılmalı; ekran düzeni aynı kalırken yalnız rol kaynaklı eylem farklarının oluştuğu doğrulanmalıdır.
