# OSGB Faz B — repo üzerinde uygulanacak küçük değişiklikler

17 Eylül 2026 · Durum: uygulama planı; aşağıdaki yeni şema ve RPC'ler **henüz uygulanmadı**.

Bu belge artık [A–L tam entegrasyon ana planının](OSGB_FULL_INTEGRATION_PLAN.md) Faz B teknik ekidir. Bütün özellikler, kaynak eşlemesi ve canlı kullanıcıları koruma koşulları ana plan ve bağlı eklerinde izlenir; toplam kapsam Faz B ile sınırlı değildir.

Amaç personal kullanıcıyı bozmadan workspace/membership/invitation temelini kurmak. Referans envanter: [Faz A](OSGB_REPO_INVENTORY.md), [scope matrisi](OSGB_SCOPE_MATRIX.md), [baseline](OSGB_BASELINE_2026-09-17.md). Bu plan bir anda bütün uygulamayı tenant'a açmaz; firma/alt modüller Faz C/D'de taşınana kadar OSGB operasyonları kapalı kalır.

## B0 — dağıtım baseline'ı ve kontrat

**Mevcut dosyalar:** `supabase/pilot-release/README.md`, `scripts/isg/p05_pilot_release.mjs`, `scripts/modules/run_pilot.mjs`, `.github/workflows/isg-foundation.yml`, `contracts/isg/v1`.

1. Yetkili read-only schema/ledger çıktısından uygulanmış migration sürüm + SQL hash manifestini oluştur. Root/candidate/mirror eşlemesini belgele; adayları applied işaretleme. Canlı snapshot, policy/grant/function/trigger envanteri yerel DDL taramasından ayrı olsun.
2. İzole DB'de bu baseline'ı yeniden kur; owner-only company/personnel/analysis/file/billing okuma-yazma kabulünü kaydet. `run_pilot` sentetik fixture testiyle full baseline rehearsal'ını ayrı raporla.
3. Kontratlar için repo convention'ında yeni workspace context version'ı tanımla. Önerilen payload: `workspace_id`, `membership_id`, `role`, `membership_status`, `permission_revision`, `context_version`; actor/session sunucudan. `NovaWorkspaceCapability` şirket availability anlamını kaybetmesin.
4. CI'da mevcut 4 foundation + 13 design başarısızlığını test/ürün uyuşmazlığı ve gerçek ürün eksiği olarak incele. Testleri sadece yeşile çevirmek için silme; OSGB testlerine baseline kusurlarını gizleme. Yeni sözleşme testleri ayrı, mevcut suite sonucu görünür.

**Kabul:** Manifestten tekrar kurulabilir DB; mevcut endpoint davranışı kayıtlı; bütün yeni semboller proposed/current olarak ayrılmış. **Rollback:** Ürün davranışı değişmez; manifest ve test fixture güncellemesi geri alınabilir.

## B1 — additive workspace/membership modeli

**Önerilen yeni dosya yerleri:** timestamp'i migration aracıyla üretilecek `supabase/pilot-release/candidates/<timestamp>_isg_workspace_foundation.sql`; `contracts/isg/v1` altında versioned fixture/sözleşme; `scripts/isg` altında DB izolasyon testleri. Bunlar mevcut dosya adı değildir. Dağıtım zinciri B0'da belirlendikten sonra release manifestine eklenir; mirror sadece doğrulanmış deployment SQL'ini yansıtır.

Mevcut `private_isg` + public dar RPC yaklaşımı korunur:

| Önerilen nesne | Invariant |
|---|---|
| `private_isg.workspaces` | UUID, kind personal/osgb, status, version; personal türünde gerçek sahip user referansı; user başına tek personal workspace partial unique. OSGB sahibi tek user sütunundan erişim türetmez. |
| `private_isg.workspace_memberships` | Workspace/user unique; owner/admin/expert rolü, active/invited/suspended/ended durum sözlüğü, permission revision; personal yalnız kendi owner üyeliği. |
| `private_isg.workspace_invitations` | Workspace, normalize edilmiş doğrulanacak email, token hash, expires/revoked/accepted bilgisi, davet eden actor, role/version. Raw token kalıcı saklanmaz/loglanmaz. |

Tüm tablolar RLS enabled, istemciye doğrudan mutation yok. Helper'lar sabit search_path, kontrollü EXECUTE grant ile dar wrapper üzerinden çağrılır; authenticated doğrudan rol tablosunu güncelleyemez. Membership FK'leri workspace eşitliğini DB'de garanti eder. Owner transferi/son owner çıkarma workspace satırı üzerinde ortak kilit sırasıyla atomik korunur. Personal workspace'e ikinci kişi veya OSGB daveti kabul edilmez.

User silinmesiyle ortak workspace ve tarihsel audit'i cascade silme. Auth identity'nin kaldırılması, membership bitirme ve retention/tombstone ilişkisi açık tasarlanır; profile/auth FK deletion davranışı mevcut account deletion ile birlikte test edilir. Sahte owner user açılmaz.

**Test:** A/B/P fixture; role spoof; cross-workspace membership FK; personal duplicate; eşzamanlı iki owner demotion; askıya alınmış üye; doğrudan anon/authenticated yazımı; helper EXECUTE/grant; son owner silme. **Kabul:** Yeni nesneler legacy owner-only endpoint'in yetkisini genişletmez. **Rollback:** OSGB flag kapalı, additive tablolar korunur; down migration veri silmez.

## B2 — context RPC ve atomik receipt/audit

**Genişletilecek gerçek katmanlar:** `private_isg.active_actor`, domain receipts/outbox yaklaşımı; `supabase/functions/_shared/isg/mutation-context.ts`, `App/Services/ISG/IsgMutationContext.swift`, mevcut mutation outcome sözleşmeleri. Dosya/simge değişimleri öncesi B0 baseline'ındaki aktif tanım seçilir.

Önerilen yeni public RPC'ler: `isg_workspace_list_v1`, `isg_workspace_context_v1`, `isg_workspace_member_mutate_v1`. Eski `isg_workspace_availability_v1` imzası bozulmaz. Liste yalnız kullanıcının üyeliklerini sayfalı verir; suspended context operasyon capability döndürmez. Workspace ID client'tan gelse de server aktif üyelik/rolü DB'den doğrular; JWT içine gömülü eski rol tek otorite olmaz.

Mutation envelope: workspace, action, expected_version, mutation_id/request hash. Aktör doğrulanmış session'dan; aynı key+aynı payload aynı sonucu, aynı key+farklı payload conflict verir. Mutation + audit + receipt + outbox aynı transaction'da. Audit yazılamazsa domain değişikliği commit edilmez. Yetki iptal edilmiş kullanıcının eski receipt'i yeniden istemesi de güncel erişim kontrolünden geçer.

**Altyapıyı yeniden kullanma kararı:** `personnel_audit/receipts` company+actor owner FK'sine, `event_dispatch` personnel/directory event source kümesine bağlı. Workspace kuruluşu için uydurma company oluşturulmaz, owner actor sahteleştirilmez. Mevcut dispatcher delivery/receipt/dead-letter motoru korunarak yeni workspace event adapter'ı eklenir. Company zorunlu envelope için açık versioned workspace aggregate dalı eklenir; eski event fixture'ları değişmeden geçer. Küçük workspace domain receipt/audit/outbox tabloları gerekiyorsa bu uyumsuzluk nedeniyle eklenir; ikinci bağımsız dispatch/queue sistemi kurulmaz. Aday dispatcher canlı değilse önce manifest/rehearsal ile bağımlılık netleştirilir, otomatik etkinleştirilmez.

Davet komutları token hash, TTL, doğrulanmış email eşleşmesi, tek kullanım, rol whitelist, rate-limit ve transaction kontrolü taşır. Email gönderimi outbox dış etkisidir; DB transaction içinde gönderilmez. Gerçek davet gönderme/onboarding, seat entitlement hazır değilken açılmaz. B test fixture'ı kapasite sınırını simüle edebilir; sahte paid entitlement veya sınırsız varsayılan oluşturamaz. Public self-service OSGB açılışı H/L koşullarına bağlıdır.

**Test:** scope listesi; forged actor; privilege escalation; duplicate/conflicting request; audit/outbox hata rollback; token replay/expiry/wrong-email; parallel accept; revoke sonrası receipt read; eski worker payload compatibility. **Rollback:** Workspace mutation read/write flag'leri kapatılır; committed receipt/audit kalır.

## B3 — personal backfill provası

**Yeni araç önerisi:** `scripts/isg/osgb_personal_backfill.mjs`; default dry-run, explicit target ve checkpoint. Gerçek veri içermeyen output fixture'ları repoya; kişisel veri/üretim dump'ı repoya değil.

Sıra: eligible profile/auth eşleşmeleri → personal workspace → aynı kullanıcı owner membership → verify. Firma ve alt kayıt `workspace_id` backfill'i Faz C/D'nin işi; B bunları zaten taşımış gibi raporlamaz. Firma bulunmasa da uygun mevcut kullanıcı personal workspace alabilir. Auth/profile uyuşmazlığı ve silinme durumları review listesine gider; email/isim üzerinden sahiplik tahmini yapılmaz.

Batch/resume: deterministik id sırası + cursor, batch transaction, personal owner unique constraint, conflict-safe insert/read, işlem öncesi/sonrası count. Eşzamanlı yeni kullanıcı kayıtlarıyla yarış testi. İkinci çalıştırma yeni workspace/membership üretmez. Eksik üyelik onarımı mevcut başka owner'ı sessizce değiştirmez. Backfill checkpoint'i kaynak baseline/version ve checksum taşır.

Bu dilim kişisel RevenueCat aboneliğini, quota kullanımını, bakiyeyi, firmayı veya asset path'ini OSGB'ye taşımaz. Yeni opening credit grant oluşturmaz. Rollout hook'u eklemek ayrı kontrollü adım; ilk prova global signup trigger'ı etkinleştirmez.

**Test:** dry-run sıfır mutation; aynı batch iki kez; yarıda kes/resume; auth/profile orphan; aynı kullanıcı için concurrent creation; count/uniqueness; mevcut firma/owner/billing değerleri değişmemiş. **Kabul:** Legacy kullanıcı başına tam bir personal workspace ve owner membership; anomaliler sıfır veya açık review engeli. **Rollback:** Job durur; tamamlanmış mapping silinmez. Production uygulaması ayrı backup/dry-run/reviewed cutover kapısından geçer.

## B4 — client context, kapalı özellik entegrasyonu

**Gerçek değişiklik noktaları:** `NovaSessionHost.swift`, `NovaWorkspaceController.swift`, `NovaCompanyServiceAdapter.swift`, `NovaModuleMutationJournal.swift`, `NovaPilotMainGate.swift`; Android mevcut auth/company repository'leri ve ortak transport kontratları.

Workspace context auth identity'den ayrı taşınır. Personal context seçiliyken mevcut company availability/RPC davranışı korunur. OSGB için C/D tamamlanmadan legacy company servislerine fallback yapılmaz: desteklenmeyen operasyon açık unavailable olur. Membership/permission revision değişiminde scope epoch invalidation, task cancellation, popup/form context ayrımı ve cache temizliği uygulanır. Eski workspace'in geç gelen başarılı cevabı yeni sayfayı güncellemez.

Keychain mutation retry anahtarlarına workspace eklenir. Eski personal key'ler yalnız deterministik personal context altında devam ettirilebilir; tekrar yeni mutation ID üretip duplicate kayıt yazılmaz. Records-changed sinyali workspace/company kapsamı taşır. Context oluşturulamazsa başka hesabın veya en son seçilmiş OSGB'nin verisi gösterilmez.

Yeni workspace selector mevcut Nova tasarım sistemiyle flag arkasında hazırlanabilir. Genel Release ve pilot giriş farkı açık tutulur. Native UI'da rol gizlemek server izin kontrolünün yerine geçmez. Android'de workspace contract/state testleri yapılır; ekran feature parity henüz yoksa tamamlanmış gösterilmez.

**Test:** aynı user A→B, logout→başka user, session refresh, background return, iptal edilmiş membership, geç cevap, offline cache, pending mutation retry, iki workspace'te aynı action/hash, eski personal client. Swift/iOS ve Kotlin kontrat fixture'ları aynı beklenen sonucu üretir.

**Kabul:** Personal mevcut akışları çalışır; OSGB verisi desteklenmeyen eski endpoint'e gitmez; kapalı flag ile bugünkü giriş davranışı korunur. **Rollback:** Selector/OSGB operasyon flag'i kapanır, schema güvenliği korunur.

## Faz C/D için şimdiden sabitlenen bağımlılıklar

`companies.workspace_id` + composite FK ve uzman-company ataması eklenmeden ortak firma açılmaz. `companies.user_id` ve actor FK'leri körlemesine yeniden adlandırılmaz. Legacy endpoint workspace'siz çağrıyı yalnız personal workspace'e çözer; tüm OSGB'leri owner OR policy ile açmaz. Her alt domain için scope matrisi read/write/export/worker/search/download/cleanup satırları tamamlanır. Mevcut personal store hakkı OSGB finansmanı olarak kullanılmaz.

## Sonraki ürün kararları

B0–B4 şema/kontrat geliştirmesine engel olmayan, fakat ilgili özelliğin açılmasını durduran kararlar: gerçek admin paneli repo/route'u (F), Scale seat kapasitesi ve mağaza ürün/fiyat/periyotları (H), davet seat rezervasyon TTL'i ve downgrade/grace davranışı (H), storage limitleri ve byte metering kaynakları (G), destek credit/override sınırları (F/I), retention/mahremiyet sınıfları ve restore RPO/RTO (K). Android konumu artık açık soru değil: bu repoda `android/` mevcut.

Faz B tamamlama kapısı: izole baseline upgrade + gerçek RLS fixture'ları + idempotent backfill + personal regression + session/workspace isolation. Test başarısızlığına veya henüz uygulanmamış migration'a rağmen OSGB pilotunu açmak bu planın parçası değildir.
