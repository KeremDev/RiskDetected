# İSGADA UX genişletme — tasarım QA

Tarih: 21 Eylül 2026

## Karşılaştırılan ekranlar

Kaynak ekranlar:

- Kontrol listesi ayrıntısı: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-0d20a3f6-3e13-4e15-8d93-29cb6d797410.png`
- Kontrol listesi seçimi: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-ab448059-1b79-4d7d-b95d-afa90444b971.png`
- Saha ziyareti ekleme: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-8c4eff14-aa06-45b7-8ae3-e291ac4428d8.png`
- Eğitim listesi: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-dd3c0be2-6727-4a02-a42c-bfb3387db109.png`
- Atama ve temsilciler: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-67559673-9693-46a4-805c-7a1fb54c178e.png`

Simülatör çıktıları:

- Kontrol listesi filtreleri: `/Users/keremkayalar/.codex/visualizations/2026/09/21/01a0c3a6-6b69-7020-9efe-d00259cdb702/design-qa-captures/56590A22-A87C-466F-B560-83B0FBFBE278.png`
- Rapor Merkezi: `/Users/keremkayalar/.codex/visualizations/2026/09/21/01a0c3a6-6b69-7020-9efe-d00259cdb702/design-qa-captures/41EA9DCB-80AF-43BC-84AC-79CA28011CFB.png`
- Rapor oluşturma sihirbazı: `/Users/keremkayalar/.codex/visualizations/2026/09/21/01a0c3a6-6b69-7020-9efe-d00259cdb702/design-qa-captures/5CA8A78E-DD81-41FB-89AE-B434FCBCFF9C.png`
- Firma ekleme sihirbazı: `/Users/keremkayalar/.codex/visualizations/2026/09/21/01a0c3a6-6b69-7020-9efe-d00259cdb702/design-qa-captures/CADCC79A-67C4-4CAF-9197-AFB890B591BF.png`

## Sonuç

| Alan | Önce | Sonra | Durum |
|---|---|---|---|
| Kontrol listesi seçimi | Açıklamasız arama, filtre yok, yinelenen kayıtlar | Tek yardım açıklaması, sektör ve liste türü filtreleri, anlamlı arama metni, mantıksal tekilleştirme | Geçti |
| Kontrol listesi ayrıntısı | Kaynak ve sürüm kullanıcıya gösteriliyor | Kaynak/sürüm veri modelinde korunuyor, müşteri yüzünden kaldırıldı | Geçti |
| Saha ziyareti | Bütün alanlar tek uzun ekranda | İşyeri → tarih/saat/süre → ayrıntılar → isteğe bağlı dosya ve sonuç ekranı | Geçti |
| Rapor Merkezi | Arşive yönlenen menü | Altı kapsamlı rapor türü, dört adımlı oluşturma, PDF/Excel indirme, ayrı arşiv | Geçti |
| Eğitim listesi | Ekle eylemi içerik akışında | Ekle eylemi ekran başlığının sağında | Geçti |
| Acil durum planı | Ekip zorunlu | Ekip seçimi isteğe bağlı | Geçti |
| Yardım metinleri | Aynı ekranda birden fazla ampul | Ana bağlamda tek yardım; uzun gerekçeler `Neden?` altında | Geçti |
| Uzun kayıt akışları | Uzun popup / tek sayfa | Atama, kurul, yıllık plan, tatbikat, ziyaret ve firma akışlarında tam ekran ilerleme, hata ve başarı durumu | Geçti |

## Görsel gözlem

- Bilgi hiyerarşisi Nova tasarım diliyle uyumlu: başlık, ilerleme, tek bağlam yardımı, form kartı ve sabit alt eylem.
- Kontrol listesi sonuç yoğunluğu belirgin biçimde azaldı; üç örnek kayıt ekranda rahat taranıyor.
- Rapor türleri eşit hiyerarşide ve dokunma alanları yeterli. Oluşturma ekranı birincil eylemi sabit alt bölgede tutuyor.
- Firma formu ilk adımda yalnızca zorunlu bağlamı gösteriyor; ek bilgi, atama ve kontrol sonraki adımlara ayrıldı.
- Kaynak ekranlarda görülen tek sayfalık ziyaret ve çoklu yardım metni desenleri yeni akışlarda kullanılmıyor.

## Otomatik doğrulama

- iOS simülatör derlemesi: geçti.
- Nova çevrimdışı tasarım paketi: 215 / 215 geçti.
- Değişiklik kapsamı kabul/regresyon testleri: 83 / 83 geçti.
- Görsel UI testi: `NovaPilotUITests.testWizardExpansionVisualAudit` geçti; dört ekran görüntüsü üretildi.

