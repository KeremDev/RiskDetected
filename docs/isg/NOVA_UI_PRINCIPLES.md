# NOVA arayüz ilkeleri

14 Eylül 2026 kullanıcı geri bildirimi; yeni NOVA sayfalarının tamamında uygulanır.

- Kompakt, kullanıcı odaklı yerleşim; gereksiz üst boşluk ve tekrar eden etiket yok.
- Çizgi ikonlar; dekoratif renkli ikon kutuları yok. İkon çizgisi duruma göre renkli veya siyah olabilir. İşlevsel düğme ve kart yüzeyleri renklendirilebilir.
- Ortak geri kontrolü: küçük çizim, en az 44 pt dokunma alanı. Büyük yazı erişilebilirliği korunur.
- Sayfanın amacını kısa ampul ikonlu açıklama anlatır. Teknik UUID/kodlar kullanıcı kartlarında gösterilmez.
- Formlarda ikon + geçici placeholder; erişilebilir alan adı ayrıca korunur. Boş alana dokunma ve klavye Tamam ile odak bırakılabilir.
- Yeşil kaydet kontrolü, eksik alanlarda anlaşılır doğrulama gösterir. Yetkisiz, yüklenmekte olan veya sonucu belirsiz işlemler etkin gösterilmez.
- Yeni firma düğmesi son firma kartının hemen altında; alt gezinme çubuğunun arkasında değil.
- Başarı kutlaması yalnızca sunucu sonucu kesinleşince, 2–3 saniye; azaltılmış hareket tercihine uyar.
- Geçici inactive/active geçişi ekranı sıfırlamaz. Oturum değişimi ve erişim iptali güvenlik sınırıdır.
- Logo yükleme, firma düzenleme, sorumlu kişi iletişim bilgileri ve CSV toplu personel aktarımı sahte kayıtlarla değil, doğrulanmış yetkili servislerle tamamlanır.
# 14 Eylül ek tasarım kararı

- Firma detayında bağımsız skor kartı yok; küçük halka ve değer firma özetinin sağında.
- Çalışan Temsilcisi / Destek Elemanları bağımsız başlıklardır.
- Bölüm durumları sağda, chevron sonrasında: kırmızı X Eksik / yeşil tik Tamamlandı. Başlık altında ikinci durum satırı yok.
- Firma/personel girişleri merkez popup; arka plan blur + karartma, belirgin X kapatma. Alttan açılan sayfa görünümü tercih edilmez.
- Teknik bilinmeyen veri ile boş kayıt modelde ayrılmaya devam eder; görünüm sadeleşmesi sahte skor üretme yetkisi değildir.
- Son düzeltme: tüm accordion'lar kapalı başlar; açılan kart açık mavi. Durum rozeti chevron'un **solunda**, kırmızı/yeşil zeminlidir. Popup yüksekliği içerikten ölçülür, kullanılabilir ekranı aşarsa kaydırılır.
