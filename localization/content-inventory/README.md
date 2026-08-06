# Content inventory

`app-content.csv`, uygulamadaki mevcut kullanıcıya görünen sabit metin
adaylarının makine tarafından çıkarılmış başlangıç envanteridir. Otomatik
çıkarım insan sınıflandırmasının yerini tutmaz.

Kurallar:

- Yeni ürün metni semantic localization key kullanmalıdır.
- `hardcoded-baseline.json` mevcut borcu geçici olarak dondurur; yeni özellik
  eklerken yenilenmez.
- Borç azaltıldıkça baseline kontrollü biçimde küçültülebilir.
- Otomatik çıkarılan satırlar yalnız `extracted` statüsündedir.
- `safety_reviewed`, `product_approved` ve `shipping` insan onayı gerektirir.
- Her satır semantic key, yüzey, P0/P1/P2 önceliği, kaynak dosya/satır,
  context, placeholder, owner, screenshot id, language review, safety review
  ve product approval alanlarını taşır.
- UI, backend, PDF, XLSX, e-mail, push, plist, legal ve canlı ASC metadata /
  subscription yüzeyleri aynı CSV'de envantere alınır.
- `inventory-summary.json`, P0/P1 sahipsiz yüzey sayısını ve yüzey/owner
  dağılımını deterministik olarak raporlar.

Komutlar:

```text
make localization-inventory
make localization-check
```
