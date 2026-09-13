# P07 ilk dilim — eğitim kataloğu, katılım ve tamamlanma

13 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; rollout kapalı, canlıya uygulanmadı, hiçbir resmî eğitim içeriği yüklenmedi.**

P06 kural motorunun **ilk gerçek tüketicisi**: tamamlanan bir eğitim planı, kuralın açtığı yükümlülüğü kapatır. P04'ün temiz dosya varlığı da burada ilk kez kullanılır (dış sertifika kanıtı).

Migration: [20260913170000_isg_training_core.sql](../../supabase/migrations/20260913170000_isg_training_core.sql) · Sözleşme: [eğitim ve tamamlanma](../../contracts/isg/v1/training-completion.md) · [Kanıt](evidence/P07_TRAINING_CORE_2026-09-13.json).

## Ne eklendi?

- **Sürümlü katalog:** resmî katalog yayını doğrulanmış mevzuat kaynağı + insan onayı ister. Sürümler `content_approved=false` ile yayımlanır; V5'teki ders/eşik/periyot sayıları test fixture'ıdır, mevzuat teyidi değildir.
- **Özel eğitim ayrı namespace:** adını "Temel İSG" koymak eşdeğerlik yaratmaz ve özel katalog `content_approved=true` iddia edemez.
- **İşyerine özgü G4 curriculum sürümü:** G4 alt sınırı katalogdan gelir; görev/risk değişince yeni sürüm açılır, önceki `superseded` olur ve işyeri+katalog başına tek aktif sürüm kalır.
- **Plan ≠ tamamlanma:** plan açmak kimseyi eğitmez ve yükümlülüğü kapatmaz.
- **Yoklama birleşimi:** süre aralıkların **birleşimidir**; çakışanlar toplanmaz, bitişik olanlar birleşir, aynı dakika aynı kişiye iki farklı derste sayılamaz. Mola ders süresinden ayrı alandır.
- **Değerlendirme:** eşik ve deneme sınırı katalog sürümünden gelir; eşik kesindir, sınır aşılınca `ATTEMPT_LIMIT_REACHED`.
- **Değişmez tamamlanma:** yeterli yoklama + geçen deneme; snapshot bir kez yazılır, sonraki katalog/curriculum sürümü geçmişi yeniden yazmaz. Geçerlilik P06'nın takvim aritmetiğiyle hesaplanır.
- **Dış sertifika ayrı kayıttır:** tamamlanma değildir; kanıt için taranmış-temiz dosya ve gerekçe ister, yoksa `needs_review` kalır.

## Test kanıtı

`--synthetic-session` → **489/489 PASS** (43'ü bu dilimin yeni kontrolü), cleanup PASS. `--isolated-copy --p05-upgrade` → **28/28 PASS**: tam legacy şema kopyasında **dokuz** migration sırayla replay edildi (49 yeni tablo, hepsinde RLS), legacy satır ve fonksiyon gövdeleri değişmedi, beş yeni rollout satırı kapalı ve yeni defterler boş geldi. Offline foundation **189 PASS**.

Kapsam: kaynaksız/incelemedeki kaynakla/sınıf kuralsız yayın denemelerinin reddi; içerik onayının kayda yazılması; özel katalogun onay iddia edememesi; G4 alt sınırı; curriculum sürümleme ve tek aktif sürüm; superseded curriculum ile plan açılamaması; kural motorundan gelen yükümlülüğün plana bağlanması; yabancı yükümlülüğün reddi; oturum yöntemi doğrulaması; kayıt tekilliği; yoklamanın oturum penceresi dışına çıkamaması; çakışan/bitişik/tekrarlı aralıkların birleşim matematiği; iki derse aynı dakikanın sayılamaması; başka kişinin aynı dakikada eğitilebilmesi; 59/60/61 eşiği; üç deneme sınırı; yetersiz yoklama ve **bir dakika eksik** hali; tam sınırda tamamlanma; takvim yılı geçerliliği; tamamlanmanın replay'i; yeni katalog sürümünden sonra snapshot'ın değişmemesi; bir katılımcı açıkken yükümlülüğün kapanmaması; herkes tamamlayınca yükümlülüğün `satisfied` ve takvimin `completed` olması; dış sertifikanın tamamlanma sayılmaması, tarih doğrulaması, bilinmeyen dosyanın reddi ve temiz dosyayla incelemeden çıkması; kill switch.

## Açık kalanlar

1. **İçerik kapısı:** resmî 2026 içeriği, ders sayıları, tekrar periyotları ve eşikler yüklenmedi. Kaynak metin + tarihli uzman incelemesi olmadan `content_approved` verilmeyecek.
2. Belge üretimi (katılım tutanağı, sertifika PDF/XLSX) P04'ün belge dilimi ve P11 ile gelir.
3. Skor katkısı (P17), bildirim (P12), eğitmen ve yoklama imzası, MYK/özel eğitim ürün kuralları.
4. Eğitim olayları henüz outbox'a yazılmıyor; dağıtım defterine kaynak olarak eklenmedi.
5. İstemci/native yüzey, canlı migration ve rollout.
