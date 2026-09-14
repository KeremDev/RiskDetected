# NOVA canlı pilot — Evrak Takibi

14 Eylül 2026. Firma/personel pilotunun üzerine evrak yükümlülük takibi eklendi. Modül canlıda **açıldı**; kimlerin ulaştığını P05 pilot allowlist'i belirliyor.

## Kullanılabilir akış

- Sol menü → Evrak Takibi. Sayfa **firma seçimiyle** açılıyor; firma seçilince o firmanın evrakları listeleniyor.
- Yükümlülük ekleme: tür (16 başlık), başlık, işyeri (boş bırakılırsa firma geneli), geçerlilik süresi (gün), uyarı penceresi (gün), sorumlu kişi, not.
- **Dayanak ayrımı:** varsayılan `expert` — uzmanın kendi kararı. `legal` seçilirse **dayanılan referans zorunlu**; şema bunu kontrol ediyor, fonksiyon atlayamıyor.
- Kopya kaydı: düzenlenme tarihi, geçerlilik bitişi, evrak no, **aslının nerede tutulduğu notu**.
- Dört durum okuma anında hesaplanıyor: **Eksik · Yaklaşıyor · Süresi doldu · Güncel**. Hiçbiri saklanmıyor.
- Hesap genelinde portföy okuması: tüm firmalar tek sorguda, firma ve durum sayaçları, en kötüden başlayan sıralama, 10'luk sayfalar.

## Üç yapısal garanti (geliştirme başlığından, aynen)

1. **Sağlık kaydı buraya giremez.** Tür kataloğu şemada sabit bir kümedir; yeni bir migration olmadan hiçbir insert sağlık türü ekleyemez.
2. **Durum saklanmıyor.** Eksik / yaklaşıyor / süresi doldu okuma anında tarihlerden hesaplanıyor, dolayısıyla hiçbir satır dünkü cevabı taşıyamaz.
3. **Dosya eklenmiyor.** Tabloların hiçbirinde asset kolonu yok. Saklanan şey, uzmanın aslının nerede olduğuna dair kendi referansı. Okuma her seferinde `file_storage_available: false` diyor.

Ayrıca hiçbir okuma uygunluk hükmü vermiyor: `compliance_verdict` her zaman null.

## Canlı bağlantı ve kapsam

Proje `ppcrzemgiztzcgddbins`. Yalnızca evrak takibi tabloları ve RPC'leri eklendi.

- Canlı ledger: `20260914193516_isg_pilot_document_tracking`. Önceki canlı head: `20260914192452` (ekipman bundle'ı).
- Birebir audit mirror: `supabase/pilot-release/supabase/migrations/20260914193516_isg_pilot_document_tracking.sql`, SHA256 `382dae88f036afc7c4137234a1c59099d128f2e74e987606362da71f3878e4dd`.
- `require_company` tanım MD5 önce/sonra aynı: `f9de5f413afb0d33e022b04b9923c3f5`. Hiçbir mevcut fonksiyon değiştirilmedi.
- Public RPC: `isg_document_tracking_read_v1`, `isg_document_tracking_mutate_v1`, `isg_document_portfolio_v1`. Üçü de **SECURITY INVOKER**.
- Açılan anahtar: `rollout.document_tracking` (read+write).
- Dört yeni private tablo RLS açık, **sıfır** tablo grant'i.

### Geliştirme zincirinden bilinçli sapmalar

Ekipman bundle'ının aksine burada **hiçbir şey kırpılmadı** — bu dilim zaten `file_assets`'e hiç dokunmuyordu. İki sapma var, ikisi de daraltma yönünde:

1. `require_document_tracking_company` P05 pilot kapılarını (`p05_pilot_can_read`, `p05_pilot_account_enabled`) taşıyor.
2. `read_document_portfolio` hesap düzeyi pilot kapısını kazandı; pilot kaydı olmayan hesap boş portföy değil, kapalı cevap alıyor.

## Doğrulama

- Disposable yerel PostgreSQL 17: `scripts/isg/pilot_document_tracking_fixture.sql` + mirror dosyası (tek transaction) + `scripts/isg/pilot_document_tracking_check.sql`. **42 kontrol PASS.**
  - Anahtarın açıldığı ve başka feature satırı eklenmediği.
  - Pilot dışı hesabın hem firma okumasında hem portföyde `FEATURE_UNAVAILABLE` alması; pilot hesabın başka sahibin firmasına ulaşamaması.
  - Tür kataloğunda sağlık kodu olmadığı, tablolarda dosya kolonu olmadığı, bilinmeyen türün FK ile reddedildiği.
  - `legal` dayanağın referanssız reddedildiği.
  - Kopyasız yükümlülüğün `missing` okuduğu.
  - Dört durumun **sınırlarda** doğru olduğu: +90 gün `valid`, +30 gün (pencerenin son günü) `due_soon`, +31 gün tekrar `valid`, -1 gün `expired`.
  - Bitiş tarihi verilmezse yükümlülüğün kendi süresinin doldurduğu; süresi olmayan yükümlülüğün **hiç bitmeyen** kopya ürettiği.
  - Eski sürümle güncellemenin `VERSION_CONFLICT` aldığı, güncel sürümün kabul edildiği.
  - Arşivlemenin satırı panodan aldığı ama **sildirmediği**, arşivlenene kopya işlenemediği.
  - Tek kopyanın silinmesiyle durumun tekrar `missing` olduğu.
  - Aynı mutation id'nin replay ettiği, ikinci kez yazmadığı, farklı gövdeyle `IDEMPOTENCY_CONFLICT` aldığı.
  - **Sayacın saydığı listeyle asla çelişemediği** (firma listesi ve portföy ayrı ayrı).
  - Portföy toplamının tablodaki canlı sayıyla, `missing` filtresinin firma listesiyle uyuştuğu.
  - Sayfa boyutunun sunucunun olduğu ve `has_more`'un doğru dediği.
  - Feature yalnız okumaya çekilince yazmanın reddedilip okumanın cevap vermeye devam ettiği; tamamen kapanınca ikisinin de reddedildiği.
  - Sıfır tablo grant'i; tam üç public wrapper çağrılabilir.
- Canlı DB'de `authenticated` rolü + gerçek pilot oturumunun claim'leri ile okuma probu: 16 tür, `health_records_tracked=false`, 1 işyeri, `file_storage_available=false`, portföy 0 kayıt, `compliance_verdict` null. **Yazma probu canlıda koşulmadı.**
- Pilot listesinde olmayan gerçek bir hesabın claim'leriyle portföy okuması canlıda `FEATURE_UNAVAILABLE` ile reddedildi.
- Güvenlik advisor'ı bundle sonrası okundu: **yeni uyarı yok** (mevcut 8 SECURITY DEFINER uyarısının hiçbiri bu dilime ait değil; üç wrapper INVOKER).

## Açık sınırlar

- **Gerçek cihaz kabulü bekliyor.** iOS build'i alınıp telefona kurulmadı; canlı doğrulama SQL rol probudur.
- Dosya eklenemiyor — tasarım kararı. Arşiv (Diğer Dosyalar) pilotta değil.
- Süresi dolan/yaklaşan evrak için **bildirim üretilmiyor**.
- Yükümlülük şablonu / firma tipine göre otomatik liste yok; her yükümlülüğü uzman kendisi ekliyor.
- Modül firma kayıt tamamlama skoruna katılmıyor.
- Android'de karşılığı yok.
- Pilot hesabın süresi **20 Eylül 2026**'da doluyor.

Kapatma: `UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='document_tracking';` — yalnız bu modülü kapatır. Evrak verisini silen otomatik rollback yoktur.
