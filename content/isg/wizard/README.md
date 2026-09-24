# İSGADA yaşayan sihirbaz kataloğu

Bu dizin, Risk Analizi ve Acil Durum Planı sihirbazlarının düzenlenebilir kaynak içeriğidir. V4 teslimindeki kayıt kimlikleri korunmuştur. Uygulamada kullanılan sürüm V5'tir. İki platform aynı `App/WizardAssets/isg_wizard/engine.js` ve aynı JSON kataloğunu çalıştırır.

## Ürün sözleşmesi

- Firma seçimi isteğe bağlıdır. Tanımlı işyerleri varsa seçim sunulur; boş liste, hata veya önkoşul oluşturmaz. İşyerini seçmeden de devam edilir.
- Risk akışı 13, acil durum akışı 11 sorudan oluşur. Aynı sayfada açılıp kapanan adımlar kullanılır. Sorulara geri dönülebilir.
- Uzman onayı, doğrulama, yayın onayı veya kullanıcıyı durduran benzer bir adım yoktur.
- Kullanıcının belirtmediği puan, mevcut önlem, imza, ekip üyesi veya değerlendirme/geçerlilik tarihi üretilmez. Bunlar indirilen belgede düzenlenebilir alanlardır.
- Çıktı cihazda oluşturulur. İndirme için yeni sunucu endpoint'i gerekmez. Kullanıcı isterse Word çıktısını mevcut Dosyalarım servisine gönderir; şirket seçilmediyse kişisel kapsam kullanılır. Sunucu mevcut yetki ve dosya denetimini uygular.
- Tarihli risk değerlendirmesi/plan kaydı otomatik açılmaz. Dosya oluşturma zamanı geçerlilik tarihi değildir. Mevcut sürüm takibi ekranları kullanılmaya devam eder.

## Kaynaklar

| Dosya | Amaç |
|---|---|
| `source/config_authoring.py` | Tekil soru, alan, koşul, özellik ve risk eşlemeleri |
| `source/risk_v3_input.json` | Korunan risk kimlikleri, senaryolar ve birinci önlemler |
| `source/enrichment.tsv` | Olası zarar, önlem hiyerarşisi ve ikinci önlem |
| `source/additions.tsv` | Yeni risk kayıtları; mevcut kimlik tekrar kullanılmaz |
| `source/extensions.json` | Katalog sürümü, ek seçenekler, eş anlamlı arama adları, kart bağımlılıkları, genel roller |
| `source/severity.json` | Açıkça yazılmış ağır zarar önceliği; risk puanı değildir |
| `source/taxonomy_v3_input.json` | Sektör, ekipman ve görev yaprakları |
| `source/card_enrichment.tsv` | Acil durum kartlarının ayrıntılı adımları |
| `build.py` | Kaynaklardan JSON ve okunabilir katalog üretimi |
| `manifest.json` | Kaynak, çıktı ve ortak motor dosyalarının SHA-256 değerleri |

`data/` ve uygulama içindeki JSON elle değiştirilmez. Motor değişiklikleri ortak JavaScript kaynağına yapılır. Python V4 motoru uygulama çalışma zamanı değildir; iki ayrı motorun ayrışması önlenmiştir. `tests/v4_profiles.json` yalnız geçmiş kabul vakalarını korur; eski zorunlu işyeri sözleşmesi uygulanmaz.

## Yeniden üretim ve kontrol

Proje kökünden:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/isg/wizard/catalogue.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/isg/wizard/catalogue.py --check
node --test scripts/isg/wizard/engine.test.mjs
```

Manifest değişikliği bilinçli içerik sürümü değişikliğiyle birlikte incelenir. Her sürüm uygulama paketine sabitlenir. Arşivlenmiş/indirilmiş belgeler kendiliğinden güncellenmez; Word ve Excel paketi tam JSON içerik görüntüsünü de taşır. Belge kimliği, katalog ve motor sürümü çıktıda yazılıdır. Uygulama mağazası güncellemesiyle yeni katalog dağıtılır. İleride uzaktan içerik güncellemesi eklenirse imzalı veri, sürüm uyumluluğu ve son çalışan sürüme dönüş uygulanmalıdır; uzaktan JavaScript çalıştırılmaz.

## Yeni sektör veya ekipman ekleme

1. Yeni bilginin kapsamını yazın: faaliyet, ekipman, işler, enerji/kimyasal özellikler, maruz kalan kişiler ve acil durumlar.
2. Var olan kayıtları yeniden kullanın. Yeni senaryo gerekiyorsa benzersiz kimlik, bağlam, olay, zarar, 2–4 somut önlem, rol, konu dayanağı ve özellik koşullarını ekleyin.
3. Ekipmanın varlığı ile o ekipmana girilerek yapılan işi ayırın. Forkliftten gaz çıkaran akü şarjı, tanktan insanın tanka girmesi sonucu çıkarılmaz.
4. Ekipman/iş ve özellik eşlemesini ekleyin. Riskin hem kendi hem aile koşulunu sağlayan gerçek bir yanıt örneği yazın.
5. Aramada kullanılan günlük isimleri `aliases` alanına ekleyin. NACE kodu bilinmiyorsa tahmin etmeyin.
6. Bir olumlu ve bir olumsuz senaryo testi ekleyin; ilgisiz faaliyetlerin riskleri artmamalıdır.
7. Katalog sürümünü artırın, yeniden üretim/testleri çalıştırın ve örnek belgeyi inceleyin. Bu bakım kontrolleri kullanıcıya onay adımı eklemez.

## Güncel takip

Ürün kararları, yapılan işler, test kanıtları ve kalan geliştirmeler: `docs/isg/SIHIRBAZ_GELISTIRME_TAKIBI_2026-09-24.md`.
