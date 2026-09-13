# P05 — Departman, görev, çalışan ve tarihli görevlendirme

13 Eylül 2026. `00e6d560` varsayılan işyeri provası üzerine eklenen **izole ilişkisel aday**. V5 §5.1–5.4 ve geçiş planı §7.1 esas alındı. Production migration, API veya iOS/Android personel ekranı değildir; P05 tamamlanmadı.

## Veri modeli ve kapsam

Yeni kaynak `scripts/isg/sql/personnel_fixture.sql`, önceki `isg_workplace_fixture` şemasına dört tablo ekler. Gerçek `companies`, Auth, Storage veya müşteri kayıtları değişmez.

| Tablo | Alanlar / ana kurallar |
|---|---|
| `departments` | UUID, company/owner/workplace UUID, code, name, is_archived. Kod şirket+işyeri içinde tekil; firma-sahip ve firma-işyeri bileşik FK |
| `job_roles` | UUID, company/owner UUID, code, title, is_archived. Kod firma içinde tekil |
| `employees` | UUID, company/owner UUID, employee_code, full_name, hired_on, employment_ends_before, is_archived. Kod firma içinde tekil, isim benzersiz değil |
| `employee_assignments` | UUID, company/owner/employee/workplace/department/job UUID, kind, starts_on, ends_before, üretilmiş effective_dates, department_name_snapshot, job_title_snapshot. Bağlantılar bileşik FK; yalnız primary |

Kodlar şu adayda tam metin ve büyük/küçük harf duyarlı eşitlik kullanır; ön/son normal boşluk reddedilir. Türkçe case-fold/Unicode normalizasyon politikası henüz belirlenmedi. Arşivleme kodu boşa çıkarmaz; başka kayıtla sessiz birleşme yapılmaz.

`department_refs` önceki testin minimal FK taşıyıcısı olarak kalır; yeni `departments` tablosu ondan veri kopyalamaz. Üst departman, görev açıklaması/eğitim/KKD linkleri, çalışma ilişkisi türü, iletişim, işveren/taşeron ilişkileri, yeniden işe giriş dönemleri ve düzeltme gerekçesi henüz eklenmedi.

## Tarih ve geçmiş kuralları

```text
Firma → işyeri → departman
   ├→ görev
   └→ çalışan → [başlangıç, bitiş) ana görevlendirme
                   ├ tarihli departman/unvan snapshot'ı
                   └ aynı çalışanın bütün işyerleri boyunca çakışma yasağı
```

Teknik tarihler `DATE`; `ends_before` ve `employment_ends_before` **hariç üst sınırdır**. Örneğin `[2026-01-01, 2026-02-01)` Ocak ayını kapsar, 1 Şubat'ı kapsamaz. Bitiş NULL ise süre açık uçludur. Bu, henüz tasarlanmamış kullanıcı ekranındaki “son çalışma günü” için verilmiş karar değildir; oradaki dahil/hariç dönüşüm açıkça ele alınmalıdır.

- Başlangıç sonlu ve zorunludur; bitiş varsa sonlu ve başlangıçtan büyük olmalı. Sıfır/ters aralık, ±infinity ve işe giriş öncesi görevlendirme reddedilir. Sonlu istihdam dönemini aşan veya buna rağmen açık uçlu görevlendirme kabul edilmez.
- `daterange(...,'[)')` + GiST exclusion constraint aynı çalışanın farklı işyerlerinde dahi çakışan ana görevini veritabanında engeller. Tarihsel aralıklar da kapsamdadır; geçmiş kaydı pasifleştirerek çakışma kuralını delme alanı yoktur. [PostgreSQL range ve exclusion kuralları](https://www.postgresql.org/docs/17/rangetypes.html).
- Yalnız `primary` kabul edilir. Yardımcı/secondary görev politikası belirlenene kadar reddedilir; çoklu görevlendirme serbest bırakılmaz.
- Görevlendirme başlarken çalışan satırı kilitlenir; istihdam tarihi değişikliği de mevcut aralıkları ters yönde doğrular. Denemeler varsayılan READ COMMITTED izolasyonunda yapıldı; bütün transaction isolation seviyeleri için kanıt değildir.
- Yeni görevlendirme arşivlenmiş firma/işyeri/çalışan/departman/göreve eklenemez. Arşivleme geçmişi silmez. Arşivli çalışanın mevcut açık görevi kapatılabilir.
- Ad/unvan snapshot'ı istemciden kabul edilmez, gerçek departman/görev kaydından alınır. Sonraki isim değişikliği eski snapshot'ı değiştirmez. Bu, eğitim sertifikası/PDF snapshot testi değildir; yalnız görevlendirme kaydıdır.
- Görevlendirme kimliği, kapsamı, başlangıcı ve snapshot'ı değişmez. Bitiş kapatılabilir veya kısaltılabilir; kapanmış aralığı yeniden açma/uzatma ayrı düzeltme akışı gelene kadar engellenir. Geçmiş düzeltme, reason/audit ve expected_version ile ayrıca tasarlanacak.
- Eski aralığı kısaltıp yeni aralığı ekleyen tek transaction denendi. Yeni kayıt başarısızsa veya commit öncesi DB bağlantısı öldürülürse eski aralığın kısalması da geri alınır. Domain audit/outbox/idempotency henüz bu dört tabloya bağlanmadı.

## Güvenlik ve veri sınırı

Dört tabloda RLS ve yalnız sahip kapsamlı SELECT vardır. Test reader'ına INSERT/UPDATE/DELETE verilmez. Trigger fonksiyonları `SECURITY INVOKER`, boş search_path ve kapalı PUBLIC EXECUTE kullanır. Sahipliği uyduran kayıtları composite FK'ler engeller; aynı uzmanın başka firmasına ait çalışan/görev ve aynı firmanın yanlış işyerindeki departman da reddedilir.

Supabase skill'i nedeniyle grants ile RLS ayrı denetlendi; [resmi RLS rehberi](https://supabase.com/docs/guides/database/postgres/row-level-security) izlendi. `request.jwt.claim.sub` test girdisidir: gerçek JWT doğrulama, oturum iptali, MFA, paid hak, quota veya API authorization uygulanmış sayılmaz. Yazma testleri private tablonun NOLOGIN/NOSUPERUSER/NOBYPASSRLS sahibi rolünde yapılır; bu rol production API rolü değildir.

Sağlık/T.C. kimlik numarası alanı veya serbest JSON payload eklenmedi. Bu yapısal kontrol, kullanıcının bir isim alanına uygunsuz metin girmesini otomatik tespit ettiği iddiası değildir. Metin/import/telemetry içerik korumaları ayrı yapılacak. Referanslı çalışan, departman ve görev silinemez; hesap silme/retention akışı henüz bağlanmadı.

## Doğrulama

Son yerel koşu: **78/78 üst seviye DB kontrolü** (önceki 52 + yeni 26), legacy oracle grubunda ayrıca 329/329 varyasyon. Offline foundation **117/117**, nova-design **24/24**, identity ve whitespace PASS. Mobil kod değişmedi; önceki turdaki mobil derleme/test sonuçları bu tur yeniden koşulmuş gibi sunulmuyor.

Yeni 26 grubun kapsamı: ACL/RLS; isim/kod kapsamı; owner/workplace FK; server snapshot; yabancı şirket çalışan/görev; departman–işyeri eşleşmesi; geçmiş/future çakışma; bitişik aralık/29 Şubat; sıfır/ters/sonsuz tarih; işe giriş/çıkış sınırları; istihdam tarihi editinin ters doğrulaması; secondary reddi; açık uç; 20 paralel çakışma (1 kabul,19 exclusion); 20 ayrı çalışanın paralel başarısı; rename/snapshot değişmezliği; referanslı silme; beş tür arşivli parent; atomik görev değişimi; hata rollback; arşiv sonrası kapama; yabancı owner görünmezliği; gerçek DB bağlantısı öldürme/retry; sağlık alanı yokluğu; yeniden açma/uzatma reddi; 10 istihdam tarihi–görevlendirme yarışında kapsam korunumu.

İlk koşu PER-09'da beklenen hata katmanının farklılığı nedeniyle durdu: `-infinity` başlangıç CHECK'ten önce işe giriş aralığı guard'ında reddedildi. Assertion doğru `EMPLOYMENT_INTERVAL_INVALID` olarak düzeltildi; kabul kuralları gevşetilmedi. Sonraki 77/77 ve ek yarışlı son 78/78 geçti. Üç koşunun geçici container'ları cleanup PASS ile kaldırıldı; yalnız yeniden üretilebilir sentetik verileri içeriyordu.

Image aynı SHA-256 ile sabit kaldı; yerelde paketli `btree_gist` **1.7** kaydedildi. Uzaktan extension indirme veya canlı upgrade yapılmadı. [btree_gist UUID/GiST desteği](https://www.postgresql.org/docs/17/btree-gist.html) ve [Supabase extension sürümü değişimi](https://supabase.com/changelog/extension-version-pinning-ignored) kontrol edildi; CREATE EXTENSION'a sürüm argümanı verilmedi.

Mevcut CI database job'u yeni SQL/probe kaynaklarını çağırır ve hash'ler; foundation'a üç statik koruma testi eklendi. Uzak CI/push/deploy yapılmadı. Komut: `node scripts/isg/run_database_contract.mjs contracts/isg/v1/local-test-environment.example.json`.

## Sonraki entegrasyon

Gerçek migration/index/lock bütçesi, Auth/capability + mutation idempotency/version/audit/outbox bileşimi, personel yeniden işe giriş/taşeron ilişkileri, üst departman, batch import ve gizlilik, native DTO/servis/CRUD ekranları, görev değişiminden eğitim ihtiyacı önerisi ve geçmiş belge snapshot'ları açık. Yeni görevlendirme otomatik eğitim/sertifika üretmez. P05 kaynak kabul senaryolarının tamamı geçmiş sayılmaz.

[Koşu/hash kanıtı](evidence/P05_PERSONNEL_FOUNDATION_2026-09-13.json).
