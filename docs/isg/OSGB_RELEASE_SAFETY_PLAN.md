# OSGB — canlı kullanıcıları koruma ve yayın planı

17 Eylül 2026 · [Tam entegrasyon ana planının](OSGB_FULL_INTEGRATION_PLAN.md) yayın eki.

**Şimdi:** planın karar bağımsız bölümleri yerel, deploy edilmemiş aday kod/SQL olarak uygulanmıştır; [uygulama durumu](OSGB_IMPLEMENTATION_STATUS_2026-09-17.md) ve [hash manifesti](OSGB_CANDIDATE_MANIFEST_2026-09-17.json) kanıtı taşır. Canlı DB/API/storage/auth/billing/feature flag/uygulama dağıtımı değiştirilmedi. Bu belge canlıya çıkma izni değildir. Bugünkü bireysel müşterileri başka veri tabanına taşıma veya uygulamayı yeniden kurdurma yok.

**İleride:** tam OSGB özelliğinin aynı uygulamada açılması kontrollü backend/schema/client değişiklikleri gerektirecek. Hedef mevcut kullanıcıların verisini, haklarını ve kullanımını korumak; bunu “canlıda hiç değişiklik yapmadan özellik yayınlandı” veya “sıfır risk” diye sunmamak. Aşağıdaki kapılar tamamlanmadan canlı değişiklik başlamaz.

## 1. Ortamların ayrılması

| Ortam | İzinli kullanım | Yalıtım |
|---|---|---|
| Yerel planlama | Docs, kaynak inceleme, çevrimdışı sözleşme tasarımı | Production tool/credential kullanılmaz |
| Geliştirme | Yeni branch/worktree, disposable DB, synthetic A/B/P fixture | Ayrı URL/key/bucket; dış email/push/AI/payments stub |
| Staging | Gerçek release zinciri provası, maskelenmiş veri profili, store sandbox, test object'ler | Ayrı Supabase proje ve storage, test RC/store/environment identity, allowlist mail/push |
| Production dark | Yalnız sonraki somut onaylı release'in additive şeması/versioned endpoint'leri | OSGB flags off; personal mevcut davranış; yeni job schedule default off |
| Production pilot | Seçilmiş OSGB workspace cohort | Server allowlist + client capability + tüm scope enforcement; personal kitleye yayılmaz |
| Genel OSGB yayın | Pilot kapıları geçtikten sonra | Cohort artışı, metrik/gözlem ve kill switch |

Geliştirme/test uygulaması farklı bundle/app build kimliği ve net ortam göstergesiyle hazırlanır; fiziksel telefondaki canlı build yanlışlıkla üzerine yazılmaz. Staging müşteri email/telefon/device token'larını içermez. Production dump gerekirse ayrıca izinli, erişimi sınırlı ve maskelenmiş işlem; repo/CI artifact içine koyulmaz. Storage snapshot gerçek dosya içerdiğinden DB kadar korunur.

Gelecekteki deployment aracı hedef proje kimliğini manifestle eşleştirmek zorunda; default production URL, shell'den miras kalan key veya yanlış CLI link ile çalışmaz. Dry-run default; production write adımı explicit hedef ve release paketine bağlıdır. CI test işi deploy hakkı taşımaz. Environment mismatch store event'i entitlement/grant üretmez.

## 2. Korunacak personal sözleşmeler

1. Mevcut kullanıcı aynı login/hesapla girer; zorunlu OSGB üyeliği veya yeniden satın alma yok.
2. Firma, personel, analiz/finding/result sections, dosya/logo/rapor ID ve erişimleri korunur. Genel object path taşıma ilk geçişe eklenmez.
3. RevenueCat app user identity, alias/restore davranışı ve kişisel abonelik zinciri koruma altındadır. Workspace seçimi RC `logIn` ile kişisel satın almaları başka kimliğe birleştirme aracı olmaz. Workspace billing intent/binding ayrı katmandır.
4. Eski quotas/paid entitlements değişmez. Personal usage hem legacy hem OSGB ledger tarafından iki kere ücretlenmez; yeni OSGB balance personal'a taşınmaz.
5. Eski app sürümleri aynı dış API sözleşmesiyle personal verisine erişir. OSGB verisini göremez; unsupported workspace için açık unavailable olur, gevşek owner-only fallback yok.
6. Personal migration mapping'i mevcut owner'dan türetilir; kullanıcı beyanı/isim/email benzerliğiyle başka kişiye sahiplik bağlanmaz.
7. Yeni UI rollout eski kullanıcıyı istemediği OSGB paneline sokmaz. Bir kullanıcı iki OSGB'de olsa da personal cache ve hakları ayrı kalır.
8. Kullanıcı silme ve OSGB'den üyelik ayrılması aynı işlem değildir. Ortak şirket verisi, satın alma binding'i ve kurumsal author geçmişi uzman silinmesiyle cascade silinmez; kişisel veri retention/anonimleştirme kararı ayrıca uygulanır.

Bu sözleşmeler old-client sentinel fixture'larıdır: giriş/refresh/background; firma create/edit/archive/logo; personnel; analiz create/history/expert/training sections; bulgu atama+detay; file upload/download; PDF/XLSX; purchase/restore/renewal; bildirim; account deletion. Her release dilimi ilgili sentinel'ı geçer.

## 3. Kaynak ve dağıtım zinciri

Root `supabase/migrations` ile `supabase/pilot-release/candidates` ve `supabase/pilot-release/supabase/migrations` tek zincir varsayılmaz. Mevcut [release README](../../supabase/pilot-release/README.md) bu konuda uyarır. Genel `supabase db push`, migration repair ile uygulanmamış adımı applied işaretleme ve ledger aynasını elle düzenleme kullanılmaz.

Release manifest şunları taşır:

- Kod HEAD, hedef environment/project, mevcut son migration sürümü ve SQL hash listesi.
- Yeni candidate SQL hash, sıralı bağımlılıklar, active policy/grant/function/trigger önkoşul ve sonkoşulları.
- Her tablo için mevcut boyut, etkilenecek satır sayısı, lock/index/backfill maliyeti; staging ölçümleri.
- Client minimum OSGB capability version; eski personal sürüm sözleşmeleri; Edge Function ve worker version uyumu.
- Feature flag rollout scope'u; offline/dark davranış; job/notification/finalization sahipliği.
- Dry-run çıktısı, checkpoint, veri karşılaştırma raporu, test artifact ve rollback provaları.

Manifest DB state'iyle uyuşmazsa deploy durur. Migration başarı logu tek başına tüm client+worker+RLS entegrasyonunun kabulü değildir.

## 4. Expand → backfill → verify → enforce → contract

### 4.1 Expand — OSGB verisi yaratmadan şema

Yeni tablolar, gerektiğinde nullable scope sütunları ve versioned RPC'ler additive eklenir. Yeni index büyük tabloda ölçülmüş yöntemle; NOT NULL veya ağır validation tek uzun transaction'a konmaz. Concurrent index gerektiğinde migration transaction sınırı ayrıca tasarlanır; tüm DDL'nin transactional olduğu varsayılmaz.

DDL için onaylı lock/statement time budget; lock beklenenden uzarsa fail-fast. Otomatik sınırsız retry yok; personal iş yükü sağlıklı değilse ilerleme durur. Feature flag kapalı olması DDL lock veya trigger maliyetini ortadan kaldırmaz; dark deploy da risk ölçümü ister.

Tüm yeni tablolarda RLS/grant/EXECUTE açığı olmadan deploy. OSGB firması henüz yazılmaz. Eski owner policy'nin yeni satırı açabileceği dönem yaratılmaz.

### 4.2 Backfill — sınırlı, tekrar çalışabilir mapping

Sıra: users/profiles → personal workspaces → owner memberships → companies → workplaces/domain parents → children/filing/assets → analiz/job/rapor scope → billing mapping → türetilmiş projection. Her domain kendi PR ve checkpoint'ine sahip. Firma dışı personal not/analiz/asset doğrulanmış owner'dan personal scope alır.

Default dry-run sadece sayım/constraint/anomali üretir. Write batch ancak ayrı onaylı hedefte: deterministic cursor, batch transaction, unique mapping, request hash, source version, checkpoint. Pause/resume/retry aynı mapping'i üretir. Orphan/mixed-owner/mixed-parent kayıt review kuyruğuna; otomatik tahmin yok.

**Eşzamanlı eski istemci yazımları:** geçiş boyunca yeni personal insert/update için küçük server compatibility adapter/trigger doğrulanmış personal workspace'i atar. Bu yol henüz kurulmadıysa backfill tamamlandı kabul edilmez. Yalnız bir kez mevcut tabloyu tarayıp yeni null satırları kaçırma. Old/new writer race ve backfill cursor'dan sonra gelen kayıtlar test edilir; gereksiz customer write freeze yapılmaz.

İkinci operasyon veritabanına dual-write önerilmez; tek domain kaynağı korunur. Yeni projection gerekiyorsa idempotent outbox ile türetilir. Karşılaştırma amaçlı dual-read duplicate email/push/AI/charge doğurmaz.

Personal satın alma/ledger için mevcut grant taşınırken ikinci opening grant oluşturulmaz. Owner sınıfı olmayan aktör alanı ownership kanıtı olarak kullanılmaz. Sırf mapping için author/current responsible değişmez. Storage object kopyalama/yeniden adlandırma ayrı iş, ilk backfill değil.

### 4.3 Verify — veriyi karşılaştır

Her batch ve finalde aşağıdaki sayımlar kaynak ID/checksum ve workspace dağılımıyla karşılaştırılır; rapor PII içermez:

| Kontrol | Kabul |
|---|---|
| Personal workspace/owner membership | Eligible kullanıcı başına tam bir; duplicate yok |
| Company ve domain parent/child | Kayıp ID yok; null scope/onaylanmamış orphan/mismatch yok |
| Tarihsel author / assignment | Creator değişmemiş; primary/dönem çakışması yok |
| File/asset/object | Eski path açılır; version/digest/byte/source referans uyumu; arşiv ve fiziksel delete ayrımı |
| Billing/credit | Subscription binding korunmuş; grant/ledger balance farkı açıklanmış; duplicate charge/grant yok |
| Jobs/outbox/idempotency | Pending işlem owner/workspace'i doğru; eski key retry duplicate üretmiyor |
| UI/RPC/statistics | Eski personal liste/özet/rapor ile yeni personal projection beklenen şekilde eşit |

Veri drift'i çözülmeden enforcement veya yeni cohort yok. İzin reddi sayısını artıran kapsamlı yanlış mapping, veri kaybı olmasa da release hatasıdır.

### 4.4 Enforce — OSGB'yi açmadan izolasyon

Validated constraints/NOT NULL, composite FKs, immutable workspace, indexes ve effective RLS policy bütünü domain bazında devreye girer. Eski endpoint yalnız personal scope kabul eder. Eski permissive owner policy ile yeni member policy'nin OR birleşimi OSGB'yi açmamalı; tüm policy seti birlikte test edilir. Legacy identity sütununa creator yazmak onun owner-only sorguyla OSGB'ye erişebilmesi anlamına gelmez.

**İlk OSGB satırı önkoşulu:** ilgili domain'in yeni read/write ve eski read/write yolları, alt dosya/export/worker/cleanup zinciri birlikte güvenlidir. Domain kapalıysa direct RPC ile de kapalı. Bir flag'in kaldırılması policy'yi gevşetemez. Yeni endpoint yeni client'a, personal compatibility endpoint eski client'a yönlendirilir; sunucu client beyanına güvenmeden scope'u doğrular.

### 4.5 Contract — ilk yayının dışındaki temizlik

Eski kolon veya fonksiyon kaldırma ancak kullanım telemetrisi, desteklenen eski sürüm politikası ve restore etkisi ölçüldükten sonra ayrı PR. İlk OSGB yayını için toplu rename/drop, cascade delete veya geri döndürülemez veri birleştirme yapılmaz. Tarihsel yazar, audit ve financial referansların kaldırılması temizlik sayılmaz.

## 5. Feature flag ve kapatma tasarımı

Aşağıdaki mantıksal bayrak aileleri yerel SQL adayında `workspace_rollout` ve `workspace_domain_rollout` olarak oluşturuldu. Tüm read/write değerleri varsayılan kapalıdır; staging veya production'da henüz oluşturulmadı.

| Flag ailesi | Kapsam | Kapatınca |
|---|---|---|
| OSGB navigation/onboarding | Environment + allowlisted workspace/user | Yeni OSGB giriş/kurulum kapanır; personal görünüm kalır |
| Workspace member/company mutation | Workspace + action | Yeni yönetim/atama komutu durur; güvenli read ve audit korunur |
| Domain read/write | Workspace + domain | Sorunlu alan unavailable/read-only; owner-only fallback yok |
| Purchase/credit intent | Workspace + product/environment | Yeni satış başlamaz; mevcut store events/reconcile/finalization devam |
| AI job start | Workspace + feature | Yeni maliyetli job yok; pending iş settle/reconcile edilir |
| Upload finalize/start | Workspace + pipeline | Güvenli quarantine cleanup/reconcile sürer; izinsiz yayın yok |
| Handover create/execute | Workspace + command | Yeni devir durur; schedule pause + revalidation; history silinmez |
| Admin privileged commands | Action + global grant | Destek komutları kapanır; normal kullanıcı rolü genişlemez |

Server flag zorunlu, client flag yalnız deneyim. Kritik yetki sorgusu başarısızsa yeni erişim kapalı; mevcut personal path'i OSGB config servisinin kesintisine gereksiz bağlama. Flag audit'i before/after/reason/actor içerir. Kill switch RBAC için bypass değildir.

## 6. Yayın kapıları

| Kapı | Gerekli kanıt | Geçmeden yapılamaz |
|---|---|---|
| G0 — plan hazır | Mandatory trace satırları, karar listesi, canlı sınırı | Implementation scope tamamlandı iddiası |
| G1 — geliştirme hazır | Ayrı environment, baseline manifest, test fixtures, migration tasarımı | Staging DB upgrade |
| G2 — staging hazır | B–J zorunlu acceptance, iOS/Android/admin, sandbox billing, data/permission reconciliation | Production release paketi önerisi |
| G3 — yayın paketi hazır | Backup/restore+rollback prova, sayısal metrik/lock bütçesi, sorumlu, product/config, exact diff/hash | Kullanıcıya somut canlı yayın onayı sunma |
| G4 — production dark kabul | Ayrı onaylı deploy, personal sentinel ve dark backend sağlığı | OSGB pilot açma |
| G5 — pilot kabul | Allowlist OSGB e2e, ledger/storage reconciliation, old-client checks, gözlem penceresi | Cohort büyütme |
| G6 — genel OSGB kabul | Tekrarlı cohort sağlığı, support runbook, incident owner | Tam yayın tamamlandı iddiası |

G3 paketinde ne değişecek, kaç satır/bucket/endpoint etkilenecek, beklenen kullanıcı davranışı, bilinen risk, durdurma ve geri dönüş net olur. Kullanıcı şu anda yalnız plan istediği için G4'e otomatik geçilmez. İç test onayları canlı kullanıcıya email/push veya gerçek satın alma başlatma yetkisi sayılmaz.

## 7. Metrik eşikleri ve otomatik durdurma

Sayısal SLO/kapasite eşikleri staging ölçümü ve ürün/operasyon onayıyla doldurulur. “Normal görünüyor” veya boş eşik release kabulü değildir. Önerilen sıfır toleranslı olaylar: cross-tenant veri görünmesi/yazılması, duplicate debit/grant, beklenmeyen veri silinmesi, eski müşterinin doğrulanmış satın alma hakkının kaybı. Böyle bir olayda cohort artışı ve ilgili yeni işlem anında durur.

Ölçülecek alanlar: personal endpoint hata oranı/p95-p99 gecikme/lock wait; auth ve scope retleri; create/readback uyumu; mutation conflict ve retries; queue lag/oldest age; pending verification/finalization; wallet drift/over-reserve; storage drift/orphan/quarantine; client crash ve unavailable oranı. Metriklere PII/prompt/receipt eklenmez.

Runbook kayıt alanları: baseline pencere ve sürüm, kabul edilmiş eşik, minimum gözlem süresi, cohort boyutu, alarm sahibi, rollback karar sahibi, son successful drill. Ölçüm toplayıcı bozulursa güvenli yayın kanıtı yoktur, rollout ilerlemez. Uyku/sabit süre sonunda onay verilmiş varsayılmaz.

## 8. Arıza ve geri dönüş senaryoları

| Olay | İlk adım | Korunacaklar |
|---|---|---|
| DDL lock/statement budget aşıldı | Migration'ı durdur; kısmi/nontransactional adımı manifestle reconcile | Personal servis erişimi; kör retry yok |
| Backfill yanlış scope | Job pause; cohort kapalı; etkilenen batch review/forward correction | Eski owner/author/source snapshots; toplu silme yok |
| Yeni endpoint/client hata | OSGB route/domain kapat; personal uyumlu sürüme dön | Tenant-aware constraints; eski owner OR açılmaz |
| Tenant sızıntısı | İlgili read/write/URL issuing kapat, yetkili erişimi sınırla, olay kaydı | Audit/evidence; UI kapamak tek başına yetmez |
| Grant/debit/finalization farkı | Yeni intent/job başlatmayı durdur, provider transaction'la reconcile | Store inbox, ledger, pending reserves; ikinci grant yok |
| Storage drift/failed delete | Destructive cleanup pause; object/metadata reconcile | Dosya içerikleri, filing links, uploader geçmişi |
| Devir job partial | Firma başına sonuç kaydıyla failed olanı retry | Başarılı firmalar tekrar devredilmez; new author işleri ezilmez |
| Admin yetki hatası | Privileged action kapat/revoke grant/session | Append-only admin audit; müşteri login sistemi çalışır |

Genel DB snapshot restore normal rollback değildir: snapshot sonrasında yazılmış gerçek kullanıcı verisi ve store transaction'ları kaybolabilir. Tercih küçük roll-forward düzeltme veya flag/route rollback. Restore zorunluysa incident planıyla source timeline, store event replay, outbox/AI/ledger reservations, DB-object reconciliation ve kayıp yazı kurtarma yapılır. RPO/RTO ölçülmeden garanti verilmez. Backup yalnız DB ise object içeriğini kurtardığı varsayılmaz.

Üretilmiş signed URL anında iptal edilebilir varsayılmaz; TTL ve gerekirse yetkilendiren proxy kararı kapı öncesi verilir. Membership revoke yeni URL/job/export'u keser; pending maliyetli işin muhasebesi tanımlı settle/reconcile yolundan geçer.

## 9. Tamamlanma ve değişiklik kaydı

Bu uygulama tesliminde yerel istemci kodu, testler ve `NOT DEPLOYED` SQL adayları eklendi. Mevcut canlı servis davranışı ve canlı ayarlar değişmedi. Adayların kesin sırası/hash'i manifestte, gerçek uygulama ve eksik kabul durumu ayrı durum belgesinde kayıtlıdır.

Gelecekte her release sonunda: gerçek deployed hash/versions, flag durumu, migration/backfill sonucu, doğrulanan eski/new client build'leri, test kanıtı, drift tablosu, açık incident ve sıradaki gate güncellenir. Planın “Planlandı” durumunu yalnız bu kanıtlarla “Kabul edildi”ye çevir. Harici sistem kararları veya eksik admin frontend nedeniyle tamamlanmayan modülü tam entegrasyona dahilmiş gibi sayma.
