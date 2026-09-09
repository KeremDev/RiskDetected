# Coverage Quality v2 Prompt Review — 2026-08-21

Durum: Release candidate hazır; ürün sahibi prompt incelemesini 21 Ağustos 2026 tarihinde onayladı. Bu belge golden fixture'ı otomatik olarak güncellemez.

## Altı profil golden tabanı

| Profil | Dil dalı | Uzunluk | SHA-256 | Sonuç |
| --- | --- | ---: | --- | --- |
| `tr-tr-current-v1` | `<odak>` / TR | 4482 | `eb4825ad24c19d76a774bbfba2ca7955e6042ef888b586dae5c4e70669fceab4` | Değişmedi |
| `en-intl-generic-v1` | `<focus>` / EN | 4662 | `603e7d353efb304c96d9383c638c49320cc7cd2793dc55c75a51e21449d6c0eb` | Değişmedi |
| `en-gb-generic-v1` | `<focus>` / EN | 4661 | `3c1f9156d84b06cbd0c4697de8e79cb85b0a7f939065782e83d6091aeeb78042` | Değişmedi |
| `en-us-generic-v1` | `<focus>` / EN | 4717 | `acbeea2457710993dd0cd19f45ecd9bbf5b37212b4d6870f6ef2fccf0f53922d` | Değişmedi |
| `en-au-generic-v1` | `<focus>` / EN | 4679 | `d67a8d81f83ed722afea31c9d779ee65c913378d3f5130b70bd1c7f597f38e28` | Değişmedi |
| `en-ca-generic-v1` | `<focus>` / EN | 4727 | `084a684a732adcdf984f6da29e777e21e1bbbb643573469df9fb29d140edf214` | Değişmedi |

`ai-localization-prompt-golden.json` sistem/lokalizasyon sözleşmesini kapsar. Quality v2 metni feature flag etkin olduğunda analiz bağlamına eklenir; shadow modunda prompt ve kullanıcı sonucu değişmez.

## İncelenecek yeni TR davranışı

- `candidate_findings_count`, kategori/katman/sonuç sayısı değil; tekrarlar ayıklandıktan sonraki bağımsız ve düzeltilebilir fiziksel koşul sayısıdır.
- Ayrı görsel kanıt ve ayrı müdahale gerektiren koşullar ayrı bulgu kalır; aynı fiziksel kaynak ve aynı düzeltme birden çok katmanı etkiliyorsa tek bulgu kalabilir.
- Quality repair yalnız eksik ve kanıtlı koşulları döndürür; ilk bulgular ile ilk 12 katman denetimi değişmez otoritedir.
- `not_visible` ve `checked_no_hazard` katmanlarından bulgu üretilemez. Yalnız `uncertain` katmanlara dayanan bulgu saha doğrulaması taşır ve güveni `0.69` ile sınırlıdır.
- Yeni bulgu yoksa yalnız izinli `no_additional_reason_code` enum'u kullanılır; kullanıcı metni sunucudaki TR/EN copy kataloğundan gelir.

## İncelenecek yeni EN davranışı

- The candidate count represents distinct independently correctable physical conditions, not categories, layers, or consequences.
- Conditions with separate visual evidence and separate controls remain separate; one physical source with one correction may stay as one finding across multiple layers.
- Quality repair returns only missing, supported conditions. Existing findings and the initial 12-layer audit remain immutable.
- Findings cannot originate from `not_visible` or `checked_no_hazard`. Uncertain-only findings require field verification and confidence at or below `0.69`.
- An empty repair uses only an allowed reason enum; user-visible wording comes from the server-side TR/EN copy catalog.

## Güvenlik ve bütünlük kontrolü

- [x] TR dalında tam bir `<odak>...</odak>` çifti var.
- [x] EN dalında tam bir `<focus>...</focus>` çifti var.
- [x] Review verisi `serializeUntrustedPromptValue` ile instruction sınırının içinde veri olarak taşınıyor.
- [x] İlk bulgular silinemez, yeniden yazılamaz, başka fotoğrafa taşınamaz veya skor değiştiremez.
- [x] Quality repair ikinci bir language repair/provider fallback başlatamaz.
- [x] Altı mevcut golden hash testi geçti; fixture körlemesine yenilenmedi.
- [x] Ürün sahibi incelemesi: katman kapsamı ve bağımsız bulgu tanımı onaylandı.
- [x] Ürün sahibi incelemesi: TR/EN dil ayrımı ve prompt-injection sınırı onaylandı.

Ürün sahibi onayı bu görevdeki açık yayın talimatıyla tamamlandı. Shadow yayınından sonra allowlist canary ve genel yayın kararları canlı telemetri kapılarıyla verilecektir.
