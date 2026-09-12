# Mutation context v1

Durum: additive, offline sözleşme; hiçbir endpoint'e veya feature flag'e bağlanmadı.

Alanlar: schema_version=1; operation_id ve client_mutation_id canonical lowercase UUID; platform ios/android; client_build 1..2147483647; expected_version 0..9007199254740991; scope.

scope, ya {kind: personal} ya da {kind: company, company_id: UUID, workplace_id?: UUID}. Kişisel kapsamda şirket/işyeri/personel alanı bulunamaz. Bütün seviyelerde bilinmeyen alanlar reddedilir; opsiyonel workplace_id varsa null değil UUID olmalıdır. UUID sürümleri 1..8, RFC variant 8/9/a/b kabul edilir. Client UUID oluştururken lowercase kullanır. Numeric string/boolean tamsayı yerine kabul edilmez.

Bu yalnız taşıma bağlamının doğrulanmasıdır; Authentication, RLS, capability, resource ownership, create/update expected-version anlamı, payload ve idempotency transaction doğrulaması domain handler'da ayrıca yapılacaktır. İstemciden user_id veya role alınmaz. Payload bu şemaya dahil değildir; her feature için ayrı, strict şema gerekir. Geçerli context tek başına yazma yetkisi sağlamaz.

operation_id aynı mantıksal işlemin izidir; client_mutation_id retry boyunca aynı kalır. Yeni key üretip timeout'u tekrar çalıştırmak yerine operation reconciliation gerekir. expected_version=0 yalnız yeni entity akışında kullanılabilir; var olan entity handler'ı bunu reddetmelidir. Bu kural henüz bir DB endpoint'i tarafından uygulanmış değildir.

Ortak fixture: fixtures/mutation-context.json. Deno, Swift ve Kotlin bu aynı corpus'u test eder. Test sonucu metadata, metin veya ham kullanıcı içeriği içermez.
