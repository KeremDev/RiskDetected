# Eğitim: katalog, katılım ve tamamlanma — v1 sunucu sözleşmesi

13 Eylül 2026. P07'nin ilk dilimi ve P06 kural motorunun **ilk gerçek tüketicisi**. Hiçbir resmî eğitim içeriği yüklenmedi; katalog sürümleri `content_approved=false` ile yayımlanır.

Migration: [20260913170000_isg_training_core.sql](../../../supabase/migrations/20260913170000_isg_training_core.sql).

## Zincir

~~~text
sürümlü katalog (resmî kaynak + insan onayı) + işyeri G4 curriculum sürümü
  → plan (hiçbir şeyi tamamlamaz) → oturum → kayıt
  → yoklama aralıkları (birleşim) → değerlendirme denemeleri
  → değişmez tamamlanma snapshot'ı + geçerlilik tarihi
  → planın bütün katılımcıları tamamlayınca P06 yükümlülüğü satisfied
~~~

| Değişmez | Kural |
|---|---|
| Plan ≠ tamamlanma | `open_training_plan` `completes_nothing=true` döner; yükümlülük açık kalır |
| Süre birleşimdir | Çakışan aralıklar toplanmaz; 09:00–10:00 + 09:30–10:30 = **90 dakika** |
| Bir dakika iki derse sayılmaz | Aynı çalışanın başka bir kaydıyla çakışan yoklama `ATTENDANCE_OVERLAP` |
| Mola ders değildir | Gereken süre `ders sayısı × lesson_minutes`; `break_minutes` ayrı alandır |
| Eşik kesindir | 59 kalır, 60 geçer; deneme sayısı katalog sürümünün `max_attempts` değeriyle sınırlıdır |
| Tamamlanma değişmez | Snapshot bir kez yazılır; sonraki katalog/curriculum sürümü geçmiş kaydı yeniden yazmaz |
| Geçerlilik takvim yılıdır | `valid_until`, P06'nın `next_due_on` fonksiyonuyla takvim yılı olarak hesaplanır |
| Özel eğitim resmî değildir | Ayrı namespace; adını "Temel İSG" koymak eşdeğerlik yaratmaz ve `content_approved=true` iddia edemez |
| Dış sertifika tamamlanma değildir | `is_training_completion=false`; kanıt için temiz (`scan_status='clean'`) bir dosya ve gerekçe ister, yoksa `needs_review` |

G4 işyerine özgüdür ve kendi sürümünü taşır: görev veya risk değişince yeni curriculum sürümü açılır, imzalanmış geçmiş kayıt değişmez. İşyeri+katalog başına tek `active` curriculum vardır.

Yükümlülük kapanışı `settle_training_requirement` ile olur ve **plana kayıtlı herkes tamamlamadan** kapanmaz; kapanış P06'nın `close_requirement` fonksiyonunu çağırır, böylece takvim `completed` olur.

## Henüz olmayanlar

Resmî 2026 içeriği ve süreleri (kaynak metin + tarihli uzman incelemesi), belge/PDF-XLSX export, skor katkısı, eğitmen/yoklama imzası, MYK ve özel eğitim ayrımının ürün kuralları, istemci/native yüzey. `training` rollout satırı kapalıdır ve istemciye GRANT verilmemiştir.
