# Evrak Takibi — P11 ilk istemci dilimi

14 Eylül 2026. Yeni migration `20260914210000_isg_document_tracking.sql`.
Rollout **açılmadı**: `document_tracking` satırı kapalı eklendi.

Sol menüdeki **Evrak Takibi** girişi artık gerçek bir sayfaya iniyor.

## 1. Ne takip ediyor

Firma bazında **evrak yükümlülüğü** kaydı: hangi evrak takip ediliyor, kimin
kararıyla, ne kadar geçerli, kim sorumlu; ve o evrakın **dosyadaki kopyaları**
(düzenlenme tarihi, geçerlilik bitişi, belge no, aslının nerede olduğu).

Durum — **Eksik · Yaklaşıyor · Süresi doldu · Güncel** — hiçbir yerde
saklanmıyor; sunucu okuma anında tarihlerden hesaplıyor. Bu sayede hiçbir satır
dünkü cevabı taşıyamaz.

## 2. Yapısal olarak imkânsız kılınan üç şey

1. **Sağlık evrakı burada tutulamaz.** Tür kataloğu şemadaki bir CHECK; sonradan
   yapılacak bir INSERT yeni bir tür ekleyemez. Probe hem kataloğu tarıyor hem de
   `health_report` eklemeyi gerçekten deniyor ve reddedildiğini doğruluyor.
2. **Durum sütunu yok.** `document_obligations` ve `document_obligation_records`
   tablolarında `status`/`state`/`is_valid`/`is_expired` diye bir kolon yok.
   Cevap `document_obligation_status(...)` ile okuma anında üretiliyor ve
   `status_authority: computed_at_read` olarak işaretleniyor.
3. **Dosya saklanmıyor.** Tabloda `asset_id`, `storage_path`, `file_sha256`
   kolonu hiç yok — P04 temiz tarama verdiktisi olmadan yükleme kalıcı
   yapmıyor ve tarayıcı çalışmıyor. Tutulan şey, aslının nerede olduğuna dair
   uzmanın kendi kaydı. Hem liste (`file_storage_available: false`) hem her
   satır (`file_stored: false`) bunu açıkça söylüyor, ekran da yazıyor.

## 3. Uygulama kendi başına yasal yükümlülük iddia etmiyor

Bir kayıt varsayılan olarak **uzman kararı** (`basis='expert'`). `legal` demek
için uzmanın dayandığı mevzuat metni zorunlu:

~~~sql
CHECK(basis<>'legal' OR (legal_ref IS NOT NULL AND btrim(legal_ref)<>''))
~~~

Form da aynı şeyi yapıyor: dayanak yazılmadan `legal` seçili kayıt kaydedilemez.
Detay ekranı bu satırı **"Uzmanın dayandığı mevzuat"** başlığıyla gösteriyor,
yani ürünün tespiti gibi sunmuyor.

## 4. Liste bir sayımdır, karar değildir

Okuma `counts` döndürüyor (her durumdan kaç kayıt) ve `compliance_verdict: NULL`.
Uygunluk oranı/skoru hesaplayan hiçbir alan yok; firma skoruna bağlanmadı.
Ekranın üstünde tek cümleyle yazıyor:

> Bu liste takip ettiğiniz evrakların sayımıdır; firmanın veya bir kişinin
> uygunluğuna dair karar değildir. Sağlık evrakı bu listede tutulmaz ve
> dosyanın kendisi burada saklanmaz.

## 5. Sunucu sınırı

P05 deseninin aynısı: `public.isg_document_tracking_read_v1` ve
`..._mutate_v1` INVOKER sarmalayıcıları → `private_isg.read_document_tracking`
ve `private_isg.mutate_document_tracking` SECURITY DEFINER kontrollü girişleri.
Yalnız bu dördüne GRANT var; tabloların hiçbirine yok.

- Her yazma `PRIMARY KEY(actor_id,mutation_id)` makbuzuyla idempotent;
  kopya ayrıca `UNIQUE(obligation_id,mutation_id)` ile anahtarlı.
- Her aksiyonun payload'ı allowlist'li: `status`, `asset_id` gibi bir anahtar yok.
- `update`/`archive` `expected_version` istiyor; eski sürüm `VERSION_CONFLICT`.
- Arşivlenmiş kayda kopya eklenmez: `OBLIGATION_ARCHIVED`.
- Yazma için Plus/Pro aboneliği ve firma sahipliği ayrıca kontrol ediliyor.
- Anahtar kapalıyken iki yön de `FEATURE_UNAVAILABLE`.

Bitiş tarihi kuralı: açıkça girilen tarih kazanır; yoksa kaydın kendi süresi
eklenir; süresi olmayan kayıt süresiz kopya üretir. Kopya formu hangi kuralın
işleyeceğini o an yazıyor.

## 6. İstemci

| Dosya | Ne yapar |
|---|---|
| `NovaDocumentTracking.swift` | Saf model ve kelimeler; SDK yok |
| `NovaDocumentTrackingScreens.swift` | Liste: istatistik kartı, arama, işyeri filtresi, durum çipleri, kompakt kartlar |
| `NovaDocumentTrackingSheets.swift` | Detay popup'ı, ekle/düzenle formu, kopya formu |
| `NovaDocumentTrackingService.swift` | İki RPC uç noktası, her çağrının iki yanında scope kontrolü |
| `NovaDocumentTrackingLiveAdapter.swift` | Sunucu hata kodlarını ekranın söyleyebileceği cevaplara çevirir |
| `NovaPilotDocumentGate.swift` | Firma seçimi ve `waitForScope` ile gerçek yetki kontrolünü bekleme |

İstemci durumu **okur**, hesaplamaz. Tanımadığı bir kelime en sakin cevaba
düşürülmüyor; `missing` olarak gösteriliyor ki uzman satıra baksın.

## 7. Koşan kontroller

- `document_tracking_guard.test.mjs` — 12 offline guard
- `nova_document_tracking.test.mjs` — 9 istemci guard'ı (payload allowlist'i
  migration'ın kendi listesiyle karşılaştırılıyor)
- `document_tracking_probe.mjs` — **31 kontrol**, tek tek elde hesaplanmış
  tarihlerle; sentetik Docker koşusunda hepsi PASS
- Şema sayıları: p05 tam tekrar 163 tablo, entegre prova 160
- Rehearsal artık 17 kapılı özelliği kapatıp her birine aynı soruyu soruyor;
  iki kontrollü giriş definer listesine eklendi
- Advisor deny listesine dört yeni tablo, FK kapsayan dokuz indeks eklendi

## 8. Eşzamanlı çalışma

Bu dilim yazılırken aynı çalışma ağacında başka bir oturum eğitim modülünü
yazıyordu. Commit yalnız bu dilimin yollarını içerir; `NovaPilotMainGate.swift`,
`Localizable.xcstrings`, `GUNCEL_DURUM` ve devir notu ortak olduğu için bu
dosyalarda sadece bu dilimin satırları alındı ve eğitim çalışması ağaçta
bırakıldı. Bu tur foundation'da kalan tek hata (`NovaCompanyManagementGate.swift`
ham metinleri), sabit metin borcundaki artış ve ana ağacın derleme hatası
(`NovaTrainingSessionService.swift`) o çalışmaya aittir.

## 9. Açık kalan

- **Rollout kapalı.** `UPDATE private_isg.rollout SET read_enabled=true,
  write_enabled=true WHERE feature='document_tracking';` — ayrı bir insan kararı.
- Dosyanın kendisi hâlâ yüklenemiyor; P04 ikinci dilimi (tarayıcı, bucket
  politikası, imzalı URL) bunun kapısı.
- Sayfa tek firma okuyor. Otuz firmanın tek listede toplanması sunucu tarafında
  bir projeksiyon ister; N+1 okuma yapılmadı.
- Yaklaşan evrak için bildirim üretilmiyor; bildirim motoruna bağlanmadı.
- Android'de karşılığı yok.
- Evrak türü kataloğu sabit; uzmanın kendi türünü tanımlaması yok ("Diğer belge"
  ile ad verilebiliyor).
