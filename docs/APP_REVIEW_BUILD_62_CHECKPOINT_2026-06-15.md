# App Review Build 62 Checkpoint

## Summary

RiskDetected iOS version `1.1.1` build `62`, `2026-06-15` tarihinde App Review'e gonderildi.

Bu kayit, App Store'da yayinda olan `1.1 (61)` surumunden sonra hazirlanan Apple Ads/RevenueCat attribution olcumleme, ASO/Apple Ads hazirlik dokumanlari ve kucuk build guncellemesi icin submission checkpoint notudur.

## Submission Details

- Submission date: `2026-06-15`
- Submission time: `22:38 Europe/Istanbul` civari
- Marketing version: `1.1.1`
- Submitted build: `62`
- Bundle identifier: `com.riskdetected.app`
- App Review status after user action: `Submitted to App Review`
- Active local branch at submission time: `codex/worktree-cleanup`
- Source checkpoint commit: `2db3b31823277aa78eec7df6f81bfbe1c2faf09f`
- Local restore tag: `app-review-build-62-2026-06-15`
- Restore ref target: `2db3b31823277aa78eec7df6f81bfbe1c2faf09f`

## Primary Review Context

Bu gonderimin ana teknik degisikligi RevenueCat uzerinden Apple Ads AdServices attribution token collection eklenmesidir. Uygulama ATT istemez, IDFA'ya erismez ve AdSupport.framework kullanmaz.

App Review Notes icin kullanilan kisa aciklama:

```text
RevenueCat is used for subscription entitlement management and Apple Ads measurement via Apple AdServices. The app does not request App Tracking Transparency permission, access IDFA, or use AdSupport.framework.
```

App Store "What's New" metni icin onerilen kisa not:

```text
Bu surumde abonelik deneyimi, performans ve genel kararlilik icin altyapi iyilestirmeleri yaptik.
```

## Included Change Areas

- Version `1.1.1`, build `62` olarak arttirildi.
- RevenueCat configure sonrasinda Apple AdServices attribution token collection etkinlestirildi.
- RevenueCat login sonrasi Supabase UUID app user id gecisinde attribution helper tekrar tetiklenir hale getirildi.
- Apple Ads / RevenueCat attribution runbook ve preflight script'i eklendi.
- Ilk Apple Ads kampanya ve Sonar keyword research dokumanlari eklendi.
- Snapshot preview test dosyasi kaldirildi.

## Verification

Local statik preflight:

```text
node scripts/apple_ads_attribution_preflight.mjs
Summary: 15 pass, 0 fail, 2 manual gate(s).
```

XcodeBuildMCP simulator build:

```text
Scheme: RiskDetected
Configuration: Debug
Simulator: iPhone 17, iOS 26.5
Status: SUCCEEDED
Build log: /Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/build_sim_2026-06-15T17-39-32-522Z_pid92261_c8477038.log
```

Manual gates:

- RevenueCat dashboard `Apple AdServices` integration was checked on 2026-06-15 and showed Active / Basic Done / Advanced Done.
- Live RevenueCat Charts attribution validation requires App Store release plus a real low-budget Apple Ads campaign.

## Restore Notes

Bu dosya submission sonrasinda olusturulmus referans kaydidir. App Review'e gonderilen kaynak durumuna donmek icin:

```bash
cd /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected
git switch --detach app-review-build-62-2026-06-15
```

Veya build 62 kaynak noktasindan yeni bir fix branch acmak icin:

```bash
git switch -c codex/fix-from-app-review-build-62 app-review-build-62-2026-06-15
```

## Notes

- App Store Connect metadata ve App Review submission islemi ASC arayuzunde manuel yapildi.
- P1 custom Supabase Apple Ads attribution backend bu build'e eklenmedi; RevenueCat attribution kirilimi yetersiz kalirsa ayrica planlanacak.
- Canli kampanya olcum dogrulanmadan Apple Ads butcesi buyutulmemeli.
