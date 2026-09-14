# NOVA canlı pilot — Periyodik Kontroller

14 Eylül 2026. Mevcut firma/personel pilotunun üzerine ekipman envanteri ve periyodik kontrol kaydı eklendi. Modül canlıda **açıldı**; kimlerin ulaştığını P05 pilot allowlist'i belirliyor.

## Kullanılabilir akış

- Sol menü → Periyodik Kontroller; ana sayfadaki **Kontrol** kartı; firma detayındaki başlık.
- Ekipman kaydı: işyeri, tür (20 öneri), seri/etiket, edinme tarihi, konum notu.
- Tür seçildiğinde **varsayılan periyot firma kuralı olarak yazılıyor** — `regulation_default`, gerekçe notuyla, onay bayrağı açık ve düzenlenebilir.
- Kontrol kaydı: tarih, sonuç (uygun / şartlı / uygunsuz), kontrolü yapan, rapor no, not. **Sonraki tarih rapor tarihinden otomatik doluyor**, uzman değiştirebiliyor.
- Kaydedilmiş rapora dokunmak düzeltme popup'ını açıyor. **Kontrol tarihi ve sonucu değiştirilemiyor** — sunucunun allowlist'inde de yoklar.
- Opsiyonel **İSG-KATİP ataması yapıldı** işareti ve notu. Bilgi amaçlıdır; hiçbir duruma, sayaca veya filtreye dokunmaz.
- Altı durum okuma anında hesaplanıyor (`state_authority: computed_at_read`), beş sayaç, arama ve firma/tür/işyeri filtreleri.

## Canlı bağlantı ve kapsam

Proje `ppcrzemgiztzcgddbins`. Yalnızca ekipman tabloları ve RPC'leri eklendi; ana migration klasörü topluca push edilmedi.

- Canlı ledger: `20260914192452_isg_pilot_equipment_checks`. Önceki canlı head: `20260914170954`.
- Birebir audit mirror: `supabase/pilot-release/supabase/migrations/20260914192452_isg_pilot_equipment_checks.sql`, SHA256 `db29a4505ed9a6b71a905f0c6b79a768a769d6a2861f7e369b0a3981ca300bc8`.
- `require_company` tanım MD5 değeri önce/sonra aynı: `f9de5f413afb0d33e022b04b9923c3f5`. Hiçbir mevcut fonksiyon değiştirilmedi.
- Public RPC: `isg_equipment_checks_read_v1(p_company,p_kind,p_query,p_state,p_workplace,p_type,p_id,p_limit,p_offset)`, `isg_equipment_checks_mutate_v1(p_company,p_action,p_operation,p_mutation,p_payload)`. İkisi de **SECURITY INVOKER**.
- Açılan anahtarlar: `rollout.modules` ve `module_registry.equipment` (ikisi de read+write). Diğer dört modül satırı **kapalı** kaldı; kapalı bir modül `MODULE_UNAVAILABLE` döner.
- Altı yeni private tablo RLS açık, **sıfır** tablo grant'i (anon/authenticated/service_role). Erişim yalnız iki wrapper üzerinden.

### Geliştirme zincirinden bilinçli sapmalar

Bundle, geliştirme dosyalarının canlı şemanın karşılayabildiği kadarına kırpılmış hâlidir. Üç sapma var, üçü de **daraltma yönünde**:

1. Yalnız `equipment` modülü kuruldu. Acil durum planı, tatbikat, KKD ve atama tabloları bu bundle'da yok; registry satırları var ve kapalı.
2. `private_isg.file_assets` canlıda yok, bu yüzden `equipment_inspections` tablosunda **`evidence_asset_id` kolonu yok**. Anahtar payload allowlist'inde kalıyor (istemci her zaman gönderiyor) ama **null olmayan değer reddediliyor** — karşılığı olmayan bir referans saklanmıyor. Arşiv dilimi bu pilotta değil; ekrandaki "arşiv raporu seç" listesi boş gelir.
3. `require_equipment_company`, geliştirme fonksiyonunun üzerine `p05_pilot_can_read` ve `p05_pilot_account_enabled` kapılarını ekliyor.

Audit mirror otomatik deployment projesi değildir. Geliştirme candidate'ını canlıda ikinci kez uygulama; gelecekteki migration zincirini bu ledger ile uzlaştır.

## Doğrulama

- Disposable yerel PostgreSQL 17: `scripts/isg/pilot_equipment_fixture.sql` + mirror dosyası (tek transaction) + `scripts/isg/pilot_equipment_check.sql`. **41 kontrol PASS.**
  - Anahtarların gerçekten açıldığı ve yalnız `equipment` satırının açık olduğu.
  - Pilot listesinde olmayan hesabın hem firma hem hesap genelinde `FEATURE_UNAVAILABLE` alması; pilot hesabın başka sahibin firmasına ulaşamaması.
  - Varsayılan periyodun `12, regulation_default, needs_review=true` olarak ve gerekçe notuyla yazılması.
  - Tarih verilmeyince `performed_on + 12 ay` ve `due_source='period'`; uzman tarihi verilince `due_source='expert'`.
  - Ürün varsayılanı olmayan tür: **hiç kural yazılmıyor, tarih üretilmiyor**, satır `period_unknown` okuyor.
  - `evidence_asset_id` kolonunun var olmadığı; null olmayan referansın `VALIDATION_ERROR` ile reddedildiği; null anahtarın kaydı engellemediği.
  - KATİP işaretinin saklandığı, `katip_official_verification` alanının hep false döndüğü ve işareti kaldırmanın **panonun okuduğu hiçbir alanı değiştirmediği** (JSON karşılaştırması) ile notu temizlediği.
  - `performed_on` ve `result` düzeltmesinin `PAYLOAD_NOT_ALLOWED` alması; düzeltmenin uygulanması; sürenin ürettiği tarihe geri çekmenin `due_source='period'` yapması.
  - Aynı mutation id'nin replay etmesi, ikinci kez yazmaması, farklı gövdeyle `IDEMPOTENCY_CONFLICT` alması.
  - Modül kapatılınca `MODULE_UNAVAILABLE`, feature kapatılınca `FEATURE_UNAVAILABLE` (feature önce).
  - Katalog dalı: 20 tür, her biri varsayılan periyoduyla, işyeri listesi, `health_records_tracked=false`.
  - `private_isg` altında istemci rolüne **sıfır** tablo grant'i; tam **iki** public wrapper çağrılabilir.
- Canlı DB'de `authenticated` rolü + gerçek pilot oturumunun claim'leri ile okuma probu: katalog 20 tür, `period_default_needs_review=true`, 1 işyeri, hesap panosu 0 kayıt, `notice_days=30`. **Yazma probu canlıda koşulmadı** (kalıcı kayıt bırakmamak için); kalıcı ekipman sayısı 0.
- Pilot listesinde olmayan gerçek bir hesabın claim'leriyle aynı okuma canlıda `FEATURE_UNAVAILABLE` ile reddedildi.
- Güvenlik advisor'ı bundle sonrası okundu: **yeni uyarı yok**. Mevcut 8 SECURITY DEFINER uyarısının hiçbiri bu dilime ait değil (iki public wrapper INVOKER). Yeni tabloların policy'siz RLS kullanması, doğrudan erişimin kapalı olması nedeniyle diğer `private_isg` tablolarıyla aynı kasıtlı duruştur. [RPC uyarısı](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [parola koruması](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Açık sınırlar

- **Gerçek cihaz kabulü bekliyor.** Bu dilimde iOS build'i alınıp telefona kurulmadı; canlı doğrulama SQL rol probudur, gerçek HTTP/JWT akışı değildir.
- Arşiv (Diğer Dosyalar) pilotta değil; kontrol kaydına dosya eklenemez.
- Yaklaşan/geçmiş kontrol için **bildirim üretilmiyor**.
- Onaylanmış tür bazlı süre kataloğu yok; varsayılan tek bir genel 12 ay.
- Modül firma kayıt tamamlama skoruna katılmıyor.
- Android'de karşılığı yok.
- Pilot hesabın süresi **20 Eylül 2026**'da doluyor; dolduğunda modül de kapanır.

Kapatma gerekiyorsa `UPDATE private_isg.module_registry SET read_enabled=false,write_enabled=false WHERE module='equipment';` yeter — yalnız bu modülü kapatır, pilotun geri kalanına dokunmaz. Ekipman verisini silen otomatik rollback yoktur.
