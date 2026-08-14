# Android staging backend dağıtım kanıtı

Tarih: 10 Ağustos 2026, 19:56 +03  
Supabase proje ref: `qlymhrrlhklcudveknih` (`riskdetected-android-staging`)  
Kaynak branch: `codex/android-release-readiness`  
Dağıtım öncesi kaynak commit: `7d8c64e13f6e61feadd38b34841d00642ffcf594`

Bu dağıtım yalnız Android staging projesine yapıldı. Production projesine migration, function veya configuration yazılmadı.

## Yerel kalite kapısı

- Clean migration replay: geçti.
- pgTAP/RLS/RPC: `478/478`, 21 dosya, geçti.
- Deno Edge Function: `316/316`, 57 dosya, geçti.
- `supabase db lint --local --level warning`: sıfır schema hatası.
- iOS `App/` kaynak diff'i: sıfır.

## Uygulanan additive migration'lar

| Uzak version | Migration | Sonuç |
|---|---|---|
| `20260810165356` | `android_legal_update_policy_pending_approval` | Gate kapalı; gerçek owner/hukuk onayı olmadığı için approval tablosuna satır yazmıyor |
| `20260810165403` | `android_web_account_deletion_queue` | Queue alanları ve fail-safe cron sözleşmesi eklendi |
| `20260810165414` | `consolidate_profiles_rls_policies` | Yalnız authenticated own-row SELECT/INSERT/UPDATE politikaları kaldı |
| `20260810165419` | `restore_localization_trigger_contract` | Platform ve dil doğrulama telemetrisi tek hardened trigger'da birleştirildi |

Uzak doğrulama sonucu:

- `android_legal_policy.enabled=false`
- `private.approved_legal_documents` içinde `tr-android-v1` satır sayısı: `4`; owner approval hash ile 4/4 bağlı, Android gate kapalı.
- Web queue alanları: 7/7 mevcut.
- `riskdetected-account-deletion-hourly` cron sayısı: `0`; staging Vault secret'ları tanımlanana kadar bilinçli olarak planlanmıyor.
- Profil politikaları: `profiles_select_own`, `profiles_insert_own`, `profiles_update_own`.
- Localization trigger: `SECURITY DEFINER`, `search_path=""`, anon/authenticated execute yok, yalnız `service_role` execute var.

## Edge Function kanonik dağıtımı

Repo'daki 20 function `supabase functions deploy --project-ref qlymhrrlhklcudveknih --use-api` ile yeniden dağıtıldı. Tümü `ACTIVE`.

| Function | Version | verify_jwt | Deploy SHA-256 |
|---|---:|---:|---|
| `account-deletion-complete` | 10 | false | `f30505ef3c3ca6132613928fb38a1eb5822f7b1a06be098961e2450b13434942` |
| `analyze` | 12 | false | `4b6a9147ae1470e765dfd63e595f077a35e3a1f90eb9604d9fe6c431e248fd27` |
| `app-release-policy` | 11 | false | `d8981944d3fd2b5bf5a6a1991592e51cdd8653499a9a488e76d61b62f9089d30` |
| `auth-send-email-hook` | 14 | false | `f9a3a964c3049cec7a688a6f5c7140bb745dbefc0de85f55a3e82bcf0a1d6618` |
| `generate-excel-report` | 11 | true | `71b6be219c32dc3869066988e248f7dbe393bdd3f00ac2399ceb32797a1f1649` |
| `manage-notification-automation` | 10 | true | `20495e36efb58ad1c8b614ed645294c31165272dceabba531a25a662ff266b40` |
| `mutate-analysis-finding` | 10 | true | `e97546d6d42ef26daa06ade18d489ac36b354b02c545f143098a488d20eb4472` |
| `process-account-deletion-queue` | 2 | false | `9a4340335e2055e7134dfe15d1c8ddb892eb207e23eeeeb1822d3f5579865dd3` |
| `process-analysis-jobs` | 10 | false | `5783447339c9825c14fc7df915362cf74ae7796ce339013ca321aab14a5cafee` |
| `process-notification-automation` | 11 | false | `fdfae041d2d209e4f493a6f8de13944477909ceaa7c1fa192f79e1bc8f700758` |
| `register-report` | 12 | true | `931a8d5e9408128c1d893d0f723b0f537d25591830d98911cc456aaf12d09ea1` |
| `request-account-deletion` | 10 | true | `43dedba26fa2fbdd6a3cf221f10dd7019d0265aeb3ec6075d0f5cd2633fb8fee` |
| `retention-cleanup` | 10 | false | `72358fc342d3f03353a531440324e1d11372574879a447a503a6acb5f3515100` |
| `revenuecat-webhook` | 12 | false | `1b696c1486a8f2a524bd35da8b459dc20e36d0ad0c90be85da66f3527c36c70f` |
| `send-push-notification` | 11 | false | `39820f9ddc1c7ab48835ea2e5f78cc609d739640bcb8725969c8651910769d72` |
| `send-report-ready-notification` | 11 | true | `89b76c37a4d44393a6f384d05c3c97ac7cda11c60b4494b3009acf2d2abb073c` |
| `send-trial-reminder-notifications` | 11 | false | `14657cc5b8585b8771e71d1d5b0572df6612e47a8d7546dbee0a552af23df1be` |
| `send-welcome-email` | 11 | true | `07912153b4a243e78d3ad294a8e7c0f8b168ee226ceff84f9ac16a2696963e9c` |
| `support-contact` | 11 | true | `d1bcffc3a9a77e5c1e0754de4a6dd8880728613d36251402c969ac4881f3b776` |
| `sync-revenuecat-subscription` | 10 | true | `fa2b9008c4477e191218b4ec251f4f507c483c53cd780e045c8f0a149c899ec8` |

`verify_jwt=false` kullanılan webhook/worker/policy uçları kendi secret, signature veya server-side auth sözleşmesini uygular; yapı repo `supabase/config.toml` ile eşleşir.

## Runtime policy smoke testi

Staging `app-release-policy` build `1` için HTTP 200 döndürdü:

- `android_runtime_gates.schema_version=1`
- `evaluated_version_code=1`
- Altı staging kapısı build allowlist nedeniyle açık; gerçek E2E tamamlandıktan sonra kapatılabilir.
- Android legal policy kapalı, `required=false`, `action=none`.
- Play listing henüz olmadığı için `policy_version=pending-play-listing` ve `app_store_url` boş.

Production'a yalnız okunur smoke çağrısı yapıldı. Production function henüz additive Android alanlarını içermediği için `android_runtime_gates=null` ve `android_legal_policy=null` döndürüyor; production deploy iOS build-81 fixture/smoke kapısından sonra yapılacak.

## Açık dış kapılar

- Staging Vault: `project_url` ve `account_deletion_queue_secret`; ardından saatlik cron doğrulaması.
- Staging Auth: leaked-password protection, auth regresyonundan sonra dashboard'da açılacak.
- Web `/gizlilik` ve `/hesap-silme` yayını.
- Owner nihai onayı ve ayrı additive approval migration'ı 2026-08-11 tarihinde tamamlandı; gate canary'ye kadar kapalı.
- Production additive deploy; iOS fixture/smoke geçmeden uygulanmayacak.
