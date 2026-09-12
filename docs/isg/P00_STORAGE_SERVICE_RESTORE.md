# P00 — Storage servis geri yükleme provası

12 Eylül 2026, 18:20:51–18:21:28 UTC. Auth + Storage birlikte **42/42 üst seviye kontrol PASS**. Tüm **588 dosya / 512.280.146 byte**, izole Storage API'den yeniden indirilerek SHA-256, boyut, MIME türü ve cache-control bilgisiyle doğrulandı. Bu kanıt, bütün uygulamanın veya mağaza güncellemesinin uçtan uca hazır olduğu anlamına gelmez.

## Yöntem ve bağımlılık

[Auth restore koşucusu](P00_AUTH_SERVICE_RESTORE.md) yeni `--with-storage` seçeneğiyle çalışır. Önce aynı disposable DB restore, roller/474 ACL, Auth77–Storage68 migration eki ve sentetik Auth testleri tamamlanır. Ardından sabit **Storage v1.69.0** image digest'i ile dördüncü disposable konteyner açılır. DB `network none`, diğer üç servis yalnız bu yeni DB'nin ağ namespace'ini paylaşır; host mount/port/dış ağ yoktur. Mevcut restore DB, diğer local stack'ler ve production değiştirilmedi.

~~~text
Orijinal yedek + sabit SHA manifest
  → path/symlink/boyut/hash kontrolü
  → restored storage.objects: bucket + name + version + MIME + cache
  → sabit image FileBackend + TenantLocation ile versioned blob/xattr yazımı
  → localhost Storage API → tüm dosyaların tekrar hash'i
  → owner/foreign/anon + signed URL negatifleri
  → storage.objects bütün satır fingerprint'i aynı
  → yalnız bu run'ın dört konteyneri kaldırılır
~~~

Eski metadata'yı yeni upload API çağrısıyla değiştirmedik: imajın kendi dosya backend'i kullanılarak orijinal `version` altında byte ve içerik/cache xattr'ları oluşturuldu. `storage.objects` satırlarına yazılmadı. Orijinal backend ETag ve dosya mtime'ı korunmuş sayılmaz; yerel backend bunları yeniden üretir. Production S3 sürüm geçmişi, CDN cache ve eski signed URL taşınabilirliği bu testin kapsamı dışındadır.

## Kanıt kapsamı

| Alan | Test |
|---|---|
| Reports199, photos380, logos3, avatars1, legal5 | Tamamı API download → hash/boyut/MIME/cache eşleşti |
| Photos, reports, logos, avatars | Her bucket için bir gerçek restore edilmiş path/owner örneği |
| Owner read | Yerel test JWT'siyle başarılı; byte hash'i eşit |
| Başka kullanıcı / anonim read | İkisi de reddedildi |
| Signed URL üretimi | Owner başarılı; başka kullanıcı ve anonim reddedildi |
| Signed download | Ek bearer olmadan doğru içerik; değiştirilmiş imza reddedildi |
| İmza kapsamı | Aynı imza başka dosya path'inde ve imzasız istek reddedildi |
| Süre aşımı | Servisten gerçek 1 saniyelik URL alındı; 2,1 saniye sonra reddedildi |
| Public legal bucket | Beş mevcut dosya token olmadan doğru hash ile okundu |
| Metadata / ledger | storage.objects fingerprint değişmedi; Auth77 / Storage68 aynı |
| Kaynak / cleanup | Kaynak sayıları aynı; dört disposable konteyner kaldırıldı |

Owner için yalnız o izole serviste geçerli, rastgele yeni secret ile JWT üretildi; kimlik klasöründen alınan UUID'nin restored Auth'ta bulunduğu ayrıca doğrulandı. Foreign kullanıcısı Auth testinde yeni oluşturulan sentetik gerçek local hesaptır. Bu yöntem mevcut Storage RLS davranışını sınar; eski müşterinin parolasını veya canlı oturumunu kullanarak giriş yapma kanıtı değildir. Birer owner örneği bütün kullanıcı/ACL varyasyonlarını kapsamaz. Upload/upsert/delete RLS, S3/TUS, dönüşüm ve CDN test edilmedi.

Bir ilk geliştirme denemesinde join sorgusundaki belirsiz sütun (`42702`) yakalandı ve kolonlar açık `o.` alias'ıyla düzeltildi. İlk başarılı 34-kontrollü turun ardından expiry ve object-binding negatifleri eklendi; final 42 kontrol geçti. Başarısız/başarılı dar raporlar restricted `backups/` altında korunuyor.

[Makine okunur final kanıt](evidence/P00_STORAGE_SERVICE_RESTORE_2026-09-12.json) kaynak hash'leri, image digest'leri ve cleanup sonucunu içerir. Foundation **80/80**; yeni 17 offline test dosya path/boyut/header ve signed URL dış adres/bozuk imza parametresi girişlerini sınar. Gerçek müşteri yedeği CI'a konmadı.

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --isolated-copy --with-storage
~~~

## Açık kapılar

İki gerçek mobil istemciyle restore E2E, eski Auth oturumu/provider config, Edge/Realtime/dış servisler, farklı fiziksel diskte yedek ve ayrı anahtar kurtarma kopyası hâlâ açık. iOS/Android bundle/paket ID ve mağaza ayarları değiştirilmedi. Mevcut geri dönüş etiketi korunuyor; bu test prod cutover izni değildir.

Kaynaklar: [Storage v1.69.0 FileBackend](https://github.com/supabase/storage/blob/v1.69.0/src/storage/backend/file.ts), [nesne konumu](https://github.com/supabase/storage/blob/v1.69.0/src/storage/locator.ts), [signed URL üretimi](https://github.com/supabase/storage/blob/v1.69.0/src/http/routes/object/getSignedURL.ts), [signed download](https://github.com/supabase/storage/blob/v1.69.0/src/http/routes/object/getSignedObject.ts), [self-hosted S3/backend ayrımı](https://supabase.com/docs/guides/self-hosting/self-hosted-s3). Kurulu image'ın derlenmiş backend/locator modülleri de salt okunur incelendi; paket güncellenmedi.
