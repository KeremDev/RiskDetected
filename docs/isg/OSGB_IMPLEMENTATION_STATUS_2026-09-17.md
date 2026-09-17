# OSGB tam entegrasyon — uygulama durumu

17 Eylül 2026 · Branch `codex/isg-transition-foundation` · Başlangıç commit'i `6eebab8946c627f42d13415cff1b8dc5007cc1ce`

Bu kayıt, [ana planın](OSGB_FULL_INTEGRATION_PLAN.md) uygulanmış yerel adaylarını ve henüz kabul edilmeyen bölümlerini ayırır. **Production veya staging veritabanına migration uygulanmadı; feature flag açılmadı; gerçek mağaza, bildirim, e-posta, AI sağlayıcısı veya kullanıcı verisi kullanılmadı.** Bütün SQL adayları `NOT DEPLOYED` durumundadır ve workspace/domain rollout satırları varsayılan olarak kapalıdır.

Sıralı 24 migration'ın boyut ve SHA-256 değerleri [aday manifestinde](OSGB_CANDIDATE_MANIFEST_2026-09-17.json) sabittir. Manifest üretimi ve dark-default kontrolü `scripts/isg/osgb_candidate_manifest.mjs` ile yeniden çalıştırılabilir.

## İnceleme sonrası durum

**Canlıya dokunmadan yapılabilen yerel ana entegrasyon tamamlandı; canlı yayın kabulü tamamlanmadı.** 17 Eylül incelemesinde migration öncesi kişisel KKD verisiyle upgrade hatası, legacy domain yazımları, dosya olay görünürlüğü, atama arşivleme ve istemci scope hataları düzeltildi. iOS pilot köküne workspace seçimi, OSGB oluşturma/davete katılma, firma, ekip/davet, firma–uzman atama ve D1–D9'un birincil operasyon yolları bağlandı. [Kapsamlı inceleme raporu](OSGB_INTEGRATION_REVIEW_2026-09-17.md) güncel eksiklerin ve doğrulamanın kaynağıdır. İleri domain parity'si, gerçek sağlayıcılar, Android UI ve cihaz/staging kabulü ayrıca izlenir.

## Faz durumu

| Faz | Yerel uygulama | Doğrulama | Kalan kabul |
|---|---|---|---|
| A | Repo/scope/baseline/trace/safety envanteri hazır | Kaynak hash ve başlangıç test durumu kayıtlı | Canlı salt-okunur katalog ve gerçek deployed ledger karşılaştırması |
| B | Workspace, membership, invitation, context/list RPC, personal dry-run backfill | Disposable PostgreSQL ve Swift/Kotlin sözleşme testleri | Staging backfill, eski sürüm sentinel, davet teslimi |
| C | Firma scope, assignment/history, canonical company bridge ve yönetici atama ekranı | A/B/P izolasyonu, current/ended liste, overlap, tarihçe ve revoked-member testleri | Gerçek veri anomali raporu ve staging performansı |
| D1–D9 | D1 özel personel ekranı; D2–D6 workspace liste/detay/oluşturma; D7 yükleme/indirme/finalize; D8 analiz/filing/export; D9 dashboard/arama/change-feed | Tek disposable PostgreSQL zincirinde çapraz-domain kabul, asset transport ve iOS API/UI guard'ları | İleri edit/archive/rapor alt akışları, gerçek object/provider, staging veri karşılaştırması ve cihaz E2E |
| E | iOS/Android workspace transportu; iOS session-owned store; gerçek pilot kökünde workspace, firma, ekip/davet/atama ve D1–D9 route'ları | iOS uygulama build'i, Swift API harness, Android core:data ve core:designsystem derleme/unit testleri geçti | Android OSGB UI, takvim/ayar/bütçe, ileri domain parity'si ve fiziksel cihaz E2E |
| F | Whitelist admin komutları, grant/MFA/reason/audit ve overview backend adayı | SQL admin negatif/pozitif fixture | Kullanıcının sağlayacağı UI kit sonrasında admin frontend entegrasyonu ve DEC-12 support-session kararı |
| G | Wallet/reservation/ledger, member quota, storage metering/reconcile, AI jobs | Concurrency, duplicate, crash/reconcile disposable testleri | Gerçek object provider ve kapasite/limit kararları |
| H–I | Seat entitlement, ürün kataloğu, purchase intent, provider inbox, verified transaction, binding, grant/refund/reconcile | Provider-neutral sırasız/duplicate lifecycle fixture | DEC-02–07 ve DEC-10–11; App Store/Play/RevenueCat sandbox kabulü |
| J | Devir preview/execute, assignment transfer, kaynaklı kurumsal hafıza | Stale preview, replay, revocation ve author koruma testleri | Retention/visibility kararı ve UI/admin akışı |
| K | Manifest guard, 24 migration tek transaction provası, kapsamlı sentetik A/B/P senaryosu | Integrated rehearsal, iOS Debug simulator build ve Android modül build/testleri geçti | Staging, restore+object, yük/EXPLAIN, fiziksel cihaz/admin/store kabulü; başlangıçtaki test arızaları |
| L | Uygulanmadı | Yok | Ayrı somut canlı yayın onayı, production dark deploy ve kademeli cohort |

## Uygulanan güvenlik sınırları

- Her workspace isteği aktif session, membership, permission revision ve gerektiğinde company assignment kontrol eder. İstemci yanıt döndüğünde session/workspace'i yeniden doğrular; eski yanıt yeni ekrana yazılamaz.
- Uzman yönetim geneli dashboard isteyemez; yalnız atanmış firmalar üzerinden sorgular. Hazır olmayan veya kapalı domain legacy/personal endpoint'e düşmez.
- Mutation'lar idempotency/mutation anahtarı, güncel yetki ve server receipt ile tamamlanır. Analiz finding/uzman görüşü firmaya işlendiğinde uygunsuzluk aynı transaction sonrasında `committed_and_visible` durumuyla okunabilir.
- Skorsuz analiz bulguları `expert_items` projeksiyonuna katılır; eğitim önerileri ayrı korunur. PDF/XLSX export işi oluşturulurken ve okunurken scope tekrar denetlenir.
- Private tablolar doğrudan authenticated erişimine açılmaz. Service worker lease aldıktan sonra yetki/scope tekrar kontrol eder.
- Kredi grant/debit, store transaction, upload finalize, export, bildirim ve devir tekrarları tek etki üretir. Rollout kapalıyken direct RPC de kapalıdır.
- PPE imzalı kanıtı file kaydına bağlanır; cleanup yalnız generated/derivative nesnelere uygulanır. Kullanıcı upload'ı sessizce silinmez.

## İstemci teslimleri

- `IsgWorkspaceAPI` ve Android `IsgWorkspaceGateway`: versioned workspace endpoint'leri, firma–uzman atama, D1–D8 veri yolları, boyut/schema/scope/cursor/status kontrolü ve mutation için `canOperate` zorunluluğu.
- `IsgWorkspaceLiveAdapter`: Supabase RPC transportu ve aktif auth kimliği doğrulaması.
- `IsgWorkspaceStore`: hesap/workspace/firma değişiminde task iptali, kontrollü loading, firma/dashboard, ekip ve firma–uzman atama, D1–D8 domain, arama, analiz, firmaya bulgu atama, export ve change-feed işlemleri.
- `NovaSuccessMessage.serverKey`: sunucudan serbest metin kabul etmeden doğrulanmış işlem anahtarını ortak başarı sunumuna çevirir.
- OSGB navigation canlı pilot girişine bağlandı; D1–D9 ana operasyon ekranları workspace store üzerinden açılır. RPC'ler dağıtılmamışsa veya kullanıcıda OSGB alanı yoksa mevcut kişisel root aynen korunur; OSGB verisi kişisel servislere düşmez.

## Doğrulama kanıtı

| Kontrol | Sonuç |
|---|---|
| OSGB manifest/domain/context/session/API hedef testleri | 99/99 geçti |
| 24 migration'ın tek disposable PostgreSQL zinciri | Geçti; container dış ağa kapalı ve sonunda siliniyor |
| Entegre senaryo | Subscription, seat, company, personnel, training, safety, equipment, operations, files, analysis, filing, export, tracking, notification, PPE evidence, upload, AI wallet, quota, handover, revoke, memory, metrics ve admin projection geçti |
| iOS Debug / generic iOS Simulator build | Geçti (`CODE_SIGNING_ALLOWED=NO`) |
| Android Gradle | JDK 17 ile `core:data` ve `core:designsystem` Debug Kotlin derleme + unit testleri geçti; Gateway dosyasında 9 test var |
| Geniş foundation paketi | 755/755 geçti; önceki açık arızalar gerçek kod ve yerelleştirme düzeltmeleriyle kapatıldı |
| Nova-design paketi | 194/194 geçti; önceki 13 açık tasarım/sözleşme arızası gerçek düzeltmelerle kapatıldı |

## Yayına engel kararlar

DEC-01 admin frontend konumu tespit edildi; entegrasyon ve ayrı repo sözleşmesi doğrulanmalı; DEC-02 Scale seat sınırı; DEC-03 gerçek ürün kimliği/fiyat/paket; DEC-04 davet rezervasyon süresi; DEC-05 grace/downgrade; DEC-06 storage limitleri; DEC-07 destek kredisi/override; DEC-08 retention/silme; DEC-09 SLO/RPO/RTO/cohort; DEC-10 RevenueCat kimlik/finalization; DEC-11 çoklu OSGB store hesabı; DEC-12 support session/global admin.

Bu kararlar kapanmadan bağlı gerçek mağaza, admin UI, limit veya canlı yayın davranışı uydurulmaz. Yerel aday zinciri altyapının yalnız bir bölümünü kapsar. Eksik karar bağımsız kod, UI ve worker bağlantıları inceleme raporunda izlenir; staging ve production kabulü verilmemiştir.
