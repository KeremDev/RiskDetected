# Ana görevlendirme isteği — v1 aday sözleşmesi

13 Eylül 2026. Uygulanan parser ve izole SQL işlemine aittir; yayınlanmış HTTP/RPC endpoint değildir. `fixtures/assignment-move.json` üç platformun ortak 61 vakasıdır.

## Alanlar

Kök nesne yalnız aşağıdaki altı alanı içerir; hepsi zorunludur. Bilinmeyen alanlar reddedilir. `previous_assignment_id` zorunlu olmasına rağmen ilk görevlendirmede açıkça `null` olmalıdır.

| JSON yolu | SQL adlandırılmış argümanı | Kural |
|---|---|---|
| context.operation_id | p_operation | İşlem kimliği; retry boyunca sabit |
| context.client_mutation_id | p_mutation | Aktör kapsamında idempotency anahtarı; operation_id'den ayrı tutulur |
| context.scope.company_id | p_company | company scope zorunlu; yetki kanıtı değildir |
| context.scope.workplace_id | p_workplace | Bu domain'de zorunlu hedef işyeri |
| context.expected_version | p_expected | 0…9007199254740990; sonraki sürüm de JS safe integer sınırında kalır |
| employee_id | p_employee | Aynı şirketteki çalışan |
| previous_assignment_id | p_previous | İlk atamada null; değişimde kısaltılacak aynı çalışan/şirket ataması |
| department_id | p_department | Aynı firma ve hedef işyerindeki departman |
| job_role_id | p_job | Aynı firmadaki görev |
| starts_on | p_on | ASCII YYYY-MM-DD, gerçek Gregoryen gün, yıl 0001…9999 |

`context` ayrıca ortak transport modelinin `schema_version=1`, `platform=ios|android`, `client_build=1…2147483647` alanlarını taşır. Bu üç alanın doğrulaması yapılır; platform/build business payload veya SQL yetkisi değildir. İsim, snapshot, bitiş tarihi, user_id, tier, sağlık bilgisi ve keyfi metadata kabul edilmez.

UUID'ler küçük harfli, standart tireli, RFC variant, sürüm 1–8 biçimindedir. `operation_id` ve `client_mutation_id` alanları eşit olmak zorunda değildir; farklılık şartı da konulmaz. Birini diğerinin yerine geçirmek yasaktır. Ortak geçerli örnekler kasıtlı olarak farklı kimlikler kullanır.

## İşlem semantiği

```text
JSON → ortak kurallarla doğrulama → değişmez named-argument nesnesi
     → [GERÇEK AUTH/CAPABILITY GATE HENÜZ BAĞLI DEĞİL]
     → izole private move_primary
       aktör/izin + firma + çalışan erişimi
       → aynı mutation anahtarı kilidi → önceki receipt kontrolü
       → expected_version → eski [başlangıç,bitiş) aralığını kısalt
       → yeni atama + sürüm + audit + outbox + receipt → tek commit
```

SQL erişim kontrolü ve çalışan kilidi receipt okunmadan önce yapılır. Aynı anahtar/aynı business payload eski cevabı döndürür; arada başka görevlendirme yapılmış olması o cevabı değiştirmez. Aynı anahtarın başka operation_id, kapsam, sürüm, tarih veya hedefle kullanılması `IDEMPOTENCY_CONFLICT` olur. Platform/build değişimi business payload değişikliği sayılmaz. Yeni anahtarla eski sürüm `VERSION_CONFLICT` olur. İşlem anahtarının actor kapsamı mevcut izole tabloyla sınırlıdır; domain'ler arası production namespace sözleşmesi açık iştir.

Yeni kayıt bir önceki atamanın hariç bitiş sınırını korur; ilk atama çalışanın hariç istihdam bitişini kullanır. Hareket tarihi eski başlangıçtan büyük ve varsa eski bitişten küçüktür. Yeni geçerli aralık için FK, arşiv, istihdam ve çakışma kontrolleri DB'de tekrar uygulanır. Bölüm/görev snapshot'ını sunucu kaydeder. Hiçbir hata eski atamayı tek başına kısalmış bırakamaz.

Başarı iç sonucu yalnız `schema_version`, `operation_id`, `employee_id`, `assignment_id`, `version` içerir. Bu iç sonuç henüz genel mutation-outcome zarfı değildir. Native response parser, HTTP hata/sonuç adaptörü, çevrimdışı gönderim kuyruğu ve servis çağrısı bağlı değildir. Sadece JSON parsing, SQL argüman hazırlama ve izole işlem kanıtı vardır; parser başarısı asla authorization anlamına gelmez.
