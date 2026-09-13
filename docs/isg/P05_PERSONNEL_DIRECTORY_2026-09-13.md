# P05 — personel rehberi, düzenleme ve arşivleme

Tarih: 13 Eylül 2026. Durum: **bu alt dilim doğrulandı; P05 bütünü açık**.

## Yapılanlar

- iOS ve Android: firmaya bağlı personel listesi, arama, 50 kayıtlık sayfalama, arşiv filtresi, detay, ekleme, düzenleme ve arşivleme onayı.
- Yeni personel için yalnız ad soyad; tarih, görev, kod veya işyeri sorulmaz. Departman isteğe bağlı: boş, mevcut seçim veya yeni ad. Yeni departman personelle tek işlemde oluşturulur.
- Tam gri sayfa zemini, beyaz yuvarlak kartlar, arka plan kutusu olmayan ikonlar, Plus Jakarta Sans. Arşivleme ortak `NovaPopupSurface` kullanır; iOS modalı başlık/alt menü dahil tüm pencereyi kapatır. iOS 16.0–16.3'te saydam modal API'si olmadığı için opak zemin fallback'i vardır; 16.4+ saydam/material karartma kullanır.
- UI işlem durumu: düzenleniyor → gönderiliyor → tamamlandı / reddedildi / sonuç belirsiz. Belirsiz sonuçta form kilitlenir ve aynı operation/mutation anahtarlarıyla yeniden kontrol edilir. Yanıtın işlem, hesap, firma, personel, sürüm ve arşiv durumu eşleşmelidir.
- SQL adayı: owner kontrollü okuma, literal alt metin araması (SQL wildcard genişlemesi yok), keyset sayfalama, sürümlü düzenleme/arşivleme. Audit, outbox ve receipt aynı transaction'dadır.
- `record_version`, `assignment_version`'dan ayrıdır. Ad değiştirme tarihli görevlendirmeyi yeniden yazmaz. Tarihli görevlendirmesi bulunan kişinin departman değişikliği ayrı görevlendirme akışını gerektirir.
- Arşivleme silme değildir; satır ve görevlendirme geçmişi korunur. Yeni yazma ve receipt replay öncesinde yetki tekrar kontrol edilir. Arşivlenmiş firmanın owner okuması açık; yazması kapalıdır.
- Tarihli görev aralığında snapshot departman adı gösterilir; gelecek görevlendirme bugünün etiketini erkenden değiştirmez. Aday rehberin gün hesabı şu an Europe/Istanbul'dur; tam işyeri timezone/context entegrasyonu açık kalır.

## Bağlantılar ve sınırlar

```text
Native ekran → NovaPersonnelClient (enjekte edilen sınır)
                    └─ UI testinde yalnız sentetik, uygulama içi QA deposu

Gerçek yerel GoTrue oturumu
  → imzası doğrulanmış yerel test token'ı
  → personnel_verified → require_active_session
  → gerçek session/user satırı kontrolü ve transaction kilitleri
  → owner + sentetik write-access kontrolü
  → read_personnel / create_employee / edit_employee
  → employee + department + audit + outbox + receipt
```

Bu iki yol **henüz üretim HTTP/SDK üzerinden birbirine bağlanmadı**. UI test deposu production köke bağlanmadı; personel backend şeması yalnız yeni, izole test veritabanında kuruluyor. `personnel_verified` production RPC değildir. Test harness'i token imzasını doğrulamadan SQL/JWT claim hazırlamaz; mobil istemcinin SQL GUC ayarlayabilmesi güven sınırı değildir.

Gerçek oturum testi; login/refresh/logout ve Auth session freshness'i doğrular. `personnel_write_access` bir sentetik izin anahtarıdır; gerçek Plus/Pro entitlement veya kapasite modeli değildir.

Belirsiz işlem anahtarı aynı ekran yaşam döngüsünde korunur. Uygulama kapanması, tab değişimi ve yeniden girişten sonra diskten güvenli kurtarma **henüz yoktur**; üretim açılışı öncesinde hesap kapsamlı kalıcı işlem günlüğü/reconciliation gereklidir. Dolayısıyla bu testler uçtan uca exactly-once üretim garantisi olarak sunulmaz.

## Doğrulama

| Yol | Sonuç | Kapsam |
|---|---|---|
| İzole PostgreSQL | 135/135 | Önceki118 + yeni17: 50/50/23 sayfalama, owner izolasyonu, edit/retry, 20 eşzamanlı sürüm yarışı, üç journal fault rollback, bağlantı öldürme, arşiv, snapshot, revoked write |
| Gerçek yerel Auth bileşimi | 148/148 | Önceki132 + yeni16: personel create/read/edit/archive, forged legacy-sub, izin kaldırma, metadata ile yetki verememe, logout sonrası read/write/replay reddi |
| Android design system | 358/358 | Yeni5 state +5 Compose/Robolectric UI testi dahil; emülatör testi olarak sayılmaz |
| Android core:data | 611/611 | Mevcut domain/contract regresyonu |
| Android debug APK | PASS | Derleme, mağaza gönderimi veya üretim E2E değil |
| Ana iOS uygulaması | PASS | Simulator Debug/no signing derlemesi |
| iOS shell UI | 16/16 | Gerçek Simulator; yeni2 personel senaryosu dahil |
| iOS son popup/operation-ID düzeltmesi | 2/2 | Personel senaryoları yeniden çalıştı; görsel ekler incelendi |
| Saf Swift editor kontrolü | PASS | 18 invariant grubu, ayrı XCTest sayısı değildir |
| Node foundation | 154/154 | Directory parser ve Auth probe başlangıç izolasyonu dahil |
| NOVA kaynak/design | 24/24 | Kaynak listesi, ikon, font ve production-harness ayrımı |
| Deno type check | PASS | Directory request adapter |

İlk iOS filtreli komut sıfır test çalıştırdı; PASS kabul edilmedi. Tam paket16 test çalıştırıldı. Filtreli yeniden koşuda metot kimlikleri `()` son ekiyle kullanılarak2 test gerçekten çalıştırıldı. Android gecikmeli eski-hesap testinin ilk iki koşusu, yeni yüklemenin tamamlanmasını beklemediği için başarısızdı; testte gerçek tamamlanma beklenerek kapsam izolasyonu tekrar doğrulandı.

DB run: `69c3d434-573d-4519-b7fd-f2b55a8a2f38`. Auth run: `9d38219e-9dea-4cf6-85bb-d8497cb580d2`. Her iki ortam cleanup PASS; canlı müşteri verisi, Supabase deployment, mağaza kimliği, bundle/package veya entitlement değişmedi.

## P05 kapanış kapısı — açık işler

| Kabul maddesi | Konum |
|---|---|
| Name-only personel + optional/inline department | Native ekran ve SQL/Auth adayı doğrulandı |
| Company/workplace owner ve backfill/catch-up | Önceki yerel candidate testleri var; gerçek migration/upgrade kanıtı açık |
| Personel liste/form/detail | İki native ekran var; gerçek production service adapter/HTTP bağlantısı açık |
| D05 production migration + güvenli rollback | Açık; test fixture'ı production migration yerine geçmez |
| İşyeri context version/timezone/jurisdiction/hazard geçmişi | Tam model/API/UI ve test matrisi açık |
| Departman hiyerarşisi, job-role CRUD, employer/contractor ilişkisi | Tam model/API/UI ve kabul matrisi açık |
| Tarihli atama ekranı + gerçek SDK bağlantısı | SQL mutation/native request sözleşmesi var; UI/service entegrasyonu açık |
| Gerçek paid yetkisi/P01 transaction/P03 kapasite bileşimi | Açık; sentetik izin anahtarı yeterli değildir |
| Kalıcı pending operation kurtarma | Açık; ekran belleği uygulama kapanmasına dayanmaz |
| REV01/21/23, DAT04/05, X07/12/13 tam uçtan uca kabul | Kısmi domain kanıtı var; P05 kapandı denemez |

Öncelikli devam: test adayını gerçek D05 migration/owner/Auth/billing sınırına taşımak, native servis bağını ve kalıcı pending kurtarmayı tamamlamak; ardından context/hiyerarşi/işveren ilişkisi/görevlendirme ekranlarını aynı kabul kapısından geçirmek. P06'ya geçiş tamamlandı olarak işaretlenmedi.
