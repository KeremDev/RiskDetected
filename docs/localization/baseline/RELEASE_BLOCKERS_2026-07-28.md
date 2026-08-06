# Global Localization Release Blockers — 2026-07-28

## Production mutation blocker

### P0 — Migration ledger drift

Yerel/uzak migration defteri `85 matched / 41 local-only / 25 remote-only`
durumundadır. Uzlaştırma yaklaşımı Faz 0'da onaylandı ve bütün farklar
sınıflandırıldı; ancak history metadata'sı production mutation yasağı gereği
değiştirilmedi. Exact canonicalization/attestation kapısı tamamlanmadan yeni
production migration uygulanamaz. Ayrıntı:
`MIGRATION_LEDGER_RECONCILIATION_2026-07-28.md`.

## Release blockers

### P0 — Human review yok

Safety profile ve glossary girdileri `draft` statüsündedir. UK H&S, US
occupational safety, AU WHS ve CA OHS practitioner onayı olmadan shipping
statüsüne geçirilemez.

### P0 — İngilizce legal set yok

Terms/privacy/legal consent içerikleri yalnız Türkçe. `en-global-v1` hukuk
metinleri qualified legal review almadan İngilizce release yapılamaz.

### P0 — Ürün entegrasyonu henüz tamamlanmadı

Faz 0 ve Faz 1 teknik kapıları tamamlandı. Safety profile içeriği insan
onayları alınana kadar `machine_draft` kalır. DB snapshot alanları,
request/queue, AI validators, reports, notification/e-mail, iOS String
Catalog, profile UI, ASO ve screenshot pipeline sonraki fazlar tamamlanmadan
release-ready değildir.

### P1 — Private table RLS defense-in-depth

İki private tabloda RLS kapalı; ancak `anon/authenticated` erişimi yok.
Ayrı güvenlik migration'ı ve test planı gerektirir. Lokalizasyon migration'ına
eklenmeyecektir.

## Yayın durumu

- Yeni App Store sürümü oluşturulmadı.
- Metadata/screenshot/subscription localization yazılmadı.
- Review submission yapılmadı.
- Production release yapılmadı.
