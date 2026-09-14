# NOVA İstatistikler

İstatistikler menüsü, iOS pilotta gerçek verileri okuyan bir sayfaya bağlandı. Yeni servis yalnızca okur; eğitim, analiz, abonelik, kota veya evrak kaydı değiştirmez.

## Sayfa

- Tüm aktif firmalar / firma seçimi; bu ay, 3, 6 ve 12 takvim ayı.
- Bugünkü aktif firma, personel ve işyeri sayısı.
- Dönemde tamamlanan fotoğraf analizleri, gerçekleşen eğitimler, tekil eğitim alan personel ve kişi × eğitim kayıtları.
- Analiz/eğitim seçilebilen, aya dokununca toplam gösteren aylık grafik; boş aylar korunur.
- Bugünkü açık, gecikmiş, doğrulamada uygunsuzluklar ve önem dağılımı. İyileştirme önerileri dahil değildir. Dönem açılan/kapanan kayıtları ayrıca açıklanır.
- Evrak takibinin kendi güncel geçerli/eksik/yaklaşan/dolmuş sayıları.
- Firma satırına dokunarak filtreleme, ilgili modülleri açma, yenileme, yükleniyor/boş/hata durumları.

## Sayım sözleşmesi

`isg_statistics_v1(p_company, p_months)` mevcut oturum ve P05 pilot/firma okuma yetkilerini denetler. Özel işlev private şemadadır; public giriş security invoker kullanır. Anon erişimi yoktur. Yanıt sahibi/filtre/sürüm ve toplamlar istemcide de kontrol edilir. Hesap değişiminde ekran durumu yenilenir; eski isteğin cevabı yeni filtreye taşınmaz.

Dönem, İstanbul saatine göre ilgili ilk ayın 1. günü ile bugün arasındadır. Fotoğraf analizinde tamamlanma tarihi (eski kayıtta yoksa oluşturma tarihi), eğitimde gerçekleşen tarih kullanılır. Çok firmalı tek etkinlik bir eğitim sayılır; grafikte ilgili dönemdeki ilk firma tarihiyle yer alır. Planlanmış, iptal ve silinmiş eğitimler sayılmaz. Firma seçilmediğinde hesaba ait firmasız fotoğraf analizleri dahildir; diğer firmalara bağlı kayıtlar dahil değildir. Arşivlenmiş firmalar tüm sayımlardan çıkarılır.

Firma/personel/işyeri ve açık/gecikmiş/evrak durumları bugünkü stoktur, tarih filtresiyle geçmiş durum iddiasına dönüştürülmez. Kapanan değer, halen kapalı olan kayıtlardan bu dönemde kapananları sayar; tekrar açılan bir kaydın önceki kapanışını tarihsel olay gibi göstermez.

Uygunsuzluk ve evrak modülleri dar canlı pilotta henüz kurulmamışsa ilgili alanlar `null` döner ve açıkça kullanılamıyor gösterilir. Bu modüllerin mevcut servisleri açıldığında istatistikler otomatik okuyabilir. Eksik kaynak sıfır olarak gösterilmez. Bu teslim başka modüllerin migration paketlerini topluca açmaz.

## Doğrulama

- İzole PostgreSQL 17: 251 fotoğraf analizi, 205 uygunsuzluk, çok firma tek eğitim, tekil kişi, kaynak yokluğu, firma/hesap ayrımı, geçersiz dönem ve kapalı pilot testleri geçti.
- Gerçek SQL yanıtı Swift modeline çözüldü; sahip/filtre uyuşmazlığı reddi, toplam ve tarih kontrolleri geçti.
- Canlı dar migration `20260914170954_isg_statistics_read` uygulandı. Candidate: `20260914170138_isg_statistics_read.sql`; pilot mirror aynı içeriktedir.
- Canlı authenticated rol testi: dört dönem, her okunabilir firma, aylık toplam uyumu ve bilinmeyen firma reddi geçti. Test iş verisi yazmadı.
- Supabase güvenlik danışmanında yeni statistics nesnelerine ilişkin bulgu yok.

İstatistiklerin bu teslimdeki uygulama yüzeyi iOS NOVA pilotudur. Android için mevcut davranış değiştirilmedi.

- Arayüz testleri: firma seçimi, 3/12 ay filtresi, yatay grafik kaydırma, ay seçimi, uygunsuzluk ekranına geçiş, boş veri ve hata sonrası yeniden deneme geçti. 2 test başarılı; son grafik düzenlemesinden sonra etkileşim testi tekrar geçti.
- Grafik ve ekran görüntüleri `artifacts/statistics/` altında sentetik verilerle saklandı; canlı hesaba örnek veri yazılmadı.
- İstanbul ay başlangıcının iki tarafı, silinmiş eğitim ve arşivlenmiş firma dışlama testleri geçti.
- iOS cihaz derlemesi 2.0.3 (102) başarılı; istatistik ekranını içeren ilk paket telefona kuruldu ve açıldı. Son 12 aylık yatay grafik düzenlemesinin yeniden kurulumu cihaz bağlantısındaki zaman aşımı nedeniyle tamamlanamadı. Bu son düzenleme kaynakta, derlenmiş pakette ve geçen simülatör testinde mevcut; yeniden cihaz bağlantısı bekliyor.
