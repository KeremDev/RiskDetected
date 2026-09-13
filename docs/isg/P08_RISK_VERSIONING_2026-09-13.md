# P08 ilk dilim — risk değerlendirmesi sürümleme ve tarih disiplini

13 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; rollout kapalı, canlıya uygulanmadı.**

Migration: [20260913190000_isg_risk_versioning.sql](../../supabase/migrations/20260913190000_isg_risk_versioning.sql) · Sözleşme: [risk sürümleme](../../contracts/isg/v1/risk-versioning.md) · [Kanıt](evidence/P08_RISK_VERSIONING_2026-09-13.json).

## Ne eklendi?

- **Dört revizyon türü, dört ayrı tarih etkisi:** tam yenileme dönemi **gerçek değerlendirme tarihinden** başlatır; kısmi revizyon yalnız listelediği hedefleri etkiler; metadata düzeltmesi vadeyi değiştirmez; daha iyi tarama yeni bir dosya varyantıdır, yenileme değildir.
- **Tarih disiplini:** gelecek tarih reddedilir, 10 yıldan eski tarih reddedilmez ama incelemeye işaretlenir, `full` dışındaki türler esas tarihi değiştiremez. Dosyanın yükleme günü hiçbir yerde hukuki tarih değildir.
- **Dönem kaynağı açıktır:** yayımlanmış kural sürümünden (`rule_version`) veya açıkça verilen fixture'dan (`unapproved_fixture` + `period_needs_review`). Yayımlanmamış kural `RULE_NEEDS_REVIEW` verir.
- **Bulgu aktarımı uzman seçimidir:** seçilen alanların kopyası ve kaynak sürümü saklanır; legacy analiz/bulgu satırına yazılmaz.
- **Kaynak drift yalnız inceleme önerir:** kaynak analiz ilerlese bile finalize edilmiş belgenin tarihi, vadesi ve durumu değişmez.
- **Tek kazananlı finalize ve gönderim kapısı:** ikinci cihaz eski sürümle gelirse `VERSION_CONFLICT`; kuyrukta bekleyen eski sürüm `assert_current_risk_version` ile durdurulur.

## Test kanıtı

`--synthetic-session` → **527/527 PASS** (38'i bu dilimin yeni kontrolü), cleanup PASS. `--isolated-copy --p05-upgrade` → **28/28 PASS**: tam legacy kopyada **on** migration replay, 54 tablo, hepsinde RLS; legacy satır ve fonksiyon gövdeleri değişmedi. Offline foundation **196 PASS**.

Kapsam: gelecek/eksik/çok eski tarih kuralları; ilk değerlendirme olmadan revizyon denemesi; tek taslak kuralı; eski `expected` ile çakışma; kirli/bilinmeyen dosya reddi; açık seçimle bulgu aktarımı ve tekrarın yan etkisizliği; finalize edilmiş sürüme kaynak eklenememesi; doğrulayansız finalize reddi; fixture döneminin incelemeye işaretlenmesi; yayımlanmış kural döneminin kullanılması; yayımlanmamış kuralın reddi; rescan'in tarihi ve vadeyi değiştirmemesi; rescan'in dönem isteyememesi; önceki final'in superseded olup satırının değişmemesi; metadata düzeltmesinin vadeyi sıfırlamaması; kısmi revizyonun scope zorunluluğu, etki listesi ve vadeyi sıfırlamaması; drift'in belgeyi değiştirmemesi; bağlantısız kaynakta drift reddi; eski sürümle gönderimin durdurulması; kill switch.

## Açık kalanlar

1. Risk maddeleri/matris içeriği ve uzman iş akışı ekranları.
2. PDF/XLSX belge üretimi (P04 belge dilimi + P11).
3. Skor katkısı (P17), uygunsuzluk bağlantısı (P09), G4 review'ının otomatik tetiklenmesi (P07 tüketicisi).
4. Risk olayları henüz outbox'a yazılmıyor.
5. İstemci/native yüzey, canlı migration ve rollout.
