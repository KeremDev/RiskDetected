# P01 — gerçek Auth + atomik işlem bileşimi

12 Eylül 2026. **Müşteri verisiz sentetik Auth turu 78/78 PASS:** önceki48 Auth/session kontrolüne30 gerçek-session mutation kontrolü eklendi. Foundation110/110 PASS. Bu yalnız private test şemasında çalışan bir bileşimdir; production API/migration, gerçek billing capability veya mobil domain E2E değildir.

Aynı kaynaklarla regresyon: eski transaction + legacy oracle31 üst seviye kontrol/329 varyasyon PASS, kapasite shadow17 grup/864 kombinasyon PASS, ayrı Auth + Storage + session restore75/75 PASS (588 dosya, kaynak sayımları değişmedi). Sentetik tur19:05:02–19:05:15 UTC; restore19:05:12–19:05:57 UTC. Üç bağımsız test ortamı cleanup PASS. Uygulama kimlikleri ve üç transport kaynağının function map'i PASS.

## İşlem sınırı

```text
Yerel GoTrue login/refresh → yerel HS256 imza/issuer/audience/zaman doğrulama
  → güvenilir test adaptörü: authenticated + doğrulanmış root JWT claim'leri
  → BEGIN
    → require_active_session(): Auth session/user uygunluğu + FOR SHARE
    → sentetik write_capabilities: izin var ve true + FOR SHARE
    → mutate_verified(): eski actor GUC'sini doğrulanmış sub ile sınırla
    → mevcut mutate(): şirket sahibi + input + idempotency + version kilidi
    → counter + audit + outbox + receipt birlikte
  → COMMIT; izin/session/şirket/aggregate kilitleri bırakılır
```

`transaction_fixture.sql` değiştirilmedi, gövdesi kopyalanmadı. Yeni `auth_mutation_fixture.sql` wrapper'ı onu çağırır. İlk prototipteki `isg_fixture_client` test rolüne ait ham `mutate()` fonksiyonu authenticated/anon/service_role için açılmadı. Yeni wrapper'ın authenticated EXECUTE izni dar ve açık; tablo UPDATE izni yok, private tabloların tümünde RLS açık. NOLOGIN/NOBYPASSRLS fixture owner, mevcut transaction şemasının sahibidir. Auth helper'ın dar SECURITY DEFINER'ı session lookup için ayrı kalır.

Yazma izni yalnız **sentetik boolean** fixture'dır: abonelik, gift, indirim, kota, MFA, admin scope veya hesap silme politikası yerine geçmez. user_metadata yetki vermez. İzin veya session kontrolü receipt okumadan önce yapılır; eski başarılı isteğin sonucu, izni alınmış/logged-out çağrıya geri verilmez.

## Yeni 30 kontrol

| Grup | Doğrulanan davranış |
|---|---|
| İzin ve kimlik | Private ACL/RLS; gerçek session ile başarı; sahte eski actor GUC'si yerine doğrulanmış sub; dört tablonun atomik yazımı |
| Tekrar ve scope | Aynı key/payload aynı sonucu verir, yeni yan etki yok; değişmiş payload conflict; eski version conflict; foreign/missing şirket aynı ACCESS_DENIED; cross-company/missing entity aynı ret |
| Session ve izin reddi | Eksik session, expired claim; false/missing izin; user_metadata grant denemesi; geri alınmış izinle hem yeni işlem hem eski receipt reddi |
| Hata atomikliği | Audit ve outbox fault ayrı ayrı tüm counter/receipt/audit/outbox durumunu korur; sonrasında geçerli işlem başarılı |
| Kilit sıralaması | Yetkili transaction açıkken izin revoke UPDATE başka bağlantıda 150ms lock timeout ile bekler; test rollback sonrası durum aynı |
| Eşzamanlılık | 20 aynı retry aynı sonucu alır, tek atomik commit; 20 farklı mutation aynı version ile yarışır, 1 başarı + 19 VERSION_CONFLICT, tek atomik commit |
| Gerçek logout | Hâlâ imzalı/eski JWT yeni write ve eski receipt replay için AUTH_REQUIRED; dört tablonun tüm içeriği değişmez |

Her ret/fault testinde counter, receipt, audit ve outbox'ın deterministik tam JSON snapshot'ı işlem öncesi/sonrası karşılaştırılır; yalnız row count'a güvenilmez. Snapshot ve gerçek JWT/hesap UUID'si public rapora yazılmaz. Bilerek bozulmuş claim negatifleri güvenilir SQL test adaptörüne verilir; bozuk token'ın HTTP gateway'den geçtiği iddia edilmez.

İzin iptali önce tamamlanırsa yeni işlem reddedilir. Zaten izin alıp kilit tutan kısa transaction önce tamamlanabilir; iptal gelecekte başlamış bütün işleri geriye dönük geri almaz. İşlem bekleme süreleri testte sınırlıdır. Gerçek HTTP logout/permission yük testi, deadlock matrisi ve production SLO ayrıca gerekir.

## Çalıştırma, güvenlik ve geri dönüş

```bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --synthetic-session
```

Yeni composition sadece `mode.synthetic` içinde çalışır; helper ayrıca `synthetic === true` olmadan SQL çalıştırmayı reddeder. JWT doğrulaması DDL'den önce gelir. Restore modu bu yeni tabloları/helper'ı yüklemez. Var olan image-digest/run-ID/network-none/port/mount guard'ları ve yalnız kendi container'larını kaldırma mekanizması korunur. Sabit GoTrue/PostgreSQL image'ları değişmedi; SDK yükseltilmedi. Yeni dört offline test bu mod/claim/ACL/wiring sınırlarını korur; statik shape testleri tek başına runtime güvenlik kanıtı sayılmaz.

Bu tur Supabase skill'i uyarınca changelog, sessions ve database functions belgeleri yeniden incelendi. JWT issuer `/auth/v1` açık ayarı korundu; yeni schema/table grant'lerinin otomatik API erişimi sağlaması varsayılmadı. Kalıcı migration oluşturulmadığı için prod advisor veya linked DB yazımı yapılmadı; prototype ACL/RLS kontrolleri disposable DB üzerinde yürütüldü. Production'a taşımadan önce ortam advisor/migration/HTTP güvenlik kapıları ayrıca zorunlu.

Geri dönüş: yalnız yeni test çağrısı/wrapper'ı geri alınabilir; canlı kullanıcı verisi veya API değişmedi. Önceki Android native dilimi `b6dbac70`; baseline `riskdetected-change-point-20260912` korunuyor. [Makine kanıtı](evidence/P01_AUTH_MUTATION_COMPOSITION_2026-09-12.json) kaynak SHA256,78 test, regression ve cleanup sonuçlarını taşır. Uzak CI henüz NOT_RUN; mevcut synthetic job komutu yeni bileşimi çalıştıracak şekilde yerel hazırlanmıştır.

P01 tamamlandı sayılmaz: production gateway/JWKS, gerçek domain/capability, native hata akışları, tam function inventory, error/state-machine ve263 domain acceptance eşlemesi açık.

Kaynaklar: [Supabase session/logout](https://supabase.com/docs/guides/auth/sessions), [database functions/privileges](https://supabase.com/docs/guides/database/functions), [issuer default değişikliği](https://supabase.com/changelog/47093-self-hosted-supabase-api-external-url-to-include-auth-v1), [yeni tablo grant davranışı](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically).
