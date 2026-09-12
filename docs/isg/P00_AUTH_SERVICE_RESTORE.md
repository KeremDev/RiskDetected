# P00 — Auth servis restore provası ve ek yedek

12 Eylül 2026. **17/17 kontrol PASS**, son tur 18:08:51–18:08:58 UTC. Bu, Auth servisinin restore edilmiş bir kopya üstünde sentetik hesapla çalıştığını gösterir; bütün ürünün felaket kurtarması tamamlanmış değildir.

## Bulunan yedek kapsamı eksikliği

İlk DB restore'unda kullanıcı, identity ve uygulama tabloları geri gelmişti; fakat `auth.schema_migrations` ve `storage.migrations` tabloları boştu. Bunlar uygulama satırları değil, servislerin hangi şema adımlarının zaten uygulandığını anlamasını sağlayan kayıtlardır. Boş bırakıp servisi açmak eski migration'ların yeniden çalışmasına yol açabilir.

Canlıdan yalnız bu iki tablonun verisi, `default_transaction_read_only=on`, TLS ve mevcut Keychain bağlantısıyla ek dump olarak alındı. Müşteri sorgusu veya canlı SQL yazımı yapılmadı:

- `backups/isg-managed-migrations-20260912-osigPE`: 17:56:14 UTC, Auth77 / Storage68 kayıt.
- SQL 8.690 byte; SHA-256 `e027928e0d920f3cd616991af4a48378adb63daf33e53790c04bb90d4f384fe5`.
- Kullanıcının seçtiği Masaüstü yedeğinin içinde `ek-servis-migration-20260912-lYqoZG` klasörüne şifreli ek kondu. Ana 3,6 GB arşiv değişmedi.
- Ek 20.516 byte AES-256-GCM, aynı Keychain anahtarı + yeni rastgele nonce; authenticated decrypt/hash PASS. Cipher SHA-256 `c0a25da7fc833a72d93666fefedfe16cf2374593a97f0cf5fea5dca124d79b4c`.
- Bu daha sonra alınmış bir ektir, ilk dump ile aynı anın snapshot'ı diye sunulmaz. Yerel servis provası uyumluluğunu doğruladı. Aynı disk/aynı Mac'te anahtar saklama riski değişmedi.

## Denenen ortam ve restore sırası

Ana doğrulanmış `isg_restore_20260912_db` yalnız okundu. Yeni disposable DB, GoTrue ve HTTP test istemcisi oluşturuldu. DB `network none`; iki yardımcı aynı DB'nin ağ namespace'ini paylaşıyor. Hiçbir host portu veya mount yok. Dolayısıyla API çağrıları yalnız o namespace'in `127.0.0.1:9999` adresine gidebilir. SMTP/OAuth/production JWT anahtarı aktarılmadı. Test JWT ve DB parolaları rastgele üretildi, komut argümanına/loga yazılmadı.

1. Kaynak konteynerin kimlik, label, image digest, port, mount ve gerçek bağlı network envanteri denetlenir.
2. Kaynağın custom-format logical dump'ı bellekte alınır; kaynak-only roller parola hash'i olmadan envanterlenir.
3. Yalnız yeni test DB'sinde imajın hazır boş managed şemaları ve `supabase_realtime` publication'ı kaldırılır. Kaynakta olup imajda olmayan `supabase_functions_admin` rolünün nitelikleri parola olmadan oluşturulur.
4. Pre-data → boş olduğu ayrıca doğrulanan `analysis_jobs` kuyruğunun PGMQ API ile kurulması → data → post-data → dump TOC'sindeki **474 ACL/default-ACL kaydının tamamının** yeniden uygulanması.
5. 208 Auth, 208 profil, 588 Storage object satırı; servis ledger'ları önce0/0, ekten sonra77/68 doğrulanır.
6. GoTrue **v2.195.0** sabit image digest ile açılır. Lokal admin üzerinden `example.invalid` sentetik hesap oluşturulur; gerçek geri yüklenmiş kullanıcılar adına giriş yapılmaz.
7. Test bitince yalnız run-ID ve digest'i doğrulanan üç geçici konteyner kaldırılır. Ana kaynak sayıları tekrar eşleşir; source restore olduğu gibi kalır.

İlk beş geliştirme denemesinde imaj şeması, publication, eksik global rol ve PGMQ extension-member ACL sırası sorunları bulundu. Her başarısız yeni kopya kaldırıldı; restricted diagnostic'ler `backups/isg-auth-service-restore-20260912-*` altında korundu. Son yaklaşım tüm ACL'leri ayrı son aşamada uyguluyor; `--no-privileges` ara aşamasını başarılı restore saymıyor. Kaynak kuyrukta mesaj varsa bu dar prova **reddeder**; kuyruk verisini sessizce atlayan genel bir restore aracı değildir.

## Doğrulamalar

| Kontrol | Sonuç |
|---|---|
| Kaynak kuyrukları boş; kullanıcı/profil/Storage sayıları aynı | PASS |
| Servis migration ledger'ları restore, boot sonrası77/68 | PASS |
| Auth health | v2.195.0 / PASS |
| Tokensiz ve süresi geçmiş service JWT ile admin endpoint | Reddedildi |
| Yeni sentetik kullanıcı → mevcut profil bootstrap trigger | Profil oluştu |
| Yanlış parola | Reddedildi |
| Doğru parola → `/user` → refresh | Aynı UUID |
| Normal user JWT → admin user list | Reddedildi |
| Logout → eski refresh token | Logout204; refresh400 |
| Kaynak DB before/after sayıları | Eşit |
| Disposable cleanup | PASS |

[Makine okunur kanıt ve kaynak hash'leri](evidence/P00_AUTH_SERVICE_RESTORE_2026-09-12.json). Foundation toplam **63/63**: yeni 18 test; yanlış CLI argümanı, eksik inspection alanı, mount, privilege, port ve sonradan eklenmiş dış ağ dahil negatifler. Bunlar 203 V5 domain kabulünün geçtiği anlamına gelmez.

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --isolated-copy
~~~

İkinci komut yalnız bu Mac'teki sabit, önceden doğrulanmış restore ve restricted ledger ekiyle çalışır; cloud/local reset komutu değildir. Önceden aynı hedef adı varsa reddeder. SIGINT/SIGTERM cleanup yapar; zorunlu SIGKILL veya Docker daemon kaybında otomatik cleanup garanti edilemez, kalan target'lar ayrıca incelenmelidir. Bu gerçek veri kopyası provası CI'a eklenmedi; CI yalnız offline guard testlerini çalıştırır.

## Hâlâ açık

Storage API/signed download sonradan [42 kontrollü birleşik provayla](P00_STORAGE_SERVICE_RESTORE.md) doğrulandı; yukarıdaki 17 kontrollü sonuç kendi tarihinin kanıtıdır. Eski kullanıcıyla OTP/OAuth/parola giriş kanıtı, eski refresh/access token ve provider-secret taşınabilirliği, e-posta teslimi, gerçek native SDK/auth callback, iki platformda yerinde update, Realtime/Edge/external servis config restore açık. Test ortamında autoconfirm yalnız sentetik admin testine hizmet eder; production Auth ayarı değiştirilmedi. JWT logout erişim token'ını anında kriptografik olarak geçersiz kılmış sayılmaz; hassas mutation için session denetimi P01/P02'de ayrıca gerekir.

Kaynaklar: [GoTrue v2.195.0 konfigurasyonu](https://github.com/supabase/auth/blob/v2.195.0/README.md), [self-hosting](https://supabase.com/docs/guides/self-hosting/docker), [API_EXTERNAL_URL değişikliği](https://supabase.com/changelog/47093-self-hosted-supabase-api-external-url-to-include-auth-v1). Prova URL'si güncel `/auth/v1` issuer/base yaklaşımını kullanır; doğrudan GoTrue HTTP yollarıyla test edilir, gateway/callback testi değildir.
