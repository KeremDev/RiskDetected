# Faz 4 Live Canary Sonuçları

Bu dizin yalnız metadata-only canlı canary sonuçları içindir. Prompt, model
yanıtı, fotoğraf/base64, kullanıcı metni, şirket adı veya gerçek kullanıcı
içeriği burada saklanamaz.

## Çalıştırma sırası

Native review alanları gerçek reviewer tarafından tamamlandıktan ve güvenli
yerel ortamda Gemini secret sağlandıktan sonra:

```sh
make localization-ai-canary-keychain-preflight

./scripts/run_ai_localization_canary_from_keychain.sh \
  --live --matrix=smoke --write-result

./scripts/verify_ai_localization_canary_result.mjs \
  docs/localization/phase-4/canary/results/smoke-result.json \
  --matrix=smoke

./scripts/run_ai_localization_canary_from_keychain.sh \
  --live --matrix=full --write-result

./scripts/verify_ai_localization_canary_result.mjs \
  docs/localization/phase-4/canary/results/full-result.json \
  --matrix=full
```

Bağlı Supabase projesinde `GEMINI_API_KEY` bulunması, secret değerinin yerel
process'e okunabildiği anlamına gelmez. Edge Function secret listesi yalnız
secret adı ve tek yönlü digest döndürür. Anahtar değeri hiçbir belgeye veya
shell çıktısına yazılmamalıdır; Keychain/secret manager üzerinden doğrudan
process ortamına enjekte edilmelidir. Bu repository için kullanılan Keychain
servisi `riskdetected_gemini_api_key_canary`, güvenli wrapper ise
`scripts/run_ai_localization_canary_from_keychain.sh` dosyasıdır.

## Kabul sözleşmesi

- Smoke: tam ve benzersiz 12/12 profil-scenario çifti.
- Full: tam ve benzersiz 84/84 profil-scenario çifti.
- Her çift `passed`; semantic code boş.
- Aynı profile snapshot, prompt contract ve manifest SHA-256 korunur.
- İlk provider cevabı için en fazla üç transient retry, bundan bağımsız en
  fazla bir validator repair yapılır; fiziksel istek sayısı çift başına
  1–5 arasındadır.
- Exact source-photo coverage guard aktiftir.
- Forbidden content alanı bulunmaz.
- Sonuç üretildikten sonra corpus/review manifesti değiştirilirse hash
  doğrulaması fail closed olur ve canary yeniden çalıştırılır.

Varsayılan kapıda başarısız veya eksik sonuç Faz 4 kapanış kanıtı değildir.
Başarısız denemeler ayrı, tarihli dosyada korunur; başarılı kanıtın üzerine
yazılmaz. Provider HTTP statüsü ve final validator ayrıntısı yalnız metadata
olarak tutulur. İstek pacing'i gerekirse
`RISKDETECTED_CANARY_INTER_PAIR_DELAY_MS` ile artırılabilir.
429/5xx geçici provider hatasında ilk cevap için aynı provider/model/key
üzerinde en fazla üç retry yapılır. Bu transient süreklilik bütçesi, tek
validator repair bütçesinden ayrıdır. Repair isteği transient retry yapmaz.
`--write-result` yalnız bu dizine yazar; başarılı smoke/full kanıtının üzerine
yazmaz, başarısız koşuyu zaman damgalı ayrı dosyada korur.

## 2026-07-30 Faz 4 kapanış istisnası

Gemini API tüketimini durdurmak için proje sahibi Kerem, ek canlı çağrı
yapılmadan Faz 4'ün kapatılmasını açıkça istedi. Bu nedenle:

- `smoke-result.json` bağımsız doğrulanmış **12/12** kanonik smoke kanıtıdır.
- Son full kanıtı
  `full-attempt-failed-2026-07-30T20-16-50.181Z.json` içinde **81/84** olarak
  korunur.
- Kanonik `full-result.json` üretilmemiştir.
- Üç residual çift geçmiş sayılmamış, Faz 5/rollout risk kaydına taşınmıştır.
- Faz 4 durumu `completed_with_operator_waiver` olarak kapatılmıştır.
- Bu istisna yalnız bu kapanışa aittir; gelecekteki prompt/model/profile
  sürüm değişikliklerinin normal doğrulama politikasını otomatik olarak
  gevşetmez.
