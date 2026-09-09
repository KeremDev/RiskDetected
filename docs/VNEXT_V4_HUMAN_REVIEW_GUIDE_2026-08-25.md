# V4 Claim İnsan Değerlendirme Rehberi

Her claim tek olay yolu üzerinden ve provider metninden bağımsız değerlendirilir.

## Etiketler

- `observed_finding`: Yerel fiziksel kusur/tehlike ve erişilebilir olay yolu
  görüntüde doğrulanır.
- `assurance_requirement`: Varlık görünür; karar belge, ölçüm, test, iç bütünlük
  veya prosedür gerektirir.
- `verification_request`: Kritik geometri kısmen görünür fakat örtülülük sonucu
  kesin kararı engeller.
- `positive_control`: İlgili olay yolunu kesen kontrol görünürdür.
- `not_assessable`: Görüntü konuya uygun değildir.
- `hard_reject`: Olumlu görsel kanıt yoktur, kanıt çelişkilidir veya iddia
  uydurma kimlik/ölçüm/standarda dayanır.

## Kanıt seviyesi

- E0: Olumlu görsel işaret yok.
- E1: Belirsiz veya güçlü karşıt işaret var.
- E2: Kritik konu var, örtülülük yüksek.
- E3: Yerel işaret var; çözünürlük/örtülülük kesin kararı sınırlar.
- E4: Yerel kusur ve olay yolu güçlü.
- E5: Kusur, yer, mekanizma ve olay yolu açık.

## Zorunlu review alanları

`analysis_human_reviews` için reviewer şu alanları doldurur:

- gold class
- gold evidence level
- criticality
- false-positive / false-negative
- standard applicability correctness
- control–evidence consistency
- duplicate-group anahtarı
- kısa reviewer notu

Üretim fotoğrafları yalnız hak sahibi hesap veya açık izin varsa eğitim verisine
dönüştürülebilir. Replay ve pilot telemetrisi otomatik olarak eğitim verisi
sayılmaz.
