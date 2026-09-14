# Risk Değerlendirmesi — istemci sınırı (P08 ikinci dilim)

15 Eylül 2026. P08'in ilk dilimi dört revizyon türünü, tarih kurallarını, analiz bulgusunun uzman eliyle aktarılmasını, etki listesini, kaynak sapma bayrağını ve tek kazananlı tamamlamayı kurmuştu. **Eksik olan istemci sınırıydı** — ve domain fonksiyonlarında sahiplik kontrolü yoktu, çünkü onlara ulaşabilen bir yol yoktu. Ekipman dilimindeki boşluğun aynısı.

Yeni migration `20260915090000_isg_risk_versions.sql`. **Kendi rollout satırını eklemiyor ve hiçbir anahtarı açmıyor**; ilk dilimin kurduğu `risk` anahtarına biniyor.

## Yapısal olarak imkânsız kılınan beş şey

1. **Başkasının değerlendirmesine ulaşılamaz.** Kontrollü girişler, delege etmeden önce firmayı oturum açmış aktöre karşı doğruluyor; her yazma satırı ayrıca `company_id` + `owner_id` ile yeniden kilitliyor.
2. **Geçerlilik tarihi uydurulmuyor.** Süresi olmayan tamamlanmış bir sürüm `period_unknown` okur — `valid` değil. Bir belgenin ne zaman biteceğini bilmemek kayıttaki bir boşluktur, temiz kâğıt değil.
3. **Süre, yayımlanmış bir kural üretmedikçe mevzuat gereği olarak sunulmaz.** Uzmanın kendi sayısı `unapproved_fixture` olarak saklanır, gözden geçirme bayrağını zorlar ve okuma bunu her satırda söyler. Katalog `period_defaults_offered: false` döner ve yalnız `status='published'` + `period_kind='years'` kuralları listeler.
4. **Yasal değerlendirme tarihi düzeltmeyle oynatılamaz.** Yalnız tam yenileme kendi tarihini taşır; allowlist ile domain fonksiyonu aynı şeyi söyler, ekran da alanı diğer türlerde hiç açmaz.
5. **Fotoğraf analizinden kendiliğinden hiçbir şey kopyalanmaz.** Kaynak bağlama uzmanın yaptığı bir işlemdir; sonradan değişen bir kaynak yalnızca sapma bayrağı kaldırabilir — tamamlanmış belge asla yeniden yazılmaz ve sunucu bunu kanıtlamak için belgeyi değişmemiş olarak geri döner.

Ayrıca: **doğrulayanı istemci seçemez.** `verified_by` allowlist'te yok; sınır oturum açmış uzmanı kendisi geçirir, yani hiçbir kayıt başkasının onayını taşıyamaz.

## Sunucu yüzeyi

- `private_isg.risk_version_receipts` — tek yeni tablo, RLS açık, sıfır grant.
- `risk_notice_days()` = 60. **Ürünün kendi uyarı mesafesi**, mevzuat süresi değil; her okumada bildiriliyor.
- `risk_assessment_status(...)` — beş durum, okuma anında.
- `risk_assessment_group(...)` — dört sayaç, her durum tam bir sayaçta.
- `require_risk_company(company, write)` — kapı + ücretli plan + sahiplik.
- `risk_assessment_row(...)` — yürürlükteki belge, üstündeki taslak, tüm sürüm geçmişi (kaynaklar ve etkilerle).
- `read_risk_versions(...)` — `catalog` / `list` / `detail`.
- `mutate_risk_versions(...)` — altı işlem: `open_assessment`, `draft_version`, `attach_source`, `record_impact`, `finalize_version`, `flag_drift`.
- Public: `isg_risk_versions_read_v1`, `isg_risk_versions_mutate_v1` — ikisi de **SECURITY INVOKER**.

## İstemci yüzeyi

Sol menüde **Risk Değerlendirmesi**. Hesabın tamamı tek okumada; firma ve durum filtreleri **yan yana**, basınca liste **altta** açılıyor.

- Dört sayaç; bir sayaca dokunmak tam olarak onun saydığı satırları filtreliyor.
- Satır: durum rozeti, **durumun gerekçesi**, geçerlilik tarihi, süre ve kaynağı, sürüm no; açık taslak, kaynak sapması ve çok eski tarih ayrı etiketler olarak.
- Detay popup'ı: yürürlükteki belgenin olguları, açık taslak kartı, tüm sürüm geçmişi (tür açıklaması, kapsam, gerekçe, aktarılan bulgu sayısı, etkiler, süre kaynağı).
- Yeni sürüm popup'ı: **önce tür seçiliyor**, çünkü tür hangi tarihlerin sorulabileceğine karar veriyor. Tam yenileme dışındaki türlerde tarih alanı hiç görünmüyor, yerine "bu tür özgün tarihi korur" yazıyor.
- Tamamlama popup'ı: onaylanmış kural varsa seçilebiliyor; yoksa ekran **"Onaylanmış bir süre kataloğu yok. Gireceğiniz süre 'uzman tarafından belirlenen' olarak kaydedilir."** diyor.

## Doğrulama

- Disposable PostgreSQL 17: fixture + ilk dilim + bu dilim + `scripts/isg/risk_versions_check.sql`. **49 kontrol PASS.**
  - Anahtarın kapalı olduğu ve okumanın reddedildiği; yalnız okumaya açıkken yazmanın reddedildiği.
  - Başka sahibin firmasının ve başka firmanın işyerinin reddedildiği.
  - Aynı işyerini iki kez açmanın aynı kaydı verdiği.
  - Gelecek tarihin, eski `expected_current`'ın reddedildiği.
  - **Açık taslağın belge olmadığı** (durum hâlâ `never_assessed`), taslağın durumun yanında bildirildiği, ikinci taslağın reddedildiği.
  - Uzman süresinin `unapproved_fixture` + gözden geçirme olduğu; sürenin **bugünden değil değerlendirme tarihinden** işlediği.
  - Doğrulayan adının reddedildiği ve satırın oturum açmış uzmanı taşıdığı.
  - Yayımlanmış kuralın kurala atfedildiği; yayımlanmamış kuralın `RULE_NEEDS_REVIEW` aldığı; süresiz tam yenilemenin reddedildiği.
  - Düzeltmenin yasal tarihi oynatamadığı.
  - **Kısmi revizyonun işyeri süresini sıfırlamadığı**, aynı anda tek sürümün `final` olduğu, öncekinin `superseded` olduğu.
  - Etki listesinin yalnız kısmi revizyona ait olduğu.
  - Kaynak bağlamanın analize hiçbir şey yazmadığı; tamamlanmış sürümün kaynak kazanamadığı.
  - Sapmanın tespit edildiği ve **belgenin bit bit değişmediği**.
  - Süresi silinmiş belgenin `period_unknown` okuduğu.
  - Katalogun uyarı penceresini, varsayılan sunulmadığını ve işyerlerini verdiği.
  - Sayacın saydığı listeyle çelişemediği; replay ve `IDEMPOTENCY_CONFLICT`.
  - Sıfır tablo grant'i; tam iki wrapper.
- `risk_versions_guard.test.mjs` 12/12, `nova_risk_assessments.test.mjs` 11/11.
- `run_suite.mjs nova-design` 95/94, `foundation` 570/569 — her iki koşudaki tek hata eşzamanlı oturumun eğitim/analiz dosyalarına ait.
- iOS Debug derlemesi **SUCCEEDED**. 99 yeni katalog anahtarı tr + en olarak eklendi; hiçbir mevcut anahtar değişmedi veya kaybolmadı (1722 → 1823).

## Açık kalanlar

- **Sentetik harness aşaması yazılmadı.** Bu dilim disposable PostgreSQL kontrolleriyle doğrulandı; `run_auth_restore.mjs` içine bir `risk-versions` aşaması eklemek bekliyor.
- `attach_source`, `record_impact` ve `flag_drift` sunucuda ve serviste var ama **ekranda henüz yüzeyleri yok**; analiz bulgusu seçme akışı ayrı bir dilim.
- `rescan` türü için dosya varyantı (`attach_rescan_variant`) sınırda yok — `file_assets` gerektiriyor.
- Rollout **açılmadı**; canlı pilot bundle'ı ayrı bir adım (canlıda `risk` anahtarı ve bu tabloların hiçbiri yok).
- Onaylanmış süre kataloğu yok; `rules` listesi boş geliyor ve ekran bunu söylüyor.
- Yaklaşan/dolmuş değerlendirme için bildirim üretilmiyor.
- Android'de karşılığı yok.
