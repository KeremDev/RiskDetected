# İSGADA — master plan / uygulama fark incelemesi

Tarih: 15 Eylül 2026. Kod tabanı: `50a94468`. İnceleme salt okuma kod/plan karşılaştırması ve canlı şema/rollout sorgularıdır; yeni uçtan uca test veya mevzuat doğrulaması yapılmadı. Bu dosya bir uygulama listesi oluşturur; ürün kodu ve canlı veri değiştirilmedi.

## Sonuç ve kanıt sınırı

Ürün birçok modülde pilot kayıt tutabilir durumda. Bu, master planın tüm belge, kaynak bağlantısı, otomasyon, ticari ve yayın şartlarının tamamlandığı anlamına gelmiyor. Durumlar: **aktif/kısmi**, **yerel/hazır fakat bağlı değil**, **eksik**, **kabul bekliyor**. Eski belgelerdeki PASS sayıları kendi test dilimlerine aittir.

Canlı kontrol: `personnel`, `document_tracking`, `modules`, `nonconformity`, `risk` read/write açık. Module registry'de equipment, emergency_plan, drill, ppe, appointment, katip_contract, annual_work_plan, board, work_permit, site_visit, contractor açık. Eğitim ve istatistik kendi pilot servislerini kullanır; bu rollout tablosunda adlarının bulunmaması kapalı oldukları anlamına gelmez.

Canlıda yeni `file_assets`, `file_library_entries`, `rule_versions`, `personal_notes`, `notification_jobs`, `billing_lifecycle_projection`, `score_subject_states`, `import_batches` tabloları bulunmuyor. `risk_assessments` ve `risk_draft_history` mevcut. Bu tespit eski uygulamanın bütün dosya/bildirim/ödeme yetenekleri yok demek değildir; yeni master altyapısının aktivasyon boşluğudur.

## 1. Önce düzeltilecek somut işleyiş açıkları

| ID | Öncelik | Bulgu / etkisi | Gereken iş ve kapanış ölçütü |
|---|---|---|---|
| H01 | Yüksek | Uygunsuzluk listesi LIMIT 200; `p_after` yalnız verilen kimliği dışlıyor. Swift liste çağrıları hep null gönderiyor. Büyük firmalarda sonraki kayıtlar erişilemez; mevcut parametreyle sayfalama eklense tekrarlar oluşur. | Tarih+kimlik cursor, next_cursor/has_more ve native yükle-devam et; 450 kayıtta eksik/tekrar olmaması. |
| H02 | Yüksek | Uygunsuzluk açılış ve doğrulama fonksiyonlarında tarih sonluluğu var, gelecekte gerçekleşmiş tarih ve doğrulamanın açılıştan önce olması kontrolü görünmüyor. | Sunucu yaşam döngüsü tarih sözleşmesi; geçmiş/bugün/gelecek negatif testleri. Bu incelemede kötü tarih canlıya yazılarak denenmedi. |
| H03 | Yüksek | Fotoğraf bulgusu/uzman maddesi kaynak kimliği metin olarak kaydediliyor; incelenen açma yolunda kaynak kaydın gerçekten o hesaba/firma kapsamına ait olduğunu çözümleyen doğrulama yok. | Kaynak sahipliği ve ilgili içerik sürümünü sunucuda çöz, snapshot al, tekrarlı aktarımı koru. Bu bir veri sızıntısı kanıtı değil, kaynak bütünlüğü açığıdır. |
| H04 | Orta | Eğitim/acil durum/tatbikat/KKD/atama çağrılarının bazıları `canWrite: ready` kullanıyor. ready erişilebilirliği gösteriyor; gerçek yazma yetkisi ayrı. | `controller.canWrite` ve modül yazma kapılarıyla butonları yönet; salt okunur hesapta form açıp sonradan reddetme yerine açık neden. Sunucu reddi korunuyor. |
| H05 | Orta | Çalışma izni PDF/XLSX çıktısından sonra pilot kayıt draft durumunda kalıyor. | Snapshot/başarılı yerel render durumlarını ayır; tekrarlı çıktı yeni yanlış durum veya numara oluşturmasın. Saha çalışma izni/onayı üretme. |
| H06 | Orta | Süreç PDF'si yalnız field listesini/alt kayıt alanlarını basıyor; related_kind/related_id ilişkilerinin okunabilir kaynak başlığı ve durumu çıktıda yok. | Kaynak adı/tarih/revizyonu belge snapshot'ına dahil et; PDF/XLSX'te göster. Kaynak sonradan değişince eski çıktı değişmesin. |
| H07 | Orta | KATİP için ayrı native gate/service bulunuyor ama ana menü ortak süreç gate'ine gidiyor. Ayrı dosya bağlama ekranının varlığı canlı menüde çalıştığını kanıtlamıyor. | Tek aktif akış belirle; gerçek dosya altyapısıyla aynı akışa belge bağlama/açma/değiştirme/kaldırma ekle. |
| H08 | Orta | İSGADA başlıkları değişti; izin, abonelik ve profil dili metinlerinde RiskDetected hâlâ görünüyor. | Görünür marka envanteri: izinler, profil, Auth, paywall, bildirim, e-posta, PDF, TR/EN. Bundle/package/ürün/entitlement kimliklerini değiştirme. |
| H09 | Orta | Ana sayfa openCount/activity nil, asistan eylemi unavailable. | Gerçek açık iş/güncel aktivite kaynakları; asistanın ürün kapsamını netleştir veya hazırlık durumunu eylemden önce göster. |
| H10 | Orta | Durum belgeleri tarihsel eklerle büyümüş; risk ve çapraz bağlantılar eski listelerde hâlâ eksik. | Tek özellik envanterinde kod/canlı/UI/cihaz durumları ayrı tutulmalı; eski kayıtlar tarihçe olarak kalmalı. |

Kod kanıtları: `App/Services/Company/NovaNonconformityService.swift`; `supabase/migrations/20260914215132_isg_pilot_findings_checklists.sql` (read_nonconformities, open_nonconformity_record, record_verification, mutate_nonconformity); `App/Views/Components/NovaPilotMainGate.swift`; `App/DesignSystem/ISG/NovaProcessPDF.swift`; `NovaProcessRecords.swift`; `App/Localization/InfoPlist.xcstrings`; `App/Views/Profile/ProfileView.swift`.

## 2. Özellik bazında tamamlanacaklar

| Alan / master bölümü | Mevcut durum | Yapılacaklar |
|---|---|---|
| Firma/işyeri/personel — §5 | Pilot temel kayıtlar aktif | İşveren/taşeron, görev/departman değişikliği ve arşivleme geçmişinin bağlı eğitim/atama/evrak üzerindeki etkisini fiziksel kabul et; toplu içe aktarma bağlantısı. |
| Eğitim — §6 + son EDU planı | Katalog, v3 kayıt, kişisel sertifika, iki platform kaynağı ve pilot servisleri var | Gerçek çok firma→kapsam→kişi→belge→paylaş/yazdır zinciri; eski kayıt düzeltme, uzun içerik ve hesap değişimi cihaz kabulü. Genel kural/skor/bildirim entegrasyonunu son eğitim kararlarıyla eşle. |
| Risk değerlendirmesi — §7 | Tarih/sürüm, düzenleme, iptal, kesinleştirme canlı | Gerçek dış belge, ekip/imza bilgileri, yöntem/risk kayıtları, güvenli kaynak bulgusu aktarımı, rescan, doğrulanmış süre kataloğu; ayrıntılı değişiklik tarihçesi yüzeyi. Uzman süre beyanı yasal otomatik süre sayılmamalı. |
| Uygunsuzluk — §10 | Kayıt, aksiyon, durum ve doğrulama servisleri açık | H01–H03; önce/sonra kanıt dosyası, kaynak kapsamı, termin değişikliği/tarihçe ve kapanış akışının cihaz kabulü; iş listesi/hatırlatma. |
| Kontrol listeleri — §10 | Hazırlama/yayınlama, kontrol/cevap/tamamlama açık | Gerçek sistem/firma şablon içerik envanteri; soru kanıtı; olumsuz yanıttan kullanıcı onaylı uygunsuzluk önerisi ve kaynak bağlantısı kabulü. |
| Acil durum — §10 | Kayıt/ekip ve yönetim işlemleri açık | Dış dosya veya plan şablon belgesi, sürüm/inceleme, atama-tatbikat-yıllık faaliyet bağlantıları, doğru periyot ve hatırlatma. |
| Tatbikat — §10 | Plan/gerçekleşme kayıtları ve düzenleme açık | Kanıt/katılım dayanağı, bulgu→aksiyon bağlantısı, rapor/tutanak, tekrar takip entegrasyonu. Eğitimde kaldırılan planlama bu modülü kapsamaz. |
| Ekipman kontrolleri — §10 | Envanter ve kontrol kayıtları aktif | Kontrol raporu dosyası, ekipman türüne göre doğrulanmış süre, hatırlatma; uzun envanter ve geçmiş rapor cihaz kabulü. |
| İSG-KATİP — §10 | Beyan esaslı sözleşme CRUD/çıktı aktif | H07, sözleşme dosyası ve bitiş hatırlatması; hesaplanan hizmet ihtiyacı varsa doğrulanmış kural/dayanak. Resmî KATİP entegrasyonu vaat edilmemeli. |
| Yıllık çalışma planı — §10 | Plan/faaliyet/sorumlu/tarih; gerçek eğitim/kontrol/uygunsuzluk ve süreç bağlantıları aktif | Kaynak tamamlanması ile faaliyet tamamlanması arasındaki açık kullanıcı kararı; hatırlatma/iş listesi; bağlantıların çıktıda görünmesi. Mevcut bağlantılar yeniden yapılacak iş değil. |
| Kurul/toplantı — §10 | Gündem/katılımcı/karar ve çıktı mevcut | Kararların ortak uzman iş listesi ve hatırlatıcıya bağlanması; imzaya uygun tutanak düzeni; gönüllü/yasal ayrımın yükümlülük ve skora bağlanması. |
| Atamalar — §10 | Personel/görev/tarih/kayıt yönetimi açık | Atama yazısı, eğitim/yeterlilik kaydı bağlantısı ve bitiş takibi; doğrulanmamış yeterlilik için otomatik uygun etiketi üretmeme. |
| KKD — son kullanıcı kararı | Zimmet ve kişisel form mevcut | Firma personeli seçimi→zimmet→form indirme fiziksel kabulü. Miktar/iade/stok eklenmeyecek. |
| Çalışma izni — §8 | Beş tür ortak alan/form ve PDF/XLSX | H05; türlere özel gerekli alan/önlem listeleri ve basılabilir imza alanlarının kabulü. Mevcut form türü seçimi tek başına beş ayrıntılı şablonun tamamı değil. |
| Taşeron — §9 | Kuruluş/iş ilişkisi CRUD; silinen tarih aralığı tekrar kullanılabilir | Personelin gerçek işveren ilişkisi, firma kişi sayısında çift saymama, belge bağlantıları ve cihaz kabulü. Aktif tarih çakışması düzeltmesi tamamlandı. |
| Saha ziyaretleri — §10 | Ziyaret/gözlem ve ilişkili kaynak kayıtları açık | Gerçek kanıt, ortak aksiyon/termin takibi, çıktıdaki ilişkili kaynak adı ve belge düzeni. |
| Onaylı defter arşivi — §10 | Analiz metni ile tam arşiv aynı şey değil; menü kullanıcı kararıyla gizli | Gelecek arşiv işi: defter kimliği/sayfa/tarih/tarama/tespit bağlantısı. Mevcut tasarım kararına aykırı olarak menüyü otomatik açma. |
| Dosya kütüphanesi — §15/31 | Yerel çekirdek/ekran var; yeni asset/kütüphane tabloları canlıda yok | Gerçek upload, karantina, format+zararlı yazılım kontrolü, güvenli asıl/türev, yetkili indirme, ret/yeniden deneme, dosya kota ve silme. Dosya takip kaydı buna eşdeğer değil. |
| Rapor merkezi — §15 | Eski analiz raporları ve yeni süreç arşivi erişilebilir | Eğitim ve diğer domain belge ailelerini ortak arama/filtreye dahil et; modüle uygun şablonlar; sürüm/yerel önbellek marka-renderer uyumu; fiziksel baskı. Eğitim için toplu PDF/bulut upload ekleme. |
| İçeri aktarma — §16 | Yerel çekirdek; canlı import_batches yok | CSV/XLS/XLSX güvenli ayrıştırıcı; firma→kolon eşle→hata önizle→onay→uygula; personel yanında ekipman/eğitim hedefleri; hata dosyası ve güvenli geri alma. |
| Kişisel not defteri — §34 | İki native kaynak ve senkron testleri var; menü/canlı kapalı | Firma bağlamından bağımsız aç; etiket yönetimi; not/reminder silme-retention; reminder çevrimdışı işlem kuyruğu ve cihaz kabulü. |
| İstatistik — §18 | Pilot okuma ve iOS grafikler var | Eğitim yükümlülük kapsaması ile yalnız eğitim alan kişi sayısını ayır; yeni süreç/risk/kritik iş özetleri; Android ekran/parite; gerçek çok firma filtreleri kabulü. |
| Firma skoru — §18 | Eski skor ile P17 aynı değil; yeni politika/üreticiler canlı değil | Onaylı ağırlıklar, açıklanabilir katkı, uygulanmaz/gönüllü/verisiz ayrımı, kritik uyarı, zaman çizgisi ve portföy karşılaştırması. |
| Kullanıcı rehberliği — §10/35 | Parça açıklamalar mevcut | İlk firma kurulumu, boş durum eylemleri, bağlama göre kısa yardım, reddedilen dosya/izin/kota/çatışma durumları; tutarlı erişilebilirlik. |

## 3. Modülleri birbirine bağlayan yatay eksikler

1. **Kural ve uygulanabilirlik motoru (§4/14):** çekirdek yerel; gerçek yayınlanmış kural kataloğu canlıda yok. Firma/işyeri bilgisi değişince yükümlülük ve dönem yeniden hesaplama; gönüllü kullanımın skoru yanlış düşürmemesi; tarih değişiminin hatırlatıcıyı iptal/yenilemesi.
2. **Bildirim otomasyonu (§17/32):** yeni P12 canlı değil. Scheduler/worker, güvenli sağlayıcı erişimi, domain üreticileri, tercih/OS izin ayrımı, eski bildirim üreticilerinden kontrollü geçiş, çift gönderim engeli, doğru sayfaya deep-link ve cihaz teslim gözlemi.
3. **Auth (§26):** servis adaptörleri var; yeni e-posta kayıt/şifre ekleme/recovery koordinasyonu kapanmamış. Kaydedilmiş sentetik testte Unicode sekiz-karakter istemci/sunucu farkı bulunmuş; yönetilen canlı Auth'ta giderildiğine dair kanıt yok. Kullanıcı adı akışı ve Apple/Google aynı hesap koruması kabul edilmeli.
4. **Abonelik/kota (§27–28):** mevcut ödeme çalışması korunmuş; yeni P14 canlı değil. Hak/hediye/indirim/kota ayrımı, personel/eğitim/dosya kapasitesi, eski hak tabanı ve webhook lifecycle; eski/yeni binary + restore/upgrade/downgrade deneyi.
5. **Davet/Geri Dönüş (§33/41–44):** sunucu prototipi var, gerçek ödül/mağaza indirim/iletişim aktive değil. Plus7 ile tek dönem %20 plan kararı korunmalı; yıllık davetçi, tekrar/çakışma ve teklif fiyatı gibi açık alt kararları ayrı tut. İki mağazada gerçek teklif uygulama/normal yenilemeye dönüş kabulü gerekli. Bu eksik kampanyalar ana modül kaydını engellemez.
6. **Analitik/admin (§29–30/43):** yeni teknik olay üreticileri, uçtan uca trace ve redaksiyon, birinci taraf ölçüm; mevcut operasyon paneliyle domain/worker/kampanya hata ekranları bağlı değil. Gerçek panel erişim yetkisi ve export kabulü yapılmalı.
7. **Yaşam döngüsü (§19):** yeni tabloların hesap silme, arşiv, saklama, dosya silme ve audit ilişkileri birlikte test edilmeli. Yeni foreign key'lerin hesap silmeyi engellemediği kanıtlanmalı; bu inceleme silme hatası kanıtlamadı. Yeni şemayla geri yükleme provası ve bağımsız kurtarma kopyası ayrıca açık.
8. **Platform/parite (§20/35):** iOS'ta ortak stil iyileştirildi; tüm sayfa+popup, büyük yazı, TR/EN, VoiceOver, klavye, readonly/hata/yükleme ve geri navigasyonu test edilmedi. Android eğitim karşılığı mevcut; diğer yeni pilot modüller ve istatistik için tam parite kanıtı yok.
9. **Yayın (§21–24):** İSGADA ikon/mağaza/izin/metin paketi, Auth/push/ödeme teknik kimliklerinin korunması, dar migration manifesti, eski istemci uyumluluğu, canary/geri dönüş ve gözlem. Son marka değişikliği sonrası build/cihaz kabulü henüz yok; son kesin telefon kurulumu 110, sonraki build'ler kuruldu sayılmaz.

## 4. Eksik diye yeniden açılmayacaklar

- Eğitim planlama, yoklama/katılım teyidi, sınav/puan, toplu sertifika, imzalı eğitim nüshası arşivi kullanıcı tarafından kaldırıldı.
- KKD miktar, iade, stok/depo kaldırıldı.
- İşveren/personel hesabına görev veya saha çalışma onayı ürünü yapılmayacak; kullanıcı uzman kayıt tutuyor.
- Sağlık takibi/tıbbi dosya ve resmî KATİP otomasyonu bu kapsamda değil.
- Onaylı defter menüsünün şu an gizlenmesi istenmişti; görünmemesi tek başına hata değildir.
- Risk taslak düzenleme/iptal, süreçlerin eğitim-ekipman-uygunsuzluk bağlantıları ve taşeron silinen tarih aralığı düzeltmeleri artık tamamlanan işlerdir.

## 5. Önerilen uygulama sırası

1. H01–H04 veri/akış düzeltmeleri, H08 marka kalıntıları; her biri odaklı negatif testle.
2. Gerçek dosya hattı ve kütüphane; bağımlı risk/KATİP/ekipman/uygunsuzluk kanıtlarını bağla.
3. H05–H07; modüle özgü belge ve rapor merkezi, gerçek iş/aksiyon bağlantıları.
4. Kural/yükümlülük + bildirim üreticileri ve gerçek teslim; kişisel not defterini devreye al.
5. Import, skor/istatistik ve ana sayfa tamamlanması.
6. Auth, abonelik/kota, analitik/admin; bağımsız dallar önceki adımlarla ilerleyebilir, genel yayından önce kapanmalı.
7. Gerçek mağaza kanıtından sonra davet/Geri Dönüş; açık ticari detayları karara bağla.
8. Android tamamlama, iki fiziksel cihazda kabul, eski istemci/migration/restore ve kontrollü yayın.

Her özellik dört ayrı sütunla izlenmeli: **kod hazır / sunucu aktif / kullanıcı akışı bağlı / cihazda doğrulandı**. Tek bir “tamamlandı” etiketi bu ayrımı kaybettiriyor.

## Kaynaklar

- `source/ISG_ADASI_MASTER_INTEGRATION_PLAN_V5.md`, özellikle §4–10, §14–24, §26–44.
- `PILOT_MASTER_ACTIVATION_2026-09-15.md` (son ekler tarihsel maddelerin yerine okunmalı).
- `../education/release-checklist.md` ve kullanıcı onaylı EDU planı.
- `P02_PASSWORD_AUTH_2026-09-13.md`, `P04_FILE_LIBRARY_2026-09-14.md`, `P06_RULE_CORE_2026-09-13.md`.
- `P11_DOCUMENT_IMPORT_CORE_2026-09-14.md`, `P12_NOTIFICATION_CORE_2026-09-14.md`, `P13_PERSONAL_NOTES_2026-09-14.md`, `P13_SERVER_PUSH_REMINDERS_2026-09-13.md`.
- `P14_BILLING_LIFECYCLE_2026-09-14.md`, `P15_CAMPAIGN_CORE_2026-09-14.md`, `P16_OBSERVABILITY_ADMIN_2026-09-14.md`, `P17_SCORE_PORTFOLIO_2026-09-14.md`.
