# App Store Approval - Version 1.0 Build 60

## Summary

RiskDetected iOS version `1.0` build `60`, Apple App Review tarafindan onaylandi ve `Ready for Distribution` durumuna gecti.

Bu kayit, onaylanan kaynak durumuna istenildiginde dogrudan geri donebilmek icin olusturuldu. Onaylanan kaynak snapshot'i, App Review'e gonderilen build 60 kaynak commit'i ile aynidir.

## Approval Details

- Approval date: `2026-06-11`
- Approval time: `23:10 Europe/Istanbul (GMT+3)`
- App Store Connect status: `Ready for Distribution`
- App Store Connect activity user: `Apple`
- Marketing version: `1.0`
- Approved build: `60`
- Release setting at approval: `Automatically release this version`
- Review context: `Guideline 5.1.1(v) account deletion fix accepted`

## Approved Source References

iOS repository:

- Repository: `https://github.com/KeremDev/RiskDetected.git`
- Approved source commit: `76ddd7184af707a10b6b2b541e1ea8c6661f1154`
- Approved source commit message: `Fix App Review account deletion and legal sync`
- Approved restore branch: `codex/app-store-approved-1.0-build-60`
- Approved restore tag: `app-store-approved-1.0-build-60-2026-06-11`
- App Review submission tag: `app-review-build-60-2026-06-10`

Website companion repository:

- Repository: `https://github.com/KeremDev/riskdetected-landing.git`
- Approved companion commit: `bc4e1f5136237036165b5633b5e80bed921df490`
- Approved companion commit message: `Add website legal document export`
- Approved restore branch: `codex/app-store-approved-1.0-build-60`
- Approved restore tag: `app-store-approved-1.0-build-60-2026-06-11`
- App Review submission tag: `app-review-build-60-2026-06-10`

## GitHub Verification

Remote restore refs were pushed and verified:

```text
RiskDetected refs/heads/codex/app-store-approved-1.0-build-60 -> 76ddd7184af707a10b6b2b541e1ea8c6661f1154
RiskDetected refs/tags/app-store-approved-1.0-build-60-2026-06-11^{} -> 76ddd7184af707a10b6b2b541e1ea8c6661f1154

riskdetected-landing refs/heads/codex/app-store-approved-1.0-build-60 -> bc4e1f5136237036165b5633b5e80bed921df490
riskdetected-landing refs/tags/app-store-approved-1.0-build-60-2026-06-11^{} -> bc4e1f5136237036165b5633b5e80bed921df490
```

## Local Backups

Tracked source archives were created from the approval tags.

- iOS archive path: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected_app-store-approved-1.0-build-60_2026-06-11_76ddd71.tar.gz`
- iOS archive size at creation: `19M`
- iOS archive source: `app-store-approved-1.0-build-60-2026-06-11`
- Website archive path: `/Users/keremkayalar/Documents/Kerem-APPler/WebRiskDetected_app-store-approved-1.0-build-60_2026-06-11_bc4e1f5.tar.gz`
- Website archive size at creation: `20M`
- Website archive source: `app-store-approved-1.0-build-60-2026-06-11`
- Archive contents: tracked source files only
- Excluded by design: DerivedData, build artifacts, exported IPA/app archives, untracked temporary files

## Restore Procedure

Use this when the request is: "App Store'da onaylanan 1.0 build 60 versiyonuna donelim."

1. Preserve current iOS work:

```bash
cd /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected
git status --short --branch
git stash push -u -m "Before restoring App Store approved 1.0 build 60"
```

2. Restore iOS source from the approval tag:

```bash
git switch --detach app-store-approved-1.0-build-60-2026-06-11
```

3. Or restore onto a named branch:

```bash
git switch -c codex/fix-from-app-store-approved-1.0-build-60 app-store-approved-1.0-build-60-2026-06-11
```

4. Restore the companion website source if legal website sync must match the approved app:

```bash
cd /Users/keremkayalar/Documents/Kerem-APPler/WebRiskDetected
git status --short --branch
git stash push -u -m "Before restoring App Store approved 1.0 build 60 website"
git switch --detach app-store-approved-1.0-build-60-2026-06-11
```

5. If Git history is unavailable, recover from the local archives:

```bash
mkdir -p /tmp/RiskDetected_app_store_approved_1_0_build_60_restore
tar -xzf /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected_app-store-approved-1.0-build-60_2026-06-11_76ddd71.tar.gz -C /tmp/RiskDetected_app_store_approved_1_0_build_60_restore

mkdir -p /tmp/WebRiskDetected_app_store_approved_1_0_build_60_restore
tar -xzf /Users/keremkayalar/Documents/Kerem-APPler/WebRiskDetected_app-store-approved-1.0-build-60_2026-06-11_bc4e1f5.tar.gz -C /tmp/WebRiskDetected_app_store_approved_1_0_build_60_restore
```

## Notes

- The approval tags and restore branches must remain immutable. Do not move or force-update them.
- The active development branch may continue to advance after this record.
- This file was created after approval and is a reference record; the approved app source snapshot is the tagged commit.
