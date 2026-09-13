# P13 — kişisel not defteri ve hatırlatıcı

14 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; `personal_notes` rollout satırı kapalı, canlıya uygulanmadı.**

Migration: [20260914070000_isg_personal_notes.sql](../../supabase/migrations/20260914070000_isg_personal_notes.sql) · Sözleşme: [kişisel defter](../../contracts/isg/v1/personal-notebook.md) · [Kanıt](evidence/P13_PERSONAL_NOTES_2026-09-14.json).

## Ne eklendi?

- **Firma domaininden tam bağımsızlık:** sekiz tablonun hiçbirinde `company`/`workplace`/`employee`/`entity` sütunu yok, dosya varlığına referans yok. Canlı `information_schema` sorgusu bunu doğruluyor.
- **Free:** üç ana fonksiyonun gövdesinde `require_company`, `user_plan_tier` veya `user_subscriptions` geçmiyor; bu da `pg_proc.prosrc` üzerinden test ediliyor.
- **Çakışmada iki metin de korunuyor:** sürüm uyuşmazsa sunucudaki metin yerinde kalıyor, gelen metin `note_conflicts`'e yazılıyor, çözüm kullanıcının seçtiği birleşimi yeni sürüm yapıyor. Sessiz metin kaybı yok.
- **Tombstone diriltilemiyor:** silinen not metnini kaybediyor, işaret kalıyor; çevrimdışı eski cihaz hem sürümlü hem sürümsüz denemede `NOTE_TOMBSTONED` alıyor.
- **Occurrence serinin kimliğinden ayrı:** birini tamamlamak/ertelemek seriyi kapatmıyor; yanıt kalan açık occurrence sayısını ve `series_closed=false` bildiriyor. Seri iptali yalnız geleceği kapatıyor.
- **DST:** occurrence'lar serinin timezone'unda yerel duvar saatini koruyor. Test Europe/Berlin'de 2027-03-27/28/29 için `09:00` yerel saati sabit tutuyor, UTC anı `08:00 → 07:00 → 07:00` olarak kayıyor.
- **Tek teslim sahibi:** hatırlatıcı başına tek claim satırı; yeni kurulum devralıyor, iki kurulum aynı anda sahip olamıyor. Garanti açıkça `at_most_once_per_installation`, `exactly_once_promised=false`.

## Test kanıtı

`--synthetic-session` → **716/716 PASS** (27'si bu dilimin yeni kontrolü), cleanup PASS. `--isolated-copy --p05-upgrade` → **29/29 PASS**: tam legacy kopyada **on altı** migration replay, 107 tablo, hepsinde RLS. Offline foundation **240 PASS**.

Bu dilimde **hata çıkmadı**; ilk koşu yeşil geçti. Tek düzeltme, offline guard testindeki bir ifadenin migration'ın kendi yorum satırındaki "attachment" kelimesine takılmasıydı — kontrol sütun tanımlarına daraltıldı.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_auth_restore.mjs --synthetic-session      # aşama: personal-notes
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
node scripts/isg/run_suite.mjs foundation
~~~

## Açık kalanlar

1. **İstemci senkron motoru:** çevrimdışı taslak kuyruğu, `expected_version` gönderimi, çakışma ekranı ve kurtarma ekranı.
2. **Cihaz tarafı zamanlama kabulleri:** DST, yeniden başlatma, uygulama güncellemesi, timezone değişimi, Focus, pil optimizasyonu ve Android exact alarm yetkisinin bulunmadığı durum. İlk sürümde exact-alarm yetkisine dayanılmayacak.
3. Etiket yönetimi fonksiyonları (tablolar hazır, yazan fonksiyon yok) ve retention politikası.
4. Not gövdesinin telemetriye girmediğinin istemci tarafı kanıtı (P16).
5. Canlı migration ve rollout.
