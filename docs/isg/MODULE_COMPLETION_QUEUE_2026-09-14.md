> 15 Eylül güncel canlı durum: [Master pilot aktivasyonu ve açık kabul listesi](PILOT_MASTER_ACTIVATION_2026-09-15.md). Altı ek süreç modülü ile uygunsuzluk/kontrol listesi servisleri açık; aşağıdaki önceki sürüm notları tarihseldir.

# Genel master plan — modül tamamlama sırası

Kullanıcı 14 Eylül 2026 tarihinde genel İSG Adası master planını seçti. Kaynak: `source/ISG_ADASI_MASTER_INTEGRATION_PLAN_V5.md`. Bu kayıt, eski durum belgelerinin tarihsel tamamlandı ifadelerini canlı teslim kanıtı olarak kabul etmez.

## Mevcut kanıt ve kalanlar

| Alan | Mevcut durum | Tamamlanmadan kapanmayacak işler |
|---|---|---|
| Eğitim | Katalog, v3 kayıt, kişi belgesi, iOS/Android kaynakları ve pilot migration mevcut | Fiziksel cihazda gerçek kayıt → belge → paylaş/yazdır kabulü; release checklist kalanları |
| İstatistikler | iOS ekranı ve pilot okuma migration mevcut | Gerçek firma filtreleri ve hesap izolasyonunun cihaz kabulü; Android paritesi |
| Ekipman / acil durum / tatbikat / atamalar / KKD | P10 SQL ve iOS dilimleri mevcut | Her dilimin belge, hatırlatma, Android ve pilot aktivasyon eksikleri kendi dokümanından kapatılacak |
| İSG-KATİP | iOS liste/form/detay, SQL aday migration; bu turda istemci doğrulama ve kalıcı tekrar deneme tamamlandı | Dosya bağlantısının canlı kabulü, hatırlatma teslimi, Android, dar pilot migration ve fiziksel kabul |
| Yıllık çalışma planı | Master kapsamı mevcut | Mevcut çekirdekle eşleme, faaliyet/sorumlu/tarih ve gerçek kayda bağlantı, servis/ekran/çıktı |
| Toplantı / kurul | Master kapsamı mevcut | Gündem, katılımcı, karar/aksiyon, tutanak ve takip |
| Saha ziyaretleri | Master kapsamı mevcut | Ziyaret, gözlem, kanıt ve aksiyon bağlantısı |
| Çalışma izni formları | Master kapsamı mevcut | Ortak belge motoruyla form, PDF/XLSX ve arşiv; canlı izin onayı kapsam dışı |
| Taşeron | Master kapsamı mevcut | Kuruluş/iş bağlantısı ve aynı personelin gerçek işveren ilişkisi |

Önce başlanmış İSG-KATİP diliminin eksikleri, sonra yıllık çalışma planı, toplantı/kurul, saha ziyaretleri, izin formları ve taşeron bağımlılık sırasıyla ele alınacak. Diğer P10 modülleri tam tamamlandı sayılmıyor; ortak belge/hatırlatma altyapısı bağlandığında kendi kabul listeleri tekrar kapatılacak.

Eğitimde kullanıcının daha sonraki kararları geçerlidir: planlama, yoklama, sınav, toplu sertifika ve imzalı nüsha arşivi eklenmeyecek. Genel yıllık çalışma planı bir eğitimi planlandığı için gerçekleşmiş kabul etmeyecek.

## Bu tur — İSG-KATİP güvenilir kayıt

- Geçersiz süre, bozuk bitiş tarihi ve başlangıçtan önce/eşit bitiş sessizce atılmak yerine reddediliyor. Boş isteğe bağlı alanlar boş kalıyor; 12 dakika aynen korunuyor.
- İşlem gövdesi ve operation/mutation kimlikleri hesap bazlı Keychain kaydında tutuluyor. Belirsiz ağ sonucunda aynı işlem yeniden gönderiliyor.
- Uygulama yeniden açılınca kullanıcı “Bekleyen işlemi tamamla” ile özgün işlemi sürdürebiliyor. Başka gövde bekleyen işlemi ezemiyor.
- Kimlik/oturum kontrolü gönderimden önce ve cevap sonrası korunuyor. Resmî İSG-KATİP entegrasyonu veya resmî bildirim iddiası yok.
- `node scripts/katip/run_database.mjs`: izole PostgreSQL 17 üzerinde 43 SQL kontrolü. Geçici container koşu sonunda kaldırılır; canlı veri değiştirilmez.
- `swiftc -parse-as-library App/DesignSystem/ISG/NovaKatipContracts.swift App/Services/Company/NovaKatipService.swift scripts/katip/ServiceCheck.swift -o /tmp/nova-katip-service-check`: gerçek servis kaynağını sahte taşıma/depolama ile derleyen davranış kontrolü. 18 davranış kontrolü geçti. Gerçek Keychain ve cihaz uçtan uca testinin yerine geçmez.

Canlı migration veya rollout anahtarı bu turda uygulanmadı. İSG-KATİP master kapsamının tamamlandığı iddia edilmiyor.

Pilot iOS 2.0.3 (103) fiziksel cihaz hedefiyle derlendi: **BUILD SUCCEEDED** (`/tmp/nova-device-103.log`). Bu turda telefona kurulum yapılmadı; telefondaki son doğrulanmış sürüm 2.0.3 (102).

## Devam — sözleşme dosyası bağlantısı

- `20260915220000_isg_katip_documents.sql` mevcut `file_library_entries` kaydını aynı firma/sahip sınırında sözleşmeye bağlar. Dosya çoğaltılmaz, arşivlenmiş veya asset oluşmamış giriş bağlanmaz.
- Kişisel mutation günlüğü bağlama/kaldırma için de kullanılır. `document_version` eşzamanlı düzenlemede eski istemcinin bağlantıyı ezmesini engeller. Kaldırma kütüphanedeki dosyayı silmez.
- iOS ayrıntısında sayfalı evrak seçimi, değiştirme, bağlantıyı kaldırma ve sistem dosya paylaşımı var. Açmadan önce sözleşme ve dosya mevcut yetkiyle tekrar okunur. Geçici dosya paylaşım kapanınca silinir.
- SQL kontrolü: önceki 43 + yeni 13 = 56 geçti. Yeni kontroller dar dosya kütüphanesi bağımlılık dublörleriyle çalışır; gerçek yükleme/tarama/Storage testi değildir.
- Gerçek Swift servis kaynağıyla 20 davranış kontrolü geçti. Bağlama ve null ile bağlantı kaldırmanın kalıcı tekrar denemesi dahil.
- Pilot cihaz hedefli iOS 2.0.3 (104) derlemesi geçti. Cihaza kurulmadı; yeni migration canlıya uygulanmadı.

### Sonraki bağımlılık: bildirim teslimi

P12 bildirim kuyruğu ve gönderim adaptörleri mevcut, ancak `P12_WORKER_TRANSPORT_2026-09-13.md` / `P12_REPOSITORY_WAIT_2026-09-13.md` canlı sağlayıcı kabulünün tamamlanmadığını kaydediyor. KATİP için ayrıca üretici kaydı, tarih değişikliği/arşivlemede bekleyen işi iptal etme, tekil zamanlama ve uygulama rotası gerekiyor. Bu işler tamamlanmadan bitiş etiketi veya sayaç "hatırlatma teslimi tamamlandı" olarak raporlanmayacak.

## Son canlı ilerleme

[Operasyon modülleri teslimi](PILOT_OPERATIONAL_MODULES_2026-09-14.md): Acil durum, tatbikat, KKD ve atama kayıt servisleri canlı pilotta açık. 167 SQL + 8 mutation kontrolü geçti. Dosya/bildirim/Android kapsamı ve diğer master modülleri açık kalıyor.

## 15 Eylül kayıt yönetimi

[Dört modül kayıt yönetimi](PILOT_MODULE_MANAGEMENT_2026-09-15.md): görünür Ekle, firma kapsamı, tam düzenleme, geçmişi koruyan silme ve firma evrak takip kaydına bağlama canlıya uygulandı. Dosya upload/arşivi ile karıştırılmamalı.
