# Periyodik Kontroller — P10 istemci dilimi

15 Eylül 2026. Yeni migration `20260915030000_isg_equipment_checks.sql`.
**Kendi rollout satırını eklemiyor ve hiçbir anahtarı açmıyor.**

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
   `unapproved_fixture` kaynağı `needs_review`'u zorluyor; okuma her satırda
   süreyi ve bu bayrağı birlikte taşıyor, ekran da **"Uzman tarafından
   belirlenen"** diye yazıyor.
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

## 5. Tür önerileri süresiz gelir

`equipment_type_suggestions` yalnızca **ad** taşır; içinde period/month/interval
diye bir kolon **yoktur**. Katalog okuması `period_defaults_offered: false`
diyor. Bir tür seçmek, o türe süre atanmış olmasına yol açmaz — süreyi uzman
girer ve kaynağını söyler.

## 6. Sunucu sınırı

`public.isg_equipment_checks_read_v1` / `..._mutate_v1` INVOKER sarmalayıcıları
→ `private_isg.read_equipment_checks` / `private_isg.mutate_equipment_checks`
SECURITY DEFINER kontrollü girişleri. Mutasyon makbuzu
`PRIMARY KEY(actor_id, mutation_id)` + `request_hash`, eylem başına payload
allowlist'i. `next_due_on`, `state` ve `needs_review` hiçbir eylemin payload'ında
yok: onlar sunucunun.

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
| `run_auth_restore.mjs --synthetic-session` | **ok: true, 1287 kontrol, 0 hata**, 39'u `equipment_checks` (`output/isg/runs/synthetic-auth-tIftDy`) |
| `run_suite.mjs foundation` | 550/551 — tek hata eşzamanlı oturumun eğitim metinleri |
| `run_suite.mjs nova-design` | 79/79 |
| `equipment_checks_guard.test.mjs` | 16/16 |
| `nova_equipment_checks.test.mjs` | 12/12 |
| `localization_catalog_tests.mjs` | L10N-001/002/003 PASS; L10N-004 borcundan bu dilime düşen **0** |
| `migrate_swift_localization_catalogs.mjs --check` | PASS, bekleyen 0 |
| iOS Debug + `NOVA_PILOT_BUILD` | SUCCEEDED |

Simülatörde firma seçimi, envanter listesi (altı durumun tamamı), süre özeti ve
ekipman popup'ı yürütüldü. Tek düzeltme: başlık, ekleme butonuyla yan yanayken
iki satıra kırılıyordu; ölçekleniyor.

## 10. Açık kalanlar

- **Modül açılmadı.** Açmak ayrı bir insan kararı ve iki anahtar istiyor:
  ~~~sql
  UPDATE private_isg.rollout SET read_enabled=true, write_enabled=true WHERE feature='modules';
  UPDATE private_isg.module_registry SET read_enabled=true, write_enabled=true WHERE module='equipment';
  ~~~
- **Onaylanmış süre kataloğu yok.** Plan §10.2'nin istediği üretim kural
  kataloğu hazırlanmadı; bu yüzden hiçbir tür için hazır süre sunulmuyor ve
  uzmanın girdiği süre kaynağıyla birlikte işaretleniyor.
- Süresi yaklaşan kontrol için **bildirim üretilmiyor**.
- Android'de karşılığı yok.
- Modül firma tamamlanma skoruna bağlanmadı.
- Kontrol raporunun kendisi yalnızca Diğer Dosyalar arşivinden seçilebiliyor;
  bu ekrandan doğrudan dosya yükleme yok.
