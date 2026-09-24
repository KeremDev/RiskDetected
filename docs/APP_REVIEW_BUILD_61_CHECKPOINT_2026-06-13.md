# App Review Build 61 Checkpoint

## Summary

RiskDetected iOS version `1.1` build `61`, `2026-06-13` tarihinde App Review'e gonderildi.

Bu kayit, App Store'da yayinda olan `1.0 (60)` surumunden sonra hazirlanan dil duzeltmesi, hata duzeltmeleri ve arayuz iyilestirmeleri icin submission checkpoint notudur.

## Submission Details

- Submission date: `2026-06-13`
- Submission time: `04:10 Europe/Istanbul` civari
- Marketing version: `1.1`
- Submitted build: `61`
- Bundle identifier: `com.riskdetected.app`
- App Store Connect build status before submission: `Complete`
- App Store Connect version build status before submission: `Ready to Submit`
- App Review status after user action: `Submitted to App Review`
- Active local branch at submission time: `codex/worktree-cleanup`
- Source checkpoint before this note commit: `f1436ab Fix onboarding sync and ship sector plus trial reminder backend.`
- Local restore branch: `codex/app-review-build-61`
- Local restore tag: `app-review-build-61-2026-06-13`
- Restore ref target: `f1436ab8578b2383c1495c247860306b377499c3`

## Primary Review Context

Bu gonderimin ana gerekcesi App Store'da dil bilgisinin `EN / Ingilizce` gorunmesi yerine Turkce olarak gorunmesini saglamaktir.

Binary icinde dogrulanan ilgili degerler:

```text
CFBundleDevelopmentRegion = tr
CFBundleLocalizations = [tr]
CFBundleShortVersionString = 1.1
CFBundleVersion = 61
```

App Store "What's New" metni icin onerilen kisa not:

```text
Uygulama dil bilgisi Turkce olarak guncellendi.
Bazi hata duzeltmeleri ve arayuz iyilestirmeleri yapildi.
```

## Included Change Areas

- App Store dil metadata davranisi icin bundle localization ayarlari `tr` olarak netlestirildi.
- Version `1.1`, build `61` olarak arttirildi.
- Aktif analiz sektoru akisi ve sektor secim UI'i sertlestirildi.
- Paywall fiyat gosterimi StoreKit/RevenueCat canli fiyat kaynagina baglandi; hardcoded release fiyat fallback'leri kaldirildi.
- Plus yillik 7 gunluk deneme icin backend push hatirlatma altyapisi eklendi.
- Yasal metin guncelleme banner'inin yeni kayit olmus kullanicilara gereksiz gosterilmemesi saglandi.
- Onboarding ve paywall ekranlarinda gorunen metin, spacing ve CTA davranislari iyilestirildi.
- Analiz sonuc ve gecmis ekranlarinda dark/light mode gorunurluk ve paywall yonlendirme duzeltmeleri yapildi.

## Local Archive And Upload Evidence

Xcode Organizer archive:

```text
/Users/keremkayalar/Library/Developer/Xcode/Archives/2026-06-13/RiskDetected 13.06.2026, 03.50.xcarchive
```

Archive Info.plist kontrolunde:

```text
Version: 1.1
Build: 61
Bundle ID: com.riskdetected.app
CFBundleDevelopmentRegion: tr
CFBundleLocalizations: tr
```

Xcode Organizer `Validate App` sonucu basariliydi. App Store Connect TestFlight build listesinde `1.1 (61)` icin `Complete` goruldu ve version `1.1` altinda build `61` `Ready to Submit` durumundaydi.

## Restore Notes

Bu dosya submission sonrasinda olusturulmus referans kaydidir. Gonderilen build'in kaynak snapshot'i bu not commit'inden hemen onceki aktif kaynak commit'i olan `f1436ab8578b2383c1495c247860306b377499c3` uzerindedir.

App Review'e gonderilen kaynak durumuna donmek icin:

```bash
cd /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected
git switch --detach app-review-build-61-2026-06-13
```

Veya build 61 kaynak noktasindan yeni bir fix branch acmak icin:

```bash
git switch -c codex/fix-from-app-review-build-61 app-review-build-61-2026-06-13
```

## Notes

- `output/` altindaki `.xcarchive`, `.xcresult`, screenshot ve diger generated review artifact dosyalari Git'e alinmadi.
- App Store Connect metadata degisiklikleri bu repo commit'inin parcasi degildir; ASC arayuzunde manuel yonetilir.
