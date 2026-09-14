# Master plan canlı pilot incelemesi — 15 Eylül 2026

Bu kayıt eski "yerel test geçti" açıklamalarının canlı teslim anlamına gelmediğini esas alır. Kaynak: `source/ISG_ADASI_MASTER_INTEGRATION_PLAN_V5.md`. Kullanıcının eğitim ve KKD kapsam daraltmaları geçerlidir.

## Bu teslimde aktif edilenler

| Modül | Pilot davranışı |
|---|---|
| İSG-KATİP kayıtları | Firma/işyeri, sözleşme tarafı, tarih ve dakika beyanı; ekle/düzenle/sil; resmî KATİP işlemi değildir |
| Yıllık çalışma planı | Plan ve alt faaliyetler; sorumlu, plan/gerçekleşme tarihi, durum ve erteleme gerekçesi |
| Kurul/toplantı | Gündem, firmaya ait katılımcılar, gerçekleşme ve alt karar/takip kayıtları |
| Saha ziyaretleri | Firma/işyeri ziyaretleri ve alt gözlem kayıtları |
| Çalışma izni formları | Beş form türü; belge hazırlama; çalışma başlatma/onay yetkisi üretmez |
| Taşeron | Firma kuruluşları ve işyeri/tarih kapsamındaki iş ilişkileri |
| Uygunsuzluk | Mevcut native ekranın eksik canlı kayıt/detay/durum servisleri kuruldu |
| Kontrol listeleri | Kullanıcının liste hazırlama/yayınlama, kontrol başlatma, cevaplama ve tamamlama servisleri kuruldu |

İlk altı modül ortak kayıt editörünü kullanır: şirket aramasıyla açılan popup, belge takip kaydına bağlantı, kararlı kayıt kimliği, iyimser eşzamanlılık, kalıcı mutation günlüğü, geçmişi koruyan silme. Firma detayındaki Firma süreçleri bölümünden seçili firma kapsamında açılır. Firma içinden açılan listede başka firmaya geçilmez.

İlk altı modülün PDF ve gerçek XLSX çıktıları sunucuda sabitlenen belge sürümünden üretilir. Yıllık plan, kurul ve ziyaret alt kayıtları çıktıya dahildir. Aynı içerik aynı belge numarası/sürümünü kullanır; değişen içerik yeni sürüm oluşturur. Rapor arşivi süreç belgesi sürümlerini ve eski analiz raporlarını ayrı seçeneklerle açar. Profil mevcut çalışan profil ekranına bağlandı.

Dosyalar cihazda üretilir; sunucuda değişmez belge verisi tutulur. Firma evrak takip kaydına bağlantı, dosya yükleme veya imzalı dosya arşivi değildir.

## Dar canlı paketler

- `20260914214927_isg_pilot_remaining_records.sql`: SHA-256 `31c01f2b21ff0bcb277321a4d5c24691eae91aad50bb6e6c86b2a467193fd073`.
- `20260914215434_isg_pilot_findings_checklists.sql`: SHA-256 `7e2d7cbb8bab57119081743b6d768e7642da4e5da46c379f837a38feb565c660`.
- Uzak migration zamanlarıyla eşleşen kopyalar `supabase/pilot-release/supabase/migrations` altında. Ana migration klasörü topluca uygulanmadı.
- Altı yeni modülün read/write anahtarları ve nonconformity rollout açık. Sunucu oturum, pilot hesap, sahiplik/firma erişimi ve yazma yetkisini denetler. Pilot dışındaki hesaplar bu yeni süreç servislerini kullanamaz.

## Doğrulama

- `node scripts/modules/run_pilot.mjs`: PostgreSQL 17 üzerinde eski operasyon, kayıt yönetimi, KKD dar kapsam, on süreç kayıt türü, uygunsuzluk ve kontrol listesi regresyonu PASS.
- Kapsam dışı sahiplik, hatalı tarihler/ebeveyn, beklenen sürüm, tekrar gönderim, alt kaydı olan ebeveynin silinmemesi, belge revizyonu ve kaynak silindikten sonra arşiv okuma kontrolleri dahil.
- Canlıda gerçek pilot oturum bağlamında her yeni kök tür için oluştur/oku/çıktı/arşiv aç; ayrıca uygunsuzluk oluştur/oku ve kontrol listesi hazırlama→yayınlama→başlatma→cevap→tamamlama smoke kontrolleri geçti. Test kayıtları transaction içi alt işlem rollback ile kaldırıldı; yalnız aktivasyon anahtarları commit edildi.
- Gerçek XLSX renderer çıktısı ZIP CRC, XML, Türkçe karakter ve formül izolasyonu kontrollerinden geçti.
- iOS pilot 2.0.3 (111) fiziksel cihaz hedefi derlemesi PASS; firma içi erişim değişikliği dahil. Fiziksel dokunma/paylaşma kabulü ayrıca gerekir.
- Supabase security advisors okundu: mevcut private/RLS-politikasız tablolar INFO; authenticated SECURITY DEFINER ve parola koruma uyarıları ayrıca mevcut. Bu okuma bütün sistemin güvenlik sertifikasyonu değildir.

## Tamamlanmamış işler — açık kabul listesi

1. Gerçek dosya Storage/yükleme/tarama/promotion hattı, imzalı evrak arşivi ve dosya kanıtı. Canlı `file_assets` yok. Format denetleyicisi antivirüs değildir; sahte clean sonucu eklenmedi.
2. Yeni risk değerlendirmesi sürümleme modülü. Canlı `risk_assessments` yok; mevcut fotoğraf analizi bunun yerine sayılmaz. Doğrulanmış kural ve dosya bağımlılıkları kapatılmalı.
3. P12 otomatik hatırlatma üreticileri/scheduler/gerçek APNs-FCM teslimi. Yerel adaptör testi canlı teslim değildir.
4. Yıllık faaliyetlerin eğitim/ekipman/uygunsuzluk vb. gerçek kayıtlara kullanıcı arayüzünden bağlanması ve takip kapsamının tamamı. Ortak süreç backend'inde dar related alanları var; bu çapraz modül bağlantıları tamamlanmış değil.
5. Çalışma izinlerinde çıktı alınmasıyla rendered durumunun ilişkisi; mevcut pilot kayıt draft durumunu korur. Gerçek saha onayı kapsam dışıdır.
6. Taşeron silinen iş ilişkisiyle aynı tarih aralığında yeniden kayıt açma davranışı ve personel işveren akışının fiziksel kabulü.
7. Acil durum/tatbikat/atama gibi önceki modüllerin tüm master belge ve hatırlatma kapsamı; kişisel not defteri ve ek arşiv entegrasyonları.
8. Normal/uzun PDF'nin fiziksel görünümü, paylaşma/yazdırma; eğitim ve istatistiklerin gerçek cihaz kabulü; Android paritesi.

Bu liste bitmeden "tüm master özellikleri tamamlandı" denmez. Eğitim planlama/yoklama/sınav/toplu belge/imzalı arşiv ve KKD miktar/iade özellikleri kullanıcı kararıyla kapsam dışıdır; eksik geliştirme olarak açılmayacak.

## Telefon kurulumu

2.0.3 (111) app bundle sürümü doğrulandı. İki `devicectl install app` denemesi cihaz tüneli ve developer disk bağlantısından sonra 60 saniyede zaman aşımına uğradı; uygulama envanteri okuması da zaman aşımına uğradı. Yeni sürüm telefona kuruldu/açıldı diye raporlanamaz. Kullanıcıdan ekran kilidini açıp USB bağlantısıyla açık bırakması istendi. Son önceki doğrulanmış kurulum 2.0.3 (110).

## Devam: süreç bağlantıları ve taşeron tarih aralığı

- Yıllık plan faaliyeti, kurul kararı ve saha gözlemi editörlerine aynı firmadaki süreç kaydını tür ve aramayla seçme/değiştirme/kaldırma eklendi. Sayfalı seçim desteklenir. Firma kapsamı değişmez; bağlantı durum değişikliği üretmez.
- İlk seçim türleri: ziyaret, toplantı, çalışma izni, sözleşme, yıllık plan, taşeron. Eğitim/ekipman/uygunsuzluk bağlantıları henüz bu seçicide yok; madde 4 bütünüyle kapanmadı.
- Düzenleme mevcut bağlantıyı korur. Erişilemeyen bağlı kayıt için kullanıcıya kaldırma/değiştirme gösterilir. Sunucu aynı firma doğrulamasına ek olarak eksik bağlantı çiftini ve kendine bağlantıyı reddeder.
- Silinen taşeron iş ilişkisi tarih aralığını artık rezerve etmez. Aktif çakışma reddedilir; yeni kayıt farklı kimlikle oluşturulur; eski satır/geçmiş korunur. Yukarıdaki madde 6'nın tarih aralığı kısmı kapandı.
- Canlı migration `20260914220546_isg_pilot_process_links.sql`; SHA-256 `f9773b2d2cff51f385a47dfbeae9809e091126e128981192d7114a390ab8ab25`.
- İzole tam operasyon regresyonu PASS; ek bağlantı/durum/kendine bağlantı/kaldırma ve aktif çakışma/silinen aralık/korunan geçmiş kontrolleri PASS. Canlı constraint read-back PASS; advisors kategorileri/sayıları öncekiyle aynı.
- iOS 2.0.3 (112) fiziksel cihaz hedefi BUILD SUCCEEDED (`/tmp/nova-device-112.log`).
- Build 112 telefon kurulumu da cihaz bağlantısından sonra 60 saniyede zaman aşımına uğradı. Kurulum/açılış doğrulanmadı; build hazırdır, fiziksel kurulum bekliyor.

## Devam: eğitim, kontrol ve uygunsuzluk bağlantıları

- Faaliyet, karar ve gözlem seçicisi artık gerçekleşmiş firma eğitim kaydını, ekipmanın kontrol kaydını ve iptal edilmemiş uygunsuzluğu da listeler. Eğitim bağlantısı çok firmalı oturumun yalnız ilgili firma alt kaydına yapılır.
- Yeni `isg_pilot_process_references_v1` yalnız okuma için kullanılır. Kaynak modüllerin yazma API'leri açılmaz/değiştirilmez; process spec'e yeni yazılabilir tür eklenmez. Aktif oturum, pilot, sahiplik/firma erişimi ve kaynak ekipman/uygunsuzluk okuma kapıları uygulanır.
- Kaydetmede aynı firma kaynağı tekrar doğrulanır. Durum kendiliğinden değişmez; başarısız ekipman kontrolüne bağlantı da başarı beyanı üretmez. İptal/erişilemez kaynak yeniden kaydetmede değiştirilmeli veya bağlantı kaldırılmalıdır.
- `20260914221013_isg_pilot_cross_module_links.sql` canlıya uygulandı; SHA-256 `0903183160f9f763074f2d89dafdb928f24817a4fa32f8fd914801ef24038432`.
- Tam izole operasyon regresyonu PASS. Üç türün liste/tekil okuma/arama/kaydetme/sahiplik testleri PASS; planlanan eğitim seçime girmez. Testte eğitim için gerçek temel tablo DDL'sinin fixture kopyası kullanılır; eğitim modülünün tamamının test edildiği iddia edilmez.
- Canlı pilot oturumuyla üç türün okuması doğrulandı; kalıcı test verisi oluşturulmadı. İlk smoke denemesi eksik `exp` test claim'i nedeniyle AUTH_REQUIRED döndü; tam süreli test bağlamında tekrar başarılı oldu. Yetki fonksiyonları değiştirilmedi.
- Advisors kategorileri ve sayıları öncekiyle aynı. iOS 2.0.3 (113) BUILD SUCCEEDED. Dosya/bildirim/risk sürümleme ve fiziksel kabul maddeleri hâlâ açık.
- Build 113 kurulum denemesi de bağlantı/usage assertion sonrasında 60 saniyede zaman aşımına uğradı. Telefon kurulumu doğrulanmadı. Fiziksel bağlantı/ekran durumu değişmeden aynı komutu tekrar çalıştırmak ilerleme sayılmayacak.

## Devam: risk değerlendirmesi kayıt ve sürümleme

- Risk Değerlendirmesi menüsü pilotta açıldı; firma detayındaki risk başlığından da erişilir. Kayıt ekle doğrudan şirket aramalı popup açar; işyeri seçildikten sonra aynı popup'ta sürüm bilgileri girilir. Açık taslak varsa ikinci taslak yerine mevcut kayda yönlendiren açıklama gösterilir.
- Tam yenileme, kısmi revizyon, bilgi düzeltmesi; değerlendirme/revizyon tarihleri, kısmi kapsam, gerekçe, uzman süre beyanı, kesinleştirme ve geçmiş okuma canlıdır. Kaydetmeler kalıcı mutation kimliği kullanır.
- Kısmi/bilgi düzeltmesi temel tarihi, süreyi ve süre kaynağının gözden geçirme durumunu korur. Yürürlükten kalkmış sürüm yeniden kesinleştirilemez. Eski sürümler silinmez. Normal revizyonda yeni süre alanı gösterilmez.
- Bu dilim uzman kayıt takibidir; dosyası yüklenmiş veya imzalı risk değerlendirmesi belgesi olduğu iddia edilmez. `rescan`, dosya asset bağlama ve bağımsız doğrulanmamış analiz bulgusu kopyalama pilotta kapalıdır. Sahte file_assets veya published rule_versions tabloları oluşturulmadı. Mevzuat kataloğu seçimi boş; uzman süresi `unapproved_fixture` kaynak koduyla gözden geçirme gerektirir.
- `20260914221703_isg_pilot_risk_records.sql`, SHA-256 `c5a71e2d9f112ec7e438b715a1d284158210ac305d9ef35cd2fff0698ac16205`. Gerçek kaynak SQL'den üretilen dar paket; ana migration klasörü topluca uygulanmadı. Risk rollout read/write açıldı, pilot ve firma erişimi sunucuda denetlenir.
- İzole PostgreSQL operasyon regresyonu PASS; risk oluştur/taslak/kesinleştir/tekrar gönderim/artık yıl/düzeltmede tarih-kaynak/geçmiş/eski sürüm reddi/hesap izolasyonu/dosya kapısı testleri PASS. Canlı gerçek pilot oturumunda oluştur→taslak→kesinleştir→detay smoke geçti; test verileri alt işlem rollback ile kaldırıldı, yalnız rollout aktivasyonu commit edildi.
- Advisors: yeni altı private tablo için RLS-politikasız INFO artışı (159); authenticated SD WARN 9 ve parola koruma WARN 1 öncekiyle aynı. Private tablo doğrudan erişim grant'leri kapalı, API kapıları açık.
- Önceki "canlı risk_assessments yok" ifadesi bu teslimle tarihsel oldu. Dosya/PDF risk belgesi, analiz kaynak aktarımı ve risk taslaklarının tam düzenleme/iptal yönetimi hâlâ açık kabul maddeleridir. Tüm P08 master tamamlandı denmez.

## Risk draft management — 2.0.3 (116)

Implemented expert draft editing and reasoned cancellation in the same content-sized popup flow. Draft kind is fixed during editing. Cancelled versions and cancellation reasons remain in history; current finalized version and validity are preserved. Per-draft edit revisions prevent stale edits/finalization, while persistent mutation receipts support retries. A private RLS-protected history stores each pre-edit/cancel snapshot. Final versions remain immutable.

Live narrow migration: `20260914223630_isg_pilot_risk_draft_management.sql` (candidate `20260914222916`). SHA-256 `d19c5d27efa5a504e09b4a5c97f246cc7247f05d8f347cc5dd1c29b24a23a561`. Pilot release mirror matches applied SQL.

Validation: `node scripts/modules/run_pilot.mjs` PASS, including prior operational modules and risk edit/replay/stale edit/stale finalize/cancel/history/new draft/final immutability/other owner checks. Live authenticated smoke passed; all smoke writes rolled back. Build 116 succeeded before the last cancellation-note display and edit-title/disabled-kind presentation adjustments. Xcode subsequently started requiring license acceptance, so those final presentation changes have not been rebuilt. No claim of phone installation or physical UI acceptance.

Remaining master-plan work is still tracked above: actual file upload/scanning/storage, real reminder delivery, risk source/file integration, work-permit output lifecycle, remaining document workflows and Android/device acceptance. This delivery does not mark those complete.
