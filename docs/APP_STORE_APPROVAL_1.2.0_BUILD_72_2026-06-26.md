# App Store Approval - Version 1.2.0 Build 72

## Summary

RiskDetected iOS version `1.2.0` build `72`, Apple App Review tarafından onaylandı, App Store Connect'te **manuel release** ile yayınlandı ve `Ready for Sale` durumuna geçti.

Bu kayıt, onaylanan kaynak durumuna istenildiğinde doğrudan geri dönebilmek için oluşturuldu. Onaylanan kaynak snapshot'i, App Review'e gönderilen build 72 kaynak commit'i ile aynıdır.

Release sonrası 24–48 saat izleme (2026-06-28) tamamlandı: canlı flag'ler değişmedi, Supabase'de release sonrası analizlerde `failed=0`, App Store Connect crash/review tarafında sorun bildirilmedi.

## Approval Details

- Approval date: `2026-06-26`
- App Store release date: `2026-06-26`
- App Store Connect status: `Ready for Sale`
- Marketing version: `1.2.0`
- Approved build: `72`
- Release setting at approval: `Manually release this version`
- Review context: `Multi-photo analysis (up to 5 photos), coverage_v2 findings, editable findings, report snapshot v2 — build-gated rollout via Supabase allowlist`

## Approved Source References

iOS repository:

- Repository: `https://github.com/KeremDev/RiskDetected.git`
- Approved source commit: `3a1a7559b9b82c8a8e559e2542feceb6de83564c`
- Approved source commit message: `Prepare build 72 for App Review`
- Approved restore branch: `codex/app-store-approved-1.2.0-build-72`
- Approved restore tag: `app-store-approved-1.2.0-build-72-2026-06-26`

## Post-Release Verification

- Live feature flags unchanged since pre-release (`kill_switch=false`, build `72` in `enabled_ios_builds`)
- App Store smoke test analysis: `9d414bd3-17ef-48d0-b4fa-914a9d6a648c` (`finding_count=29`, `coverage_v2=true`, 5 photos)
- Monitoring window (2026-06-28): release sonrası `4 completed / 0 failed`; son 7 gün `9 completed / 0 failed`
- Follow-up plan: [BUILD_72_RELEASE_FOLLOWUP_2026-06-26.md](BUILD_72_RELEASE_FOLLOWUP_2026-06-26.md)
- Rollout runbook: [BUILD_GATED_IOS_ROLLOUT_RUNBOOK.md](BUILD_GATED_IOS_ROLLOUT_RUNBOOK.md)

## GitHub Verification

After pushing restore refs, verify:

```bash
git fetch origin --tags
git rev-parse app-store-approved-1.2.0-build-72-2026-06-26^{}
git rev-parse origin/codex/app-store-approved-1.2.0-build-72
```

Expected: both resolve to `3a1a7559b9b82c8a8e559e2542feceb6de83564c`.

## Restore Procedure

Use this when the request is: "App Store'da onaylanan 1.2.0 build 72 versiyonuna dönelim."

1. Preserve current iOS work:

```bash
cd /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected
git status --short --branch
git stash push -u -m "Before restoring App Store approved 1.2.0 build 72"
```

2. Restore iOS source from the approval tag:

```bash
git switch --detach app-store-approved-1.2.0-build-72-2026-06-26
```

3. Or restore onto a named branch:

```bash
git switch -c codex/fix-from-app-store-approved-1.2.0-build-72 app-store-approved-1.2.0-build-72-2026-06-26
```

## Notes

- The approval tag and restore branch must remain immutable. Do not move or force-update them.
- The active development branch may continue to advance after this record.
- This file is a reference record; the approved app source snapshot is the tagged commit.
- Website companion repo was unchanged for this release; no landing restore tag was created for build 72.
