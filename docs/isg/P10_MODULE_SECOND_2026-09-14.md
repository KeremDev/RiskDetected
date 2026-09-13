# P10 ikinci dilim — yedi modül daha

14 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; rollout ve on iki modül anahtarının tamamı kapalı, canlıya uygulanmadı.**

İlk dilim beş modülü kapsıyordu. Bu dilimle §7.5'in **on iki** başlığı sunucu tarafında karşılandı: ISG-KATİP sözleşme takibi, yıllık çalışma planı, yıllık eğitim planı, kurul/toplantı/karar, çalışma izni formu, saha ziyareti/gözlem ve onaylı defter arşivi eklendi. Kalan dört başlık başka fazlara ait: evrak merkezi P11, taşeron paketi P05/P11, portföy P17, ürün rehberliği P18.

Migration: [20260914010000_isg_module_core_second.sql](../../supabase/migrations/20260914010000_isg_module_core_second.sql) · Sözleşme: [modül domainleri](../../contracts/isg/v1/module-domains.md) · [Kanıt](evidence/P10_MODULE_SECOND_2026-09-14.json).

## Üç iddia yapısal olarak imkânsız

Planın "iddia edilmeyecek" dediği üç şey birer CHECK kısıtıyla kapatıldı; sadece varsayılan değerle bırakılmadı:

- `katip_contracts.official_integration` → yalnız `false` olabilir. Resmî sisteme giriş, scrape veya otomatik bildirim yok.
- `work_permit_forms.authorises_work` → yalnız `false` olabilir; tabloda `approved_by`/`approved_at`/`work_started_at` gibi bir sütun da yok. Form bir belgedir, yetki makinesi değildir.
- `notebook_archive_entries.ai_text_is_official_record` → yalnız `false` olabilir. Kayıt yalnız taranmış imzalı kopyadır; AI taslağı köken referansıdır.

Testte üçü de doğrudan `UPDATE` ile zorlandı ve üçü de `CHECK_VIOLATION` verdi.

## Diğer modül kuralları

- **Yıllık çalışma planı:** işyeri+yıl başına tek plan; faaliyetin planlanan tarihi planın takvim yılında olmak zorunda; kayan faaliyet gerekçeli ve **sonraki yıla** taşınır; **planı kapatmak hiçbir maddeyi gerçekleşmiş yapmaz** (kapanış yanıtı `items_marked_performed_by_closing: 0` döner ve madde `planned` kalır).
- **Yıllık eğitim planı:** bir ihtiyaçtır, tamamlanma değildir; mükerrer plan tekil anahtarla engellenir; gerçekleşme P07'nin eğitim planına bağlanır ve completion sayısı yalnız eğitim domaininden okunur, kopyalanmaz.
- **Kurul:** gönüllü kullanım `counts_towards_legal_score=false` ile kaydedilir; katılım bir snapshot'tır, hesap/rol/portal açılmaz; planlı toplantıda katılım ve karar bulunmaz.
- **Saha ziyareti:** firma kapsamlıdır, kişisel not defteriyle birleşmez; iki tabloda da sağlık/klinik sütunu yoktur (canlı `information_schema` sorgusuyla doğrulandı); seçilen gözlem P09'da tek bir uygunsuzluk açar.

## Test kanıtı

`--synthetic-session` → **621/621 PASS** (33'ü bu dilimin yeni kontrolü), cleanup PASS. `--isolated-copy --p05-upgrade` → **29/29 PASS**: tam legacy kopyada **on üç** migration replay, 84 tablo, hepsinde RLS, on iki modül anahtarı da kapalı; legacy satır ve fonksiyon gövdeleri değişmedi. Offline foundation **216 PASS**.

Ayrıca: faz kapısının modül anahtarından önce cevap vermesi; açık uçlu ve süreli sözleşme ayrımı; sözleşmenin referans başına tekilliği; plan yılı uyuşmazlığı; gerekçesiz ve aynı/önceki yıla taşıma reddi; kapalı plana madde eklenememesi; bilinmeyen katalogla eğitim planı reddi; toplantının katılımsız yapılamaması; kararların numaralandırılması; kirli belgeyle render reddi; aynı ziyaretin tek kayıt olması; gözlemin tekrar tıklamada ikinci uygunsuzluk açmaması; imzasız defter kaydının reddi; tek modülü durdurmanın diğerlerini etkilememesi; kill switch.

## Açık kalanlar

1. Evrak/rapor merkezi (P11), taşeron paketi, portföy (P17), ürün rehberliği (P18).
2. Belge/PDF-XLSX üretimi, task ve bildirim tetikleyicileri, skor katkısı.
3. Modül olayları henüz outbox'a yazılmıyor.
4. İstemci/native yüzey, canlı migration ve rollout.
