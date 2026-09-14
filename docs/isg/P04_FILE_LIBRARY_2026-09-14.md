# Diğer Dosyalar — P04 ikinci dilim (dosya arşivi)

14 Eylül 2026. Yeni migration `20260915010000_isg_file_library.sql`.
Rollout **açılmadı**: `file_library` satırı kapalı eklendi.

Sol menüdeki **Diğer Dosyalar** girişi artık gerçek bir sayfaya iniyor, firma
detay sayfasındaki **Dosya Ekle** butonu ve ilgili başlıklar buraya bağlandı.

## 1. Ne yapıldı

P04'ün ilk dilimi (`20260913130000_isg_file_core.sql`) karantina durum
makinesini kurmuş, kendi başlığında da **"no bucket, storage policy, scanner or
client surface"** yazmıştı. Bu dilim tam olarak o dördünü ekliyor:

| Eksik olan | Bu dilimde |
|---|---|
| Bucket | `isg-quarantine` + `isg-documents`, ikisi de private |
| Storage policy | Karantinaya **yalnız INSERT**, arşivden **yalnız SELECT**, ikisi de `auth.uid()` önekiyle |
| Tarayıcı | `isg-file-inspect` Edge Function + `_shared/isg/file-format-inspector.ts` |
| İstemci yüzeyi | `public.isg_file_library_read_v1` / `..._mutate_v1` + NOVA ekranları |

Ayrıca isimlendirme/dosyalama katmanı: `file_library_entries` (başlık, kategori,
not, sürüm) ve kategori→firma başlığı eşlemesi.

## 2. Yapısal olarak imkânsız kılınan dört şey

1. **Açılabilen dosya her zaman promote edilmiş bir asset'tir.** İndirme yolu
   `file_assets` satırından geliyor; o satırı da durum makinesi *promote edilen
   byte'ların taranan byte'larla aynı olduğunu* doğrulamadan üretmiyor. Karantinadaki
   bir dosya için yol taşıyabilecek hiçbir kolon yok.
2. **İstemci karantinayı okuyamaz, değiştiremez, silemez.** O bucket'taki tek
   policy kendi öneki altına INSERT. Taranmış bir nesne sonradan takas edilemez.
3. **Verdikti, dosyayı yükleyen hesap veremez.** Denetim girişi yalnız
   `service_role`'a GRANT'li ve **aktör argümanı almıyor**: sahibi kendisine
   verilen intent satırından okuyor. Yani o GRANT'i tutmak kullanıcı gibi
   davranma yetkisi vermiyor.
4. **Ürün, çalışmayan bir virüs taramasını iddia etmiyor.** Bir dosyayı neyin
   temizlediği `file_scanners` kaydından bakılıyor; kayıtlı olmayan tarayıcı
   *malware saptamıyor* sayılıyor. **Bilinmeyen, evet değildir.**

Probe bunların hepsini gerçekten deniyor: farklı byte'ları promote etmeye
çalışıyor (`HASH_MISMATCH`), istemci eylem listesinde verdikt arıyor
(`VALIDATION_ERROR` / `PAYLOAD_NOT_ALLOWED`), `has_function_privilege` ile
denetim girişinin `authenticated`'a kapalı olduğunu doğruluyor.

## 3. Biçim denetimi — ne olduğu ve ne olmadığı

`isg_format_inspector` **gerçek bir katman**:

- gerçek tür, dosyanın kendi başlığından (uzantı ve MIME kanıt değil)
- boyut ve sha256, intent'e karşı yeniden doğrulanır
- **PDF:** `/Encrypt`, `/EmbeddedFile`, `/JavaScript`, `/JS`, `/Launch`,
  `/RichMedia`, `/XFA`, `/AA` reddedilir
- **DOCX/XLSX:** merkezî dizin yürüyüşü — entry sayısı, sıkıştırma oranı, yol
  traversal, `vbaProject.bin`, macroEnabled content type, `TargetMode="External"`,
  `<!DOCTYPE`/`<!ENTITY`, DDE alanı
- **DOC/XLS:** compound file dizini — `_VBA_PROJECT`, `Macros`,
  `EncryptedPackage`, `ObjectPool`. **Makrosuz DOC/XLS pozitif fixture'dır**,
  "eski format" diye reddedilmez.
- **Görseller:** başlıktan piksel bütçesi (PNG/JPEG/WebP). HEIF/AVIF için
  bütçe **doğrulanmadı** olarak kaydedilir, doğrulanmış gibi gösterilmez.
- **CSV:** satır/uzunluk sınırı; hiçbir formül çalıştırılmaz.

**Antivirüs değildir.** İmza veritabanı ve davranış analizi yok; iyi biçimli bir
belgenin içindeki zararlı yükü göremez. Bu yüzden:

- kendini `assurance='format_inspection'`, `detects_malware=false` olarak
  kaydediyor,
- her satır `malware_scanned: false` dönüyor,
- ekran bunu **açıkça yazıyor** ("bu bir virüs taraması değildir"),
- ve planın §31.6 geniş format yayın kapısı bu dilimle **karşılanmıyor**.

37 birim testi gerçek fixture byte'larıyla (elle kurulmuş zip, compound file,
PNG/JPEG başlıkları) bu davranışı doğruluyor.

## 4. Durum saklanmıyor

Bir kaydın durumu hiçbir yerde saklanmıyor: okuma anında intent'in kendi
durumundan ve temizlenmiş bir asset olup olmadığından hesaplanıyor
(`state_authority: computed_at_read`).

~~~
pending → uploaded → scanning → clean → promoted
              ↘ rejected / scan_failed / expired
~~~

Ekranda dört sayaç var (Dosyada · İşleniyor · Kabul edilmedi · Denetlenemedi) ve
**bir sayaca dokunmak tam olarak o sayacın saydığı satırları** filtreliyor:
aynı kelimeler sunucunun kabul ettiği filtre değerleri.

## 5. İçerik adresli promote ve aynı belgenin iki kez dosyalanması

Nihai yol `assets/{owner}/{sha256}`. Aynı belge ikinci kez dosyalanınca yeni bir
nesne yazılmıyor; kayıt **zaten orada olan asset'e bağlanıyor**
(`duplicate_of_existing_asset: true`). `file_library_entries.asset_id` bilerek
UNIQUE değil: bir nesne üzerinde iki başlık altında iki kayıt olabilir.

## 6. Sunucu sınırı

P05 deseninin aynısı: `public.isg_file_library_read_v1` ve `..._mutate_v1`
INVOKER sarmalayıcıları → `private_isg.read_file_library` /
`private_isg.mutate_file_library` SECURITY DEFINER kontrollü girişleri.
Mutasyon makbuzu `PRIMARY KEY(actor_id, mutation_id)` + `request_hash`, eylem
başına payload allowlist'i.

Üçüncü giriş `public.isg_file_inspection_v1` yalnız `service_role`'a açık.
Entegre prova definer allowlist'i üç yeni isimle güncellendi.

**İki anahtar gerekiyor:** kütüphane `file_core` üzerine biniyor, bu yüzden
`file_library` tek başına açılırsa tek byte bile kabul edilmiyor. Probe bunu
ayrıca kontrol ediyor.

## 7. Worker'da yetki kimde

Edge function **kullanıcının kendi JWT'siyle** kaydın ona ait olduğunu
doğruluyor; service_role yalnız byte'lara erişmek için kullanılıyor ve çağırdığı
giriş aktör argümanı almıyor. Yani service anahtarını tutmak hiçbir zaman
kullanıcı gibi davranmak değil.

Denetim çalıştırılamazsa yükleme gerçekten bulunduğu yerde kalıyor; ekran
"Dosya arşive alınmadı" diyor, temizlenmiş gibi göstermiyor.

## 8. Bağlanan yerler

- Sol menü → **Diğer Dosyalar** (hesabın tamamı, firma seçimiyle daralıyor)
- Firma detay sayfası → **Dosya Ekle** butonu (o firmaya kilitli)
- Firma detay sayfasındaki başlıklar → kategori eşlemesi **sunucudan** geliyor
  (`file_library_categories.section`), istemcide ikinci bir liste yok. Risk,
  Acil Durum, Periyodik Kontroller, İş Kazaları, Kurul, Eğitim, Zimmet, Personel
  ve Diğer Dosyalar başlıkları kendi dosyalarını tek çağrıda okuyor.

Evrak Takibi'nden ayrı bir şey: takip **neyin borçlu olduğunu**, arşiv **hangi
dosyanın gerçekten dosyalandığını** söylüyor. İkisi firma sayfasında yan yana
duruyor.

## 9. Ekran tasarımı

Kullanıcının Evrak Takibi'nde onayladığı düzenin aynısı: önce firma seçimi
(aramalı, yazmadan da listeleyen), ampullü ipucu, seçimden sonra ana sayfadaki
kart biçiminde dört sayaç, arama, durum ve başlık seçicileri, ilk **10** kayıt ve
"Daha fazla göster". Satıra dokunmak kompakt popup açıyor: durum, red gerekçesi
ve denetçinin bulgusu, tür/boyut/saptanan tür/eklenme, not, **Denetim** kartı ve
işlemler (aç, düzenle, listeden kaldır, yüklemeyi iptal et).

Filtreler iki yatay çip şeridi değil, **yan yana iki seçici**: Durum ve Başlık.
Dokununca liste **altta** iki sütunlu, sayıları sağda açılıyor; seçince
kapanıyor. On üç başlık böylece ekrandan taşmadan erişilebilir kalıyor. Aynı
seçici dosya ekleme ve yeniden dosyalama popup'larında da kullanılıyor: dosya
seçilir seçilmez başlık listesi **kendiliğinden açılıyor** ve başlık seçilene
kadar "Yükle ve denetle" pasif kalıyor — başlık kataloğun ilk sırasına
varsayılmıyor, uzmana soruluyor.

Simülatör incelemesinde üç şey düzeltildi: "Denetlenemedi" kelimesi kart içinde
ortadan bölünüyordu (ölçekleniyor), firma satırındaki dört etiket taşıyordu
(**Dosyada N** + **Arşive alınmadı M** oldu), ipucu dört satırdı (iki satır).

## 10. Koşular

| Kapı | Sonuç |
|---|---|
| `run_auth_restore.mjs --synthetic-session` | **ok: true, 1248 kontrol, 0 hata**, 48'i `file_library` (`output/isg/runs/synthetic-auth-J5B1Fe`) |
| `run_suite.mjs foundation` | 534/535 — tek hata eşzamanlı oturumun eğitim metinleri |
| `run_suite.mjs nova-design` | 67/67 |
| `file_format_inspector.test.mjs` | 37/37 |
| `file_library_guard.test.mjs` | 15/15 |
| `nova_file_library.test.mjs` | 15/15 |
| `localization_catalog_tests.mjs` | L10N-001/002/003 PASS; L10N-004 borcu **tamamı eğitim modülünün**, bu dilimden 0 |
| `migrate_swift_localization_catalogs.mjs --check` | PASS, bekleyen 0 |
| iOS Debug + `NOVA_PILOT_BUILD` derlemeleri | SUCCEEDED |

## 11. Açık kalanlar

- **Rollout açılmadı.** Açmak ayrı bir insan kararı ve **iki** anahtar
  gerektiriyor:
  ~~~sql
  UPDATE private_isg.rollout SET read_enabled=true, write_enabled=true
   WHERE feature IN ('file_core','file_library');
  ~~~
- **Edge function canlıda çalıştırılmadı.** Sentetik koşu gerçek Postgres
  üzerinde ama Storage servisi ayağa kaldırılmıyor; probe raporu bunu
  `storage_schema: 'synthetic_stand_in'`, `storage_service_exercised: false`,
  `bytes_uploaded_or_promoted: false` olarak yazıyor. Denetçinin mantığı 37
  birim testiyle doğrulandı; **dağıtılmış fonksiyonun gerçek Storage'a karşı
  koşusu yapılmadı.**
- **Antivirüs yok.** Planın §31.6 geniş format yayın kapısı açık.
- Önizleme türevi (`file_derivatives`) üretilmiyor; dosya aslıyla açılıyor.
- Yapılandırılmış import (XLS/CSV kolon eşleme) bu dilimde yok; CSV bu yüzden
  Diğer Dosyalar'ın kabul listesinde de yok.
- Android'de karşılığı yok.
- Arşiv firma tamamlanma skoruna bağlanmadı.
