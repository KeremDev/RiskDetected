# ADR: Localization Context ve Safety Profile Sözleşmesi

- Durum: Accepted for implementation
- Tarih: 2026-07-28
- Kapsam: Global Localization + Country Safety, Wave 1
- Normatif kaynak:
  `docs/specs/RISKDETECTED_GLOBAL_LOCALIZATION_COUNTRY_SAFETY_CODEX_IMPLEMENTATION_PLAN_2026-07-28.md`

## Karar

RiskDetected localization davranışı tek bir `language` veya storefront
değerinden türetilmeyecektir. Aşağıdaki eksenler bağımsız ve typed tutulur:

- uygulama dili;
- içerik/output locale'i;
- kullanıcının açıkça seçtiği çalışma yargı alanı;
- versioned safety profile id/version;
- risk yöntemi;
- legal document set;
- regulatory reference policy.

Safety profile kaynağı `localization/safety-profiles/*.yaml`, terminoloji ve
ortak güvenlik sözleşmesi `localization/glossary/*.yaml` olacaktır. Aynı
source SHA-256 değerinden Swift, TypeScript ve JSON manifest üretilir.

## Yasak çıkarımlar

Safety profile veya çalışma yargı alanı aşağıdakilerden çıkarılamaz:

- App Store storefront;
- IP, GPS, SIM veya cihaz bölgesi;
- Apple ID ülkesi veya ödeme para birimi;
- RevenueCat müşteri bilgisi.

Yeni kullanıcı bu seçimi açıkça yapar. English fallback yalnız aynı dilde
`en-intl-generic-v1` olabilir; English istek Türkçe output'a düşmez.

## Wave 1 profilleri

- `tr-tr-current-v1`
- `en-intl-generic-v1`
- `en-gb-generic-v1`
- `en-us-generic-v1`
- `en-au-generic-v1`
- `en-ca-generic-v1`

English profilleri yalnız terminoloji profilidir. Mevzuat canvas'ı, structured
regulatory reference ve legal compliance claim üretimi kapalıdır. Türkiye
dışı legislation davranışı uzaktan açılabilir bir profile/flag değildir.

## Ortak safety contract

Hierarchy of Controls tek sırada tutulur:

1. elimination;
2. substitution;
3. engineering controls;
4. administrative controls;
5. personal protective equipment (PPE).

Fine-Kinney ve 5×5 için “hukuki standart veya mevzuata uygunluk kanıtı
değildir” açıklaması profile bağımsız ortak metindir. İngilizce yeni
kullanıcıda varsayılan yöntem 5×5; Fine-Kinney seçilebilir advanced
yöntemdir. Mevcut Türkçe davranış korunur.

## Review ve onay

Codex kaynakları `machine_draft`, çıkarılan envanter satırlarını `extracted`
olarak işaretleyebilir. `language_reviewed`, `safety_reviewed`,
`product_approved` ve `shipping` gerçek insan onayı ve approval hash'i
olmadan yazılamaz. Reviewer adı/e-postası repository'ye alınmaz.

## Veri modeli sonucu

PostgreSQL enum yerine additive `text + CHECK + manifest validation`
yaklaşımı kullanılacaktır. Kalıcı `analyses.localization_snapshot` daha
sonraki veri-modeli fazında otorite olur; request veya queue payload profile
uyduramaz. Eski build açık Türkçe/Türkiye varsayılanıyla çalışır.

## Güvenlik ve rollout sonucu

- Profil çözümleme fail-closed olur.
- Non-TR legislation isteği AI/quota/queue öncesi stable code ile reddedilir.
- Profile/language/legal değişiklikleri feature flag ve immutable snapshot
  sözleşmesine uyar.
- Production migration/deploy yalnız ilgili sonraki faz kapıları geçtikten
  sonra yapılır.
