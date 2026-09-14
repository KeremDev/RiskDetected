# NOVA — 14 Eylül kompakt arayüz çalışması

Durum: **İlk arayüz paketi uygulandı; kullanıcının dokuz maddelik talebinin tamamı bitmedi.** Canlı veritabanı/rollout değiştirilmedi. Telefon için yeni kurulum yapılmadı; son kurulu sürüm 2.0.3 (92).

## Uygulananlar

- Üst başlık boşluğu azaltıldı; ortak geri çizimi 14 pt, dokunma alanı 44 pt.
- İşyeri/departman/görev/dış firma ve geçmiş sayfalarına ampullü amaç açıklamaları eklendi.
- Dizinlerde arama ve kompakt arşiv filtresi; sorgu varken kalan sayfalar da okunur. UUID/kod karttan kaldırıldı; sunucu kimlikleri değişmedi.
- Tam genişlik boş kayıt kartı. Düzenle ve Bilgi geçmişi yan yana. “Tarihli bağlam” kullanıcı kontrolünde “Bilgi geçmişi” olarak adlandırıldı; geçmiş tarihlerdeki tehlike sınıfı vb. bilgileri korur.
- Firma özeti hafif yeşil yüzeyli; ikon + değer etiketleri, uygun genişlikte üç sütun. Erişilebilirlik okuyucusunda anlamlı etiketler korunur. Bilinmeyen değerler hâlâ —, sahte sıfır/skor yok.
- Firma formunda tekrar eden alan başlıkları kaldırıldı; tek placeholder, Firma e-posta, uyumlu seçim fontu. Yeşil kaydet düğmesi boş alanlarda doğrulama gösterir; yetki/yükleme/belirsiz sonuç korumaları kaldırılmadı.
- Personel ekleme sheet oldu; firma alt başlığına ikon eklendi. Ad soyad tekrarı ve “Boş bırakabilirsiniz” metni kaldırıldı; yeşil doğrulamalı kaydet.
- Ortak form klavye kapatma yüzeyi: alan dışı dokunma, kaydırma ve Tamam desteği; girilen değer silinmez.
- Ortak 2,5 saniyelik başarı kutlaması; dim arka plan, çizgi ikonlar, küçük giriş animasyonu, Reduce Motion ve VoiceOver duyurusu. Firma/personel kayıtları için doğrulanmış commit sonrasında çağrılır.
- `inactive → active` artık tüm workspace'i sıfırlamaz. Gerçek `background → active`, oturum değişimi ve manuel erişim yenilemesi güvenlik kontrolünü sürdürür. **Gerçek arka plan dönüşünde açık ekranın korunması ayrıca çalışılmalı**; bu değişiklik güvenlik revalidation'ını kaldırmaz.

## Açık işler — tamamlandı sayılmamalı

1. Firma düzenle formu + kapsamlı, sürüm kontrollü, idempotent pilot update RPC. Önceki pilot firmanın boş sektör bilgisi buradan girilebilmeli.
2. Sorumlu kişinin opsiyonel e-posta/telefon alanlarının kalıcı ve atomik kaydı. Mevcut V1/V2 bekleyen oluşturma istekleri bozulmamalı.
3. Galeriden logo seçme, kırpma, boyutlandırma/sıkıştırma, yetkili Storage yükleme; başarısız yükleme ve artık dosya temizliği.
4. Personelin opsiyonel görev/unvanının kalıcı kaydı ve ilgili dizinle ilişkisi; tarihli görevlendirme geçmişi uydurulmamalı.
5. CSV şablonu, dosya seçimi, kolon eşleştirme, önizleme/hata listesi, tekrar yüklemede çift kayıt önleme ve toplu aktarım. XLSX ayrıca desteklenecekse açıkça doğrulanmalı.
6. Eğitim/uygunsuzluk gerçek create akışları bağlandığında ortak kutlama çağrısı. Şu an bu modüller canlı pilot UI'ında bağlı değil.
7. Gerçek arka plan dönüşünde yetki yeniden kontrol edilirken taslak/konum korunması; erişim iptali ve eski callback reddi bozulmamalı.
8. Tüm ekleme/düzenleme sayfalarına açıklama/tek-placeholder yaklaşımının kalan yayılımı; gerçek telefon + büyük yazı + dark mode kabulü.
9. Sonraki cihaz build'i ve telefon kurulumu. Şu an yalnız simülatör/yerel doğrulama.

## Doğrulama

- 24 Node testi PASS (native pilot, yerelleştirme, tasarım, oturum, paket korumaları).
- Bunların içinde 34 Swift pilot create kontrolü ve 27 scene lifecycle kontrolü PASS.
- Beş XCUI testinde firma formu/özet, dizin araması/kod gizleme, personel sheet, kutlama görünme/otomatik kapanma, pilot dışı legacy root ve erişim yok durumu kontrol edilir.
- İlk ek XCUI koşusunda iki test-seçici sorunu bulundu: editor geri kimliği ve kutlamanın accessibility eleman türü. Ayrı editor kimliği ve türden bağımsız kimlik sorgusuyla giderildi. Son klavye yüzeyi değişikliği ayrıca yeniden test edilir.
- Son tekrar: **5/5 XCUI PASS**, boş alana dokununca klavyenin kapandığı ve yazılan adın korunduğu da doğrulandı. 11 mevcut PaywallDesignKit actor uyarısı var; yeni derleme hatası yok. Backend sentetik/upgrade testleri bu tur yeniden çalıştırılmadı; DDL değişikliği yok.

## Devam ederken

Son XCUI kanıtı: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-09-13T21-46-43-328Z_pid84322_1d5aacf0.xcresult`. Ekran görüntüleri: `output/isg/pilot/ui-compact-final/`.

[NOVA tasarım ilkeleri](NOVA_UI_PRINCIPLES.md) bütün yeni NOVA ekranlarında uygulanmalı.

Canlı migration zinciri hâlâ `20260913201043` + `20260913205739`. Root migration klasörüne genel `db push` yapılmaz. Yeni pilot işlevleri eski istemci/pending kayıt sözleşmelerini koruyan ek migration ile, klon Auth/PostgREST/RLS testi sonrasında dağıtılmalı. Gerçek kullanıcı kayıtları QA verisi olarak değiştirilmez.

Yeni DDL öncesi kontrol: `capture_p05_deploy_checkpoint.mjs` şema listesi `private_isg` içermiyor; yeni P05 tablolarını da kapsayacak şekilde düzeltilip yeni checkpoint alınmalı. Önceki arşivler bu şemayı kapsayan tam uygulama yedeği sayılmamalı.
