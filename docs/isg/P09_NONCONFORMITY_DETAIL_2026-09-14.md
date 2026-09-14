# P09 ikinci dilim — uygunsuzluk detayı, risk skoru ve geliştirme önerisi

14 Eylül 2026. Migration `20260914190000_isg_nonconformity_detail.sql`.
Rollout **açılmadı**; istemciye yeni GRANT yok; `public.findings` / `public.analyses` yazılmadı.

## Neden bu dilim

P09 çekirdeği bir uygunsuzluğu yalnız **başlık, önem derecesi, tarih ve sorumlu** ile saklıyordu.
Uzmanın elle girdiği akışta istenen alanların hiçbirinin yeri yoktu:

- Tehlike açıklaması
- Alınacak önlem
- Mevzuat bilgisi
- Firma sorumlusu
- Risk metodu ve skorlama (Fine-Kinney veya 5×5)

Ayrıca uzman görüşü maddeleri **skorsuz** geliyor ve bunlar bir uygunsuzluk değil,
**geliştirme önerisi** olarak da kaydedilebilmeli. Çekirdek şemada bunu ayıracak bir alan yoktu.

## Ne eklendi

### 1. `private_isg.nonconformity_details` (1:1, kayıt başına en fazla bir satır)

| Alan | Not |
|---|---|
| `hazard_description`, `control_measure` | ≤ 2000 karakter |
| `legislation_ref` | ≤ 500 karakter |
| `responsible_contact` | ≤ 200 karakter, rapor kişisi — yeni uygulama kullanıcısı değil |
| `risk_method` | `fine_kinney` \| `matrix_5x5` \| NULL |
| `fk_probability/frequency/severity` | yalnız yayımlanmış ölçek değerleri |
| `m5_probability/severity` | 1–5 |
| `risk_score` | **GENERATED ALWAYS … STORED** |
| `risk_band` | **GENERATED ALWAYS … STORED** |

Skor ve bant **generated column**. Bu, "istemci skor gönderemesin" kuralını bir CHECK'e değil,
şemanın kendisine bağlar: hiçbir INSERT/UPDATE — sunucunun kendi kodu dahil — bu iki sütuna yazamaz.

Bantlar mevcut ürünle birebir aynı eşiklerden geliyor
(`supabase/functions/mutate-analysis-finding/index.ts`): Fine-Kinney ≤70 / ≤200 / ≤400,
5×5 ≤4 / ≤9 / ≤19. Ölçek değerleri de `public.findings` ile aynı.

Üç CHECK, yarım skoru imkânsız kılıyor:

- Metot yoksa **hiçbir** skorlama girdisi olamaz.
- `fine_kinney` seçildiyse üç Fine-Kinney girdisi dolu, iki matris girdisi boş.
- `matrix_5x5` seçildiyse iki matris girdisi dolu, üç Fine-Kinney girdisi boş.

Aynı kurallar `set_nonconformity_detail` içinde `RISK_INPUT_INCOMPLETE` olarak da cevap veriyor,
böylece istemci bir CHECK ihlali yerine anlaşılır bir alan hatası görüyor.

### 2. `nonconformities.record_kind`

`nonconformity` (varsayılan) veya `improvement`. Varsayılan sayesinde **bu dilimden önce yazılmış her
kayıt anlamını aynen koruyor**; probe bunu ayrıca doğruluyor.

Anahtar yalnız iki yeni action'ın payload allowlist'inde var. `open_manual` ve `open_from_finding`
hâlâ `record_kind` taşıyamıyor — yani eski iki yol bir geliştirme önerisini sessizce açamaz.

### 3. `source_kind` genişletildi: `legacy_expert_item`

Uzman görüşü maddesi skorlu bir bulgu değil; skorlu bulgu gibi dosyalanmamalı.
Kısıt genişletilirken, beklenen kısıt yerinde değilse migration **sessizce geçmek yerine patlıyor**
(`NONCONFORMITY_SOURCE_KIND_CONSTRAINT_MISSING`).

### 4. Yeni action'lar

| Action | Ne yapar | Bant eşlemesi |
|---|---|---|
| `open_detailed` | Elle akordiyon akışının tek kaydı: başlık + önem + tüm detay + skor | — (severity zorunlu) |
| `open_from_expert_item` | Skorsuz uzman görüşü maddesini uygunsuzluk **veya** geliştirme önerisi olarak açar | **anahtar yok** |
| `set_detail` | Mevcut kaydın detayını ekranda görünenle **bütün olarak** değiştirir | — |

`open_from_expert_item` allowlist'inde `risk_band` **hiç yok**. Skorsuz bir maddede eşlenecek bant
olmadığı için, "bilinmeyen ≠ hayır" kuralı burada bir kontrol değil, **anahtarın yokluğu** ile sağlanıyor.

`set_detail` kısmi güncelleme yapmaz: ekran hangi detayı gösteriyorsa onu gönderir, temizlenen alan
gerçekten temizlenir. Probe bunu, mevzuat ve sorumlu alanlarının `null`'a düşmesiyle doğruluyor.

### 5. Yan bulgu — `open_manual`'ın `assignee` alanı sessizce düşüyordu

Önceki dilimde `open_manual` ve `open_from_finding` payload'ında `assignee` **kabul ediliyor ama
hiçbir yere yazılmıyordu**: `open_nonconformity` bu parametreyi hiç almıyordu. Bu dilimde
`open_nonconformity_record` alanı alıyor ve `assignee_contact` olarak saklıyor.
Eski imza (`open_nonconformity`) korunuyor ve hâlâ `record_kind='nonconformity'` anlamına geliyor.

## Doğrulama

| Koşu | Sonuç |
|---|---|
| `run_auth_restore.mjs --synthetic-session` | **1158 / 1158 PASS** (24 yeni kontrol) |
| `run_auth_restore.mjs --isolated-copy --p05-upgrade` | **33 / 33 PASS**, `private_isg` 159 tablo |
| `run_suite.mjs foundation` | **470 / 470 PASS** (10 yeni guard) |

Sentetik şemada `private_isg` artık **156** tablo (tam legacy replay'de 159 — iki farklı ortam).

Hesaplama beklentileri elle yazıldı, üretim ifadesinin ikinci çağrısı değil:
Fine-Kinney 6 × 3 × 15 = **270** → `high`; 5×5 4 × 5 = **20** → `critical`.

## Açık kalanlar

- Rollout hâlâ kapalı. Pilot için açmak ayrı ve insan kararı:
  `UPDATE private_isg.rollout SET read_enabled=true, write_enabled=true WHERE feature='nonconformity';`
- Uygunsuzluk **detay ekranı** (durum geçişi, düzeltici aksiyon, doğrulama) hâlâ yok.
- `record_kind` listede dönüyor ama sunucu tarafında bir **filtre parametresi** yok;
  istemci 200 satırlık listeyi kendi ayırıyor. Kayıt sayısı büyürse filtre sunucuya taşınmalı.
- Detay için ayrı bir sürüm/iyimser kilit yok: `set_detail` son yazanı kabul eder.
  Kaydın kendi `version` alanı yalnız durum geçişlerini koruyor.
