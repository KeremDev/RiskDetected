# Prompt Sistemi Yenileme Planı

> Güncel tek yapılacaklar özeti için bkz. `PROJECT_STATUS_AND_NEXT_2026-05-12.md`.
> Bu dosya prompt revamp planının tarihsel ayrıntılarını korur; prompt sisteminin uygulanan/kalan durumu status dosyasında özetlenmiştir.

Kaynak dosya: `/Users/keremkayalar/Downloads/isg_ai_odakli_analiz_prompt_seti.docx`

Tarih: 2026-05-11

## Amaç

RiskDetected analiz motorunu yeni "AI Odaklı İSG Fotoğraf Analizi Prompt Seti"ne geçirmek. Hedef sadece canvas metinlerini değiştirmek değil; iOS seçim ekranı, Supabase Edge Function, AI cevap şeması, veritabanı kaydı, sonuç ekranı ve rapor çıktılarının aynı prompt mantığıyla çalışması.

Yeni prompt yaklaşımı şu eksenlere dayanıyor:

- Fotoğrafı Türkiye İSG mevzuatı perspektifiyle analiz etmek.
- Yalnızca görüntüde görülen bulgulara dayanmak.
- Emin olunmayan veya ölçüm gerektiren konuları "kontrol edilmeli" / "ölçümle doğrulanmalı" olarak işaretlemek.
- Bulguları kısa, net, denetim odaklı ve uygulanabilir üretmek.
- Her bulguda tehlike, olası risk/sonuç, risk derecesi, acil önlem ve Türkiye mevzuat karşılığı üretmek.
- Her analizde tek canvas seçilecek; çoklu canvas seçimi kaldırılacak.
- Fine-Kinney ve 5x5 ham girdileri yeni prompt sisteminde de istenecek; skorları yine sistem hesaplayacak.

## Mevcut Durum

### iOS

Canvas listesi ve kullanıcıya görünen kısa açıklamalar burada:

- `App/Models/AnalysisCanvas.swift`
- `App/Views/Home/CanvasSheet.swift`

Şu an iOS tarafındaki `AnalysisCanvas.body` metinleri sadece UI açıklaması. AI'a giden asıl prompt Supabase Edge Function içinde. Yeni UX kararına göre canvas kartlarında yalnızca başlık gösterilecek; alt metin/body kullanıcıya gösterilmeyecek.

### Backend / Edge Function

Asıl AI prompt burada üretiliyor:

- `supabase/functions/analyze/index.ts`
- `Supabase/functions/analyze/index.ts`

Not: Repoda hem `supabase` hem `Supabase` klasörü var ve `analyze/index.ts` içerikleri şu an aynı görünüyor. Değişiklik yapılırken ikisinin deployment/versiyonlama amacı netleştirilmeli. Şimdilik risk almamak için ikisi de senkron tutulmalı.

Mevcut prompt mimarisi:

- `CANVAS_FOCUS` içinde canvas bazlı kısa odak cümleleri var.
- `buildSystemPrompt(canvases, isPro)` bu odakları birleştiriyor.
- AI'dan JSON bekleniyor.
- Free için en fazla 4, Pro için en fazla 14 bulgu isteniyor. Yeni hedef: Free 4, Pro 10 bulgu.
- Fine-Kinney ve 5x5 ham girdileri isteniyor.

Mevcut cevap şeması:

- `hazards[].title`
- `hazards[].category`
- `hazards[].observed_evidence`
- `hazards[].description`
- `hazards[].recommended_action`
- `hazards[].references`
- `hazards[].confidence`
- Fine-Kinney ham değerleri
- 5x5 ham değerleri
- `ai_summary`
- `limitations`

### Veritabanı

Mevcut kayıt modeli yeni promptu kısmen taşıyabilir:

- `analyses.canvas`: sadece primary canvas id tutuluyor.
- `raw_ai_response`: tam AI cevabını geçici olarak saklıyor, retention ile temizleniyor.
- `findings.description`: gözlem + açıklama birlikte yazılıyor.
- `findings.recommended_action`: tek aksiyon alanı.
- `findings.references_text`: mevzuat metni için kullanılabilir.

Eksik kalan noktalar:

- Tek canvas kararından sonra `analyses.canvas` MVP için yeterli kalabilir; ileride audit için seçilen canvas metadata'sı ayrıca tutulabilir.
- Acil önlem ayrı alan değil.
- Olası risk/sonuç ayrı alan değil.
- Mevzuat karşılığı ayrı ve normalize alan değil.
- "İlk 3 öncelikli aksiyon" için ayrı yapı yok.
- Prompt versiyonu kalıcı ve kolay sorgulanabilir şekilde tutulmuyor.

## DOCX'ten Gelen Yeni Prompt Seti

### Ortak Ana Prompt

Model, fotoğrafı Türkiye İSG mevzuatı perspektifiyle ve iş güvenliği uzmanı saha gözlemi gibi analiz etmeli. Sadece görüntüde görülen bulgulara dayanmalı. Görünmeyen veya emin olmadığı noktaları "kontrol edilmeli" diye belirtmeli.

Çıktı mantığı:

1. Genel özet
2. Bulgular:
   - Tehlike
   - Olası risk/sonuç
   - Risk derecesi: Düşük / Orta / Yüksek / Kritik
   - Acil önlem
   - Türkiye mevzuat karşılığı
3. İlk 3 öncelikli aksiyon

Mevzuat tarafında kanun/yönetmelik başlığı yazılmalı. Madde numarası, ölçüm değeri veya standart numarası uydurulmamalı; emin değilse "doğrulanmalı" denmeli.

### Canvas Seçim Kuralı

Kullanıcı her analizde yalnızca bir odak kartı seçebilmeli. Backend yine gelen payload'ı normalize etmeli; birden fazla canvas gelirse ilk geçerli canvası almalı veya validation hatası dönmeli. Tercih edilen davranış: iOS tarafında tek seçim, backend tarafında güvenlik için tek canvas zorunluluğu.

### Canvas Promptları

- Genel: Görüntüdeki tüm görünür İSG uygunsuzluklarını tara; düşme, çarpma, sıkışma, elektrik, yangın, kimyasal, düzen-temizlik, KKD, işaretleme, acil çıkış ve çalışma alanı risklerini önceliklendir.
- KKD: Baret, gözlük/yüz koruma, eldiven, iş ayakkabısı, reflektif yelek, solunum koruması, kulak koruması, emniyet kemeri ve kullanım/uygunluk eksiklerini değerlendir.
- Makine: Koruyucular, döner/hareketli parçalar, sıkışma-ezilme-kesilme riskleri, acil durdurma, bakım-kilit/etiketleme, periyodik kontrol ve yetkisiz erişim uygunsuzluklarını analiz et.
- Uyarı levhaları: Uyarı, yasak, zorunluluk, acil çıkış, yangın ekipmanı, yönlendirme, zemin/alan işaretlemesi, görünürlük, konum ve eksik işaret risklerini belirt.
- Elektrik: Pano, kablo, priz, topraklama, kaçak akım, açık iletken, izolasyon, dağınık kablolama, nem/sıvı teması, yetkisiz erişim ve elektrik çarpması/yangın risklerini değerlendir.
- Sektör: Sektör bağlamını tahmin et; inşaat, üretim, depo/lojistik, ofis veya saha çalışmasına özgü tipik İSG risklerini görünür bulgularla ilişkilendir. Tahmin belirsizse açıkça belirt.
- Yangın: Yanıcı/parlayıcı malzeme, sıcak çalışma, elektrik kaynaklı yangın, söndürücü erişimi, yangın dolabı, acil çıkış, tahliye yolu, depolama düzeni ve yangın yükünü analiz et.
- Ergonomi: Uygunsuz duruş, elle kaldırma-taşıma, itme-çekme, tekrar eden hareket, uzun süreli statik çalışma, ekranlı çalışma, çalışma yüksekliği ve kas-iskelet zorlanmalarını belirt.
- Ortam Ölçümü: Gürültü, toz, gaz/buhar, aydınlatma, sıcaklık, havalandırma, titreşim ve kimyasal maruziyet gibi ölçüm gerektiren başlıkları "ölçümle doğrulanmalı" olarak yaz.
- Patlama: Patlayıcı atmosfer, gaz/buhar/toz birikimi, yanıcı depolama, basınçlı kap, statik elektrik, kıvılcım/ateşleme kaynağı, havalandırma, Ex ekipman ve patlamadan korunma dokümanı ihtiyacını değerlendir.
- Çevre: Atık yönetimi, sızıntı/dökülme, kimyasal depolama, drenaj, toprak/su kirliliği, emisyon/toz yayılımı, saha düzeni ve çevresel acil durum risklerini analiz et.
- Mevzuat: Görüntüdeki bulguları Türkiye İSG mevzuatı açısından eşleştir. 6331, Risk Değerlendirmesi, KKD, İş Ekipmanları, Sağlık ve Güvenlik İşaretleri, Acil Durumlar, Yapı İşleri, İş Hijyeni, Patlayıcı Ortamlar vb. başlıklarla ilişkilendir. Emin olmadığın maddeyi uydurma.
- Yüksekte Çalışma: Düşme tehlikesi, korkuluk, iskele, merdiven, platform, yaşam hattı, ankraj, emniyet kemeri, boşluk/kenar koruması, düşen cisim ve erişim güvenliğini analiz et.
- Hareketli Ekipman: Forklift, transpalet, vinç, kamyon, araç-yaya ayrımı, kör nokta, hız, manevra alanı, yük güvenliği, geri görüş, uyarı sistemi ve çarpma/ezilme risklerini belirt.
- Genel Premium: Tüm görünür İSG risklerini denetim odaklı ve ayrıntılı analiz et. Bulguları kritik seviyeden düşüğe sırala; her biri için kök neden, olası kaza senaryosu, acil aksiyon ve mevzuat karşılığını ver.
- İş Makineleri: Ekskavatör, yükleyici, vinç, kazıcı, kaldırıcı ve saha araçlarında devrilme, ezilme, kör nokta, operatör görüşü, yük kaldırma, zemin stabilitesi, bakım/periyodik kontrol ve yetkisiz yaklaşma risklerini analiz et.

### Mevzuat Havuzu

Öncelikli mevzuat başlıkları:

- 6331 sayılı İş Sağlığı ve Güvenliği Kanunu
- İş Sağlığı ve Güvenliği Risk Değerlendirmesi Yönetmeliği
- Kişisel Koruyucu Donanımların İşyerlerinde Kullanılması Hakkında Yönetmelik
- İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği
- Sağlık ve Güvenlik İşaretleri Yönetmeliği
- İşyerlerinde Acil Durumlar Hakkında Yönetmelik
- Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği
- Çalışanların Patlayıcı Ortamların Tehlikelerinden Korunması Hakkında Yönetmelik
- İş Hijyeni Ölçüm, Test ve Analizleri Hakkında Yönetmelik
- Tozla Mücadele, Gürültü, Titreşim, Kimyasal Maddeler, Elle Taşıma İşleri ve Ekranlı Araçlarla Çalışma yönetmelikleri

## Önerilen Mimari

### 1. Prompt Registry Oluştur

Yeni dosya önerisi:

- `supabase/functions/analyze/prompts.ts`

İçerik:

- `PROMPT_VERSION = "isg-photo-v2026-05-11"`
- `COMMON_ANALYSIS_PROMPT`
- `SINGLE_CANVAS_RULE`
- `LEGISLATION_POOL`
- `CANVAS_PROMPTS`
- `PRO_CANVASES`

Avantajı:

- `index.ts` sadeleşir.
- Prompt versiyonu tek yerden yönetilir.
- Test yazmak kolaylaşır.
- iOS ve backend metinlerinin ayrışması daha kontrollü olur.

Risk:

- Supabase Edge Function Deno import yolu doğru ayarlanmalı.
- Deployment sırasında `prompts.ts` dosyasının da function klasörüne dahil edildiği doğrulanmalı.

### 2. iOS Canvas Seçimini ve Kart Görünümünü Güncelle

Dosya:

- `App/Models/AnalysisCanvas.swift`

Yapılacak:

- Kullanıcı yalnızca 1 canvas seçebilecek.
- Canvas kartlarında sadece başlık gösterilecek.
- Alt metin/body kullanıcıya gösterilmeyecek.
- `body` alanı iOS tarafında gerekirse veri modeli uyumluluğu için kalabilir, ancak UI'da kullanılmayacak.

Öneri:

- iOS `body`: UI'da gösterilmez; backend promptunun kaynağı değildir.
- Backend `CANVAS_PROMPTS`: tam profesyonel prompt.

### 3. Edge Function Prompt Builder'ı Yenile

Dosya:

- `supabase/functions/analyze/index.ts`
- `Supabase/functions/analyze/index.ts`

Yapılacak:

- `CANVAS_FOCUS` yerine yeni `CANVAS_PROMPTS` kullanılacak.
- `buildSystemPrompt` şu bölümleri üretecek:
  - Rol: deneyimli İSG/HSE uzmanı
  - Görsel kanıt kuralı
  - Ortak çıktı kuralları
  - Seçilen tek canvas promptu
  - Tek canvas zorunluluğu
  - Mevzuat havuzu
  - JSON zorunluluğu
  - Fine-Kinney ve 5x5 ham değer kuralları; skor hesaplama yine backend/DB tarafında yapılacak
  - Free 4 / Pro 10 bulgu limiti

Önemli:

- DOCX'te tablo formatı öneriliyor, ama Gemini'den yine JSON istemeliyiz. UI, PDF ve DB düzenli çalışsın diye tabloyu JSON alanlarına çevirmek daha doğru.

### 4. AI Response Schema'yı Genişlet

Mevcut şema çalışır ama yeni promptu tam taşımaz. Tavsiye edilen yeni hazard alanları:

- `title`
- `category`
- `hazard`
- `observed_evidence`
- `possible_consequence`
- `risk_degree`
- `immediate_action`
- `legislation_reference`
- `legislation_confidence`
- `needs_verification`
- `root_cause`
- `accident_scenario`
- `recommended_action`
- `references`
- `confidence`
- Fine-Kinney ham değerleri
- 5x5 ham değerleri

Analiz seviyesi alanlar:

- `ai_summary`
- `priority_actions`: string array, max 3
- `limitations`
- `selected_focus`

Geriye uyumluluk:

- UI hemen kırılmasın diye `recommended_action` ve `references` bir süre korunmalı.
- Yeni alanlar DB'ye yazılırken eski alanlara da özetlenebilir.

### 5. Database Planı

#### Minimal yol

DB migration yapmadan:

- `possible_consequence` ve `immediate_action` gibi alanlar `description` ve `recommended_action` içine birleştirilir.
- `legislation_reference` mevcut `references_text` içine yazılır.
- `priority_actions` sadece `raw_ai_response` içinde kalır.

Artısı:

- Hızlı.
- Daha az migration riski.

Eksisi:

- Sonuç ekranı, PDF ve Excel'de alanlar temiz ayrılamaz.
- Arama/filtre/rapor kalitesi sınırlı kalır.
- `raw_ai_response` retention sonrası detay kaybolabilir.

#### Önerilen yol

Yeni migration ekle:

- `analyses.prompt_version text`
- `analyses.priority_actions jsonb`
- `findings.observed_evidence text`
- `findings.possible_consequence text`
- `findings.immediate_action text`
- `findings.legislation_reference text`
- `findings.needs_verification boolean default false`
- `findings.root_cause text`
- `findings.accident_scenario text`

Opsiyonel:

- `ai_usage_logs.prompt_version text`
- `ai_usage_logs.selected_canvas text`

Backfill:

- Yeni alanlar eski bulgularda boş kalabilir.

RLS:

- Yeni kolonlar mevcut tablo RLS'ini bozmaz.
- Ayrı tablo açılmayacağı için policy karmaşası artmaz.

### 6. iOS Data Model ve UI Etkisi

Dosyalar:

- `App/Services/AnalysisService.swift`
- `App/Views/Result/ResultView.swift`
- `App/Views/Result/RiskDetailView.swift`
- `App/Views/Report/ReportView.swift`
- `App/Models/HistoryItem.swift`
- `App/Models/RecentAnalysis.swift`

Yapılacak:

- `FindingRow` yeni DB alanlarını decode edecek.
- UI bulgu kartlarında şu yapı daha net gösterilecek:
  - Tehlike
  - Olası risk/sonuç
  - Acil önlem
  - Mevzuat karşılığı
  - Doğrulama/ölçüm notu
- Result ekranına "İlk 3 öncelikli aksiyon" bölümü eklenebilir.
- Risk detail ekranı mevzuat ve aksiyonları ayrı bloklar halinde göstermeli.
- Analizler listesi tek canvas başlığını göstermeye devam eder.

### 7. Rapor / Excel Etkisi

Dosyalar:

- `App/Services/PDFReportService.swift`
- `App/Views/Report/ReportView.swift`
- `supabase/functions/generate-excel-report/index.ts`

Yapılacak:

- PDF Standart Rapor:
  - İlk 3 öncelikli aksiyon bölümü.
  - Bulgularda acil önlem ayrı satır.
  - Mevzuat karşılığı ayrı satır.
- Pro Risk Analizi:
  - Mevcut Fine-Kinney / 5x5 tabloları korunur.
  - Yeni alanlar kontrol önlemleri ve mevzuat kolonlarına beslenir.
- Excel:
  - Yeni kolonlar eklenir:
    - Olası risk/sonuç
    - Acil önlem
    - Mevzuat karşılığı
    - Ölçümle doğrulanmalı mı?

### 8. QA Planı

Test senaryoları:

- Tek canvas: Genel
- Tek canvas: KKD
- Tek canvas: Ortam Ölçümü, ölçüm gerektiren belirsiz konular doğru "ölçümle doğrulanmalı" mı?
- Tek canvas: Mevzuat, madde numarası uydurmuyor mu?
- Canvas seçim UI: ikinci canvas seçildiğinde önceki seçim kalkıyor mu?
- Backend validation: birden fazla canvas payload'ı gelirse güvenli şekilde reddediliyor veya tek geçerli canvasa normalize ediliyor mu?
- Pro canvas: Genel Premium, root cause ve kaza senaryosu geliyor mu?
- Free kullanıcı Pro canvas seçemiyor mu?
- Free kullanıcı max 4 bulgu alıyor mu?
- Pro kullanıcı max 10 bulgu alıyor mu?
- Fine-Kinney ve 5x5 ham girdileri her bulguda geliyor mu?
- PDF ve Excel yeni alanları taşıyor mu?
- Eski analiz kayıtları Result/Reports ekranında kırılmadan açılıyor mu?

Backend teknik testleri:

- Edge Function invalid JSON simulation.
- Gemini 429/503 fallback.
- Unknown canvas id validation.
- Duplicate canvas id normalization.
- Prompt version raw audit içinde görünüyor mu?
- DB insert yeni nullable alanlarla başarılı mı?

## Uygulama Sırası

### Faz 1 - Prompt Registry ve Backend Prompt

1. `prompts.ts` oluştur.
2. DOCX'teki ortak prompt, canvas promptları ve mevzuat havuzunu taşı.
3. `buildSystemPrompt` fonksiyonunu yeni registry ile değiştir.
4. `PROMPT_VERSION` değerini audit içine yaz.
5. Unknown canvas ve birden fazla canvas payload kontrolünü sertleştir.
6. Backend local/type check ve Supabase function testlerini çalıştır.

Bu faz DB migration olmadan yapılabilir. Ancak yeni alanlar şemaya eklenmeden AI çıktısının tamamı sadece raw response içinde kalır.

### Faz 2 - Response Schema ve Mapping

1. `RESPONSE_SCHEMA` yeni alanları destekleyecek şekilde genişlet.
2. AI çıktısını mevcut `findings` alanlarına geriye uyumlu map et.
3. `priority_actions` değerini `raw_ai_response` içine yaz.
4. Result ekranının eski kayıtlarla kırılmadığını doğrula.

Bu fazdan sonra hızlı canlı test yapılabilir.

### Faz 3 - Database Migration

1. `analyses.prompt_version`, `analyses.priority_actions` ekle.
2. `findings` için yeni yapılandırılmış alanları ekle.
3. `ai_usage_logs` için prompt/canvas audit kolonlarını değerlendir.
4. Backfill migration yaz.
5. Supabase linked project'e migration uygula.

Bu faz üretim verisini etkilediği için ayrı commit ve ayrı QA gerektirir.

### Faz 4 - iOS UI ve Model Güncellemesi

1. `AnalysisCanvas.swift` başlıklarını koru; body metinleri UI'da gösterilmeyecek şekilde CanvasSheet'i düzenle.
2. `FindingRow` yeni alanları decode edecek.
3. Result ve RiskDetail ekranlarını yeni bulgu yapısına göre düzenle.
4. Canvas seçim sheet'inde tek seçim davranışını uygula.
5. Eski kayıtlar için fallback metinleri ekle.

### Faz 5 - PDF / Excel Raporlar

1. Standart PDF yeni alanları gösterecek.
2. Pro Fine-Kinney / 5x5 çıktılarında acil önlem ve mevzuat alanları net gösterilecek.
3. Excel export yeni kolonları taşıyacak.
4. Reports preview ve download akışı kontrol edilecek.

### Faz 6 - Manual QA ve Canlı Test

1. Eski analiz açma testi.
2. Yeni tek canvas analizi.
3. Canvas tek seçim davranışı.
4. Free/Pro davranışı.
5. PDF/Excel üretimi.
6. Dark mode hızlı pass.
7. Supabase logs ve `ai_usage_logs` kontrolü.

## Karar Gerektiren Noktalar

1. Yeni DB alanlarını hemen ekleyelim mi, yoksa önce promptu backend'de değiştirip raw response ile hızlı test mi yapalım?
2. iOS canvas kartlarında sadece başlık gösterilecek; alt metin/body kaldırılacak.
3. "Mevzuat" canvası Free mi Pro mu kalacak? Şu an Pro.
4. "Genel Premium" Pro olarak kalıyor; Free Genel ile farkı UI metninde daha açık anlatılmalı mı?
5. Raporlarda mevzuat karşılığı sadece başlık olarak mı gösterilecek, yoksa ileride madde doğrulama modülü planlanacak mı?

## Benim Önerim

Önerilen yol: Faz 1 + Faz 2'yi önce yapalım, ardından tek canlı analizle prompt kalitesini görelim. Eğer çıktı istediğimiz gibi ayrışıyorsa Faz 3 DB migration'a geçelim.

Sebep:

- Prompt kalitesini migration riski almadan hızlı ölçeriz.
- AI'ın yeni şemayı ne kadar stabil doldurduğunu görürüz.
- DB alanlarını gerçek çıktı davranışına göre netleştiririz.
- Üretim verisine dokunmadan önce iyi bir örnek set elde ederiz.

Faz 3'e geçtiğimizde ise yapılandırılmış alanları eklemek uzun vadede daha doğru. Çünkü PDF, Excel, rapor arşivi, arama/filtreleme ve ileride denetim panelleri için bu alanlara ayrı ayrı ihtiyaç olacak.
