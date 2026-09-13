# Devir notu — İSG geçişinde sunucu dilimlerini sürdürmek

14 Eylül 2026. Bu belge, bu depoda İSG geçişini **devralacak bir sonraki geliştirici veya ajan** içindir. Neyin bittiğini, neyin açık olduğunu, hangi kalıbın izlendiğini ve hangi tuzaklara düşüldüğünü tek yerde toplar.

## 1. Nerede duruyoruz?

P05 (firma/işyeri/personel) daha önce kapanmıştı. 13–14 Eylül'de eklenen sunucu dilimleri:

| Faz | Dilim | Migration | Faz dokümanı |
|---|---|---|---|
| P01/P03 | Olay dağıtım defteri + gölge kota defteri | `20260913110000`, `20260913113000` | [P01_P03](P01_P03_DISPATCH_AND_QUOTA_2026-09-13.md) |
| P04 | Dosya kabul matrisi, karantina, anti-TOCTOU promotion | `20260913130000` | [P04](P04_FILE_CORE_2026-09-13.md) |
| P06 | Mevzuat kaynağı, sürümlü kural, tarihli yükümlülük | `20260913150000` | [P06](P06_RULE_CORE_2026-09-13.md) |
| P07 | Eğitim kataloğu, yoklama birleşimi, değişmez tamamlanma | `20260913170000` | [P07](P07_TRAINING_CORE_2026-09-13.md) |
| P08 | Risk sürümleme ve tarih disiplini | `20260913190000` | [P08](P08_RISK_VERSIONING_2026-09-13.md) |
| P09 | Uygunsuzluk durum makinesi ve checklist | `20260913210000` | [P09](P09_NONCONFORMITY_CORE_2026-09-13.md) |
| P10 | §7.5 modülleri, iki paket hâlinde 12 başlık | `20260913230000`, `20260914010000` | [P10-1](P10_MODULE_CORE_2026-09-13.md), [P10-2](P10_MODULE_SECOND_2026-09-14.md) |
| P11 | Belge numarası/snapshot/export + import zinciri | `20260914030000` | [P11](P11_DOCUMENT_IMPORT_CORE_2026-09-14.md) |
| P12 | Bildirim omurgası, rıza kökeni, sahiplik/shadow, gönderim-anı kapısı | `20260914050000` | [P12](P12_NOTIFICATION_CORE_2026-09-14.md) |
| P13 | Kişisel not defteri, çakışma/tombstone, occurrence, teslim sahibi | `20260914070000` | [P13](P13_PERSONAL_NOTES_2026-09-14.md) |

Toplam: `private_isg` şemasında **107 tablo**, hepsinde RLS açık, istemciye **sıfır** GRANT. Sentetik kabul koşusu **716/716 PASS**, tam legacy kopya upgrade **29/29 PASS** (16 migration), offline foundation **240 PASS**.

**Canlıya hiçbir şey uygulanmadı.** Bütün yeni `private_isg.rollout` satırları ve on iki modül anahtarı kapalı; mağaza, canlı DB, legacy kota otoritesi ve mevcut istemci sözleşmeleri değişmedi.

## 2. Değişmez kurallar

1. **Rollout kapalı doğar.** Migration hiçbir yerde `UPDATE private_isg.rollout SET ...` yapmaz; açma işi ayrı ve insan kararıdır.
2. **İstemciye GRANT yok.** Yeni fonksiyonlar `anon`/`authenticated`/`service_role` için EXECUTE almaz; sadece P05'in mevcut altı istemci RPC'si granted kalır. Yeni tablo eklerken `REVOKE ALL ON ALL TABLES IN SCHEMA private_isg ...` satırını tekrarla.
3. **Her tabloda RLS.** `CREATE TABLE` sayısı ile `ENABLE ROW LEVEL SECURITY` sayısı eşit olmalı; guard testleri bunu sayar.
4. **Her fonksiyonda `SET search_path=''`** ve tam nitelikli isimler.
5. **Onaylanmamış sayı, onaylanmış gibi durmaz.** V5'ten gelen limit/süre/eşik değerleri `*_needs_review` veya `content_approved=false` / `period_source='unapproved_fixture'` gibi açık bir işaretle saklanır.
6. **"İddia edilmeyecek" şeyler CHECK ile imkânsız yapılır**, varsayılan değerle bırakılmaz. Örnek: `CHECK(NOT official_integration)`, `CHECK(NOT authorises_work)`, `CHECK(NOT ai_text_is_official_record)`, `CHECK(authority='shadow')`.
7. **Legacy'ye yazılmaz.** `public.findings`, `public.analyses`, `public.reports` ve legacy kota helper'ları okunmaz/yazılmaz; yalnız referans taşınır.
8. **Takvim aritmetiği.** Yıl 365 güne, ay 30 güne çevrilmez; `private_isg.next_due_on` ve `make_interval` kullanılır.
9. **Bilinmeyen ≠ hayır.** Eksik kanıt `needs_review`/`review` üretir, sessizce "gerekli değil" olmaz.

## 3. Yeni bir dilim nasıl eklenir? (sırayla)

1. `supabase/migrations/<YYYYMMDDHHMMSS>_isg_<konu>.sql` — tablolar, indeksler, RLS, fonksiyonlar, `REVOKE`, `NOTIFY pgrst`. Yeni rollout özelliği ekliyorsan `rollout_feature_check` kısıtını **drop/add** et.
2. `scripts/isg/<konu>_probe.mjs` — `begin<Konu>Probe({synthetic,sql,concurrentSql,companyID,ownerID,pass})`, `synthetic!==true` ve eksik scope'ta **SQL'e dokunmadan** hata fırlatır. İçeride `CREATE SCHEMA isg_<x>_test` + sabit dağıtımlı `observe(kind,args)` fonksiyonu (dinamik SQL yok), sonra `mark(...)` kontrolleri.
3. `scripts/isg/<konu>_guard.test.mjs` — offline: mod reddi, rollout'un migration'da açılmaması, GRANT olmaması, tablo/RLS sayısı, domain kuralının kaynakta durması, runner bağı.
4. `scripts/isg/run_suite.mjs` — guard testini `foundation` paketine `push` et.
5. `scripts/isg/run_auth_restore.mjs` — import, `let <x>Probe;`, `stage='...'` ile çağrı (**`personnel-advisors` aşamasından önce**), `report.<x> = ...afterLogout()`, `source_sha256` listesine `.concat(mode.synthetic ? <x>Files : [])`.
6. `scripts/isg/p05_upgrade_probe.mjs` — migration'ı `p05UpgradeFiles` sonuna ekle, tablo sayısı ve rollout sayısı beklentilerini güncelle, yeni defterlerin boş replay edildiğini doğrula.
7. `.github/workflows/isg-foundation.yml` — migration yolunu **iki** `paths` bloğuna da ekle.
8. `scripts/isg/personnel_advisor_probe.mjs` — yeni tabloları `denyTables`'a, koşudan sonra rapor edilen `unused_index` anahtarlarını `reviewedFKIndexes`'e ekle.
9. Koş: sentetik → upgrade → foundation. Sonra `contracts/isg/v1/<konu>.md`, `docs/isg/<FAZ>_....md`, `docs/isg/evidence/<FAZ>_....json`, `EXECUTION_STATUS.md`, `GUNCEL_DURUM_2026-09-13.md`, ana plan satırı; en sonda commit.

## 4. Tekrar eden tuzaklar (hepsi bu turda gerçekten yaşandı)

| Belirti | Kök neden | Çözüm |
|---|---|---|
| `column reference X is ambiguous` veya sessiz yanlış eşleşme | plpgsql değişken adı sütun adıyla aynı (`scope`, `activity`, `version`, `row`, `state`, `position`, `local`) | Değişkeni yeniden adlandır (`contract_scope`, `label`, `revision`, `entry`, `next_state`, `ordinal`) |
| SQLSTATE **2201B** (invalid_regular_expression) | PostgreSQL regex tekrar sayısını **255** ile sınırlar; `{5,500}` geçersiz | Uzunluğu ayrı `length(...) BETWEEN` kontrolüne al |
| JSON `null` gönderilen alan "dolu" sayılıyor | `a->'field'` jsonb `null` döner, SQL NULL değil | Observe'da `nullif(a->'field','null'::jsonb)` kullan |
| SQLSTATE **42883** (undefined_function) | `date + bigint` operatörü yok | Sayıyı `integer` yap |
| Beklenmedik **CHECK_VIOLATION** | Hata kodu regex'i rakam kabul etmiyordu (`EXCEL_1900_LEAP_BUG`) | `^[A-Z][A-Z0-9_]{2,n}$` |
| `record "x" is not assigned yet` | Record değişkenine yalnız bir koşul dalında `SELECT INTO` yapılmış | Skaler değişken kullan veya koşulsuz ata |
| btree index satır boyutu riski | Uzun `text` sütunu UNIQUE anahtarında | `md5(sütun)` üzerinde unique index |
| Advisor aşaması kırmızı | Yeni tablolar/indeksler review listelerinde yok | `personnel_advisor_probe.mjs`'deki iki listeyi güncelle; gerçek FK indeks eksiğini **düzelt**, listeye ekleme |
| Python `str.replace` ile kod düzenlerken sayı bozulması | `"count(*)=3"` deseni `"count(*)=30"` içinde de eşleşti | Daha uzun/benzersiz desen seç, sonra `grep` ile doğrula |
| Kapı sırası varsayımı | Faz kapısı modül anahtarından **önce** cevap verir | Önce `FEATURE_UNAVAILABLE`, sonra `MODULE_UNAVAILABLE` bekle |
| Yalnız **bir kod yolunda** patlayan gölgeleme | Değişken adı sütun adıyla aynı ama o satıra sadece bazı dallarda ulaşılıyor (`route`) | `route`, `state`, `version`, `purpose`, `scope`, `position` gibi adları baştan kullanma |

## 5. Komutlar

~~~bash
node scripts/isg/run_auth_restore.mjs --synthetic-session          # tam sentetik kabul (Docker gerekir)
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade # tam legacy kopyada migration replay
node scripts/isg/run_suite.mjs foundation                          # offline guard/contract testleri
node scripts/isg/run_suite.mjs capacity-shadow|nova-design|password-auth
deno test --allow-read=contracts/isg/v1/fixtures supabase/functions/_shared/isg/mutation-context_test.ts supabase/functions/_shared/isg/mutation-outcome_test.ts
~~~

`--isolated-copy --p05-upgrade` modu `isg_restore_20260912_db` etiketli, ağsız restore container'ının **kopyasını** kullanır; kaynak container'a yazmaz. Sentetik mod müşteri verisine hiç dokunmaz. Her iki mod da geçici container'ları temizler; cleanup başarısızsa koşu yeşil sayılmaz.

## 6. Sıradaki işler

1. **P12'nin ikinci dilimi:** gerçek APNs/FCM/e-posta adaptörleri, onboarding rıza ekranı ve izin durumları, simulate/shadow/canary, gerçek cutover. P01'in dağıtım defteri hâlâ gerçek bir tüketici bekliyor.
2. **P04'ün ikinci dilimi:** gerçek AV/parser sandbox'ı, DOC/XLS pozitif güvenlik fixture'ları, bucket/storage policy, signed URL. Teknoloji ve maliyet kararı gerekiyor.
3. **P11'in render worker'ı:** PDF/XLSX üretimi ve görsel kabuller.
4. **P14 lifecycle/store**, **P15 referral**, **P16 admin**, **P17 skor**: bağımlılıkları planın §15.1 grafiğinde. P13'ün sunucu tarafı bitti; istemci senkron motoru ve cihaz tarafı zamanlama kabulleri açık.
5. **P18/P19/P20:** native kabuk, bütünleşik prova, mağaza güncellemesi. Bunlar insan onayı ve gerçek cihaz kanıtı isteyen kapılar.

Her fazın kendi dokümanında "Açık kalanlar" bölümü vardır; bir fazı kapatmadan önce oradaki maddeleri kontrol et. Hiçbir faz, kendi dokümanı "kapandı" demeden kapalı sayılmaz.
