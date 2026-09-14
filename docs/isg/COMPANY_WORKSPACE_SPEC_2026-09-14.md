# Firma çalışma alanı — yeni kullanıcı talebi

> Sonraki kullanıcı düzeltmesi: [Build 93 sonrası revizyon](UI_REFINEMENT_2026-09-14.md). Ayrı skor kartı kaldırıldı, halka firma özetine taşındı. Temsilci/destek bağımsız başlık, durumlar sağda Eksik/Tamamlandı, sheet görünümü yerine merkez popup. Aşağıdaki ilk yerleşim metni bu düzeltmelerle birlikte okunmalıdır.

14 Eylül 2026. Önceki kompakt UI talebine **ek** kapsamdır; firma detayındaki beş büyük gezinme kutusu yerine aynı sayfada açılan bölümler hedeflenir. Bu dosya tasarım/uygulama sözleşmesidir, tamamlanmış özellik veya canlı dağıtım kanıtı değildir.

## Sayfa düzeni

1. Ortak küçük geri düğmesi + sabit Firma Detayı başlığı.
2. Firma bilgi kartı: logo/çizgi ikon, firma adı, kısa ikonlu özet değerleri.
3. Başarı Skoru kartı: 0–100 dinamik halka ve “12 başlıktan 7’si tamamlandı” gibi kısa başlık özeti. Kullanıcı düzeltmesiyle Evraklar / Eğitim / Rapor / Firma Bilgileri şeklindeki dört kategori kaldırıldı. Referans fotoğraftaki halka NOVA font/renklerine uyarlanır; ikonların dekoratif arka planları alınmaz.
4. Yan yana Dosya Ekle ve Evrak Ekle işlemleri.
5. Açılıp kapanan ana/alt bölümler. Basit alanlar yerinde, karmaşık girişler sheet ile düzenlenir. Pencere kapanınca aynı firma, açık bölüm ve kaydırma konumu korunur.

## Bölümler ve işlemler

| Bölüm | İçerik ve etkileşim |
| --- | --- |
| Firma Bilgileri | Temel alanları yerinde düzenleme; zorunlu ad, sektör, tehlike sınıfı; isteğe bağlı iletişim ve çalışan sayısı |
| ↳ Firma Logosu | Alt bölümde galeriden seçim, kırpma, önizleme, optimize yükleme, değiştirme |
| ↳ Personel Listesi | Aramalı liste sheet'i; kişiden detaya geçiş; küçük Personel Ekle düğmesi ve ayrı ekleme sheet'i |
| ↳ Çalışan Temsilcisi | Mevcut personel seçimi veya hızlı personel oluşturup atama; doğrulanmış atama sonrasında atama yazısı önizleme/indirme |
| ↳ Destek Elemanları | Koruma, İlkyardım, Kurtarma, Söndürme ekibi seçimi; personel seçme veya hızlı oluşturma, görev atama |
| Risk Değerlendirmesi | Mevcut dosya ve tarih bilgileri, indirme/önizleme; yoksa tarihli dosya ekleme |
| Acil Durum Planı | Risk değerlendirmesiyle aynı dosya/tarih yapısı |
| Periyodik Kontroller | Ekipman kataloğu veya özel ekipman; kontrol tarihi, geçerlilik süresi, otomatik bitiş; opsiyonel rapor dosyası; mevcut kayıt listesi |
| İş Kazaları | Tarih, kişi, açıklama ve ek dosyalarla kayıt; mevcut kazaların listesi |
| İSG Kurulu | Kurul kayıtları ve ilgili belgeler; ayrıntılı alan sözleşmesi mevcut kurul modülüyle eşleştirilecek |
| Eğitimler | Firma/personel eğitim kayıtları ve belgeler |
| Diğer Dosyalar | Kategorisiz/diğer firma dosyaları ve indirme |
| Zimmet Formları | Personel bağlantılı zimmet kayıtları ve belgeleri |

İşyerleri, Departmanlar, Görev ve Unvanlar, Dış Firmalar kaldırılmaz; Firma Bilgileri altında kompakt yönetim girişleri olarak korunur.

## Skor — kullanıcı tarafından düzeltilen kural

Kullanıcı **dört kategori / 25’er puan önerisini reddetti**. Skor, aşağıdaki firma takip başlıklarının Tamamlandı durumuna geçmesiyle artacak:

**Skor = tamamlanan takip başlığı sayısı / toplam takip başlığı sayısı × 100.**

Başlıklar eşit ağırlıklı; sabit kategori ağırlığı yok. Kullanıcının açık örnekleri Firma Logosu, Risk Analizi, Kurul, Acil Durum Eylem Planı. Uygulama yorumu: bunlar dahil sayfada takibi yapılan tekil alt başlıklar sayılır; Firma Bilgileri gibi kapsayıcı accordion grubu ayrıca sayılmaz. Dizin yönetim bağlantıları ve Dosya/Evrak Ekle işlem düğmeleri ayrı skor öğesi değildir. Tam sayı gösterimi en yakın değere yuvarlanır; halka gerçek oranı kullanır.

- Gösterge kayıt tamamlama düzeyidir; hukuki uygunluk, işyerinin güvenli olduğu veya çalışmaya izin verildiği anlamına gelmez.
- Her tekil takip başlığı için Tamamlandı koşulu tanımlanır; o başlığa birden fazla dosya yüklemek ek puan kazandırmaz.
- Logo firma oluştururken isteğe bağlı kalır, fakat kullanıcının bu düzeltmesiyle **Firma Logosu başlığı skora dahildir**. İsteğe bağlı iletişim alanları bağımsız puan başlığı değildir.
- Başlık kapsamı/verisi bilinmiyorsa sahte yüzde üretilmez. Servis bağlanmamış başlıklar skoru yapay yükseltmek için paydadan çıkarılmaz; güvenilir toplam hesaplanamıyorsa — gösterilir.
- Halka yalnız doğrulanmış skorla `score / 100` oranında dolar. 0 boş, 100 tam; null/eksik veri 0 değildir. Değer sonlu ve 0–100 aralığında doğrulanır.
- Kayıt başarılı olduğunda sunucu özetinden yeniden hesaplanır; başarısız yükleme, bekleyen işlem veya yalnız dosya seçimi skoru değiştirmez.

## Bölüm durumları

- **Eksik:** Okuma başarıyla tamamlanmış ve bölüm için beklenen kayıt/alan eksik.
- **Tamamlandı:** Gereken kayıtlar sunucuda doğrulanmış. Dosya varlığı tek başına içerik doğrulaması yerine geçmez.
- **Kontrol gerekli:** Tarih/süre veya gerekli alan bilgisi eksik ya da belge süresi geçmiş.
- **Veri alınamadı / yükleniyor:** Servis kapalı, erişim reddedilmiş, veri henüz alınmamış. Bunlar Eksik diye etiketlenmez.
- **Uygulanmıyor / Kaza yaşanmadı:** Açık kullanıcı beyanı ve kapsama göre ayrı durum. Boş iş kazası listesi otomatik olarak Eksik veya kaza yok anlamına gelmez; kaza bildirimi yapan firma puan kaybetmez.

## Güvenli uygulama sırası

1. Kullanıcının eşit başlık oranı kuralını ve başlık bazlı tamamlama koşullarını uygula; tasarım ilkelerini koru.
2. Tek sayfa accordion + ortak sheet yönlendirmesi + saf skor/durum modeli; küçük/büyük yazı ve halka 0/50/100/bilinmeyen testleri.
3. Önceki açık işler: firma düzenleme, logo, sorumlu iletişimi, personel görevi, CSV aktarımı. Bunlar yeni sayfa yapısına bağlanır; ikinci bağımsız yönetim akışı yapılmaz.
4. Mevcut P06+ belge/dosya/eğitim/atama/ekipman/kurul modüllerinin sözleşmelerini incele; yalnız gereken pilot RPC'lerini ekle. Genel rollout veya tüm migration zinciri açılmaz.
5. Yetkili dosya yükleme + metadata kaydı + retry/temizlik; şirketler arası erişim, büyük/yanlış dosya ve bağlantı kesintisi testleri.
6. Temsilci/destek atamalarının tarihli kaydı ve indirilebilir yazı. Yazı oluşturulması imza/onay veya ilkyardım yeterlilik belgesi yerine geçmez.
7. Periyodik kontrol süreleri yalnız doğrulanmış mevzuat/üretici kuralından veya açık kullanıcı girişinden türetilir; bütün ekipmanlara tahmini sabit süre atanmaz. Kullanıcı kaynağı ve kural kaynağı ayrılır; takvim ayı/yılı aritmetiği kullanılır.
8. Sunucuya kaydedilen değişiklik sonrası bölüm durumları ve skorun aynı kapsamda yenilenmesi; oturum değişimi/erişim iptali/arka plan dönüşünde güvenli state yönetimi.
9. Sentetik uçtan uca, izin/izolasyon, idempotency, accessibility ve fiziksel cihaz kabulü. Yeni canlı DDL öncesi private_isg dahil checkpoint eksikliği giderilir.

## Mevcut durumla fark

### Uygulama ilerlemesi — 14 Eylül, yerel kaynak

- Başlık bazlı saf skor modeli eklendi: 12 tekil başlık, eşit ağırlık, 0/50/58/100 ve bilinmeyen veri dahil 11 kontrol PASS. Henüz bütün başlıkların canlı veri kaynağı yok; gerçek toplam bu nedenle — gösterilir.
- Dinamik halka kartı, durum göstergeli accordion bileşeni ve istenen 12 bölüm firma detayına eklendi. Dört kategori kaldırıldı. Yerel durumları tamamlandı yapan sahte toggle yok.
- Personel Listesi ve Personel Ekle ayrı sheet girişleri; liste içinde arama ve kişi detayına geçiş mevcut. Doğrudan ekleme de bekleyen işlem denetimi yapar. Dizin yönetimi sheet üzerinden sürer; kapanışta firma özeti yenilenir, açık bölümler korunur.
- Dosya Ekle/Evrak Ekle görsel girişleri eklendi fakat servis bağlanmadığı için devre dışı. Logo, temsilci/destek, risk/acil durum, ekipman, kaza, kurul, eğitim, diğer dosya ve zimmet bölümleri şu anda açıkça **Veri bekleniyor** durumunda; kayıt/yükleme/indirme/atama yapmaz.
- Canlı migration, rollout veya telefon kurulumu yapılmadı. Bu ilerleme **talebin tamamlandığı anlamına gelmez**; yukarıdaki servis ve form adımları devam ediyor.

### Son doğrulama

- 25 Node testi PASS; 11 saf skor, 27 scene ve 34 pilot create iç kontrolü ilgili testler içinde çalışır (toplamlara tekrar eklenmez).
- Tam Xcode simülatör derlemesi ve 6 `NovaPilotUITests` PASS: kompakt firma/personel, kutlama otomatik kapanışı, doğrudan personel sheet dönüşünde accordion korunması, dizin arama/personel sheet, legacy root ve erişilemeyen pilot.
- Son kaynaklar `NovaPersonnelCreateSheet` dahil derlendi. Gerçek canlı yeni modül kaydı veya fiziksel cihaz kabulü yapılmadı.
- Görsel kontrolde skor kartının normal yazı boyutunda gereksiz dikey yerleştiği görüldü ve düzeltildi. Normal boyutta halka/özet yan yana, erişilebilir büyük yazıda alt alta. Ardından 6 XCUI yeniden PASS.
- XCResult: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-09-13T22-18-53-874Z_pid84322_211870aa.xcresult`.
- Son ekran kanıtları: `output/isg/pilot/company-workspace-compact-final/`.
- Beceriler: SwiftUI UI Patterns (accordion/sheet/durum yapısı), iOS Debugger Agent (Xcode simülatör doğrulaması).

Şu anki canlı pilotta P05 firma/personel/dizinler ve kısmi firma özeti var. Skor, bu sayfadaki belge/dosya/atama/kurul/kaza/ekipman akışları henüz telefonda çalışıyor sayılmamalı. Önceki [UI açık işleri](UI_ITERATION_2026-09-14.md) geçerlidir; bu sözleşme yalnız firma detayının hedef bilgi mimarisini günceller.
