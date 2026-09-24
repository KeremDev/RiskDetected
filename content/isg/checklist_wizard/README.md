# Kontrol listesi sihirbazı kataloğu

Kontrol listesi sihirbazı, risk ve acil durum sihirbazlarıyla aynı cevapları (faaliyet, takip soruları, alan, ekipman, madde, iş, çalışma koşulları) kullanır ve bunlardan kontrol konularını (paketleri) önerir. Bu klasör, sihirbazın kataloğunu üreten düzenlenebilir kaynakları tutar.

| Dosya | İçerik |
|---|---|
| `source/packs.json` | Yalnız sihirbazda bulunan genişleme paketleri (39 paket, 390 soru). |
| `source/triggers.json` | Her paketin hangi seçimlerle önerileceği ve 243 V6 faaliyetinin paket eşlemesi. |
| `../../../docs/isg/checklists/ISG_ADASI_CHECKLIST_SEED.json` | Sunucudaki katalog (117 paket, 200 şablon, 1.169 soru). Bu klasörden değiştirilmez. |
| `../../../App/WizardAssets/isg_wizard_v6/rd-data.json` | Tetiklerin işaret ettiği V6 taksonomisi. Üretilen dosyadır; burada düzenlenmez. |

Üretilen dosya: `App/WizardAssets/isg_wizard_v6/rd-checklist.json`. Elle düzenlenmez.

```sh
node scripts/isg/checklist_wizard/build.mjs          # kataloğu yazar
node scripts/isg/checklist_wizard/build.mjs --check  # kaynaklardan farklıysa başarısız olur
node --test scripts/isg/checklist_wizard/checklist.test.mjs
node scripts/isg/checklist_wizard/generate_extension_migration.mjs          # uzantı migration'ının seed bloğunu yazar
node scripts/isg/checklist_wizard/generate_extension_migration.mjs --check  # packs.json ile uyumsuzsa başarısız olur
node scripts/isg/checklist_wizard/db/run_database.mjs                       # migration'ı geçici bir Postgres'te sınar
```

## Çalışma zamanı

- `App/WizardAssets/isg_wizard_v6/rd-checklist.js` depoda tutulur. `rd-bridge.js` ve diğer `rd-*.js` dosyaları ise `~/Downloads/ISGADA_KATALOG_GENISLEME_V6` paketindeki `build.py` ile üretilir ve üzerine yazılır. Bu yüzden kontrol listesi modu üretilen köprüyü değiştirmez: `rd-checklist.js`, `rd-bridge.js`'den sonra yüklenir ve `RDBridge`'i sarar. Yalnız `start({mode: 'checklist'})` ile açılan oturumda devreye girer; risk ve acil durum modlarında her çağrı asıl köprüye gider.
- iOS (`NovaRiskWizardRuntime.swift`) ve Android (`NovaRiskWizardRuntime.kt`) aynı betik listesini `rd-checklist` ile bitirir ve `RDBridge.init(rd-data, rd-checklist)` çağırır. Kontrol listesi kataloğu bulunamazsa risk ve acil durum modları yine açılır.
- Sihirbaz metinlerinin tamamı `rd-checklist.js` içindeki `TEXT` sözlüğünden gelir; iki platform aynı Türkçe metni gösterir.

## Kaydetme

Liste, kontrol listesi modülünün mevcut şablon eylemleriyle Listelerim'e yayımlanır:

1. `draft_template` — başlık mevcut listelerle çakışırsa sona ` (2)` eklenir. Aynı başlık mevcut listenin yeni sürümünü açardı.
2. `copy_items` — katalog soruları doğrulama yöntemi, açıklama ve kaynaklarıyla kopyalanır; en fazla 100'lük gruplar. Temel sorular `checklist-tr-2026-09-15-v1` şablonlarından (`catalog_ins_01` …), genişleme soruları `checklist-tr-2026-09-25-ext1` şablonlarından (`catalog_ext_earthmove` …) gelir.
3. Genişleme kataloğu sunucuda yoksa (`20260925002500_checklist_catalog_extension_v1.sql` uygulanmamışsa) sunucu o şablonu `ACCESS_DENIED` ile reddeder, hiçbir şey yazılmaz. Kaydedici bir kez denedikten sonra o listedeki genişleme sorularını `set_item` ile kendi soru olarak yazar.
4. `set_item` — kullanıcının kendi soruları konu başlığıyla (`section_title`) yazılır.
5. `publish_template` — sürüm yayımlanır. Başarılı her şablon eylemi taslağın `edit_revision` değerini bir artırır; reddedilen eylem değiştirmez. Kaydedici beklenen revizyonu yerel olarak izler.

## Sunucu uzantı kataloğu

`supabase/migrations/20260925002500_checklist_catalog_extension_v1.sql`, genişleme paketlerini `checklist-tr-2026-09-25-ext1` katalog sürümü olarak ekler. Bu sürüm `extends_catalog_version` sütunuyla temel sürümü gösterir. Temel katalog değişmez. `read_checklists_company_v3` artık en yeni temel sürümü uzantılarıyla birlikte okur; yalnız en yeni sürümü okuması, uzantı eklenince 200 temel şablonu kütüphaneden düşürürdü. Uzantı satırları alan uzmanı onayına kadar `professional_review_status = 'pending'` kalır.

Uygulanmış bir migration değiştirilmez: `ext1`'deki paketler ve soru metinleri sabittir. Yeni paket veya metin değişikliği yeni bir uzantı sürümüyle (`…-ext2`) ve yeni bir migration'la gelir. `generate_extension_migration.mjs --check`, `packs.json` değişince başarısız olarak bunu hatırlatır. Kod kuralları `scripts/isg/checklist_wizard/codes.mjs` içindedir.

İki konuda ortak olan bir sunucu sorusu listeye bir kez girer (sunucu aynı atomik soruyu aynı kapsamla iki kez kopyalamaz).

## Yeni paket veya tetik ekleme

1. Mevcut paket yeterliyse yenisini açmayın; `triggers.json` içinde tetiğini genişletin.
2. Yeni paket `packs.json`'a eklenir: benzersiz büyük harfli kod, tür (`sector`, `hazard`, `activity`, `equipment`, `general`), eş anlamlılar, kaynaklar ve 6–12 soru. Her soru tek bir gözlenebilir veya doğrulanabilir durumu sorar, `?` ile biter, 200 karakteri aşmaz.
3. Yöntem: `G` görsel kontrol, `K` kayıt/plan doğrulama, `Y` yetkin kişinin güvenli işlev kontrolünü doğrulama. Uzmana tehlikeli bir deney yaptıran soru yazılmaz.
4. Kaynak kimlikleri seed kaynaklarından veya `rd-data.json` içindeki mevzuat anahtarlarından (`TR-…`) seçilir; üretici bilinmeyen kimliği reddeder.
5. `triggers.json` içine tetik ekleyin. `f` özellik, alan veya koşul; `eq` ekipman; `eg` ekipman grubu (`rd-data.json` içindeki `g`); `tk` iş; `mt` madde. Genel özellikler geniş etki yapar: örneğin `machinery` forklift ve rafları da kapsar, bu yüzden makine koruyucuları ve enerji izolasyonu ekipman gruplarıyla tetiklenir.
6. Olumlu ve olumsuz test ekleyin (`checklist.test.mjs`): ilgili seçimde paket gelmeli, benzer fakat ilgisiz seçimde gelmemeli.
7. `build.mjs` çalıştırın; sürümü değiştiren içerik değişikliklerinde `VERSION` değerini artırın.

Üretici şunları reddeder: bilinmeyen özellik, ekipman, iş veya madde kimliği; eşlemesi olmayan V6 faaliyeti; yalnız aramayla bulunabilen paket; tekrar eden soru metni; bilinmeyen kaynak.
