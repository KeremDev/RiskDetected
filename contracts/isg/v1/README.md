# ISG v1 — ilk güvenlik ve test altyapısı

Bu ilk dilim production feature açmaz ve mevcut API sözleşmesini değiştirmez.

- mutation-context.md / mutation-context.schema.json: actor yetkisi vermeyen, strict ortak taşıma bağlamı. Yeni Deno/Swift/Kotlin parser'ları aynı sentetik corpus'u kullanır; hiçbir canlı endpoint'e bağlı değildir.
- [mutation-outcome.md](mutation-outcome.md): committed/pending/indeterminate/rejected yanıtları ve altı durumlu saf istemci reducer'ı; üç platformda221 yanıt +84 geçiş, henüz API/UI coordinator'a bağlı değil.

- safety-policy.json: mevcut teknik kimlikler, kaynak hash'i ve bağımsız local test hedefleri. Staging allowlist şu an boş; herhangi bir staging/prod/store isteği kapalıdır.
- local-test-environment.example.json: yalnız synthetic/mock/sink ortam bildirimi. Dosyanın doğrulanması çalışan veya güvenli bir backend bulunduğu anlamına gelmez.
- scripts/isg/verify_environment.mjs: manifest'i fail-closed doğrular. DB runner, gerçek Docker inspection'ını da validateContainerInspection ile doğrulamak zorundadır. Normal bridge veya mevcut local stack izolasyon sayılmaz.
- scripts/isg/verify_identity.mjs: kaynak kimlik regresyonunu yakalar. Signed binary/store/Keychain continuity kanıtı değildir.
- scripts/isg/build_test_manifest.mjs: 203 kaynak + 60 geçiş senaryosunu orijinal bölüm/ID ile kayıpsız envanterler. Hiçbirini test edilmiş saymaz.
- scripts/isg/verify_backup.mjs: mevcut checkpoint'i read-only hash/arşiv/COPY metadata bakımından kontrol eder; restore çalıştırmaz, satır içeriği yazdırmaz.
- function-test-map.json / scripts/isg/verify_function_map.mjs: altı context/outcome transport kaynağının fingerprint + corpus + harness bağı; tüm uygulama AST/coverage iddiası değildir.
- scripts/isg/run_database_contract.mjs: yalnız yeni, no-network, synthetic PostgreSQL container'ında 30 transaction/concurrency/crash testi. Migration/API deploy etmez. Ayrıntılar docs/isg/P01_TRANSACTION_PROTOTYPE.md.
- scripts/isg/run_android_contract.mjs: açıkça seçilmiş, yalnız ayrılmış test AVD'sinde 43 ortak fixture + 1 izolasyon kontrolü; SDK'sız/no-network test APK, hash kontrollü kurulum/cleanup. API26/33/37 kanıtı docs/isg/P01_ANDROID_NATIVE_CONTRACT.md içinde; uygulama E2E değildir.

Mevcut komutlar:

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/verify_identity.mjs
node scripts/isg/verify_environment.mjs contracts/isg/v1/local-test-environment.example.json
node scripts/isg/build_test_manifest.mjs
node scripts/isg/verify_backup.mjs
node scripts/isg/verify_function_map.mjs
node scripts/isg/run_database_contract.mjs contracts/isg/v1/local-test-environment.example.json
~~~

263 kabul senaryosunun gerçek domain testleri henüz eşlenmedi. Bu altyapının yeşil olması uygulamanın İSG dönüşümü tamamlandı demek değildir. Migration/API/native domain geliştirmesi P00 restore ve karar kapılarına bağlıdır. Canlı sırlar veya kullanıcı verisi bu dizine girmez.
