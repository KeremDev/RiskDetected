# P13 — kişisel not defteri ve hatırlatıcı

14 Eylül 2026 · Durum: **not senkronu, iki native not ekranı ve server-push reminder dilimi yerel tamamlandı; `personal_notes`/`notifications` rollout'ları kapalı, canlıya uygulanmadı. P13 fazı kapanmadı.**

İlk migration: [20260914070000_isg_personal_notes.sql](../../supabase/migrations/20260914070000_isg_personal_notes.sql) · Sözleşme: [kişisel defter](../../contracts/isg/v1/personal-notebook.md) · [İlk dilim kanıtı](evidence/P13_PERSONAL_NOTES_2026-09-14.json) · [Güncel server-push reminder paketi ve yapılacaklar](P13_SERVER_PUSH_REMINDERS_2026-09-13.md).

## Güncel ek paket

İlk sunucu çekirdeğinden sonra authenticated notebook sync ve organization RPC'leri, iOS/Android'de kullanıcıya ayrılmış şifreli pending not kuyruğu, iki metni koruyan conflict akışı, checklist/tag editörleri ve gerçek repository'ler eklendi. Kullanıcının seçimiyle reminder teslimi yalnız `server_push` oldu; local alarm fallback'i kurulmadı.

Reminder okuma/create/complete/snooze/cancel API'si, kalıcı kurulum UUID'si, seçili installation için güncel token/OS izin kapısı, occurrence producer→P12 job/claim zinciri ve gönderim-anı iptal/sürüm/zaman/izin kontrolü tamamlandı. iOS APNs token rotasyonu da installation-temelli tek kayda geçirildi. Native giriş ve iki sunucu rollout'u hâlâ kapalıdır.

## Ne eklendi?

- **Firma domaininden tam bağımsızlık:** sekiz tablonun hiçbirinde `company`/`workplace`/`employee`/`entity` sütunu yok, dosya varlığına referans yok. Canlı `information_schema` sorgusu bunu doğruluyor.
- **Free:** üç ana fonksiyonun gövdesinde `require_company`, `user_plan_tier` veya `user_subscriptions` geçmiyor; bu da `pg_proc.prosrc` üzerinden test ediliyor.
- **Çakışmada iki metin de korunuyor:** sürüm uyuşmazsa sunucudaki metin yerinde kalıyor, gelen metin `note_conflicts`'e yazılıyor, çözüm kullanıcının seçtiği birleşimi yeni sürüm yapıyor. Sessiz metin kaybı yok.
- **Tombstone diriltilemiyor:** silinen not metnini kaybediyor, işaret kalıyor; çevrimdışı eski cihaz hem sürümlü hem sürümsüz denemede `NOTE_TOMBSTONED` alıyor.
- **Occurrence serinin kimliğinden ayrı:** birini tamamlamak/ertelemek seriyi kapatmıyor; yanıt kalan açık occurrence sayısını ve `series_closed=false` bildiriyor. Seri iptali yalnız geleceği kapatıyor.
- **DST:** occurrence'lar serinin timezone'unda yerel duvar saatini koruyor. Test Europe/Berlin'de 2027-03-27/28/29 için `09:00` yerel saati sabit tutuyor, UTC anı `08:00 → 07:00 → 07:00` olarak kayıyor.
- **Tek teslim sahibi:** hatırlatıcı başına tek claim satırı; yeni kurulum devralıyor, iki kurulum aynı anda sahip olamıyor. Garanti açıkça `at_most_once_per_installation`, `exactly_once_promised=false`.

## İlk dilim test kanıtı ve son regresyon

İlk `--synthetic-session` koşusu **716/716 PASS** (27'si bu dilimin yeni kontrolü), cleanup PASS idi. İlk `--isolated-copy --p05-upgrade` koşusu **29/29 PASS** ve on altı migration; offline foundation **240 PASS** idi.

Güncel reminder paketi sonrası tam regresyon: **858/858 sentetik PASS (857 tekil; 20 yeni reminder), 32/32 legacy upgrade / 22 migration ve 363/363 foundation**. Swift reminder/native guard **6/6**, Android notebook **23/23** + app Kotlin compile, iOS ana Debug Simulator build PASS. Gerçek APNs/FCM çağrısı yapılmadı; Android cihaz/emülatör bağlı değildi ve kapalı feature gate nedeniyle runtime reminder UI E2E çalıştırılmadı. [Güncel makinece okunabilir kanıt](evidence/P13_SERVER_PUSH_REMINDERS_2026-09-13.json).

Bu dilimde **hata çıkmadı**; ilk koşu yeşil geçti. Tek düzeltme, offline guard testindeki bir ifadenin migration'ın kendi yorum satırındaki "attachment" kelimesine takılmasıydı — kontrol sütun tanımlarına daraltıldı.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_auth_restore.mjs --synthetic-session      # aşama: personal-notes
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
node scripts/isg/run_suite.mjs foundation
~~~

## Açık kalanlar

1. P12 production pool/worker rolü, credential/secret kaynağı, scheduler ve P01 consumer bağlantısı; önce kapalı rollout üzerinde staging/simulate.
2. Fiziksel iOS/Android cihazda APNs/FCM, izin/token rotasyonu, timezone, reboot, uygulama güncellemesi, Focus ve pil optimizasyonu kabulü. `server_push` nedeniyle Android exact-alarm yetkisi kullanılmayacak.
3. Reminder deep-link'i ile provider accepted / cihaz teslimi / kullanıcı açması durumlarını birbirine karıştırmadan gözlemleme.
4. Çevrimdışı reminder create/settle için mutation UUID'sini koruyan şifreli pending kuyruk. Bugünkü reminder yazmaları online'dır; not yazma kuyruğu ise tamamlanmıştır.
5. Etiket oluşturma/yönetme yüzeyi, retention politikası, istemci telemetri redaksiyon kanıtı ve gerçek cihaz accessibility/UI kabulü.
6. Bu kapılar geçmeden canlı migration/rollout, mağaza yayını veya P13 kapanışı yok.
