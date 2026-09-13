# P05 — Varsayılan işyeri ve firma kapsamı provası

13 Eylül 2026. Native firma loader commit'i `e5c85286` sonrasındaki veri bağımlılığı dilimi. V5 §5.1 ve geçiş planı §6.3 temel alınır. **Bu bir izole PostgreSQL aday şeması/testidir; production migration, gerçek backfill veya tamamlanmış personel modülü değildir.**

## Uygulanan aday

`scripts/isg/sql/workplace_fixture.sql` yalnız `isg_workplace_fixture` şemasını kullanır. Gerçek `public.companies` değiştirilmez. `legacy_companies` sentetik kaynak; `workplaces` aday hedef; `department_refs` yalnız composite FK test taşıyıcısıdır. Gerçek departman/çalışan/görev modellerinin yerini tutmaz.

```text
Eski firma UUID'si
  → şirket satırını transaction boyunca kilitle
  → legacy_company_id zaten varsa aynı işyeri UUID'sini döndür
  → yoksa bilinen ad/adres/hazard/archive alanlarını kopyala
  → işyeri + audit + outbox birlikte commit
  → sonraki backfill/catch-up aynı kaydı bulur
```

- `legacy_company_id UNIQUE` retry ve paralel catch-up için tek kayıt anahtarıdır; firma adı birleştirme anahtarı değildir. Arşivlenmiş varsayılan kayıt da bu anahtarı korur.
- Aynı firmaya farklı hazard sınıfında başka işyerleri eklenebilir. Adları aynı olsa bile UUID'leri ve kapsamları farklıdır.
- `(company_id, owner_id)` bileşik FK yanlış uzmanı; `(company_id, workplace_id)` referansı aynı uzmanın farklı firmaları arasındaki ilişki hatasını engeller.
- Bilinmeyen tehlike sınıfı `NULL`, jurisdiction `NULL`, `needs_review=true`. Bilinmeyen alanlara Türkiye veya orta tehlike sınıfı uydurulmaz. Bu bayrağın varlığı bir mevzuat değerlendirmesi değildir.
- İlk kopya sonrasındaki retry yeni işyeri adını/sınıfını/sürümünü geri yazmaz; eski şirket verisini de değiştirmez. `companies.department` serbest metninden otomatik departman kurulmaz.
- Kullanılmış işyeri silme ve firma sahipliği transferi FK ile engellenir. Gerçek hesap silme/retention ve olası transfer akışı ayrıca tasarlanacak; CASCADE ile geçmişi silme eklenmedi.
- Başlatıcı `SECURITY INVOKER`, private ve yalnız test sahibi rolünden kullanılabilir. Client `anon`/`authenticated` veya test reader'ına execute verilmez. Reader yalnız kendi işyerlerini okuyabilir; doğrudan yazamaz, kaynak/audit/outbox okuyamaz.
- Test RLS'sindeki `request.jwt.claim.sub` yalnız doğrulanmış öznenin **sentetik stand-in** değeridir; JWT, `auth.sessions`, MFA, paid capability veya gerçek API kontrolünü uygulamaz. Worker'ın tablo sahibi olması production yetkilendirme tasarımı sayılmaz.

## Test ve güvenlik sonucu

Son PostgreSQL 17.6 koşusu: **52/52 üst seviye kontrol** = önceki 30 transaction + 1 legacy oracle grubu + yeni 21 işyeri kontrolü. Legacy oracle grubunda ayrıca 329/329 eski tier/limit varyasyonu var; bunlar yeni işyeri testi sayılmaz. Offline foundation 114/114, nova-design 24/24, diff whitespace PASS. Mevcut CI database job'u yeni probe'u da çalıştırır; uzak CI bu turda çalıştırılmadı.

İşyeri kontrolleri: tüm tablolar RLS; private function/reader ACL; doğru alan kopyası; tekrar; 20 paralel çağrı; unknown context; archive; iki owner + aynı owner iki şirket; INSERT/UPDATE/DELETE reddi; iki bileşik FK; aynı isim/farklı tesis; duplicate marker; eksik/NULL firma; audit ve outbox hata enjeksiyonu; backfill sonrası eski istemci benzeri yeni firma ve catch-up; yeni işyeri bağlamını/eski satırları koruma; context/version negatifleri; referanslı silme/owner transfer reddi; gerçek DB bağlantısını commit öncesi öldürme ve başarılı retry.

İlk tur WP-01'de fonksiyon ACL beklentisi düştü: şema düzeyindeki default-privilege REVOKE global PUBLIC EXECUTE'ı çıkarmaz. Aday rolün global varsayılanı kapatıldı ve fonksiyonlara açık REVOKE eklendi. Sonraki 20/20 ve bağlantı kaybı eklenmiş son 21/21 turlar geçti. Bu düzeltme yalnız yeni sentetik şemadadır; production'da böyle bir açık bulunduğu iddia edilmez. Davranış [PostgreSQL 17 default privileges belgesi](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html) ile doğrulandı.

Supabase kılavuzu nedeniyle güncel changelog ve [RLS/GRANT ayrımı](https://supabase.com/docs/guides/database/postgres/row-level-security) kontrol edildi. Yeni tablo erişiminin otomatik kabul edilmemesi gerektiği [Data API değişim kaydında](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically) da belirtiliyor. Bu test Data API kullanmaz ve API'ye tablo açmaz. Mevcut image digest korunur; [PG 15→17 varsayılan geçişi](https://supabase.com/changelog/46080-self-hosted-supabase-upgrading-from-pg-15-to-17-breaking-change) nedeniyle sürüm yükseltme yapılmadı.

## İzolasyon ve kalan işler

Mevcut `run_database_contract.mjs` yeni, run-label'lı container oluşturur: network none, yayınlanan port/host mount yok, image pull yok, sentetik veri. Her SQL'den önce kimlik/izolasyon kontrolü vardır; yalnız bu koşunun tam container ID'si kaldırılır. Başarısız ve başarılı üç koşuda cleanup PASS. Kaldırılanlar sadece yeniden üretilebilir test veritabanlarıdır; müşteri yedeği veya başka container silinmedi.

Komut: `node scripts/isg/run_database_contract.mjs contracts/isg/v1/local-test-environment.example.json`.

Sonraki işler: gerçek eski tabloyla additive migration/index/lock bütçesi ve source hash provası; gerçek Auth/session+capability bileşimi; batched checkpoint/backfill operasyonu; tarihli işyeri bağlamı; departman/görev/çalışan ve assignment aralıkları; domain mutation sürüm/idempotency sözleşmesi; tam audit/outbox payload/consumer; veri silme politikası; iki native CRUD. Hiçbiri bu testle tamamlandı sayılmaz. Canlı migration hazır olunca CLI ile oluşturma/advisor kapıları ayrıca uygulanacak.

[52 kontrol ve hash manifest'i](evidence/P05_WORKPLACE_FOUNDATION_2026-09-13.json).
