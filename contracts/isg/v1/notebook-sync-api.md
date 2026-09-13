# P13 — mobil not senkron API sözleşmesi

Migration: `20260914070004_isg_notebook_sync_api.sql`. İki RPC `public` şemasındadır; özel tablolar doğrudan istemciye açılmaz. Sunucu sahibi ve aktif oturumu `active_actor()` ile doğrular. İstek sahibini, firma kimliğini veya abonelik seviyesini istemciden almaz. Free hesap desteklenir. `personal_notes` rollout kapalıdır.

## Yazma

`isg_notebook_mutate_v1(p_mutation uuid, p_note uuid, p_action text, p_expected bigint, p_title text, p_body text, p_conflict uuid)`

- `sync`: yeni notta expected=0; düzenlemede son görülen sürüm. title≤200, body≤20000; ikisi birden null olamaz. conflict=null.
- `delete`: title/body/conflict=null, son görülen sürüm.
- `resolve`: conflict kimliği ve kullanıcının birleştirdiği metin; expected mutlaka notun güncel sürümüdür.
- Mutation UUID aynı niyetin ağ retry'larında değiştirilmez. Yeni kullanıcı düzenlemesinde yeni UUID gerekir. Aynı UUID/farklı istek `IDEMPOTENCY_CONFLICT` olur.
- Senkron sürüm çatışması HTTP 200 / state=`conflict` döner; hata sayıp sessizce tekrar üzerine yazılmaz. İki metin sunucuda korunur; aynı retry ikinci conflict oluşturmaz.
- Başarılı yanıt `schema_version`, `mutation_id`, `note_id`, `state`, `version` veya `server_version` ve `replayed` içerir. Çakışmada `conflict_id` bulunur. Yazma receipt'i not metnini taşımaz.
- Silme sürümü artırır ve tombstone döndürür. Eski edit veya conflict çözümü tombstone'u geri açamaz. Daha önce tamamlanmış mutation replay'i tarihi yanıtı döndürebilir: istemci cache sürümünü düşürmemeli, yerel tombstone'u kaldırmamalıdır.

## Okuma

`isg_notebook_read_v1(p_note uuid, p_after uuid)`

`p_note=null` iken owner-only tam tarama: `notes` en fazla 20 kayıt; `has_more` ve `next_after`. Tombstone'lar dahildir. `scan_mode=full_scan_restart` bir incremental-change cursor değildir. Sonraki eşitleme null cursor'dan yeniden başlar; sayfada bulunmamak silinme kanıtı sayılmaz. Eşzamanlı eklenen ve cursor'dan önce sıralanan bir UUID sonraki taramada görülür.

`p_note` doluysa tek not ve çözülmemiş conflict'leri okunur. `p_after`, conflict UUID cursor'udur. Her sayfa en fazla 20 conflict; yanıt `has_more_conflicts`, `next_conflict_after` içerir. Not tombstone ise metin null, conflict listesi boştur. Başka hesabın notu ile bulunmayan not aynı `ACCESS_DENIED` sonucunu verir.

## İstemcinin uygulaması gerekenler

Yerel taslak ve mutation UUID ağ isteğinden önce owner'a ayrılmış güvenli depoya yazılmalı. Hesap değişiminde eski hesabın kuyruk ve cache'i yeni hesaba bağlanmamalı. Ağ hatası aynı mutation ile tekrar denenmeli; `VERSION_CONFLICT` veya `NOTE_TOMBSTONED` otomatik yeni mutation üretmemeli. Conflict içerikleri yalnız sahibi için gösterilmeli, log/analytics içine alınmamalı.

Native şifreli kuyruk, sürüm kontrollü okuma, not/çakışma ekranları ve ayrı etiket/checklist API'si eklendi; ayrıntılar [organizasyon ve native sözleşmesinde](notebook-organization-api.md). UI ve sunucu rollout kapalıdır. Hatırlatıcı teslim entegrasyonu ve gerçek istemci uçtan uca kabulü tamamlanmadı. Sunucu API'sinin test edilmesi P13 faz kapanışı sayılmaz.
