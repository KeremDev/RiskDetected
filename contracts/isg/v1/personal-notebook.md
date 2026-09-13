# Kişisel not defteri ve hatırlatıcı — v1 sunucu sözleşmesi

14 Eylül 2026. P13. Defter **firma domaininden bağımsızdır ve Free'dir**: sekiz tablonun hiçbirinde firma, işyeri, çalışan veya entity sütunu yoktur, ek dosya bağlantısı yoktur ve hiçbir fonksiyon abonelik/plan kontrolü yapmaz.

Migration: [20260914070000_isg_personal_notes.sql](../../../supabase/migrations/20260914070000_isg_personal_notes.sql).

## Senkron ve çakışma

`sync_personal_note` sahip + `expected_version` ile çalışır. Sürüm uyuşmazsa **son yazan kazanmaz**: sunucudaki metin yerinde kalır, gelen metin `note_conflicts` satırına yazılır ve yanıt `state='conflict'`, `both_texts_preserved=true` döner. `resolve_note_conflict` kullanıcının seçtiği birleşimi yeni sürüm olarak yazar ve iki metni de kanıt olarak saklar.

Aynı içerik tekrar gönderilirse sürüm artmaz (`unchanged`). Başka bir hesap nota dokunamaz.

## Silme ve tombstone

`delete_personal_note` metni temizler, `tombstone` işaretler ve **gelecek hatırlatıcı occurrence'larını iptal eder**; tamamlanmış occurrence geçmişi korunur. Çevrimdışı kalmış eski bir cihaz aynı not kimliğiyle geri gelemez: hem sürümlü hem sürümsüz deneme `NOTE_TOMBSTONED` alır.

## Hatırlatıcı serisi ve occurrence

Occurrence kimliği serinin kimliğinden ayrıdır. Bir occurrence'ı ertelemek veya tamamlamak seriyi kapatmaz (`series_closed=false`, kalan açık occurrence sayısı yanıtta). Erteleme yalnız ileri bir zamana yapılabilir. Seriyi iptal etmek yalnız **gelecek** occurrence'ları kapatır, tamamlananları korur.

Occurrence'lar serinin kendi timezone'unda **yerel duvar saatini** korur: Avrupa yaz saati geçişinde yerel 09:00 sabit kalır, UTC anı bir saat kayar. `local_due_at` ve `due_at` ayrı saklanır.

## Teslim sahibi

`device_delivery_claims` hatırlatıcı başına **tek satırdır**: ya adı belli bir kurulum yerel olarak teslim eder ya da server push yolu. Yeni bir kurulum devralır, iki kurulum aynı anda sahip olamaz; yanıt önceki kurulumu bildirir. Garanti açıkça `at_most_once_per_installation`'dır ve `exactly_once_promised=false` döner — çevrimdışı çok cihazda mutlak OS teslimi vaat edilmez.

## Henüz olmayanlar

İstemci senkron motoru ve çevrimdışı taslak kuyruğu, kurtarma ekranı, cihaz tarafı DST/reboot/uygulama güncellemesi/Focus/pil optimizasyonu/Android exact alarm testleri, etiket yönetimi fonksiyonları, retention politikası ve not gövdesinin telemetriden dışlanmasının istemci tarafı kanıtı. `personal_notes` rollout satırı kapalıdır; istemciye GRANT verilmemiştir.
