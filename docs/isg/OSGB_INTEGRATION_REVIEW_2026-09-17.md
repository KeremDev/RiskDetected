# OSGB entegrasyon incelemesi ve düzeltme raporu

> Bu önceki tur raporudur. D1–D7 sayfalama, belirsiz mutasyon tekrarı, yaşam döngüsü bağlantıları ve burada açık görünen D1/D2 tenant-native görev/dış firma/atama ile müfredat/sınav/plan/sertifika modülleri daha sonra tamamlandı. **18 Eylül 2026'da** eğitim, risk değerlendirmesi ve periyodik kontrolün bireysel Pilot Canlı Nova akışları da OSGB yönetici/uzman ekranlarına taşındı; staging `20260918020000` seviyesine getirildi ve fiziksel iPhone build 122 kabulü yapıldı. Güncel ürün eşitliği için [OSGB_PERSONAL_PILOT_PARITY_REVIEW_2026-09-18.md](OSGB_PERSONAL_PILOT_PARITY_REVIEW_2026-09-18.md), önceki genel inceleme için [OSGB_FINAL_REVIEW_2026-09-17.md](OSGB_FINAL_REVIEW_2026-09-17.md) kullanılmalıdır.

17 Eylül 2026 · `codex/isg-transition-foundation` · Referans HEAD: `6eebab8946c627f42d13415cff1b8dc5007cc1ce`

## Sonuç

**Canlı sisteme dokunmadan yapılabilen yerel OSGB entegrasyonunun ana operasyon yolu tamamlandı; mevcut paket henüz canlı yayına hazır değil.** Ana plan iki kaynak belgenin zorunlu kapsamını kapsıyor. 24 SQL adayı, iOS çalışma alanı/firma/ekip ve firma–uzman atama akışları, D1–D9'un birincil liste/detay/oluşturma yolları, güvenli dosya taşıma worker'ları ve sentetik kabul zinciri hazır. Üretim migration'ı, gerçek sağlayıcı ve mağaza bağlantıları, Android OSGB arayüzü, fiziksel cihaz/staging kabulü ile bazı ileri düzenleme/raporlama/devir alt akışları ayrı yayın kapıları olarak açık kalıyor.

Bu incelemede bireysel kullanıcı uyumluluğu, dosya mahremiyeti, atama yaşam döngüsü, geçmiş yazar bilgisi ve istemci oturum yönetimindeki somut hatalar düzeltildi. Yeni regresyon provası, migration **öncesinden kalan imzalı KKD ve personel verisini** kullanıyor. Önceki prova ağırlıklı olarak migration sonrasında oluşturulan yeni kayıtlarla çalıştığından bu hatayı yakalamamıştı.

Bu tamamlama turunda ayrıca:

- canlı pilot girişine kişisel kökü koruyan güvenli OSGB çalışma alanı kapısı bağlandı;
- çalışma alanı oluşturma, davet koduyla katılma ve çalışma alanı değiştirme akışları eklendi;
- firma listeleme, arama, oluşturma, düzenleme ve arşivleme gerçek workspace RPC'lerine bağlandı;
- ekip/davet listesi, uzman veya yönetici daveti, rol/pratik durumu değişikliği, askıya alma, yeniden açma, üyelik sonlandırma, daveti yenileme ve iptal etme akışları eklendi;
- firma yöneticisinin aktif uzmanı firmaya dönemli ataması, güncel/planlı/sona eren atamaları görmesi ve atamayı sürüm kontrollü sonlandırması eklendi;
- D1 personel için işyeri/departman/çalışan akışları; D2–D6 için workspace kapsamlı liste/detay/oluşturma; D7 için dosya yükleme/indirme/finalize; D8 için analiz liste/detay/firmaya işleme/export; D9 için dashboard, arama ve periyodik değişiklik akışı pilot köke bağlandı;
- bu ekranlar mevcut Nova kart, istatistik, popup, başarı bildirimi ve TR/EN yerelleştirme düzenine uyarlandı;
- önceki foundation paketindeki 4 ve Nova-design paketindeki 13 açık arıza gerçek kod ve yerelleştirme düzeltmeleriyle kapatıldı.

**Bu çalışma sırasında canlı/staging veritabanına migration uygulanmadı, özellik açılmadı, mağaza/AI/e-posta sağlayıcısı çağrılmadı, telefona dağıtım yapılmadı.** Önceki çalışma değişiklikleri korundu. Düzenlemeler yerel, henüz dağıtılmamış adaylar üzerindedir. Canlı kullanıcıların mevcut akışının değişmediği, bu çalışmanın dağıtım yapmaması bakımından kesindir; gelecekteki dağıtımın tüm gerçek kullanıcı verileriyle uyumluluğu henüz kanıtlanmış değildir.

## İncelenen kaynaklar ve yöntem

- Kullanıcının `ISGADA_OSGB_MULTI_TENANT_INTEGRATION_PLAN_2026-09-16.md` ve `deep-research-report-2.md` belgeleri; özellikle kullanıcı/rol ayrımı, tüm operasyonlar, mağaza, devir ve geriye uyumluluk gereksinimleri.
- [Tam entegrasyon planı](OSGB_FULL_INTEGRATION_PLAN.md), [R001–R100 izlenebilirlik matrisi](OSGB_REQUIREMENTS_TRACEABILITY.md), [scope matrisi](OSGB_SCOPE_MATRIX.md), [uygulama durumu](OSGB_IMPLEMENTATION_STATUS_2026-09-17.md) ve yayın güvenliği belgeleri.
- 24 adayın ilgili tablo, trigger, RPC, yetki, migration ve istemci sözleşmeleri; gerçek eski firma yazım trigger'ı ile karşılaştırma.
- iOS `IsgWorkspaceAPI/LiveAdapter/Store`, Android `IsgWorkspaceGateway`, mevcut servislerde çağrı noktası araması.
- Yeni dolu-veri upgrade provası, mevcut bütünleşik SQL senaryosu, firma köprüsü provası, Swift davranış testleri, Android birim testleri ve derlemeler; eski bireysel modül regresyonları.

Bu bir satırların tamamının biçimsel doğruluk kanıtı değildir. Disposable DB fixture'ı gerçek production şemasının bütün RLS, auth, indeks ve veri dağılımını içermiyor. Test aktörü sentetik; SQL senaryoları gerçek kullanıcı JWT'siyle fiziksel cihaz E2E yerine geçmez.

## Düzeltilen bulgular

| No | Öncelik | Hata ve etkisi | Düzeltme / kanıt |
|---|---|---|---|
| F01 | P1 | Global `ppe_signed_evidence_shape`, eski `signed_copy=true` kayıtlarında yeni dosya/asset ID'leri olmadığı için migration'ı durduruyordu. | Eski imzalı kanıt biçimi korundu; OSGB için kanıt zorunluluğu ayrı trigger ile sürüyor. Önceki sürümde dolu-veri testi CHECK hatası verdi; düzeltilmiş zincir geçiyor. |
| F02 | P1 | Yeni domain trigger'ları eski istemcilerin göndermediği workspace/yazar alanlarını veya NULL workspace eşitliğini zorunlu tutuyordu. Firma eşleştirmesinden sonraki personel güncellemesi de `IMMUTABLE_SCOPE` hatasına düşebiliyordu. | Yalnız legacy kişisel firmayı doğrulayan ortak uyumluluk kontrolü eklendi; OSGB satırı bu yoldan kaçamıyor. Personel, eğitim, risk, KKD/tatbikat, ekipman/kontrol, operasyon ve alt kayıt trigger'larına uygulandı. Mevcut legacy RLS/FK ve domain kuralları kaldırılmadı. |
| F03 | P1 | Üyeye özel dosyanın değişiklik olayı, workspace genelindeki akışta başka yöneticiye dosya varlığını/ID'sini gösterebiliyordu. | Dosya ve dosya bağlantısı olayları güncel dosya görünürlüğüyle filtreleniyor. Kaynağı çözümlenmeyen ham asset olayları paylaşılmıyor. Kişiye özel dosya olayı, alıcısı olmayan owner'da görünmüyor. |
| F04 | P1 | Arama/dashboard bağımsız domain kapatma anahtarlarını dolanabiliyordu. | Arama ve olay akışında kaynak domain kontrolü; dashboard'un gerekli domain'leri kapalıysa `FEATURE_UNAVAILABLE`. Kapalı veri ölçülmüş sıfır olarak sunulmuyor. Dashboard tarih sınırı workspace saat dilimini kullanıyor. |
| F05 | P1 | Firma arşivlemede gelecekte başlayacak atama için bitiş başlangıçtan önce yazılıyor; sonlu bitişi olan aktif atamalar kapanmıyordu. Askıdaki uzmanın atamasını kapatmak da aktif-uzman kontrolüne takılıyordu. | Başlamamış dönem boş aralıkla, aktör/gerekçeyle iptal ediliyor; açık uçlu ve sonlu aktif atamalar kapanıyor. Askıdaki üyenin mevcut süresi yalnız kısaltılabilir/kapatılabilir; yeni erişim açılamaz. Birleşik regresyon bunu doğruluyor. |
| F06 | P2 | Firma senkronizasyon trigger'ı değişikliği yapan admin'i workspace'i ilk oluşturan kişiyle değiştiriyordu. | OSGB RPC'sinin doğruladığı son değiştiren aktör korunuyor. Farklı admin'le güncelleme testi eklendi. |
| F07 | P1 | Kişisel firma silme, yeni mirror FK'sına takılıyordu. | Legacy silmede mirror arşivlenir, eski firma bağlantısı NULL yapılır; OSGB geçmişi cascade silinmez. OSGB firması fiziksel silinmek yerine arşivlenmek zorundadır. Eski firma/personel silme davranışı test edildi. |
| F08 | P2 | Yeni firma adı unique indeksi, eski uygulamada geçerli aynı adlı kişisel firmaları engelliyordu. | Arama indeksi tutuldu; kimlik firma UUID'sidir. Aynı adlı kişisel firma oluşturma testi geçiyor. |
| F09 | P1 | Sadece workspace eşleştiren backfill, eski ücretli-plan trigger'ına takılıyor ve eski `updated_at` bilgisini değiştiriyordu. | Yalnız workspace alanı değişen, sahibi doğrulanmış eşleştirme business-edit kontrolünden ayrıldı. Limit sıfırken backfill ve timestamp korunumu test edildi. Normal kullanıcı firma yazımındaki plan kontrolü devam ediyor. |
| F10 | P2 | Tamamlanmış firma backfill'i tekrar sayabiliyor; checkpoint devamı kontrol edilmiyordu. | Tamamlanan çalıştırma tekrarında sıfır iş; devam cursor'u checkpoint ile doğrulanıyor. Farklı fingerprint reddi korunuyor. |
| F11 | P1 | Yanıt sonrası yalnız workspace eşitliği, A→B→A geçişini veya aynı üyelikle oturum değişimini yakalamıyordu. Bazı list/context çağrıları gerçek Supabase kimliğini kontrol etmiyordu. | iOS auth kimliği + zorunlu nesil anahtarı + cancellation kontrolü; Android zorunlu scope token ve cancellation kontrolü. Live adapter gerçek auth ile eşleşmeyen kimliği döndürmez. Davranış testleri eski yanıtları reddediyor. |
| F12 | P2 | iOS store seçim doğrulanırken işlem başlatabiliyor, hata sonrasında eski selection kalabiliyor; sadece ilk 50 firma yükleniyordu. | İşlemler `ready` durumuna bağlı; başarısız seçim temizleniyor; firma sayfaları cursor ile yükleniyor. Mutasyon kimliğini çağıran akış sağlıyor; retry'da kendiliğinden yeni UUID üretilmiyor. |
| F13 | P2 | Export cevabında workspace/company eksikliği kabul ediliyor ve dönen işin istenen iş olduğu doğrulanmıyordu. | SQL read cevabına scope eklendi. Her iki istemci scope'u zorunlu tutuyor ve export job ID'sini karşılaştırıyor. Yanlış/eksik envelope ve yanlış iş testleri eklendi. |
| F14 | P2 | Android için belgelenmiş `context` metodu yoktu; iOS yönetici genel change-feed isteğini de engelliyordu. | Android context RPC/kimlik kontrolü eklendi. iOS firma gereksinimini server'daki role kontrolüne bırakıyor; uzman hâlâ firma seçmek zorunda. |
| F15 | P2 | Swift analiz DTO'su sunucunun risk skorlarını, fotoğraf kaynaklarını ve eğitim ayrıntılarını atıyordu. | Fine-Kinney/5×5 alanları, kaynak fotoğraf/anahtarlar, hedef kitle/süre/katalog/sürüm alanları korundu. 135 ve 12 skorlarının decode sonrası kaldığı test edildi. |
| F16 | P1 | Firma atama mutasyonu vardı ancak yönetici mevcut atamaları okuyup yönetemiyordu; bu nedenle uzmanların firma erişimi ürün içinden açılamıyordu. | Yöneticiye özel sayfalı atama liste RPC'si, iOS atama ekranı, Android gateway ve sürüm kontrollü bitirme eklendi. Current/ended listeleme, tenant sınırı, overlap ve tarihçe disposable PostgreSQL'de doğrulandı. |

İlk arama mahremiyeti şüphesinin bir bölümü mevcut tablo kısıtıyla zaten engelleniyordu: `member_private`/`workspace_management` dosyaları firma ID'si taşımıyor. Bu nedenle firma aramasında gerçekleşmiş sızıntı iddia etmiyorum. Aramaya ek görünürlük kontrolü eklendi; doğrulanan asıl açık değişiklik akışındaydı.

Kod odakları: `supabase/pilot-release/candidates/20260917*.sql`, `App/Services/ISG/IsgWorkspace*.swift`, `android/core/data/src/main/kotlin/com/riskdetectedan/core/data/isg/IsgWorkspaceGateway.kt`. Manifest hash'leri ve değişen istemcilerin fonksiyon/test haritası yenilendi.

## Kullanım türlerine göre değerlendirme

### Bireysel kullanıcı

Mevcut personal root ve endpoint'ler OSGB store'una yönlendirilmedi. Eski owner sütunları ve kişisel abonelik/kredi akışı korunuyor. Dolu-veri provasında eski imzalı KKD'nin upgrade'i, firma eşleştirmesinden sonra personel/KKD güncellemesi, eski alanlarla işyeri/ekipman/kontrol/yıllık plan/alt kayıt oluşturma, aynı adlı firma ve kişisel firma silme geçiyor. Mevcut pilot operasyon paketi de geçti.

Bu sonuç **bütün bireysel hesap silme ve dosya silme durumlarının kabulü değildir**. OSGB üyeliği, uzman profili, finansal kayıt ve geçmiş referansı bulunan kullanıcının ayrılma/hesap silme politikası ayrı tamamlanmalı. Bütün üretim verisi için backfill anomali raporu, eski istemciyle eşzamanlı yazım ve gerçek restore provası henüz yok.

### OSGB sahibi / yöneticisi

Yerel backend'de üyelik, davet, seat, firma, atama, sürüm, cüzdan ve operasyon adayları var. Admin aktör geçmişi ve firma arşivleme yaşam döngüsü düzeltildi. iOS pilot kökünde çalışma alanı, firma, ekip/davet ve firma–uzman atama yönetimi gerçek RPC'lerle kullanılabilir durumda. D1–D9'un ana operasyon ekranları workspace store üzerinden açılıyor; mevcut kişisel modüllerdeki bütün ileri edit/archive/rapor/alt-kayıt özellikleri henüz bire bir taşınmış değil. Ayrı Super Admin paneli kullanıcının sağlayacağı UI kit beklenerek bilinçli olarak ertelendi.

### OSGB uzmanı

Sentetik zincir atanmış firmada işlem, sorumluluk devri ve eski yetkinin reddini sınar. İstemci scope değişimi kontrolleri güçlendirildi. Workspace seçimi ve OSGB kökü gerçek pilot girişine bağlandı; uzman atanmış firmada D1–D9 ana kayıt yollarını kullanabiliyor. Kişisel iş listesi, bütçe/takvim, tüm ileri domain alt akışları ve fiziksel cihaz kabulü tamamlanmadığı için tam uzman ürün kabulü verilmiyor.

### Firmanın çalışan/personel kayıtları

`employees` çalışan kaydı, OSGB `membership` uzman üyeliğinden farklıdır. Bu ayrım korundu. D1 adayı işyeri/departman/personel temeli sağlıyor; görev-unvan, dış firma, personel atama geçmişi ve ilgili bütün mevcut ekranlar için tam workspace bağlantısı gösterilemiyor. Çalışanın bağımsız login/personel portalı bu planın teslimi olarak varsayılmadı.

## Plan–uygulama boşlukları

Aşağıdaki işler yalnız staging onayı bekleyen bitmiş özellikler değildir; önemli kısmı **eksik kod/arayüz entegrasyonudur**.

| Plan / gereksinim | Gerçek durum | Kalan geliştirme ve kabul |
|---|---|---|
| A / R001, R100 | Envanter/manifest var; durum metni fazla geniş yorumlanabiliyordu. | Gerçek deployed ledger ve DB katalog karşılaştırması; her R satırı için somut PR/test/UI kanıtı. |
| B–C / R003, R006–R014 | Workspace seçici, oluşturma/katılma, firma, ekip/davet ve uzman–firma atama yönetimi iOS pilot kökünde gerçek RPC'lere bağlı. Atama listesi/tarihçesi ve sonlandırma çalışıyor. | Uzman sınıfı/belge/beyan kaynağı, workspace iş profili ve gerçek e-posta davet worker'ı. |
| D1 / R022 | İşyeri/departman/çalışan liste ve birincil mutasyon ekranları workspace servisinde. | Görev-unvan, dış firma, çalışan atama geçmişi ve mevcut personal ileri alt akışlarının workspace eşdeğeri. |
| D2 / R023 | Eğitim liste/detay/oluşturma ve ölçüm yolu workspace store'a bağlı. | Mevcut müfredat, belge/sertifika, yıllık eğitim ve ileri edit/rapor akışlarının tenant içinde tam parity ve cihaz kabulü. |
| D3–D6 / R024–R030 | Risk/uygunsuzluk, plan/KKD, ekipman ve operasyon için workspace kapsamlı liste/detay/oluşturma ekranları ve ölçümler var. | Mevcut personal modüllerdeki ileri edit/archive/rapor/alt-kayıt parity'si ve cihaz E2E. |
| D7–D8 / R031–R033, G / R077–R083 | Workspace dosya liste/yükleme/indirme/finalize worker'ları; analiz liste/detay/firmaya işleme/export iş akışı iOS store'a bağlı. Asset transport provası var. | Gerçek object storage ortamı, export renderer ve gerçek AI provider işçisiyle sandbox E2E; üretim credential/limit kararları. |
| D9 / R034–R036 | Dashboard, firma araması ve 30 saniyelik sessiz change-feed yenilemesi iOS'ta bağlı; notification queue ve mahremiyet kontrolleri hazır. | Gerçek realtime/push teslimi ve deep link worker'ı, skor parity, hesap ayrılma/silme/retention. Ham asset olayları görünürlük çözülmeden paylaşılmıyor. |
| E / R037–R041 | iOS Store/API gerçek pilot kökünde kullanılıyor; owner/expert OSGB kökü, workspace/firma/ekip/atama ve D1–D9 ana operasyon route'ları var. Android Gateway D1–D8 ve atama sözleşmelerini taşıyor. | Android OSGB UI kökü, takvim/ayar/bütçe, ileri domain parity, cache ve fiziksel cihaz TR–EN/erişilebilirlik kabulü. |
| F / R042–R047 | Private admin komut/overview adayları var. | Admin frontend, kullanıcının sağlayacağı UI kit ile ayrı çalışılmak üzere bilinçli olarak ertelendi; bu turda değiştirilmedi. |
| G / R067–R075 | Cüzdan, rezervasyon, kullanım, kota ve storage hesapları yerel testlerde çalışıyor. | Gerçek AI çağrısı/timeout/reconcile worker'ı, maliyet ve görünür kullanım UI. Ledger testi gerçek sağlayıcının tekrar çağrılmadığını tek başına kanıtlamaz. |
| H–I / R051–R066, R076 | Provider-neutral inbox/purchase intent/verified-record state machine var. | Apple/Google/RevenueCat doğrulama ve finalization adapter'ları, gerçek ürün kataloğu, restore/paywall UI ve mağaza sandbox yaşam döngüsü. |
| J / R084–R093 | Atama devir transaction'ı, kaynaklı olay ve brief tablosu var. | Sihirbaz UI, zamanlanmış yürütücü, açık işlerin sorumluluk devri; tüm şirket geçmişi projector/rebuild. Mevcut deterministic brief yalnız devir olayını özetliyor; açık/gecikmiş/yaklaşan işlerin tam özeti değil. Kaynaklı, ücret onaylı AI Handover Brief akışı eksik. |
| K / R094–R098 | Yerel SQL/Swift/Kotlin kontrolleri ve build var. | Gerçek auth/RLS rolleri, production benzeri upgrade, cihaz E2E, büyük veri/EXPLAIN, yük, DB+object restore, account deletion ve sağlayıcı sandbox kabulü. |
| L / R099 | Yayın yapılmadı. | Yukarıdaki geliştirmeler ve kabul bitmeden dark deploy/cohort genişletilmemeli. |

Fiyat, gerçek ürün kimliği, Scale sınırı, grace/downgrade, storage limiti, retention ve SLO gibi açık kararlar gerçek bağımlılıklardır. Ancak OSGB ekranlarının veya servis bağlantılarının yapılmaması bu kararların tamamına bağlanamaz; karar bağımsız kod işleri de hâlâ vardır.

## Doğrulama sonuçları

| Kontrol | Bu incelemede sonuç | Sınır |
|---|---|---|
| OSGB Node test paketi | 103/103 | Kaynak guard'ları ile executable Swift/context testlerinin karışımı; 103 cihaz senaryosu değildir. |
| Dolu-veri review regresyon zinciri | 24 migration + mevcut bütünleşik senaryo + 10 yeni regresyon grubu geçti | PostgreSQL 17 disposable fixture, dış ağa kapalı; gerçek production upgrade değil. |
| Canonical company bağımsız SQL provası | Geçti | Sentetik personal/OSGB veri. |
| Swift API davranış testleri | Geçti | A→B→A, auth değişimi, yanlış export işi, skor korunumu dahil. |
| iOS Debug Simulator build | Geçti | Fiziksel cihaz veya pilot canlı build değildir. |
| Android core:data compile + unit test | Geçti; Gateway dosyasında 9 test | Tam Android UI E2E değildir. |
| Mevcut pilot operasyon modülleri | Geçti | Eski modüllerin kendi fixture/gerçek SQL zinciri; yeni 24 migration ile üretim şemasının birleşimi değildir. |
| Fonksiyon/test kaynak haritası | 16 kaynak, hash kontrolü geçti | Kapsam haritası tek başına davranış testi değildir. |
| Geniş foundation | 758/758 | Ekip editörü, bildirim davranışı, eksik localization anahtarı ve raw metinler gerçek kod düzeltmeleriyle kapatıldı. |
| Nova-design | 194/194 | Önceki 13 tasarım/sözleşme arızası gerçek UI ve sözleşme düzeltmeleriyle kapatıldı. |

Foundation ve tasarım paketleri tamamen yeşildir. Bu sonuç OSGB'nin canlı yayın kabulü değildir; gerçek migration, sağlayıcı, ileri domain parity'si ve cihaz kabulü ayrı kapılardır.

Tekrar çalıştırılabilir ana komutlar:

```sh
node scripts/isg/run_osgb_review_regressions.mjs
node scripts/isg/run_osgb_company_canonical_bridge.mjs
node --test scripts/isg/osgb_*.test.mjs
node scripts/isg/verify_function_map.mjs
node scripts/modules/run_pilot.mjs --completed-records
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_suite.mjs nova-design
```

Yeni test kaynakları: `scripts/isg/osgb_review_preupgrade.sql`, `osgb_review_regression_check.sql`, `run_osgb_review_regressions.mjs`, `WorkspaceAPICheck.swift` ve Android `IsgWorkspaceGatewayTest.kt`. [Kalıcı kanıt özeti](review-2026-09-17/verification.json) ve [SQL regresyon çıktısı](review-2026-09-17/regressions.txt) bu raporla birlikte saklanır.

## Tamamlama sırası

1. D1–D9 ana route'larında bağlanan workspace akışlarını fiziksel cihazda doğrulamak; görev/unvan/dış firma/personel atama geçmişi ve ileri edit/archive/rapor alt akışlarında kişisel modül parity'sini tamamlamak.
2. Davet e-postası, object storage, AI, export ve bildirim worker adapter'larını gerçek altyapıya bağlamak; kontrollü sandbox E2E yapmak.
3. Kullanıcının sağlayacağı UI kit sonrasında gerçek admin deposunda OSGB sekmeleri/komutlarını bağlamak.
4. Mağaza kararlarını kapatıp Apple/Google/RevenueCat purchase/restore/refund/finalization sandbox kabulünü tamamlamak.
5. Devir sihirbazı, açık işlerin devri, kapsamlı ücretsiz özet ve kaynaklı AI brief'i tamamlamak.
6. Hesap silme/retention, production benzeri schema upgrade, eski sürüm sentinel, restore/yük ve fiziksel cihaz testlerini tamamlamak; bundan sonra somut yayın paketi değerlendirmek.

**Kabul kararı:** Kişisel kök korunarak iOS çalışma alanı, firma, ekip/davet, uzman atama ve D1–D9 ana operasyon yolları workspace servislerine bağlandı; bütün yerel foundation, tasarım ve OSGB testleri yeşil. Üretim migration'ı, gerçek sağlayıcılar, Android OSGB UI, ileri domain parity'si ve fiziksel cihaz/staging kabulü tamamlanmadan bütün ürünün yayına hazır olduğu onayı verilmedi.
