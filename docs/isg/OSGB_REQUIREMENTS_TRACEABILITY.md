# OSGB tam kapsam — gereksinim ve kabul matrisi

> Güncel kabul durumu [son genel incelemede](OSGB_FINAL_REVIEW_2026-09-17.md). D1–D7 cursor sayfalama, sabit mutasyon denemesi, D2–D6 yaşam döngüsü ve D1/D2 tenant-native ileri personel/eğitim akışları test edildi. Bu tablolardaki “Kabul kanıtı” sütunu beklenen kontrolü tarif eder; gerçek sağlayıcı ve yayın satırlarının kabul edildiğini göstermez.

17 Eylül 2026 · [Ana plan](OSGB_FULL_INTEGRATION_PLAN.md) · [Canlı koruma eki](OSGB_RELEASE_SAFETY_PLAN.md).

**S1:** `ISGADA_OSGB_MULTI_TENANT_INTEGRATION_PLAN_2026-09-16.md`. **S2:** `deep-research-report-2.md`. Kaynak sürümleri [hash kaydında](OSGB_BASELINE_2026-09-17.md). § numaraları S1'e aittir. S2 başlıkları en altta eşlenir.

Tablolardaki faz/PR isimleri kapsamı gösterir. Karar bağımsız backend ve istemci data katmanı yerel aday olarak uygulanmıştır; kanıt ve eksikler [17 Eylül uygulama durumunda](OSGB_IMPLEMENTATION_STATUS_2026-09-17.md), kesin migration hash'leri [aday manifestinde](OSGB_CANDIDATE_MANIFEST_2026-09-17.json) bulunur. Bunlar staging veya canlı kabul değildir. Her ID'nin mobil/admin/staging kanıtı ve açık kararı kapanmadan mandatory satır tamamlanmış sayılamaz.

## 1. Ürün, kimlik ve erişim

| ID | Kaynak | Gereksinim | Uygulama | Kabul kanıtı |
|---|---|---|---|---|
| R001 | §0–2 | Repo/HEAD/ownership ve deployment ayrımı | A1–A2/B0 | Doğrulanmış envanter, hash manifest, baseline; önerilen isim mevcut sanılmıyor |
| R002 | §0,3 | Tek workspace_id; personal+OSGB; auth/owner/author/responsible ayrımı | B1/C1/D | Personal yetkisi OSGB'ye taşınmıyor; creator devredilmiyor |
| R003 | §3,4.1 | Çoklu workspace; kişi farklı alanlarda farklı rol | B4/E1 | Aynı user A owner/B expert/P owner fixture ve client geçişi |
| R004 | §3,4.2 | Aynı gerçek firmanın ayrı tenant kayıtları, global auto-merge yok | C1 | Aynı vergi no ile A/B kayıtları izole; firma UUID kimliği; legacy aynı adlı firmalar engellenmez |
| R005 | §4.1,6 | Workspace oluşturma+ilk owner; son owner ve owner transferi | B1/B5/F2 | Atomik create, concurrent last-owner ret, audit |
| R006 | §4.1 | Üye status/practicing/history ve workspace iş profili | B1/C2 | Üyelik history korunur; personal profil/iç not ayrılır |
| R007 | §4.1 | Uzman sınıfı/belge/beyan tarihleri ve bilgi kaynağı | C2 | Self-reported/uploaded-document etiketi; resmi onay iddiası yok |
| R008 | §4.1,6 | Süreli hash davet, email, duplicate/rate limit, resend/revoke | B5/H6 | Wrong email/expired/replayed invite ret; raw token log yok |
| R009 | §6,7.4 | Davet kabulü membership+seat atomik, notification retry | B2/B5/H6 | Double accept bir üyelik; email failure yarım membership üretmiyor |
| R010 | §5.1,6 | Suspend/end/reactivate; güvenlik askısı deviri beklemez | B5/C3/D | Revoke read/write/job/download testi, personal etkilenmiyor |
| R011 | §5 | Rol/action permission matrisi ve izinli field listesi | B2/C1/D/F | Expert role/author/workspace spoof ret; admin billing ayrı |
| R012 | §5.2 | RLS+WITH CHECK+FK+private helper; policy recursion/OR/grant | B–D/K1 | Gerçek anon/authenticated rolleriyle negatif DB testleri |
| R013 | §5.2,9 | Global admin güncel grant/MFA; normal mobilde bypass yok | F1–F2 | Revoked grant, fake JWT metadata, no-MFA ret |
| R014 | §5.3,6 | Workspace selector, deep link, cache/realtime scope | B4/E1/D9 | Old response/cursor/cache A→B sızmıyor; link yetki doğruluyor |
| R015 | §5.3,6 | Başlamış upload/job/purchase ilk workspace'e sabit | D7–D8/G4/H2 | Sekme değişimi başka wallet/asset sahibi yaratmıyor |
| R016 | §14 | Versioned API/hata/pagination/idempotency/actor | B2/D/H/J | Hash mismatch conflict; localized error; cursor scope; stale version ret |
| R017 | §4.4,14 | Mevcut audit/outbox/receipt motorunu genişlet | B2/D | Audit failure rollback, dispatcher retry tek etki, fake company yok |

## 2. Firma, uzman ataması ve bütün domain'ler

| ID | Kaynak | Gereksinim | Uygulama | Kabul kanıtı |
|---|---|---|---|---|
| R018 | §4.2 | Firma/işyeri workspace, creator/updater/version/archive | C1/C4 | Company/workplace composite uyumu; old-client CRUD sentinel |
| R019 | §4.2 | Çoktan çoğa expert-company assignment ve history | C3 | Yetkili çoklu uzman; ended uzman yetkisiz; history duruyor |
| R020 | §4.2 | Primary, future effective, yarı açık dönem çakışması | C3 | Aynı primary future overlap reddi, ardışık sınır kabul |
| R021 | §4.3 | Parent-child/responsible membership scope ve immutable tenant | C/D | Cross-company ve cross-workspace FK/command ret |
| R022 | §4.3,13 | Personel/dizin/department/job/contractor/personnel assignment | D1 | **Yerel kabul geçti:** composite scope, görev/dış firma/sözleşme, etkili tarih ve overlap reddi; personal kayıt ayrı |
| R023 | §4.3,13 | Eğitim/müfredat/katılım/sertifika/yıllık eğitim | D2 | **Yerel kabul geçti:** tenant-safe müfredat/konu/sınav/plan/sertifika, katılım ve saat/kişi istatistikleri |
| R024 | §4.3,13 | Risk değerlendirme ve sürümleri | D3 | Source file/version/detail/export izinleri |
| R025 | §4.3,13 | Uygunsuzluk, action/verification, checklist | D3 | Analizden firmaya commit/readback/detail; state/audit doğru |
| R026 | §4.3,13 | Acil durum ve tatbikat | D4 | Plan/personel/rapor aynı scope; gerçekleşme bilgisi korunur |
| R027 | §4.3,13 | Temsilci/destek atamaları ve KKD zimmet/iade | D4 | OSGB kullanıcı atamasıyla karışmaz; employee/asset izolasyonu |
| R028 | §4.3,13 | Ekipman/envanter/periyodik kontrol | D5 | Ekipman ve rapor doğru firmada; tür/periyot override scope'u |
| R029 | §4.3,13 | Manuel KATİP, yıllık plan, kurul ve kararlar | D6 | Version/asset/author korunur; resmi entegrasyon izlenimi yok |
| R030 | §4.3,13 | Çalışma izni, ziyaret/observations, onaylı defter arşivi | D6 | Yetkili firma history ve kaynak dosya; planlanan/gerçekleşen ayrı |
| R031 | §4.3,10 | Dosya library/personal filing/shared assets/legacy buckets | D7 | Yetkisiz blob/filing link ret; eski logo/fotoğraf/rapor açılır |
| R032 | §5.3,8,14 | Analiz intake/results/findings ve background worker | D8/G4 | Job actor/scope/finance sabit; uzman görüşü/eğitim önerileri kaybolmaz |
| R033 | §5.3,14 | PDF/XLSX/report/export ve mevcut import yolları | D8 | Source selection→job→output asset→download aynı izin |
| R034 | §5.3,13,15 | Tracking/score/aggregate/search/notification/realtime | D9/E2 | Count/cursor/push/deep-link sızıntısı yok; scoped detay parity |
| R035 | §12,17 | Personal notes/sağlık/management-private görünürlük | D9/J4 | Firma ataması özel notu otomatik açmıyor; search/RAG negatif |
| R036 | §3,16,17 | Account deletion, membership departure, cleanup | C4/D9/K | Uzman silinmesi OSGB verisini cascade silmiyor; retention uygulanıyor |

## 3. Ekranlar, admin ve raporlama

| ID | Kaynak | Gereksinim | Uygulama | Kabul kanıtı |
|---|---|---|---|---|
| R037 | §13 | OSGB overview/firma/uzman/davet/atama/settings | E1–E2 | Owner tüm portföyü, expert yalnız atananı görür; onboarding e2e |
| R038 | §13 | Expert home/kendi iş-görev-ziyaret/bütçesi | E2/E4 | Scope'lu ekran+liste ve workspace değişimi |
| R039 | §13 | Merkezi takvim, görev ve ziyaret/son tarih projection | E3/D6 | Aynı kaynağın list/calendar/deadline tutarlılığı |
| R040 | §13 | Ortak mevcut UI/service; hazırlayan/sorumlu/onaylayan ayrımı | D/E3 | Yönetici author impersonation yok; tek domain kaynağı |
| R041 | §13,15 | Standart istatistik/detail filtre/empty/loading/TR-EN/a11y | E/K4 | iOS/Android UI kabul; unknown sıfır değil |
| R042 | §9.1 | Mevcut admin panelini genişlet, paralel uygulama yok | F1 | Gerçek panel repo/route ve auth bağlanmış |
| R043 | §9.1 | Platform overview/OSGB list-detail/expert usage | F3/F4 | Server pagination/filters ve global/workspace etiketleri |
| R044 | §9.1 | Admin operasyon/doküman/storage/AI/billing/memory/audit sekmeleri | F4 | G–J gerçek verisiyle her sekme ve işlem doğrulanmış |
| R045 | §9.2 | Create/invite/company/assign/correct/archive/suspend/reactivate/owner transfer | F2 | Whitelist+reason+version+idempotency+audit; genel SQL edit yok |
| R046 | §9.2,8.4 | Destek credit/entitlement override/reconcile | F4/I4 | Sınırlı/süreli/ek doğrulamalı; paid store kaydı taklidi yok |
| R047 | §9.3 | Güncel global grant, MFA, hassas audit, gerekiyorsa süreli support | F1–F3 | Revoke/expiry anında yeni erişim ret; audit silinmez |
| R048 | §15 | Firma/seat/ziyaret/uygunsuzluk/doküman/eğitim metrik sözlüğü | E2/D9 | Metric→filtered list parity; yasal uygunluk puanı iddiası yok |
| R049 | §15 | AI/credit/storage/billing health platform KPI | G5/F4 | Kesin debit ve rezervasyon ayrı; drift/lag görünür |
| R050 | §15 | Gelir/MRR, currency, gross/net ayrımı | H/I/F4 | Admin grant gelir değil; FX'siz toplam yok; eksik veri etiketli |

## 4. Mağaza, abonelik ve kapasite

| ID | Kaynak | Gereksinim | Uygulama | Kabul kanıtı |
|---|---|---|---|---|
| R051 | §1,7.1 | Yalnız Apple/Google, provider-neutral domain, mevcut RC koruma | H1 | Personal purchase/restore regression ve tek charge/finalization authority ADR |
| R052 | §7.1 | Client PurchaseProvider ≠ server verifier; canonical verified purchase | H1/H3/H4 | Client success tek başına entitlement yaratmıyor |
| R053 | §7.2 | Billing identity, opaque token, hedef workspace intent | H2 | App/env/product/actor/binding kontrolü; PII/token log yok |
| R054 | §7.2 | Transaction+subscription chain tek workspace, restore transfer değil | H2/H7 | Aynı receipt B workspace'te ikinci grant oluşturamaz |
| R055 | §7.2 | Owner ayrılığı≠store purchaser değişimi; çoklu OSGB ürünleme | H7 | Renewal devam; subscription-group/replacement sandbox kanıtı |
| R056 | §7.3 | Starter 5/Growth 10/Pro 20/Scale açık kapasite | H2/H6 | Sınırlar çakışmasız; bilinmeyen Scale satılmaz |
| R057 | §7.3 | Sürümlü product/base-plan/offer/periyot/currency ve ayrı kredi ürünleri | H2/I1 | Fiyat store'dan; yanlış ürün/ortam reddi; promosyon uydurma yok |
| R058 | §7.4 | Seat pratiği: yönetici vs practicing, assignment sayısından bağımsız | H6 | Owner practicing bir, çok firma yine bir; expert unique |
| R059 | §6,7.4 | Reserved seat + active seat transaction, accept/reactivate/downgrade | H6 | Last-seat yarışında aşım yok; TTL/revoke release |
| R060 | §7.5 | Apple purchase/unfinished/verify/notification/reconcile | H3/H5 | Sandbox lifecycle ve doğru app/environment/product doğrulama |
| R061 | §7.5 | Google PURCHASED/RTDN/verify/acknowledge/consume | H4/H5 | Pending grant yok; finalize retry deadline alarmı |
| R062 | §7.5 | Kalıcı inbox, tek event/transaction, sırasızlık/dead-letter | H5 | Duplicate ve out-of-order callback hakkı bozmuyor |
| R063 | §7.5 | Pending/active/canceled-active/grace/hold/expired/revoked/failure | H7 | Provider state/time bazlı entitlement; veri silinmiyor |
| R064 | §7.4–7.6 | Upgrade/downgrade/excess-seat/read-export davranışı | H6/H7 | Fazla seat rastgele silinmiyor; artış kontrollü |
| R065 | §7.6 | Cross-platform restore, bağımsız abonelik çakışması | H7 | Seat toplanmıyor; tek provider revoke diğer geçerli hakkı silmiyor |
| R066 | §7.6 | Refund/revoke audit ve kredi grant'e bağlı ters hareket | H7/I3 | Transaction silme yok; workspace data korunur |

## 5. AI cüzdanı ve depolama

| ID | Kaynak | Gereksinim | Uygulama | Kabul kanıtı |
|---|---|---|---|---|
| R067 | §8.1 | Workspace wallet; personal finansmana sessiz fallback yok | G3/G4 | OSGB yetersiz bakiye personal krediyi etkilemez |
| R068 | §8.1–8.2 | Immutable integer ledger, grant allocation, projection | G3/I1 | Posting/remaining allocation/balance reconcile; edit/delete ret |
| R069 | §8.1 | Satın alınmış kredi expire olmaz, subscription balance silmez | I2 | Süre/abonelik sona erme fixture'ında bakiye korunur |
| R070 | §8.3 | Atomik reserve/consume/release ve üye kota kilidi | G4 | Parallel reserve spend aşımı yok; tek charge |
| R071 | §8.3 | Provider timeout/crash/cancel/ambiguous outcome ve bounded cost | G4/K3 | Kör duplicate çağrı yok; belirsiz iş reconcile; negative normal spend yok |
| R072 | §8.2 | AI usage actor/model/feature/pricing-version/job ölçümü | G5 | Ledger-usage bağları; prompt analytics'e taşınmıyor |
| R073 | §8.4 | Aylık uzman limiti/timezone/month rollover | G5 | Reserved+spent kontrol; eski job doğru dönemden settle |
| R074 | §8.4 | Refund after spend, debt, future grant mahsup | I3 | Referanslı reversal, debt görünür, yeni spend engelli |
| R075 | §8.4,9.2 | Admin grant/correction reason/ticket/üst limit | I4/F4 | Store satışından ayrı; audit failure mutasyonu durduruyor |
| R076 | §7.5,8 | Callback+webhook+restore tek grant; finalize retry | I1–I2 | Commit sonrası crash/replay aynı bakiyeyi koruyor |
| R077 | §10.1 | Asset workspace/uploader/source/version/byte metadata | D7/G1 | Parent filing yetkisi ve gerçek object eşlemesi |
| R078 | §10.2 | Quarantine/inspect/server-byte finalize tekilliği | G2 | Fake byte/duplicate finalize/failed upload doğru ölçülüyor |
| R079 | §10.2 | API delete confirmation, archive≠delete, son referans/retention | G2 | Failed delete ve shared ref byte'ı yanlış düşürmüyor |
| R080 | §10.3 | Current vs period uploaded vs generated; file/version/download ayrımı | G2/G5 | Metrik sözlüğü; signed URL indirme byte'ı sayılmıyor |
| R081 | §10.3 | Original uploader ve current responsible ayrı; MB/MiB | G1/G5/J3 | Devir eski upload istatistiğini yeni uzmana taşımıyor |
| R082 | §10.4 | Storage event/rollup/reconciliation ve eski inventory | G2/K3 | Drift kaydı, idempotent rebuild; eski dosya yeni upload değil |
| R083 | §10.4 | Storage entitlement limiti≠AI kredi | G2/H2 | Byte limit ve wallet ayrı; bilinmeyen limit uydurulmuyor |

## 6. Devir, hafıza ve yayın

| ID | Kaynak | Gereksinim | Uygulama | Kabul kanıtı |
|---|---|---|---|---|
| R084 | §11.1 | Kaynak/hedef/firmalar/effective/not/checklist ve açık iş preview | J1 | Kaynak sayıları doğru; devredilmeyen iş sorumlusu açık |
| R085 | §11.1–11.2 | Snapshot/version/seat/aktiflik/primary revalidation | J2 | Stale preview ve suspended target ret |
| R086 | §11.2 | Firma başına atomik devir, batch partial retry | J2 | Aynı firma duplicate değil; diğer uzman ataması bozulmaz |
| R087 | §11.2–11.3 | Future job, cancel ve tamamlanmış işlem compensation | J2/J3 | Effective zamanda yeniden kontrol; yeni işler ezilmez |
| R088 | §3,11.3 | Author/uploader/usage geçmişi sabit | J3/C4 | Devir öncesi-sonrası ID ve actor karşılaştırması |
| R089 | §12 | Source-linked memory, event unique, occurred/recorded, rebuild | J4 | Duplicate source event yok; tarihsel olay uydurulmuyor |
| R090 | §12 | Visibility/redaction/source deletion/search/RAG izinleri | J4/J5 | Management/private not uzman araması/AI'ında yok |
| R091 | §12 | AI olmadan deterministik devir özeti | J5 | AI kapalıyken açık/gecikmiş/yaklaşan özet çalışır |
| R092 | §12 | Onaylı ücretli AI brief, kaynak/model/version/stale/review | J5/I | Charge tek, citation kaynaklara gider, source değişince stale |
| R093 | §12 | Prompt injection sınırı ve kaynaksız çıkarım etiketi | J5/K1 | Kaynak içi talimat izin/araç kapsamını değiştiremez |
| R094 | §16 | Additive migration, personal backfill, concurrent old clients | B3/C4/D/L | Dry-run/resume/re-run count ve old writer race testi |
| R095 | §16 | Legacy personal-only route; policy OR ve contract temizliği | C/D/K1/L | Eski app OSGB göremez; eski kolonlar ilk yayında drop edilmez |
| R096 | §16–17 | DB+object backup/restore, reconcile ve forward rollback | K3/L | RPO/RTO prova; ledger/store sonrası veri korunur |
| R097 | §17 | Mahremiyet/minimization/retention/secret/log korunması | D/F/G/J/K1 | Log ve export örnekleri redakte; deletion politikası doğrulanmış |
| R098 | §17–18 | İzolasyon, concurrency, billing, performance ve arıza testi | K1–K4 | A/B/P fixture, sandbox, gerçek rol ve tam mobil build kanıtları |
| R099 | §19L | Allowlist pilot, cohort, metrik/kill-switch, destek runbook | L1–L4 | Sayısal eşikler ve somut yayın kararı; personal sentinel geçer |
| R100 | §20–21 | ADR, açık karar, küçük PR ve gerçek kabul kaydı | A–L | Her PR migration/test/rollback; DEC kapıları kapanmadan satış yok |

## 7. Opsiyonel ve kapsam dışı maddeler

Bunlar da tam planda görünürdür; zorunlu özellik diye sessizce eklenmez veya unutulmaz.

| ID | Kaynak | Madde | Plan içindeki durum |
|---|---|---|---|
| O01 | §13 | Yeni OSGB şablon kütüphanesi | Ana plan §7/X1; kaynak belgede sonraki genişleme; mevcut şablonların scope'u D'de zorunlu |
| O02 | §13 | Yeni CSV/XLSX toplu import ürünü | §7/X2; mevcut import yolu varsa D8'de zorunlu izolasyon |
| O03 | §13 | İsteğe bağlı belge onay sistemi | §7/X3; revision/approver/audit; ayrı ürün genişlemesi |
| O04 | §13 | Gelişmiş uzman iş yükü optimizasyonu | §7/X4; temel uzman/firma/usage raporu zaten E/F'de zorunlu |
| O05 | §5.1 | Manager/salt-okunur denetçi rolü | Sonraki ihtiyaç; başlangıç owner/admin/expert zorunlu |
| O06 | §9.3 | Support impersonation/session | Gerekiyorsa F3, süreli/read-only/denetimli; kalıcı sınırsız erişim kapsam dışı |
| N01 | §1.1 | Harici ödeme/web checkout/havale/manuel tahsilat | Implementasyon yapılmaz; admin grant ödeme sayılmaz |
| N02 | §1.1 | İBYS/resmi KATİP API/scraping/e-Devlet/kamu aktarımı | Implementasyon yapılmaz; manuel KATİP kaydı D6'da korunur |
| N03 | §1.1 | Otomatik yasal uygunluk ve resmi uzman doğrulama | Implementasyon yapılmaz; beyan/tracking görünümü kullanılır |
| N04 | §1.1,3 | Tenantlar arası firma mülkiyet devri/global auto-merge | Implementasyon yapılmaz; aynı OSGB uzman devri J'de zorunlu |
| N05 | §1.1 | Paralel admin/ikinci veri uygulaması/client service key | Implementasyon yapılmaz; mevcut katman genişler |

## 8. Kaynak test senaryolarının tamamı

S1 §18 kimlikleri korunur. Bunlar henüz OSGB için koşulmuş testler değildir; fixture ve acceptance taslağıdır. İlave old-client/RC/dark-deploy testleri yayın ekinde tanımlıdır.

| Kaynak test | Senaryo / beklenen sonuç | Sorumlu faz |
|---|---|---|
| TEN-01 | A uzmanı B company read/write: veri/yazım yok | C/D/K |
| TEN-02 | A parent'a B company/member child: DB invariant ret | B/C/D |
| TEN-03 | OSGB owner uzmanın personal firmasını okuyamaz | B/C/D |
| TEN-04 | Workspace'siz legacy endpoint personal-only | B4/C/D/K |
| AUTH-01 | Expert kendini owner yapamaz | B/F |
| AUTH-02 | Son owner yeni owner olmadan çıkarılamaz | B5 |
| AUTH-03 | Assignment end/suspend sonrası read/write/job/download ret | C/D/G |
| UI-01 | Workspace switch cache/realtime karışması yok | B4/E/K |
| SEAT-01 | Son seat için parallel accept yalnız bir etkin seat | H6 |
| SEAT-02 | Practicing owner iki firmada tek seat | C3/H6 |
| SEAT-03 | 12→10 limit düşüşü veri silmez, excess durumu açık | H6/H7 |
| PAY-01 | Pending/sahte/yanlış app-env purchase grant yok | H/I |
| PAY-02 | Callback+notification+restore tek purchase/grant | H5/I1 |
| PAY-03 | Receipt başka OSGB'ye taşınamaz | H2/H7/I |
| PAY-04 | Sırasız lifecycle authoritative projection'a gider | H5/H7 |
| PAY-05 | Commit sonrası finish/consume failure retry, regrant yok | H1/I2 |
| PAY-06 | İki platform subscription seat toplamıyor, destek uyarısı | H7 |
| CR-01 | Wallet100, eşzamanlı reserve150: aşım yok | G3/G4 |
| CR-02 | Duplicate AI request/worker crash tek kesin debit | G4 |
| CR-03 | Provider unknown: kontrolsüz release veya duplicate call yok | G4/K3 |
| CR-04 | Harcanmış kredi refund referanslı reversal/debt | I3 |
| CR-05 | Admin credit audit'li, gelir raporundan ayrı | I4/F4 |
| FILE-01 | Duplicate finalize tek asset/byte | G2 |
| FILE-02 | Archive/failed delete mevcut byte düşürmez | G2 |
| FILE-03 | Object/metadata drift reconcile edilir | G2/K3 |
| ADMIN-01 | Normal user global admin servise erişemez | F1/F2 |
| ADMIN-02 | MFA/reason eksik mutasyon reddi, audit zorunlu | F2/F4 |
| HAND-01 | Devir geçmiş author/upload aktörünü değiştirmez | J3 |
| HAND-02 | Preview sonrası version/suspend stale commit ret | J2 |
| HAND-03 | Duplicate execute tek assignment/history etkisi | J2 |
| MEM-01 | Management not uzman search/AI'ına sızamaz | J4/J5 |
| MIG-01 | İkinci backfill duplicate workspace/grant/memory üretmez | B3/C4/G/J |
| MIG-02 | Restore DB+object/izin eşlemesi tutarlı | K3 |

## 9. Kaynak bölüm ve karar izleri

| Kaynak bölüm | Bu plandaki karşılığı |
|---|---|
| S1 §0–2 | Ana plan §1–2/A, repo envanteri, R001–R004 |
| S1 §3–6 | Ana plan §2/B/C, R002–R021 |
| S1 §7 | H/I, R051–R066/R076 |
| S1 §8 | G/I, R067–R076 |
| S1 §9 | F, R042–R047 |
| S1 §10 | D7/G, R077–R083 |
| S1 §11–12 | J, R084–R093 |
| S1 §13–15 | D/E/F, metrik/API sözlüğü, R016/R022–R050 ve O01–O05 |
| S1 §16–18 | Canlı koruma eki/K, R094–R098 ve tüm kaynak test kimlikleri |
| S1 §19–21 | Ana plan A–L/karar defteri/bitiş tanımı, R099–R100 |
| S1 §22 | Ana plan teknik kaynak notu ve başlangıç provenance hash'leri |
| S2 GitHub incelemesi | A/envanter, yeniden kullanım tablosu; gerçek Android ve RC bulundu |
| S2 Apple/Google ödeme | H/I, capacity, binding, verification, provider-neutral domain |
| S2 Super Admin | F/G/I, usage, paid olmayan destek hakkı ve audit |
| S2 Devir/hafıza/resmi sınır | J ve N02–N04 |
| S2 PR A–L sırası | Ana plan §3 ile içerik eşlenmiş; harf sırası için S1 esas |

S1'in ADR-001…015 başlıkları da karar defterine taşınır; bunlar henüz uygulanmış ADR dosyaları değildir:

| ADR | Karar konusu | Sahibi faz / açık karar |
|---|---|---|
| 001 | Tek workspace / shared schema / personal+OSGB | B |
| 002 | Membership+assignment/RLS/composite FK | B/C/D |
| 003 | Ayrı trusted platform admin/global grant | F / DEC-01,12 |
| 004 | Dönemli çoklu assignment, author/responsible | C/J |
| 005 | Client provider ≠ server verifier, Apple/Google/RC | H / DEC-10 |
| 006 | Canonical transaction, inbox, reconciliation | H/I |
| 007 | Purchaser-workspace binding/restore | H / DEC-11 |
| 008 | Seat/practicing/invite/downgrade/Scale | H / DEC-02,04,05 |
| 009 | Wallet/ledger/reserve/refund debt | G/I / DEC-07 |
| 010 | Asset byte metering/upload≠storage | G / DEC-06 |
| 011 | Admin reason/MFA/audit/support session | F / DEC-07,12 |
| 012 | Source-linked memory/visibility/redaction | J / DEC-08 |
| 013 | Aynı OSGB devir/future/batch/compensation | J |
| 014 | Resmi sistemler kapsam dışı | D/E / N02–N03 |
| 015 | Additive/personal backfill/old-client uyumu | B–D/K/L / DEC-09 |

## 10. Uygulama sırasında durum kaydı

Her R/O satırı için durum: `Planlandı → Geliştiriliyor → Test edildi → Staging kabul → Yayınlandı → Canlı kabul`. “Kapsam dışı” yalnız N veya açık ürün kararıyla O için geçerlidir; mandatory R satırı kaynak gerekçesi olmadan çıkarılmaz. Eksik veri/test ekranında tamamlandı işareti yok.

Kabul satırı şablonu: `ID | PR/commit | migration manifest | DB/RLS artifact | iOS build/e2e | Android build/e2e | admin e2e/uygulanmaz | staging evidence | açık DEC | release/cohort | tarih`. Kanıt verilmemiş alan boş/bekliyor kalır. Böylece ana plan bütün özellikleri kapsarken gerçek tamamlanma ayrı izlenir.
