# P05/P18 — Firma veri bağlantısının ilk kontrolü

13 Eylül 2026. P02 servis commit'i `6170015a` sonrasında firma liste servisleri ve NOVA sunum girdileri incelendi. Bu dilim yeni firma modülünü veya canlı NOVA root bağlantısını tamamlamaz.

## Mevcut veri eşlemesi

| Ekran alanı | Mevcut kaynak | Kural |
|---|---|---|
| Kart kimliği | `companies.id` | Swift UUID / Android String; ada göre birleştirme yok |
| Görünen ad | `companies.name` | Örnek ekranın şirket adı gerçek veri yerine kullanılmaz |
| Sahip | `companies.user_id` | V5 §8: tek uzman sahibi; OSGB'deki uzman atama/şirket paylaşım modeli taşınmaz |
| Alt açıklama | `address`, `hazard_class`, isteğe bağlı `department` | `department` sektör değildir; mevcut modelde sektör alanı yok |
| Logo/baş harf | `logo_path` veya isimden sunum baş harfi | Storage erişimi mevcut yetki yolundan; yeni public bucket yok |
| Aktif/arşiv | `is_archived` | Varsayılan liste yalnız aktif; rapor/geçmiş gerektiğinde arşiv dahil |
| Sıralama | `created_at DESC` | Android mevcut SDK `nullslast` ekliyor; test bunu da doğruluyor |

`NovaCompanyItem` yalnız id/name/detail içerir; yetki kaynağı değildir. Mevcut NOVA ekranındaki “atanmış firma” kopyası referans tasarımdan gelmektedir; gerçek owner tabanlı bağlantı yapılırken firma sahipliğini anlatan kopya kullanılmalı. Yeni bir OSGB yönetici/uzman atama tablosu bu görsel nedeniyle oluşturulmayacak. V5'teki personel/işyeri görevlendirme geçmişi ayrı kavramdır.

## Uygulanan iptal düzeltmesi

İki mevcut liste servisi de genel hata yakalama içinde iptali yükleme hatasına çeviriyordu. Android artık `CancellationException`'ı aynen yükseltiyor; başarıdan önce ve genel hata yolunda coroutine etkinliği kontrol ediliyor. iOS `CancellationError`'ı ayrı tutuyor; SDK/URLSession iptali farklı hata biçiminde sarsa da `Task.checkCancellation()` ile UI'a normal hata/başarı olarak dönmesi engelleniyor.

Bu değişiklik yalnız **liste isteği** içindir; kaydet/arşivle/logo mutation davranışları değiştirilmedi. Sorgu filtresi, sıralama, paid kontrolü, RLS ve veri modeli değişmedi.

## Doğrulama

- Android gerçek pinned SDK + MockWebServer: aktif/arşiv dahil GET ve geciken HTTP isteğini iptal etme. Loopback sentetik yanıtlar; gerçek şirket okunmadı.
- İptal testi servis dönüşünde başarı veya kullanıcıya gösterilecek `Failure` olmadığını ve `CancellationException` alındığını doğrular.
- İlk sorgu beklentisi SDK'nın `.nullslast` ekini içermediği için düştü; mevcut kontrat doğrulanıp beklenti düzeltildi. Üretim sıralaması değiştirilmedi.
- iOS ana proje simulator Debug/no-signing build PASS; `build_sim_2026-09-12T23-39-00-007Z_pid70458_eb16e22c.log`, 18,9 saniye. Bu incremental build'de yeni uyarı yok; önceki tam derleme paywall uyarılarının çözüldüğü iddia edilmiyor.
- Son Android toplamı ve dosya hash'leri: [kanıt](evidence/P05_COMPANY_READ_BOUNDARY_2026-09-13.json). iOS için gerçek CompanyService cancellation runtime testi henüz yok.

## Sonraki gerçek bağlantının koşulları

1. Sunucunun owner/RLS sonucunu mevcut SDK üzerinden al; UI sayısını veya `profiles.tier` değerini yetki kabul etme.
2. `NovaSessionHost`'un **güncel** epoch'unu her yayınlamada denetle. Listeye ayrıca request ID/query/archived kapsamı ve latest-request-wins gerekir; host tek başına aynı epoch içindeki yarışları çözmez.
3. Auth owner/oturum değiştiğinde feature job'u iptal et ve scoped değeri hemen gizle. Bu tur servis iptalini korur, fakat mevcut tüm ekranların hesap değişiminde iptal ettiğini kanıtlamaz.
4. Aynı hesaba geri dönüş A→B→A, geç başarı/hata, arama/refresh çakışması, arşiv filtresi değişimi ve yetki geri alınması için typed loader testleri ekle.
5. Native sunumda gri tuval/beyaz kart standardını ve account-scoped hatasız boşluk/yükleniyor/hata durumlarını koruyarak bağla. Hazır olmayan P05 personel/işyeri alanlarını örnek OSGB verileriyle doldurma.

Canlı şema/RLS, kayıtlar, uygulama kökü, mağaza kimlikleri veya yayın değişmedi. Bu kontrol P05 veya P18'in tamamlandığı anlamına gelmez.
