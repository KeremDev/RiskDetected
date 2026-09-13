# P05/P18 — Hesap kapsamlı native firma listesi

13 Eylül 2026. Önceki servis iptal düzeltmesi `21e01264` üzerine eklenen sunum/veri bağlantısı dilimi. **Ana uygulama kökü henüz yeni ekrana geçirilmedi; P05 ve P18 tamamlanmadı.**

## Bağlantı ve sahiplik

```text
Mevcut CompanyService / CompanyRepository.listCompanies(includeArchived)
  → gerçek Company modelini NovaOwnedCompany'ye eşleyen adaptör
  → owner + host epoch + request ID + arşiv kapsamı kontrolü
  → NovaCompanyDestination yaşam döngüsü
  → NovaCompaniesScreen: gri tuval, beyaz yuvarlak arama ve firma kartları
```

Servis adaptörleri ana uygulamada derlenir; root bağlantısı hazırlanırken loader olarak enjekte edilecektir. Sunum katmanında SDK, endpoint, singleton veya credential yoktur. Ayrı iOS QA uygulaması ve Android Compose testleri sentetik loader kullanır; müşteri verisi okumaz. Bu testler gerçek Supabase RLS/paid/capability veya Auth root entegrasyonu kanıtı değildir.

- Swift `NovaCompanyListState` değer durumu, Kotlin eşdeğer immutable durum ve aynı 34 JSON senaryosu kullanılır.
- İstek yalnız hazır host ve açık `companies` hedefi için başlayabilir. Sonucu yayımlarken await öncesinin değil **güncel** host'un sahibi/epoch'u kontrol edilir.
- Yeni istek eski listeyi temizler. Aynı oturumdaki refresh yarışı request ID ile ayrılır. Eski başarı, hata, iptal ve eski kart tıklaması yeni isteğe etki edemez.
- A→B→A, aynı kullanıcı/yeni oturum, availability yenileme veya iptal durumunda eski kapsamın verisi okunamaz. Saf reducer eski snapshot'ı bir sonraki begin'e kadar bellekte tutabilir; bu anında bellek silme iddiası değildir.
- Arşiv filtresi değiştiğinde yeni lifecycle görevi başlamadan da eski listenin görüntülenmesi ve seçimi engellenir. Varsayılan aktif liste; açıkça istenirse arşiv dahil.
- Farklı owner içeren, yinelenen UUID'li veya boş isimli cevap **tamamen** reddedilir; kısmi yabancı satır gösterilmez.
- iOS `.task(id:)`, Android `LaunchedEffect` ve await sonrası iptal kontrolü kullanılır. Loader iptali dinlemese de gecikmiş cevap yayımlanmaz.
- Host epoch değişimi arama metnini/fokusunu da sıfırlar (`.id(epoch)` / `key(epoch)`). Arama mevcut liste üzerinde yereldir; yeni uzaktan arama endpoint'i eklenmedi.
- Hata metni sabit ve güvenlidir; SDK hata gövdesi kullanıcıya taşınmaz. Retry yeni request ID üretir.

## Gerçek model eşlemesi

`id`, `user_id`, `name`, `is_archived` mevcut Company'den gelir. Detay, boşluğu temizlenmiş adres + gerçek tehlike sınıfı başlığıdır. `department` sektör kabul edilmez; OSGB uzman atama modeli ve sahte sektör üretilmez. Android eski unknown→medium fallback'ini bu adaptörde kullanmaz; bilinmeyen hazard veya canonical olmayan UUID güvenli hata olur. Swift modelinde UUID ve hazard zaten typed decode edilir.

Bağlı owned liste `N firma` / `Henüz firma eklenmedi.` kullanır. Eski referans fixture'ının `atanmış firma` varsayılanı geriye dönük korunur; yeni owner listesinde kullanılmaz. Logo indirme, firma yazma/arşivleme, personel/işyeri ve rapor alanları bu dilimin parçası değildir.

## Doğrulama

| Kontrol | Sonuç / sınır |
|---|---|
| Swift ortak corpus | 34/34, gerçek state kaynakları |
| Android tasarım modülü | 348/348; 34 ortak + 5 yeni lifecycle/Compose testi dahil |
| Android profil modülü | 6/6; 3 gerçek Company projection testi dahil |
| Android veri modülü | 489/489; mevcut SDK loopback kontrolleri dahil |
| Android lint / Debug APK | PASS; profil ve APK görevleri son turda up-to-date olabilir |
| iOS hostlu tam UI | 14/14; son arşiv read-scope ve search-reset sıkılaştırmasından önceki tam tur |
| iOS son kaynak hedefli UI | Yeni 3/3 tekrar; gerçek arama metniyle A→B reseti dahil |
| iOS ana uygulama | Son kaynak Debug/no-signing build PASS, 8,6 saniye |
| Node | foundation 111/111, password-auth 7/7, nova-design 24/24 |
| Kaynak kapıları | identity, transport function-map, YAML parse, Android secret/PII scan, diff whitespace PASS |

Android son test düzeltmesi, arama alanı ve kartta aynı `Firma A` metninin iki semantics düğümüne eşleşmesiydi; benzersiz kart tag'i ve gerçek EditableText değeriyle assertion düzeltildi. Ürün davranışı bu nedenle değiştirilmedi. `createComposeRule` deprecated uyarısı mevcut test altyapısıyla uyumluluk için bırakıldı; test framework/SDK yükseltilmedi.

Görsel kontrol: `output/isg/owned-company-ui-20260913/CC4FE61E-A188-445D-BA75-893D9A41A2EB.png` üzerinde sürekli gri zemin ve beyaz kartlar incelendi. Firma A ve sarı QA araç çubuğu sentetiktir; üretim ekranı/kullanıcı kaydı değildir. Android bu turda Robolectric JVM'de doğrulandı; cihaz üstü veya live E2E sayılmaz.

## Açık entegrasyon işi

1. Mevcut Auth durumunu ve sunucu erişim sonucunu gerçek `NovaSessionHost` composition root'una bağla; profil tier'ından yeni hak üretme.
2. Yalnız gerçek işlevi tamamlanmış hedefleri aç. Firma seçimi henüz tamamlanmamış işyeri/personel modülünü sentetik ekranla başarılı gösteremez.
3. SDK→adaptör→ekran zincirinin tam izole runtime testi, iOS gerçek CompanyService cancellation testi ve yerinde güncelleme/gerçek cihaz kanıtı açık.
4. P05 işyeri/personel/görevlendirme domain sözleşmeleri, mutation/audit/outbox, RLS ve iki native düzenleme akışı ayrıca yapılacak.

Canlı DB/Auth/SMTP, paid politika, müşteriler, mağaza ayarları ve bundle/package/callback/entitlement değişmedi. Push/deploy yapılmadı. Ayrıntılı yerel kanıt: [manifest](evidence/P05_NATIVE_COMPANY_LOADER_2026-09-13.json).
