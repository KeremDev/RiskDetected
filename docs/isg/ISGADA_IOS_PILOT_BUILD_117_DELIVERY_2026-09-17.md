# İSGADA iOS canlı pilot build 117 teslimi — 17 Eylül 2026

## Sonuç

İOS uygulaması `2.0.3 (117)` olarak Apple Development kimliği ve
`com.riskdetected.app` bundle kimliğiyle imzalandı. Mevcut uygulama kaldırılmadan
Kerem'in eşleşmiş fiziksel iPhone'una kuruldu; böylece cihazdaki canlı oturum ve
uygulama verileri korundu. Uygulama cihazda başarıyla başlatıldı ve çalışan süreç
ile kurulu sürüm tekrar okundu.

Derleme `NOVA_PILOT_BUILD` koşuluyla ve yalnız onaylı canlı pilot hesap sınırıyla
üretildi. Başka kullanıcı bu özel pilot köküne geçirilemez.

## Canlı yayın ayarı

Canlı `analysis_result_hub_v1` bayrağında mevcut güvenlik önkoşulları doğrulandı:

- yayın modu `build_allowlist`;
- kill switch kapalı;
- önceki pilot build 116 listede;
- build 117 listede değil.

Yalnız `enabled_ios_builds` listesine `117` eklendi ve read-back ile doğrulandı.
`analysis_engine_v4`, Android değerleri, rollout modu, kill switch ve diğer
özellik bayrakları değiştirilmedi. Böylece analiz uzman görüşü ve eğitim önerisi
gibi sonuç merkezi bölümleri yeni pilot build'de yayın kapısına takılmaz.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| Workspace API/store ve staging güvenlik testleri | 15/15 geçti |
| Analysis result hub testleri | 5/5 geçti |
| Generic iOS device build | Başarılı |
| İmza | Apple Development / Team `68CU98HAY3` |
| Uygulama sürümü | `2.0.3 (117)` |
| Fiziksel cihaz kurulumu | Başarılı |
| Fiziksel cihaz açılışı | Başarılı |
| Çalışan süreç | `RiskDetected`, PID cihazdan doğrulandı |

Kanıtlar `output/isg/ios-pilot-2026-09-17/` dizinindedir. Bu dizinde build logu,
kurulum/açılış ve kurulu uygulama JSON çıktıları, canlı flag önce/sonra
snapshot'ları ve fiziksel cihaz ekran görüntüsü bulunur.

## Kapsam sınırı

Build, canlı kişisel pilotu çalıştırır ve yeni workspace istemcisini içerir.
Üretim veritabanında OSGB tenant migration/rollout paketi henüz yayınlanmadığı
için istemci güvenli biçimde mevcut kişisel pilot köküne düşer. Bu davranış eski
kullanıcıların akışını bozmaz. OSGB tenant ürününün üretimde görünmesi ayrıca
kontrollü production migration, pilot workspace üyeliği ve Faz L yayın kabulünü
gerektirir; bu teslim o geniş production rollout'u yapmaz.
