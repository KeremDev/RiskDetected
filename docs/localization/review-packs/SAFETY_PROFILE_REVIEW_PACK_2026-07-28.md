# Safety Profile Human Review Pack — 2026-07-28

## Durum

- Kaynak SHA-256:
  `3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932`
- Review durumu: `machine_draft`
- Language approval hash: yok
- Safety approval hash: yok
- Product approval hash: yok
- Shipping yetkisi: yok

Bu paket insan review girdisi içindir. Reviewer adı, e-posta adresi veya başka
kişisel veri repository'ye yazılmayacaktır; onay alınırsa yalnız internal
review ID ve approved source hash kaydedilecektir.

## Ortak sözleşme

Hierarchy of Controls:

1. Elimination
2. Substitution
3. Engineering controls
4. Administrative controls
5. Personal protective equipment (PPE)

Ortak risk yöntemi açıklaması:

> Fine-Kinney and 5×5 are product methods for prioritising risk; they are not
> legal standards or evidence of regulatory compliance.

İncelenecek kararlar:

- Açıklama hukuki uygunluk/certification iddiasını yeterince dışlıyor mu?
- Fine-Kinney ve 5×5 band adları hedef locale için anlaşılır mı?
- PPE'nin otomatik ilk öneri olmaması yeterince açık mı?

## Profil matrisi

| Profile | Locale | Ana domain/ürün terimi | Varsayılan yöntem | Mevzuat / structured refs | Review ihtiyacı |
| --- | --- | --- | --- | --- | --- |
| `tr-tr-current-v1` | `tr-TR` | iş sağlığı ve güvenliği / iş güvenliği risk analizi | Fine-Kinney | mevcut TR davranışı | Türkçe ürün + İSG |
| `en-intl-generic-v1` | `en-001` | workplace safety / safety inspection | 5×5 | kapalı | native technical English + safety |
| `en-gb-generic-v1` | `en-GB` | health and safety / risk assessment | 5×5 | kapalı | UK editor + UK H&S practitioner |
| `en-us-generic-v1` | `en-US` | occupational safety and health / safety inspection | 5×5 | kapalı | US editor + US OSH practitioner |
| `en-au-generic-v1` | `en-AU` | work health and safety / WHS inspection | 5×5 | kapalı | AU editor + AU WHS practitioner |
| `en-ca-generic-v1` | `en-CA` | occupational health and safety / OHS inspection | 5×5 | kapalı | CA editor + CA OHS practitioner |

## Profile özgü safety soruları

### International

- Regülatör adı ve ülkeye özgü hukuk terimi tamamen dışarıda mı?
- “on-site verification” dili fotoğraftan kesin sonuç iddiasını engelliyor mu?
- `global compliance` yasağı yeterli mi?

### United Kingdom

- HSE ile HSENI ayrımını ima eden yanlış genelleme var mı?
- `reasonably practicable` generic output'ta hukuki yük taşımadan kaçınılıyor
  mu?
- British spelling ve `control measure` kullanımı doğal mı?

### United States

- Fotoğraf analizi JHA/JSA olarak adlandırılmıyor mu?
- Federal OSHA ile State Plan farkları nedeniyle compliance/violation iddiası
  dışarıda mı?
- `hazard assessment`, `corrective action`, `prioritize` kullanımı doğal mı?

### Australia

- Model WHS laws tek ulusal hukuk profili gibi sunulmuyor mu?
- Victoria ve state/territory farklarına rağmen `WHS compliant` iddiası
  dışarıda mı?
- `prioritise`, `organised`, `control measure` kullanımı doğal mı?

### Canada

- Federal, provincial ve territorial toplam 14 jurisdiction tek rejim gibi
  sunulmuyor mu?
- `Canadian compliance` / `Canada-wide OHS compliant` iddiası dışarıda mı?
- Canadian English terminolojisi doğal mı?

## Onay çıktısı sözleşmesi

Her reviewer değişiklikleri YAML/CSV diff olarak döndürür. Kabul edilen
değişikliklerden sonra yeni source SHA üretilir. `language_reviewed`,
`safety_reviewed` veya `product_approved` durumu yalnız ilgili approval hash
ve internal review ID mevcutsa yükseltilir. Bu kanıtlar yokken ASC review
submission ve shipping engellenir.
