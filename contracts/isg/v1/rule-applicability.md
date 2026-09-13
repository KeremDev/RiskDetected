# Mevzuat kaynağı, kural sürümü ve uygulanabilirlik — v1 sunucu sözleşmesi

13 Eylül 2026. P06'nın ilk dilimi. İçerik (2026 eğitim süreleri vb.) **yüklenmedi**; bu dilim kuralın nasıl kaynaklandığı, sürümlendiği, yayımlandığı ve tarihli yükümlülüğe dönüştüğüdür.

Migration: [20260913150000_isg_rule_core.sql](../../../supabase/migrations/20260913150000_isg_rule_core.sql).

## Yayın zinciri

~~~text
kaynak belge + checksum + erişim tarihi  → needs_review
  + adı belli inceleyen + yazılı gerekçe → kaynak incelemeden çıkar
kural sürümü (draft) → simulation → insan onaylı publish → superseded
published kural + işyeri context'i + tarih → applicability_decision
required karar → requirement_instance (dönem başına bir tane) → schedule v1 → v2 …
~~~

Yalnız URL eklemek doğrulama değildir: `needs_review=false` için belge özeti, `verified_by` ve 10–2000 karakterlik gerekçe birlikte gerekir. Kaynağı incelemede olan bir kural yayımlanamaz; simulation'sız kural yayımlanamaz; onaylayan ve onay notu olmadan yayımlanamaz. Bir `rule_code` için aynı anda tek `published` sürüm vardır; yeni yayın öncekini `superseded` yapar.

## Sınırlı ifade dili

`{"all"|"any":[clause, …]}`, en fazla 8 clause, tek seviye. Fact allowlist: `hazard_class`, `industry_code`, `jurisdiction`, `employee_count`. Operatör allowlist: `in`, `not_in`, `eq`, `gte`, `lte`; sayısal operatörler yalnız `employee_count` üzerinde. Serbest metin, aritmetik, dinamik SQL yoktur.

Değerlendirme üç sonuç verir: `required`, `not_required`, `needs_review`. **Eksik veya yanlış tipli bir fact asla "gerekli değil" değildir**, `needs_review` + `missing_facts`'tir. `all` içinde kesin bir uyuşmazlık bilinmezliği yener (`not_required`); `any` içinde bir doğru clause yeter.

Jurisdiction ayrı bir kapıdır: fact yoksa `JURISDICTION_UNKNOWN` (review), kuralın jurisdiction'ından farklıysa `JURISDICTION_MISMATCH` (not_required). Türkiye kuralı başka ülkeye otomatik uygulanmaz.

## Tarih ve dönem

`period_kind` yalnız `once`, `months`, `years`. **Yıl 365 güne, ay 30 güne çevrilmez**: takvim aritmetiği kullanılır, 31 Ocak + 1 ay ayın son günüdür (artık yılda 29 Şubat). `due_on` ve `timezone` açıkça saklanır. Aynı (firma, işyeri, kural, aksiyon, dönem) için tek yükümlülük vardır; tekrar çağrı yeni kayıt açmaz. Takvim değişince eski schedule `invalidated` + gerekçe olur ve yeni sürüm yazılır; mevcut due date sessizce düzenlenmez. Yükümlülük başına tek `active` schedule kısıtlıdır.

`reconcile_rules` günlük sayım verir: incelemedeki kaynak/karar, `required` olup yükümlülüğü açılmamış kararlar, gecikmiş ve aktif takvimi olmayan yükümlülükler, superseded kural üzerinde açık kalan yükümlülükler. Gün başına tek satır tutar ve görev çoğaltmaz.

## Henüz olmayanlar

Gerçek mevzuat kataloğu ve 2026 içerik doğrulaması (resmî metin + tarihli uzman incelemesi) yapılmadı; hiçbir kural satırı yüklenmedi. Görev/bildirim tüketicileri, eğitim/risk/uygunsuzluk bağlantıları, skor katkısı ve istemci yüzeyi bu dilimde yoktur. `rule_engine` rollout satırı kapalıdır ve istemciye GRANT verilmemiştir.
