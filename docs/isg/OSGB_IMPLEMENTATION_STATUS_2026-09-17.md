# OSGB tam entegrasyon — uygulama durumu

> **18 Eylül 2026 güncellemesi:** Güncel ürün eşitliği ve cihaz kabul kaynağı [OSGB_PERSONAL_PILOT_PARITY_REVIEW_2026-09-18.md](OSGB_PERSONAL_PILOT_PARITY_REVIEW_2026-09-18.md) dosyasıdır. Eğitim, risk değerlendirmesi ve periyodik kontrolün bireysel Pilot Canlı Nova akışları OSGB yönetici/uzman tenant servislerine taşındı; staging `20260918020000` seviyesine getirildi ve fiziksel iPhone'a OSGB Pilot `2.0.3 (122)` kuruldu. 1002/1002 ISG regresyonu geçti. Production değişmedi. Gerçek mağaza sandbox'ı, production rollout'u, fiziksel Android kabulü ve UI kit bekleyen admin frontend ayrı yayın kapılarıdır.

17 Eylül 2026 · Branch `codex/isg-transition-foundation` · Başlangıç commit'i `6eebab8946c627f42d13415cff1b8dc5007cc1ce`

Bu kayıt, [ana planın](OSGB_FULL_INTEGRATION_PLAN.md) uygulanmış parçalarını ve dış kabul adımlarını ayırır. Operasyon migration'ları staging projesine `20260918020000` seviyesine kadar uygulandı; staging rollout'u sentetik QA tenant'ı için açıldı. **Production veritabanına veya production rollout'una işlem yapılmadı.** Kaynak migration'larda rollout varsayılanları kapalıdır.

Sıralı 32 migration'ın boyut ve SHA-256 değerleri [aday manifestinde](OSGB_CANDIDATE_MANIFEST_2026-09-17.json) sabittir. Admin migration'ı staging dışında tutulmuştur; manifest üretimi ve dark-default kontrolü `scripts/isg/osgb_candidate_manifest.mjs` ile yeniden çalıştırılabilir.

## İnceleme sonrası durum

**Yerel entegrasyonun yanında staging operasyon kabulü, gerçek AI/object/export zinciri, Android ürün kökü ve iOS fiziksel OSGB Pilot kabulü tamamlandı; production mağaza kabulü tamamlanmadı.** iOS ve Android workspace/firma/D1–D9 yolları tenant servislerine bağlıdır. Eğitim, risk ve periyodik kontrolün bireysel Pilot Nova iş kuralları OSGB ekranlarında da kullanılır. Güncel kanıt [eşitlik raporunda](OSGB_PERSONAL_PILOT_PARITY_REVIEW_2026-09-18.md), dış yayın adımları [staging kabul raporunda](OSGB_STAGING_ACCEPTANCE_2026-09-17.md) tutulur.

## Faz durumu

| Faz | Yerel uygulama | Doğrulama | Kalan kabul |
|---|---|---|---|
| A | Repo/scope/baseline/trace/safety envanteri hazır | Kaynak hash ve başlangıç test durumu kayıtlı | Canlı salt-okunur katalog ve gerçek deployed ledger karşılaştırması |
| B | Workspace, membership, invitation, context/list RPC, personal dry-run backfill | Disposable PostgreSQL, staging sentetik tenant ve Swift/Kotlin sözleşme testleri | Gerçek e-posta davet teslimi ve eski uygulama sürümü cihaz testi |
| C | Firma scope, assignment/history, canonical company bridge ve yönetici atama ekranı | A/B/P izolasyonu, current/ended liste, overlap, tarihçe ve revoked-member testleri | Gerçek veri anomali raporu ve staging performansı |
| D1–D9 | D1 görev/unvan, dış firma, sözleşme ve atama geçmişi; D2 müfredat/konu/sınav/yıllık plan/sertifika; D3–D6 workspace yaşam döngüleri; D7 yükleme/indirme/finalize; D8 analiz/filing/export; D9 dashboard/arama/change-feed | Disposable zincir ve staging tenant kabulü; gerçek object/Gemini/PDF/XLSX geçti | Yük/EXPLAIN, restore ve fiziksel cihaz E2E |
| E | iOS/Android workspace transportu ve OSGB ürün kökleri; workspace, firma, dashboard, D1–D9 ve D1/D2 ileri ekranları | iOS build/harness; Android unit test, QA build, staging runtime gate ve API 33 emülatör E2E geçti | Takvim/ayar/bütçe genişletmeleri ve fiziksel Android cihaz kabulü |
| F | Whitelist admin komutları, grant/MFA/reason/audit ve overview backend adayı | SQL admin negatif/pozitif fixture | Kullanıcının sağlayacağı UI kit sonrasında admin frontend entegrasyonu ve DEC-12 support-session kararı |
| G | Wallet/reservation/ledger, member quota, storage metering/reconcile, AI jobs | Concurrency/reconcile yanında gerçek staging object ve Gemini settle/commit geçti | Production kapasite/limit kararları |
| H–I | Seat entitlement, ürün kataloğu, purchase intent, provider inbox, verified transaction, binding, grant/refund/reconcile | Provider-neutral sırasız/duplicate lifecycle fixture | DEC-02–07 ve DEC-10–11; App Store/Play/RevenueCat sandbox kabulü |
| J | Devir preview/execute, assignment transfer, kaynaklı kurumsal hafıza | Stale preview, replay, revocation ve author koruma testleri | Retention/visibility kararı ve UI/admin akışı |
| K | Manifest guard, 32 adayın sıralı/hash kontrollü manifesti, kapsamlı sentetik A/B/P ve staging QA senaryosu | Integrated rehearsal, gerçek object/provider/export, iOS fiziksel cihaz build 122 ve Android QA emülatör E2E geçti | Restore, yük/EXPLAIN, fiziksel Android/admin/store kabulü |
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

- `IsgWorkspaceAPI` ve Android `IsgWorkspaceGateway`: versioned workspace endpoint'leri, firma–uzman atama, D1/D2 gelişmiş personel/eğitim ve D1–D8 veri yolları, boyut/schema/scope/cursor/status kontrolü ve mutation için `canOperate` zorunluluğu.
- `IsgWorkspaceLiveAdapter`: Supabase RPC transportu ve aktif auth kimliği doğrulaması.
- `IsgWorkspaceStore`: hesap/workspace/firma değişiminde task iptali, kontrollü loading, firma/dashboard, ekip ve firma–uzman atama, D1–D8 domain, arama, analiz, firmaya bulgu atama, export ve change-feed işlemleri.
- `NovaSuccessMessage.serverKey`: sunucudan serbest metin kabul etmeden doğrulanmış işlem anahtarını ortak başarı sunumuna çevirir.
- OSGB navigation canlı pilot girişine bağlandı; D1–D9 ana operasyon ekranları workspace store üzerinden açılır. RPC'ler dağıtılmamışsa veya kullanıcıda OSGB alanı yoksa mevcut kişisel root aynen korunur; OSGB verisi kişisel servislere düşmez.

## Doğrulama kanıtı

| Kontrol | Sonuç |
|---|---|
| OSGB manifest/domain/context/session/API hedef testleri | Hedefli eşitlik/manifest testleri geçti; tam ISG paketi 1002/1002 geçti |
| 32 adayın manifest bütünlüğü | Sıra, boyut, SHA-256 ve dark-default guard'ları geçti |
| Entegre senaryo | Subscription, seat, company, personnel, training, safety, equipment, operations, files, analysis, filing, export, tracking, notification, PPE evidence, upload, AI wallet, quota, handover, revoke, memory, metrics ve admin projection geçti |
| iOS Debug / generic iOS Simulator ve fiziksel arm64 build | Geçti; OSGB Pilot `2.0.3 (122)` bağlı iPhone'a kuruldu ve açıldı |
| Android Gradle | JDK 17 ile `core:data` ve `core:designsystem` Debug Kotlin derleme + unit testleri geçti; Gateway dosyasında 9 test var |
| Geniş foundation paketi | 761/761 geçti; D1/D2 ileri sözleşme guard'ları dahil |
| Nova-design paketi | 194/194 geçti; önceki 13 açık tasarım/sözleşme arızası gerçek düzeltmelerle kapatıldı |

## Yayına engel kararlar

DEC-01 admin frontend konumu tespit edildi; entegrasyon ve ayrı repo sözleşmesi doğrulanmalı; DEC-02 Scale seat sınırı; DEC-03 gerçek ürün kimliği/fiyat/paket; DEC-04 davet rezervasyon süresi; DEC-05 grace/downgrade; DEC-06 storage limitleri; DEC-07 destek kredisi/override; DEC-08 retention/silme; DEC-09 SLO/RPO/RTO/cohort; DEC-10 RevenueCat kimlik/finalization; DEC-11 çoklu OSGB store hesabı; DEC-12 support session/global admin.

Bu kararlar kapanmadan bağlı gerçek mağaza, admin UI, limit veya canlı yayın davranışı uydurulmaz. Yerel aday zinciri altyapının yalnız bir bölümünü kapsar. Eksik karar bağımsız kod, UI ve worker bağlantıları inceleme raporunda izlenir; staging ve production kabulü verilmemiştir.
