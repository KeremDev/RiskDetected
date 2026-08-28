# Analiz Kalitesi Uzman İncelemesi V1

Bu paket, Faz 1 ölçümünden sonra mevcut motor / ablation / clean-room vNext
kararını vermek içindir. Değerlendirme otoritesi ürünü kullanan İSG uzmanıdır.
Fotoğraflar açıkça istenmedikçe repoya eklenmez; değerlendirme kaydı yalnız
analysis ID, fotoğraf SHA-256 değerleri ve uzman kararlarını içerir.

## Sabit çalışma koşulları

- Aynı üç fotoğrafla dört ayrı analiz çalıştırılır.
- Plan, safety profile, çıktı dili, canvas, uygulama build'i, model ve provider
  dört tekrarda aynı tutulur.
- Analiz tamamlanmadan ve ölçüm alınmadan kullanıcı düzenlemesi yapılmaz.
- Ek set iki tek-fotoğraf ve iki üç-fotoğraf analizinden oluşur.
- Mümkünse ek sette makine/proses ile saha/inşaat örnekleri dengelenir.
- Her çalıştırmadan sonra `admin_analysis_quality_run_v1(analysis_id)` sonucu
  değerlendirme dosyasındaki ilgili çalıştırmaya bağlanır.

## Bulgular için değerlendirme ölçeği

Her analizde aşağıdaki bilgiler doldurulur:

1. Fotoğraf bazında beklenen bağımsız fiziksel tehlikeler.
2. Kaçırılan kritik ve diğer tehlikeler.
3. Görsel kanıtı olmayan veya desteklenmeyen bulgular.
4. Yanlış biçimde tek bulguda birleştirilen tehlikeler.
5. Her görünür finding için uzman tarafından doğru kabul edilen Fine-Kinney
   `P`, `F`, `S` değerleri.
6. Düzeltici önlem ve önleyici kontrol için `uygun`, `revize` veya
   `kullanılamaz` kararı.
7. Genel sonuç için `kullanılabilir`, `kısmen` veya `kullanılamaz` kararı.
8. Kararı açıklayan serbest uzman notu.

Modelin `F` değeri her bulguda sayısal olmalıdır. Trace içinde
`fk_frequency_missing_fallback` görülürse kullanıcıya yine sayısal skor
gösterilir; ancak uzman değerlendirmesinde fallback ayrıca işaretlenir.

## Karar kapısı

Mevcut motor, ham model beklenen kritik tehlikeleri sabit dört tekrarın en az
üçünde yakalıyor ve kayıp bir veya iki deterministik aşamaya indirgenebiliyorsa
iyileştirilir. Sorumlu politika trace ile ayrışıyor fakat doğru ayar belli
değilse production davranışını etkilemeyen internal ablation hazırlanır.

Kritik bir tehlike dört tekrarın en az ikisinde ham model tarafından
kaçırılıyorsa; aynı finding'in P/F/S değerleri kabul edilemez biçimde
değişiyorsa; veya kusurlar prompt, schema ve birden fazla normalization
katmanına yayılıyorsa clean-room vNext yönü seçilir.

Sekiz analizlik paket yayın kanıtı değildir; yatırım yolunu seçen teşhis
kapısıdır.

## Service-role ölçüm sorguları

Migration Edge instrumentation'dan önce yayınlanır. Edge yayınından sonra her
çalıştırma için tek analiz özeti alınır:

```sql
select public.admin_analysis_quality_run_v1(
  '<analysis-id>'::uuid
);
```

Yedi günlük pencere ve önceki 28 günlük baseline karşılaştırması:

```sql
select public.admin_analysis_quality_metrics_v1(7, 28);
```

Alarm olayları yalnız service-role ile incelenir:

```sql
select rule_key, severity, status, metric_value, threshold, created_at
from public.admin_alert_events
where rule_key like 'analysis_%'
order by created_at desc;
```
