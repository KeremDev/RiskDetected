# P03 ilk dilim — eski şirket hakkı ve gölge geçiş hesabı

12 Eylül 2026. **Hiçbir canlı limit, abonelik, fiyat, katalog, floor veya RLS kuralı değiştirilmedi.** Bu dilim test ve read-only değerlendirmedir. Tasarım ve ticari onaydan bağımsız hazırlanabilen güvenlik temeli öne alınmıştır.

## Sabitlenen mevcut davranış

`private.user_plan_tier` aktif hakkı `user_subscriptions` üzerinden bulur: Plus/Pro, active/trialing/grace_period ve bitişi NULL veya `now()` sonrasında. Sonuç yoksa Free'dir. Dolayısıyla `profiles.tier` paid görünse bile bu helper Free dönebilir. `private.company_limit_for_user` profil mevcutsa canonical Free/Plus/Pro için 0/5/25 döner; profil yoksa NULL döner. Profil etiketine fallback gibi görünen COALESCE dalı, `user_plan_tier` normal durumda NULL dönmediği için paid hakkı tek başına geri vermez.

329 sentetik SQL varyasyonu geçti: 3 profil etiketi × (eksik abonelik + 3 subscription tier × 9 status × 4 bitiş durumu) ve eksik profil/null-user. NULL, geçmiş, tam sınır anı ve gelecek bitiş ayrı sınandı. Gövdeler tarihli migration'lardan yalnız ilgili fonksiyon olarak çıkarılır; tüm eski migration körlemesine çalıştırılmaz. Test public tabloları yeni, no-network container'da yaratılır, RLS ve explicit revoke uygulanır ve tüm fixture transaction'ı rollback olur. [Kanıt](evidence/P03_LEGACY_CAPACITY_MATRIX_2026-09-12.json).

Bu, mevcut SQL truth table'ının kanıtıdır; yeni P03 otoritesinin veya gerçek RevenueCat/store E2E'nin kanıtı değildir. Ham status `cancelled/canceled` SQL'de paid sayılmaz. Bunun kullanıcı aboneliğini iptal eder etmez hak kaybetmesi anlamına geldiği varsayılmaz: mevcut RevenueCat webhook CANCELLATION dahil ilgili olaylarda subscriber state'i yeniden doğrulayıp erişim devam ediyorsa DB status'unu active yazar. O handler'ın store/backend hata ve retry matrisi P14'te ayrıca sınanacak.

## Gölge karar modeli

Kaynak: `scripts/isg/company_capacity_shadow.mjs`. Sadece saf fonksiyon; ortam değişkeni, network, DB write veya kullanıcı kimliği yoktur. `publishable=false` her sonuçta sabittir. Gerçek API authorization'da kullanılamaz.

| Girdi | Anlam / kanıt ihtiyacı |
|---|---|
| billing_state | verified_paid / verified_free / sync_pending; client veya stored profile tier değil |
| eligibility | eligible / ineligible / unknown; onaylı rollout cutoff ve geçmiş hak kaydı |
| legacy_contract | Son onaylı eski sözleşme hakkı: finite / unlimited / unknown |
| existing_floor | Daha önce kazanılmış koruma; belirsizse sıfır sayılmaz |
| candidate_capacity | Aday yeni kapasite; sayı modelden dayatılmaz; Plus3/Pro30 sadece deneme girdisi |
| active_company_count | Mevcut aktif şirket sayısı; archived kayıtlar bu sayı değildir |
| protected_active_company_count | Geçerli olduğu doğrulanmış, korunacak aktif kullanım; yetkisiz fazla kullanım otomatik kazanılmış hak sayılmaz |

Doğrulanmış paid hesapta aday floor = önceki floor, aday kapasite, geçerli kullanım ve eligible ise eski sözleşme hakkının maksimumu. Unlimited ayrı etiketle korunur. Unknown gerekli kanıtlar review gerektirir; subscription sync pending Free'ye çevrilmez.

Free hesapta kazanılmış eski floor saklanır, fakat etkin yeni şirket yazma kapasitesi 0'dır. Yeni paid aday kapasitesi Free hesaba gelecekte kullanılacak bir hak olarak da kaydedilmez. Gift ve indirim bu fonksiyonun girdisi değildir; onlardan gerçek paid entitlement türetilmez. Hiçbir durumda fazla şirket silme önerisi üretilmez. Read-only excess sayısı sadece UI/karar tasarımına teknik öneridir; bugünkü production okuma RLS'sini değiştirmez ve kullanım hakkı yaratmaz.

17 Node test grubu ve 864 sonlu kapasite kombinasyonu geçti. Ek örnekler: eski Plus kullanımı 0/1/3/5; Pro25→aday30; eski yüksek floor; geçerli yüksek kullanım; unlimited; downgrade; pending sync; bilinmeyen cutoff; geç uygulama güncellemesi; bozuk sayı/alan; client owner/tier/gift alanı reddi. Paylaşılan native DTO kapsamı değildir; native hak UI'si henüz bağlanmadı.

## Yedek verisi üzerinde read-only karşılaştırma

`read_legacy_capacity_snapshot.mjs` yalnız `isg_restore_20260912_db` etiketli, ağsız, portsuz, mountsuz restore'u kabul eder. Production'a bağlanmaz. SQL transaction `READ ONLY`'dir. UUID/e-posta/firma ismi değil, sadece kümelenmiş sayılar çıkartılır. Restore'daki iki fonksiyon gövdesi migration oracle'ıyla karşılaştırıldı; eşleşti.

208 profil snapshot'ında canonical 6 Plus ve 3 Pro; stored Plus olup canonical Free olan 1 kayıt bulundu. Canonical Free'de de önceden kalmış şirket kayıtları vardır. Bu nedenle ne mevcut şirketleri silmek ne de görünüm etiketinden hak taşımak güvenlidir.

Örnek karşılaştırma yalnız varsayım olarak mevcut snapshot paid gruplarını eligible kabul eder: Plus gruplarında floor 5, Pro gruplarında aday floor 30 çıkar. Bu kayıtlar DB'ye yazılmadı. Cutoff, gerçek geçmiş eligibility, istisnalar, protected usage provenance ve mağaza/RC reconciliation tamamlanmadan backfill yapılmaz. Snapshot tarihi bugün olsa bile bu çıktı **canlı güncel abonelik kanıtı değildir**. [Sayılar ve varsayımlar](evidence/P03_CAPACITY_SHADOW_SNAPSHOT_2026-09-12.json).

## Sonraki P03 işleri

1. Canlı store/RC katalog ve subscription/lifecycle kaynaklarını read-only tamamla; RLS/paid helper/Edge/native/admin call-site envanterini çıkar.
2. Eligibility cutoff ve yeni ticari parametrelerin insan onayını al; geçmiş/late-update kullanıcıları kapsayan server-side kalıcı floor tasarla.
3. Adet, AI, report ve storage kotaları için kaynak/periyot/funding-source ayrımını tamamla; eski sayaçlar otorite kalırken yeni reservation ledger'ı shadow olarak karşılaştır.
4. Gerçek migration, concurrency, RLS/API ve native read-only UI testlerini izole ortamda tamamla. Şirket trigger'ındaki mevcut count kontrolünü yeni atomik rezervasyonla değiştirme ancak açık migration/cutover testinden sonra yapılır.
5. P00/P01 kapıları ve ticari kararlar kapanmadan publish/rollout yok.

~~~bash
node scripts/isg/run_suite.mjs capacity-shadow
node scripts/isg/run_database_contract.mjs contracts/isg/v1/local-test-environment.example.json
node scripts/isg/read_legacy_capacity_snapshot.mjs
~~~
