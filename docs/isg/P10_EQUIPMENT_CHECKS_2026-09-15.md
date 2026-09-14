# Periyodik Kontroller — P10 istemci dilimi

15 Eylül 2026. Üç migration: `20260915030000_isg_equipment_checks.sql`,
`20260915050000_isg_equipment_periods.sql` ve
`20260915070000_isg_equipment_inspection_edit.sql`. **Üçü de kendi rollout
satırını eklemiyor ve hiçbir anahtarı açmıyor.**

Sol menüdeki **Periyodik Kontroller** girişi artık gerçek bir sayfaya iniyor,
firma detay sayfasındaki aynı başlık ve ana sayfadaki özet kartı bağlandı.

## 1. Ne eksikti

P10'un ilk dilimi (`20260913230000_isg_module_core.sql`) ekipman envanterini,
tür bazlı kontrol süresini ve kontrol kaydını kurmuştu — planın kurallarıyla
birlikte: **süre ekipman türüne aittir**, her ekipmana tek tip yıllık süre
verilmez; **tür kuralı yoksa sonraki tarih üretilmez**; **olumsuz sonuç için de
tarih üretilmez**.

Eksik olan iki şeydi:

1. **İstemci sınırı yoktu.** Üç domain fonksiyonu vardı, hiçbiri dışarıdan
   erişilebilir değildi.
2. **Domain fonksiyonlarında sahiplik kontrolü yoktu** — çünkü onlara kimse
   ulaşamıyordu. `set_equipment_inspection_rule` yalnızca firmanın var olduğuna
   bakıyordu, `record_equipment_inspection` ekipmanın kime ait olduğuna hiç
   bakmıyordu. Kontrollü giriş tam olarak bunu ekliyor.

## 2. Yapısal olarak imkânsız kılınan dört şey

1. **Tarih uydurulmuyor.** Tür için süre yoksa satır `period_unknown` okur —
   **`valid` değil**. Sonraki tarihi bilmemek kayıttaki bir boşluktur, "bir yıl
   daha iyidir" demek değildir.
2. **Süre, kaynağı söylenmeden mevzuat gereği gibi sunulmuyor.**
   `unapproved_fixture` ve `regulation_default` kaynakları `needs_review`'u
   zorluyor; okuma her satırda süreyi ve bu bayrağı birlikte taşıyor, ekran da
   **"Uzman tarafından belirlenen"** veya **"ürün varsayılanı"** diye yazıyor.
3. **Başka sahibin ekipmanına erişilemiyor.** Kontrollü giriş, domain
   fonksiyonuna devretmeden önce firmayı oturum açmış aktöre karşı doğruluyor.
4. **Bu bir insan sağlık kontrolü değil.** Tür öneri kataloğu şemada sabit bir
   CHECK ve içinde sağlık kodu yok; probe `health_check` eklemeyi gerçekten
   deniyor ve reddedildiğini doğruluyor.

## 3. Sonradan tanımlanan süre eski raporu değiştirmiyor

Bir rapor kaydedildiğinde sonraki tarih o anki kurala göre hesaplanıp saklanır.
Süre sonradan tanımlanırsa **eski rapor yeniden yazılmaz**. Bu durumda ekranda
süre görünür ama durum hâlâ "Süre belirsiz" olur; satır bunu çelişki gibi
bırakmak yerine `period_defined_after_report` ile söyler ve popup şunu yazar:

> Rapor kaydedildiğinde bu tür için süre tanımlı değildi; sonraki tarih
> hesaplanmadı. Süre sonradan tanımlandı, eski rapor değiştirilmedi.

## 4. Durum saklanmıyor

Altı durum okuma anında hesaplanıyor (`state_authority: computed_at_read`):

| Durum | Ne demek |
|---|---|
| `never_inspected` | Kayıtlı rapor yok |
| `period_unknown` | Rapor var, tür için süre yok |
| `failed` | Son rapor olumsuz |
| `overdue` | Kayıtlı sonraki tarih geçmiş |
| `due_soon` | Kayıtlı tarih uyarı penceresinde |
| `valid` | Tarih henüz gelmedi |

Ekranda **beş sayaç** var (Süresi geçti · Olumsuz · Takipsiz · Yaklaşıyor ·
Güncel) ve her durum tam olarak bir gruba ait. **Bir sayaca dokunmak tam olarak
o sayacın saydığı satırları** filtreliyor: aynı kelimeler sunucunun kabul ettiği
filtre değerleri.

Uyarı penceresi (30 gün) sunucunun; her okumada `notice_days` olarak dönüyor ve
ekran onu yazıyor, kendi uydurmuyor.

## 5. Varsayılan süreler — ikinci migration `20260915050000`

**Sahibin kararıyla değişti.** İlk dilim hiçbir tür için süre sunmuyordu (§10.2'de
onaylanmış kural kataloğu olmadığı gerekçesiyle). Sahip modülün sürelerle
gelmesi gerektiğini söyledi; bu yüzden artık **her tür bir süreyle başlıyor** ve
dürüstlüğün tamamını **atıf** taşıyor:

| | |
|---|---|
| Nereden geliyor | `equipment_default_periods` — her satırda `basis_note` **zorunlu** (20–500 karakter) |
| Değer | Tür ayrımı yapılmadan **12 ay**; yönetmelik ekinin kendi kuralı "aksi belirtilmedikçe yılda bir" olduğu için uydurma bir tür ayrımı yapılmadı |
| Kaynak etiketi | `regulation_default` → **"Mevzuat eki genel süresi · ürün varsayılanı"** |
| Onay | Şema **needs_review'u zorluyor**: `CHECK(period_source<>'regulation_default' OR needs_review)` |
| Uzman bunu seçebilir mi | **Hayır.** P10 fonksiyonu yalnız `manufacturer`, `rule_version`, `unapproved_fixture` kabul ediyor; `regulation_default` yalnızca sunucunun kendi yazdığı etikettir |

Varsayılan, ekipman kaydedilirken **gerçek, görünür, düzenlenebilir bir firma
kuralı olarak yazılıyor** — gizli bir sabit değil. Süreler ekranında kaynağıyla
ve onay bayrağıyla listeleniyor, popup şunu yazıyor:

> Bu, ürünün bu tür için başlattığı genel süredir; bu firma için henüz
> onaylanmadı. Süreler ekranından onaylayın veya değiştirin.

Ürünün varsayılanı olmayan bir tür hâlâ **hiç tarih üretmiyor**; probe bunu
`welding_set` üzerinden gerçekten deniyor.

## 5.1. Sonraki tarih otomatik, ama uzmanın

Rapor tarihi girilince sonraki tarih **süreden otomatik hesaplanıp forma
dolduruluyor** ("12 aylık süreden otomatik dolduruldu; değiştirebilirsiniz").
Uzman değiştirebilir.

Kaydedilen tarihin **ne anlama geldiği sunucunun kararı**: gönderilen tarih
sürenin ürettiğiyle aynıysa `due_source='period'`, farklıysa `'expert'`. Detay
kartı bunu tarihin altında yazıyor ("Süreden hesaplandı" / "Uzman tarafından
değiştirildi"), geçmişte de etiketleniyor. İstemcinin doldurduğu değer bir form
varsayılanıdır; sınıflandırma istemcinin değil.

Rapor tarihinden önceki bir tarih ve olumsuz sonuca elle verilen tarih
reddediliyor (`DUE_BEFORE_REPORT`, `DUE_ON_A_FAILED_CHECK`).

## 5.3. Kaydedilmiş rapor düzeltilebiliyor — `20260915070000`

"Kullanıcı isterse değiştirebilir" yalnız giriş anında değil. Geçmişteki bir
rapora dokunmak **düzeltme popup'ını** açıyor: sonraki kontrol tarihi, kontrolü
yapan, rapor no, arşiv raporu, İSG-KATİP işareti ve notu, not.

**Değiştirilemeyen iki alan:** kontrol tarihi ve sonucu. Bunlar raporun
kendisidir; değiştirmek olanı sessizce yeniden yazmak olurdu. Ekran ne
yapılacağını söylüyor:

> Kontrol tarihi ve sonucu raporun kendisidir; buradan değiştirilmez. Yanlışsa
> doğru raporu ayrıca kaydedin.

Sunucu da aynısını yapıyor: `performed_on` ve `result` bu eylemin payload
allowlist'inde yok. Düzeltilen tarih girişteki ile **aynı şekilde**
sınıflandırılıyor — sürenin ürettiğine geri çekilirse tekrar "Süreden
hesaplandı" oluyor. Temiz olmayan bir asset bu yoldan da eklenemiyor.

## 5.2. İSG-KATİP ataması — uzmanın beyanı

Kontrol kaydederken opsiyonel bir işaret: **"İSG-KATİP ataması yapıldı"** ve
isteğe bağlı bir atama notu.

Bu bir **doğrulama değil**. Plan §10'un İSG-KATİP satırı zaten "resmî sistemde
işlem yapılmış olduğu iddia edilmez" diyor ve `katip_contracts` tablosu bunu
`official_integration boolean CHECK(NOT official_integration)` ile yapısal
kılmış. Aynı kalıp buraya taşındı: `katip_official_verification` kolonu **yalnız
false olabilir**, probe `true` yazmayı gerçekten deniyor ve reddedildiğini
doğruluyor. İşaretin altında ekranda yazıyor:

> Bu işaret uzmanın kendi beyanıdır. Uygulama İSG-KATİP üzerinde sorgulama veya
> işlem yapmaz.

İşaretlenmemiş bir kayda not yazılamıyor (`CHECK(katip_assignment_declared OR
katip_declared_note IS NULL)`): boş bir kutunun açıklaması olmaz. İşareti geri
almak notunu da alıyor.

**Sadece bilgi amaçlı.** Hiçbir duruma, sayaca veya filtreye dokunmuyor; probe
işareti değiştirip sayımların ve satır durumunun **bit bit aynı kaldığını**
doğruluyor ve `katip` diye bir filtre kelimesi olmadığını gösteriyor. Ekranda
mühür ikonu değil **konuşma balonu** kullanılıyor — mühür doğrulama gibi okunur.
Detay kartında "Atama yapıldı · uzman beyanı" olarak görünüyor.

## 6. Sunucu sınırı

`public.isg_equipment_checks_read_v1` / `..._mutate_v1` INVOKER sarmalayıcıları
→ `private_isg.read_equipment_checks` / `private_isg.mutate_equipment_checks`
SECURITY DEFINER kontrollü girişleri. Mutasyon makbuzu
`PRIMARY KEY(actor_id, mutation_id)` + `request_hash`, eylem başına payload
allowlist'i. `next_due_on` uzmanın (bkz. §5.1); `due_source`, `state`,
`needs_review` ve `katip_official_verification` hiçbir eylemin payload'ında yok:
bir tarihin **ne anlama geldiği** sunucunun.

Her yazma, kuralı elinde tutan P10 fonksiyonuna devrediliyor; bu dilim tarih
hesaplamıyor ve `equipment_inspections`'a doğrudan INSERT yapmıyor.

**İki anahtar gerekiyor:** `modules` özelliği **ve** `equipment` modül anahtarı.
Probe ikisini ayrı ayrı kapatıp her birinin tek başına yeterli olmadığını
doğruluyor (`FEATURE_UNAVAILABLE` / `MODULE_UNAVAILABLE`).

## 7. Bağlanan yerler

- Sol menü → **Periyodik Kontroller** (hesabın tamamı, firma seçimiyle daralıyor)
- Firma detay sayfası → **Periyodik Kontroller** başlığı, beş sayaçlı şerit ve
  aynı sayfayı o firmaya kilitli açan buton
- **Ana sayfa özet kartı**: "Kontrol · ilgi bekleyen" — süresi geçmiş ve son
  raporu olumsuz olan ekipman sayısı. Kayıt sayımıdır, firma hakkında karar
  değildir; karta dokunmak bu sayfaya iner.
- **Diğer Dosyalar ile bağlantı:** kontrol kaydederken arşivdeki *Periyodik
  kontrol raporu* dosyaları seçilebiliyor. Yalnızca gerçekten temizlenmiş
  dosyalar listeleniyor ve sunucu zaten `scan_status='clean'` olmayan bir asset'i
  reddediyor.

## 8. Ekran tasarımı

Onaylanan düzenin aynısı: önce firma seçimi (aramalı, yazmadan da listeleyen),
ampullü ipucu, seçimden sonra ana sayfa kart biçiminde beş sayaç, süre özeti
satırı, arama, **yan yana iki seçici** (Durum · Tür) ve ilk **10** kayıt.

Satıra dokunmak kompakt popup açıyor: durum, **neden öyle olduğunun açıklaması**,
son kontrol / sonuç / sonraki kontrol / kontrolü yapan / kapsam / rapor no,
süre kartı (süre + kaynağı birlikte), aynı popup içinde kontrol kaydetme paneli,
kontrol geçmişi ve işlemler.

Tarihi olmayan satır boş bırakılmıyor: **"Tarih yok"** yazıyor, çünkü tarihin
yokluğu bilginin kendisi.

## 9. Koşular

| Kapı | Sonuç |
|---|---|
| `run_auth_restore.mjs --synthetic-session` | **ok: true, 1305 kontrol, 0 hata**, 57'si `equipment_checks` (`output/isg/runs/synthetic-auth-Ikxt4p`) |
| `run_suite.mjs foundation` | 557/558 — tek hata eşzamanlı oturumun eğitim metinleri |
| `run_suite.mjs nova-design` | 84/84 |
| `equipment_checks_guard.test.mjs` | 23/23 |
| `nova_equipment_checks.test.mjs` | 17/17 |
| `localization_catalog_tests.mjs` | L10N-001/002/003 PASS; L10N-004 borcundan bu dilime düşen **0** |
| `migrate_swift_localization_catalogs.mjs --check` | PASS, bekleyen 0 |
| iOS Debug + `NOVA_PILOT_BUILD` | SUCCEEDED |

Simülatörde firma seçimi, envanter listesi (altı durumun tamamı), süre özeti,
ekipman popup'ı, kontrol kaydetme paneli ve rapor düzeltme popup'ı yürütüldü:
rapor tarihi seçilince
sonraki tarih kendiliğinden doldu, "Süreden hesaplandı" satırı göründü ve
İSG-KATİP işareti ile beyan uyarısı çalıştı. İki düzeltme: başlık, ekleme
butonuyla yan yanayken iki satıra kırılıyordu (ölçekleniyor); yeni katalog
anahtarları eklendikten sonra **yeniden derlemeden** bakıldığı için ekranda
`⟦EKSİK:…⟧` görünüyordu — `RDLocalization` fallback'i değil kataloğu okuyor.

## 10. Açık kalanlar

- **Modül açılmadı.** Açmak ayrı bir insan kararı ve iki anahtar istiyor:
  ~~~sql
  UPDATE private_isg.rollout SET read_enabled=true, write_enabled=true WHERE feature='modules';
  UPDATE private_isg.module_registry SET read_enabled=true, write_enabled=true WHERE module='equipment';
  ~~~
- **Onaylanmış, tür bazlı süre kataloğu hâlâ yok.** Plan §10.2'nin istediği
  üretim kural kataloğu hazırlanmadı. Şu an gelen varsayılan **tek bir genel
  süredir** (12 ay) ve `regulation_default` etiketiyle, onay bekleyen olarak
  geliyor. Tür/standart/sektör bazlı doğrulanmış süreler bu katalog
  hazırlandığında `equipment_default_periods` tablosuna girer — kod değişmez.
- **İSG-KATİP ile entegrasyon yok ve planlanmadı.** İşaret uzmanın beyanıdır.
- Süresi yaklaşan kontrol için **bildirim üretilmiyor**.
- Android'de karşılığı yok.
- Modül firma tamamlanma skoruna bağlanmadı.
- Kontrol raporunun kendisi yalnızca Diğer Dosyalar arşivinden seçilebiliyor;
  bu ekrandan doğrudan dosya yükleme yok.

## Canlı pilot

14 Eylül 2026'da bu modül canlı projede açıldı. Canlı proje bu dosyadaki migration zincirini taşımıyor; açılış, kırpılmış bir pilot bundle ile yapıldı ve üç bilinçli sapma taşıyor. Ayrıntı, sapmalar, doğrulama ve kapatma yolu: [Canlı pilot kaydı](NOVA_EQUIPMENT_PILOT_2026-09-14.md).

Buradaki geliştirme migration'ları (`20260915030000`, `20260915050000`, `20260915070000`) **değiştirilmedi**; pilot bundle onların canlıya uyarlanmış kopyasıdır ve `supabase/pilot-release/` altında ayrı durur.
