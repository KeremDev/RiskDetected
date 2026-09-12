# P01 — gerçek Auth oturumuyla freshness prototipi

12 Eylül 2026. Yeni kritik write işlemlerinden önce kullanılacak oturum kontrolünün **izole SQL adayı** hazır. Production migration, Edge/RPC bağlantısı veya mevcut login/purchase/analiz davranışı değişikliği değildir. Test şeması yalnız yeni disposable restore kopyasında oluşturulup konteynerle birlikte kaldırılır.

## Doğrulanan güvenlik sınırı

Supabase logout refresh oturumunu sonlandırır; daha önce alınan access JWT'nin kriptografik imzasını tek başına bozmaz. Bu yüzden kritik yeni mutation akışında yalnız JWT parse etmek veya imza doğrulamak yeterli değildir. Aday kontrol şu ayrımı uygular:

~~~text
Gateway: imza + issuer + audience + token süresi
  → aynı transaction içinde require_active_session()
    → root sub + session_id + authenticated role + exp
    → auth.sessions.id ve user_id eşleşmesi; not_after geçerli
    → Auth user silinmemiş / ban aktif değil / anonim değil
    → session + user FOR SHARE kilidi
  → owner / capability / deletion / MFA kontrolü [henüz bağlı değil]
  → domain + audit + receipt + outbox [henüz bağlı değil]
  → COMMIT / ROLLBACK; kilit bırakılır
~~~

SQL güvenilir gateway'in set ettiği claim'leri varsayar; imza doğrulamaz. Kendi `request.jwt.claims` GUC'sini değiştirebilen doğrudan SQL istemcisi bu sınırın yerine geçmez. İzole provada gerçek GoTrue login/refresh JWT'si alındı, **yerel-only** HS256 doğrulayıcı ile imza/issuer/audience/zaman kontrolünden geçirildi ve yalnız bundan sonra SQL'e aktarıldı. Bu küçük test doğrulayıcısı production JWKS/rotation adaptörü değildir.

## Testler

Oturum dilimi **33 kontrol**: Auth temel17 ile **50/50** ayrı servis turu geçti. Genişletilmiş Auth + Storage + session turu **75/75 PASS**, 18:30:41–18:31:24 UTC; [makine kanıtı ve kaynak hash'leri](evidence/P01_AUTH_SESSION_GUARD_2026-09-12.json). Offline foundation **98/98**: yeni18 yerel JWT ve açık mod/argüman testi.

| Senaryo | Sonuç |
|---|---|
| Gerçek yerel login/refresh JWT → SQL guard | ALLOW |
| Boş/array/missing claim, bozuk/eksik session veya actor | DENY |
| Mevcut session + farklı actor; bilinmeyen session | DENY |
| anon/service role; bozuk/eksik/string/fractional/expired exp | DENY |
| user_metadata içinden actor/session/rol uydurma | Yetki kaynağı sayılmadı |
| DB session.not_after geçmiş / gelecek | DENY / ALLOW |
| Ban / deleted_at / anonymous user | DENY |
| Synthetic user alanlarını geri alma | ALLOW |
| Private helper ACL | anon/service EXECUTE yok; authenticated dar helper erişimi |
| Guard transaction kilidi alınmışken session DELETE ve user ban UPDATE | İki ayrı bağlantıda lock timeout ile BLOCKED |
| Kilitli transaction bitişi; test revocation'ları rollback | Session korunuyor / ALLOW |
| Gerçek GoTrue logout | Auth session satırı kaldırıldı; refresh reddedildi |
| Logout sonrası eski JWT | İmza/süre hâlâ geçerli, SQL guard DENY |

Eşzamanlılık deneyi gerçek PostgreSQL row lock kullanır: 2 saniyelik açık transaction sırasında revocation SQL'leri 150 ms lock timeout ile reddedilir ve rollback edilir. Bu deney eşzamanlı GoTrue HTTP logout yük testi değildir. Önce yetkilendirilmiş kısa transaction bitene kadar sonradan gelen logout/ban bekleyebilir; “logout gelecekte/halen sürmekte olan her işi anında iptal eder” iddiası yoktur. Sonrasında tamamlanmış gerçek logout'un yeni guard isteğini reddettiği ayrıca doğrulandı.

## Uygulama ve güvenlik ayrıntıları

- `scripts/isg/sql/auth_session_fixture.sql`: yalnız test şeması `isg_session_fixture`, sabit `search_path=pg_catalog`, Auth tablo adları tam nitelikli; default PUBLIC EXECUTE açık bırakılmaz. Dar SECURITY DEFINER yalnız Auth session/user okuması ve kilitlemesi yapar.
- `observe_guard` sadece test sonucu ALLOW/DENY yakalayan SECURITY INVOKER sarmalayıcıdır; client API olarak dağıtılmayacak.
- `scripts/isg/auth_session_probe.mjs`: sentetik yeni hesap dışında Auth satırı değiştirmez. SQL testleri yalnız yeni run-ID/digest'i doğrulanan restore DB'sine gider. Tokens/UUID/parola/kişisel satırlar public rapora yazılmaz.
- `scripts/isg/restore_mode.mjs`: ilk açık `--isolated-copy` zorunlu; Storage ve session guard ayrı opt-in. Bilinmeyen/tekrar argüman veya hedef parametresi Docker/Keychain/dosya işlemlerinden önce reddedilir.
- İlk iki geliştirme turunda JWT doğrulaması issuer uyuşmazlığında durdu. Kontrol gevşetilmedi; yerel GoTrue için `GOTRUE_JWT_ISSUER=http://127.0.0.1:9999/auth/v1` açık ayarlandı. API_EXTERNAL_URL tek başına beklenen issuer kanıtı sayılmadı. Canlı issuer ayarı değiştirilmedi.

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --isolated-copy --with-session-guard
node scripts/isg/run_auth_restore.mjs --isolated-copy --with-storage --with-session-guard
~~~

## Production'a geçmeden açık kalanlar

1. Gerçek gateway/JWKS/issuer rotation, expired-token HTTP reddi, native client hata/yeniden giriş deneyimi ve eski binary paritesi.
2. Gerçek domain mutation ile **aynı transaction** entegrasyonu, owner/capability/paid erişim, pending account deletion, admin scope/MFA ve audit/outbox birlikte atomiklik. Guard'ı ayrı RPC'de çağırıp sonraki istekte write yapmak yeterli değildir.
3. Auth global inactivity/single-session/timebox ayarlarının okuma ve yürütme politikası. `not_after` ve session varlığı bütün global politikaların anında uygulandığı anlamına gelmez.
4. Kilit yükü, lock ordering/deadlock/timeout ve servis hata eşlemesi; yalnız iki revocation türünün dar ordering deneyi vardır.
5. Yeni SQL sonradan aşağıdaki bağımsız sentetik Auth CI job'una bağlandı; uzak CI yürütümü hâlâ NOT_RUN. Gerçek müşteri yedeği CI'a taşınmayacak.

263 ana kabul hâlâ UNMAPPED; bu prototip P01/P02 güvenlik kanıtını artırır, domain kapsamını tamamlanmış saymaz.

Kaynaklar: [Supabase session_id/logout semantiği](https://supabase.com/docs/guides/auth/sessions), [GoTrue v2.195.0 JWT configuration](https://github.com/supabase/auth/blob/v2.195.0/internal/conf/configuration.go), [PostgreSQL row locking](https://www.postgresql.org/docs/17/explicit-locking.html).

## Sonraki dilim — müşteri verisiz CI

`node scripts/isg/run_auth_restore.mjs --synthetic-session` artık ayrı bir test yoludur. Backup klasörü, ana restore DB, Storage dosyaları veya Keychain okunmaz; source erişim fonksiyonu bu modda ayrıca reddeder. Hedefler `isg_test_auth_session_db/auth/client`, yalnız yeni run'a ait; restore hedefleriyle çakışmaz. `--with-storage` veya `--isolated-copy` ile birleştirilmesi daha çalışmaya başlamadan reddedilir.

Sıfırdan açılan sabit PostgreSQL imajında Auth bootstrap şeması vardır, kullanıcı sayısı0'dır; public profil tablosu yoktur. GoTrue kalan migration'larını uygulayıp Auth77 ledger'a ulaşır. Yalnız bir sentetik hesap oluşturulur. Production profil trigger/backup/Storage kontrolleri bu modda çalıştırılmış sayılmaz. Auth + SQL session dilimi **48/48 PASS**, 18:39:02–18:39:10 UTC. Aynı kaynakla ayrı gerçek restore regresyonu **75/75 PASS**, 18:38:50–18:39:33 UTC. İki farklı isimli ortamın paralel çalışması da birbirine dokunmadan tamamlandı; her ikisi kendi konteynerlerini kaldırdı.

Foundation **101/101**. Ek kontroller: Docker classic/containerd gerçek image ID çözümlemesi; sentetik modun backup yolu açamaması; CI'ın yalnız sentetik komutu ve yalnız REPORT.json artifact'ını kullanması. Registry index ile container Image ID'nin aynı olması varsayımı kaldırıldı: onaylı RepoDigest doğrulanır, gerçek kurulu image ID'si çözülür ve container bununla karşılaştırılır. Üç sabit image'ın registry manifest'lerinde Linux amd64/arm64 bulunması salt okunur doğrulandı; yerel çalışma arm64 kanıtıdır, x64 runtime henüz koşmadı.

`.github/workflows/isg-foundation.yml` içindeki `auth-session-prototype` job'u Node24/Ubuntu24, üç digest-pinned image ve 8 dakika sınırı kullanır. Image pull hazırlığı dışında servisler network-none namespace'inde; host port/mount yok. Workflow YAML parse ve job-boundary testi geçti. Push/deploy veya uzak job çalıştırma yapılmadı; henüz uzak yeşil CI iddiası yok.

[Sentetik CI hazırlığı, restore regresyonu ve kaynak hash'leri](evidence/P01_SYNTHETIC_AUTH_CI_2026-09-12.json).
