# İSGADA — OSGB tam entegrasyon ana planı

17 Eylül 2026 · Plan sürümü 1 · Referans kod: `6eebab8946c627f42d13415cff1b8dc5007cc1ce`, `codex/isg-transition-foundation`.

**Durum: yerel ana operasyon entegrasyonu tamamlandı; tam ürün ve yayın kabulü verilmedi.** Güncel kapsam/kanıt/eksikler [uygulama durumunda](OSGB_IMPLEMENTATION_STATUS_2026-09-17.md), 24 SQL adayının kesin sırası ve hash'leri [aday manifestinde](OSGB_CANDIDATE_MANIFEST_2026-09-17.json) kayıtlıdır. iOS'ta workspace/firma/ekip/atama ile D1–D9 birincil yolları workspace servislerine bağlıdır; ileri domain parity'si, gerçek provider/store, Android OSGB UI, admin frontend ve staging/device kabulü açıktır. Canlı veritabanına, kullanıcılara, API'lere, feature flag'lere, ödeme ürünlerine, webhook'lara, dosyalara veya uygulama dağıtımına işlem yapılmadı. İlerideki canlı geçiş bu belgeden otomatik yetki almaz; hazırlanmış somut yayın paketi ayrıca değerlendirilir.

Bu belge önceki yalnız Faz B planının üzerinde **A–L tam kapsamın ana kaynağıdır**. [Faz B teknik alt planı](OSGB_PHASE_B_PLAN.md) ayrıntılı ek olarak korunur. Yerel aday, staging kabulü ve canlı yayın birbirinden ayrı durumlarda izlenir; henüz kabul edilmemiş işin adı “tamamlandı” olarak değiştirilmez.

17 Eylül kod incelemesinde kişisel veri uyumluluğu ve yetki/istemci hataları düzeltildi; firma–uzman atama yönetimi ile D1–D9 ana iOS route'ları eklendi. Eksik ileri UI parity'si, provider/store, Android, admin ve devir teslimleri [inceleme raporunda](OSGB_INTEGRATION_REVIEW_2026-09-17.md) açıkça listelendi. Karar bağımsız bütün geliştirmelerin bitmiş olduğu varsayılmamalıdır.

## 1. Kaynaklar ve kapsamın tamamlığı

Girdiler: kullanıcının `ISGADA_OSGB_MULTI_TENANT_INTEGRATION_PLAN_2026-09-16.md` (ayrıntılı kaynak, aşağıda **S1**) ve `deep-research-report-2.md` (**S2**) dosyaları. Hash'ler [başlangıç raporunda](OSGB_BASELINE_2026-09-17.md). S2'deki harf sırası S1'den farklı; bu plan harfler için S1'in A–L sırasını, içerik için iki belgenin birleşimini kullanır. Güncel kullanıcı talebi ilk-aşamayla-sınırlı planı kaldırır; bütün entegrasyon burada planlanır.

Bağlı teslimler:

- [Özellik → kaynak → faz → kabul ölçütü matrisi](OSGB_REQUIREMENTS_TRACEABILITY.md): bütün zorunlu özellikler ve açıkça ertelenen seçenekler.
- [Canlı sistemi koruma ve yayın prosedürü](OSGB_RELEASE_SAFETY_PLAN.md): ortamlar, migration, geriye uyumluluk, prova, durdurma ve geri dönüş.
- [Gerçek repo envanteri](OSGB_REPO_INVENTORY.md) ve [domain/scope matrisi](OSGB_SCOPE_MATRIX.md): mevcut kodun nerede genişletileceği.
- [Başlangıç test raporu](OSGB_BASELINE_2026-09-17.md): tekrar çalıştırılmamış sonuçları güncel başarı gibi sunmadan referans.

### 1.1 Bitmiş ürünün kapsamı

Tek girişle kişisel çalışma alanı ve bir veya birden fazla OSGB üyeliği. OSGB sahibi/yöneticisi firma ekler, uzman davet eder, firmalara dönemli atama yapar. Uzman yalnız yetkili firmalarda mevcut tüm İSG işlemlerini yürütür. Firma verisi OSGB'de kalır; uzman ayrıldığında kişisel hesaba taşınmaz ve geçmiş yazar değiştirilmez.

OSGB ve uzman panelleri, mevcut Super Admin paneli genişlemesi, Apple/Google abonelik ve kredi satın alma, ortak AI cüzdanı, uzman kotaları, depolama ölçümü, raporlama, uzman devir sihirbazı, işletme hafızası ve kaynaklı AI devir özeti teslimin zorunlu parçalarıdır. AI özeti kullanıcının isteğine bağlıdır; özelliğin geliştirilmesi kapsam dışına ertelenmez.

Tam entegrasyon yalnız yeni firma ekranının açılması değildir. Liste/detail/create/edit/archive, kaynak dosyası, arama, rapor, export, import mevcutsa import, background job, bildirim, cache ve hesap silme yolları da tamamlanmış olmalıdır. iOS ve mevcut Android projesinde kabul ayrı yapılır.

### 1.2 Sabit sınırlar

- Aktif satın alma kanalları Apple IAP ve Google Play. Mevcut RevenueCat hattı korunur; harici ödeme/manuel tahsilat implementasyonu eklenmez.
- İBYS, resmi İSG-KATİP API/scraping/doğrulama, e-Devlet girişi ve kamu veri aktarımı yok. Manuel KATİP ve uzman belge bilgileri kullanıcı beyanıdır.
- Otomatik hukuki uygunluk kararı veya resmi doğrulanmış uzman rozeti yok. Takip skoru yalnız uygulama kayıtlarının durumunu anlatır.
- Ayrı veri kopyaları kullanan ikinci OSGB uygulaması veya paralel admin kullanıcı tabanı kurulmaz.
- Tenantlar arası firma mülkiyeti devri ve vergi numarasıyla global birleştirme yok. Aynı OSGB içindeki sorumluluk devri var.
- Kullanıcı şifresi görüntüleme, kalıcı impersonation, client service-role key ve finansal geçmişi düzenleyerek düzeltme yok.

## 2. Mevcut sisteme oturan mimari

### 2.1 Yeniden kullanım haritası

| Gerçek bileşen | Yapılacak genişleme | Korunacak davranış |
|---|---|---|
| `NovaSessionHost`, `NovaWorkspaceController`, `NovaPilotMainGate` | Auth identity'den ayrı workspace/membership context, permission revision, workspace seçimi | Personal giriş ve session doğrulaması; pilot/Release ayrımı |
| `CompanyService`, `NovaCompanyServiceAdapter`, `NovaPilotCompanyService` | Versioned workspace query/command yolları | Eski istemcinin personal firma işlemleri |
| `NovaPersonnelService`, `NovaDirectoryService`, `employee_assignments` | Company/workspace scope | Personelin işyeri/departman/görev ataması OSGB uzman atamasına dönüşmez |
| `Nova*` domain servisleri; `NovaModuleEditor`, `NovaPilotProcessGate` | Ortak permission context, author/responsible ayrımı | Mevcut form, popup, tarih, rapor, işlem sonucu ve domain kuralları |
| `NovaModuleMutationJournal`, ISG mutation context/outcome | Workspace içeren retry anahtarı ve scope doğrulaması | Yarım kalmış personal mutation'ın aynı işlem kimliğiyle güvenli tekrarı |
| `personnel_audit/receipts/outbox`, `directory_events/outbox`, event dispatcher | Workspace aggregate adapter, audit/receipt scope | Tek teslimat/receipt/dead-letter yaklaşımı; sahte company oluşturulmaz |
| `NovaFileLibrary*`, upload intents/assets, `isg-file-inspect` | Metadata/fiziksel object/filing erişimi ve byte olayları | Eski file path ve rapor/logo/fotoğraf erişimi |
| `AnalysisService`, result hub, AI worker ve rapor Edge Function'ları | Workspace'e sabit job + izin + reservation | Kişisel analiz ve rapor hakları; mevcut sonuç içerikleri |
| `SubscriptionManager`, Android `BillingRepository`, RC sync/webhook | Provider bağımsız workspace billing adaptasyonu | Mevcut personal abonelik, restore, renewal ve hak otoritesi |
| `public.admin_users`, audit ve private admin adayları | Global OSGB yönetim komutları | Mevcut admin güvenliği; workspace owner global admin sayılmaz |

Kaynakta aynı isimli `workspace` bugün tenant değildir. Admin frontend kardeş `RiskDetected-OperasyonMerkezi` deposunda tespit edildi; mevcut panelin OSGB entegrasyonu henüz yapılmadı ve o deponun kendi çalışma kuralları uygulanmalıdır. Repo migration'ları root adayları ile pilot ledger aynalarını birlikte içerir; doğrudan `supabase db push` dağıtım yöntemi olarak kullanılmaz.

### 2.2 Veri kimlikleri ve kalıcı kurallar

`workspace_id` tek tenant kimliğidir; ayrıca eşanlamlı `tenant_id` eklenmez. Auth user, workspace sahibi, tarihsel yazar ve güncel sorumlu ayrı anlamlardır. Mevcut `user_id/owner_id` sütunları topluca yeniden adlandırılmaz.

Önerilen workspace alanları: kind, name, status, timezone, creator, personal owner, version, created/archived timestamps. Kullanıcı başına tek personal workspace; OSGB adı global unique değil. Üyelik workspace/user tekil, role/status/practicing-expert/version ve yaşam döngüsü geçmişi içerir. Davet üye değildir; doğrulanmış email, süreli hash token, role ve seat reservation taşır.

Uzman profili mevcut profilin uygun uzantısında uzman sınıfı, belge no, beyan tarihleri ve iş iletişimini tutar. Bilgi kökeni self-reported/uploaded-document olarak gösterilir. Workspace member profili ekip, iş unvanı, kapasite ve yalnız yönetime açık iç not içerir; global kişisel profile karışmaz.

Firma mevcut tabloda workspace, creator/updater, archive/version ile genişler. İşyeri/location için mevcut `workplaces` yeniden kullanılır; ikinci şirket adres dizini kurulmaz. Uzman-company assignment membership'e bağlanır, role/primary/starts/ends/status/reason/version ve history içerir. Dönemler `[starts_at, ends_at)`; aynı tür üye ataması ve aynı firmada primary dönem çakışması DB invariant ile reddedilir, yalnız açık uçlu satır unique kontrolüne güvenilmez.

Her parent-child ve responsible membership ilişkisi aynı workspace'e composite FK veya eşdeğer DB invariant ile bağlanır. Workspace ve tarihsel creator normal update alanı değildir. Normal kullanıcı update'leri whitelist + expected version kullanır. Para integer minor unit + para birimi; byte ve credit integer; zamanlar UTC saklanır, gösterim ve kota dönemleri workspace timezone'una göre hesaplanır.

### 2.3 Yetki sözleşmesi

| İşlem | Owner | Admin | Expert | Platform superadmin |
|---|---|---|---|---|
| OSGB portföyü | Tam workspace | Tam workspace | Yalnız aktif atanan firmalar | Ayrı denetimli global servis |
| Firma ekle/arşivle | Var | Var | Varsayılan yok | Gerekçeli komut |
| Operasyon/izinli firma alanını düzenle | Kendi aktörüyle | Kendi aktörüyle | Atandığı firma + domain izni | Kendi admin aktörüyle |
| Davet/atama | Var | Var | Yok | Gerekçeli komut |
| Owner transfer/kapatma | Ek doğrulama | Yok | Yok | Kritik işlem protokolü |
| Satın alma | Var | Ayrı `billing.manage` izni | Yok | Müşteri adına mağaza satın almaz |
| Kredi raporu | OSGB geneli | Yetkisi kadar | Kendi kullanım/bütçesi | Global yetki kapsamında |
| Destek kredisi/override | Yok | Yok | Yok | Sınırlı, audit'li karşı hareket |
| Devir onaylama | Var | Var | Teslim bilgisi/onayı | Gerekçeli komut |

Üyelik/assignment bitince eski kayıtların yazarı olmak erişim sağlamaz. Askıya alma, devir tamamlanmasını beklemeden erişimi keser. Yeni uzman firma takımına açık kurumsal geçmişi görür; kişisel/sağlık/management-private içerik otomatik açılmaz. Personal workspace'e OSGB rolü üzerinden erişim verilmez.

Sunucu her istekte aktif session, workspace, güncel membership/role, company assignment ve domain/entitlement iznini doğrular. RLS read ile write-check ayrı test edilir; private helper recursion/search_path/EXECUTE sınırları denetlenir. Global admin için normal sorgulara genel `OR is_admin` eklenmez. Scope hatası kayıt varlığını sızdırmadan standart forbidden/not-found davranışına eşlenir.

### 2.4 Oturum ve istemci davranışı

Tek geçerli alan varsa doğrudan açılır, çoklu üyelikte son **halen yetkili** seçim veya seçici kullanılır. Deep link önce workspace sonra kayıt iznini doğrular. Cache anahtarları user/workspace/permission revision/company/query içerir. Workspace değişince task/realtime/arama state'i ayrılır; eski cevabın yeni ekranı doldurması engellenir. Başlayan upload/AI/purchase işlemi ilk workspace'ine sabit kalır.

Arka plandan dönüşte mevcut görünüm yetki doğrulanana kadar kontrollü loading state ile korunur veya hassas içerik örtülür; boş listeyi gerçek sıfır gibi gösterme. Auth refresh ile gerçek yetki kaybı ayrılır. Mutation başarı mesajı yalnız sunucu commit/receipt doğrulamasından sonra ortak component üzerinden çıkar. Yeni ekranlar mevcut siyah çizgi ikon, kompakt istatistik, ampullü full-width empty state, yuvarlak kolay basılan popup kapatma ve floating glass menü dilini kullanır; erişilebilirlik, dark mode ve TR/EN metinleri test edilir.

### 2.5 Şema ve veri otoritesi taslağı

Aşağıdaki yeni isimler öneridir; mevcut eşdeğer bulunduğunda genişletilir. Aynı gerçeği tutan iki otorite kurulmaz. Private ISG tabloları ve dar public RPC convention'ı korunur.

| Alan | Hedef nesneler / yeniden kullanım | Otorite ve asgari kısıt |
|---|---|---|
| Workspace/üyelik | `workspaces`, `workspace_memberships`, `workspace_invitations`, membership history | Personal owner unique; workspace/user unique; active owner korunur; invitation hash/token tek kullanımlık |
| Uzman profili | Mevcut profil uzantısı veya `expert_profiles`, `workspace_member_profiles` | Global beyan ile workspace iş bilgisi ayrı; iç not visibility |
| Firma/atama | `public.companies`, mevcut `workplaces`; yeni `company_assignments` ve events | Composite workspace/company/member; range overlap; immutable author ve değişebilir responsible |
| Domain | Mevcut tüm operational tablolar/children/receipts | Workspace scope parent'tan; domain version; creator/scope whitelist dışı |
| Billing | `billing_products`, `billing_identities`, `purchase_intents`, `store_transactions`, `billing_events`, workspace subscriptions/entitlements/overrides | Provider+environment+app+transaction unique; chain binding unique; versioned provenance; personal legacy otorite ayrımı |
| Credit/AI | `credit_wallets`, `credit_ledger_entries`, `credit_grants`, allocations, `credit_reservations`, `ai_usage_records`, member quotas | Wallet/workspace tekilliği; request hash; grant/purchase ve settle/reservation unique; immutable posting |
| Storage | Mevcut upload intents/file assets/derivatives/library filing; usage events/daily rollups/reconciliation runs | Object/version/source event unique; byte server ölçümlü; rollup yeniden üretilebilir |
| Devir | `company_handovers`, items, execution attempts | Workspace/company, from/to membership, effective time, preview hash, execution key/version; firma başına atomik |
| Hafıza | `company_memory_events`, `company_handover_briefs` | Source entity/id/version/event unique; visibility/redaction; brief source/model/template/time/review |
| Admin ve olay | Mevcut global admin grants/audit/actions + workspace event adapter | Tek global rol otoritesi; domain receipt/outbox retry pattern; reason/MFA/version |

`companies.user_id` gibi eski sahiplik FK'si ile yeni author FK'sinin hangi kayıt türünde nullable/retained/tombstoned olacağı C1/C4 migration tasarımında açıkça belgelenir. OSGB için zorunlu legacy owner FK'sini sürdürmek adına sahte auth kullanıcı oluşturulmaz. Personal account deletion eski kişisel davranışı korurken kurumsal author silinmesi workspace data cascade'ine dönüşmez. Bu geçiş doğrulanmadan ilk OSGB company yazılamaz.

Öncelikli sorgu indeksleri workspace/company/time/id, user/status/workspace membership, workspace/member/company assignment, wallet/time/id ledger, workspace/actor/time usage, workspace/uploader/status asset. Son indeks seti gerçek sorgu/EXPLAIN ve write maliyetiyle belirlenir; her sütuna kör indeks eklenmez. İzolasyon kısıtları performans gerekçesiyle kaldırılmaz.

## 3. A–L geliştirme sırası ve bağımlılıklar

Fazlar aşağıdaki incelenebilir PR'lara bölünür; harf bir takvim süresi veya deploy izni değildir. Her PR: amaç, gerçek dosyalar, schema/API değişimi, fixture, pozitif/negatif test, rollback ve açık bağımlılık içerir. Yeni dosya/tablo isimleri implementasyonda repo convention'ına göre kesinleştirilir.

| Faz | Teslim | Önkoşul | Durum |
|---|---|---|---|
| A | Repo envanteri, sahiplik haritası, baseline | Yok | Yerel keşif tamamlandı; canlı katalog doğrulaması bekliyor |
| B | Workspace/üyelik/davet/personel bağlamı, personal mapping | A + izole baseline | Yerel backend/client adayı ve disposable kabul testi hazır; staging bekliyor |
| C | Firma scope, uzman profili, atamalar/history | B | Yerel backend adayı ve A/B/P testi hazır; gerçek veri doğrulaması bekliyor |
| D | Bütün operasyon ve yan veri yolları | C | D1–D9 yerel aday zinciri, iOS ana ekran adaptörleri ve çapraz-domain prova hazır; ileri parity/staging/device kabulü bekliyor |
| E | OSGB/uzman ekranları, ortak operasyonlar | D | iOS store ve D1–D9 route'ları, Android data gateway hazır; Android UI ve cihaz E2E bekliyor |
| F | Mevcut Super Admin genişlemesi | D + mevcut panel kaynağı | Backend komut/overview adayı hazır; DEC-01 nedeniyle frontend kabulü bekliyor |
| G | Storage ölçümü, AI usage, wallet/reserve temeli | D + F güvenli admin komut çekirdeği | Yerel aday ve concurrency/reconcile testi hazır; gerçek provider/limit bekliyor |
| H | Apple/Google abonelik, katalog, seat enforcement | C/G + ürün kararları | Provider-neutral aday hazır; ürün kararları ve store sandbox bekliyor |
| I | Mağaza kredi satışı, grant/refund/ledger | G/H | Provider-neutral aday hazır; ürün kararları ve store sandbox bekliyor |
| J | Devir, işletme hafızası, deterministik ve AI brief | D/E/F; ücretli brief için I | Yerel aday ve stale/replay/revoke testi hazır; UI/retention kararı bekliyor |
| K | Tam sistem, güvenlik, performans, restore kabulü | B–J'nin bütün teslimleri | Yerel manifest, integrated rehearsal ve iOS build hazır; staging/restore/load/device kabulü bekliyor |
| L | Kontrollü pilot ve kademeli yayın | K + somut yayın kararı | Uygulanmadı; ayrı canlı yayın kararı gerekir |

E/F önce operasyonel çekirdek ekranları kurar, G–J verisi geldikçe aynı ekranları tamamlar. Kullanım/billing ekranı boş veya sahte veriyle bitmiş sayılmaz. Bu iki fazın **final kabulü** I/J sonrası yapılır; bağımlılık döngüsü nedeniyle yarım paneller teslim edilmez.

### Faz A — doğrulanmış başlangıç

**A1:** Mevcut envanter/scope/baseline dokümanlarını yeni başlangıç HEAD'iyle doğrula. Yerel başlangıçta foundation 655/659, design 181/194; modül DB, Swift harness ve transport fixture testleri geçti. Bunlar yeni entegrasyon testleri değildir.

**A2:** Başlangıç branch/HEAD/dirty tree kaydı alındı ve yerel adayların sıralı SHA-256 [manifesti](OSGB_CANDIDATE_MANIFEST_2026-09-17.json) üretildi. Canlı read-only katalog erişimi bu uygulama turunda yapılmadı. İleride izinli export ile deployed SQL hash/policy/grant/trigger/fonksiyon eşlemesi edinilir; hassas dump repoya konmaz.

**Kabul:** Kaynak/candidate/deployed ayrımı açık; mevcut başarısız testler triage edilmiş; eski ve yeni istemci fixture'ları hazır. **Geri dönüş:** Belge/test artifact değişikliği; ürün davranışı yok.

### Faz B — workspace, üyelik ve personal foundation

[B0–B4 ayrıntısı](OSGB_PHASE_B_PLAN.md) uygulanır; aşağıdaki genişletmeler tam kapsamın parçasıdır.

**B1:** Additive workspace/membership/invitation + lifecycle history; personal unique; OSGB yaratma+ilk owner atomik; owner transfer/son owner kilidi; üyeliğe self-elevation yok.

**B2:** Versioned context/list/member RPC; actor auth'tan; receipt/hash/audit/outbox aynı transaction; workspace aggregate adapter. Üyelik role/status/practicing değişiklikleri revision artırır.

**B3:** Dry-run/resume personal workspace backfill; orphan/quarantine raporu; yeni kullanıcıyla yarış kontrolü. Ödeme/bakiye/firma/asset taşımadan yalnız doğrulanmış mapping oluştur.

**B4:** Aynı login, workspace seçimi, context freshness, pending personal retry uyumluluğu; iOS/Android contract ve navigation. OSGB domain'leri hazır değilken legacy endpoint'e fallback yok.

**B5:** Invite create/revoke/resend/accept; doğrulanmış email, tek kullanım, normalize duplicate/rate limit, hash token, TTL. Notification outbox retry'ı; delivery failure üyelik yaratmaz. Suspend/end/reactivate ve owner transfer UI'ı. Gerçek seat policy H'de bağlanana kadar self-service davet kabulü kapalı.

**Kabul/test:** Çoklu-workspace aynı user, wrong email/expired/replayed token, concurrent owner change ve accept, revoked member/receipt, personal izolasyonu. **Geri dönüş:** Yeni workspace akışları kapanır; eski personal yol çalışır, üyelik/audit mapping silinmez.

### Faz C — firmalar, uzmanlar ve atama tarihçesi

**C1:** `companies` ve `workplaces` için additive workspace alanı/composite key/index; old-owner filtre, isim unique ve plan-limit trigger'larını birlikte ele al. Legacy `user_id` OSGB verisine dolaylı sahiplik hakkı veremez. OSGB şirketi ilk kez yazılmadan eski owner policy'lerinin bu satıra erişimi engellenmiş olmalı.

**C2:** Uzman global beyan profili ile OSGB iş profilini ayır; iç yönetici notlarını ayrı görünürlükte tut. Workspace uzman dizininde active/suspended/former/pending filtreleri ve kapasite/atama özetleri.

**C3:** Company assignment create/end/correct/history; çoktan çoğa, primary, ileri tarih, timezone ve aralık çakışması. Üyelik aktifliği ile seat/operasyonel uzman kuralı server'da kontrol edilir. Aynı firmaya iki uzman eşzamanlı update yaparsa expected version conflict.

**C4:** Personal company mapping/backfill; ongoing eski client insert/update uyum katmanı. Account deletion/owner departure için company/profile/auth cascade zincirini düzelt; kurumsal veri uzman user'a bağlı silinmez. OSGB owner transfer mağaza purchaser transferi değildir.

**Kabul/test:** A uzmanı B veya kendi personal firmasına OSGB rolüyle erişemez; future overlap reddedilir; author koruma; eski firma CRUD/quota/logo/rapor smoke testleri; deleted author kurumsal geçmişi düşürmez. **Geri dönüş:** Yeni OSGB firma yazımı kapanır; scope constraint/policy korunur, legacy personal yolu eski dış sözleşmesiyle devam eder.

### Faz D — bütün mevcut domain ve erişim yolları

Her D PR'ı [scope matrisi](OSGB_SCOPE_MATRIX.md) satırını ve [izlenebilirlik tablosunu](OSGB_REQUIREMENTS_TRACEABILITY.md) kapatır. Kontrol sırası schema/backfill/invariant → server/RLS/worker → client → pozitif/negatif/e2e. Tüm domain'leri tek dev migration'da taşıma.

| PR | Domain dilimi | Özel kabul |
|---|---|---|
| D1 | Workplaces/departments/employees/job roles/contractors/personnel assignments | Yanlış firma employee/department ID'si reddedilir; eski personnel history korunur |
| D2 | Eğitim kayıtları, katılımcılar, müfredat, sertifika ve mevcut yıllık eğitim planı | Saat, kişi, adam×saat ve eksik eğitim gerçek scoped kayıtlardan; aday/pilot veri çift sayılmaz |
| D3 | Risk analizi/sürümleri ve uygunsuzluk/actions/checklists | Finding→firma ataması gerçek commit sonrası listede görünür; kaynak snapshot, uzman görüşü/eğitim önerisi ve detay aynı içerik |
| D4 | Acil durum planı/tatbikat/temsilci-destek ataması/KKD | Team/employee/plan/file linkleri aynı workspace+company; kullanıcı rolüyle mesleki yetki karışmaz |
| D5 | Ekipman envanteri/periyodik kontrol/tür-periyot kataloğu | Ekipman firmaya bağlı; kontrol rapor/date/result/history doğru; katalog ve firma override'ı ayrılır |
| D6 | KATİP/yıllık iş planı/kurul-karar/çalışma izni/ziyaret/defter | Manuel kayıt niteliği, kaynak asset, karar sürümü ve gerçekleşme/planning ayrımı korunur |
| D7 | Dosya kütüphanesi/personal file/shared filing/legacy fotoğraf-logo-rapor | Parent filing izni olmadan blob ID ile erişim yok; eski dosya path'leri çalışır |
| D8 | Analiz intake/results/finding edit/worker, PDF-XLSX/export ve mevcut import | Job/input/output/link/download izinleri; üretim sonucu ve finansmanı workspace switch ile değişmez |
| D9 | Tracking/score/statistics/search/notification/realtime/personal notes/cleanup | Count ve cursor sızıntısı yok; özel notlar yönetim/uzman scope'una yanlış açılmaz; silme işçileri ortak veriyi silmez |

Her dilim liste/detail/yazma/arşiv/alt kayıt/rapor/arama/download/job ve eski client coverage içerir. RLS yanında tüm SECURITY DEFINER/service-role erişimleri açık scope uygular. Hazır olmayan domain OSGB için kapalı kalır; bir domain'in açılması diğerini dolaylı açmaz.

**Kabul/test:** A/B/P negatif matris + revoked membership + mixed parent-child + eski endpoint regression; ölçülen query plan/index ve batch performansı. **Geri dönüş:** Etkilenen OSGB domain flag'i kapanır; güvenli veri korunur, owner-only güvenliğine genel dönüş yapılmaz.

### Faz E — OSGB ve uzman deneyimi

**E1:** Workspace selector; OSGB onboarding/status/settings; firma portföyü, uzman/davet/atama yönetimi; rol uyumlu mevcut shell. Atanmamış firma ve boş OSGB yönlendirmeleri.

**E2:** OSGB dashboard: firma/uzman, atanmamış firma, açık/gecikmiş uygunsuzluk, planlanan/tamamlanan ziyaret, yaklaşan süreler; tüm kartlar aynı filtreli listeye iner. Expert home: kendi firmaları, görev/ziyaret, yaklaşan eğitim/doküman ve kendi bütçesi.

**E3:** Company detail ve tüm ortak modüller aynı data/service üzerinden; görev/takvim mevcut ziyaret/son tarih projeksiyonuna bağlanır. Yönetici “uzman olarak davranma” yoluyla author sahteleştirmez. Mesleki imza gerekiyorsa hazırlayan/sorumlu/onaylayan ayrı kayıt.

**E4 (G–J sonrası):** Seat/abonelik/credit/storage/kullanım sayfaları, devir sihirbazı ve memory sekmesi aynı navigation'a bağlanır. Gerçek ölçüm yoksa sıfır gösterme. Abonelik uyarıları kişisel kullanımı kesmez.

**Kabul/test:** Owner→davet→expert→firma→operasyon→istatistik akışı, aynı kullanıcının personal/iki OSGB geçişi, TR/EN/dynamic type/erişilebilirlik, iOS ve Android e2e. **Geri dönüş:** OSGB navigasyonu feature flag ile kapanır; background finansal uzlaştırma ve eski personal shell devam eder.

### Faz F — mevcut Super Admin paneli

**F1:** Gerçek panel repo/router/service konumunu al, mevcut auth/MFA/global-role grant akışına bağlan. `public.admin_users` ve private admin adaylarının hangisinin aktif olduğunu doğrula; ikinci rol otoritesi yaratma. Güncel grant iptali anında yeni komutları durdurur.

**F2:** Whitelist komutlar: OSGB oluştur, owner/uzman davet et, firma oluştur/ata, izinli kaydı düzelt/revizyon oluştur/arşivle, üyeyi suspend/reactivate et, owner transferi. Reason/ticket, target workspace/entity, expected version, mutation key/correlation zorunlu; kritik komutta MFA ve ek doğrulama. Genel SQL/table-edit arayüzü yok. Sınırlı before/after audit alanları hassas veriyi çoğaltmaz.

**F3:** Platform overview/OSGB list-detail/expert usage; server pagination/filter/aggregation. OSGB detayında üyeler, firmalar, atama, ziyaret/uygunsuzluk/doküman, memory/audit sekmeleri. Global metrik ile workspace metrik etiketi açık. Varsa support session varsayılan read-only, hedef+gerekçe+TTL+revoke+audit; kalıcı impersonation yok.

**F4 (G–J sonrası):** Billing/storage health, kredi ve AI, abonelik, usage ve devir sekmeleri; support credit, süreli entitlement override, purchase reconcile komutları. OSGB oluşturmak paid store satın alması üretmez; pending_purchase/admin_trial/admin_sponsored açık kökenle tutulur. Superadmin müşteri adına store purchase yapmaz.

**Kabul/test:** Eksik MFA/reason, revoked grant, yanlış workspace, replay, audit failure rollback; destek kredisi gelir sayılmaz; expired support session veri okuyamaz. **Geri dönüş:** Admin action flag'i kapanır; audit korunur, normal personal/mobile izinleri genişletilmez. Panel kaynağı yoksa F tamamlanmış sayılmaz.

### Faz G — dosya ölçümü, AI kullanım ve cüzdan çekirdeği

**G1 — Asset metadata:** Mevcut `file_assets` ve filing ilişkilerini genişlet: workspace/company, uploaded-by user/membership, source kind, object/version/path, server-byte, digest, lifecycle/timestamps. Eski object'leri topluca yeniden adlandırma. Tenant sınırları arasında ortak blob dedup açma; aynı tenant'ta bir object çok kayıtta kullanılsa da fiziksel byte bir kez sayılır. Retained sürüm/thumbnail/generated rapor ayrı source kind taşır.

**G2 — Ölçüm olayları:** Intent→karantina/inspection→finalize; server metadata ile byte doğrula. Finalize event tekil; başarısız upload sayılmaz. Delete requested→Storage API sonucu doğrula→deleted; yalnız arşivleme veya başarısız delete byte düşürmez. Son referans/retention koşulu sağlanmadan object silme. Eski dosya inventory'sini bugünün upload'ı gibi kaydetme. Günlük rollup ve reconciliation run fark kaydı; missing/orphan object, retry ve crash testleri.

**G3 — Wallet/ledger temeli:** Workspace başına ayrı wallet; posted/reserved/debt projection, immutable posting ledger, grants/allocation, reservation ve member quota. `purchase_credit`, `admin_grant`, `usage_debit`, `refund_reversal`, `correction` ayrılır. Reservation accounting ile posting bakiyesi farklıdır. Personal ledger varsa taşıma sırasında ikinci opening grant yok; yalnız bakiye varsa kaynak snapshot + unique migration entry. Mevcut shadow quota ledger ücretli bakiye diye sunulmaz.

**G4 — AI job muhasebesi:** Yetki → request/hash → wallet ve member quota kilidi → üst sınır reserve → job outbox → commit → provider çağrısı → tek debit/usage settle → kullanılmayan reserve release. Provider sırasında açık DB transaction yok. Aynı key/farklı payload conflict. Normal spend negatif bakiye üretemez; ek maliyet için sınır veya ek reserve gerekir. Kesin failure release; belirsiz timeout/başlamış cancellation reconciliation'a gider, kör yeniden ücretli çağrı yapılmaz. Dış provider exactly-once desteği yoksa tek dış çağrı garantisi verilmez; ledger charge tekilliği sağlanır.

**G5 — Usage ve kota UI:** AI kullanım kaydı workspace/actor/membership/company/feature/model/request/job, input/output ölçümü, charged units ve price-rule version taşır; prompt/personel içeriği analytics'e kopyalanmaz. Üye aylık bütçesi OSGB cüzdanı üzerinde limit; ayrı para değildir. Period workspace timezone'unda, yeni aya taşan iş başladığı rezervasyon dönemine bağlı. Workspace switch finansman kaynağını değiştirmez; yetersiz kredi kişisel bakiyeden sessizce çekilmez.

**Kabul/test:** Wallet 100 iken parallel 150 reserve reddi, kota yarışları, duplicate finalize/settle/delete, server byte spoof, provider ambiguous outcome, source uploader/history korunması. **Geri dönüş:** Yeni OSGB AI/upload başlatma kapanabilir; outstanding reserve/usage/file reconciliation devam eder, ledger/audit silinmez. Ücretli OSGB AI I öncesi açılmaz.

### Faz H — mağaza abonelikleri ve uzman kapasitesi

**H1 — Canonical billing ve RevenueCat kararı:** Client `PurchaseProvider` ile server `BillingProviderAdapter` farklı sözleşmeler. Catalog, purchase intent, verification, subscription reconciliation, entitlement ve grant servisleri provider tiplerinden ayrılır. Mevcut RC SDK purchase/restore ve personal webhook/sync otoritesi korunur. RC'nin OSGB product/binding/consumable olay ayrıntısını karşılayıp karşılamadığı sandbox spike ile kanıtlanır. Yeterliyse Apple/Google alışverişi mevcut SDK içinden yürür; eksik kanıt için dar server store adapter kullanılır. Aynı transaction'ı iki sistem grant/finalize etmez; **tek finalization sahibi** ADR'da belirlenir. SDK'nın finish/consume zamanlaması backend commit sonrasına zorlanabiliyor varsayılmaz; yetmiyorsa yalnız yeni OSGB ürünleri için kontrollü adapter seçilir, personal purchase yolu değiştirilmez. SDK listener'larının yeni ürünleri otomatik işleyip işlemediği de sınanır; RC ile doğrudan StoreKit/Play listener birlikte çalışınca ownership/dedup ayrımı kanıtlanmadan bu yapı yayınlanmaz.

**H2 — Katalog, identity ve intent:** Canonical starter=5, growth=10, pro=20 expert; scale=21+ pazarlama aralığı ama teknik max_experts ürün kararı olmadan satılamaz. Provider/environment/product/base-plan/offer/periyot/version eşlemesi; fiyat store'dan, TL hardcode yok. Consumable kredi ürünleri ayrı; istenmeyen aylık promosyon kredi eklenmez. Actor+workspace+izinli product+opaque billing identity+expiry+idempotency server intent'te saklanır. Apple account UUID/Google obfuscated identity planı gerçek SDK destekleriyle doğrulanır; PII veya client'in workspace id beyanı billing kanıtı değildir.

**H3 — Apple adapter:** Ürün getirme, purchase pending/cancel/success, unfinished transaction listener, server doğrulama, StoreKit/RC identity binding, App Store server notification ve reconciliation. App/environment/product/transaction/subscription-chain/quantity/effective-time/provenance doğrulanır; JWS decode tek başına doğrulama değildir. Aynı mağaza hesabıyla çoklu OSGB aboneliği subscription-group davranışı sınanmadan vaat edilmez; ilk sürüm chain başına tek OSGB binding.

**H4 — Google adapter:** Ürün/base-plan/offer, purchase query/restore, verified PURCHASED, RTDN/server API/reconcile; pending iken grant yok. Subscription acknowledge ve consumable consume ayrı görevler. Refund/revoke/state mapping ve provider deadline alarmı; gerçek API/SDK sürümü implementation'da pinlenir.

**H5 — Inbox/projection/retry:** Callback/webhook/restore girdisi güvenilir doğrulama sonrası kalıcı inbox'a; event/transaction unique, state/grant/outbox commit; finalization kanıtlı adapter politikasına göre retry. RC/store bildirimleri aynı canonical transaction'da birleşir. Sırasız HTTP gelişi yerine effective time + authoritative reconcile. Dead-letter, lag, verified/rejected/unknown ve versioned provenance. Hassas receipt/token loglanmaz.

**H6 — Seat enforcement:** Aktif benzersiz practicing expert bir seat; yalnız yönetim yapan owner/admin sıfır, operasyon yapan owner/admin bir seat. Çok firma assignment bir seat'i çoğaltmaz. Davet rezervasyonu, accept/reactivate/practicing değişikliği ve effective downgrade aynı kilitli capacity kuralına bağlı. Kabulde rezervasyon aktife dönüşür, iki kere sayılmaz. Expired/revoked invite rezervasyonu release. Last-seat parallel accept testi zorunlu.

**H7 — Lifecycle/restore/çakışma:** active, canceled-but-active, grace, pending, hold/paused, expired/revoked, verification-failed canonical state'leri provider state/provenance ile saklanır. Cancel paid-through tarihe kadar hakkı korur; veri silinmez. Upgrade/downgrade gerçek effective tarihte; fazla seat olursa rastgele kullanıcı çıkarılmaz, yeni kapasite/atama artışı bloklanır, düzeltme ve read/export davranışı ürün kararına göre gösterilir. Owner departure purchase history'yi ve renewal binding'i değiştirmez. Restore başka OSGB'ye taşıma değildir. İki platformda aktif abonelik oluşursa iki kayıt da korunur; seat'ler toplanmaz, bir provider revoke diğer geçerli hakkı yanlış kapatmaz. Deterministik entitlement precedence ve destek uyarısı test edilir.

**Kabul/test:** İki mağazada sandbox purchase/renew/restore/pending/refund, app/product/env mismatch, forged callback, duplicate/sırasız notification, owner transfer, chain replay ve RC personal regression; müşteri hesabı başına çoklu OSGB ürünleme kapısı. **Geri dönüş:** Yeni OSGB intent/purchase kapatılır; personal satış/renewal ve mevcut OSGB notification/reconcile/finalization durmaz.

### Faz I — kredi satışı ve kesin muhasebe

**I1:** Store consumable verified purchase→workspace binding→tek grant, grant allocation ve unique purchase-event invariants. Callback+webhook+restore üç kez gelse bir bakiye etkisi. UI yalnız backend wallet doğrulanınca satın almayı tamamlandı gösterir; pending ve verification failed açık durumlar.

**I2:** Commit sonrası finish/consume veya callback kaybı için retry/inbox reconciliation; yeniden grant yok. Cihaz restore listesi tüketilmiş kredinin muhasebe kaynağı değildir; server ledger esas. Apple/Google'dan alınmış satın alma kredisi sona ermez, abonelik bitince bakiye silinmez. Feature entitlement ile bakiye farklı gösterilir.

**I3:** Refund grant referansıyla karşı posting; harcanmamış allocation önce geri alınır, harcanmış kısım debt olur. Spend debt yaratamaz, doğrulanmış refund yaratabilir. Available=max(0,posted−reserved), debt ayrı; yeni harcama durur. Pending reservation/refund yarışında wallet lock ve açık settle/release kararı. Gelecek grant'in debt mahsup sırası sabit ve audit'li; random grant seçimi yok.

**I4:** Superadmin support credit/correction: reason/ticket, limit, ek onay gerektiren eşik, correlation/actor; satış/gelir raporuna girmez. Entitlement override süreli/kökenli/revoke edilebilir; store subscription taklidi yapmaz. OSGB ve expert credit history/kota ekranları; E4/F4'e bağlanır.

**Kabul/test:** Tek transaction tek grant, concurrent buy/spend/refund, consumed refund/debt/mahsup, replay grant, wrong workspace restore, admin limit/audit failure ve personal balance regression. **Geri dönüş:** Yeni kredi satışları kapanır; mevcut wallet kullanılabilirliği belirlenmiş entitlement kuralıyla korunur; refund ve reconciliation çalışır, posting silinmez.

### Faz J — devir sihirbazı ve işletme hafızası

**J1 — Preview:** Kaynak uzman ve firmalar → hedef uzman/etkin tarih → açık işler seçimi → not/checklist → preview → onay. Açık/kritik uygunsuzluk, geciken/ileri ziyaret, yaklaşan evrak/eğitim, açık görev, dosya ve önemli not özetlenir. Birden fazla atanmış uzmanın başka sorumluluğu yanlış kaldırılmaz; devredilmeyen işlerin kime kalacağı açık gösterilir. Expert teslim onayı ile yönetici yürütme onayı ayrıdır.

**J2 — Execute:** Preview hash/snapshot/version; commit'te source assignment, hedef üyelik/seat/status, primary overlap ve iş sürümleri yeniden kontrol edilir. Bir firma: handover+assignment close/open+seçili sorumluluklar+history+audit+memory/outbox tek transaction. Çok firmada **firma başına atomik**, batch ilerleme ve kısmi hata raporu; başarılı firma tekrar işlenmez. Gelecek tarihli transfer job'u zamanı gelince yeniden doğrular; hedef suspend ise durur ve yöneticiye bildirir.

**J3 — Cancel/compensate:** Çalışmamış plan iptal edilir. Tamamlanmış devir geçmişi silerek geri alınmaz; ters/yeni devir, güncel version kontrolü ve compensation. Sonradan yazılmış yeni uzman kayıtları eski snapshot'la ezilmez. Aynı OSGB sınırı, tarihsel creator/uploader/AI actor korunur.

**J4 — Memory projection:** Mevcut source events'ten company-created, assignment/transfer, visit, nonconformity, risk, document, training, critical-note vb. kronolojik indeks. Source entity/id/version/event key tekil; occurred_at ile backfill recorded_at farklı. Visibility company-team/management/support; gizlenmiş/silinmiş kaynağın eski özetini göstermeye devam etme. Timeline filtre/pagination/source deeplink, olay düzeltme ve yeniden kurma/reconcile. İkinci operasyon veritabanı kurulmaz.

**J5 — Deterministik brief ve AI:** AI kapalıyken çalışan açık kritik/gecikmiş/yaklaşan iş ve son operasyon özeti. İsteğe bağlı AI brief aynı I ledger yolundan tahmini kredi ve kullanıcı onayıyla; prompt injection'a karşı kaynaklar talimat değil veri. Yetkili source/chunk retrieval, private not filtreleri, model/template/version/generated time/source IDs/versions ve review status; kaynak değişince stale etiketi. Kaynaksız çıkarım doğrulanmalı işareti; kaynak linkleri. Yeniden üretim kendiliğinden sınırsız harcama yapmaz.

**Kabul/test:** Preview sonrası yeni iş/version/suspend, future transfer, duplicate execute, batch partial retry, eski author/upload usage korunması, compensation güncel veriyi ezmez, memory redaction/search/RAG negatifleri, AI kapalı ve yetersiz kredi akışı. **Geri dönüş:** Yeni devir/AI brief oluşturma kapanır; geçmiş ve scheduled job güvenli pause/revalidation ile korunur, compensation gerekir.

### Faz K — uçtan uca kabul ve yayın provası

**K1:** [Kapsam matrisindeki](OSGB_REQUIREMENTS_TRACEABILITY.md) her mandatory satır için uygulama PR'ı + test kanıtı + mobil/admin kabulü. Tüm domain A/B/P izolasyonu, RLS policy OR bileşimi, grant/search_path, service-role worker/download/export, membership revoke, log/secret/redaction incelemesi.

**K2:** Performance/capacity: büyük firma portföyü, çok uzman paralel write/seat/credit, pagination stable cursor, N+1, indeks/EXPLAIN, queue lag ve offline reconnect. Test dataset/süre/yük/sonuç kaydedilir; ölçülmemiş sayı başarı diye yazılmaz.

**K3:** DB + gerçek object içeren izole restore provası; store inbox/ledger/job/pending reservations/asset referansları tutarlı mı. Fault injection: DB unavailable, provider timeout, notification duplicate, worker crash after commit, failed delete, migration lock/time budget aşımı. Eski ve yeni app sürümü birlikte aktifken legacy uyumluluk.

**K4:** iOS tam build/test/device, Android build/test/device; erişilebilirlik/localization; store sandbox ve review metadata/demo hesabı. Admin tüm sekmeleri gerçek scoped datayla çalışır. Kalan başlangıç test başarısızlıkları düzeltilmiş veya gerekçeli yeni davranış testiyle değiştirilmiş olmalı; sessiz ignore yok.

**Kabul:** Sıfır açık kritik/yüksek izolasyon/finansal bütünlük hatası; tüm mandatory scope tamam; restore ve rollback provası kanıtlı; karar defterindeki yayın engelleri kapanmış. **Geri dönüş:** Yayın paketi reddedilir; canlıda değişiklik yapılmaz.

### Faz L — canlıya güvenli, kademeli geçiş

[Canlı koruma prosedürü](OSGB_RELEASE_SAFETY_PLAN.md) bağlayıcı yayın planıdır. Bu aşama mevcut çalışma kapsamında yürütülmez.

**L1:** Reviewed baseline→additive schema→dark versioned backend; bütün OSGB flag'leri kapalı. Personal sentinel smoke ve latency/error/lock ölçümü; user-facing kişisel davranış ve store otoritesi aynı kalır.

**L2:** Küçük, checkpoint'li personal/company/child mapping batch'leri; dual-read karşılaştırma yalnız read; duplicate dış etki üretmeyen sidecar projection. Anomali durdurma; NOT NULL/FK/policy enforcement ayrı küçük adımlar. Eski client concurrent writes güvenli compatibility yolundan mapping alır.

**L3:** Seçilmiş onaylı OSGB pilotu, tüm zorunlu domain ve billing/credit/devir/admin özellikleri hazır olarak; sandbox/test hakları açık kökenli. Personal kitleye otomatik OSGB geçişi yok. Pilot başarıdan sonra onaylı gerçek store ürünleri ve dar OSGB cohort.

**L4:** Operasyon sorumlusu ve tanımlı gözlem pencereleriyle cohort genişletme; gate kötüleşirse yalnız OSGB yeni onboarding/intent/iş başlatma kapanır. Telemetri, destek, pending jobs/purchases ve finansal reconciliation takip edilir. Eski sütun/policy kaldırma uzun süre sonra ayrı contract PR; ilk yayının zorunlu parçası değildir.

**Kabul:** Eski personal müşterilerde davranış/veri/hak kaybı yok; pilot mandatory e2e çalışır; drift/incident eşikleri sağlanır; geri dönüş denenmiş. “Sıfır risk” garantisi yerine ölçülen kabul ve durdurma mekanizması kullanılır. **Geri dönüş:** OSGB kill switch, kompatibl eski app/backend route, güvenli read-only; ledger/purchase/author/audit korunur, genel DB restore varsayılan rollback değildir.

## 4. Metrik ve raporlama sözlüğü

Her kart: kapsam, dönem/timezone, hesaplama zamanı ve gerektiğinde reconciliation zamanı. Karttan detay listeye aynı filtreyle gidilir. Ölçüm yoksa “ölçülmüyor”, kaynak kapalıysa unavailable; sahte sıfır yok.

| Gösterge | Kaynak / tanım |
|---|---|
| Aktif OSGB / ödeme yapan OSGB | Workspace status ve store entitlement ayrı metrik |
| Aktif uzman / seat | Aktif practicing membership; global benzersiz user ayrıca; reserved seat ayrı |
| Firma / atanmamış firma | Workspace aktif company; geçerli assignment yokluğu; tenantlar arası birleştirme yok |
| Ziyaret / uygunsuzluk / doküman | Planned/performed/cancel/late; open/closed/reopened/critical; current/expired/version/eksik ayrımı |
| Eğitim | Verilen saat, benzersiz kişi, kişi×katılım saati, eksik konular/kişiler; breaks/duplicate attendance dahil değil |
| AI tüketimi | Kesinleşmiş debit; reserve, failed/unknown ve pricing version ayrı; expert/company/feature/model filtre |
| Kredi satışı | Verified purchase grant; admin grant ve refund ayrı, credit adedi para geliri değildir |
| Mevcut depolama | Halen fiziksel tutulan object/version byte; retained archive ve generated/derivative dahil, aynı object tek |
| Dönem yükleme / üretim | Başarılı user upload byte, generated byte ayrı; sonradan silme geçmiş upload metriğini azaltmaz |
| Dosya / indirme | Mantıksal aktif dosya ile fiziksel sürüm ayrı; download request ile teslim edilmiş byte ayrı; signed URL oluşturmak indirme kanıtı değil |
| Gelir / MRR | Doğrulanabilen store tutarı+para birimi+dönem; eksik finansal veride tahmini brüt etiketi; FX kaynağı olmadan para birimleri toplanmaz, net/vergi/komisyon uydurulmaz |
| Sağlık | Purchase verification/finalization, binding conflict, inbox/outbox lag, dead-letter, wallet drift, storage drift, admin auth/scope retleri |

MB/GB decimal byte, MiB/GiB kullanılırsa ayrı etiket. Uzman upload ve AI geçmişi orijinal aktörde kalır; devir sonrası güncel sorumlu bazlı görünüm ayrı rapordur. Prompt, email, personel veya token metrik label'ı olmaz.

## 5. API, olay ve idempotency ortak kontratı

Mevcut RPC/Edge yaklaşımı korunur, yeni genel REST framework zorunlu değil. Workspace list/context/create/settings/member; company CRUD/assignment/history; usage; upload/finalize/download/delete; catalog/intent/verify/restore; provider inbox; AI job/get/cancel/settle; handover preview/execute/cancel; memory/brief; admin whitelist komutları versioned contract olarak tanımlanır.

Mutation: `workspace_id`, allowed domain payload, `expected_version`, `idempotency_key/request hash`; actor/session sunucu kaynaklı. Queue: workspace, original actor, company/source id/version, correlation, operation key ve izinli service actor. Job başlaması/sonuç sunulması güncel yetkiyi yeniden değerlendirir; yetki kaybı ücretli dış etki sonrası muhasebeyi yok etmez, sonuç erişimini durdurur.

Standart hata ailesi: UNAUTHENTICATED, FORBIDDEN/NOT_FOUND, WORKSPACE_INACTIVE, ASSIGNMENT_REQUIRED, SEAT_LIMIT_REACHED, INSUFFICIENT_CREDITS, QUOTA_EXCEEDED, PURCHASE_PENDING, PURCHASE_BINDING_CONFLICT, VERSION_CONFLICT, INVALID_SCOPE, RETRYABLE_PROVIDER_ERROR. Retry edilebilirlik ve user-visible localized mesaj ayrı; raw SQL/provider secret yok. Cursor scope/revision/version'e bağlı ve deterministik sıralı; farklı workspace'te replay edilmez.

## 6. Açık kararlar ve uygulama kapıları

Bu kararlar uydurulmaz; ilgili geliştirme mock/fixture ile sürdürülebilir fakat bağlı canlı özellik karar kapanmadan açılmaz. Ürün karar sorumlusu kullanıcı/ürün sahibi; teknik öneri, kanıt ve uygulama ekibi ayrı alanlarla ADR'da kayıtlıdır.

| ID | Karar | Önerilen yaklaşım / engellediği kapı |
|---|---|---|
| DEC-01 | Gerçek admin frontend repo/route/auth akışı | Mevcut paneli genişlet; F1/final admin kabulünü engeller |
| DEC-02 | Scale max_experts | Açık integer limit veya açık ürünce onaylı sınırsızlık; NULL varsayımı yok; H katalog/Scale satışı |
| DEC-03 | Product IDs, süre, fiyat ve credit paket miktarı | Store ürünlerinden doğrula; test fixture fiyatını gerçek ürün sayma; H/I satış |
| DEC-04 | Invite seat reservation TTL | Süreli rezervasyon + accept'te tekrar kontrol önerisi; gerçek TTL ürün kararı; H/L davet |
| DEC-05 | Grace/expired/downgrade ve elde kalan kredi kullanım hakkı | Bakiye silme yok; güvenli read/export; yeni write/AI erişimi açık state matrix ile; H/I/L |
| DEC-06 | Plan storage limitleri ve retention | Integer byte + sürüm/arşiv dahil tanım; limite dair sayı üretme; G quota enforcement |
| DEC-07 | Support credit/override üst sınırı ve ikinci onay eşiği | Süreli/kökenli ve reason/ticket; finance yetki matrisi; F4/I4 |
| DEC-08 | Hassas veri sınıfı/saklama/silme/tombstone | Kurumsal geçmiş ve kişisel silme ayrımı; retention sorumlusu kararı; C/D/K |
| DEC-09 | RPO/RTO, SLO, lock/batch bütçesi, pilot cohort/gözlem | Staging ölçümünden sayısal eşik; boş eşikle deploy yok; K/L |
| DEC-10 | RevenueCat OSGB identity ve finalization sahipliği | Sandbox kanıtıyla mevcut SDK tercih; ikinci grant/finish yetkilisi yok; H1/I |
| DEC-11 | Aynı store hesabının çoklu OSGB aboneliği | İlk sürüm chain başına tek binding; çoklu satın alma vaadi test edilene kadar yok; H ürünleme |
| DEC-12 | Platform admin global grant ve support session ihtiyacı | Mevcut grant otoritesiyle eşle; session gerekiyorsa TTL/read-only; F |
| DEC-13 | Gelecek ürün genişlemeleri | Yeni OSGB şablonu, yeni CSV/XLSX import, isteğe bağlı onay, gelişmiş iş yükü; §7'de açık kapsam |

## 7. Kaynak belgede opsiyonel olan genişlemeler

S1 §13'te “sonraki ürün genişlemeleri” olarak geçen yeni OSGB şablon kütüphanesi, yeni toplu CSV/XLSX import ekranları, isteğe bağlı doküman onay iş akışı ve gelişmiş uzman iş yükü optimizasyonu **ilk tam OSGB entegrasyonunun zorunlu kabulü değildir**. Tam planda görünür seçenek olarak korunur; sessizce unutulmaz. Mevcut import/şablon/onay/iş yükü özelliği varsa D/E'de tenant kapsamına alınması zorunludur. Yeni manager/read-only auditor rolü de başlangıç owner/admin/expert kapsamından sonra eklenebilir.

Genişleme paketi açılırsa: X1 workspace şablon version/permission; X2 preview+validation+checkpoint+row error+idempotent import; X3 approval state machine+immutable revision/approver/audit; X4 kaynaklı capacity/workload metriği. Her biri B–D ve ilgili E/F izinlerine bağımlı, aynı A/B/P negatif matrisi ve read/export kabulüyle ayrı ürün PR'ıdır. Resmi entegrasyon veya muhasebe eklemez.

## 8. Tam entegrasyonun bitiş tanımı

“Bitti” için bütün mandatory gereksinimler uygulandı/test edildi/kabul edildi olmalı; yalnız planned veya UI mock yeterli değil. Her gereksinim satırında PR/commit, migration manifest sürümü, DB test artifact, iOS/Android/admin kanıtı ve kalan karar bulunur.

Uçtan uca son prova: owner OSGB kurar → mağazada doğrulanmış plan → uzman daveti/seat → firma+atama → expert aynı login ile işlem → dosya/AI rezervasyon ve kredi → bulgu firmaya kaydolur/detail açılır → dashboard ve admin doğru sayar → uzman devri ve memory → refund/restore ve support correction → suspend/erişim iptali → personal kullanıcı aynı eski akışını sürdürür. Her adım A/B tenant negatif kontrolüyle tamamlanır.

Canlı kullanıcıları koruma kabulü; yalnız yeni özelliğin çalışmasıyla kapanmaz. Eski sürüm personal login, firma/personel/analiz/rapor/logo/dosya/abonelik/restore/silme davranışı ve ölçülen hata-gecikme bütçesi korunmalıdır. Kaynak/dump/receipt sırları repo/loga yazılmaz. Operasyon sorumlusu ve geri dönüş yolu olmayan paket L'ye geçmez.

## 9. Teknik kaynak doğrulama notu

17 Eylül 2026'da salt-okunur resmi kaynak kontrolü yapıldı; SDK sürümleri ve ürünleme implementation/sandbox sırasında tekrar doğrulanır. Bu bir mağaza onayı garantisi değildir.

Apple IAP ile alınmış kredilerin sona ermemesi kuralı I tasarımında korunur. Google kredi davranışına da aynı ürün tutarlılığı uygulanır. [Apple App Review Guidelines, 3.1.1](https://developer.apple.com/app-store/review/guidelines/).

Google'da pending satın alma entitlement üretmez; satın alma backend'de doğrulanır. Acknowledgement/consumption sorumluluğu seçilen adapter/SDK ile sandbox'ta kanıtlanır. [Google Play Billing security](https://developer.android.com/google/play/billing/security).

Supabase'de service role erişiminin RLS bypass niteliği nedeniyle worker/admin işlemleri ayrıca açık scope doğrular. [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

RevenueCat webhook güvenliği, retry ve kimlik olayları mevcut entegrasyonla birlikte ele alınır; dokümanın varlığı workspace binding/finalization tasarımının SDK'da hazır olduğu anlamına gelmez. [RevenueCat Webhooks](https://www.revenuecat.com/docs/integrations/webhooks).
