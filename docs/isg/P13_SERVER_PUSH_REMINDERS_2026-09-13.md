# P13 — server-push kişisel hatırlatıcı dilimi

13 Eylül 2026 · Durum: **API, iki native istemci ve P12 dispatch bağı yerel olarak tamamlandı; rollout kapalı, üretime uygulanmadı. P13 fazı kapanmadı.**

Migration: [20260914070005_isg_notebook_reminder_api.sql](../../supabase/migrations/20260914070005_isg_notebook_reminder_api.sql) · Sözleşme: [notebook reminder API](../../contracts/isg/v1/notebook-reminder-api.md) · [Makinece okunabilir kanıt](evidence/P13_SERVER_PUSH_REMINDERS_2026-09-13.json).

## Bu dilimde tamamlananlar

- Kullanıcının seçtiği ilk teslim stratejisi yalnız **`server_push`** olarak uygulandı. Aynı reminder için yerel alarm veya sessiz fallback kurulmadı.
- Aktif oturumlu ve owner-only sayfalı okuma ile `create`, `complete`, `snooze`, `cancel` işlemleri eklendi. Yazmalar UUID mutation kimliği, request hash ve seri sürümüyle korunuyor.
- Oluşturma, seçilen kalıcı kurulum UUID'si için güncel APNs/FCM token'ı, son 24 saatte kaydedilmiş OS izni ve açık ana bildirim + `app_reminders` tercihi yoksa `DEVICE_UNAVAILABLE` ile kapanıyor. Geçmiş tarih istemciye güvenilmeden sunucuda da reddediliyor.
- İlk sekiz occurrence oluşturuluyor. Producer uygun occurrence'ı P12 job/episode kayıtlarına çeviriyor fakat sağlayıcı çağırmıyor.
- Claim ve gerçek gönderim sınırı occurrence durumu, seri sürümü, planlanan/ertelenen zaman, tek teslim sahibi, seçili installation, token, OS izni, aktif oturum, minimum build ve `app_reminders` tercihinin tamamını yeniden doğruluyor. Bayat job başka cihaza veya eski saate gönderilmiyor.
- iOS ve Android aynı response/mutation sözleşmesini kullanıyor. İki ekranda tarih, tekrar, oluşturma, tamamla, 10 dakika ertele ve iptal akışları bulunuyor; kaydedilmemiş formdan çıkış korunuyor.
- Kurulum UUID'si kullanıcı kimliğinden türetilmiyor ve cihazda kalıcı tutuluyor. iOS APNs token rotasyonu da Android gibi `(user, provider, application, installation)` kimliğiyle mevcut kaydı güncelliyor; aynı kurulum için bayat ikinci token bırakmıyor.
- Reminder UI `NotebookUIRelease.enabled=false`, sunucu `personal_notes` ve `notifications` rollout'ları varsayılan kapalı. Canlı migration, worker, provider çağrısı veya mağaza gönderimi yapılmadı.

## Doğrulama

| Katman | Sonuç | Sınır |
|---|---|---|
| İzole GoTrue + PostgREST + PostgreSQL | **858/858 PASS, 857 tekil ID; 20 yeni reminder kontrolü** | Sentetik cihaz/token; provider çağrısı yok |
| Reminder → P12 zinciri | Producer job üretimi, seçili installation snapshot'ı, claim, snooze ile eski job iptali/yeni zaman, cancel ile gelecek job iptali PASS | Gerçek APNs/FCM teslimi değil |
| Legacy-kopya upgrade | **32/32 PASS; 22 migration**, legacy satır/helper parmak izleri değişmedi, cleanup PASS | Üretim migration'ı değil |
| Foundation | **363/363 PASS** | Tüm ürün kabulü değil |
| Swift sözleşme/native guard | **6/6 PASS** | Fiziksel cihaz UI/push değil |
| Android notebook unit + app compile | **23/23 PASS**, `:app:compileDebugKotlin` PASS | Bağlı emulator/fiziksel cihaz yoktu |
| iOS ana uygulama | Debug iPhone Simulator build PASS | Feature gate kapalı olduğu için reminder ekran E2E çalıştırılmadı |

Sentetik rapor: `output/isg/runs/synthetic-auth-Ks1gUb/REPORT.json`. Legacy upgrade raporu: `backups/isg-auth-service-restore-20260912-fBTALn/REPORT.json`. Her iki disposable ortamın cleanup sonucu PASS; dış egress ve production değişikliği yok.

## Koşularda bulunan ve düzeltilenler

1. Yeni reminder HTTP RPC'leri sentetik PostgREST allowlist'inde yoktu; ilk tam koşu notebook aşamasında kapandı. İki endpoint açık listeye eklendi.
2. Cihaz izin RPC'si aynı allowlist'te eksikti; ikinci koşu ilk iki reminder kontrolünden sonra kapandı. İzin endpoint'i eklendi. İki başarısız koşunun da cleanup'ı PASS.
3. iOS APNs kaydı hâlâ token-temelli upsert kullanıyordu. Token rotasyonunda aynı installation için eski kayıt bırakma riski kurulum-temelli unique anahtara geçirilerek giderildi.
4. Yeni worker/repository kaynakları eklenince fonksiyon-test manifest hash'leri doğal olarak değişti; gerçek drift kapısı bunu yakaladı, eşleme güncellendi ve foundation yeniden tamamen geçti.
5. Kaynak incelemesinde gelecekte tarih denetiminin yalnız native istemcilerde olduğu görüldü; aynı kontrol DB mutation kapısına eklendi ve gerçek HTTP üzerinden geçmiş tarih reddi doğrulandı.
6. `app_reminders` tercihi kapalı bir kullanıcı teknik olarak reminder oluşturabiliyor fakat job gönderim anında bastırılıyordu. Teslim edilemeyecek bu durum artık oluşturma anında `DEVICE_UNAVAILABLE` ile reddediliyor.

Son sıkılaştırmadan sonraki ilk tekrar, reminder migration'ına ulaşmadan yerel Auth `session-guard` claim kontrolünde kapandı (`synthetic-auth-kZfz5Y`); aynı kaynakla hemen tekrarlanan tam koşu geçti ve iki koşunun cleanup'ı PASS oldu. Bu erken/kararsız altyapı denemesi başarı sayısına katılmadı, kanıttan silinmedi.

## Kalan işler — uygulanma sırası

1. **P12 çalışma ortamı:** production pool/worker rolü, secret/credential kaynağı, scheduler ve P01 consumer bağlantısını kapalı rollout üzerinde staging/simulate ile doğrula.
2. **Gerçek cihaz reminder kabulü:** APNs ve FCM için izin açık/kapalı, token rotasyonu, foreground/background, timezone değişimi, uygulama güncellemesi, yeniden başlatma, Focus ve Android pil optimizasyonu senaryoları. `server_push` seçimi nedeniyle Android exact-alarm izni kullanılmayacak.
3. **Teslim gözlemi ve deep-link:** provider accepted, cihaz teslimi ve kullanıcı açmasını ayrı durumlar olarak izle; reminder deep-link'ini eski build güvenli düşüşüyle bağla. Exactly-once veya kesin teslim iddiası verme.
4. **Reminder mutation dayanıklılığı:** çevrimdışı create/settle için aynı mutation UUID'sini koruyan şifreli pending kuyruk ve belirsiz HTTP yanıtından kurtarma davranışı ekle. Bugünkü reminder yazmaları online'dır.
5. **P13 kalan ürün işleri:** etiket oluşturma/yönetme yüzeyi, retention/silme politikası, istemci telemetri redaksiyon kanıtı ve gerçek cihaz accessibility/UI kabulü.
6. Bunlar ve P12 kapıları geçmeden P13 kapanışı, canlı rollout, mağaza update'i veya P14'e kesin geçiş ilan etme.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_auth_restore.mjs --synthetic-session
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
node scripts/isg/run_suite.mjs foundation

cd android
env JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ./gradlew :core:data:testDebugUnitTest --tests '*Notebook*Test' \
  :app:compileDebugKotlin --offline
~~~

iOS ana build için `RiskDetected` scheme'i, generic iPhone Simulator hedefi ve `CODE_SIGNING_ALLOWED=NO` kullanıldı.
