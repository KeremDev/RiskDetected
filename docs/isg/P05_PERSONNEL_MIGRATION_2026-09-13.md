# P05 — gerçek şema migration ve HTTP/RPC dilimi

Tarih: 13 Eylül 2026. **Yerelde doğrulanan ilk backend dilimi; P05 bütünü ve üretim açılışı tamamlanmadı.**

## Kapsam

`supabase/migrations/20260913074153_isg_personnel_owner_rpc.sql`, CLI `migration new` ile oluşturuldu. Dosyanın aynısı izole PostgreSQL 17.6 üzerinde çalıştırılır; test sırasında migration metni dönüştürülmez. Önceki `isg_personnel_fixture` tablolarından ayrıdır.

Bu ilk migration, mevcut `public.companies`, `public.user_subscriptions` ve `private.user_plan_tier` ile çalışır. Test bootstrap'ı mevcut firma/abonelik DDL ve helper tanımlarını kaynak migration'lardan aynen alır; `profiles` bağımlılığı minimaldir. Bu nedenle **tam mevcut uygulama şemasının restore/upgrade kanıtı değildir**.

## Veri modeli

| Yeni özel tablo | İşlev ve temel alanlar |
|---|---|
| `private_isg.rollout` | `feature=personnel`, `read_enabled`, `write_enabled`; başlangıçta ikisi de kapalı; yazma okuma olmadan açılamaz |
| `workplaces` | Firma/owner composite FK, ad/adres/tehlike sınıfı başlangıç kopyası, nullable timezone/jurisdiction, `needs_review`, arşiv, version, unique legacy company marker |
| `departments` | Firma/owner/workplace, kod, ad, arşiv; firma/işyeri/kod tekil; compound FK başka firmanın işyerini engeller |
| `employees` | Firma/owner, otomatik kod, ad soyad, isteğe bağlı intake department, nullable işe giriş/çıkış, kayıt zamanı, record version, arşiv |
| `personnel_receipts` | Actor+mutation anahtarı, operation/firma, normalize talep SHA-256 özeti, önceki sonuç, kayıt zamanı |
| `personnel_audit` | Event/operation/firma/actor/personel/sürüm/işlem; personel+sürüm tekil; personelin adı audit payload'ına kopyalanmaz |
| `personnel_outbox` | Audit event bağlantısı, create/update/archive türü, şema sürümü1, zaman; consumer henüz yok |
| `workplace_initializations` | Varsayılan işyeri oluşturuldu kaydı; aynı transaction |

Sekiz tabloda RLS açık. `anon`, `authenticated`, `service_role` doğrudan tablo yetkisi yok. RLS politikası olmaması bu özel tablolar için bilerek default-deny anlamındadır; owner kontrolleri denetlenen RPC girişindedir. Tam sütun/constraint/index tanımı migration dosyasındadır.

Bu tablolar henüz tarihli görevlendirme, işyeri context geçmişi, departman hiyerarşisi, görev kataloğu ve işveren/taşeron ilişkisini içermez. Önceki aday test modelindeki bu özellikler bu migration'a uygulanmış sayılmaz. `intake_department_id` basit personel girişi içindir; görevlendirme geçmişi entegrasyonunda tarih/snapshot guard'ları taşınmadan aynı endpoint genişletilmemelidir.

## Akış ve yetki sınırı

```text
Yerel gerçek GoTrue login / refresh → imzalı access token
  → PostgREST (yalnız public şema, authenticator → authenticated)
  → public.isg_personnel_read_v1 / isg_personnel_mutate_v1 [INVOKER]
  → private_isg.read_personnel / mutate_personnel [kontrollü DEFINER]
      → token sub/role/session/exp + auth.uid uyumu
      → gerçek auth.sessions + auth.users satırı; silinmiş/banned/anonymous reddi
      → rollout kilidi
      → yazmada mevcut Plus/Pro etkin hak ve abonelik satırı kilidi
      → firma owner kontrolü; yazmada aktif firma kilidi
      → okuma: 50 satır + UUID cursor / tek personel
      → yazma: normalize talep → aynı anahtar receipt → expected version
          → isteğe bağlı yeni departman + personel
          → audit → outbox → receipt → tek COMMIT
```

Özel yardımcıların tamamında sabit boş `search_path` bulunur. Client'a yalnız iki kontrollü private giriş ve iki public wrapper için EXECUTE verilir. Service-role, anonim rol, doğrudan tablo, private schema HTTP ve private yardımcı RPC yolları açık değildir. `user_metadata` / profil tier yetki kaynağı değildir.

Yazma için mevcut sistemde `plus/pro` ve `active/trialing/grace_period`, ayrıca gelecekte veya NULL bitiş kabul edilir. `expired/paused/billing_issue/inactive/cancelled`, geçmiş dönem bitişi ve free reddedilir. Bu, **mevcut legacy helper ile uyum** dilimidir; P03'ün yeni fiyat, grandfather floor, şirket kapasitesi ve plan revizyonlarının tamamlandığı anlamına gelmez. Owner free'e düştüğünde mevcut personeli okumaya devam edebilir.

Client'ın SQL claim ayarlaması desteklenen bir yol değildir. SQL test harness'i önceden imza doğrular. Ayrıca gerçek HTTP testi, GoTrue token'ını PostgREST'e gönderir; PostgREST imzayı doğrular, SQL gerçek oturum kaydını tekrar kontrol eder. Logout sonrası kriptografik olarak geçerli token ile okuma/yazma/receipt replay reddedilir.

## RPC sözleşmesi

Ortak sunucu eşleyicisi: `supabase/functions/_shared/personnel/rpc-request.ts`. Kaynak payload doğrulanmadan RPC adı/argümanı üretilmez. Owner/session inputtan alınmaz.

| RPC | Parametreler / sonuç |
|---|---|
| `isg_personnel_read_v1` | `p_company,p_kind,p_query,p_archived,p_after,p_id`; employees/departments için `{rows,next}`, detail için tek satır |
| `isg_personnel_mutate_v1` | `p_company,p_action,p_operation,p_mutation,p_employee,p_expected,p_name,p_change_department,p_department,p_department_name` |
| Mutation sonucu | `schema_version,operation_id,employee_id,owner_id,company_id,version,is_archived` |

Create: ad soyad yeterli; personel ve kod otomatik, expected0, tarihler NULL. Departman boş/mevcut/yeni olabilir. Yeni ad firma içinde normalize Türkçe eşleşmeyle yeniden kullanılır; birden fazla eşleşme varsa açık seçim istenir. Ad benzerliği çalışan birleştirmez.

Edit: eski sürüm şart; adı değiştir, departmanı koru/boşalt/seç/oluştur. Archive: fiziksel silme değil, sürüm artışı ve arşiv bayrağıdır. Arşivlenmiş personelin create receipt'i tekrar başarı olarak sunulmaz; archive receipt'i yetki devam ettiği sürece aynen dönebilir. Aynı mutation anahtarının farklı talebe verilmesi conflict'tir. Uygulama kapanması sonrası güvenli anahtar kurtarma henüz bu backend diliminin parçası değildir.

Hatalar: `AUTH_REQUIRED`, `FEATURE_UNAVAILABLE`, `PAID_PLAN_REQUIRED`, `ACCESS_DENIED`, `VALIDATION_ERROR`, `VERSION_CONFLICT`, `IDEMPOTENCY_CONFLICT`, `DEPARTMENT_SCOPE_INVALID`, `DEPARTMENT_SELECTION_REQUIRED`. Bunlar PostgREST hata gövdesinden tam kod eşleşmesiyle çevrilmeli; açıklama substring'i yetki kanıtı olarak kullanılmamalıdır.

## Backfill ve geri alma

- Başlangıçta eski firma satırları değiştirilmez; her firmaya tek default workplace oluşturulur. Bilinmeyen timezone/jurisdiction uydurulmaz, inceleme gerekir.
- Eski binary yeni company eklediğinde AFTER INSERT aynı initializer'ı çalıştırır; rollout kapalıyken de default oluşur. Mevcut firma kapasite helper/trigger tanımı değiştirilmez.
- Bu yeni AFTER INSERT trigger legacy INSERT transaction'ına bağımlılık ekler: initializer hatası tüm firma INSERT'ini geri alır. Büyük backfill süresi/kilit etkisi ve tam legacy akışlar ayrıca ölçülmelidir.
- İşyeri başlangıç kopyası firma ad/adres/tehlike sınıfının sürekli canlı aynası değildir. Sonraki değişiklikler tarihli context akışı tamamlanmadan geçmişi güncellememelidir.
- Bütün migration tek transaction'dır; kilit bekleme limiti5 saniye. Yarım başarısız migration rollback olur. Tüm migration ikinci kez körlemesine uygulanmaz; initializer tekrarında UUID değişmez.
- Açılış sonrası uygulama seviyesinde geri dönüş: önce yeni yazmayı kapat, gerekirse okumayı da kapat; tabloları/drop ile silme. Receipt/audit/outbox ve kullanıcı kayıtlarını koru. Eski sürüme dönmek veri şemasını otomatik geriye indirmek değildir.
- Firma fiziksel silinirse yeni grafın tamamı cascade ile temizlenir. İzole testte bu davranış ve diğer firmanın korunması doğrulandı; gerçek hesap silme/retention sürecinin tam kabulü ayrıca açık.

## Test kanıtları ve sınırlar

Son koşu bilgileri ve kaynak hash'leri eşlik eden `evidence/P05_PERSONNEL_MIGRATION_2026-09-13.json` dosyasındadır.

| Son doğrulama | Sonuç |
|---|---|
| Gerçek yerel Auth + migration + PostgREST + Advisor | **221/221**; önceki148 + migration52 + HTTP18 + Advisor3 |
| Supabase Advisor | Yeni schema için ERROR/WARN0; gözden geçirilmiş8 default-deny INFO; tüm sentetik ortam55 bulgu, tamamı temiz diye sunulmaz |
| Ayrı aday SQL regresyonu |135/135; içindeki legacy kapasite oracle329/329 |
| Node foundation |159/159 |
| NOVA tasarım/kaynak regresyonu |24/24 |
| Deno RPC eşleyici type check |PASS |
| Bundle/package/Auth callback/entitlement kaynak kontrolü |PASS; imzalı binary/store kanıtı değil |

Başarılı son Auth run: `4545dd35-6fba-4bd6-bc97-e84ae4ed0984`; SQL regresyon run: `72bfdb37-366b-4b12-b325-0ab6b4ae14a1`. İki koşuda geçici container cleanup PASS. Bu tur native uygulama kodu değiştirilmedi; iOS/Android build/UI testleri yeniden çalıştırılmış gibi sayılmaz.

Migration testleri: varsayılan kapalı erişim, gerçek sahiplik, abonelik10 durum matrisi, metadata sahteciliği, oturum iptali, ad-only/NULL tarihler, Türkçe departman tekrar kullanımı, audit/outbox/receipt hata enjeksiyonunda tam rollback,20 eşzamanlı edit'te tek kazanan, abonelik iptal kilidi,50/50/5 sayfalama, literal arama, arşiv filtreleri, backfill/catch-up/UUID korunması, firma silme cascade, private ACL/search-path.

HTTP testleri: gerçek token ve sahte imza, anonim istek, create/retry/conflict/list/detail/departments/edit/stale/archive; özel şema/tablo/fonksiyona erişim yasağı; logout sonrası read/write/replay reddi. Kong/API-key, rate limit, TLS, mobil SDK ve gerçek müşteri verisi kullanılmadı.

Dört geçici container aynı `network=none` alanında; port/mount yok; tam ID+label doğrulanır ve yalnız koşunun kendi container'ları temizlenir. Advisor kontrolü yalnız bu test DB'ye özel0700 dizin/0600 Unix socket köprüsünden bağlanır; TCP listener açılmaz, readonly DB rolü kullanılır, köprü/dizin kapanışta temizlenir. Üretim DB URL, Keychain, backup kaynağı veya müşteri oturumu kullanılmaz.

İlk abonelik-kilit gözlem testi aktif statement yerine tüm transaction metnini aradığı için başarısız oldu; benzersiz `application_name` ile gözlem düzeltildi, veri kuralı değiştirilmedi. Geçmiş başarısız koşular PASS olarak sayılmaz.

Advisor'ın ilk iki denemesi boş URL host'unun CLI tarafından reddedilmesi nedeniyle başarısızdı. Explicit URL host ve Unix socket `host` parametresiyle bağlantı doğrulandı. Advisor üç eksik company/owner FK indeksini buldu; migration'a eklendi. Özel sekiz default-deny tablo için `rls_enabled_no_policy` INFO notları bilerek korunur; çözüm olarak client'a tablo erişimi açılmaz. Gate yalnız bu açıkça gözden geçirilmiş tablo/not eşleşmelerine izin verir; yeni başka bulgu koşuyu başarısız yapar. Sentetik/legacy fixture ortamının diğer bulguları yeni şemanın temizliği olarak sunulmaz.

## P05 devam noktası

1. Tam mevcut schema restore üzerinde migration/upgrade ve Advisor sonuçları; büyük backfill, tüm legacy firma CRUD/hesap silme ve kontrollü rollback tatbikatı.
2. iOS/Android gerçek Supabase servis adaptörleri + scope/epoch doğrulaması + kalıcı pending işlem kurtarma. Mevcut NOVA UI hâlâ sentetik test deposunda; üretim kökü değiştirilmedi.
3. Tarihli workplace context, departman hiyerarşisi/görev/işveren ilişkisi ve assignment geçmişini gerçek şemaya/API/UI'a taşıma; P01/P03 tam bileşim.
4. REV01/21/23, DAT04/05, X07/12/13 tam uçtan uca kabul kapısı. P05/P06 tamamlandı işaretlenmez.

## Resmi teknik başvurular

API şema/parametre doğrulaması için [PostgREST14 yapılandırması](https://docs.postgrest.org/en/v14/references/configuration.html) ve [RPC işlevleri](https://docs.postgrest.org/en/v14/references/api/functions.html); CI kurulumu için [resmi Supabase CLI action](https://github.com/supabase/setup-cli) incelendi. Supabase becerisi; CLI sürümü/dokümantasyon kontrolü, özel schema/ACL, gerçek session kontrolü ve Advisor kapısını bu çalışmaya dahil etti.
