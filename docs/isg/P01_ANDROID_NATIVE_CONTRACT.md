# P01 — Android cihaz üstü contract matrisi

12 Eylül 2026. **API 26, 33 ve 37: 44'er test, toplam 132 PASS / 0 FAIL / 0 SKIP.** [Makine kanıtı](evidence/P01_ANDROID_NATIVE_CONTRACT_2026-09-12.json) kaynak ve APK SHA256, her cihazın zamanı, 44 test adı ve cleanup sonucunu içerir.

## Kapsam ve izolasyon

Yeni `android/isg-contract-tests` bir test library modülüdür; ana uygulama ona bağımlı değildir. AGP 9 built-in Kotlin source set üzerinden gerçek `IsgMutationContext.kt` dosyasını ve ortak JSON corpus'u doğrudan kullanır; parser kopyası yoktur. 43 fixture'a ek olarak cihazdaki Application sınıfı, paket ve ağ izinlerini doğrulayan bir izolasyon testi vardır.

Test APK paketi ve instrumentation target'ı `com.riskdetectedan.isg.contracttests.test`; Application yalnız `android.app.Application`. INTERNET/ACCESS_NETWORK_STATE izni yok, cleartext kapalı. Merged manifest'teki tek izin AndroidX test desteğinin REORDER_TASKS iznidir. Supabase, RevenueCat, Firebase, Hilt veya production uygulama graph'ı yüklenmez. Bu APK yeni mağaza uygulaması değildir; `com.riskdetected.app` ve `com.riskdetectedan.app` değişmedi.

| İzole AVD | API | Test | Sonuç |
|---|---|---|---|
| ISG_Contract_API26_20260912 | 26 / minSdk | 44 | PASS |
| ISG_Contract_API33_20260912 | 33 | 44 | PASS |
| ISG_Contract_API37_20260912 | 37 / targetSdk | 44 | PASS |

Üç arm64 emülatörde aynı APK ve aynı kaynak/fixture hash'i kullanıldı. Sadece test için oluşturulan AVD'ler çalıştırıldı; mevcut beş kullanıcı AVD'sine dokunulmadı. Her kurulum hash ile doğrulandı, runner'ın kurduğu test paketi hash tekrar kontrol edilerek kaldırıldı. Üç emülatör kapatıldı; yeniden test için üç AVD tanımı/diskleri tutuluyor (yaklaşık 3,6 GB). Ana uygulama kurulmadı/açılmadı, kullanıcı oturumu veya canlı API kullanılmadı.

## Tekrar çalıştırma

Önce yukarıdaki ayrılmış AVD'lerden birini açıp gerçek serial değerini `adb devices` ile belirleyin. Runner fiziksel cihazı, başka AVD'yi, uyuşmayan API'yi ve önceden kurulu test paketini reddeder; kullanıcı uygulamasının verisini silmez.

```bash
env JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home node scripts/isg/run_android_contract.mjs --serial emulator-5554
node scripts/isg/run_suite.mjs foundation
```

Runner offline APK derler; manifest, paketlenmiş fixture ve cihazdaki APK hash'ini kontrol eder. Instrumentation çıktısında her beklenen fixture'ın tek kez PASS olması ve 44 toplam sonuç zorunludur; skip, eksik/çift sonuç veya crash başarı sayılmaz. Raporlar `output/isg/runs/android-contract-*/REPORT.json` altında, ham build/instrumentation logları restricted izinlerle tutulur. Cleanup kimliği veya hash değişirse otomatik silme durur ve REQUIRES_REVIEW raporlanır. Host kaybı/SIGKILL sonrası otomatik cleanup garantisi verilmez.

## Diğer doğrulamalar ve bulunan sorunlar

- Foundation **106/106**; yeni beş test grubu serial/AVD, CLI, manifest, instrumentation sonuçları ve SDK'sız modül bağımlılığı negatiflerini kapsar. Identity ve üç kaynaklı function map PASS.
- `:isg-contract-tests:lintDebug :app:assembleDebug :core:data:testDebugUnitTest --offline` PASS. Ana app build ve mevcut 151-test core:data görevi bu son kontrolde UP-TO-DATE; yeni 151 test koşumu diye sayılmadı.
- Lint 0 hata, 1 `UseTomlInstead` uyarısı: test runner 1.7.0 sürümü modül Gradle dosyasında sabit. Manifest permission-remove uyarıları, kaldırılacak iznin zaten bulunmadığını belirtir.
- İlk offline build eksik transitif `androidx.annotation:annotation-jvm:1.7.0` paketini buldu; bir online Gradle turunda sabit bağımlılık indirildi. SDK yükseltilmedi. AGP 9 kaynak bağlama hatası `.kotlin.directories` ile düzeltildi.
- İlk wrapper provası Android `/data/app/~~...` yolunu reddetti; koruma silmeyi durdurdu. Yol doğrulaması ve APK okuma buffer'ı düzeltildi; eldeki paketin hash'i kontrol edilip yalnız test paketi kaldırıldı. Son üç runner turu cleanup dahil PASS.
- Android CI'a yalnız test APK assemble adımı ve ilgili path filtreleri eklendi. Üç cihazlı uzak CI koşumu eklenmiş/çalışmış değildir; hiçbir workflow push edilmedi.

## Açık kalanlar

Bu testler parser'ın gerçek Android runtime davranışını kanıtlar; ekran, giriş/çıkış, abonelik, ağ hatası veya domain mutation E2E değildir. 263 V5/X kabul kaydını kapatmaz. iOS kanıtı ve sentetik transaction kapsamı [P01 işlem prototipi](P01_TRANSACTION_PROTOTYPE.md) belgesindedir. Android QA skill'i testleri ayrı, açıkça seçilmiş emülatörlerde çalıştırma ve mevcut kullanıcı ortamını koruma yaklaşımında kullanıldı.
