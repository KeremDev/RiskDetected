# P05 — Ad soyad ile kolay personel kaydı

13 Eylül 2026 kullanıcı kararı. Bu ek, önceki belgelerdeki personel eklemede tarih/departman/görev zorunluluğu varsayımının yerine geçer. Eski kaynak V5 ve tarihsel kanıtlar değiştirilmez.

## Kesinleşen ekran kuralı

- Kullanıcıdan yalnız **Ad soyad** istenir. İsimden kişi birleştirilmez; aynı adlı iki kişi ayrı kaydedilebilir.
- Firma mevcut firma ekranından alınır; tekrar seçtirilmez. İşe giriş/başlangıç, bitiş/çıkış, işyeri, görev ve personel kodu alanları ekleme formunda bulunmaz.
- **Departman — isteğe bağlı:** mevcut firmanın aktif departmanları arasından seçilebilir, boş bırakılabilir veya yeni ad yazılabilir. Firma departmansız olsa da kayıt yapılabilir. Listede departman bulunması alanı zorunlu yapmaz.
- Yeni ad yazmak tek başına veri kaydetmez. **Personeli kaydet** işlemi, gerekiyorsa departmanı ve personeli birlikte oluşturur. Vazgeçmede veya başarısız kayıtta artık departman kalmaz.
- Aynı departman adı tekrar yazılırsa mevcut kayıt kullanılır. NFC, baş/son ve tekrarlı ASCII boşlukları, Türkçe/Latin büyük-küçük harf eşlemesiyle tekrarlar azaltılır. Departman adı benzerliği kişi adı birleştirmeye uygulanmaz.
- Geçmişten aynı isimli birden fazla aktif departman varsa sistem rastgele seçmez; listeden açık seçim ister. Kullanıcının metnini başka bir departmana sessiz bağlamaz.
- Yeni form mevcut NOVA standardıyla yapılacak: kesintisiz gri zemin, beyaz yuvarlak kart, zeminsiz uygun ikon, ortak popup. Bu tur ekran çizimi/host bağlantısı yapılmadı.

## Koda uygulanan değişiklik

`IsgEmployeeCreate` Swift/Kotlin modelleri ve `employee-create.ts` sunucu parser'ı yalnız context + full_name + opsiyonel department kabul eder. Context UI tarafından sağlanır, kullanıcı alanı değildir: firma kapsamı ve yeni kayıtta expected_version=0. İşyeri kapsamı burada kabul edilmez; seçilmeyen bir işyeri sessizce yok sayılmaz.

Department yok/null, `{kind:"existing",id}` veya `{kind:"new",name}` olabilir. İki mod birlikte, bilinmeyen alanlar, tarih/görev/kod/user_id/sağlık alanları reddedilir. Ad 200, departman 120 UTF-8 byte sınırında; boş ve kontrol karakterli değerler reddedilir. Bu model yalnız decoding/validation yapar; henüz form payload builder, HTTP/SDK çağrısı veya gerçek Auth yetkisi değildir.

İzole `employee_intake_fixture.sql`:

1. Çalışanın `hired_on` alanını nullable yapar. Yeni sade kayıtta işe giriş ve çıkış **NULL** kalır. Bugün gerçek işe giriş tarihi olarak uydurulmaz.
2. `registered_at` ayrı teknik kayıt anıdır; eski çalışanlara geçmiş kayıt zamanı uydurulmaz. Personel kodu UUID'den otomatik üretilir.
3. Opsiyonel `intake_department_id` aynı şirkete composite FK ile bağlanır. Bu başlangıç tercihi tarihli görev/unvan ataması değildir. Daha sonra tarihli atama eklenirse güncel departman okuma modelinin tarihli atamayı önceliklendirmesi ayrıca bağlanmalıdır; başlangıç tercihi güncelmiş gibi süresiz kullanılmamalı.
4. Firma/izin kontrolü → firma kilidi → idempotency → departmanı çöz/oluştur → personel + audit + outbox + receipt, tek transaction.
5. Yeni departman için mevcut default workplace kullanılır/yoksa aynı transaction'da hazırlanır; kullanıcıya işyeri alanı eklenmez. Başka firmaya ait veya arşivli departman/işyeri reddedilir. Arşivli departman yeniden açılmaz; aktif eşleşme yoksa yeni aktif kayıt oluşturulabilir.
6. Hiç departman verilmezse yeni departman, işyeri, görev veya yapay tarihli görevlendirme oluşturulmaz. Firma–çalışan ilişkisi `employees.company_id` ile kurulur.

Firma satırı kilidi bu yazma yolundaki eşzamanlı metin çözümünü seri hale getirir. Bütün production yazıcılarını kapsayan merkezi departman dedup/index/migration politikası henüz yayınlanmadı. Aynı şirket için yoğun yazma lock bütçesi ayrıca ölçülmeli.

Supabase kılavuzu gereği grants/RLS ayrı kontrol edildi; [resmi RLS rehberi](https://supabase.com/docs/guides/database/postgres/row-level-security). Yeni tablolar private/RLS açık, fonksiyon invoker ve PUBLIC EXECUTE kapalıdır. Sentetik GUC/izin tablosu gerçek Auth/paid gate değildir. Receipt, idempotency için personelin normalleştirilmiş adını private DB'de tutar: log/telemetry'ye gönderilmez; production retention/hesap silme tasarımı bu kişisel veriyi kapsamalıdır.

## Doğrulama ve sınırlar

- Swift **61/61**, Kotlin ortak **61/61**, Deno **61/61**: yalnız isim, boş departman, mevcut/yeni departman, boşluk/NFC/Türkçe ad, tek isim, apostrof, UTF-8 sınırları, eksik/bilinmeyen alanlar, eski tarih/görev alanları ve yanlış kapsam.
- Tüm Android core:data **611/611**, 0 failure/error/skip; ana Debug APK PASS. Ana iOS simulator build PASS; iOS debugger skill'i build doğrulaması için kullanıldı. İlk Swift derlemesinde `try` ifadesinin kısa-devre operatörüne taşınması gerekti; düzeltme sonrası corpus ve ana build geçti.
- İzole PostgreSQL **118/118** (önceki99 + yeni19), legacy oracle içinde329/329. İlk115/115 turu sonrası üç ek kapsam/rollback testiyle118/118 geçti. İki koşunun geçici sentetik container'ı temizlendi; müşteri verisi değişmedi.
- 20 aynı retry → bir personel/bir departman; 20 ayrı personel + aynı yeni departman →20 kişi/1 departman. Üç journal fault, ilk default workplace rollback, gerçek bağlantı kesme/retry, aynı sahipteki başka firma departmanının FK reddi, erişim iptali/arşiv sonrası replay reddi doğrulandı.
- Foundation **123/123**, NOVA **24/24**, identity ve CI YAML PASS. Swift/Deno CI çağrıları eklendi; uzak CI/push/deploy yapılmadı. Eski118 DB testi sayısı V5 kaynak kabul matrisinin tamamı değildir; eski testler ilk şemalarında, yeni intake testleri nullable genişleme sonrasında çalışır.

Bu tur **kayıt sözleşmesi ve izole işlem altyapısı** değişti. Personel liste/form/detail ekranı, gerçek servis/Auth bağlantısı, migration ve outbox consumer önceki gibi açık; uygulamada canlı kullanıma açıldı iddiası yoktur. Tarihsiz kişinin iş/görev süresi veya eğitim uygunluğu otomatik varsayılmaz.

[Makine okunur kanıt](evidence/P05_SIMPLE_EMPLOYEE_INTAKE_2026-09-13.json).
