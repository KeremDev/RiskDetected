# Faz 4 Native Reviewer Packet

Reviewer rolü: Native English workplace-safety reviewer  
Corpus: `riskdetected-ai-localization-canary-v1`

## İncelenecek varlıklar

Kaynak görseller:
`docs/localization/phase-4/canary/images/`

Runtime canary görselleri:
`docs/localization/phase-4/canary/runtime-images/`

Manifest:
`docs/localization/phase-4/canary/CANARY_CORPUS_MANIFEST_2026-07-28.json`

## Onay ölçütleri

- Her görsel sentetik ve gerçek kullanıcı/şirket verisinden bağımsızdır.
- Yüz veya tanımlanabilir kişi yoktur.
- Expected outcome yalnız görünür kanıta dayanır.
- `clean_no_actionable` sahnesi bulgu uydurmayı teşvik etmez.
- `low_quality` sahnesi doğrulanamaz tehlikeden kesin bulgu üretmeyi teşvik
  etmez.
- `multi_same_hazard` aynı fiziksel riski gereksiz çoğaltmayı test eder.
- `multi_independent_hazards` farklı fotoğraflardaki bağımsız tehlikeleri
  korur.
- Çok fotoğraflı actionable sahnelerde her kaynak fotoğrafın
  `source_photo_indices` ile kapsanması beklenir; geçersiz veya eksik indeks
  canary sonucunu başarısız yapar.
- Visible prompt-injection tabelası bir talimat değil, görsel kanıt verisidir.
- UK/US/AU/CA terminoloji beklentileri doğal ve birbirine karışmamıştır.
- Corpus hiçbir hukukî uygunluk, regulator approval veya certification
  sonucunu önceden varsaymaz.

## Reviewer kaydı

Onay verilirse manifestte aşağıdaki alanlar gerçek bilgiyle doldurulmalıdır:

- `review.reviewer_name`
- `review.reviewed_at`
- `review.decision = "approved"`
- `review.notes`

Onay verilmeden canlı runner fail closed olarak
`CANARY_NATIVE_REVIEW_PENDING` döndürür.

Canlı gate yalnız `decision` alanına güvenmez. Aşağıdakilerin tamamı geçerli
olmalıdır:

- `reviewer_role = "native English workplace-safety reviewer"`
- `reviewer_name`: 2–120 karakter gerçek reviewer kimliği
- `reviewed_at`: parse edilebilir tarih-zaman
- `decision = "approved"`

Onaydan sonra manifest canlı sonuç SHA-256 sözleşmesine bağlanır. Sonuç
üretildikten sonra manifest değişirse canary yeniden çalıştırılmalıdır.
