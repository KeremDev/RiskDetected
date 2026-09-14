# Uygunsuzluk panosu, fotoğraf akışı ve analiz detayı — ikinci tur

14 Eylül 2026. Native (migration yok). Sunucu tarafı değişmedi:
[P09 ikinci dilim](P09_NONCONFORMITY_DETAIL_2026-09-14.md), rollout hâlâ kapalı.
Önceki tur: [Fotoğraf analizi akışı](P09_ANALYSIS_FLOW_2026-09-14.md).

Kullanıcı geri bildirimi üzerine dört yüzey yeniden kuruldu.

## 1. Uygunsuzluklar artık bir pano

Eskiden tek firmanın listesiydi; şimdi hesabın okuyabildiği **her firmanın** kayıtları tek yerde.

- Başlık + hemen yanında **Yeni** düğmesi
- Başlık / firma / işyeri araması
- **Firma**, **Durum** ve **Kayıt türü** filtreleri
- **Termini geçen** filtresi, kendi sayısıyla birlikte
- `N / M kayıt` sayacı ve filtreleri tek dokunuşla temizleme
- Her satır: başlık, önem, durum, tür rozeti, firma · işyeri, açılış/termin, geciktiyse kırmızı uyarı, kaynak

Termin karşılaştırması ISO gün metni üzerinden yapılıyor ve bugünün tarihi çağıran katmandan
(İstanbul saati) geliyor; görünüm kendi takvim aritmetiğini yapmıyor.

Pano her firmayı **kendi okuma çağrısıyla** okuyor; bir firma kendi kontrolünden geçemezse listeye
girmiyor, uydurulmuyor.

## 2. Kayıt ekranı

Satıra dokunmak kaydın kendi sayfasını açıyor: künye, detay (düzenlenebilir), **durum geçişleri**,
**düzeltici aksiyonlar**, **uzman doğrulaması**.

Durum geçişleri `nonconformity_state_edges` tablosunun **birebir aynısı**: on altı kenar, hangisinin
gerekçe, hangisinin atanan kişi istediği dahil. `nova_analysis_flow.test.mjs` iki listeyi **iki yönlü**
karşılaştırıyor — sunucunun kabul edeceği bir geçişi gizlemek de, reddedeceğini sunmak da aynı hata.

Ayrıca ekran sunucunun reddedeceği iki şeyi baştan söylüyor:

- Kapatma, kabul edilmiş bir doğrulama olmadan teklif edilmiyor.
- Beş karakterden kısa gerekçe gönderilmiyor (sunucudaki `length(reason) BETWEEN 5 AND 2000`).

## 3. Fotoğraf akışı: önce resim, sonra popup

İlk ekran ana sayfadaki kartın aynısı: fotoğraf alanı ve tek yeşil düğme.

- **Kamera** ve **Galeri** seçenekleri
- En fazla üç fotoğraf, küçük görseller, dokununca büyük hâli popup'ta
- **Analizi başlat** → firma (aramalı, "firmasız devam et" ile) → sektör → odak, hepsi tek merkez popup'ta
- Bekleme ekranı ürünün kendi `AnalyzingView`'ı: bulanık önizleme, tarama animasyonu, adımlar ve **yüzde**

Ana sayfadaki fotoğraf kartı doğrudan resim adımına, "Uygunsuzluk Ekle" ise nasıl başlanacağı
sorusuna gidiyor. Hızlı ekleme sayfası da artık ana ekrana haber veriyor (`onDestination`), yoksa
önceki niyet üstünde kalıyordu.

## 4. Analiz detayı

- Analiz fotoğrafı **başlığın sağında** küçük görsel; dokununca popup'ta büyük hâli. Birden fazlaysa
  sayısı rozetle yazıyor.
- Dört bölüm **ikon menüsü**; seçilen bölümün ikonu ve başlığı **tek çerçevenin içinde**.
- Her bölümün altında ne olduğunu söyleyen bir satır ("3 skorlu bulgu · uygunsuzluğa dönüştürülebilir",
  "%d skorsuz öneri · önem derecesini siz seçersiniz").
- Bulgu kartı: başlık, bant, skor ve açıklamanın **iki satırı**; devamı için **Devamını incele**.
- O popup: tüm alanlar, **Faydalı / Faydasız**, **Bulguyu düzenle**, **Bulguyu sil** (onaylı).
- Analiz hangi sektör ve odaklarla koştuysa etiket olarak üstte yazıyor.

Faydalı/Faydasız aynı düğmeye tekrar basınca geri alınıyor; değiştirilen bir görüş kayıtta kalmıyor.
Düzenleme ve silme yalnız **Risk Analizi** bölümünde: diğer üç bölümün arkasında düzenlenecek bir
bulgu kaydı yok.

## 5. Analizlerim

Her satırda fotoğraf, firma (ya da "Firmasız"), en yüksek bant, bulgu ve fotoğraf sayısı, sektör ve
tarih. Dokununca o analizin detay sayfası.

## 6. Elle girişte fotoğraf — ve neden kaydedilmiyor

Fotoğraf adımı **birinci sıraya** eklendi: kamera, galeri, küçük görsel, büyütme.

Fakat fotoğraf **kayda eklenmiyor** ve ekran bunu açıkça yazıyor. Sebep uydurma değil:
P04 dosya çekirdeği bir dosyayı ancak **temiz tarama sonucu** varken kalıcı hâle getiriyor
(`promote_clean_upload`, `scan.verdict<>'clean'` → `VALIDATION_ERROR`) ve şu an çalışan bir tarayıcı
yok. `evidence_photo` amacı tabloda tanımlı, `requires_scan=true`. Tarayıcı olmadan "fotoğraf
kaydedildi" demek yanlış olurdu.

**Bunu açmak için gereken dilim:** P04'ün ikinci dilimi (gerçek AV/parser sandbox'ı, bucket/storage
policy, signed URL) + uygunsuzluğa kanıt bağlayan bir istemci sınırı. Teknoloji ve maliyet kararı
gerektiriyor; handover'daki 2. maddenin ta kendisi.

## Doğrulama

| Kontrol | Sonuç |
|---|---|
| `run_suite.mjs foundation` | **470 / 470 PASS** |
| `run_suite.mjs nova-design` | **35 / 35 PASS** (3 yeni davranış testi) |
| `migrate_swift_localization_catalogs.mjs --check` | PASS, bekleyen 0 |
| `check_localization_hardcoded.mjs` | 15 (değişmedi) |
| iOS Debug build | SUCCEEDED |
| `NOVA_PILOT_BUILD` simülatör build | SUCCEEDED |

73 yeni dil anahtarı TR/EN eklendi (toplam 1309); hiçbir katalog küçülmedi.

Simülatörde doğrulandı: pano ve filtreler, kayıt ekranı ve durum geçişleri, ikon menülü analiz
detayı, bulgu popup'ı (Faydalı/Faydasız/düzenle/sil), fotoğraflı Analizlerim.

## Açık kalanlar

- **Rollout kapalı.** Pano canlı veri göstermeden önce:
  `UPDATE private_isg.rollout SET read_enabled=true, write_enabled=true WHERE feature='nonconformity';`
- **Elle girişte kanıt fotoğrafı saklanmıyor** (yukarıdaki gerekçe).
- Pano firma başına ayrı çağrı yapıyor; firma sayısı büyürse sunucuya çok-firmalı bir okuma eklenmeli.
- `record_kind` ve termin filtresi istemcide; 200 satırlık sayfa sınırı aşılırsa sunucuya taşınmalı.
- Analiz seçiminde firma seçmek **çalışma alanı seçimini de** değiştiriyor.
- Kayıt ekranındaki düzeltici aksiyonun durumu (planned/done) değiştirilemiyor; sunucuda böyle bir
  action henüz yok.
- `tests/isg/shell-ios` harness'ı hâlâ derlenmiyor (P18 dil taşımasından kalma).
