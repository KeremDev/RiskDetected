# P05 — Atomik görevlendirme ve üç platform istek bağlantısı

13 Eylül 2026. `8edb64cb` ilişkisel personel adayı üzerine üç bağlı dilim uygulandı: private mutation, iOS/Android/server request doğrulaması ve gerçek server parser → izole PostgreSQL named-argument bağlantısı. **P05 veya production entegrasyonu tamamlanmış değildir.**

## Uygulanan kod

- `scripts/isg/sql/personnel_mutation_fixture.sql`: çalışan üzerinde assignment_version; private write-access, receipt, audit ve outbox tabloları; `move_primary` tek transaction işlemi. Sadece sentetik runner'a eklenir; Supabase migrations dizinine veya canlı sisteme uygulanmaz.
- `App/Services/Company/IsgAssignmentMove.swift`, Android `core/data/.../company/IsgAssignmentMove.kt`: mevcut mutation context'i kullanan saf doğrulama modelleri. Gerçek ana uygulamalarla derlendiler; personel ekranı/SDK yazma servisine bağlanmadılar.
- `supabase/functions/_shared/personnel/assignment-move.ts`: aynı kurallarla parser ve immutable named-argument hazırlayıcı. Yetki kontrolü veya ağ işlemi yapmaz.
- `scripts/isg/personnel_mutation_probe.mjs`: aynı sunucu hazırlayıcısını gerçek izole SQL fonksiyonuyla çalıştırır; sadece test adaptörüdür. İstemci çağrı yolu veya HTTP testi değildir.
- Ortak 61 fixture, Swift kontrol aracı, parametrik Kotlin JUnit, Deno ve üç offline source guard eklendi. CI tetik yolları ile Swift/Deno job'ları genişletildi.

[Alanların tamamı, tarih ve retry sözleşmesi](../../contracts/isg/v1/assignment-move.md).

## Sıra, bağımlılıklar ve güvenlik

```text
company/workplace/personnel ilişkileri
  → request parser + named-argument hazırlığı
  → private mutation: erişim → mutation kilidi → çalışan kilidi → receipt
  → sürüm eşleşmesi → eski tarih aralığı → yeni görevlendirme
  → assignment_version + audit + outbox + receipt
  → commit (veya tamamını rollback)
```

Erişim iptali ve firma/çalışan arşivlenmesi cached success replay'i de engeller. Snapshot istemciden alınmaz; önceki relational trigger'dan gelir. Aynı çalışan üzerindeki 20 version yarışından biri kazanır, 19'u conflict olur. Aynı işlemin 20 retry'ı tek atama/sürüm/audit/outbox/receipt üretir. İki kimlik ayrı aktarılır; operation_id cevaba, client_mutation_id idempotency anahtarına gider.

Yeni dört tabloda RLS açık; anon/authenticated/reader çağrısı ve private journal okuması kapalıdır. Fonksiyon invoker, boş search_path ve kapalı PUBLIC EXECUTE kullanır. Supabase skill'i grants/RLS/EXECUTE sınırlarını ayrı test etmeyi yönlendirdi. GUC aktörü ve `personnel_write_access` **sentetik izin stand-in'idir**: gerçek JWT/session iptali, MFA, paid hak, quota veya gateway uygulanmış sayılmaz. Önceden yapılan gerçek Auth prototipi bu domain'e otomatik bağlı değildir.

Outbox yalnız typed ID/version/event alanları taşır, serbest JSON veya sağlık verisi alanı yoktur. Receipt allowlist domain payload saklar; çalışan adı/sağlık/TCKN yoktur. Bu, her metnin otomatik içerik denetiminden geçtiği anlamına gelmez. Geçici test owner rolü tablo DML yetkisine sahiptir; production'da tüm yazıcıların sürüm/audit protokolünden geçeceği ayrı yetki/migration tasarımıyla sağlanmalıdır.

Outbox kaydı henüz bir eğitim ihtiyacı, push veya belge üretmez. Consumer, lease/receipt bileşimi ve domain event dönüşümü açık. Çalışan yaratma/düzeltme/arşivleme, yeniden işe giriş, taşeron/işveren ilişkisi ve tarihsel düzeltme gerekçesi de bu mutation kapsamında değildir.

## Son yerel doğrulama

| Kontrol | Sonuç ve kapsam |
|---|---|
| İzole PostgreSQL | **99/99** üst seviye kontrol; önceki 78 + yeni 21; legacy oracle grubunda ayrıca329/329 |
| Yeni DB grupları | ACL/RLS; aktör/kapsam; atomik5 yazı; retry; değişmiş payload; stale version; audit/outbox/receipt fault;20 retry/20 version yarışı; revoke/archive; yanlış hedef/tarih; bağlantı öldürme; sonradan replay; sonlu istihdam bitişi; null/overflow;61 corpus hazırlığı; iOS→Android atama/değişim/replay; geçerli payload ile yetki atlanamaması |
| Swift |61/61 ortak fixture |
| Deno |62/62;61 corpus parser+named arguments ve1 ek detached/non-finite kontrol |
| Android |core:data550/550 JUnit,0 failure/error/skip; yeni61 dahil; Debug APK assemble PASS |
| Ana iOS |XcodeBuildMCP Debug/no signing simulator build PASS; gerçek uygulama kaynakları derlendi, launch/login yapılmadı |
| Offline |foundation120/120; nova-design24/24; identity/function-map/CI YAML/whitespace PASS |

Bu sayılar V5'in203 kaynak kabul senaryosunun tamamlandığı anlamına gelmez. Function-map hâlâ dar altı transport dosyasına aittir; yeni domain parser'ı ayrı corpus/guard/runtime bağlantısıyla denendi. CI dosyası yerelde doğrulandı; uzak CI koşusu/push/deploy yapılmadı. Bu tur yeni UI veya emülatör instrumentation testi yoktur; gri tuval/beyaz kart kaynakları değiştirilmedi.

İlk DB koşusunda92 kontrol sonrası bağlantı kaybı testi `DB_CRASH_FIXTURE_NOT_WAITING` ile durdu: test application_name'i PostgreSQL63-byte sınırında kesiliyordu. Runner suffix'i sekiz hex hash'e kısaltıldı. Sonraki94,96 ve son99 kontrolün tümü geçti. Dört koşunun geçici container'ları cleanup PASS ile kaldırıldı; yalnız tekrar üretilebilir sentetik veri vardı. Müşteri verisi/yedek silinmedi. Node26'nın TS import'u yerel üst package.json nedeniyle MODULE_TYPELESS_PACKAGE_JSON uyarısı verdi; kullanıcı package.json dosyası değiştirilmedi, doğrulama başarısız olmadı.

Image ve kaynak SHA-256'ları [kanıtta](evidence/P05_ASSIGNMENT_MUTATION_2026-09-13.json). iOS debugger skill'i ana uygulama build doğrulamasında kullanıldı. Bundle/paket/callback/entitlement değerleri korunmuştur; imzalı mağaza güncelleme testi değildir.

## Devam noktası

Gerçek session/capability sınırını bu domain'e bağlamak; internal sonucu ortak outcome zarfına dönüştürmek; production additive migration ve münhasır yazma yetkileri; departman/görev/çalışan native liste/form/detail ve servis bağlantısı; event consumer; kaynak kabul matrisi ve gerçek iki-platform uçtan uca test. Bu kapılar kapanmadan feature açılmayacak.
