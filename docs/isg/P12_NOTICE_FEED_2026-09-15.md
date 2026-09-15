# P12 · Başlık çubuğundaki bildirim çanı (notice feed)

Tarih: 2026-09-15 · Dal: `codex/isg-transition-foundation`

## Ne eksikti

Çan ikonu başlıkta duruyordu ama ölüydü. Üç ayrı sebepten:

1. `NovaPilotRoot`'un `available` kümesinde `.notifications` yoktu, dolayısıyla
   `navigation.canOpen(.notifications)` false dönüyor ve buton `.disabled(true)`
   kalıyordu.
2. `NovaExpertShell`'e `notificationItems` / `hasUnread` / `onReadAll` /
   `onClearNotifications` hiçbir çağıran tarafından verilmiyordu; panel her
   zaman "Yeni bildirim yok" gösteriyordu.
3. `.notifications` hedefinin içeriği yoktu; `default` dalına düşüp "Bu modül
   hazırlanıyor" yazıyordu.

Arka tarafta da bir "gelen kutusu" yoktu. `private_isg.notification_*`
tabloları **push kuyruğu**: `delivery_attempts` şema düzeyinde
`delivery_confirmed`/`read_confirmed` sütunlarını `CHECK(NOT ...)` ile yasaklar.
Uygulama içi liste için hiçbir okuma yüzeyi yoktu.

## Ne yapıldı

`supabase/migrations/20260915240000_isg_pilot_notice_feed.sql`

Bildirimler **okuma anında hesaplanır**. Hiçbir bildirim metni, önem derecesi
veya tarihi saklanmaz; saklanan tek şey okuyucunun kendi işaretleridir.

Yapısal olarak imkânsız kılınan beş iddia:

1. **Hiçbir bildirim, push gönderildiğini/iletildiğini/okunduğunu söylemez.**
   Dosya hiçbir teslimat tablosunu okumaz (guard testi bunu `delivery_attempts`,
   `notification_jobs`, `notification_episodes`, `notification_consents` için
   ayrı ayrı doğrular) ve hem okuma hem yazma zarfı
   `push_delivery_claimed: false` taşır.
2. **Silmek kaydı silmez.** Dosyadaki tek `DELETE` hedefi `notice_marks`.
   Silme, *durumu* gizler: anahtar `kind:record_id:due_on` biçiminde olduğu için
   tarih değişince bildirim yeni bir durum olarak geri gelir ve eski işaret
   budanır. Zarf `dismiss_is_permanent: false` der.
3. **Tarih uydurulmaz.** Her kaynak kendi tarihini `IS NOT NULL` ile şart koşar;
   süresiz sözleşme veya geçerlilik tarihi olmayan plan hiç bildirim üretmez.
4. **Başka hesabın kaydına erişilemez.** Her kaynak `c.user_id=p_actor` ile
   birleşir ve `p05_pilot_can_read` süzgecinden geçer.
5. **Kapalı modül bildirim üretmez**, yani çan hesabın açamayacağı bir yüzeyi
   işaret edemez. `risk` ve `document_tracking` kendi rollout anahtarlarına,
   diğer on tür `modules` + `module_registry` çiftine bakar.

Okunan on kaynak ve pencereleri: risk değerlendirmesi 60 gün, İSG-KATİP /
atama / acil durum planı / periyodik kontrol 30 gün, tatbikat / yıllık plan işi
/ kurul toplantısı 14 gün, kurul kararı 7 gün, evrak ise **yükümlülüğün kendi
`notice_days` değeri**. Periyodik kontrolde ve evrakta yalnızca **en yeni**
kayıt sayılır.

İstemci sınırı iki fonksiyon:

- `public.isg_pilot_notice_feed_v1(p_company, p_scope, p_limit)` — `active`,
  `unread`, `all`
- `public.isg_pilot_notice_mark_v1(p_action, p_keys)` — `read`, `read_all`,
  `dismiss`, `dismiss_all`, `restore`

Toplu eylemler liste almaz (`PAYLOAD_NOT_ALLOWED`), listede olmayan anahtar
reddedilir (`NOTICE_NOT_FOUND`), böylece tablo serbest depolama olarak
kullanılamaz.

### iOS

| Dosya | Ne |
|---|---|
| `App/DesignSystem/ISG/NovaNotices.swift` | Türler, önem derecesi, cümleler (`noPushNote`, `dismissNote`) |
| `App/DesignSystem/ISG/NovaNoticeCenterScreen.swift` | Bildirim Merkezi sayfası |
| `App/Services/Company/NovaNoticeService.swift` + `NovaNoticeLiveAdapter.swift` | Taşıma ve ret eşlemesi |
| `App/Views/Components/NovaPilotNoticeGate.swift` | Kompozisyon kökü |
| `App/DesignSystem/ISG/NovaExpertShell.swift` | Çan rozeti (sayı), satır başına oku/sil/geri al |
| `App/Views/Components/NovaPilotMainGate.swift` | Besleme, `.notifications` rotası, işaretleme |

Bildirime dokunmak onu okumuş sayar ve ilgili modüle götürür. Hiçbir işaret
yerel olarak uygulanmaz: her yazmadan sonra sayılar sunucudan yeniden istenir.

Katalog: 38 yeni anahtar (tr + en), `isg_notice_feed` comment'i ile.

## Doğrulama

| Ne | Sonuç |
|---|---|
| `scripts/isg/notice_feed_check.sql` (tek kullanımlık Postgres 17, canlı şema biçimli fixture) | **54/54 geçti** |
| `scripts/isg/notice_feed_guard.test.mjs` | **14/14 geçti** |
| `scripts/isg/nova_notices.test.mjs` | **8/8 geçti** |
| iOS derlemesi | **YAPILAMADI** — `xcodebuild` ve `git` "You have not agreed to the Xcode license agreements" diyor; `sudo xcodebuild -license accept` gerekiyor |

Her iki test de `scripts/isg/run_suite.mjs` içine bağlandı (`foundation` ve
`nova-design`).

## Canlı pilota uygulandı — 2026-09-15

`mcp__supabase__apply_migration` ile proje `ppcrzemgiztzcgddbins` üzerinde
uygulandı. Atanan sürüm **`20260915053021`** (dosya adı `isg_pilot_notice_feed`
olarak istendi; canlı sistem kendi zaman damgasını verdi — yerel dev
migration'ın adıyla aynı değil).

- Aynı SQL, `supabase/pilot-release/supabase/migrations/20260915053021_isg_pilot_notice_feed.sql`
  altına aynalandı (dosya adı canlının verdiği sürüm numarasıyla).
- SHA256: `4728e6fce33ea051e1a58a1e6aa03f4e8c404b735e8c317dff095f16c3480c34`
- Önceki canlı head: `20260914230601` (`isg_pilot_checklist_plan_board`)
- `private_isg.require_company` MD5'i değişmedi: `f9de5f413afb0d33e022b04b9923c3f5`
  (bu dosya onu hiç tanımlamıyor/dokunmuyor)

**Bir divergence, ilk uygulamada bulundu ve düzeltildi:** yerel Docker
fixture'ımda `board_decisions.decision_no` sütununu `text` varsaymıştım; canlı
şemada `integer`. UNION ALL'daki diğer dokuz kaynak `title` alanı `text`
döndürdüğü için ilk `apply_migration` çağrısı
`42804: UNION types text and integer cannot be matched` ile reddedildi. Fix:
`t.decision_no::text`. Fixture, check ve guard testi de düzeltilip yeniden
doğrulandı (54/54, guard artık 14/14 — yeni test bu cast'i doğruluyor), sonra
ikinci `apply_migration` çağrısı `{"success":true}` döndü.

- Client sınırı canlıda doğrulandı: `notice_marks` tablosuna
  `anon`/`authenticated`/`service_role` hiçbir GRANT taşımıyor; `authenticated`
  yalnız `isg_pilot_notice_feed_v1` ve `isg_pilot_notice_mark_v1`'i çağırabiliyor
  (`information_schema.routine_privileges` sorgusu: `count=2`).
- Bu bir **deploy**, bayrak açma değil: canlı proje `supabase/migrations`
  zincirini değil, elle hazırlanmış pilot paketlerini taşıyor
  ([[live-project-runs-on-pilot-bundles]]).

## Bekleyenler

- **iOS derlemesi yapılmadı.** Xcode lisansı kabul edilmeden derleme mümkün
  değil. Swift tarafı derlenene kadar doğrulanmış sayılmaz — SQL canlıda
  çalışıyor olsa da istemci hâlâ derlenmemiş durumda.
- Android karşılığı yok.
- Push tarafı hâlâ kapalı ve bu iş onu açmaz; bu liste telefon bildirimi
  değildir.

## Bu turda benim olmayan kırmızılar

- `nova_localization.test.mjs`: `NovaNavigation.swift` içinde
  `localizable.nova.drawer.group.` interpolasyonlu anahtar hiçbir katalogda
  tanımlı değil; ayrıca `NovaNavigation.swift:48-51`, `NovaComponents.swift:400`
  ve `NovaCompanyManagementGate.swift` satırlarında ham Türkçe literal var.
- `localization_catalog_tests.mjs` L10N-001: altı `nova.drawer.*` anahtarının
  `comment` alanı yok.
- `nova-design` paketinde 5 kırmızı: `nova_analysis_flow` (2),
  `nova_emergency_plans` (`publish_plan` artık serviste yok),
  `nova_ppe_handovers` (2 — `NovaPilotPPEGate` yeniden yazılmış).
