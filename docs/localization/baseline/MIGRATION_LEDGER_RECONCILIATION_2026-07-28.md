# Migration Ledger Reconciliation — 2026-07-28

## Executive result

Production migration history ile repository migration dizini eşleşmiyor:

| Sınıf | Sayı |
| --- | ---: |
| Matched | 85 |
| Local-only | 41 |
| Remote-only | 25 |

Matched 85 sürüm ayrıca exact remote statement ile karşılaştırıldı:

| İçerik sınıfı | Sayı |
| --- | ---: |
| Byte-identical | 21 |
| Yalnız yorum/boşluk farkı | 51 |
| Yalnız statement terminator farkı | 11 |
| Semantic statement farkı | 2 |

Yeni localization migration'ı oluşturulmadı veya uygulanmadı. Özellikle
`supabase db push`, eski migration'ları yanlış sırada çalıştırabileceği ve
güncel feature flag değerlerini geriye götürebileceği için yasaklıdır.

Salt-okunur kanıt seti:

- `MIGRATION_LEDGER_BEFORE_RECONCILIATION_2026-07-28.json`
- `MIGRATION_MATCHED_CONTENT_COMPARISON_2026-07-28.json`
- `REMOTE_MIGRATION_EVIDENCE_MANIFEST_2026-07-28.json`
- `remote-migration-history/` altında 25 remote-only statement ile iki
  semantic-diff statement'ın exact, checksum'lı kopyası

Bu sayıların Faz 0 sonunda sıfırlanması beklenmez. Faz 0 çıkış sözleşmesi
yaklaşımın onaylanmasını, her farkın açıklanmasını ve production mutasyonu
yapılmamasını ister. History repair veya production DDL bu fazın içinde
yapılırsa aynı çıkış sözleşmesi ihlal edilmiş olur.

## Sınıf A — Aynı iş ailesi, farklı timestamp

Aşağıdaki production migration'larının repository'de aynı isimli veya aynı
iş ailesindeki karşılıkları farklı timestamp ile bulunuyor.

| Remote history | Remote name | Yerel aday |
| --- | --- | --- |
| `20260611105834` | `admin_users` | `20260611120000_admin_users.sql` |
| `20260611105836` | `admin_audit_logs` | `20260611120100_admin_audit_logs.sql` |
| `20260611154735` | `admin_saved_filters` | `20260611120300_admin_saved_filters.sql` |
| `20260611155228` | `admin_dashboard_daily_series` | `20260611120400_admin_dashboard_daily_series.sql` |
| `20260611155618` | `model_pricing_catalog` | `20260611120500_model_pricing_catalog.sql` |
| `20260611161445` | `admin_subscription_inconsistency_scan` | `20260611120600_admin_subscription_inconsistency_scan.sql` |
| `20260611170250` | `admin_data_quality_and_notes` | `20260611120700_admin_data_quality_and_notes.sql` |
| `20260611170729` | `admin_alerts` | `20260611120800_admin_alerts.sql` |
| `20260611171231` | `admin_pgmq_queue_metrics` | `20260611120900_admin_pgmq_queue_metrics.sql` |
| `20260611172004` | `admin_user_segmentation_v2` | `20260611121000_admin_user_segmentation.sql` |
| `20260611173529` | `admin_cohort_retention` | `20260611121100_admin_cohort_retention.sql` |
| `20260611174422` | `admin_exports` | `20260611121200_admin_exports.sql` |
| `20260611174722` | `admin_findings_analytics` | `20260611121300_admin_findings_analytics.sql` |
| `20260611175741` | `admin_rate_limit_events` | `20260611121400_admin_rate_limit_events.sql` |
| `20260612191457` | `add_active_analysis_sector` | `20260612120000_add_active_analysis_sector.sql` |
| `20260612224143` | `add_trial_reminder_notifications` | `20260612222601_add_trial_reminder_notifications.sql` |
| `20260613001428` + `20260613001447` | onboarding sector allowlist + RPC | `20260613031500_expand_onboarding_sector_allowlist.sql` |
| `20260615170803` + `20260615171457` | Plus yearly trial backfills | `20260615040000_backfill_plus_yearly_trial_columns.sql` |
| `20260615172300` | `default_trial_will_renew` | `20260615180000_default_trial_will_renew.sql` |

İsim eşleşmesi SQL eşitliği kanıtı değildir. Production
`supabase_migrations.schema_migrations` satırlarında statement hash'leri
alındı; repository dosyaları exact remote statement ile karşılaştırılmadan
rename veya history repair yapılmamalıdır.

## Sınıf B — Remote-only hotfix

Aşağıdaki production migration'larının repository'de exact timestamp ve
exact statement kopyası yok:

| Remote history | Name | Not |
| --- | --- | --- |
| `20260611185911` | `add_gemini_25_flash_lite_pricing` | Pricing hotfix |
| `20260611190306` | `fix_gemini_25_flash_official_pricing` | Pricing correction |
| `20260611193019` | `dashboard_daily_series_istanbul_tz` | Timezone correction |
| `20260611200440` | `admin_recent_sign_ins` | Daha sonraki yerel function revizyonundan farklı |

Bu dört migration remote-first olarak exact statement ile repository'ye
geri alınmalıdır. Yeni birleştirilmiş migration ile geçmiş yeniden
yazılmamalıdır.

## Sınıf C — Local-only, production end-state mevcut veya sonraki state ile örtülmüş

Aşağıdaki 20 migration remote history'de görünmüyor:

1. `20260624194120_account_deletion_nullable_audit_user_refs.sql`
2. `20260625052249_subscription_test_overrides.sql`
3. `20260625105240_allow_multi_photo_build_67.sql`
4. `20260625111151_grant_authenticated_analyses_write.sql`
5. `20260625112128_allow_multi_photo_build_68.sql`
6. `20260625122643_allow_multi_photo_build_69.sql`
7. `20260625141400_allow_multi_photo_build_70.sql`
8. `20260625212844_allow_multi_photo_build_72.sql`
9. `20260626183000_admin_recent_sign_ins_use_activity.sql`
10. `20260626190000_admin_data_quality_multi_photo_edit.sql`
11. `20260628203000_ios_release_policy_build_72_appstore.sql`
12. `20260628203155_allow_multi_photo_build_73.sql`
13. `20260630115105_analysis_prompt_limit_integration.sql`
14. `20260630163000_allow_multi_photo_build_74.sql`
15. `20260630170000_hobby_multi_photo_runtime_guard.sql`
16. `20260630172000_paid_multi_photo_limit_three.sql`
17. `20260630184719_allow_multi_photo_build_75.sql`
18. `20260708133746_allow_multi_photo_build_76.sql`
19. `20260710104500_reduce_photo_coverage_minimum.sql`
20. `20260712193000_enable_single_photo_layer_audit.sql`

Salt-okunur production kanıtı:

- Account-deletion audit FK'leri `ON DELETE SET NULL`; actor alanı nullable.
- `subscription_test_overrides` tablosu mevcut.
- `authenticated`, `analyses` için güncel yazma sözleşmesine sahip.
- `multi_photo_analysis.enabled_ios_builds`, 63–77 build'lerini içeriyor.
- Güncel paid photo limiti `3`.
- Coverage minimumu `1`.
- Single-photo layer audit ve compact schema açık.
- Release policy build 77 state'iyle sonraki migration tarafından
  güncellenmiş.
- İlgili admin function'ları production'da mevcut.

Bu kanıtlar güncel son-state'in uyumlu olduğunu gösterir; tek tek eski
migration'ların gerçekten history dışında çalıştırıldığını ispatlamaz.
Özellikle state-only flag migration'ları sonradan başka migration'lar
tarafından örtülmüş olabilir. Audit/provenance doğrulanmadan otomatik
`migration repair --status applied` yapılmamalıdır.

## Sınıf D — Local-only ve production'da eksik

### `20260612195822_add_analysis_sector_constraints.sql`

Production `analyses.analysis_sector` alanı var, fakat local migration'ın
eklemek istediği `analyses_analysis_sector_check` veya eşdeğer bir CHECK
constraint production'da yok.

Bu migration uygulanmış olarak işaretlenemez. Ledger uzlaştırıldıktan sonra
eski timestamp'i çalıştırmak yerine güncel head sonrasında yeni, forward-only
ve güvenli bir migration hazırlanmalıdır:

1. Geçersiz değerleri aggregate olarak ölç.
2. İzin verilen değerleri code/backend allowlist ile doğrula.
3. Constraint'i `NOT VALID` ekle.
4. Backfill/temizliği bounded batch ile tamamla.
5. Constraint'i validate et.
6. pgTAP ve eski build compatibility testlerini çalıştır.

## Diğer local-only kayıt

`20260611120200_admin_seed_owner.sql` için production'da admin kullanıcı
durumunun mevcut olması, seed migration'ın exact çalıştığını ispatlamaz.
Dosya PII içerdiği için rapora değer alınmadı. Aggregate varlık kanıtı ve
owner onayıyla ayrı sınıflandırılmalıdır.

## Sınıf E — Aynı timestamp altında semantic statement farkı

### `20260622195418_multi_photo_editable_findings.sql`

Remote statement historical iOS release policy'yi build 63 seviyesinde
yazarken yerel dosya 64–66 build allowlist'i ve build 66 policy'si içeriyor.
Bu exact-history eşitliği değildir. Canlı son durumda `ios_release_policy`
build 77'dir; `multi_photo_analysis.enabled_ios_builds` 63–77'yi içerir.
Dolayısıyla fark sonraki migration'larla superseded durumdadır, fakat yerel
dosya remote statement'ın exact kopyası sayılmayacaktır.

### `20260714170000_enable_single_photo_compact_layer_quality.sql`

Remote fetch statement'ı yalnız terminatörden oluşuyor; yerel dosya iki
single-photo feature flag'ini `true` yapıyor. Canlı son durumda
`single_photo_compact_layer_schema_enabled=true` ve
`single_photo_evidence_guard_enabled=true` doğrulandı. Son state uyumlu olsa
da provenance eşitliği kanıtlanmış değildir; bu sürüm için history repair
yapılmayacaktır.

## Onaylanan uzlaştırma prosedürü

1. Production schema-only ve `supabase_migrations` yedeğini sakla.
2. 25 remote-only kaydın exact statement'larını güvenli artefakta çıkar.
3. Sınıf A dosyalarını statement bazında karşılaştır:
   - exact ise remote timestamp'i canonical kabul et;
   - farklı ise semantic diff ve object-level diff üret.
4. Sınıf B exact remote dosyalarını repository'ye geri al.
5. Local semantic duplicate dosyaları aktif migration yolundan çıkarırken
   ayrı archive/checksum tut.
6. Sınıf C için Management API/audit kayıtlarıyla uygulama provenance'ını
   doğrula. Kanıt yoksa owner-approved state attestation olmadan history
   repair yapma.
7. Sınıf D constraint'i yeni forward migration olarak planla.
8. Canonical migration yolu değiştirildikten sonra izole boş DB'de
   `supabase db reset` ve pgTAP çalıştır.
9. Faz 2 production migration kapısından önce `supabase migration list
   --linked` sonucunu yeniden al; açıklanmamış yeni fark varsa DDL uygulama.
10. History repair komutlarını ayrı bir değişiklik setinde, exact version
    listesi ve rollback/restore kanıtıyla kullanıcı onayına sun.

## Onay kapısı

Onaylanan karar: **remote history authoritative + exact statement
reconstruction + kanıtlı local-only state attestation**.

Kullanıcının execution planını eksiksiz ve faz sırasına uyarak uygulama
talimatı bu plandaki remote-first uzlaştırma yaklaşımını operasyonel karar
olarak onaylar. Bu onay production mutation onayı değildir. History metadata
repair ve production schema değişikliği Faz 0'da yapılmayacak; exact komut
listesi ve geri dönüş kanıtı hazırlanıp ilgili sonraki kapıda ayrıca
sunulacaktır.

## Faz 0 sonucu

- 41 local-only kaydın tamamı Sınıf A/C/D veya PII seed kaydı olarak
  sınıflandırıldı.
- 25 remote-only kaydın tamamı Sınıf A/B olarak sınıflandırıldı ve exact
  statement kopyaları checksum'la arşivlendi.
- 85 matched sürümün tamamı karşılaştırıldı; 83 lexical/byte-equivalent, iki
  semantic fark Sınıf E olarak açıklandı.
- Canlı/yerel migration farklarında sınıflandırılmamış kayıt kalmadı.
- Production DDL, DML, migration history repair veya deploy yapılmadı.
