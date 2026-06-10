# App Review Build 60 Checkpoint

## Summary

RiskDetected version `1.0` build `60`, `2026-06-10` tarihinde App Review'e gonderilen ikinci kaynak durumu olarak donduruldu. Bu build, Guideline 5.1.1(v) hesap silme reddi sonrasi hazirlanan duzeltmeleri ve website kaynakli legal markdown senkronizasyonunu icerir.

## Checkpoint References

- Submission date: `2026-06-10`
- Submission context: `App Review 5.1.1(v) ikinci gonderim`
- Submitted build: `60`
- Marketing version: `1.0`
- iOS checkpoint commit: `76ddd7184af707a10b6b2b541e1ea8c6661f1154`
- iOS commit message: `Fix App Review account deletion and legal sync`
- iOS local working branch at checkpoint time: `codex/worktree-cleanup`
- iOS restore branch: `codex/app-review-build-60`
- iOS restore tag: `app-review-build-60-2026-06-10`
- iOS tag message: `App Review submission checkpoint for build 60`
- Website companion commit: `bc4e1f5136237036165b5633b5e80bed921df490`
- Website companion branch at checkpoint time: `main`
- Website restore branch: `codex/app-review-build-60`
- Website restore tag: `app-review-build-60-2026-06-10`
- Website tag message: `App Review build 60 website legal checkpoint`

## Included Changes

- Profile ekraninda `Cikis yap` ustune dogrudan gorunen `Hesabimi sil / Delete Account` satiri eklendi.
- Hesap silme onay metni, islemin uygulama icinde tamamlandigini ve e-posta/destek/web sitesi gerekmedigini acik soyleyecek sekilde guncellendi.
- Hesap silme tamamlandiktan sonra sign-out oncesi `Hesap silindi / Account Deleted` basari onayi eklendi.
- KVKK, Gizlilik Politikasi, Kullanim Kosullari ve Acik Riza Beyani `2026-06-10` metinleriyle guncellendi.
- KVKK ve Kullanim Kosullari icinde `MERSIS/VKN/TCKN: 21832867210` app, website markdown ve Supabase fallback tarafinda esitlendi.
- Uygulama legal dokumanlari once `https://riskdetected.com/legal-documents/manifest.json` uzerinden, 24 saatlik refresh ile okuyacak sekilde guncellendi.
- Supabase Storage `legal-documents` bucket'i website markdown ciktilariyla fallback olarak guncellendi.
- Website build hattina legal JSX sayfalarindan markdown + manifest ureten `prebuild` export adimi eklendi.
- Production website deploy edildi ve `https://riskdetected.com/legal-documents/manifest.json` JSON olarak dogrulandi.

## Live References

- Website legal manifest: `https://riskdetected.com/legal-documents/manifest.json`
- Website KVKK markdown: `https://riskdetected.com/legal-documents/tr/KVKK-Aydinlatma-ve-Acik-Riza-Metni.md`
- Supabase fallback manifest: `https://ppcrzemgiztzcgddbins.supabase.co/storage/v1/object/public/legal-documents/manifest.json`
- Vercel production deployment: `https://riskdetected-landing-91uiygbfg-kerem-kayalars-projects.vercel.app`
- Vercel inspect URL: `https://vercel.com/kerem-kayalars-projects/riskdetected-landing/BkBogqoaxpHR5myfVypHREx8hPox`

## Local Backups

Tracked source archives were created from the checkpoint tags.

- iOS archive path: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected_app-review-build-60_2026-06-10_76ddd71.tar.gz`
- iOS archive size at creation: `19M`
- iOS archive source: `app-review-build-60-2026-06-10`
- Website archive path: `/Users/keremkayalar/Documents/Kerem-APPler/WebRiskDetected_app-review-build-60_2026-06-10_bc4e1f5.tar.gz`
- Website archive size at creation: `20M`
- Website archive source: `app-review-build-60-2026-06-10`
- Archive contents: tracked source files only
- Excluded by design: DerivedData, build artifacts, exported IPA/app archives, untracked temporary files

## Restore Procedure

Use this when the request is: "App Review'e gonderdigimiz build 60'a donelim."

1. Preserve current iOS work before restoring:

```bash
cd /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected
git status --short --branch
git stash push -u -m "Before restoring App Review build 60"
```

2. Restore the iOS source from the checkpoint tag:

```bash
git switch --detach app-review-build-60-2026-06-10
```

3. Or restore onto a named branch for fixes based on build 60:

```bash
git switch -c codex/fix-from-app-review-build-60 app-review-build-60-2026-06-10
```

4. Restore the companion website source if legal website sync must match the submitted build:

```bash
cd /Users/keremkayalar/Documents/Kerem-APPler/WebRiskDetected
git status --short --branch
git stash push -u -m "Before restoring App Review build 60 website"
git switch --detach app-review-build-60-2026-06-10
```

5. If Git history is unavailable, recover from the source archives:

```bash
mkdir -p /tmp/RiskDetected_app_review_build_60_restore
tar -xzf /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected_app-review-build-60_2026-06-10_76ddd71.tar.gz -C /tmp/RiskDetected_app_review_build_60_restore

mkdir -p /tmp/WebRiskDetected_app_review_build_60_restore
tar -xzf /Users/keremkayalar/Documents/Kerem-APPler/WebRiskDetected_app-review-build-60_2026-06-10_bc4e1f5.tar.gz -C /tmp/WebRiskDetected_app_review_build_60_restore
```

## Verification Performed

- `npm run build` in `WebRiskDetected`: passed.
- Vercel production deploy: passed and aliased to `https://riskdetected.com`.
- Website legal manifest: HTTP 200 JSON and hash values verified.
- Supabase fallback legal manifest: hash values verified.
- KVKK markdown on website, Supabase fallback, and app bundle source all show `MERSIS/VKN/TCKN: 21832867210`.
- XcodeBuildMCP `build_sim` on `iPhone 17 Pro`: passed.
- `git diff --check` in both repos: passed.
- App Review preflight relevant checks: `Public legal/support URL health`, `App legal URL config and bundled docs`, and `Account deletion path readiness` passed. Remaining preflight failures were existing unrelated marker/screenshot checks.

## Notes

- The iOS checkpoint tag and restore branch must remain immutable. Do not move or force-update them.
- The website checkpoint tag and restore branch must remain immutable. Do not move or force-update them.
- Changes after this checkpoint should be committed separately on the active development branches.
- This file was created after the checkpoint source commit, so it is a reference record and not part of the exact submitted build 60 source snapshot.
