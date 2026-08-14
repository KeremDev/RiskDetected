# Safety profile source of truth

Bu klasördeki `.yaml` dosyaları YAML 1.2'nin JSON uyumlu alt kümesiyle
yazılır. Böylece profil kaynağı insan tarafından okunabilir kalırken codegen
yerel veya CI ortamında ek paket indirmeden deterministik çalışır.

Kurallar:

- Profil kimliği yayımlandıktan sonra değiştirilmez; yeni davranış yeni sürüm
  kimliğiyle eklenir.
- Storefront, cihaz bölgesi, IP, GPS, SIM veya ödeme ülkesi profil seçmez.
- `terminology_only` profilleri hukukî uygunluk veya mevzuat kapsamı iddia
  etmez.
- `manifest.yaml` sıra ve desteklenen tiplerin tek kaynağıdır.
- Swift ve TypeScript dosyaları elle düzenlenmez; `make localization-codegen`
  ile üretilir.
- `localization/generated/safety-profiles.manifest.json`, Swift ve
  TypeScript çıktıları aynı source SHA-256 değerini taşır.
- Hierarchy of Controls ile Fine-Kinney/5×5 hukuki-standart açıklaması
  profile bağımsız olarak `glossary/core.yaml` kaynağından üretilir.
- `review_status: machine_draft`, insan language/safety/product onayı
  anlamına gelmez.
