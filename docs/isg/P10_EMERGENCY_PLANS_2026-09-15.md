# Acil Durum Planları — istemci sınırı (P10 dilimi)

15 Eylül 2026. P10 çekirdeği sürümlü planı kurmuştu: yenileme **yalnız işaretçiyi** devrediyor, önceki sürüm kendi kapsamı, ekibi, tarihleri ve dosyasıyla kayıtta kalıyor. Eksik olan istemci sınırıydı — ve `publish_emergency_plan` sahiplik kontrolü taşımıyordu: `module_scope` işyerinin firmaya ait olduğunu kanıtlıyor, **firmanın çağırana ait olduğunu değil**.

Yeni migration `20260915130000_isg_emergency_plans.sql`. **Kendi rollout satırını eklemiyor, hiçbir anahtarı açmıyor**; `modules` özelliğine ve `emergency_plan` modül anahtarına biniyor — ikisi de açık olmadan cevap vermiyor ve **farklı hata veriyorlar** (`FEATURE_UNAVAILABLE` / `MODULE_UNAVAILABLE`).

## Yapısal olarak imkânsız kılınan beş şey

1. **Başka sahibin planına ulaşılamaz**, ve yenileme bu firmanın olmayan bir plana yöneltilemez. İşyeri de `owner_id` ile yeniden doğrulanıyor.
2. **Yenileme öncesini yeniden yazmaz.** Okuma her sürümü kendi ekibi, tarihleri ve kapsamıyla döndürüyor; geçmiş iddia edilmiyor, gösteriliyor. Aynı anda tek sürüm `active`.
3. **Geçerlilik tarihi mevzuat süresi olarak sunulmaz.** Onaylanmış yenileme kataloğu yok; katalog `period_defaults_offered: false` diyor, satır `period_source: expert` taşıyor. Tarihi olmayan plan `period_unknown` okur — `valid` değil.
4. **Dayanağı yazılmamış plan gözden geçirmede kalır.** `needs_review` çekirdek fonksiyonda yazılı dayanağın yokluğundan geliyor; **payload'da böyle bir alan yok**, yayımlanmış sürümü düzenleyen bir işlem de yok. İşaret ancak dayanağı yazılmış yeni bir sürümle geçer.
5. **Ekip anlık görüntüsü serbest JSON olamaz.** Her giriş burada ad ve şemadaki sabit görev kümesinden bir rol için denetleniyor; yalnız `full_name`, `role`, `contact` anahtarlarına izin var. Plana donan şey bir ekip, istemcinin gönderdiği her şey değil.

Ayrıca **yayımlama tek yazma işlemi**. Düzeltme diye bir şey yok: planı düzeltmek bir sonraki sürümü yayımlamaktır ve öncesi her şeyini korur.

## Sunucu yüzeyi

- `private_isg.emergency_plan_receipts`, `private_isg.emergency_team_roles` (5 rol, şemada sabit) — ikisi de RLS açık, sıfır grant.
- `emergency_notice_days()` = 30 — **ürünün kendi uyarı mesafesi**, mevzuat süresi değil; her okumada bildiriliyor.
- `emergency_plan_status(...)` beş durum okuma anında; `emergency_plan_group(...)` dört sayaç.
- `require_emergency_company(...)` — çekirdeğin hiç yapmadığı sahiplik kontrolü.
- `emergency_team_snapshot(...)` — anlık görüntünün şeklini doğrulayan tek yer.
- `emergency_plan_row(...)`, `read_emergency_plans(...)` (`catalog`/`list`/`detail`), `mutate_emergency_plans(...)` (tek işlem: `publish_plan`).
- Public: `isg_emergency_plans_read_v1`, `isg_emergency_plans_mutate_v1` — ikisi de **SECURITY INVOKER**.

## İstemci yüzeyi

Sol menüde **Acil Durum Planları**. Dört sayaç, firma ve durum filtreleri **yan yana**, liste **altta**.

- Satır: kapsam, işyeri/firma, durum rozeti ve **durumun gerekçesi**, hazırlanma/geçerlilik/ekip/sürüm olguları, dayanağı yazılmamışsa ayrı etiket.
- Detay popup'ı: olgular, ekip listesi (ad · görev · iletişim), **tüm sürüm geçmişi her biri kendi ekibiyle**, ve yenileme butonu.
- Yayımlama formu: işyeri seçimi (yenilemede sabit, gösteriliyor), kapsam, hazırlanma ve geçerlilik tarihleri, ekip düzenleyici (ad + şemadaki roller + isteğe bağlı iletişim), dayanak alanı. Ekip boşken buton kapalı.

## Doğrulama

- Disposable PostgreSQL 17: fixture + P10 çekirdeği + bu dilim + `scripts/isg/emergency_plans_check.sql`. **43 kontrol PASS.**
  - İki anahtarın **farklı hata verdiği**; bu modülü açmanın başka modül açmadığı.
  - Başka sahibin firmasının ve başka firmanın işyerinin reddedildiği.
  - Ekip denetimi: nesne olmayan giriş, beklenmeyen anahtar (`tckn`), bilinmeyen rol, adsız giriş ve boş ekip — dördü de reddediliyor.
  - Yarının tarihinin ve başlangıçtan önceki bitişin reddedildiği.
  - Dayanaksız planın gözden geçirmede kaldığı; **işaretin payload'dan set edilemediği**; dayanak yazılınca geçtiği.
  - Tarihin uzmana atfedildiği; ürünün süre önermediği; tarihsiz planın `period_unknown` okuduğu.
  - Sınır günleri: +30 `due_soon`, -1 `expired`, aralıklı olan `valid`.
  - **Yenilemenin öncekini bit bit değiştirmediği** (kapsam, tarihler, ekip JSON'u aynı), eskisinin `superseded` olduğu, tek aktif sürüm kaldığı, geçmişte iki sürüm olduğu, eskisinin **kendi 2 kişilik ekibini**, yenisinin 1 kişilik ekibini taşıdığı.
  - Bilinmeyen plana yöneltilen yenilemenin reddedildiği.
  - İletişimsiz girişin iletişim saklamadığı; dolu girişin tam üç anahtar sakladığı.
  - Sayacın listeyle çelişemediği; **plan başına tek satır, sürüm başına değil**.
  - Replay ve `IDEMPOTENCY_CONFLICT`; kapalı modülün reddettiği; sıfır tablo grant'i; tam iki wrapper.
- `emergency_plans_guard.test.mjs` 13/13, `nova_emergency_plans.test.mjs` 13/13.
- `run_suite.mjs nova-design` 121/119, `foundation` 596/595 — hatalar eşzamanlı oturumun analiz/eğitim dosyalarına ait.
- iOS Debug derlemesi **SUCCEEDED**. 75 yeni katalog anahtarı tr + en; mevcut hiçbir anahtar değişmedi veya kaybolmadı (1899 → 1974).

## Açık kalanlar

- **Sentetik harness aşaması yazılmadı**; disposable PostgreSQL kontrolleriyle doğrulandı.
- **Plan dosyası eklenemiyor.** Çekirdek `p_asset` alıyor ama sınır her zaman NULL geçiyor: istemcinin `file_assets` yolu yok. Ölü yüzey bırakmamak için anahtar allowlist'e konmadı.
- Ekip üyeleri **elle yazılıyor**; firma personel kaydından seçim bu dilimde yok (anlık görüntü olduğu için bağ kurulmuyor, ama seçim kolaylığı ayrı bir iş).
- Tatbikat kaydı bu plana bağlanmadı — `drill_records` planın sürümüne FK taşıyor, o modül ayrı dilim.
- Yaklaşan/dolmuş plan için bildirim üretilmiyor.
- Rollout ve modül anahtarı **açılmadı**; canlı pilot bundle'ı ayrı adım.
- Android'de karşılığı yok.
