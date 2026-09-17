# OSGB entegrasyonu — Faz A repo envanteri

17 Eylül 2026 · İncelenen HEAD: `6eebab8946c627f42d13415cff1b8dc5007cc1ce` · Branch: `codex/isg-transition-foundation`.

Sonraki kullanıcı talebiyle [A–L tam entegrasyon ana planı](OSGB_FULL_INTEGRATION_PLAN.md) hazırlandı. Aşağıdaki teslim sınırı önceki keşif çalışmasının tarihsel kapsamıdır; artık toplam geliştirme planını Faz B ile sınırlamaz.

## Teslim sınırı

Kullanıcının verdiği `ISGADA_OSGB_MULTI_TENANT_INTEGRATION_PLAN_2026-09-16.md` ve `deep-research-report-2.md` incelendi. Kısa rapor keşif ile foundation uygulamasını birlikte isterken ayrıntılı planın §21 ilk uygulama dilimi **yalnız Faz A ve repoya özel Faz B planı** diyor. Bu teslim ayrıntılı planın bu sırasını izler. Belgelerdeki önerilen tablo/endpoint isimleri mevcut kod olarak kabul edilmedi.

Bu teslim OSGB'yi uygulamada etkinleştirmez. Üretim verisi, migration ledger'ı, mağaza ayarları ve üyelikler değiştirilmedi. Uygulama kaynaklarına davranış değişikliği yapılmadı. Başlangıç çalışma ağacı temizdi; belgedeki referans commit yerel HEAD ile birebir aynı. Önceki [firma takip belgesi](ISGADA_COMPANY_MODULE_TRACKING_2026-09-15.md) mevcut, ancak ekran metinleri ve yerleşimi için tarihsel referanstır; bugünkü kodun yerine geçmez.

İlgili çıktılar:

- [Sahiplik, erişim ve kapsam matrisi](OSGB_SCOPE_MATRIX.md)
- [Faz B küçük değişiklik planı](OSGB_PHASE_B_PLAN.md)
- [Başlangıç testleri ve açık noktalar](OSGB_BASELINE_2026-09-17.md)
- [Tekrarlanabilir çevrimdışı kaynak indeksi](../../scripts/isg/osgb_repo_inventory.mjs)

## Temel bulgular

1. **Bugünkü workspace tenant değil.** `NovaWorkspaceController`, firma seçimi/oturum/availability yönetir; `NovaSessionIdentity` yalnız kullanıcı ve session taşır. SQL `isg_workspace_availability_v1` aynı kullanıcıya ait firmanın kullanılabilirliğini döndürür. Kaynak taramasında personal/OSGB workspaces veya workspace memberships tabloları bulunmadı.
2. **Sahiplik ile aktör birlikte modellenmiş.** `companies.user_id` gerçek bugünkü sahiplik sınırı. Alt tablolardaki `(company_id, owner_id)` bağlarına ek olarak bazı receipt/audit tablolarında `(company_id, actor_id) → companies(id,user_id)` var. Bu bağlar korunarak ikinci uzmanın işlem yapması mümkün değil; yalnız RLS genişletmek yeterli olmaz.
3. **Mevcut assignment, OSGB uzman ataması değil.** `employee_assignments`, firma personelini işyeri/departman/göreve yerleştirir. `appointments` temsilci/destek gibi kayıtları yönetir. İkisi de oturum açan uzman üyeliğinin firmaya erişim ataması değildir.
4. **Ödeme sistemi zaten var.** iOS ve Android RevenueCat kullanıyor; sunucuda sync/webhook ve `user_subscriptions` mevcut. Yeni provider abstraction bu hattı koruyarak kurulmalı. Aday quota tablosu `authority='shadow'`; ortak satın alınmış kredi cüzdanı sayılmaz.
5. **Admin backend yapıları var; panel frontend'i bulunamadı.** `public.admin_users`, audit tabloları ve `private_isg` admin adayları mevcut. Bu checkout'ta genişletilecek gerçek admin web route/screen/service bulunamadı. Ayrı panel scaffold etmek yerine Faz F öncesi mevcut panelin kaynağı belirlenmeli.
6. **Migration dizinleri tek dağıtılabilir zincir değil.** Root migration'lar, pilot adayları ve ledger aynaları ayrı değerlendirilmeli. `db push` ile hepsini uygulamak mevcut şemayı çoğaltabilir.

## Gerçek bileşen haritası

| Alan | Kaynak | Bugünkü anlam / entegrasyon etkisi |
|---|---|---|
| Auth | `App/Services/AuthService.swift`; `private_isg.active_actor()` | Sunucu doğrulanmış kullanıcı/session; body'den aktör kabul edilmez. Üyelik yetkisi bundan ayrı eklenmeli. |
| Oturum ve context | [NovaSessionHost.swift](../../App/DesignSystem/ISG/NovaSessionHost.swift), [NovaWorkspaceController.swift](../../App/Services/Company/NovaWorkspaceController.swift) | Kullanıcı/session/company/epoch; workspace seçimi ve permission revision henüz yok. |
| Pilot giriş | [NovaPilotMainGate.swift](../../App/Views/Components/NovaPilotMainGate.swift) | `DEBUG && NOVA_PILOT_BUILD` ve yapılandırılmış kullanıcı kontrolü. Release'in otomatik yeni shell açtığı varsayılmamalı. |
| Firma | [CompanyService.swift](../../App/Services/CompanyService.swift), [NovaCompanyServiceAdapter.swift](../../App/Services/Company/NovaCompanyServiceAdapter.swift), `isg_pilot_overview_v2` | Legacy doğrudan CRUD ve dar pilot RPC birlikte var. Overview ve client cevap doğrulaması da owner eşitliği bekliyor. |
| Firma SQL | [add_companies.sql](../../supabase/migrations/20260520154818_add_companies.sql) | `user_id` profile FK; kullanıcı başına isim tekilliği, ücretli plan/firma limiti trigger'ı. Owner silinmesinde cascade, ortak OSGB verisi için ayrıca çözülmeli. |
| Personel/dizin | [personnel_owner_rpc.sql](../../supabase/migrations/20260913074153_isg_personnel_owner_rpc.sql), [workplace_context_assignments.sql](../../supabase/migrations/20260913081536_isg_workplace_context_assignments.sql) | Workplaces/departments/employees/job_roles/contractors/personnel assignments; composite owner FK ve işlem geçmişi. |
| Workspace adı | [workspace_availability.sql](../../supabase/migrations/20260913084736_isg_workspace_availability.sql) | Tenant tablosu kurmaz; owner/pilot/paid erişim değerlendirmesi sunar. Pilot override'ları da kontrol edilmeli. |
| Tekrar deneme | [NovaModuleMutationJournal.swift](../../App/Services/Company/NovaModuleMutationJournal.swift) | Keychain kaydı function + user + company/action/payload hash; receipt doğrulanıp decode olunca temizlenir. Workspace eklenirken yarım personal işlemler kaybedilmemeli. |
| Event/audit | [event_dispatch.sql](../../supabase/migrations/20260913110000_isg_event_dispatch.sql) | Personnel/directory outbox kaynakları, delivery/receipt/dead-letter/reconcile mevcut. Registry kaynak kümesi sınırlı, company bağlamı gerekli. Şirketi olmayan workspace olayı için doğrudan uyumlu değil. |
| Analiz | [NovaAnalysisWorkspaceService.swift](../../App/Services/Company/NovaAnalysisWorkspaceService.swift), `AnalysisService.swift`, `AnalysisResultHubService.swift` | `findings` doğrudan okumaları ile RPC/Edge Function birlikte var. Tenant izni yalnız liste ekranında filtrelenemez. |
| Analiz worker/rapor | `supabase/functions/{analyze,analyze-v4,analyze-vnext,process-analysis-jobs,analysis-result-sections,mutate-analysis-finding,register-report,generate-excel-report}/index.ts` | Kullanıcı bazlı job, finding, rapor, kota ve storage erişimleri. Kuyruktan çalışırken güncel üyelik/firma yetkisi yeniden kontrol edilmeli. |
| Dosya | [file_core.sql](../../supabase/migrations/20260913130000_isg_file_core.sql), [file_library.sql](../../supabase/migrations/20260915010000_isg_file_library.sql), `NovaFileLibraryService.swift`, `NovaFileLibraryLiveAdapter.swift` | Intent→inspection→asset→library; `isg-quarantine` / `isg-documents`, owner içeren path'ler. Legacy photos/reports/logos ayrıca var. |
| Kişisel/paylaşılan dosya | Pilot mirror `20260916090111_isg_pilot_personal_files.sql`, `20260916090922_isg_pilot_shared_file_assets.sql` | Kişisel dosya ile firmaya filing ilişkisi ayrı. Aynı sahibin blob paylaşımı tenantlar arası paylaşım anlamına gelmez. |
| iOS billing | [SubscriptionManager.swift](../../App/Services/SubscriptionManager.swift) | Mevcut RevenueCat/customer identity/store sync korunmalı. |
| Android billing | [BillingRepository.kt](../../android/core/data/src/main/kotlin/com/riskdetectedan/core/data/billing/BillingRepository.kt) | RevenueCat purchase/restore/backend sync gerçek kodda var. Android yeni scaffold gerektirmiyor. |
| Billing backend | `supabase/functions/revenuecat-webhook/index.ts`, `sync-revenuecat-subscription/index.ts`, `_shared/revenuecat-owner-guard.ts` | Legacy kullanıcı sahipliği ve abonelik otoritesi; OSGB daveti kişisel satın alma sahipliğini değiştirmemeli. |
| Quota/billing adayları | [quota_reservations.sql](../../supabase/migrations/20260913113000_isg_quota_reservations.sql), [billing_lifecycle.sql](../../supabase/migrations/20260914090000_isg_billing_lifecycle.sql) | Reservation/settlement/floor; lifecycle evidence/projection, benefits/checkout/reconcile. Projection `access_authority='legacy'`; store kredi ledger'ı hazır kabul edilemez. |
| Admin | [admin_users.sql](../../supabase/migrations/20260611105834_admin_users.sql), [observability_admin.sql](../../supabase/migrations/20260914130000_isg_observability_admin.sql) | Global roller owner/support/finance/analyst/legal_ops; workspace owner ile aynı rol değil. Aday admin session/action/audit/export mevcut, canlı etkinliği bu çalışmada doğrulanmadı. |
| Hesap silme | `supabase/functions/{request-account-deletion,process-account-deletion-queue,account-deletion-complete,retention-cleanup}/index.ts` | Kullanıcı silme ve storage cleanup, OSGB'den uzman ayrılmasından farklı tutulmalı. Cascade etkileri Faz C/D öncesi test edilmeli. |
| UI ortakları | `App/DesignSystem/ISG`, `App/Views/Components/NovaCompanyManagementGate.swift` | İstatistik, popup, empty state, firma modülleri yeniden kullanılmalı; yeni ikinci tasarım sistemi kurulmaz. |

Yukarıdaki SQL kaynakları bir sembolün nerede tanımlandığını gösterir; dosyanın varlığı canlıda uygulanmış olduğu anlamına gelmez. Aynı fonksiyonun farklı pilot tanımı olabilir. Effective policy/trigger/function seti ancak dağıtım zinciri ve DB kataloglarıyla doğrulanır.

## Kaynak taramasının kapsamı ve tekrarı

`node scripts/isg/osgb_repo_inventory.mjs > /tmp/osgb-source-index.json`

Bu HEAD'de 458 SQL dosyası, 466 tablo tanım geçişi (301 farklı sembol), 223 literal client callsite ve 25 top-level Edge Function entrypoint bulundu. Bunlar **canlı tablo/endpoint sayısı değildir**; aday ve tekrar edilmiş ledger tanımlarını kapsar. Script yalnız Git'te izlenen ilgili dosyaları okur, DB'ye bağlanmaz. Tablo tanımlarını ve `.rpc/.from/.invoke` literal çağrılarını dosya/satırla verir. Dinamik endpoint değişkenleri, shared helper'lar, UI doğrudan erişimleri, ALTER/FK/policy/grant ve dinamik SQL için manuel inceleme gereklidir. Özellikle `Nova*Service` client factory/journal çağrıları yalnız literal taramasıyla tamamlanmış sayılmaz.

## Migration ve dağıtım sınırı

[Pilot release README](../../supabase/pilot-release/README.md) root zincirinin doğrudan push edilmemesini açıklıyor. README'nin iki migration sayımı tarihsel; bugün dizinde daha fazla ayna var. Canlı son migration, policy/grant durumu, feature flag'ler ve remote hash'ler bu keşifte sorgulanmadı.

Faz B'nin ilk işi root adaylarını yeniden uygulamak değil, gerçek deployed baseline'ı pinleyip yeni additive candidate'ı bunun üzerine izole ortamda denemek. Pilot ledger aynası elle yeniden yazılmaz, uygulanmamış SQL applied işaretlenmez. Ayrı migration nesilleri için deployment manifest hazırlanır. Test fixture'larının kullandığı sentetik şema gerçek staging restore'unun yerine geçmez.

## Korunacak ürün kararları

Tek `workspace_id`; personal ve OSGB ayrı; tarihsel aktör ve güncel sorumlu ayrı. Workspace owner/admin/expert, global admin'den ayrı. Mevcut kişisel haklar ve RevenueCat hattı korunur. Yeni OSGB billing/seat/credit/storage ölçümü ileriki fazlarda gerçek doğrulama ve concurrency kontrolüyle açılır. Davet kişisel firmayı OSGB'ye taşımaz. Devir aynı OSGB içinde sorumluluğu değiştirir, yazarlığı değiştirmez. İBYS, resmi İSG-KATİP veri bağlantısı ve harici ödeme bu projenin bu kapsamına eklenmez.
