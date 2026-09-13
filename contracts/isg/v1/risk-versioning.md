# Risk değerlendirmesi sürümleme — v1 sunucu sözleşmesi

13 Eylül 2026. P08'in ilk dilimi. Mevcut fotoğraf analizi ve bulguları **yalnız kaynak** olarak okunur; hiçbir legacy satır yazılmaz, güncellenmez veya otomatik risk değerlendirmesine dönüştürülmez.

Migration: [20260913190000_isg_risk_versioning.sql](../../../supabase/migrations/20260913190000_isg_risk_versioning.sql).

## Dört işlem türü ve tarih etkisi

| Tür | Yeni kayıt | Tarih / takip etkisi | Engellenen davranış |
|---|---|---|---|
| `full` (tam yenileme) | Yeni esas sürüm + uzman doğrulaması | Dönem **gerçek `assessment_on`** tarihinden işler | Bugünü veya dosya yükleme gününü esas tarih saymak |
| `partial` (kısmi revizyon) | Scope'lu sürüm + etki listesi | Yalnız listelenen hedefler incelenir | Bütün işyerinin vadesini sıfırlamak |
| `metadata` (düzeltme) | Gerekçeli düzeltme sürümü | Vade değişmez | Geçmiş belgeyi üzerine yazmak |
| `rescan` (daha iyi tarama) | Yeni dosya varyantı + kaynak hash | Vade ve esas tarih değişmez | Yeni yükleme gününü yenileme saymak |

`full` dışındaki türler `assessment_on` alamaz; farklı bir tarih gönderilirse `ASSESSMENT_DATE_IMMUTABLE`. Gelecek tarih `ASSESSMENT_DATE_IN_FUTURE` ile reddedilir; 10 yıldan eski tarih reddedilmez ama `date_needs_review` ile işaretlenir. Aynı anda tek taslak açık olabilir.

## Dönem kaynağı

`full` finalize'ında dönem ya **yayımlanmış bir kural sürümünden** gelir (`period_source='rule_version'`) ya da açıkça verilen bir fixture değerinden gelir — o durumda `period_source='unapproved_fixture'` ve `period_needs_review=true`. Yayımlanmamış kural `RULE_NEEDS_REVIEW` verir. Hesap P06'nın takvim-yılı fonksiyonuyla yapılır.

## Kaynak bulgu, drift ve gönderim

Bulgu risk kaydına **yalnız uzman seçtiği için** girer: `attach_risk_source` seçilen alanların kopyasını ve kaynak sürümünü saklar, yanıtı `legacy_analysis_written=false` der. Kaynak analiz ilerlerse `flag_source_drift` yalnız bir **inceleme önerisi** üretir: finalize edilmiş belgenin tarihi, vadesi ve durumu değişmez.

Finalize tek kazanandır: ikinci cihaz eski `expected_current` ile gelirse `VERSION_CONFLICT`. Belge gönderen her iş `assert_current_risk_version` ile güncel sürümü kanıtlamak zorundadır; kuyrukta bekleyen eski sürüm gönderilemez.

## Henüz olmayanlar

Risk maddeleri/matris içeriği, PDF-XLSX üretimi, skor katkısı (P17), uygunsuzluk bağlantısı (P09), G4 review'ının otomatik tetiklenmesi ve istemci/native yüzey bu dilimde yoktur. `risk` rollout satırı kapalıdır ve istemciye GRANT verilmemiştir.
