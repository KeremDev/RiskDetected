# Security Observations — 2026-07-28

## Private tablolarda RLS uyarısı

Supabase schema advisory, aşağıdaki mevcut tablolarda RLS'nin kapalı olduğunu
bildirdi:

- `private.support_request_rate_limits`
- `private.analysis_job_state`

Etkin yetki kontrolü ayrıca salt-okunur olarak yapıldı.

| Tablo | Rol | Schema USAGE | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `analysis_job_state` | `anon` | Hayır | Hayır | Hayır | Hayır | Hayır |
| `analysis_job_state` | `authenticated` | Hayır | Hayır | Hayır | Hayır | Hayır |
| `analysis_job_state` | `service_role` | Hayır | Evet | Evet | Evet | Evet |
| `support_request_rate_limits` | `anon` | Hayır | Hayır | Hayır | Hayır | Hayır |
| `support_request_rate_limits` | `authenticated` | Hayır | Hayır | Hayır | Hayır | Hayır |
| `support_request_rate_limits` | `service_role` | Hayır | Hayır | Hayır | Hayır | Hayır |

Sonuç:

- `anon` ve `authenticated` için doğrudan istemci erişimi doğrulanmadı.
- Bulguyu “aktif client exposure” değil, savunma katmanı eksikliği olarak
  sınıflandırıyoruz.
- Otomatik `ENABLE ROW LEVEL SECURITY` uygulanmadı. İlgili backend erişim
  yolları ve gerekli service-role politikaları doğrulanmadan RLS açmak iş
  akışını durdurabilir.
- Remediation localization migration'ına karıştırılmamalı; ayrı migration,
  pgTAP ve rollback planıyla ele alınmalıdır.

