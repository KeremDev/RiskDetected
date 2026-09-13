# Kota rezervasyonu ve eski hak tabanı — v1 gölge sözleşmesi

13 Eylül 2026. Bu defter **otorite değildir**. Mevcut şirket limiti, abonelik helper'ları, RLS ve trigger'lar aynen yerinde kalır; bu migration onlara dokunmaz, hiçbirinden çağrılmaz.

Migration: [20260913113000_isg_quota_reservations.sql](../../../supabase/migrations/20260913113000_isg_quota_reservations.sql).

## Gölge işareti

Her rezervasyon satırı `authority='shadow'` ile yazılır ve CHECK bu tek değere kilitlidir. Defteri gerçek otorite yapmak ayrı bir migration ve açık bir cutover kararı gerektirir; uygulama kodundan bayrak çevirerek olmaz.

## Alanlar ve kurallar

| Girdi | Kural |
|---|---|
| `p_limit` / `p_unlimited` | Çağıranın kendi yetki kontrolünden gelir. İkisi birlikte verilemez; sınırsız **açık bayraktır**, büyük sayı değildir |
| `p_kind` | `company_slot`, `ai_analysis`, `report_export`, `storage_bytes` — yalnız yapısal tür; ticari sayı gömülü değildir |
| `p_period` | Türün dönem penceresine uygun biçim: `lifetime`, `YYYY`, `YYYY-MM`, `YYYY-MM-DD` |
| `p_mutation` | Hesap kapsamında idempotency anahtarı; aynı anahtar farklı gövdeyle gelirse `IDEMPOTENCY_CONFLICT` |
| `p_ttl_seconds` | 10…86400; süresi geçen rezervasyon `expired` olur ve kapasiteyi serbest bırakır |

Durumlar: `reserved → settled | released | expired`. `settled` bir tüketim geri açılmaz; iade ayrı bir karardır. Kullanım = aynı (sahip, tür, dönem) için `reserved + settled` toplamıdır.

Eşzamanlılık: hesap+dönem penceresi advisory lock ile serileştirilir. Son boş slot iki kez satılmaz — 20 paralel istekten tam biri `reserved`, diğerleri `CAPACITY_EXCEEDED` alır.

## Eski hak tabanı

`legacy_entitlement_floors` ölçülmüş, kanıt taşıyan bir koruma kaydıdır. `is_unlimited` ile sayısal `floor_value` birbirini dışlar; `source='unknown'` satırı `needs_review` olmak zorundadır. `effective_floor()` her zaman `grants_access=false` döner: taban bir ölçümdür, erişim üretmez. Kayıt yoksa sonuç sıfır değil, **inceleme** olarak raporlanır.

`record_quota_shadow()` legacy sayacı ile defteri karşılaştırır, uyuşmazlığı kaydeder ve `authority='legacy'` döndürür. Karşılaştırma hiçbir legacy satırını, helper gövdesini veya trigger'ı değiştirmez.

## Henüz olmayanlar

Plan kataloğu, onaylanmış limit sayıları, eligibility cutoff'u, gift/indirim ayrımı ve gerçek backfill P03'ün açık kalemleridir. İstemciye EXECUTE verilmedi; native hak UI'si bağlanmadı. `quota_ledger` rollout satırı kapalıdır.
