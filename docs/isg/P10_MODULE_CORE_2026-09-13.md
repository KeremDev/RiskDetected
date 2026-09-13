# P10 ilk dilim — beş İSG modülü ve modül başına anahtar

13 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; rollout ve beş modül anahtarının tamamı kapalı, canlıya uygulanmadı.**

P10 çok modüllü bir fazdır. Bu dilim §7.5 tablosunun beş satırını kapsar: **acil durum planı, tatbikat, ekipman/periyodik kontrol, görevlendirme, KKD teslim/iade**. Kalan on bir modül kendi dilimlerinde gelecek.

Migration: [20260913230000_isg_module_core.sql](../../supabase/migrations/20260913230000_isg_module_core.sql) · Sözleşme: [modül domainleri](../../contracts/isg/v1/module-domains.md) · [Kanıt](evidence/P10_MODULE_CORE_2026-09-13.json).

## İki katmanlı anahtar

`modules` rollout satırı **ve** her modül için ayrı `read_enabled`/`write_enabled`. Plandaki "modül bazlı flag/read-only; başka modülü veya temel ürünü kapatma yok" kuralı böyle uygulanıyor: KKD modülünün yazması kapatıldığında ekipman modülü çalışmaya devam ediyor.

## Modül kuralları

- **Acil durum planı:** yenileme yeni sürümdür; önceki satırın kapsamı, tarihi, ekip snapshot'ı ve dosyası değişmeden kalır, yalnız `active` işareti devreder. Mevzuat/gerekçe notu yoksa kayıt `needs_review` olur.
- **Tatbikat:** planlamak gerçekleştirmek değildir — planlı kayıtta gerçekleşme tarihi ve katılımcı listesi yoktur. Katılımcılar yalnız o firmanın çalışanları olabilir; sonuç bir kez yazılır, tekrar çağrı ilk tarihi değiştirmez.
- **Ekipman:** periyot **türe** aittir. Tür kuralı yoksa vade uydurulmaz (null döner ve inceleme işaretlenir); istisna notu kayıtta görünür; başarısız kontrol yeni dönem açmaz.
- **Görevlendirme:** aynı kişi, aynı tür, aynı kapsamda çakışan iki görevlendirme alamaz (GiST exclusion). Görevi bitirmek dönemi serbest bırakır ve aynı kişi yeni dönemde yeniden atanabilir.
- **KKD:** miktar pozitif olmak zorunda; teslimden önce iade ve teslim edilenden fazla iade reddedilir; imzalı kopya varsayılmaz, temiz belge olmadan işaretlenemez.

## Test kanıtı

`--synthetic-session` → **588/588 PASS** (33'ü bu dilimin yeni kontrolü), cleanup PASS. `--isolated-copy --p05-upgrade` → **29/29 PASS**: tam legacy kopyada **on iki** migration replay, 74 tablo, hepsinde RLS; beş modül anahtarı da kapalı geldi; legacy satır ve fonksiyon gövdeleri değişmedi. Offline foundation **209 PASS**.

Kapsam: iki katmanlı kapı ve modül bazlı duraklatma; plan sürümleme ve önceki satırın değişmemesi; bilinmeyen plan id'si ve geçersiz geçerlilik tarihi reddi; planlı tatbikatın boş kalması; olmayan plan sürümüne tatbikat reddi; firma dışı katılımcı reddi; sonucun tekrar yazılamaması; seri numarası başına tek ekipman; kuralsız türde vade üretilmemesi; tür başına farklı periyotlar; takvim ayı ile vade hesabı ve istisna notunun görünmesi; başarısız kontrolün dönem açmaması; kirli kanıt dosyası reddi; görevlendirme çakışması ve tür/kişi farkının çakışma sayılmaması; görev bitişinin dönemi serbest bırakması; arşivli/yabancı çalışan reddi; sıfır ve negatif miktar reddi; imzasız belge reddi; referans başına tek teslim; kısmi iade ve fazla iade reddi; kill switch.

## Açık kalanlar

1. Kalan on bir modül: ISG-KATİP sözleşme takibi, yıllık çalışma planı, yıllık eğitim planı, kurul/karar, onaylı defter arşivi, çalışma izni formu, taşeron paketi, saha ziyareti, evrak merkezi, portföy, ürün rehberliği.
2. Belge/PDF-XLSX üretimi, task ve bildirim tetikleyicileri, skor katkısı.
3. Modül olayları henüz outbox'a yazılmıyor.
4. İstemci/native yüzey, canlı migration ve rollout.
