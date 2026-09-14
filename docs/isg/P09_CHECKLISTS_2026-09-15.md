# Kontrol Listeleri — istemci sınırı (P09 ikinci dilim)

15 Eylül 2026. P09'un ilk dilimi uygunsuzluk durum makinesini, kontrol kaydını, sabitlenen şablon sürümünü ve olumsuz yanıtın açıkça uygunsuzluğa çevrilmesini kurmuştu. Bu dilimde **iki boşluk** vardı — biri yalnızca erişilemezlik değil, gerçek bir eksiklik:

1. **Şablon yazma yolu hiç yoktu.** `publish_checklist_version` yayımlanacak bir taslak istiyordu ama taslak oluşturan hiçbir fonksiyon yoktu ve hiçbir şablon seed edilmemişti. Modül tek bir kontrol bile başlatamıyordu.
2. **`checklist_templates` sahipsizdi.** Uzmanın kendi listesi, her hesabın okuduğu bir tabloya düşerdi; üstelik iki uzman aynı kodu kullanamazdı.

Yeni migration `20260915110000_isg_checklist_runs.sql`. **Kendi rollout satırını eklemiyor ve hiçbir anahtarı açmıyor**; ilk dilimin kurduğu `nonconformity` anahtarına biniyor.

## Ürün hazır liste göndermiyor

Kutudan çıkan bir soru listesi, "mevzuatın sorduğu şeyler bunlar" gibi okunur ve böyle onaylanmış bir katalog yok. Bu yüzden **hiçbir şablon seed edilmedi** ve bu dilimdeki hiçbir fonksiyon ürün şablonu oluşturamaz. Ekran bunu boş kalarak değil, yazarak söylüyor:

> Ürün hazır kontrol listesi göndermez. Onaylanmış bir soru kataloğu yok; listeyi siz yazarsınız.

`owner_id` kolonu NULL'a açık bırakıldı — ileride onaylanmış bir katalog gelirse yeri hazır olsun diye, bugün gönderilen bir şey için değil.

## Yapısal olarak imkânsız kılınan beş şey

1. **Başka hesabın şablonuna veya kaydına ulaşılamaz**, ve bir uzmanın seçtiği ad başkasınınkiyle çakışamaz: saklanan kod sahipten türetiliyor (`'c'||md5(owner||':'||başlık)`), uzmanın yazdığı şey ise başlık. Ürün şablonu okunabilir ama **düzenlenemez**.
2. **Olumsuz yanıt kendiliğinden uygunsuzluk kaydı açmaz.** Kayıt açmak payload'da ayrı bir alan, çekirdek fonksiyon bunu açıkça istiyor, varsayılanı `false` ve **her okuma `auto_nonconformity: false` döndürüyor**. Ekranda kutu işaretsiz geliyor ve yanında gerekçesi yazıyor.
3. **Yayımlanmış sürüm düzenlenemez.** Listeyi değiştirmek yeni bir sürüm demek; kayıt doldurulduğu sürümü sabitliyor, bu yüzden sonradan yayımlamak yanıtlanmış bir kaydı yeniden yazamıyor.
4. **Yanıtsız soru varken kontrol tamamlanamaz**, ve tamamlandıktan sonra hiçbir yanıt değişemez.
5. **"Uygulanamaz"** yalnızca listenin izin verdiği soruda kabul ediliyor; ekran da diğerlerinde seçeneği hiç göstermiyor.

Ayrıca: **onaylayanı istemci seçemez.** `approver` allowlist'te yok; sınır oturum açmış uzmanı geçiriyor ve okuma `approval_is_self_declared: true` diyor — yayımlamak uzmanın kendi onayıdır, mevzuat onayı değil.

## Sunucu yüzeyi

- `ALTER TABLE checklist_templates ADD COLUMN owner_id, is_archived`.
- `private_isg.checklist_receipts` — tek yeni tablo, RLS açık, sıfır grant.
- `checklist_template_code(owner,title)`, `draft_checklist_template(...)`, `set_checklist_item(...)`, `remove_checklist_item(...)`, `cancel_checklist_run(...)` — eksik olan yazma yolu.
- `require_checklist_company(...)`, `require_checklist_template(...)` — çekirdek fonksiyonların hiç yapmadığı sahiplik kontrolü.
- `checklist_run_row(...)` — sayımlar okuma anında sayılıyor, saklanmıyor.
- `read_checklists(...)` — `catalog` / `templates` / `list` / `detail`.
- `mutate_checklists(...)` — sekiz işlem.
- Public: `isg_checklists_read_v1`, `isg_checklists_mutate_v1` — ikisi de **SECURITY INVOKER**.

## İstemci yüzeyi

Sol menüde **Kontrol Listeleri**. Üç sayaç (Sürüyor / Tamamlandı / İptal edildi), firma ve durum filtreleri **yan yana**, liste **altta** açılıyor.

- **Listelerim** popup'ı: liste adı yaz → taslak; soru ekle/sil; "Uygulanamaz'a izin ver" kutusu; yayımlama notu zorunlu; yayımla. Yayımlanmış sürüm salt okunur gösteriliyor, yanında onayın kime ait olduğu yazıyor.
- **Kontrol başlat**: yayımlanmış liste + işyeri. Liste yoksa ekran ne yapılacağını söylüyor.
- **Kontrol popup'ı**: sabitlenen sürüm en üstte bir olgu olarak; sorular sırayla, her biri yanıt rozetiyle; yanıtsız soru sayısı ve tamamla butonunun neden kapalı olduğu yazılı.
- **Yanıt popup'ı**: üç seçenek (liste izin veriyorsa), not, ve yalnız "Uygun değil" seçilince **işaretsiz** gelen "Bu madde için uygunsuzluk kaydı aç" kutusu + önem + termin.

## Doğrulama

- Disposable PostgreSQL 17: fixture + P09 çekirdeği + bu dilim + `scripts/isg/checklist_runs_check.sql`. **49 kontrol PASS.**
  - Anahtarın kapalı olduğu; yalnız okumaya açıkken yazmanın reddedildiği.
  - Hiçbir şablonun seed edilmediği ve `product_templates_offered: false`.
  - Başka sahibin firmasının reddedildiği.
  - Şablonun uzmana ait olduğu; ikinci çağrının açık taslağı döndürdüğü ve ikinci sürüm yazmadığı.
  - **Aynı başlığın iki hesapta iki kod** ürettiği; her hesabın yalnız kendi listelerini gördüğü; başkasının listesini düzenleyemediği.
  - Boş listenin ve notsuz yayımın reddedildiği; onaylayan adının reddedildiği; onaylayanın oturum açmış uzman olduğu.
  - Yayımlanmış sorunun ne değiştirilebildiği ne silinebildiği.
  - **Kaydın sürümü sabitlediği**: ikinci sürüm yayımlandıktan sonra bile kaydın hâlâ 2 soru sorduğu; eski sürümün silinmeyip `superseded` olduğu; yeni taslağın yayımlanandan başladığı.
  - "Uygulanamaz"ın izin verilmeyen soruda reddedildiği.
  - **Olumsuz yanıtın tek başına hiçbir kayıt açmadığı**; istendiğinde tam bir tane açtığı; aynı soruyu tekrar yanıtlamanın aynı kaydı kullandığı.
  - Yanıtsız soruyla tamamlamanın `RUN_INCOMPLETE` aldığı; tamamlandıktan sonra yanıtın da iptalin de reddedildiği.
  - Açık kaydın iptal edilebildiği ve ikinci iptalin aynı cevap olduğu.
  - Sayacın saydığı listeyle çelişemediği; replay ve `IDEMPOTENCY_CONFLICT`.
  - Sıfır tablo grant'i; tam iki wrapper.
- `checklist_runs_guard.test.mjs` 13/13, `nova_checklists.test.mjs` 13/13.
- `run_suite.mjs nova-design` 108/106, `foundation` 583/582 — hatalar eşzamanlı oturumun analiz/eğitim dosyalarına ait.
- iOS Debug derlemesi **SUCCEEDED**. 76 yeni katalog anahtarı tr + en; mevcut hiçbir anahtar değişmedi veya kaybolmadı (1823 → 1899).

## Açık kalanlar

- **Sentetik harness aşaması yazılmadı**; disposable PostgreSQL kontrolleriyle doğrulandı.
- **Kanıt dosyası eklenemiyor.** Çekirdek `record_run_item` bir asset alıyor ama sınır her zaman NULL geçiyor: `file_assets`'e giden istemci yolu bu pilotta yok. Ölü yüzey bırakmamak için anahtar allowlist'e de konmadı.
- Açılan uygunsuzluk kaydına **modül içinden gidilemiyor**; Bulgular ekranı ayrı.
- Şablon arşivleme (`is_archived`) kolon olarak var, işlem olarak yok.
- Rollout **açılmadı**; canlı pilot bundle'ı ayrı bir adım.
- Android'de karşılığı yok.
