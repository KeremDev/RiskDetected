# P01 — doğrulanmış işlem prototipi

12 Eylül 2026. Bu parça **sentetik PostgreSQL prototipidir**, production migration/API değildir. Canlı eski akışa bağlı değildir; yeni şirket/personel/not/ödeme tablosu oluşturmaz. P00 restore, gerçek Auth/session ve capability kontrolleri tamamlanmadan domain mutation'ına dönüştürülemez.

## Çalışan parçalar

- Strict mutation context: Deno, Swift ve Kotlin aynı 43 JSON örneğini kabul/reddeder. Kimlik, sayı sınırları, eksik/bilinmeyen alanlar, kişisel scope'a şirket/entity ekleme ve nullable işyeri örnekleri dahil. Bu parser yetki vermez.
- 3 native/backend kaynak yüzeyi için dosya-hash + test harness + fixture bağlama kaydı. Yeni dosya veya aynı dosyada yeni kod, eski eşlemeyi geçersiz kılar. Symbol etiketleri review edilmiş isimlerdir; bu araç AST/call-graph veya bütün legacy fonksiyonların envanteri değildir. Swift CodingKey glue'su ayrıca doğrudan fonksiyon-coverage iddiası taşımaz.
- Gerçek PostgreSQL transaction, row/advisory lock, foreign key, owner kontrolü, private function ACL, audit/outbox/receipt atomikliği.
- Gerçek 20-istek concurrency; aynı retry tek uygulama, farklı key/aynı expected_version tek kazanan.
- Internal worker lease/fencing, 30 saniyelik sentetik süre, 3-deneme sentetik sınır, sıralı aggregate sürümleri, dead-letter ve bağımsız şirketin ilerlemesi.
- Consumer receipt + projection + tamamlanmış event tek transaction. Commit öncesi SQL hata enjeksiyonu ve gerçek backend process termination ile yarım kayıt oluşmaması; commit sonrası kayıp acknowledgment tekrarında tek projection.

30 senaryo geçti. [Makine çıktısı](evidence/P01_TRANSACTION_PROTOTYPE_2026-09-12.json) image digest, Node/PostgreSQL sürümü, seed, kaynak SHA256, run ID ve cleanup sonucunu taşır.

## Sınanmış akış

~~~mermaid
flowchart TD
    A[Sentetik actor/session adaptörü] --> B[Aktif actor ve şirket sahibi]
    B --> C[Actor + mutation key kilidi]
    C --> D{Önceki receipt?}
    D -->|aynı payload| R[Önceki sonuç; yeni yan etki yok]
    D -->|farklı payload| X[Conflict]
    D -->|yok| E[Şirket + entity scope ve sürüm kilidi]
    E --> F[Counter + audit + outbox + receipt]
    F -->|tek transaction| G[Commit]
    F -->|hata / bağlantı ölümü| H[Tümü rollback]
    G --> I[Lease alan bağımsız worker]
    I --> J[Token + süre + aggregate sıra kontrolü]
    J --> K[Consumer receipt + projection + event done]
    K -->|tek transaction| L[Commit; tekrar ack etkisiz]
    K -->|hata / bağlantı ölümü| M[Rollback; güvenli retry]
~~~

## Güvenlik ve izolasyon

Koşucu yalnız açık JSON manifest'i kabul eder. İsim/project/label/image/run ID eşleşir; host mount, port ve ağ çıkışı yoktur. `docker exec` ile yalnız o yeni container'a gider. Mevcut isim doluysa yeniden kullanmayı reddeder. Üretim yedeği, Keychain, ortam API anahtarları veya kullanıcı verisi yüklenmez. Image otomatik indirilmez; önceden bulunmalıdır. CI image'ı digest ile ayrı hazırlık adımında indirir.

İş bitince yalnız oluşturduğu tam container ID'sini ve run label'ını doğrulayarak siler; kullanıcının eski container/volume'larına dokunmaz. Silinen veri yalnız bu run'ın sentetik fixture'larıdır; kaynak SQL ile tekrar oluşturulur. `output/isg/runs/<run_id>/database-contract.json` kalır. Hata ve cleanup ayrı durumdur; cleanup başarısızsa suite yeşil değildir. SIGINT/SIGTERM best-effort cleanup uygular; SIGKILL/host çökmesinde sonraki run var olan container'ı silmek yerine reddeder. Böyle bir hedef ayrıca incelenmelidir.

Private fonksiyonlar için varsayılan `PUBLIC EXECUTE` global düzeyde kaldırılır: yalnız `IN SCHEMA` revoke, PostgreSQL'in global default grant'ini kaldıramaz. İlk negatif test bu hatayı yakaladı. Geçici bootstrap PostgreSQL sürecine erken bağlanma da testte bulundu; sabit image'ın final PID 1 wrapper'ı ve SQL readiness birlikte bekleniyor. İki düzeltmeden sonra suite tamamlandı. Kaynaklar: [Supabase database functions](https://supabase.com/docs/guides/database/functions), [PostgreSQL default privileges](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html), [PostgreSQL locking](https://www.postgresql.org/docs/17/explicit-locking.html).

## Production'a taşınmadan açık kalanlar

1. `actors.active` gerçek `auth.sessions`, JWT doğrulama, account deletion veya paid capability yerine geçmez. Sonraki [session freshness prototipi](P01_SESSION_FRESHNESS_PROTOTYPE.md) gerçek yerel Auth JWT/login/logout ve DB row lock ile ayrı doğrulandı; henüz bu transaction mutation'ına bağlı değildir. Gerçek istemciye SQL/GUC erişimi verilmez.
2. Counter domain örneğidir. Şirket/işyeri composite bütünlük kuralı gösterilir ama gerçek D05 şeması/backfill/API henüz yoktur.
3. Canonical payload jsonb olarak tam eşitlikle karşılaştırılır. Production allowlist/hash/retention ve payload boyutu politikası ayrı tasarlanacak; hassas domain içeriği receipt/audit'e gelişigüzel konmayacak.
4. Test clock ve retry/lease sayıları ticari/SLO kararı değildir; production worker server clock, backoff, jitter, timeout ve dead-letter recovery ayrıca gerekir.
5. Bir consumer prototipi vardır. Çoklu consumer fan-out, DB dışı e-posta/push/store sağlayıcısının idempotency'si ve reconciliation henüz yoktur. Store ile DB arasında dağıtık atomiklik iddiası yoktur.
6. Dead event aynı aggregate'in sonraki sürümünü bekletir. Review/replay/DLQ admin akışı henüz yoktur; sessiz otomatik atlama uygulanmaz.
7. X09/X10/X11 ve X12 için teknik destek kanıtıdır; bu geçiş kabullerinin RPC/Edge/native/gerçek domain katmanlarının bütünü geçti olarak işaretlenmez. 263 ana kabul hâlâ UNMAPPED.
8. Fonksiyon eşleme kontrolü sadece üç yeni transport dosyasıyla sınırlıdır. Route/RPC/trigger/policy/admin/full native inventory ve gerçek release coverage gate P01'de açık kalır.

## Çalıştırma

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/verify_function_map.mjs
deno test --allow-read=contracts/isg/v1/fixtures supabase/functions/_shared/isg/mutation-context_test.ts
node scripts/isg/run_database_contract.mjs contracts/isg/v1/local-test-environment.example.json
~~~

Swift: `swiftc App/Services/ISG/IsgMutationContext.swift scripts/isg/MutationContextCheck.swift -o <yeni-çıktı>`; sonra executable'a ortak fixture JSON yolu verilir. Android: JDK 17 ile `android/` içinde `./gradlew :core:data:testDebugUnitTest --tests com.riskdetectedan.core.data.isg.IsgMutationContextTest --offline`. Saf Swift testleri app launch veya iki cihaz senkronizasyonu değildir.

Hostless iOS hedefi `tests/isg/ios/ISGContractTests.xcodeproj`, scheme `ISGContractTests`: gerçek iOS Simulator'da 43 ayrı XCTest geçti. Test bundle'ına yalnız production Swift model dosyası, XCTest harness ve aynı JSON fixture girer; ana uygulama target'ı ve SDK paketleri bağımlılık değildir. CI mevcut iPhone simulator envanterinden hedef seçer; simulator bulunmazsa sessiz skip değil fail verir. Sonuç xcresult artifact olarak saklanır. Yerel sonuç [kanıt dosyasındadır](evidence/P01_IOS_NATIVE_CONTRACT_2026-09-12.json); uzak CI henüz çalıştırılmadı.
