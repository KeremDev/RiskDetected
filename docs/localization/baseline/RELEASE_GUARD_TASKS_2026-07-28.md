# Localization Release Guard Tasks — 2026-07-28

Release guard aşağıdaki kontroller tamamlanmadan İngilizce build'i
`release-ready` kabul etmemelidir.

## Repository ve generated contract

- Normatif plan checksum'ı doğrulansın.
- Safety profile YAML/schema/manifest validasyonu geçsin.
- Swift ve TypeScript generated dosyaları güncel ve byte-identical mirror
  olsun.
- Profile ID/version değişiklikleri immutable-history kuralını ihlal etmesin.
- Migration ledger `local-only=0`, `remote-only=0` olsun.

## Localization kalite kapıları

- Yeni hard-coded kullanıcı metni bulunmasın.
- String Catalog stale/orphan key raporu sıfır veya açıklanmış allowlist olsun.
- Placeholder, plural ve format specifier parity doğrulansın.
- English sistem-owned yüzeylerde beklenmeyen Türkçe token bulunmasın.
- Turkish yüzeylerde beklenmeyen English leakage bulunmasın.
- `en-* → tr` runtime fallback'i statik ve dinamik testte yasaklansın.
- Country-specific variant yalnız glossary farkı varsa kullanılsın.

## Safety ve AI

- Forbidden claim sözlüğü prompt, AI fixture, rapor, push/e-mail, ASO ve
  screenshot copy üzerinde taransın.
- Non-TR profile için legislation canvas ve structured law reference
  capability'si kapalı olsun.
- Non-TR legislation request backend'de quota/queue öncesi stable code ile
  reddedilsin.
- Profile/language/legal validator ve en fazla bir repair attempt doğrulansın.
- Repair aynı provider route'u kullansın ve ikinci logical quota tüketmesin.
- User-owned quote/sign metni ile system-owned copy ayrımı test edilsin.

## Secret, PII ve telemetry

- Repository output'larında API key, bearer token, service-role key,
  provider prompt body veya signed URL bulunmasın.
- Localization telemetry low-cardinality allowlist dışına çıkmasın.
- Free-form bölge, e-mail, telefon, tam isim veya kullanıcı içeriği analytics
  alanına yazılmasın.
- AI/raw report içeriği release artefaktına veya log snapshot'ına alınmasın.

## Store ve görsel

- ASC discovery ile exact intended diff üretilsin.
- Metadata teknik limitleri ve forbidden claim taraması geçsin.
- Screenshot manifest, pixel dimension, locale ve mevzuat görünürlüğü
  doğrulansın.
- Subscription/group localization read-after-write doğrulansın.
- Version `AFTER_APPROVAL` kalsın.
- Review submission yalnız explicit owner flag ile mümkün olsun.
- Human language/safety/legal approval hash'leri olmadan submit engellensin.

