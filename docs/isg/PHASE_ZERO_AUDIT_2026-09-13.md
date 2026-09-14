# P00'dan güncel pakete plan / kod / kanıt denetimi

Tarih: 13 Eylül 2026 · Dal: `codex/isg-transition-foundation` · Başlangıç HEAD: `69a20166`

## Sonuç ve kapsam

Plan P00–P21 boyunca mevcut durum, kaynak ve yerel kanıtlarla karşılaştırıldı. P01/P04/P07/P11/P16 sınırlarında doğrulanmış hatalar düzeltildi; bütün fazlar tamamlandı anlamına gelmez. P05'in önceki iki native SDK→DB yerel kabulü geçerliliğini korur. Bu tur yeni native/gerçek sağlayıcı/store/güvenlik-yük kabulü yapılmadı. UI iterasyonu açık, yeni kök ve son tasarım dondurulmadı; hiçbir canlı rollout, migration veya mağaza değişikliği yapılmadı.

Denetim yöntemi: ana plan §0–4 ve §15, güncel faz tablosu, teslim notları, kabul defteri, seçilmiş SQL güven sınırları, yeni negatif/eşzamanlılık testleri ve bütün mevcut yerel sunucu probe zinciri. Bu bir tüm-satırlar güvenlik denetimi değildir. Tarihsel PASS sayıları güncel kaynak kanıtı sayılmaz.

## Düzeltilenler

| Kimlik / faz | Doğrulanan eksik / hata | Düzeltme ve regresyon |
|---|---|---|
| A01 / P01 | Eksik Docker inspection alanları veya test öneki taşıyan bir volume izolasyon sayılabiliyordu. Privilege/runtime port alanları yeterince denetlenmiyordu. | Eksik envanter, privilege/capability/device/security override, host IPC ve bütün mount'lar reddedilir; gerçek portlar manifestle karşılaştırılır. Olumsuz fixture'lar eklendi. |
| A02 / P01–P19 | Koşu sonunda alınan kaynak hash'i, çalışma sırasında değiştirilmiş kodu eski çalışmanın PASS sonucuna bağlayabiliyordu. Signup/recovery aynı check ID'sini iki kez yazıyordu. | Hash envanteri başlangıçta alınır ve başarıdan önce tekrar karşılaştırılır; drift koşuyu başarısız yapar. Tekrarlanan check ID reddedilir; SMTP kontrolleri amaç bazında ayrı adlandırıldı. |
| A03 / P04 | Süresi dolmuş upload scan/promote olabiliyor; temiz fakat promote edilmemiş intent expiry taramasında kalıyordu. | Scan/promote aşamalarında TTL reddi, expiry sweeper'a `clean` eklenmesi; üç gerçek SQL negatif kabulü. Tamamlanmış promotion replay'i korunur. |
| A04 / P07 | İki ayrı eğitim kaydından aynı çalışana eşzamanlı çakışan yoklama yazılabiliyordu. Kapanmış plana yeni katılımcı eklenebiliyordu. | Ortak employee satırı kilitlenir; iki paralel işlemden yalnız biri başarılı olur. Kapalı plana yeni enrollment reddedilir; mevcut replay korunur. |
| A05 / P07 | Gelecekte biten yoklama ve yoklama/değerlendirmeden önce veya gelecekte tamamlanma tarihi kabul edilebiliyordu. | Güvenilir sunucu zamanı ve İstanbul yerel tarihiyle sınır kontrolü; gelecekte attendance ve iki geçersiz completion tarihi testi. |
| A06 / P11 | `equipment` seçimi çalışan writer'ına ulaşabiliyordu; import dosyası firma/owner/amaç/hash bağı taşımıyordu. | Yazarı olmayan hedef `FEATURE_UNAVAILABLE`; sadece hedef firmanın owner'ına ait temiz `structured_import` varlığı ve aynı hash kabul edilir. |
| A07 / P11 | İdempotency tarih/ondalık/sütun ayarlarını kapsamıyordu; aynı durumdaki satırın içeriği değişse de preview hash aynı kalıyordu. | Tam istek fingerprint'i ve mutation kilidi; preview hash ham/normalize içerik, hedef ve sürümü kapsar. Negatif replay ve değişmiş içerik testi. |
| A08 / P11 | Bilinmeyen sütunlar ve iç içe JSON ham import kaydına girebiliyordu. | Şimdilik yalnız `employee_code/full_name/hired_on`; değerler string/null. Bilinmeyen alan reddi eski `HEALTH_COLUMN_REFUSED` kodunu kullanır; bu genel hata adının API düzeyinde iyileştirilmesi ayrı iş. |
| A09 / P16 | NULL içeren scope listesinde SQL üç-değerli mantığı yetki kontrolünü atlayabiliyordu. | NULL scope girişte reddedilir, authorization yalnız ifade açıkça TRUE ise geçer. Bozuk geçmiş session fixture'ı da reddedilir. Gerçek panel adaptörü henüz yok; canlı erişim olayı iddiası değildir. |
| A10 / P11 | Export settlement herhangi bir temiz dosyayı kabul ediyordu; aynı state'e farklı asset ile tekrar istek sessizce replay sayılıyordu. | Belgenin firması/owner'ı, `company_document` amacı ve export formatı zorunlu; farklı asset/error replay'i conflict. Dört yanlış bağ ve bir replay negatif kabulü. Bu kontrol renderer'ın gerçekten snapshot'ı çizdiğini kanıtlamaz; renderer/parite kabulü açık. |

## Faz bazında eksikler ve kapanış sınırları

| Faz | Bu denetimin sonucu | Hâlâ gerekli |
|---|---|---|
| P00 | Yedek bütünlüğü ve izole eski-veri upgrade tekrar kontrol edildi; integrity tek başına restore kanıtı değildir. | Aynı disk dışı doğrulanmış kopya; ölçülmüş RPO/RTO; imzalı eski binary matrisi; panel checkpoint'i ve gerçek servis yapılandırması envanteri. |
| P01 | İşlem/outbox çekirdeği var; A01/A02 kapatıldı. Fonksiyon haritası yalnız 10 transport dosyasını kapsıyor. | Domain producer/consumer, gerçek worker rolü ve bütün domain fonksiyon→test eşlemesi. |
| P02 | İzole Auth parola/signup/recovery/session/mutation probe'ları var. | Native amaç koordinatörü, hesap bağlama/MFA/provider/deep-link uçtan uca kabulü. |
| P03 | Shadow kota ve legacy hak koruma mevcut; legacy hâlâ otorite. | Onaylı katalog/limit/cutoff, gerçek floor backfill ve kontrollü cutover. Hediye/indirim çekirdeği artık P14'te mevcut; gerçek store bağı eksik. |
| P04 | Dosya yaşam döngüsü var; A03 kapatıldı. | Gerçek AV/parser sandbox, dosya güvenlik corpus'u, bucket policy/signed URL ve native bağlantı. |
| P05 | Önceki yerel geliştirme/kabul tamamlandı; upgrade provası tekrarlandı. | Bağımlı domain tüketicileri P06/P07/P10/P11; fiziksel cihaz/gateway/imzalı update P19/P20. P05'i yeniden sıfırlama. |
| P06 | Sürümlü kurallar/yükümlülük/schedule çekirdeği mevcut. | Resmî içerik ve hukuk onayı, task/domain/bildirim tüketicileri. |
| P07 | Eğitim çekirdeği mevcut; A04/A05 kapatıldı. | Resmî katalog, sertifika/PDF-XLSX, eğitmen/imza, skor/bildirim ve native akış. |
| P08 | Risk sürümleme/finalize/drift çekirdeği mevcut. | Matris/içerik, risk→uygunsuzluk, G4 review, belge/skor/native. |
| P09 | Durum makinesi ve checklist çekirdeği mevcut. | Gerçek saha kanıtı, domain üreticisi, bildirim/skor/PDF/native. |
| P10 | On iki modülün yerel SQL dilimleri mevcut. | Evrak, task/bildirim/skor bağlantıları, taşeron paketi ve gerçek native akışlar. |
| P11 | Import/export defteri var; A06–A08 ve A10 kapatıldı. | Güvenli parser, gerçek render worker ve görsel parite, equipment writer, satır ölçeği/yük, arama/legacy rapor/native. |
| P12 | Worker/repository yanında cihaz kayıt modeli ve kalıcı gönderim journal'ı da mevcut; eski tabloda bunların hiç yok denmesi artık doğru değil. | Production pool/rol/credential/scheduler, gerçek token/izin yaşam döngüsü, sağlayıcı teslimi, e-posta/tüketici/deep-link ve cihaz kabulleri. |
| P13 | Native şifreli not kuyruğu ve server-push reminder bağı mevcut. | Offline **reminder mutation** kuyruğu (not kuyruğuyla karıştırma), deep-link/gerçek teslim, tag/retention/redaksiyon. |
| P14 | Lifecycle/quote/settlement çekirdeği mevcut. | Gerçek Apple/Google/RC adapter'ı, store teklif spike'ları, ticari onaylar ve legacy otorite cutover'ı. |
| P15 | Önceki R1–R3 sürüm/qualification/winback düzeltmeleri mevcut ve ortak zincirde yeniden sınanır. | Annual/unknown/review çözümü, gerçek qualification producer'ı, katalog/store/operasyon bağlantısı. |
| P16 | İzleme/admin çekirdeği var; A09 kapatıldı. | Güvenilir Auth→admin rol/MFA adapter'ı, panel/telemetri/domain producer'ı, retention ve gerçek panel kabulü. |
| P17 | Bağımsız hesap oracle'ı ve skor/portföy çekirdeği var. | Onaylı ağırlıklar, domain projection'ları, gerçek veri shadow'u ve native açıklama/portföy. |
| P18 | NOVA/iOS katalog ve katalog koruyan writer mevcut. UI bilerek iterasyonda. | Android TR/EN, dil/VoiceOver/Dynamic Type/cihaz kabulü, domain servisleri ve yeni root geçişi. Görsel final kararını şimdi zorlamıyoruz. |
| P19 | Katman defteri ve kill-switch provası var; A02 kanıt üretimini sıkılaştırdı. | 263 senaryonun tek tek gerçek koşu+katman bağları; cross-layer, store, eski binary, hesap silme, measured restore, güvenlik/yük. `covered=0` önceki P05 yerel kabulünü iptal etmez. |
| P20 | Yayın başlamadı; yanlışlıkla atlanmış tamamlanmış faz değil. | P19 kapıları ve insan onayları sonrası aynı mağaza kayıtlarına imzalı update/canary. |
| P21 | Yayın sonrası faz; henüz başlamadı. | Yayından sonra ölçülü queue/drift/maliyet/destek gözlemi ve geri dönüş. |

## Devam sırası

1. UI iterasyonlarıyla paralel altyapı: P01 tüketici/worker güven sınırı ve P04 gerçek dosya doğrulama → P11 parser/render. Ekipman import kapalı kalır.
2. P06–P10 domain olaylarını task/bildirim/skor/belgeye bağla. Import telafisinin downstream kayıtlar oluşmuşken davranışını ayrıca negatif testlerle incele; bu tur tam kabul edilmedi.
3. P12 gerçek worker/token/credential/scheduler ile P13 reminder offline/deep-link/cihaz kabulü.
4. P14 store spike + RC adapter, ardından P15 annual/review ve qualification producer; ticari parametreleri insan onayı olmadan sabitleme.
5. P16 gerçek panel/Auth adapter'ı, P17 domain projection'ları; UI kararı netleşince P18 kök/erişilebilirlik/dil kabulü.
6. P00 dış-disk/ölçülü kurtarma ve P19 senaryo bazlı kanıt açıklarını kapat; ardından P20 için ayrı yayın onayı.

## Son doğrulama

Kanıt özeti: [Koşular, hash'ler ve sınırlar](evidence/PHASE_ZERO_AUDIT_2026-09-13.json). Son sunucu koşusu 13 Eylül 2026 19:01–19:03 UTC'dir. Kaynak dosyaları koşu boyunca sabit kaldı ve son kontrolde rapor hash envanterleri mevcut kaynakla eşleşti.

| Doğrulama | Sonuç | Sınır |
|---|---|---|
| Sentetik Auth/PostgREST/SQL tüm faz zinciri | **1046/1046 PASS, 1046 tekil ID**, cleanup PASS | Gerçek izole DB, taklit sağlayıcı; native/store/production değil. 82 kaynak hash'i. |
| İzole legacy kopya upgrade | **33/33 PASS**, cleanup PASS; 26 candidate migration | Kaynak yedek yalnız okundu; eski satır/helper koruma geçti. Tam uygulama restore ve Storage byte kabulü bu koşu değil. 58 kaynak hash'i. |
| P01 transaction/personnel prototip DB | **135/135 PASS**, cleanup PASS | Yeni Docker inspection gerçek konteynerde de geçti. Üretim sözleşmesinin tamamı değil; 21 kaynak hash'i sonradan da eşleşti. |
| Foundation | **436/436 PASS** | Yerel guard/unit/contract testleri. |
| Bütün `scripts/isg/*.test.mjs` | **482/482 PASS** | Foundation ve NOVA ile örtüşür; test sayılarını toplayarak kapsam büyütme. |
| NOVA | **24/24 PASS** | Tasarım kaynak/contract kontrolleri; bu tur yeni UI build/cihaz kabulü yok. |
| P00 yedek bütünlüğü | 31 ana hash, 588 Storage hash, 6 arşiv ve Git bundle PASS | 131 COPY tablosu, 208 kullanıcı, 210 identity; `restore_proven=false` bu aracın doğru sınırıdır. |
| Teknik kimlik / fonksiyon haritası | PASS / PASS | Kimlik source assertion; fonksiyon haritası sadece 10 transport dosyası, test çalıştırmaz. |
| P19 kabul defteri | 263: **covered 0 / partial 20 / blocked 166 / unclaimed 77** | `release_ready=false`; bu tur tam senaryo kabulü ilan edilmedi. |
| Yerel Supabase advisor | İSG kapsamı: **0 ERROR / 0 WARN / 290 INFO** | Yeni sentetik DB'nin index kullanım bilgisi production performans kanıtı değildir; FK index'leri kaldırılmadı. |

Raporlar: `output/isg/runs/synthetic-auth-luSod4/REPORT.json`, `backups/isg-auth-service-restore-20260912-v54pyZ/REPORT.json`, `output/isg/runs/6d55739e-c84e-4fe9-b7c7-67ab98bcab3e/database-contract.json`. Önceki ara koşu `synthetic-auth-7C8ots` kaynak düzenlemesiyle örtüştüğü için son kanıt olarak kullanılmadı. Yeni drift kontrolü yalnız envanterdeki dosyaları kapsar, bütün repo immutable snapshot garantisi değildir.

İlk offline tur yeni SQL ifadesini eski regex ile aradığı için kırmızıydı; davranış kontrolleri korunarak guard beklentileri güncellendi, yukarıdaki son turlar sıfır hatayla geçti. Node'un üst dizindeki package type eksikliği nedeniyle verdiği `MODULE_TYPELESS_PACKAGE_JSON` uyarısı test hatası değildir; workspace dışındaki `/Users/keremkayalar/package.json` değiştirilmedi.

## Uygulama sınırı

Düzenlenen SQL dosyaları canlıya uygulanmamış candidate migration'lardır. Önceden bu candidate'ları yüklemiş yerel bir DB'ye `CREATE` dosyalarını tekrar çalıştırma: disposable DB'yi yeniden kur veya ayrıca sürümlü forward migration hazırla. Kullanıcının mevcut değişiklikleri, legacy doküman silmeleri ve artifact klasörleri korunmuştur.
