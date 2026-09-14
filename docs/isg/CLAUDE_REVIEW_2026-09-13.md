# Claude sonrası inceleme — durum, hatalar ve kalan işler

> **Takip paketi:** Kullanıcının düzeltme talebiyle R1–R5 için altyapı düzeltmeleri eklendi. Bu belge ilk incelemenin tarihsel bulgularıdır; güncel uygulama sınırları ve açık ürün kararları için [düzeltme/UI hazırlık kaydı](REVIEW_FIXES_UI_ITERATION_2026-09-13.md) okunmalı.

İnceleme tarihi: 13 Eylül 2026. Dal: `codex/isg-transition-foundation`.
Karşılaştırma: `8304f5b4..69a20166` (altı commit; P14–P19). Paketlerin dosya adlarındaki 14 Eylül tarihleri korunmuştur; sıralama için Git commit'leri esas alınmıştır.

## Sonuç ve kapsam

Claude sunucu çekirdeklerini ve iOS yerelleştirmesini ilerletti; P14–P19'un tamamını ürün olarak bitirmedi. Yeni paketler canlıya açılmış kabul edilemez. Legacy hak otoritesi korunuyor; yeni rollout kapıları kapalı. Bir sonraki öncelik yeni tablo/faz eklemekten önce kampanya doğrulamalarını, kabul kanıtı eşlemesini ve gerçek entegrasyonları tamamlamak olmalı.

Bu inceleme kaynak kodu, V5 planı, altı commit ve kayıtlı kanıtların karşılaştırılmasıdır. Yeni kampanya bulguları kaynak üzerinden doğrulandı; ayrı negatif SQL reproducer'ları bu tur yazılmadı. Bu bir kapsamlı güvenlik taraması veya yeni fiziksel cihaz/store kabulü değildir. Uygulama kodu ve migration'lar değiştirilmedi.

## Yeniden doğrulama

| Kontrol | Bu incelemedeki sonuç |
|---|---|
| `node scripts/isg/run_suite.mjs foundation` | 424/424 PASS, fail/skip 0 |
| `node scripts/isg/run_suite.mjs nova-design` | 24/24 PASS, fail/skip 0 |
| `node scripts/isg/acceptance_ledger.mjs` | 263 senaryo; covered 0, partial 20, blocked 166, unclaimed 77; release_ready=false |
| `node scripts/isg/run_auth_restore.mjs --synthetic-session` | 1007/1007 PASS (1006 tekil), cleanup PASS; gerçek kaynak erişimi yok |
| Upgrade / iOS build / Android build / cihaz / store | Bu tur yeniden çalıştırılmadı; paket belgelerindeki sonuçlar tarihsel kanıttır |

Yeşil foundation testlerinin bir kısmı kaynak/kontrat guard'ıdır. Bunlar aşağıdaki eksik iş senaryolarının geçtiği anlamına gelmez. `covered=0` da projede hiç uçtan uca test olmadığı anlamına gelmez: P05 gerçek native→SDK→DB kabulü daha önce yapılmıştır.

Yeni yerel sentetik kanıt: `output/isg/runs/synthetic-auth-79y1bS/REPORT.json`, run_id `9df090bd-1b4d-4994-9f57-3bc059d336d8`. Başlangıç/bitiş: 2026-09-13 18:26:16–18:28:36 UTC. Bu ignored yerel çıktı başka makineye otomatik taşınmaz.

## Kaynakta tespit edilen sorunlar

### R1 — Yüksek: ödül, başka kampanyanın sürümüyle verilebilir

`supabase/migrations/20260914110000_isg_campaign_core.sql:396` içindeki `award_referral_reward`, sürümün yalnız `published` olmasını kontrol ediyor. `version_row.campaign_id = claim_row.campaign_id` kontrolü yok. A kampanyasında qualified olmuş claim, B kampanyasının yayımlanmış sürümü verilerek B bütçesinden ve B ödül kodlarıyla işlenebilir. Qualification fonksiyonunda aynı sahiplik kontrolünün bulunması ödüllendirme çağrısını korumuyor.

Yapılacak: sürüm bulunmasını ve claim'in kampanyasına ait olmasını doğrula; qualification sırasında sürümü sabitle. Farklı kampanya sürümü, olmayan sürüm ve qualification sonrası sürüm değişimi negatif testleri ekle. Bunlar private, kapalı fonksiyonlardır; mevcut istemciden erişilebilir açık iddiası değildir, bağlanmadan önce giderilmesi gereken iş kuralı hatasıdır.

### R2 — Yüksek: davet ödülü sınıflandırması V5 §33.1 ile uyuşmuyor

Qualification yalnız state/zamanı yazıyor (`:339`); ödül türü daha sonra `award_referral_reward` içinde o anki projection ve çağıranın `p_plan_period` değeriyle seçiliyor (`:398–421`). Böylece qualification ile award arasında plan değişince kazanılan ödül de değişebilir. Ayrıca bütün mağazalar içindeki son satır seçiliyor; bir mağazadaki daha yeni expired kaydı diğer mağazadaki aktif aboneliği maskeleyebilir. Grace durumu bekletilmiyor, aylık ücretli kola giriyor. Yıllık/unknown kolunda claim kalıcı rejected yapılıyor ve davet edilenin hediyesine de ulaşılmıyor.

Plan §33.1 ödül türünü qualification anında sabitler; grace/bilinmeyen durumda bekletme ister. Yıllık hak bankalama ayrıntısı karar gerektirse de kalıcı ret ile eşdeğer değildir. Planın açık ödül matrisi davet edilene 7 gün Plus öngörür.

Yapılacak: doğrulanmış hesap çapı store özeti, qualification snapshot'ı ve bekleyen uygunluk durumu oluştur. Free→paid / paid→Free arası değişim, iki store, grace, unknown ve yıllık davetçi testlerini ekle. Yıllık bankalama kararını açık tut; kararsızlığı sessiz kalıcı redde çevirmeme davranışını belirle.

### R3 — Yüksek: winback temasında tam uygunluk tekrar kontrol edilmiyor

`record_winback_contact` (`:532–536`) yalnız en son projection'ın active/in_trial/grace olmasını engelliyor. İlk açılışta kullanılan `winback_eligibility` ise diğer store, hold/pause, refund/revoke ve aktif hediye gibi ek engelleri kontrol ediyor (`:441–461`). Episode açıldıktan sonra bu koşullardan biri değişirse contact kaydı yine üretilebilir; diğer store'daki aktif abonelik de son expired satırı tarafından maskelenebilir.

Yapılacak: temas rezervasyonu/gerçek gönderim sınırında ortak güncel uygunluk kontrolü kullan; geçerli zaman ve kanal rızası denetimini koru. Episode sonrası gift activation, refund, pause ve diğer mağazada resubscribe senaryolarını test et. Bugünkü fonksiyon `delivery_claimed=false` döndürüyor; gerçek istenmeyen push gönderildiği iddia edilmiyor.

### R4 — Orta: kabul defteri senaryo bazlı kanıtı yeterince doğrulamıyor

`scripts/isg/acceptance_ledger.mjs:34` kanıt JSON'undan yalnız kısa kabul kimliğini ve dosya adını alıyor; PASS sonucu, mevcut kaynak hash'i ve koşulmuş test kimliği doğrulanmıyor. `:103` civarındaki karar global katman durumlarını kullanıyor: P05 API kanıtı başka domain'in API kabulünün yerine geçebilir. Registry'de iki DEL-01 tam kimlikle korunmuş olsa da claim eşlemesi hâlâ kısa kimliğe dayanıyor.

Bugünkü çıktı kapalı ve ihtiyatlıdır. Ancak katmanlar ileride full yapıldığında eski/ilgisiz kanıtla covered üretme riski vardır. Yapılacak: tam senaryo kimliği × katman × test kimliği × başarılı koşu × kaynak revizyonu eşlemesi; başarısız/eski/yanlış domain kanıtına negatif test. Global full bayraklarını doğrudan senaryo kabulü yerine kullanma.

### R5 — Orta: bilinen yıkıcı yerelleştirme aracı düzeltilmemiş

`scripts/migrate_swift_localization_catalogs.mjs:1855` katalogları boş koleksiyonlardan yeniden kuruyor; `:1994` mevcut katalogları üzerine yazıyor. P18 belgesi 300 anahtar kaybı (216 aktif referans) yaşandığını, katalogların kurtarıldığını fakat aracın düzeltilmediğini açıkça kaydetmiş. Katalog sayısı alt sınır guard'ı tam anahtar koruma veya idempotency garantisi değildir.

Yapılacak: mevcut katalogları birleştirerek güncelleyen writer; bilinmeyen/mevcut anahtar ve çeviri metadatasını koruma; iki kez çalıştırmada sıfır diff ve anahtar kümesi testi. Düzelene kadar `--apply`/`--write-catalogs` kullanma. Bu tur bu komutlar çalıştırılmadı.

## Claude'un düzelttiği işler ve açık kalan ayrım

- P15: suppression yazdıktan sonra exception nedeniyle kaydın rollback olması düzeltildi; rıza eksikliğinin episode'u tümden kapatması giderildi; dört eksik FK indeksi eklendi. Bunlar gerçek kod iyileştirmeleridir; test fixture düzeltmeleriyle aynı kategoride sayılmamalı.
- P18: kaybolan katalog anahtarları geri kondu; otomasyonun kaçırdığı metinler elle taşındı; localization bağımlılığı yüzünden kırılan izole notebook sözleşmesi için label modelden görünüm katmanına taşındı. Araç kök hatası açık kaldı.
- P14/P16/P19: constraint fixture, fonksiyon argümanı, kendi kendine kıyas, SECURITY DEFINER ve modül anahtarı varsayımları gibi test/prova sorunları giderildi. Bunlar tek başına yeni üretim davranışı düzeltildiği anlamına gelmez.

## Planla karşılaştırma ve yapılacaklar

| Alan | Gerçek ilerleme | Kapanış için kalan |
|---|---|---|
| P14 billing | Lifecycle evidence/projection, gift–discount ayrımı, settlement/reconciliation çekirdeği | RevenueCat/webhook→P01 tüketicisi, gerçek store teklifleri ve restore/refund senaryoları, paywall, P03 hak otoritesi cutover |
| P15 kampanya | Canonical referral, sunucu qualification kanıtı, bütçe ve winback kayıtları | R1–R3, gerçek mutation producer/scheduler, bildirim adaptörü, native link/teklif UI, yıllık/çakışma/tavan kararları |
| P16 izleme/admin | Sınırlı teknik zarf, destek/audit, scope/session ve action defteri | Native producer/kuyruk, gerçek Auth/MFA ve domain action bağlantısı, OperasyonMerkezi ekranları, gerçek ağ gizlilik kabulü |
| P17 skor | Sürümlü politika, katkı hesapları, immutable snapshot ve örnek oracle | P06–P10'dan gerçek veri üreticileri, onaylı ağırlık/critical tanımları, native/admin portföy ve sonuç kabulleri |
| P18 NOVA | iOS tarafında 261 yeni TR/EN anahtar ve ikon erişilebilirlik adları | R5, Android çevirileri, uzman dil incelemesi, EN/VoiceOver/Dynamic Type cihaz turu, app root ve gerçek modül servisleri |
| P19 kabul | 263 satırlık envanter ve bütün kapılar kapalıyken legacy koruma provası | R4, senaryo bazlı kanıt eşleme, gerçek cross-layer akışlar, hesap silme, 16 binary/backend kombinasyonu, store/operasyon kabulleri |
| P01/P04/P06–P13 | Önceki domain/queue/dosya/not/reminder çekirdekleri korunuyor; P05 yerel native kabulü var | Gerçek tüketici/worker bağlantıları, AV/parser, PDF/XLSX renderer, mevzuat içeriği onayı, modül ekranları; P12 provider ortamı ve P13 offline reminder/deep-link/cihaz kabulü |
| P20/P21 yayın/operasyon | Bu altı commit'te kapanış kanıtı yok | Mağaza matrisi, rollout/rollback, dış disk yedek ve ölçülmüş RPO/RTO, destek/izleme/retention süreçleri |

Öncelikli sıra:

1. R1–R3 kampanya doğrulamalarını negatif SQL testleriyle kapat; yeni kampanyayı açma.
2. R4 kabul eşlemesini ve R5 katalog aracını düzelt; yeşil testlerin kapsamadığı sınırları otomatik denetime al.
3. Entegrasyon dilimlerini uçtan uca tamamla: gerçek domain mutation→P01 tüketici→skor/task/bildirim; notebook reminder→worker→cihaz. Her dilime görünür native sonuç ve hata senaryosu ekle.
4. P14 store bağlama, P04/P11 güvenli dosya/render ve P16 gerçek admin/telemetri yollarını tamamla. Yetki/canlı ayar gerektiren adımları ayrı onayla yürüt.
5. Android/iOS NOVA paritesi ve gerçek modül ekranları; ardından P19–P21 kabul ve kademeli yayın kapıları.

## Doküman uyuşmazlıkları

- Güncel durumun girişindeki “aktif P13” eski kaldı; son eklenen paket P19, ürün fazları hâlâ kısmi.
- P19'daki “hiçbir gerçek native→server→görünür sonuç yok” ifadesi P05 kabul kanıtıyla çelişir. Doğru eksik, bütün yeni modüllerin cross-layer kapsamıdır.
- Layer defterindeki NOTES “offline queue missing” ifadesi not kuyruğu için eski bilgidir. Eksik olan offline reminder mutation ve gerçek iki cihaz kabulüdür.
- STORAGE “byte-level restore untested” ifadesi P00'daki `storage_588_api_download_hash_size_mime_cache_match` ve `all_bytes_tested:true` kanıtıyla çelişir. Yeni domain bucket/policy ve ölçülmüş RPO/RTO açık kalır.
- P15 “Plus7 ve %20 hep aday” ifadesi V5 §33.1 ile uyuşmuyor: miktarlar kullanıcı kararıdır. Qualification, tekrar tavanı, yıllık bankalama ve temas zamanlaması ile store yayın onayı ayrıca açıktır.

Bu rapor eski kanıtları silmez, mevcut registry durumlarını yükseltmez ve katmanları otomatik full yapmaz. Önceden silinmiş legacy belgeler ile mevcut untracked artifact dizinlerine dokunulmadı.
