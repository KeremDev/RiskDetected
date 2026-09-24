# Kontrol listesi sihirbazı — geliştirme kaydı

Tarih: **25.09.2026** · Katalog: **isgada-kontrol-1.1.0** (sunucu kataloğu `checklist-tr-2026-09-15-v1` ve uzantısı `checklist-tr-2026-09-25-ext1`)
Durum: iOS ve Android'de kodda tamamlandı ve commit edildi; dağıtım yapılmadı. Gerçek hesapla Listelerim'e kaydetme henüz denenmedi.

## Kullanıcı akışı

Kontroller ekranında ve Kontrol Listeleri › Listelerim bölümünde **Sihirbaz ile liste oluştur** düğmesi açılır. Risk ve acil durum sihirbazlarıyla aynı kabuk ve aynı ilk sorular kullanılır:

1. İşyeri (isteğe bağlı firma), faaliyet, takip soruları, alanlar, ekipmanlar, maddeler, işler, çalışma koşulları.
2. **Liste türü:** periyodik İSG saha denetimi, ekipman kullanım öncesi kontrolü veya iş başlamadan önce kontrol. Saha denetiminde isteğe bağlı sıklık (günlük / haftalık / aylık) genel tur listesini ekler. Düzen: tek liste (konu başlıklarıyla) veya her konu ayrı liste.
3. **Konular:** seçimlerden gelen öneriler gerekçeleriyle; faaliyetin kendi konuları önce, her işyerindeki konular (yangın, tahliye, ilk yardım, elektrik) sonda. Kapatılabilir, aramayla yeni konu eklenebilir.
4. **Sorular:** her konu açılıp soru soru kaldırılabilir; konuya veya listenin sonuna kendi sorunuz eklenebilir.
5. **Özet:** liste adı düzenlenir.
6. **Sonuç:** Word (sahada doldurulacak form: U / UD / GD sütunları, açıklama, uygunsuzluk tablosu, imza), Excel (açılır listeli sonuç sütunu), PDF; **Listelerime kaydet** ve kaydedilen listeyle **Kontrolü başlat** (mevcut başlatma akışına geçer; işyeri ve tarih orada seçilir).

Sihirbaz kendiliğinden kontrol başlatmaz, uygunsuzluk açmaz, mevzuata uygunluk beyanı yapmaz.

## İçerik

| | Sunucu kataloğu | Sihirbaz kataloğu |
|---|---:|---:|
| Konu paketi | 117 | **156** (39 yeni) |
| Soru | 1.169 farklı | **1.560** (390 yeni) |
| Faaliyet eşlemesi | 24 sektör | **243 V6 faaliyeti**, tamamı eşli |
| Ekipman / iş / madde tetikleri | — | V6 kataloğundaki 540 ekipman, 470 iş, 97 madde kimliğiyle |

Yeni paketler: iş makinesi, şirket aracı ve ağır vasıta, tehlikeli madde taşıma (ADR), akaryakıt/LPG ikmal, döküm, cam, plastik enjeksiyon, yanıcı toz/ATEX, amonyaklı soğutma, basınçlı kap/otoklav, asansör/yürüyen merdiven, motorlu testere/ağaç kesimi, zirai ilaçlama/biyosidal, sondaj, enerji hattı/trafo, doğal gaz şebeke ve iç tesisat, kule tırmanışı, akü/UPS/lityum, veri merkezi, sahne/etkinlik, kuaför/güzellik, doğal taş, tahıl/yem/gübre, asfalt/bitüm, trafiğe açık yolda çalışma, iyonlaştırıcı radyasyon, hasta taşıma, motorlu kapı/kepenk, alt işveren, özel politika gerektiren çalışanlar, şiddet/nakit riski, yıkım/asbest, çelik-prefabrik montaj, arıtma tesisi, klima santrali/soğutma kulesi, moto kurye, müşteri adresinde servis, kriyojenik/inert gaz, endüstriyel fırın.

Kaynaklar ve bakım yolu: [content/isg/checklist_wizard/README.md](../../content/isg/checklist_wizard/README.md).

## Mimari

- `App/WizardAssets/isg_wizard_v6/rd-checklist.js` (depoda) `RDBridge`'i sarar; üretilen `rd-*.js` dosyalarına ve `build.py`'a dokunulmadı.
- `rd-checklist.json`, `scripts/isg/checklist_wizard/build.mjs` ile kaynaklardan üretilir ve doğrulanır.
- iOS: `NovaRiskWizardScreen(mode: "checklist")`, sayfalar `NovaChecklistWizardViews.swift`. Android: `NovaRiskWizardScreen(mode = "checklist")`, sayfalar `NovaChecklistWizardPages.kt`.
- Kaydetme mevcut `draft_template` / `copy_items` / `set_item` / `publish_template` eylemleriyle yapılır.

## Sunucu uzantı kataloğu (hazırlandı, uygulanmadı)

`supabase/migrations/20260925002500_checklist_catalog_extension_v1.sql`:

- 39 genişleme paketini `checklist-tr-2026-09-25-ext1` katalog sürümü olarak ekler (39 ürün şablonu, 390 madde, 390 atomik soru, 27 yeni mevzuat kaynak kaydı). Temel katalog `checklist-tr-2026-09-15-v1` değişmez.
- `checklist_catalogs.extends_catalog_version` sütununu ekler. `read_checklists_company_v3` en yeni temel sürümü uzantılarıyla birlikte okur. Önceki davranış yalnız en yeni sürümü okuyordu; uzantı eklenince 200 temel şablon kütüphaneden düşerdi. Fonksiyonun geri kalanı değişmedi.
- Uzantı satırları `pending` durumundadır; alan uzmanı onayı ayrı bir migration'la verilir (temel katalogdaki `20260921133000` gibi).
- Seed bloğu `packs.json`'dan `generate_extension_migration.mjs` ile üretilir; `--check` ile doğrulanır.
- Canlı proje bu zinciri taşımıyor ve temel katalog v1 de canlıda yok. Bu migration geliştirme zinciri ve staging içindir.

Uygulama tarafı migration'a bağlı değildir. Uygulandığı sunucuda genişleme soruları doğrulama yöntemi ve açıklamasıyla kopyalanır. Uygulanmadığı sunucuda sunucu bu şablonları reddeder; kaydedici bir denemeden sonra bu soruları kendi soru olarak yazar.

## Doğrulama (25.09.2026)

| Kontrol | Sonuç |
|---|---|
| Katalog üretimi ve `--check` | Geçti |
| Node testleri (`checklist.test.mjs`) | **17/17** — 243 faaliyetin hepsine konu, sunucu referanslarının tamamı (1.170) gerçek şablon maddesiyle eşleşiyor, risk/acil durum modları değişmedi |
| iOS simülatör derlemesi | Geçti, değişen dosyalarda uyarı yok |
| iOS çalışma zamanı testleri (`NovaRiskWizardTests`) | **4/4** — kontrol listesi modu, dışa aktarım ve sahte istemciyle kaydetme sırası |
| iOS arayüz testi | **1/1** — firmasız akış, konular, sorular, sonuç sayfası; ekran görüntüleri incelendi |
| Android derlemesi (`feature:nova`, `isg-design-preview`) | Geçti (`b5580546` üzerinde, ana çalışma ağacında) |
| Android cihaz testleri (API 33) | **2/2** — yeni `NovaChecklistWizardRuntimeTest` ve mevcut `NovaDocumentWizardRuntimeTest`; test varlıkları `src/androidTest/assets/isg_wizard_v6` bağlantısıyla gelir |
| Android önizleme uygulaması | Kontroller › sihirbaz › sonuç sayfasına kadar elle yürütüldü |
| Word / Excel | ZIP ve XML ayrıştırması geçti; Word ilk sayfası görsel olarak incelendi |
| Uzantı migration'ı (yerel Postgres, `db/run_database.mjs`) | Geçti. Gerçek v1 DDL ve seed ile onay migration'ı üzerinde: temel 200/2.000 değişmedi; uzantı 39/390; kütüphane ve başlatma kataloğu 239 şablon okuyor; sektör/tür filtreleri ve soru araması uzantıyı buluyor; ikinci uygulama hiçbir şeyi değiştirmiyor. Docker kapalı olduğu için tam Supabase zinciri tekrar oynatılmadı |
| Kaydedici, iki sunucu durumu | iOS ve Android testlerinde: uzantı varken 390 soru kopyalanıyor, yokken tek red sonrası kendi soru olarak yazılıyor; revizyonlar ve konumlar kesintisiz |
| Yerelleştirme kapıları | Tek yeni anahtar (`localizable.nova.checklist.wizard.open`) için L10N-018 kilidi güncellendi. Katalog kapıları 23/25; kalan iki kırmızı (L10N-004, L10N-013) HEAD'de aynı listeyle kırmızı. Hard-coded kontrol tabanla aynı. `localization_inventory --check` HEAD'de zaten eski |

## Açık işler

- [ ] Gerçek staging hesabıyla Listelerim'e kaydetme, tekrar kaydetme (başlık çakışması) ve **Kontrolü başlat** geçişi.
- [x] Genişleme paketlerini sunucu kataloğuna alan migration hazırlandı (`20260925002500`).
- [ ] Migration'ı staging'e uygulamak ve kütüphane, başlatma ve sihirbaz kaydını gerçek hesapla denemek.
- [ ] Canlıya taşımak: canlıda katalog v1 de yok; ikisi birlikte, kırpılmış bir pilot paketi olarak hazırlanmalı.
- [ ] Yeni 390 sorunun alan uzmanı incelemesi (sunucu kataloğundaki 1.169 soru için pilot onayı var; yenileri için yok).
- [ ] Uygulama içinde yarım kalan sihirbaz oturumunu kaydetme (şu an ekran kapanınca cevaplar kaybolur; diğer sihirbazlarla aynı).
