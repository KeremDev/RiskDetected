# Faz 2 Tamamlama Denetimi — 2026-07-28

## Kapı sonucu

**Faz 2: TAMAMLANDI**

Bu karar execution planındaki “Additive veri modeli ve dual backend contract”
fazının teknik kabulüdür. Production migration uygulanmadı, migration history
repair yapılmadı ve Edge Function deploy edilmedi. Faz 3 iOS localization
uygulaması bu denetimden önce başlatılmadı.

## Faz önkoşulu: migration defteri — PASS

Faz 0'da belirlenen `remote history authoritative + exact statement
reconstruction + kanıtlı local-only state attestation` modeli uygulandı:

- 110 production migration kaydı canonical aktif geçmiş olarak kuruldu.
- 41 eski local-only migration kanıt manifestiyle arşivlendi.
- Aynı sürüm numarasındaki iki semantic divergence'ın local kopyası arşivlendi,
  remote statement canonical dosya oldu.
- Production'da bulunup canonical geçmişte temsil edilmeyen schema durumu
  `20260728201500` forward migration'ına dönüştürüldü.
- Canlı feature flag ve plan capability durumu `20260728202000` ile
  tekrar üretilebilir hale getirildi.
- Localization migration'ı `20260728203000` olarak yalnız bu iki kapıdan sonra
  eklendi.
- Aktif defter 113 migration'dır; duplicate ve unexpected version sayısı 0'dır.
- `supabase migration list --linked`: 110 eşleşen remote kayıt, yalnız üç
  beklenen local forward migration, remote-only kayıt 0.

Kanıt:
`docs/localization/baseline/MIGRATION_LEDGER_AFTER_RECONCILIATION_2026-07-28.json`.

## Veri modeli denetimi

| Plan işi | Durum | Kanıt |
| --- | --- | --- |
| Nullable additive alanlar | PASS | 7 tabloda 46 nullable alan |
| Idempotent Türkçe backfill | PASS | 7 bounded `LIMIT 500` döngüsü; yeniden çalıştırmada yalnız eksik alanları tamamlıyor |
| Analiz snapshot otoritesi | PASS | `analyses.localization_snapshot`; scalar/snapshot eşleşme trigger'ı |
| Snapshot immutability | PASS | trusted writer dışında ilk yazma reddi; kurulduktan sonra snapshot ve otorite alanları immutable |
| Rapor snapshot alanları | PASS | Faz 5 report uygulaması için nullable ve immutable kopya contract'ı hazır |
| Notification/support alanları | PASS | event, private job ve support hedefleri additive olarak genişletildi |
| Validation alanları | PASS | analysis ve AI usage üzerinde status/attempt/code alanları |
| CHECK geçiş modeli | PASS | 32 CHECK `NOT VALID`; yeni yazıları koruyor, dual-read telemetry tamamlanmadan zorunlu validation yok |
| İndeksler | PASS | analysis/report user-profile-created indeksleri |
| Feature flags | PASS | 11 flag migration'da `rollout_mode=off`; `ON CONFLICT DO NOTHING` |

Migration:
`supabase/migrations/20260728203000_global_localization_context_wave1.sql`.

## Backfill güvenliği — PASS

Read-only production cardinality:

| Hedef | Satır | 500'lük batch |
| --- | ---: | ---: |
| `public.profiles` | 95 | 1 |
| `public.analyses` | 128 | 1 |
| `public.reports` | 126 | 1 |
| `public.ai_usage_logs` | 128 | 1 |
| `public.notification_events` | 290 | 1 |
| `private.notification_jobs` | 1 | 1 |
| `public.support_requests` | 1 | 1 |

Backfill:

- yalnız null/eksik localization alanlarını tamamlar;
- mevcut snapshot'ı değiştirmez;
- historical TR kayıtları açıkça `tr`, `tr-TR`, `TR`,
  `tr-tr-current-v1` olarak etiketler;
- AI metnini, rapor dosyasını veya kullanıcı mesajını çevirmeye çalışmaz;
- support kullanıcısının yazdığı mesajın dilini tahmin etmez.

Kanıt:
`docs/localization/phase-2/PRODUCTION_BACKFILL_CARDINALITY_2026-07-28.json`.

## Dual backend contract denetimi

Yeni shared modüller:

- `supabase/functions/_shared/localization-contract.ts`
- `supabase/functions/_shared/safety-profile-manifest.ts`
- `supabase/functions/_shared/regulatory-reference-policy.ts`
- `supabase/functions/_shared/localization-context-resolver.ts`

`analyze` contract'ı:

- `output_language`
- `output_locale`
- `work_jurisdiction_country`
- `work_jurisdiction_region`
- `safety_profile_id`
- `safety_profile_version`
- `method`

alanlarını typed resolver üzerinden kabul eder.

Eski istemci alan göndermediğinde açık TR default snapshot oluşturulur. Yeni
istemci altı profile ait geçerli context kurabilir. Profile version, locale,
country, method veya persisted snapshot uyuşmazlığı stable code ile fail
closed olur.

## Atomiklik ve queue otoritesi — PASS

- Snapshot quota reservation ve queue enqueue'dan önce analysis satırına
  conditional/atomic olarak yazılır.
- Eşzamanlı istek kaydı tekrar okuyup persisted snapshot'ı otorite kabul eder.
- Worker, retry ve coverage repair request body'sinden context türetmez;
  `analyses.localization_snapshot` değerini yeniden yükler.
- Queue geçişi `localization_queue_payload_v1` flag'i altındadır.
- Queue mesajına tam snapshot kopyalanmaz; yalnız gerekli guard metadata'sı
  yazılır.
- Migration-first / function-deploy aralığında yalnız legacy, localization
  otoritesi taşımayan in-flight worker TR snapshot'ı bir kez kurabilir.
- Mevcut claim, lease, ambiguous dispatch, exact coverage repair ve
  finalization invariants korunmuştur.

## Türkiye dışı legislation gate — PASS

Non-TR profile + legislation canvas:

1. AI çağrısından önce,
2. snapshot persist ve quota reservation'dan önce,
3. queue enqueue'dan önce

`CANVAS_NOT_AVAILABLE_FOR_SAFETY_PROFILE` ile reddedilir. Backend Türkçe
kullanıcı mesajı üretmez; istemci stable code'u kendi dilinde gösterecektir.

## Schema ve temiz reset denetimi — PASS

- Canonical remote geçmiş + `20260728201500` sonrasında local schema dump,
  production baseline ile byte-identical:
  `4576c3577deaceede660d9969c5d63b8f35baeec74e25cc0544b85dda9a181ea`.
- Runtime attestation ve localization dahil 113 migration boş local veritabanına
  sıfırdan başarıyla uygulandı.
- Son schema: 11.340 satır, 395.533 byte,
  SHA-256 `3ac171aeee06e0de538eb7b3c7acdf7a51ebe9ca93847a094f54504820ed92e2`.
- Production farkı 493 satırdır; tamamı beklenen additive localization
  column/check/function/trigger/comment/index farkıdır.
- `public` ve `private` schema lint sonucu hata 0'dır.

## Çıkış kriteri denetimi

### Eski build Türkçe analiz yapabilir — PASS

Legacy request ve legacy in-flight worker testleri açık TR snapshot üretir.
Nullable dual-read alanları eski insert contract'ını bozmaz.

### Yeni build altı profile ait snapshot oluşturabilir — PASS

TR, International English, GB, US, AU ve CA profile request'leri aynı manifest
hash'i üzerinden resolve edildi. Locale/country/profile/version/method
uyuşmazlıklarının tamamı reddedildi.

### Snapshot retry/repair boyunca değişmez — PASS

Resolver testi persisted snapshot'ı request'e üstün tutar. DB trigger'ı
snapshot ve denormalized otorite kolonlarında mutation'ı
`LOCALIZATION_SNAPSHOT_IMMUTABLE` ile reddeder. Worker/retry/repair static
contract testleri aynı DB snapshot'ını yeniden yüklediğini doğrular.

### Non-TR legislation quota tüketmez ve job oluşturmaz — PASS

Gate çağrı sırası static test ile quota/queue/AI öncesinde sabitlendi. Resolver
altı profile ve legislation varyantını test eder; non-TR varyant stable code ile
reddedilir.

### pgTAP/RLS testleri geçer — PASS

- pgTAP: 6 dosya, 223 assertion, 0 hata.
- Localization pgTAP: 88 assertion.
- Faz 2 hedefi 7 tabloda mevcut RLS durumu korunur.
- `anon`, `private.notification_jobs` okuyamaz.
- Authenticated client authoritative snapshot kuramaz.
- Service-role snapshot kurabilir; malformed/mismatch/immutable değişiklikler
  reddedilir.

## Regresyon sonucu

- Deno: 188/188.
- `analyze/index.ts` type-check: PASS.
- Localization profile contract: 17/17.
- İçerik envanteri: 2.397; sahipsiz P0/P1: 0.
- Hard-coded localization guard: yeni aday 0.
- Xcode Debug build/run: warning 0, error 0.
- Tam iOS UI: 39 test, 38 pass, 1 planlı skip, 0 failure.
- Planlı skip: gerçek provider ve açık dış test ortamı gerektiren
  `testE2ERealThreePhotoAnalysisCompletes()`.
- `git diff --check`: PASS.

İlk tam UI koşumundaki dört fixture/selector hatası kapatıldı:

- sahte UI photo Storage yolları artık yalnız DEBUG/UI-test modunda
  deterministik yerel JPEG üretir;
- photo tray fixture, asenkron plan capability çözümünden sonra iki fotoğrafı
  deterministik tamamlar;
- PDF preview kapatma kontrolü stable `document_preview.close` identifier'ı
  taşır;
- onboarding testi gerçek button query'si kullanır.

Ayrıntılı makine kanıtı:
`docs/localization/phase-2/PHASE_2_TEST_MANIFEST_2026-07-28.json`.

## Production ve faz sınırı

- `supabase db push` çalıştırılmadı.
- Migration history repair yapılmadı.
- Production DDL/DML/backfill uygulanmadı.
- Production feature flag değeri değiştirilmedi.
- Edge Function deploy edilmedi.
- App Store Connect mutation yapılmadı.
- İnsan language/safety/product approval durumu yükseltilmedi.
- Faz 3 iOS localization altyapısı bu kapanıştan önce başlatılmadı.

## Bir sonraki izinli adım

Yalnız Faz 3 iOS localization altyapısı ve ülke güvenlik deneyimi açılabilir.
Faz 4 AI localization işi, Faz 3'ün bütün iş listesi ve çıkış kriterleri ayrı
bir tamamlama denetiminde PASS olmadan başlatılamaz.
