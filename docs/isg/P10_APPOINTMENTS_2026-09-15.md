# Atama ve Temsilciler — istemci sınırı (P10 dilimi)

15 Eylül 2026. P10 çekirdeği atamayı, sonlandırmayı ve önemli olan kuralı kurmuştu: **aynı kişi aynı görevi aynı kapsamda çakışan tarihlerde üstlenemez** — ve bunu kimsenin unutamayacağı bir dışlama kısıtıyla (`EXCLUDE USING gist`) yapıyordu. İki şey eksikti:

1. **İstemci sınırı yoktu ve sahiplik kontrolü de yoktu.** `module_scope` işyerinin firmaya ait olduğunu kanıtlıyor, firmanın çağırana ait olduğunu değil.
2. **Plan §10'un saydığı "seçim/atama dayanağı" alanı yoktu**, atama yazısının nerede olduğunu yazacak yer de yoktu.

> `end_appointment` çekirdekte **zaten vardı**; ilk taramamda kaçırmıştım. Bu dilim onu yeniden tanımlamıyor, yalnız erişilebilir kılıyor.

Yeni migration `20260915190000_isg_appointments.sql`. **Kendi rollout satırını eklemiyor, hiçbir anahtarı açmıyor**; `modules` + `appointment` anahtarlarına biniyor.

## Yapısal olarak imkânsız kılınan beş şey

1. **Başka sahibin ataması, personeli veya işyeri ulaşılamaz.**
2. **Aynı kişi aynı görevi aynı kapsamda çakışan tarihlerde üstlenemez.** Kural kısıtın kendisinde; **bu dilim `APPOINTMENT_OVERLAP` diye ikinci bir kontrol yazmıyor** — bitiş tarihi düzeltmesi de aynı kısıttan geçiyor, bu yüzden kişinin bir sonraki aynı görevinin üstüne uzatılamıyor.
3. **Hiç kimseye yeterli etiketi konmaz.** Böyle bir alan yok, şemada koyacak yer yok, ve **her okuma bunu söylüyor**. `qualification_verified` payload'da olsa `PAYLOAD_NOT_ALLOWED`.
4. **Ürün bir işyerinin kaç kişiye ihtiyacı olduğunu söylemez.** Onaylanmış sayı kataloğu yok; okuma "gereken sayı bilinmiyor" diyor — sıfır ya da yeterli ima etmiyor.
5. **Atama başlamadan bitemez**, ve sonlandırmak o atamaya yapılan bir değişikliktir, yeni bir kayıt değil.

Ayrıca: **görevin neden verildiğini söylemek zorunlu.** `basis` (seçimle / atamayla) girilmezse `BASIS_REQUIRED`.

## Sunucu yüzeyi

- `ALTER TABLE appointments ADD COLUMN basis, basis_note, letter_location`.
- `private_isg.appointment_receipts`, `private_isg.appointment_kinds` (5 görev, her birinin **olağan dayanağı** — forma öneri, kural değil).
- `appointment_status(starts_on, ends_before, today)` — **üç durum, her biri kendi sayacı**.
- `require_appointment_company(...)` — çekirdeğin hiç yapmadığı sahiplik kontrolü.
- `appointment_row(...)`, `read_appointments(...)` (`catalog`/`list`/`detail`), `mutate_appointments(...)` (iki işlem).
- Public: `isg_appointments_read_v1`, `isg_appointments_mutate_v1` — ikisi de **SECURITY INVOKER**.

## İstemci yüzeyi

Sol menüde **Atama ve Temsilciler**. Üç sayaç (Görevde / Başlayacak / Sona erdi) ve **hemen altında** "ürün kaç kişi gerektiğini söylemez" cümlesi. Firma ve görev filtreleri **yan yana**, liste **altta**.

- Satır: kişi, görev · işyeri · firma, durum rozeti ve **gerekçesi**, başlangıç/bitiş, dayanak etiketi.
- Detay popup'ı: başlangıç, bitiş, dayanak (+ tutanak no), atama yazısının yeri; **yeterlilik doğrulanmadığı** ve **yazının saklanmadığı** ayrıca yazılı; sonlandır / bitiş tarihini düzelt butonu.
- Görev formu: personel ve işyeri seçimi, görev listesi (**görev seçmek olağan dayanağı dolduruyor, uzman değiştirebiliyor**), dayanak + tutanak no, tarihler, atama yazısının yeri.
- Sonlandırma popup'ı: başlangıç tarihini hatırlatıp bitişi soruyor; düzeltme ise başlığı da öyle diyor.

## Doğrulama

- Disposable PostgreSQL 17: **ortak fixture** + P10 çekirdeği + bu dilim + `scripts/isg/appointments_check.sql`. **39 kontrol PASS.**
  - İki anahtarın farklı hata verdiği; başka sahibin firmasının, personelinin ve işyerinin reddedildiği.
  - Dayanaksız ve tanınmayan dayanaklı atamanın reddedildiği.
  - **Yeterlilik iddiasının reddedildiği** ve şemada koyacak kolon olmadığı.
  - Başlamış atamanın `active`, ileri tarihlinin `upcoming` okuduğu; dayanağın ve "doğrulanmadı" ifadesinin satırda olduğu.
  - **Çakışan atamanın reddedildiği**; aynı kişinin başka görevde ve aynı görevin başka işyerinde serbest olduğu.
  - Başlangıçtan önceki bitişin reddedildiği; sonlandırmanın kapattığı; aynı tarihle tekrarın replay olduğu; **yanlış yazılan bitişin düzeltilebildiği**; sonrasında aynı görevin yeniden üstlenilebildiği; ve **düzeltmenin sonraki atamanın üstüne uzatılamadığı**.
  - Başka firmanın atamasının sonlandırılamadığı.
  - Sayacın listeyle çelişemediği; görev filtresinin yalnız o görevi saydığı; tanınmayan görev filtresinin reddedildiği.
  - Replay ve `IDEMPOTENCY_CONFLICT`; sıfır tablo grant'i; tam iki wrapper.
- `appointments_guard.test.mjs` 14/14, `nova_appointments.test.mjs` 13/13.
- `run_suite.mjs nova-design` 159/157, `foundation` 637/636 — hatalar eşzamanlı oturumun analiz/eğitim dosyalarına ait.
- iOS Debug derlemesi **SUCCEEDED**. 63 yeni katalog anahtarı tr + en (2112 → 2175); mevcut hiçbir anahtar değişmedi.

## Ortak fixture

Bu dilimle birlikte `scripts/isg/module_slice_fixture.sql` eklendi. Önceki beş dilimin kontrolleri scratch fixture'larla koşulmuştu ve **yeniden koşulamıyordu**; artık hepsi bu tek dosyayla koşuyor ve aynı sayıları veriyor: risk **49**, kontrol listeleri **49**, acil durum **43**, tatbikat **38**, KKD **39**, atama **39**.

## Açık kalanlar

- **Sentetik harness aşaması yazılmadı**; disposable PostgreSQL kontrolleriyle doğrulandı.
- **Atama yazısı dosyası eklenemiyor** — istemcinin `file_assets` yolu yok; çekirdeğin `p_asset` parametresi hep NULL geçiliyor ve allowlist'te yok.
- Atamanın kendisi düzeltilemiyor: yanlış kişi/görev/başlangıç için yol yok, yalnız bitiş tarihi değiştirilebiliyor.
- Göreve bağlı eğitim/yeterlilik ilişkisi kurulmadı (plan §10 bunu istiyor; yeterlilik iddiası olmadan bağ kurmak ayrı bir dilim).
- Görev süresi dolan atama için bildirim üretilmiyor.
- Rollout ve modül anahtarı **açılmadı**; canlı pilot bundle'ı ayrı adım.
- Android'de karşılığı yok.
