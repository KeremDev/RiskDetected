# KKD Zimmetleri — istemci sınırı (P10 dilimi)

15 Eylül 2026. P10 çekirdeği zimmeti, iadeyi ve önemli olan iki kuralı kurmuştu: **hiçbir şey verilmeden önce geri gelmez** ve **verilenden fazlası geri gelmez**. Üç şey eksikti — ikisi yalnızca erişilemezlik değil:

1. **İstemci sınırı yoktu ve sahiplik kontrolü de yoktu.** `record_ppe_handover` personelin firmaya ait olduğunu kanıtlıyor, firmanın çağırana ait olduğunu değil; `record_ppe_return` bir zimmet kimliği alıp **tamamen ona güveniyordu**.
2. **Yanlış girilen iade geri alınamıyordu.** Kazara girilen bir iade, kişinin hâlâ neyi taşıdığını **kalıcı olarak** yanlış gösterirdi.
3. **`signed_copy` saklanmış bir dosya istiyor**, istemcinin dosyaya giden yolu yok — yani bayrak ancak reddedilebilirdi. Uzmanın elinde olan şeyse bir klasördeki imzalı form ve **nerede olduğunu yazacak yer yoktu**.

Yeni migration `20260915170000_isg_ppe_handovers.sql`. **Kendi rollout satırını eklemiyor, hiçbir anahtarı açmıyor**; `modules` + `ppe` anahtarlarına biniyor.

## Yapısal olarak imkânsız kılınan beş şey

1. **Başka sahibin zimmetine veya personeline ulaşılamaz**, ve iade çağıranın firması dışındaki bir zimmete işlenemez.
2. **Verilenden fazlası geri gelmez, hiçbir şey verilmeden önce geri gelmez.** İki kural çekirdekte kalıyor; sınır oraya ancak kimin sorduğunu kanıtladıktan sonra ulaşıyor.
3. **Ürün imzalı form tuttuğunu asla iddia etmez.** `signed_copy` hiçbir allowlist'te yok, dolayısıyla yalnız `false` olabiliyor ve **her okuma dosyanın burada saklanmadığını söylüyor**. Saklanan şey uzmanın aslının nerede olduğuna dair kendi notu.
4. **Kişinin hâlâ neyi taşıdığı okuma anında iadelerden sayılıyor**, saklanmıyor. Yanlış iadeyi geri almak bunu **anında** düzeltiyor — elle düzeltilecek bir alan yok.
5. **Yarın tarihli zimmet ve iade reddediliyor**: olmamış bir günde hiçbir şey verilmedi.

## Sunucu yüzeyi

- `ALTER TABLE ppe_handovers ADD COLUMN signed_copy_location text` — tracker referans tutar, dosya değil; evrak takibindeki ile aynı.
- `private_isg.ppe_receipts` — tek yeni tablo, RLS açık, sıfır grant.
- `ppe_handover_status(handed, returned)` — **üç durum, her biri kendi sayacı**. Burada grup katmanı yok, çünkü gruplanacak bir şey olmazdı.
- `require_ppe_company(...)` — çekirdeğin hiç yapmadığı sahiplik kontrolü.
- `remove_ppe_return(...)` — eksik olan düzeltme yolu.
- `ppe_handover_row(...)`, `read_ppe_handovers(...)` (`catalog`/`list`/`detail`), `mutate_ppe_handovers(...)` (üç işlem).
- Public: `isg_ppe_read_v1`, `isg_ppe_mutate_v1` — ikisi de **SECURITY INVOKER**.

## İstemci yüzeyi

Sol menüde **KKD Zimmetleri**. Üç sayaç (Zimmette / Kısmen iade / Kapandı), filtreler **yan yana**, liste **altta**.

- Satır: ekipman, kişi/firma, durum rozeti ve **gerekçesi** ("6 çift hâlâ zimmette"), zimmet miktarı/tarih/belge no; kayıp varsa ve personel arşivlenmişse ayrı etiketler.
- Detay popup'ı: zimmet / iade edilen / hâlâ zimmette / tarih olguları, imzalı formun yeri, iade geçmişi ve her iadenin yanında **"Bu iadeyi geri al"**.
- Zimmet formu: personel seçimi, ekipman adı (**hazır liste yok, öyle yazıyor**), miktar + birim, tarih, belge no, imzalı formun yeri.
- İade formu: **önce hâlâ zimmette olanı yazıyor**, sonra miktar, tarih, durum (kullanılabilir/yıpranmış/hasarlı/kayıp) ve not.

## Doğrulama

- Disposable PostgreSQL 17: fixture + P10 çekirdeği + bu dilim + `scripts/isg/ppe_handovers_check.sql`. **39 kontrol PASS.**
  - İki anahtarın farklı hata verdiği.
  - Başka sahibin firmasının ve başka firmanın personelinin reddedildiği.
  - **İmzalı kopya bayrağının istemciden set edilemediği**; katalogun dosya saklanmadığını ve hazır liste sunulmadığını söylediği.
  - Yarın tarihli zimmetin reddedildiği.
  - Hiç iade yokken tamamının zimmette göründüğü; `signed_copy` satırda false kalırken **formun yerinin kaydedildiği**.
  - Zimmetten önceki iadenin, fazla iadenin ve yarın tarihli iadenin reddedildiği.
  - Kısmi iadenin durumu `partial` yaptığı ve altının kaldığı; **ikinci iadenin toplamı aşamadığı**; tamamının kapattığı; kaybın ayrıca raporlandığı.
  - **Yanlış iadeyi geri almanın zimmeti yeniden açtığı** ve kalanın yamalanmadan yeniden sayıldığı; başka zimmetin iadesinin silinemediği.
  - Aynı belge numarasının tek zimmet olduğu.
  - Başka firmanın zimmetine iade işlenemediği.
  - Sayacın listeyle çelişemediği; **zimmet başına tek satır, iade başına değil**.
  - Replay ve `IDEMPOTENCY_CONFLICT`; sıfır tablo grant'i; tam iki wrapper.
- `ppe_handovers_guard.test.mjs` 13/13, `nova_ppe_handovers.test.mjs` 13/13.
- `run_suite.mjs nova-design` 146/144, `foundation` 623/622 — hatalar eşzamanlı oturumun analiz/eğitim dosyalarına ait.
- iOS Debug derlemesi **SUCCEEDED**. 71 yeni katalog anahtarı tr + en; mevcut hiçbir anahtar değişmedi veya kaybolmadı (2041 → 2112).

## Açık kalanlar

- **Sentetik harness aşaması yazılmadı**; disposable PostgreSQL kontrolleriyle doğrulandı.
- **İmzalı form dosyası eklenemiyor** — istemcinin `file_assets` yolu yok; bu yüzden `signed_copy` her zaman false ve yalnız yeri not ediliyor.
- Zimmet düzeltilemiyor: yanlış girilen miktar/tarih için bir düzeltme yolu yok, yalnız iade geri alınabiliyor.
- Ekipman için tür/kod kataloğu yok — ürün liste göndermiyor, ad serbest metin.
- KKD yenileme/ömür takibi yok; zimmet bir süre taşımıyor.
- Rollout ve modül anahtarı **açılmadı**; canlı pilot bundle'ı ayrı adım.
- Android'de karşılığı yok.
